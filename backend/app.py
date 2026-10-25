"""Starts the server and defines PharmaTrace API endpoints."""
import io
import logging
import os
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
from datetime import datetime, timezone, timedelta
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

from flask import Flask, jsonify, request, send_file  # noqa: E402
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

        off_chain_analysis.append(
            f"OCR Batch Number: '{found_b or 'Not detected'}' vs Expected '{record.get('batch')}' ({b_status})."
        )
        off_chain_analysis.append(
            f"OCR Expiry Date: '{found_e or 'Not detected'}' vs Expected '{exp_e or 'N/A'}' ({e_status})."
        )
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

    if session:
        user_role = session["role"].lower()
        user_addr = session["address"]
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

    # Verify on-chain active status for non-admin roles
    if user_role != "admin":
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

    key = auth.get_signing_key_for_address(user_addr, fallback_role=user_role)
    return key, user_role, user_addr, None


# =====================================================================
# AUTHENTICATION ENDPOINTS
# =====================================================================

@app.route("/api/auth/login", methods=["POST"])
def api_login():
    """Authenticate a supply-chain organization or admin account."""
    data = request.get_json(silent=True) or request.form.to_dict()
    identifier = (data.get("identifier") or data.get("username") or data.get("email") or "").strip()
    password = data.get("password") or ""
    expected_role = (data.get("role") or data.get("expected_role") or "").strip()

    if not identifier or not password:
        return jsonify(
            error="Username/email and password are required.",
            code="MISSING_CREDENTIALS",
        ), 400

    res, err, status = auth.authenticate_user(identifier, password, expected_role=expected_role or None)
    if err is not None:
        return jsonify(err), status
    return jsonify(res), 200


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

@app.route("/register", methods=["POST"])
def register():
    """Upload a medicine reference image to IPFS and register it on-chain."""
    signer_key, _, signer_addr, auth_err = _resolve_authorized_signer(("manufacturer",))
    if auth_err is not None:
        return auth_err

    medicine_id = request.form.get("medicine_id", "").strip()
    name = request.form.get("name", "").strip()
    batch = request.form.get("batch", "").strip()
    expiry = request.form.get("expiry", "").strip()
    quantity_str = request.form.get("quantity", "100").strip()
    file = request.files.get("image")

    if not all([medicine_id, name, batch, expiry, file]):
        return jsonify(
            error="Required fields: medicine_id, name, batch, expiry, image."
        ), 400

    try:
        quantity = int(quantity_str) if quantity_str.isdigit() else 100
    except ValueError:
        quantity = 100

    try:
        expiry_date = datetime.strptime(expiry, "%Y-%m-%d").date()
    except ValueError:
        return jsonify(
            error=f"Invalid expiry date received: {expiry!r}. Use YYYY-MM-DD."
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
                error="Expiry date must be today or in the future."
            ), 400

        image_bytes = file.read()
        if not image_bytes:
            return jsonify(error="The uploaded image is empty."), 400

        image_cid = ipfs.upload_image(
            image_bytes,
            file.filename or "reference.jpg",
        )

        tx_hash = blockchain.register_medicine(
            medicine_id,
            name,
            batch,
            expiry_timestamp,
            image_cid,
            quantity=quantity,
            private_key=signer_key,
        )
        tx_meta = blockchain.get_tx_meta(tx_hash)

        return jsonify(
            success=True,
            medicine_id=medicine_id,
            name=name,
            batch=batch,
            expiry=expiry,
            quantity=quantity,
            manufacturer=signer_addr,
            image_cid=image_cid,
            transaction_hash=tx_hash,
            block_number=tx_meta.get("block_number"),
            confirmation_status=tx_meta.get("confirmation_status", "Confirmed"),
            message="Medicine registered successfully on the blockchain.",
        ), 201

    except Exception as exc:
        app.logger.exception("Medicine registration failed")
        return jsonify(error=f"{type(exc).__name__}: {exc}"), 500


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
        for u in users:
            meta = auth.get_org_metadata(u.get("address", ""))
            enriched.append({
                **meta,
                **u,
            })
        return jsonify(users=enriched)
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
        return jsonify(
            success=True,
            target=target,
            approver_role=resolved_role,
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
        return jsonify(
            success=True,
            target=target,
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
        return jsonify(error=f"{type(exc).__name__}: {exc}"), 500


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
        return jsonify(error=f"{type(exc).__name__}: {exc}"), 500


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
        return jsonify(
            success=True,
            medicine_id=actual_id,
            reason=reason,
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
# SYSTEM ROLES & DEMO UTILITIES
# =====================================================================

@app.route("/api/roles", methods=["GET"])
def get_system_roles():
    """Get system accounts and configured role addresses for demo & dashboard routing."""
    return jsonify({
        "admin": {
            "address": blockchain.w3.eth.account.from_key(blockchain.DEFAULT_ADMIN_KEY).address,
            "role": "Admin",
            "username": "admin",
            "email": "admin@pharmatrace.local",
            "requires_approval": False,
        },
        "manufacturer": {
            "address": blockchain.w3.eth.account.from_key(blockchain.DEFAULT_MFR_KEY).address,
            "role": "Manufacturer",
            "username": "manufacturer",
            "email": "manufacturer@elnova.local",
            "requires_approval": True,
        },
        "distributor": {
            "address": blockchain.w3.eth.account.from_key(blockchain.DEFAULT_DIST_KEY).address,
            "role": "Distributor",
            "username": "distributor",
            "email": "distributor@medline.local",
            "requires_approval": True,
        },
        "pharmacy": {
            "address": blockchain.w3.eth.account.from_key(blockchain.DEFAULT_PHARM_KEY).address,
            "role": "Pharmacy",
            "username": "pharmacy",
            "email": "pharmacy@apollocare.local",
            "requires_approval": True,
        },
        "consumer": {
            "role": "Consumer",
            "requires_approval": False,
        },
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=True)
