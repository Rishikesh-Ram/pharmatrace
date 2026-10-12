"""Starts the server and defines /verify  ->  Verified | Suspicious | Unverified"""
import io
import logging

from dotenv import load_dotenv

load_dotenv()  # must run before the services read their settings

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

    # (d) verdict
    return jsonify(
        verdict=decide(True, chain_ok, image_ok),
        medicine_id=medicine_id,
        details={**record_details, "image_ok": image_ok,
                 "similarity": None if score is None else round(score, 4),
                 "threshold": vision.SIMILARITY_THRESHOLD, "image_error": image_error},
        ocr=ocr_result,
    )


@app.route("/health")
def health():
    return jsonify(status="ok", chain_connected=blockchain.is_connected(),
                   model_installed=vision.is_installed())


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=True)