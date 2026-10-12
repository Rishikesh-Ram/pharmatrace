"""Tesseract OCR: reads name, batch and expiry from the pack photo."""
import os
import re

from PIL import Image

_BATCH_RE = re.compile(r"(?:batch\s*(?:no\.?|number)?|b\.?\s*no\.?|lot)\s*[:.\-]?\s*([A-Z0-9\-/]{3,})", re.I)
_EXPIRY_RE = re.compile(r"(?:exp(?:iry)?\.?(?:\s*date)?)\s*[:.\-]?\s*([0-9]{1,2}\s*[/\-.]\s*[0-9]{2,4}|[A-Za-z]{3,9}\.?\s*[0-9]{2,4})", re.I)


def read_text(img: Image.Image) -> str:
    """Returns raw OCR text, or '' if Tesseract is unavailable."""
    try:
        import pytesseract
        if os.getenv("TESSERACT_CMD"):
            pytesseract.pytesseract.tesseract_cmd = os.environ["TESSERACT_CMD"]
        return pytesseract.image_to_string(img)
    except Exception:
        return ""


def extract_fields(text: str) -> dict:
    batch = _BATCH_RE.search(text)
    expiry = _EXPIRY_RE.search(text)
    return {
        "batch": batch.group(1).strip() if batch else None,
        "expiry": re.sub(r"\s+", "", expiry.group(1)) if expiry else None,
    }


def analyse(img: Image.Image, record: dict) -> dict:
    """Runs OCR and compares what it finds with the blockchain record."""
    text = read_text(img)
    low = text.lower()
    found = extract_fields(text)
    return {
        "ocr_available": bool(text.strip()),
        "found_batch": found["batch"],
        "found_expiry": found["expiry"],
        "name_match": bool(record.get("name")) and record["name"].lower() in low,
        "batch_match": bool(record.get("batch")) and record["batch"].lower() in low,
    }
