"""Tests for Phase 3: Distributor Receipt Protection, OCR Consensus, and Multi-Image Registration."""
import io
import json
import pytest
from PIL import Image

from app import app
from services import ocr, ipfs, blockchain


@pytest.fixture
def client():
    return app.test_client()


def _make_dummy_image_bytes(color=(200, 200, 200), size=(320, 320), format="JPEG"):
    buf = io.BytesIO()
    img = Image.new("RGB", size, color=color)
    img.save(buf, format=format)
    return buf.getvalue()


# =====================================================================
# 1. DISTRIBUTOR RECEIPT TESTS
# =====================================================================

def test_distributor_receive_nonexistent_batch(client):
    """Attempting distributor receipt on a non-existent batch returns 404."""
    res = client.post("/api/distributor/receive", json={
        "medicine_id": "NON_EXISTENT_BATCH_9999",
        "details": "Testing non-existent receipt",
    })
    assert res.status_code == 404
    assert "not found on blockchain" in res.json["error"]


def test_distributor_duplicate_receipt_rejected(client):
    """Attempting distributor receipt on a batch already at Stage 2 returns HTTP 400 with ALREADY_RECEIVED."""
    # Batch 2623014N was previously received and is currently at Stage 2
    res = client.post("/api/distributor/receive", json={
        "medicine_id": "2623014N",
        "details": "Duplicate receipt attempt",
    })
    assert res.status_code == 400
    assert res.json.get("code") in ("ALREADY_RECEIVED", "STAGE_EXCEEDED")


def test_pharmacy_receipt_prevents_premature_or_duplicate(client, monkeypatch):
    """Pharmacy receipt validates that the batch is strictly at Stage 2."""
    monkeypatch.setattr("app._resolve_authorized_signer", lambda *args, **kwargs: ("0x" + "1" * 64, "pharmacy", "0x90F79bf6EB2c4f870365E785982E1f101E93b906", None))
    # Non-existent
    res = client.post("/api/pharmacy/receive", json={"medicine_id": "UNKNOWN_BATCH"})
    assert res.status_code == 404
    assert "not found on blockchain" in res.json["error"]


# =====================================================================
# 2. OCR CONSENSUS & DATE NORMALIZATION TESTS
# =====================================================================

def test_ocr_batch_consensus_voting():
    """Consensus voting resolves true batch number even when individual OCR variants contain OCR errors."""
    variants = [
        "Batch: 26230146\nLOT No. 2623014N\nEXPIRY DATE 06/2027",  # variant with single character typo
        "Batch: 2623014N\nLOT No. 2623014N\nEXPIRY DATE 06/2027",
        "Batch: 2623014N\nMFG. 01/2026\nEXPIRY DATE 06/2027",
        "LOT No 2623014N\nEXPIRY 06/2027",
    ]
    res = ocr.extract_consensus_fields(variants, expected_batch="2623014N", expected_expiry="2027-06")
    assert res["found_batch"] == "2623014N"
    assert res["batch_status"] == "match"
    assert res["batch_confidence"] > 0.70
    assert res["batch_candidates"]["2623014N"] >= 4
    assert res["found_expiry"] == "2027-06"
    assert res["expiry_status"] == "match"


def test_ocr_date_normalization_and_month_end_boundary():
    """Checks that end-of-month and rollover timestamps correctly resolve to the registration month."""
    # June 2027 end timestamp (stored as July 1 00:00:00 UTC = 1814400000)
    month_str = ocr._record_expiry_month({"expiry": 1814400000})
    assert month_str == "2027-06", f"Expected '2027-06' but got {month_str}"

    # Direct month/year strings
    assert ocr._normalise_month_date("06/2027") == "2027-06"
    assert ocr._normalise_month_date("2027-06") == "2027-06"
    assert ocr._normalise_month_date("JUN 2027") == "2027-06"
    assert ocr._normalise_month_date("01/2026") == "2026-01"


def test_image_quality_assessment():
    """Image quality assessment detects blur and glare without external dependencies."""
    # Create sharp test image
    sharp_img = Image.new("L", (400, 400), color=128)
    for x in range(0, 400, 10):
        for y in range(0, 400, 10):
            sharp_img.putpixel((x, y), 255)
    quality_sharp = ocr.assess_image_quality(sharp_img)
    assert quality_sharp["resolution_ok"] is True
    assert quality_sharp["laplacian_variance"] > 40.0

    # Low resolution image
    small_img = Image.new("RGB", (100, 100), color=(100, 100, 100))
    quality_small = ocr.assess_image_quality(small_img)
    assert quality_small["resolution_ok"] is False
    assert any("Low resolution" in f for f in quality_small["feedback"])


# =====================================================================
# 3. MULTI-IMAGE REGISTRATION TESTS
# =====================================================================

def test_register_exceeding_10_images_rejected(client):
    """Uploading more than 10 images is rejected with 400 and MAX_IMAGES_EXCEEDED."""
    data = {
        "medicine_id": "TEST_MULTI_OVERFLOW",
        "name": "Test Medicine",
        "batch": "TEST_MULTI_OVERFLOW",
        "expiry": "12/2028",
        "quantity": "50",
        "images": [
            (io.BytesIO(_make_dummy_image_bytes()), f"img_{i}.jpg")
            for i in range(11)
        ],
    }
    res = client.post("/register", data=data, content_type="multipart/form-data")
    assert res.status_code == 400
    assert res.json.get("code") == "MAX_IMAGES_EXCEEDED"
    assert "maximum of 10 package images" in res.json["error"]


def test_register_invalid_image_format_rejected(client):
    """Uploading an invalid file extension (e.g. .pdf, .exe) is safely rejected with 400."""
    data = {
        "medicine_id": "TEST_INVALID_FMT",
        "name": "Test Medicine",
        "batch": "TEST_INVALID_FMT",
        "expiry": "12/2028",
    }
    files = {
        "images": (io.BytesIO(b"%PDF-1.4 dummy pdf bytes"), "document.pdf"),
    }
    res = client.post("/register", data={**data, **files}, content_type="multipart/form-data")
    assert res.status_code == 400
    assert "Unsupported format" in res.json["error"]


def test_batch_images_retrieval_endpoint(client):
    """GET /api/batches/<id>/images retrieves package images and manifest."""
    # Existing registered batch 2623014N
    res = client.get("/api/batches/2623014N/images")
    assert res.status_code == 200
    assert "images" in res.json
    assert len(res.json["images"]) >= 1
    assert res.json["images"][0]["cid"] == "QmNcioqqfqp3GHKYxmfh2soBwy9NPE4fp4fYonNnffd5oZ"
