"""Starts the server and defines /verify  ->  Verified | Suspicious | Unverified"""
import io
import logging
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")
import os  # noqa: E402

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
        return jsonify(verdict="Unverified", reason="No blockchain record found.",
                       medicine_id=medicine_id)

    # OCR: name / batch / expiry from the pack
    ocr_result = ocr.analyse(uploaded, record)
    chain_ok = not record["recalled"] and not record["expired"]
    if chain_ok and REQUIRE_OCR_BATCH_MATCH:
        chain_ok = ocr_result["batch_match"]

    record_details = {
        "name": record["name"], "manufacturer": record["manufacturer"],
        "batch": record["batch"], "expiry": record["expiry"],
        "recalled": record["recalled"], "expired": record["expired"],
        "recall_reason": record["recall_reason"], "blockchain_ok": chain_ok,
    }

    # model must be present for the image check
    try:
        vision.get_model()
    except vision.ModelNotReady as e:
        return jsonify(verdict=None, error=str(e), medicine_id=medicine_id,
                       details=record_details, ocr=ocr_result), 503
    except Exception as e:
        return jsonify(error=f"Model failed to load: {e}"), 500

    # (b) reference image from IPFS + (c) model comparison
    score, image_ok, image_error = None, False, None
    try:
        reference = ipfs.fetch_image(record["ipfs_cid"])
        score = vision.similarity(uploaded, reference)
        image_ok = score >= vision.SIMILARITY_THRESHOLD

    except Exception as e:
        image_error = str(e)
        log.error("Image comparison failed: %s", e)

        return jsonify(
            verdict="Unverified",
            reason=(
                "Image comparison unavailable. "
                "A valid reference image must be configured."
            ),
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
        details={**record_details, "image_ok": image_ok,
                 "similarity": None if score is None else round(score, 4),
                 "threshold": vision.SIMILARITY_THRESHOLD, "image_error": image_error},
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

        history = blockchain.read_history(record["raw"]["id"])

        return jsonify(
            found=True,
            medicine_id=record["raw"]["id"],
            name=record["name"],
            batch=record["batch"],
            manufacturer=record["manufacturer"],
            expiry=record["expiry"],
            expired=record["expired"],
            recalled=record["recalled"],
            recall_reason=record["recall_reason"],
            current_owner=record["raw"].get("currentOwner", ""),
            history=history,
        )
    except Exception:
        app.logger.exception("Blockchain lookup failed")
        return jsonify(error="Could not read the blockchain record."), 500

@app.route("/health")
def health():
    return jsonify(status="ok", chain_connected=blockchain.is_connected(),
                   model_installed=vision.is_installed())


from datetime import datetime, timezone, timedelta



@app.route("/register", methods=["POST"])
def register():
    """Upload a medicine reference image to IPFS and register it on-chain."""
    medicine_id = request.form.get("medicine_id", "").strip()
    name = request.form.get("name", "").strip()
    batch = request.form.get("batch", "").strip()
    expiry = request.form.get("expiry", "").strip()
    file = request.files.get("image")

    if not all([medicine_id, name, batch, expiry, file]):
        return jsonify(
            error="Required fields: medicine_id, name, batch, expiry, image."
        ), 400

    try:
        expiry_date = datetime.strptime(expiry, "%Y-%m-%d").date()
    except ValueError:
        return jsonify(
            error=f"Invalid expiry date received: {expiry!r}. Use YYYY-MM-DD."
        ), 400

    try:
        # Keep the medicine valid through the entire expiry date.
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
        )

        return jsonify(
            success=True,
            medicine_id=medicine_id,
            name=name,
            batch=batch,
            expiry=expiry,
            image_cid=image_cid,
            transaction_hash=tx_hash,
            message="Medicine registered successfully on the blockchain.",
        ), 201

    except Exception as exc:
        app.logger.exception("Medicine registration failed")
        return jsonify(error=f"{type(exc).__name__}: {exc}"), 500



if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=True)