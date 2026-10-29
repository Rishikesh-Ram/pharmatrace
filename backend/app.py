"""Starts the server and defines PharmaTrace API endpoints."""
import io
import logging
import os
import re
import time
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
from datetime import datetime, timezone, timedelta
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

from flask import Flask, g, jsonify, request, send_file  # noqa: E402
from flask_cors import CORS  # noqa: E402
from PIL import Image  # noqa: E402

from services import auth, blockchain, ipfs, ocr, vision  # noqa: E402

REQUIRE_OCR_BATCH_MATCH = os.getenv("REQUIRE_OCR_BATCH_MATCH", "false").lower() == "true"

app = Flask(__name__)
CORS(app)
log = logging.getLogger("pharmatrace")


def decide(record_exists: bool, chain_ok: bool, image_ok: bool) -> str:
    """No record -> Unverified. Both pass -> Verified. One passes -> Suspicious. None -> Unverified."""
    if not record_exists:
        return "Unverified"
    if chain_ok and image_ok:
        return "Verified"
    if chain_ok or image_ok:
        return "Suspicious"
    return "Unverified"


def _build_explainable_verdict(
    *,
    record_exists: bool,
    record: dict | None,
    verdict: str,
    chain_ok: bool,
    image_ok: bool,
    score: float | None,
    image_error: str | None,
    ocr_result: dict | None,
) -> dict:
    """Construct an explainable breakdown distinguishing on-chain facts from off-chain analysis."""
    if not record_exists or record is None:
        return {
            "category": "Unregistered",
            "headline": "Unregistered Medicine — No Blockchain Record Found",
            "summary": "No batch or medicine ID matching this query exists on the PharmaTrace smart contract.",
            "on_chain_facts": [
                "Smart contract lookup returned no registered medicine record.",
            ],
            "off_chain_analysis": [],
            "field_mismatches": ["Medicine / Batch ID is not registered on-chain."],
            "reasons": [
                "No manufacturer has registered this medicine ID or batch number on the blockchain.",
                "Do not consume or dispense unregistered medicines.",
            ],
        }

    recalled = bool(record.get("recalled"))
    expired = bool(record.get("expired"))
    stage = int(record.get("stage", 1))
    stage_names = {1: "Manufactured (Stage 1)", 2: "With Distributor (Stage 2)", 3: "At Retail Pharmacy (Stage 3)"}

    on_chain_facts = [
        f"Registered on-chain by manufacturer {record.get('manufacturer')}.",
        f"Current supply-chain custody stage: {stage_names.get(stage, f'Stage {stage}')}.",
        f"Registered Batch Number: {record.get('batch')}.",
        f"Recall status: {'RECALLED (' + (record.get('recall_reason') or 'Active recall') + ')' if recalled else 'Not recalled'}.",
        f"Expiry status on-chain: {'EXPIRED' if expired else 'Valid (not expired)'}.",
    ]

    off_chain_analysis = []
    mismatches = []
    reasons = []

    if score is not None:
        pct = round(score * 100, 1)
        thresh_pct = round(vision.SIMILARITY_THRESHOLD * 100, 1)
        off_chain_analysis.append(
            f"Packaging visual similarity score: {pct}% (threshold: {thresh_pct}%) — {'PASSED' if image_ok else 'BELOW THRESHOLD'}."
        )
        if not image_ok:
            mismatches.append(f"Visual packaging similarity ({pct}%) is below required threshold ({thresh_pct}%).")
    elif image_error:
        off_chain_analysis.append(f"Visual packaging comparison could not be completed: {image_error}")

    if ocr_result:
        found_b = ocr_result.get("found_batch")
        b_status = ocr_result.get("batch_status")
        found_e = ocr_result.get("found_expiry")
        e_status = ocr_result.get("expiry_status")
        exp_e = ocr_result.get("expected_expiry_month")
        b_ev = ocr_result.get("batch_evidence")
        e_ev = ocr_result.get("expiry_evidence")
        qual = ocr_result.get("quality") or {}

        off_chain_analysis.append(
            f"OCR Batch Number: '{found_b or 'Not detected'}' vs Expected '{record.get('batch')}' ({b_status})."
            + (f" {b_ev}" if b_ev else "")
        )
        off_chain_analysis.append(
            f"OCR Expiry Date: '{found_e or 'Not detected'}' vs Expected '{exp_e or 'N/A'}' ({e_status})."
            + (f" {e_ev}" if e_ev else "")
        )
        if qual:
            sharp = qual.get("laplacian_variance", 0.0)
            glare_pct = round(qual.get("glare_fraction", 0.0) * 100, 1)
            off_chain_analysis.append(
                f"Image Quality Assessment: Sharpness {sharp:.1f} ({'sharp' if not qual.get('is_blurry') else 'blurry'}), Glare {glare_pct}% ({'acceptable' if not qual.get('has_glare') else 'high reflection'}), Lighting {qual.get('lighting', 'normal')}."
            )
            for f in qual.get("feedback", []):
                off_chain_analysis.append(f"Quality advisory: {f}")

        if b_status == "mismatch":
            mismatches.append(
                f"Printed batch number '{found_b}' does not match registered batch '{record.get('batch')}'."
            )
        if e_status == "mismatch":
            mismatches.append(
                f"Printed expiry '{found_e}' does not match registered expiry '{exp_e}'."
            )

    if recalled:
        category = "Recalled"
        headline = "Recalled Medicine Batch — Do Not Use"
        reasons.append(f"Batch has been recalled on-chain: {record.get('recall_reason') or 'Safety recall'}.")
    elif expired:
        category = "Expired"
        headline = "Expired Medicine Batch — Do Not Use"
        reasons.append("The on-chain expiry timestamp for this batch has passed.")
    elif image_error and score is None:
        category = "Unable to verify"
        headline = "Unable to Complete Optical Verification"
        reasons.append("On-chain record is valid, but reference image comparison could not be completed.")
    elif verdict == "Unverified":
        category = "Unable to verify"
        headline = "Insufficient Evidence — Unverified"
        reasons.append("Evidence is insufficient or image was unreadable to complete verification.")
    elif verdict == "Verified" and not mismatches:
        category = "Verified"
        headline = "Verified Record & Packaging Evidence Passed"
        reasons.append("On-chain registration is active, not recalled, not expired, and physical packaging matches the IPFS reference.")
    elif verdict == "Verified" and mismatches:
        # Even if visual similarity passed, flag OCR field mismatch as Suspicious explanation
        category = "Suspicious"
        headline = "Suspicious — OCR Text Mismatch Detected"
        reasons.extend(mismatches)
    else:
        category = "Suspicious"
        headline = "Suspicious Packaging Evidence"
        if mismatches:
            reasons.extend(mismatches)
        else:
            reasons.append("Submitted packaging photo differed from the manufacturer's reference packaging on IPFS.")

    return {
        "category": category,
        "headline": headline,
        "summary": " ".join(reasons),
        "on_chain_facts": on_chain_facts,
        "off_chain_analysis": off_chain_analysis,
        "field_mismatches": mismatches,
        "reasons": reasons,
    }


def _resolve_authorized_signer(required_roles: tuple[str, ...], explicit_role: str | None = None, explicit_address: str | None = None):
    """Enforce role and active on-chain status for privileged operations.
    Returns (private_key, role_name, address, error_tuple_or_None).
    """
    auth_header = request.headers.get("Authorization", "")
    session = auth.verify_token(auth_header)

    if auth_header.strip() and not session:
        return None, None, None, (
            jsonify(
                error="Invalid or expired session token.",
                code="UNAUTHORIZED",
            ),
            401,
        )

    if session:
        user_role = session["role"].lower()
        user_addr = session["address"]
        if explicit_role and explicit_role.strip().lower() != user_role:
            return None, None, None, (
                jsonify(
                    error=f"Access denied: Authenticated role '{user_role}' cannot perform operations as '{explicit_role.strip().lower()}'.",
                    code="UNAUTHORIZED_ROLE",
                ),
                403,
            )
        if user_role not in required_roles:
            return None, None, None, (
                jsonify(
                    error=f"Access denied: Role '{user_role}' is not authorized for this operation. Required: {', '.join(required_roles)}.",
                    code="UNAUTHORIZED_ROLE",
                ),
                403,
            )
    else:
        user_role = (explicit_role or required_roles[0]).strip().lower()
        if user_role not in required_roles:
            return None, None, None, (
                jsonify(
                    error=f"Access denied: Role '{user_role}' is not authorized for this operation. Required: {', '.join(required_roles)}.",
                    code="UNAUTHORIZED_ROLE",
                ),
                403,
            )
        if explicit_address:
            user_addr = explicit_address
        else:
            key_tmp = blockchain.get_key_for_role(user_role)
            user_addr = blockchain.w3.eth.account.from_key(key_tmp).address

    # Verify on-chain authorization for admin and supply-chain roles
    if user_role == "admin":
        expected_admin = auth._resolve_admin_address()
        if user_addr.lower() != expected_admin.lower():
            return None, None, None, (
                jsonify(
                    error="Access denied: Wallet does not match the smart-contract Administrator address.",
                    code="UNAUTHORIZED_ADMIN_ADDRESS",
                ),
                403,
            )
    else:
        try:
            chain_u = blockchain.get_user(user_addr)
            expected_role_num = blockchain.ROLE_MAP.get(user_role, 0)
            if chain_u["role"] != expected_role_num:
                return None, None, None, (
                    jsonify(
                        error=f"Wallet {user_addr} is not registered on-chain as {user_role.capitalize()}.",
                        code="ONCHAIN_ROLE_MISMATCH",
                    ),
                    403,
                )
            if chain_u["status"] != 1:
                return None, None, None, (
                    jsonify(
                        error=f"Organization '{chain_u.get('name') or user_addr}' is currently '{chain_u.get('status_name')}' on-chain and cannot perform privileged operations until all required approvals are completed.",
                        code="ORGANIZATION_NOT_ACTIVE",
                        status_name=chain_u.get("status_name"),
                    ),
                    403,
                )
        except Exception as exc:
            return None, None, None, (
                jsonify(error=f"Could not verify on-chain authorization: {exc}"),
                503,
            )

    g.actor = session or {"role": user_role, "username": user_role, "address": user_addr}
    key = auth.get_signing_key_for_address(user_addr, fallback_role=user_role)
    return key, user_role, user_addr, None


# =====================================================================
# AUTHENTICATION ENDPOINTS
# =====================================================================

@app.route("/api/auth/login", methods=["POST"])
def api_login():
    """Authenticate a supply-chain organization or admin account."""
    data = request.get_json(silent=True) or request.form.to_dict()
    identifier = (data.get("identifier") or "").strip()
    username = (data.get("username") or "").strip()
    email = (data.get("email") or "").strip()
    password = data.get("password") or ""
    expected_role = (data.get("role") or data.get("expected_role") or "").strip()

    if expected_role.lower() == "admin":
        if (not identifier and not email and not username) or not password:
            return jsonify(
                error="Username or email and password are required for administrator sign-in.",
                code="MISSING_CREDENTIALS",
            ), 400
    else:
        if not identifier and not username and not email:
            return jsonify(
                error="Username/email and password are required.",
                code="MISSING_CREDENTIALS",
            ), 400
        if not password:
            return jsonify(
                error="Password is required.",
                code="MISSING_CREDENTIALS",
            ), 400

    res, err, status = auth.authenticate_user(
        identifier=identifier or None,
        password=password,
        expected_role=expected_role or None,
        username=username or None,
        email=email or None,
    )
    if err is not None:
        return jsonify(err), status
    return jsonify(res), 200


@app.route("/api/auth/change-password", methods=["POST"])
def api_change_password():
    """Change an account password securely."""
    data = request.get_json(silent=True) or request.form.to_dict()
    current_password = data.get("current_password") or ""
    new_password = data.get("new_password") or ""

    auth_header = request.headers.get("Authorization", "")
    session = auth.verify_token(auth_header)
    ident = session.get("username") if session else (data.get("username") or data.get("identifier") or data.get("email") or "")
    if not ident:
        return jsonify(error="User identification is required.", code="MISSING_CREDENTIALS"), 400

    ok, err = auth.change_password(
        identifier_or_username=ident,
        current_password=current_password,
        new_password=new_password,
    )
    if not ok:
        return jsonify(error=err or "Password change failed.", code="PASSWORD_CHANGE_FAILED"), 400

    return jsonify(success=True, message="Password updated successfully."), 200


@app.route("/api/auth/me", methods=["GET"])
def api_auth_me():
    """Validate current bearer token and return live on-chain organization status."""
    auth_header = request.headers.get("Authorization", "")
    session = auth.verify_token(auth_header)
    if not session:
        return jsonify(error="Invalid or expired session token.", code="UNAUTHORIZED"), 401

    try:
        chain_user = blockchain.get_user(session["address"])
        meta = auth.get_org_metadata(session["address"])
        return jsonify(
            authenticated=True,
            user={**chain_user, **meta, **session},
        )
    except Exception as exc:
        return jsonify(error=str(exc)), 503


@app.route("/api/auth/logout", methods=["POST"])
def api_logout():
    """Revoke current bearer token."""
    auth_header = request.headers.get("Authorization", "")
    auth.revoke_token(auth_header)
    return jsonify(success=True, message="Signed out successfully.")


@app.route("/api/auth/admin-status", methods=["GET"])
def api_admin_status():
    """Check whether the initial administrator account has been provisioned."""
    return jsonify(admin_provisioned=auth.has_admin_account())


@app.route("/api/auth/bootstrap-admin", methods=["POST"])
def api_bootstrap_admin():
    """One-time endpoint to provision the initial administrator when none exists."""
    if auth.has_admin_account():
        return jsonify(
            error="An administrator account has already been provisioned. Public admin creation is disabled.",
            code="ADMIN_ALREADY_PROVISIONED",
        ), 403

    data = request.get_json(silent=True) or request.form.to_dict()
    username = (data.get("username") or "").strip()
    email = (data.get("email") or "").strip()
    password = data.get("password") or ""
    org_name = (data.get("org_name") or "PharmaTrace Regulatory Authority").strip()

    try:
        record = auth.provision_initial_admin(
            username=username,
            email=email,
            password=password,
            org_name=org_name,
        )
        return jsonify(
            success=True,
            admin=record,
            message="Initial Administrator account provisioned successfully.",
        ), 201
    except PermissionError as exc:
        return jsonify(error=str(exc), code="ADMIN_ALREADY_PROVISIONED"), 403
    except ValueError as exc:
        return jsonify(error=str(exc), code="VALIDATION_ERROR"), 400


# =====================================================================
# VERIFICATION & LOOKUP
# =====================================================================

@app.route("/verify", methods=["POST"])
def verify():
    medicine_id = request.form.get("medicine_id", "").strip()
    file = request.files.get("image")
    if not medicine_id or not file:
        return jsonify(error="Send form-data fields 'medicine_id' and 'image'."), 400
    try:
        uploaded = Image.open(io.BytesIO(file.read())).convert("RGB")
    except Exception:
        return jsonify(error="Could not read the uploaded image."), 400

    if not blockchain.is_connected():
        return jsonify(
            error="Blockchain node is unreachable. Cannot verify medicine record.",
            code="BLOCKCHAIN_UNAVAILABLE",
        ), 503

    # (a) blockchain record (by ID or batch number)
    record = blockchain.find_record(medicine_id)
    if record is None:
        explainable = _build_explainable_verdict(
            record_exists=False,
            record=None,
            verdict="Unverified",
            chain_ok=False,
            image_ok=False,
            score=None,
            image_error=None,
            ocr_result=None,
        )
        return jsonify(
            verdict="Unverified",
            reason="No blockchain record found.",
            medicine_id=medicine_id,
            explainable=explainable,
        )

    actual_id = record["raw"].get("id") or record.get("id") or medicine_id

    # OCR: name / batch / expiry from the pack
    ocr_result = ocr.analyse(uploaded, record)
    chain_ok = not record["recalled"] and not record["expired"]
    if chain_ok and REQUIRE_OCR_BATCH_MATCH:
        chain_ok = ocr_result["batch_match"]

    audit = blockchain.read_audit_trail(actual_id)

    record_details = {
        "medicine_id": actual_id,
        "name": record["name"],
        "manufacturer": record["manufacturer"],
        "batch": record["batch"],
        "expiry": record["expiry"],
        "mfg": record.get("mfg", ""),
        "quantity": record.get("quantity", 0),
        "stage": record.get("stage", 1),
        "recalled": record["recalled"],
        "expired": record["expired"],
        "recall_reason": record["recall_reason"],
        "blockchain_ok": chain_ok,
        "ipfs_cid": record.get("ipfs_cid", ""),
        "reference_image_url": f"/api/reference-image/{actual_id}",
    }

    # model check
    score, image_ok, image_error = None, False, None
    try:
        reference = ipfs.fetch_image(record["ipfs_cid"])
        score = vision.similarity(uploaded, reference)
        image_ok = score >= vision.SIMILARITY_THRESHOLD
    except Exception as e:
        image_error = str(e)
        log.warning("Image comparison fallback triggered: %s", e)
        final_verdict = "Suspicious" if chain_ok else "Unverified"
        explainable = _build_explainable_verdict(
            record_exists=True,
            record=record,
            verdict=final_verdict,
            chain_ok=chain_ok,
            image_ok=False,
            score=None,
            image_error=image_error,
            ocr_result=ocr_result,
        )
        return jsonify(
            verdict=final_verdict,
            reason="Image comparison unavailable or reference missing.",
            medicine_id=actual_id,
            details={
                **record_details,
                "image_ok": False,
                "similarity": None,
                "threshold": vision.SIMILARITY_THRESHOLD,
                "image_error": image_error,
            },
            ocr=ocr_result,
            explainable=explainable,
            journey=audit.get("journey", []),
            events=audit.get("events", []),
        )

    # (d) verdict
    # A low-quality, blurry, or unreadable image must not automatically be labelled counterfeit; label Unverified
    quality = ocr_result.get("quality") or {}
    if not quality.get("quality_acceptable", True) and not image_ok:
        final_verdict = "Unverified"
    else:
        final_verdict = decide(True, chain_ok, image_ok)

    # If OCR detected a definite batch mismatch on the printed label, downgrade Verified -> Suspicious
    if final_verdict == "Verified" and ocr_result.get("batch_status") == "mismatch":
        final_verdict = "Suspicious"

    explainable = _build_explainable_verdict(
        record_exists=True,
        record=record,
        verdict=final_verdict,
        chain_ok=chain_ok,
        image_ok=image_ok,
        score=score,
        image_error=image_error,
        ocr_result=ocr_result,
    )

    # Record persisted consumer verification event
    blockchain.record_consumer_verification(
        actual_id,
        verdict=final_verdict,
        details=f"Optical score: {score}, OCR batch: {ocr_result.get('found_batch')} ({ocr_result.get('batch_status')})",
        method="package_verification",
    )
    audit = blockchain.read_audit_trail(actual_id)

    return jsonify(
        verdict=final_verdict,
        medicine_id=actual_id,
        details={
            **record_details,
            "image_ok": image_ok,
            "similarity": None if score is None else round(score, 4),
            "threshold": vision.SIMILARITY_THRESHOLD,
            "image_error": image_error,
        },
        ocr=ocr_result,
        explainable=explainable,
        journey=audit.get("journey", []),
        events=audit.get("events", []),
    )


@app.route("/api/ocr/extract-package", methods=["POST"])
def extract_package():
    """Extract printed medicine fields (name, batch, mfg date, expiry date)
    from an uploaded package image without requiring a prior batch ID.
    """
    file = request.files.get("image")
    if not file:
        return jsonify(error="No image file provided in 'image' field."), 400

    try:
        uploaded = Image.open(io.BytesIO(file.read())).convert("RGB")
    except Exception as exc:
        return jsonify(error="Could not read uploaded image.", details=str(exc)), 400

    try:
        result = ocr.extract_package_fields(uploaded)
        return jsonify(result), 200
    except Exception as exc:
        app.logger.exception("Failed to extract package fields")
        return jsonify(error="OCR field extraction failed.", details=str(exc)), 500


@app.route("/api/consumer/record-verification", methods=["POST"])
def record_consumer_verification_endpoint():
    """Explicitly records a consumer verification event for a medicine batch."""
    data = request.get_json(silent=True) or request.form.to_dict()
    medicine_id = data.get("medicine_id", "").strip()
    verdict = data.get("verdict", "Verified").strip()
    method = data.get("method", "batch_lookup").strip()
    details = data.get("details", "").strip()

    if not medicine_id:
        return jsonify(error="medicine_id is required."), 400

    record = blockchain.find_record(medicine_id)
    if record is None:
        return jsonify(error=f"Medicine '{medicine_id}' not found on blockchain."), 404

    actual_id = record["raw"].get("id") or record.get("id") or medicine_id
    ev = blockchain.record_consumer_verification(
        actual_id,
        verdict=verdict,
        details=details,
        method=method,
    )
    audit = blockchain.read_audit_trail(actual_id)

    return jsonify(
        success=True,
        event=ev,
        journey=audit.get("journey", []),
        message="Consumer verification recorded successfully.",
    )


@app.route("/api/reference-image/<path:medicine_id>", methods=["GET"])
def get_reference_image(medicine_id):
    """Serve the manufacturer's reference packaging image for side-by-side comparison."""
    record = blockchain.find_record(medicine_id)
    if record is None or not record.get("ipfs_cid"):
        return jsonify(error="Reference image not found for this medicine."), 404
    try:
        img = ipfs.fetch_image(record["ipfs_cid"])
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=88)
        buf.seek(0)
        return send_file(buf, mimetype="image/jpeg")
    except Exception as exc:
        return jsonify(error=f"Reference image unavailable: {exc}"), 404


@app.route("/lookup/<path:medicine_id>", methods=["GET"])
def lookup(medicine_id):
    if not blockchain.is_connected():
        return jsonify(error="Blockchain node is unavailable."), 503

    try:
        record = blockchain.find_record(medicine_id)
        if record is None:
            return jsonify(
                found=False,
                medicine_id=medicine_id,
                message="No matching medicine ID or batch number found.",
            ), 404

        actual_id = record["raw"]["id"]
        history = blockchain.read_history(actual_id)
        stages = blockchain.read_stages(actual_id)
        audit = blockchain.read_audit_trail(actual_id)

        return jsonify(
            found=True,
            medicine_id=actual_id,
            name=record["name"],
            batch=record["batch"],
            manufacturer=record["manufacturer"],
            manufacturer_name=audit.get("organizations", {}).get("manufacturer_name", ""),
            expiry=record["expiry"],
            mfg=record.get("mfg", ""),
            expired=record["expired"],
            recalled=record["recalled"],
            recall_reason=record["recall_reason"],
            current_owner=record["raw"].get("currentOwner", ""),
            quantity=record.get("quantity", 0),
            stage=record.get("stage", 1),
            distributor=record.get("distributor", ""),
            distributor_name=audit.get("organizations", {}).get("distributor_name", ""),
            pharmacy=record.get("pharmacy", ""),
            pharmacy_name=audit.get("organizations", {}).get("pharmacy_name", ""),
            ipfs_cid=record.get("ipfs_cid", ""),
            reference_image_url=f"/api/reference-image/{actual_id}",
            history=history,
            stages=stages,
            journey=audit.get("journey", []),
            events=audit.get("events", []),
            recall_event=audit.get("recall_event"),
        )
    except Exception:
        app.logger.exception("Blockchain lookup failed")
        return jsonify(error="Could not read the blockchain record."), 500


@app.route("/health")
def health():
    return jsonify(
        status="ok",
        chain_connected=blockchain.is_connected(),
        model_installed=vision.is_installed(),
    )


# =====================================================================
# MEDICINE REGISTRATION (MANUFACTURER)
# =====================================================================

def _parse_revert_message(exc: Exception) -> str:
    msg = str(exc)
    m = re.search(r"reverted with reason string ['\"]([^'\"]+)['\"]", msg)
    if m:
        reason = m.group(1).strip()
        friendly = {
            "Wrong stage": "Smart contract rejected the transition: the batch is not in the required supply-chain stage.",
            "Not your manufacturer": "Smart contract rejected the transition: this distributor is not registered under the manufacturer of this batch.",
            "Not your distributor": "Smart contract rejected the transition: this pharmacy is not registered under the distributor of this batch.",
            "Medicine has expired": "Smart contract rejected the transition: the medicine has passed its on-chain expiry date.",
            "Medicine is recalled": "Smart contract rejected the transition: this medicine batch has been recalled.",
            "Not approved for this role": "Smart contract access denied: sender is not active or approved for this role on-chain.",
        }
        return friendly.get(reason, f"Blockchain revert: {reason}")
    if "revert" in msg.lower():
        return "Transaction execution reverted by the smart contract."
    return msg


@app.route("/register", methods=["POST"])
def register():
    """Upload medicine package images (up to 10) to IPFS, create package manifest, and register on-chain."""
    signer_key, _, signer_addr, auth_err = _resolve_authorized_signer(("manufacturer",))
    if auth_err is not None:
        return auth_err

    medicine_id = request.form.get("medicine_id", "").strip()
    name = request.form.get("name", "").strip()
    batch = request.form.get("batch", "").strip()
    expiry = request.form.get("expiry", "").strip()
    quantity_str = request.form.get("quantity", "100").strip()

    # Collect up to 10 images from multipart request
    files = []
    if "images" in request.files:
        files = request.files.getlist("images")
    elif "image" in request.files:
        files = [request.files.get("image")]
    else:
        for key in sorted(request.files.keys()):
            if key.startswith("image"):
                files.extend(request.files.getlist(key))

    files = [f for f in files if f and f.filename]

    if not all([medicine_id, name, batch, expiry]) or len(files) == 0:
        return jsonify(
            error="Required fields: medicine_id, name, batch, expiry, and at least one package image."
        ), 400

    if len(files) > 10:
        return jsonify(
            error=f"A maximum of 10 package images can be uploaded per batch (received {len(files)}).",
            code="MAX_IMAGES_EXCEEDED",
        ), 400

    try:
        quantity = int(quantity_str) if quantity_str.isdigit() else 100
    except ValueError:
        quantity = 100

    # Parse expiry supporting MM/YYYY, MM-YYYY, YYYY-MM-DD, YYYY-MM
    expiry_date = None
    for fmt in ("%m/%Y", "%m-%Y", "%Y-%m-%d", "%Y-%m"):
        try:
            dt = datetime.strptime(expiry, fmt)
            if fmt in ("%m/%Y", "%m-%Y", "%Y-%m"):
                import calendar
                _, last_day = calendar.monthrange(dt.year, dt.month)
                expiry_date = dt.replace(day=last_day).date()
            else:
                expiry_date = dt.date()
            break
        except ValueError:
            pass

    if expiry_date is None:
        return jsonify(
            error=f"Invalid expiry date received: {expiry!r}. Use MM/YYYY or YYYY-MM-DD."
        ), 400

    # Parse manufacturing date if provided (supporting past batches like 01/2026)
    mfg = (request.form.get("mfg") or request.form.get("mfg_date") or "").strip()
    mfg_date = None
    if mfg:
        for fmt in ("%m/%Y", "%m-%Y", "%Y-%m-%d", "%Y-%m"):
            try:
                dt = datetime.strptime(mfg, fmt)
                mfg_date = dt.replace(day=1).date()
                break
            except ValueError:
                pass

        if mfg_date and expiry_date <= mfg_date:
            return jsonify(
                error="Expiry date must be later than manufacturing date."
            ), 400

    try:
        expiry_timestamp = int(
            datetime.combine(
                expiry_date + timedelta(days=1),
                datetime.min.time(),
                tzinfo=timezone.utc,
            ).timestamp()
        )

        if expiry_timestamp <= int(datetime.now(timezone.utc).timestamp()):
            return jsonify(
                error="Expiry date must be in the future."
            ), 400

        # Read view labels if provided (e.g. view_0, view_1, or views list)
        raw_views = request.form.getlist("views")
        if not raw_views:
            raw_views = [request.form.get(f"view_{i}", "").strip() for i in range(len(files))]

        # Validate and prepare each image
        allowed_extensions = {".jpg", ".jpeg", ".png", ".webp"}
        image_records = []
        uploaded_cids = []

        for i, file_item in enumerate(files):
            file_bytes = file_item.read()
            if not file_bytes:
                return jsonify(error=f"Image {i + 1} ('{file_item.filename}') is empty."), 400

            if len(file_bytes) > 10 * 1024 * 1024:
                return jsonify(error=f"Image {i + 1} exceeds 10MB size limit."), 400

            ext = os.path.splitext(file_item.filename)[1].lower()
            if ext not in allowed_extensions:
                return jsonify(
                    error=f"Unsupported format '{ext}' for image {i + 1}. Allowed: JPG, PNG, WebP."
                ), 400

            try:
                test_img = Image.open(io.BytesIO(file_bytes))
                test_img.verify()
            except Exception as img_err:
                return jsonify(
                    error=f"Invalid or corrupted image data in file {i + 1} ('{file_item.filename}'): {img_err}"
                ), 400

            # Determine view label
            view_label = raw_views[i] if i < len(raw_views) and raw_views[i] else (
                "Primary Package Photo" if i == 0 else f"Package View {i + 1}"
            )

            # Upload to Pinata / IPFS
            cid = ipfs.upload_image(file_bytes, filename=file_item.filename or f"package_{i + 1}.jpg")
            uploaded_cids.append(cid)
            image_records.append({
                "index": i,
                "cid": cid,
                "filename": file_item.filename,
                "view": view_label,
                "size_bytes": len(file_bytes),
                "url": f"/api/reference-image/{medicine_id}" if i == 0 else f"{ipfs.PINATA_GATEWAY}{cid}",
            })

        primary_image_cid = uploaded_cids[0]

        # Build stable package manifest
        manifest_payload = {
            "batch_id": batch,
            "medicine_id": medicine_id,
            "medicine_name": name,
            "mfg": mfg,
            "expiry": expiry,
            "primary_image_cid": primary_image_cid,
            "total_images": len(image_records),
            "created_at": int(time.time()),
            "manufacturer_address": signer_addr,
            "images": image_records,
        }

        # Save local manifest & pin manifest to IPFS
        ipfs.save_local_manifest(batch, manifest_payload)
        ipfs.save_local_manifest(medicine_id, manifest_payload)
        manifest_cid = None
        try:
            manifest_cid = ipfs.upload_json(manifest_payload, name=f"{batch}_manifest.json")
            manifest_payload["manifest_cid"] = manifest_cid
            ipfs.save_local_manifest(batch, manifest_payload)
            ipfs.save_local_manifest(medicine_id, manifest_payload)
        except Exception as pin_err:
            log.warning("Could not pin manifest JSON to IPFS: %s", pin_err)

        # Register on-chain using primary image CID (100% compatible with existing contract)
        tx_hash = blockchain.register_medicine(
            medicine_id,
            name,
            batch,
            expiry_timestamp,
            primary_image_cid,
            quantity=quantity,
            private_key=signer_key,
        )
        tx_meta = blockchain.get_tx_meta(tx_hash)

        return jsonify(
            success=True,
            medicine_id=medicine_id,
            name=name,
            batch=batch,
            mfg=mfg,
            expiry=expiry,
            quantity=quantity,
            manufacturer=signer_addr,
            image_cid=primary_image_cid,
            manifest_cid=manifest_cid,
            total_images=len(image_records),
            images=image_records,
            transaction_hash=tx_hash,
            block_number=tx_meta.get("block_number"),
            confirmation_status=tx_meta.get("confirmation_status", "Confirmed"),
            message="Medicine registered successfully on the blockchain.",
        ), 201

    except Exception as exc:
        app.logger.exception("Medicine registration failed")
        friendly_err = _parse_revert_message(exc)
        return jsonify(error=f"{type(exc).__name__}: {friendly_err}"), 500


@app.route("/api/batches/<path:batch_id>/images", methods=["GET"])
@app.route("/api/medicine-images/<path:batch_id>", methods=["GET"])
def get_batch_images(batch_id):
    """Retrieve all uploaded package images and manifest for a registered batch."""
    clean_id = batch_id.strip()
    manifest = ipfs.get_local_manifest(clean_id)
    if not manifest:
        rec = blockchain.find_record(clean_id)
        if rec and rec.get("ipfs_cid"):
            return jsonify(
                batch_id=clean_id,
                medicine_name=rec.get("name", ""),
                total_images=1,
                primary_image_cid=rec["ipfs_cid"],
                manifest_cid=None,
                images=[{
                    "index": 0,
                    "cid": rec["ipfs_cid"],
                    "filename": "reference.jpg",
                    "view": "Primary Package View",
                    "size_bytes": 0,
                    "url": f"/api/reference-image/{clean_id}",
                }],
            )
        return jsonify(error=f"No packaging images found for '{clean_id}'."), 404

    return jsonify(
        batch_id=manifest.get("batch_id", clean_id),
        medicine_name=manifest.get("medicine_name", ""),
        total_images=manifest.get("total_images", len(manifest.get("images", []))),
        primary_image_cid=manifest.get("primary_image_cid"),
        manifest_cid=manifest.get("manifest_cid"),
        images=manifest.get("images", []),
    )


# =====================================================================
# USER & ORGANIZATION MANAGEMENT (ADMIN / WORKSPACE)
# =====================================================================

@app.route("/api/users", methods=["GET"])
def get_users():
    """Retrieve all registered users, their approval statuses, and organization metadata."""
    if not blockchain.is_connected():
        return jsonify(error="Blockchain node is unavailable."), 503

    try:
        users = blockchain.get_all_users()
        enriched = []
        organizations = []
        for u in users:
            meta = auth.get_org_metadata(u.get("address", ""))
            is_admin_entry = bool(
                u.get("is_admin")
                or u.get("role") == 1
                or (u.get("role_name") or "").lower() == "admin"
            )
            item = {
                **meta,
                **u,
                "is_admin": is_admin_entry,
                "is_organization": not is_admin_entry,
            }
            enriched.append(item)
            if not is_admin_entry:
                organizations.append(item)
        return jsonify(
            users=enriched,
            organizations=organizations,
            organization_count=len(organizations),
        )
    except Exception as exc:
        return jsonify(error=str(exc)), 500


@app.route("/api/users/<address>", methods=["GET"])
def get_user_by_address(address):
    """Retrieve a specific user profile and status."""
    if not blockchain.is_connected():
        return jsonify(error="Blockchain node is unavailable."), 503

    try:
        user = blockchain.get_user(address)
        meta = auth.get_org_metadata(address)
        return jsonify(user={**meta, **user})
    except Exception as exc:
        return jsonify(error=str(exc)), 500


@app.route("/api/register-user", methods=["POST"])
def register_user():
    """Register a new supply-chain organization on-chain and store credentials."""
    data = request.get_json(silent=True) or request.form.to_dict()
    role = data.get("role", "").strip().lower()
    name = data.get("name", "").strip()
    email = data.get("email", "").strip()
    username = data.get("username", "").strip()
    password = data.get("password", "")
    license_number = data.get("license_number", "").strip()
    contact_phone = data.get("contact_phone", "").strip()
    location = data.get("location", "").strip()
    linked_mfr = data.get("linked_manufacturer", "").strip()
    linked_dist = data.get("linked_distributor", "").strip()

    if role == "admin":
        return jsonify(
            error="Public registration for Admin is prohibited.",
            code="ADMIN_SIGNUP_FORBIDDEN",
        ), 403

    if not role or not name:
        return jsonify(error="Role and Organization Name are required."), 400

    if role not in ("manufacturer", "distributor", "pharmacy"):
        return jsonify(error="Role must be Manufacturer, Distributor, or Pharmacy."), 400

    try:
        reg_details = blockchain.register_user_with_details(
            role,
            name,
            linked_mfr=linked_mfr,
            linked_dist=linked_dist,
        )
        org_record = auth.register_organization_credentials(
            address=reg_details["address"],
            role=role,
            org_name=name,
            email=email,
            username=username,
            password=password,
            license_number=license_number,
            contact_phone=contact_phone,
            location=location,
            linked_manufacturer=reg_details.get("linked_manufacturer", ""),
            linked_distributor=reg_details.get("linked_distributor", ""),
            tx_hash=reg_details["tx_hash"],
            block_number=reg_details.get("block_number"),
            private_key=reg_details.get("private_key"),
        )
        chain_user = blockchain.get_user(reg_details["address"])
        required_approvals = ["Admin"]
        if role == "distributor":
            required_approvals.append("Manufacturer")
        elif role == "pharmacy":
            required_approvals.extend(["Manufacturer", "Distributor"])

        return jsonify(
            success=True,
            role=role,
            name=name,
            address=reg_details["address"],
            status_name=chain_user.get("status_name", "Pending"),
            required_approvals=required_approvals,
            transaction_hash=reg_details["tx_hash"],
            block_number=reg_details.get("block_number"),
            confirmation_status="Confirmed",
            organization=org_record,
            message=f"{name} registered on blockchain with status Pending. Required approvals: {', '.join(required_approvals)}.",
        ), 201
    except PermissionError as exc:
        return jsonify(error=str(exc), code="FORBIDDEN"), 403
    except ValueError as exc:
        return jsonify(error=str(exc), code="VALIDATION_ERROR"), 400
    except Exception as exc:
        app.logger.exception("User registration failed")
        return jsonify(error=f"{type(exc).__name__}: {exc}"), 500


@app.route("/api/approve-user", methods=["POST"])
def approve_user():
    """Approve a pending organization user."""
    data = request.get_json(silent=True) or request.form.to_dict()
    target = data.get("target", "").strip()
    approver_role = data.get("approver_role", "admin").strip().lower()

    if not target:
        return jsonify(error="Target address is required."), 400

    signer_key, resolved_role, _, auth_err = _resolve_authorized_signer(
        ("admin", "manufacturer", "distributor"),
        explicit_role=approver_role,
    )
    if auth_err is not None:
        return auth_err

    try:
        tx_hash = blockchain.approve_user(target, signer_role=resolved_role, private_key=signer_key)
        tx_meta = blockchain.get_tx_meta(tx_hash)
        updated = blockchain.get_user(target)
        actor_user = getattr(g, "actor", {}).get("username", resolved_role)
        app.logger.info("Organization %s approved by %s (%s). Tx: %s", target, actor_user, resolved_role, tx_hash)
        return jsonify(
            success=True,
            target=target,
            approver_role=resolved_role,
            actor_username=actor_user,
            status=updated.get("status_name", "Pending"),
            adminOk=updated.get("adminOk", False),
            mfrOk=updated.get("mfrOk", False),
            distOk=updated.get("distOk", False),
            transaction_hash=tx_hash,
            block_number=tx_meta.get("block_number"),
            confirmation_status=tx_meta.get("confirmation_status", "Confirmed"),
            message=f"Approval recorded on-chain by {resolved_role.capitalize()}. Current status: {updated.get('status_name')}.",
        )
    except Exception as exc:
        app.logger.exception("User approval failed")
        return jsonify(error=f"{type(exc).__name__}: {exc}"), 500


@app.route("/api/reject-user", methods=["POST"])
def reject_user():
    """Reject a pending organization user."""
    data = request.get_json(silent=True) or request.form.to_dict()
    target = data.get("target", "").strip()
    rejecter_role = data.get("rejecter_role", "admin").strip().lower()

    if not target:
        return jsonify(error="Target address is required."), 400

    signer_key, resolved_role, _, auth_err = _resolve_authorized_signer(
        ("admin", "manufacturer", "distributor"),
        explicit_role=rejecter_role,
    )
    if auth_err is not None:
        return auth_err

    try:
        tx_hash = blockchain.reject_user(target, signer_role=resolved_role, private_key=signer_key)
        tx_meta = blockchain.get_tx_meta(tx_hash)
        updated = blockchain.get_user(target)
        actor_user = getattr(g, "actor", {}).get("username", resolved_role)
        app.logger.info("Organization %s rejected by %s (%s). Tx: %s", target, actor_user, resolved_role, tx_hash)
        return jsonify(
            success=True,
            target=target,
            rejecter_role=resolved_role,
            actor_username=actor_user,
            status=updated.get("status_name", "Rejected"),
            transaction_hash=tx_hash,
            block_number=tx_meta.get("block_number"),
            confirmation_status=tx_meta.get("confirmation_status", "Confirmed"),
            message=f"Organization {target} rejected on-chain.",
        )
    except Exception as exc:
        app.logger.exception("User rejection failed")
        return jsonify(error=f"{type(exc).__name__}: {exc}"), 500


# =====================================================================
# SUPPLY-CHAIN STAGE ADVANCEMENT (DISTRIBUTOR & PHARMACY)
# =====================================================================

@app.route("/api/distributor/receive", methods=["POST"])
def distributor_receive():
    """Distributor records receipt of medicine from manufacturer."""
    signer_key, _, signer_addr, auth_err = _resolve_authorized_signer(("distributor",))
    if auth_err is not None:
        return auth_err

    data = request.get_json(silent=True) or request.form.to_dict()
    medicine_id = data.get("medicine_id", "").strip()
    details = data.get("details", "").strip()

    if not medicine_id:
        return jsonify(error="Medicine ID or Batch ID is required."), 400

    try:
        record = blockchain.find_record(medicine_id)
        if record is None:
            return jsonify(error=f"Medicine '{medicine_id}' not found on blockchain."), 404

        actual_id = record["raw"]["id"]
        current_stage = int(record.get("stage") or 1)

        # 1. On-chain stage validation
        if current_stage == 2:
            stages = blockchain.read_stages(actual_id)
            dist_info = stages.get("distributor", {})
            dist_actor = dist_info.get("actor") or record.get("distributor", "Authorized Distributor")
            dist_time = dist_info.get("timestamp")
            time_str = f" at {datetime.fromtimestamp(dist_time, tz=timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}" if dist_time else ""
            return jsonify(
                error=f"Medicine batch '{medicine_id}' has already been received by distributor ({dist_actor}){time_str}. Current status: Stage 2 (With Distributor).",
                code="ALREADY_RECEIVED",
                current_stage=2,
                distributor=dist_actor,
            ), 400

        if current_stage >= 3:
            return jsonify(
                error=f"Medicine batch '{medicine_id}' has already progressed to retail pharmacy (Stage 3).",
                code="STAGE_EXCEEDED",
                current_stage=current_stage,
            ), 400

        if current_stage != 1:
            return jsonify(
                error=f"Cannot record distributor receipt: batch '{medicine_id}' is at Stage {current_stage}, but Stage 1 (Manufactured) is required.",
                code="INVALID_STAGE",
                current_stage=current_stage,
            ), 400

        # 2. Distributor-Manufacturer linkage validation
        chain_u = blockchain.get_user(signer_addr)
        dist_linked_mfr = (chain_u.get("manufacturer") or "").lower()
        batch_mfr = (record.get("manufacturer") or "").lower()
        if dist_linked_mfr and batch_mfr and dist_linked_mfr != batch_mfr:
            return jsonify(
                error=f"Distributor ({signer_addr}) is registered under manufacturer {dist_linked_mfr}, but batch '{medicine_id}' was manufactured by {batch_mfr}.",
                code="MANUFACTURER_MISMATCH",
            ), 400

        # 3. Recall validation
        if record.get("recalled"):
            return jsonify(
                error=f"Cannot receive batch '{medicine_id}': medicine is recalled ({record.get('recall_reason') or 'Safety Recall'}).",
                code="BATCH_RECALLED",
            ), 400

        # 4. Expiry validation
        if record.get("expired"):
            return jsonify(
                error=f"Cannot receive batch '{medicine_id}': medicine has expired.",
                code="BATCH_EXPIRED",
            ), 400

        tx_hash = blockchain.distributor_receive(actual_id, details=details, private_key=signer_key)
        tx_meta = blockchain.get_tx_meta(tx_hash)
        return jsonify(
            success=True,
            medicine_id=actual_id,
            stage=2,
            distributor=signer_addr,
            transaction_hash=tx_hash,
            block_number=tx_meta.get("block_number"),
            confirmation_status=tx_meta.get("confirmation_status", "Confirmed"),
            message="Distributor receipt confirmed on blockchain (Stage 2).",
        )
    except Exception as exc:
        app.logger.exception("Distributor receive failed")
        friendly_err = _parse_revert_message(exc)
        status_code = 400 if "Smart contract" in friendly_err or "revert" in friendly_err.lower() else 500
        return jsonify(error=friendly_err, code="TRANSACTION_FAILED"), status_code


@app.route("/api/pharmacy/receive", methods=["POST"])
def pharmacy_receive():
    """Pharmacy records receipt of medicine from distributor."""
    signer_key, _, signer_addr, auth_err = _resolve_authorized_signer(("pharmacy",))
    if auth_err is not None:
        return auth_err

    data = request.get_json(silent=True) or request.form.to_dict()
    medicine_id = data.get("medicine_id", "").strip()
    details = data.get("details", "").strip()

    if not medicine_id:
        return jsonify(error="Medicine ID or Batch ID is required."), 400

    try:
        record = blockchain.find_record(medicine_id)
        if record is None:
            return jsonify(error=f"Medicine '{medicine_id}' not found on blockchain."), 404

        actual_id = record["raw"]["id"]
        current_stage = int(record.get("stage") or 1)

        # 1. On-chain stage validation
        if current_stage == 3:
            stages = blockchain.read_stages(actual_id)
            pharm_info = stages.get("pharmacy", {})
            pharm_actor = pharm_info.get("actor") or record.get("pharmacy", "Authorized Pharmacy")
            pharm_time = pharm_info.get("timestamp")
            time_str = f" at {datetime.fromtimestamp(pharm_time, tz=timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}" if pharm_time else ""
            return jsonify(
                error=f"Medicine batch '{medicine_id}' has already been received by pharmacy ({pharm_actor}){time_str}. Current status: Stage 3 (In Pharmacy).",
                code="ALREADY_RECEIVED",
                current_stage=3,
                pharmacy=pharm_actor,
            ), 400

        if current_stage == 1:
            return jsonify(
                error=f"Cannot record pharmacy receipt: batch '{medicine_id}' is still in Stage 1 (Manufactured). It must first be received by an authorized distributor (Stage 2).",
                code="PREVIOUS_STAGE_PENDING",
                current_stage=1,
            ), 400

        if current_stage != 2:
            return jsonify(
                error=f"Cannot record pharmacy receipt: batch '{medicine_id}' is at Stage {current_stage}, but Stage 2 (With Distributor) is required.",
                code="INVALID_STAGE",
                current_stage=current_stage,
            ), 400

        # 2. Pharmacy-Distributor linkage validation
        chain_u = blockchain.get_user(signer_addr)
        pharm_linked_dist = (chain_u.get("distributor") or "").lower()
        batch_dist = (record.get("distributor") or "").lower()
        if pharm_linked_dist and batch_dist and pharm_linked_dist != batch_dist:
            return jsonify(
                error=f"Pharmacy ({signer_addr}) is registered under distributor {pharm_linked_dist}, but batch '{medicine_id}' is currently held by distributor {batch_dist}.",
                code="DISTRIBUTOR_MISMATCH",
            ), 400

        # 3. Recall validation
        if record.get("recalled"):
            return jsonify(
                error=f"Cannot receive batch '{medicine_id}': medicine is recalled ({record.get('recall_reason') or 'Safety Recall'}).",
                code="BATCH_RECALLED",
            ), 400

        # 4. Expiry validation
        if record.get("expired"):
            return jsonify(
                error=f"Cannot receive batch '{medicine_id}': medicine has expired.",
                code="BATCH_EXPIRED",
            ), 400

        tx_hash = blockchain.pharmacy_receive(actual_id, details=details, private_key=signer_key)
        tx_meta = blockchain.get_tx_meta(tx_hash)
        return jsonify(
            success=True,
            medicine_id=actual_id,
            stage=3,
            pharmacy=signer_addr,
            transaction_hash=tx_hash,
            block_number=tx_meta.get("block_number"),
            confirmation_status=tx_meta.get("confirmation_status", "Confirmed"),
            message="Pharmacy receipt confirmed on blockchain (Stage 3).",
        )
    except Exception as exc:
        app.logger.exception("Pharmacy receive failed")
        friendly_err = _parse_revert_message(exc)
        status_code = 400 if "Smart contract" in friendly_err or "revert" in friendly_err.lower() else 500
        return jsonify(error=friendly_err, code="TRANSACTION_FAILED"), status_code


@app.route("/api/stages/<path:medicine_id>", methods=["GET"])
def get_stages(medicine_id):
    """Retrieve full distributor & pharmacy timeline records."""
    if not blockchain.is_connected():
        return jsonify(error="Blockchain node is unavailable."), 503

    try:
        record = blockchain.find_record(medicine_id)
        if record is None:
            return jsonify(error="Medicine not found."), 404

        actual_id = record["raw"]["id"]
        stages = blockchain.read_stages(actual_id)
        history = blockchain.read_history(actual_id)
        audit = blockchain.read_audit_trail(actual_id)
        return jsonify(
            medicine_id=actual_id,
            stages=stages,
            history=history,
            journey=audit.get("journey", []),
            events=audit.get("events", []),
        )
    except Exception as exc:
        return jsonify(error=str(exc)), 500


@app.route("/api/recall", methods=["POST"])
def recall_medicine():
    """Recall a medicine batch on blockchain (Manufacturer or Admin)."""
    data = request.get_json(silent=True) or request.form.to_dict()
    medicine_id = data.get("medicine_id", "").strip()
    reason = data.get("reason", "").strip()
    role = data.get("role", "manufacturer").strip().lower()

    if not medicine_id or not reason:
        return jsonify(error="Medicine ID and recall reason are required."), 400

    signer_key, resolved_role, _, auth_err = _resolve_authorized_signer(
        ("manufacturer", "admin"),
        explicit_role=role,
    )
    if auth_err is not None:
        return auth_err

    try:
        record = blockchain.find_record(medicine_id)
        if record is None:
            return jsonify(error=f"Medicine '{medicine_id}' not found on blockchain."), 404

        actual_id = record["raw"]["id"]
        tx_hash = blockchain.recall_medicine(actual_id, reason, signer_role=resolved_role, private_key=signer_key)
        tx_meta = blockchain.get_tx_meta(tx_hash)
        actor_user = getattr(g, "actor", {}).get("username", resolved_role)
        app.logger.info("Medicine %s recalled on-chain by %s (%s). Tx: %s", actual_id, actor_user, resolved_role, tx_hash)
        return jsonify(
            success=True,
            medicine_id=actual_id,
            reason=reason,
            actor_username=actor_user,
            transaction_hash=tx_hash,
            block_number=tx_meta.get("block_number"),
            confirmation_status=tx_meta.get("confirmation_status", "Confirmed"),
            message=f"Medicine {actual_id} recalled on blockchain.",
        )
    except Exception as exc:
        app.logger.exception("Medicine recall failed")
        return jsonify(error=f"{type(exc).__name__}: {exc}"), 500


@app.route("/api/batches", methods=["GET"])
def get_batches():
    """Retrieve all medicine batches on blockchain with optional stage and manufacturer filtering."""
    if not blockchain.is_connected():
        return jsonify(error="Blockchain node is unavailable."), 503

    stage = request.args.get("stage")
    stage_val = int(stage) if stage and stage.isdigit() else None
    manufacturer = request.args.get("manufacturer", "").strip() or None

    try:
        batches = blockchain.get_all_batches(stage=stage_val, manufacturer=manufacturer)
        return jsonify(batches=batches, count=len(batches))
    except Exception as exc:
        app.logger.exception("Failed to fetch batches")
        return jsonify(error=str(exc)), 500


# =====================================================================
# SYSTEM ROLES & CONFIGURATION
# =====================================================================

@app.route("/api/roles", methods=["GET"])
def get_system_roles():
    """Get configured role addresses and system metadata."""
    return jsonify({
        "admin": {
            "address": blockchain.w3.eth.account.from_key(blockchain.DEFAULT_ADMIN_KEY).address,
            "role": "Admin",
            "requires_approval": False,
            "admin_provisioned": auth.has_admin_account(),
        },
        "manufacturer": {
            "address": blockchain.w3.eth.account.from_key(blockchain.DEFAULT_MFR_KEY).address,
            "role": "Manufacturer",
            "requires_approval": True,
        },
        "distributor": {
            "address": blockchain.w3.eth.account.from_key(blockchain.DEFAULT_DIST_KEY).address,
            "role": "Distributor",
            "requires_approval": True,
        },
        "pharmacy": {
            "address": blockchain.w3.eth.account.from_key(blockchain.DEFAULT_PHARM_KEY).address,
            "role": "Pharmacy",
            "requires_approval": True,
        },
        "consumer": {
            "role": "Consumer",
            "requires_approval": False,
        },
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=True)
