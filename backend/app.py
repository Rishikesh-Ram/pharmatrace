"""Starts the server and defines PharmaTrace API endpoints."""
import io
import logging
import os
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
from datetime import datetime, timezone, timedelta
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

from flask import Flask, jsonify, request  # noqa: E402
from flask_cors import CORS  # noqa: E402
from PIL import Image  # noqa: E402

from services import blockchain, ipfs, ocr, vision  # noqa: E402

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

    # (a) blockchain record
    record = blockchain.read_record(medicine_id)
    if record is None:
        return jsonify(
            verdict="Unverified",
            reason="No blockchain record found.",
            medicine_id=medicine_id,
        )

    # OCR: name / batch / expiry from the pack
    ocr_result = ocr.analyse(uploaded, record)
    chain_ok = not record["recalled"] and not record["expired"]
    if chain_ok and REQUIRE_OCR_BATCH_MATCH:
        chain_ok = ocr_result["batch_match"]

    record_details = {
        "name": record["name"],
        "manufacturer": record["manufacturer"],
        "batch": record["batch"],
        "expiry": record["expiry"],
        "recalled": record["recalled"],
        "expired": record["expired"],
        "recall_reason": record["recall_reason"],
        "blockchain_ok": chain_ok,
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

        return jsonify(
            verdict="Suspicious" if chain_ok else "Unverified",
            reason="Image comparison unavailable or reference missing.",
            medicine_id=medicine_id,
            details={
                **record_details,
                "image_ok": False,
                "similarity": None,
                "threshold": vision.SIMILARITY_THRESHOLD,
                "image_error": image_error,
            },
            ocr=ocr_result,
        )

    # (d) verdict
    return jsonify(
        verdict=decide(True, chain_ok, image_ok),
        medicine_id=medicine_id,
        details={
            **record_details,
            "image_ok": image_ok,
            "similarity": None if score is None else round(score, 4),
            "threshold": vision.SIMILARITY_THRESHOLD,
            "image_error": image_error,
        },
        ocr=ocr_result,
    )


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

        return jsonify(
            found=True,
            medicine_id=actual_id,
            name=record["name"],
            batch=record["batch"],
            manufacturer=record["manufacturer"],
            expiry=record["expiry"],
            expired=record["expired"],
            recalled=record["recalled"],
            recall_reason=record["recall_reason"],
            current_owner=record["raw"].get("currentOwner", ""),
            quantity=record.get("quantity", 0),
            stage=record.get("stage", 1),
            distributor=record.get("distributor", ""),
            pharmacy=record.get("pharmacy", ""),
            history=history,
            stages=stages,
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
        )

        return jsonify(
            success=True,
            medicine_id=medicine_id,
            name=name,
            batch=batch,
            expiry=expiry,
            quantity=quantity,
            image_cid=image_cid,
            transaction_hash=tx_hash,
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
    """Retrieve all registered users and their approval statuses."""
    if not blockchain.is_connected():
        return jsonify(error="Blockchain node is unavailable."), 503

    try:
        users = blockchain.get_all_users()
        return jsonify(users=users)
    except Exception as exc:
        return jsonify(error=str(exc)), 500


@app.route("/api/users/<address>", methods=["GET"])
def get_user_by_address(address):
    """Retrieve a specific user profile and status."""
    if not blockchain.is_connected():
        return jsonify(error="Blockchain node is unavailable."), 503

    try:
        user = blockchain.get_user(address)
        return jsonify(user=user)
    except Exception as exc:
        return jsonify(error=str(exc)), 500


@app.route("/api/register-user", methods=["POST"])
def register_user():
    """Register a new supply-chain organization on-chain."""
    data = request.get_json(silent=True) or request.form.to_dict()
    role = data.get("role", "").strip()
    name = data.get("name", "").strip()
    linked_mfr = data.get("linked_manufacturer", "").strip()
    linked_dist = data.get("linked_distributor", "").strip()

    if not role or not name:
        return jsonify(error="Role and Organization Name are required."), 400

    try:
        tx_hash = blockchain.register_user(
            role,
            name,
            linked_mfr=linked_mfr,
            linked_dist=linked_dist,
        )
        return jsonify(
            success=True,
            role=role,
            name=name,
            transaction_hash=tx_hash,
            message=f"{name} registered successfully as {role}. Awaiting approval.",
        ), 201
    except Exception as exc:
        app.logger.exception("User registration failed")
        return jsonify(error=f"{type(exc).__name__}: {exc}"), 500


@app.route("/api/approve-user", methods=["POST"])
def approve_user():
    """Approve a pending organization user."""
    data = request.get_json(silent=True) or request.form.to_dict()
    target = data.get("target", "").strip()
    approver_role = data.get("approver_role", "admin").strip()

    if not target:
        return jsonify(error="Target address is required."), 400

    try:
        tx_hash = blockchain.approve_user(target, signer_role=approver_role)
        updated = blockchain.get_user(target)
        return jsonify(
            success=True,
            target=target,
            status=updated.get("status_name", "Active"),
            transaction_hash=tx_hash,
            message=f"User {target} approved successfully.",
        )
    except Exception as exc:
        app.logger.exception("User approval failed")
        return jsonify(error=f"{type(exc).__name__}: {exc}"), 500


@app.route("/api/reject-user", methods=["POST"])
def reject_user():
    """Reject a pending organization user."""
    data = request.get_json(silent=True) or request.form.to_dict()
    target = data.get("target", "").strip()
    rejecter_role = data.get("rejecter_role", "admin").strip()

    if not target:
        return jsonify(error="Target address is required."), 400

    try:
        tx_hash = blockchain.reject_user(target, signer_role=rejecter_role)
        return jsonify(
            success=True,
            target=target,
            transaction_hash=tx_hash,
            message=f"User {target} rejected.",
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
        tx_hash = blockchain.distributor_receive(actual_id, details=details)
        return jsonify(
            success=True,
            medicine_id=actual_id,
            stage=2,
            transaction_hash=tx_hash,
            message="Distributor receipt confirmed on blockchain (Stage 2).",
        )
    except Exception as exc:
        app.logger.exception("Distributor receive failed")
        return jsonify(error=f"{type(exc).__name__}: {exc}"), 500


@app.route("/api/pharmacy/receive", methods=["POST"])
def pharmacy_receive():
    """Pharmacy records receipt of medicine from distributor."""
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
        tx_hash = blockchain.pharmacy_receive(actual_id, details=details)
        return jsonify(
            success=True,
            medicine_id=actual_id,
            stage=3,
            transaction_hash=tx_hash,
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
        return jsonify(medicine_id=actual_id, stages=stages, history=history)
    except Exception as exc:
        return jsonify(error=str(exc)), 500






@app.route("/api/recall", methods=["POST"])
def recall_medicine():
    """Recall a medicine batch on blockchain (Manufacturer or Admin)."""
    data = request.get_json(silent=True) or request.form.to_dict()
    medicine_id = data.get("medicine_id", "").strip()
    reason = data.get("reason", "").strip()
    role = data.get("role", "manufacturer").strip()

    if not medicine_id or not reason:
        return jsonify(error="Medicine ID and recall reason are required."), 400

    try:
        record = blockchain.find_record(medicine_id)
        if record is None:
            return jsonify(error=f"Medicine '{medicine_id}' not found on blockchain."), 404

        actual_id = record["raw"]["id"]
        tx_hash = blockchain.recall_medicine(actual_id, reason, signer_role=role)
        return jsonify(
            success=True,
            medicine_id=actual_id,
            reason=reason,
            transaction_hash=tx_hash,
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
            "requires_approval": False,
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
