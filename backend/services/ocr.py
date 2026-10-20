
"""OCR extraction and reference comparison for PharmaTrace."""
import os
import re
from datetime import date, datetime, timezone

from PIL import Image, ImageEnhance, ImageFilter, ImageOps


MONTHS = {
    "JAN": 1, "JANUARY": 1,
    "FEB": 2, "FEBRUARY": 2,
    "MAR": 3, "MARCH": 3,
    "APR": 4, "APRIL": 4,
    "MAY": 5,
    "JUN": 6, "JUNE": 6,
    "JUL": 7, "JULY": 7,
    "AUG": 8, "AUGUST": 8,
    "SEP": 9, "SEPT": 9, "SEPTEMBER": 9,
    "OCT": 10, "OCTOBER": 10,
    "NOV": 11, "NOVEMBER": 11,
    "DEC": 12, "DECEMBER": 12,
}

_BATCH_RE = re.compile(
    r"(?:batch\s*(?:no\.?|number)?|b\.?\s*no\.?|lot)"
    r"\s*[:.\-]?\s*([A-Z0-9][A-Z0-9/\-]{2,})",
    re.I,
)

_MONTH_DATE_RE = re.compile(
    r"\b(JAN(?:UARY)?|FEB(?:RUARY)?|MAR(?:CH)?|"
    r"APR(?:IL)?|MAY|JUN(?:E)?|JUL(?:Y)?|"
    r"AUG(?:UST)?|SEP(?:T(?:EMBER)?)?|"
    r"OCT(?:OBER)?|NOV(?:EMBER)?|DEC(?:EMBER)?)"
    r"\.?\s*[-./ ]?\s*(20\d{2}|\d{2})\b",
    re.I,
)

_NUMERIC_DATE_RE = re.compile(
    r"\b(\d{1,2})\s*[/.-]\s*(\d{2,4})\b"
)



def _get_tesseract():
    import pytesseract
    from pathlib import Path

    command = os.getenv("TESSERACT_CMD")
    if not command:
        default_path = Path(
            r"C:\Program Files\Tesseract-OCR\tesseract.exe"
        )
        if default_path.exists():
            command = str(default_path)

    if command:
        pytesseract.pytesseract.tesseract_cmd = command

    return pytesseract



def _ocr_variants(img: Image.Image) -> list[str]:
    """Try several OCR configurations; retain all results."""
    try:
        pytesseract = _get_tesseract()
    except Exception:
        return []

    source = img.convert("RGB")
    gray = ImageOps.grayscale(source)
    gray = ImageOps.autocontrast(gray)

    if max(gray.size) < 1800:
        gray = gray.resize(
            (gray.width * 2, gray.height * 2)
        )

    sharp = gray.filter(ImageFilter.SHARPEN)
    contrast = ImageEnhance.Contrast(gray).enhance(1.6)

    results = []
    for variant in (gray, sharp, contrast):
        for psm in (6, 11):
            try:
                text = pytesseract.image_to_string(
                    variant,
                    config=f"--psm {psm}",
                )
                if text.strip():
                    results.append(text)
            except Exception:
                continue

    return results


def read_text(img: Image.Image) -> str:
    """Returns combined OCR text, or an empty string if unavailable."""
    return "\n".join(_ocr_variants(img))


def _normalise_batch(value: str | None) -> str | None:
    if not value:
        return None
    value = re.sub(r"[^A-Z0-9]", "", value.upper())
    return value or None



def _normalise_month_date(value: str | None) -> str | None:
    """Normalize ISO dates, month/year and numeric month/year to YYYY-MM."""
    if not value:
        return None

    value = value.strip().upper()

    # ISO date must be checked BEFORE month/year patterns.
    iso_match = re.search(
        r"\b(20\d{2})-(\d{1,2})-(\d{1,2})\b", value
    )
    if iso_match:
        year, month, day = map(int, iso_match.groups())
        try:
            date(year, month, day)
            return f"{year:04d}-{month:02d}"
        except ValueError:
            return None

    month_match = _MONTH_DATE_RE.search(value)
    if month_match:
        month_text, year_text = month_match.groups()
        month = MONTHS.get(month_text.upper())
        if month is None:
            month = MONTHS.get(month_text.upper()[:3])
        if month is None:
            return None

        year = int(year_text)
        if year < 100:
            year += 2000 if year < 70 else 1900

        return f"{year:04d}-{month:02d}"

    numeric_match = _NUMERIC_DATE_RE.search(value)
    if numeric_match:
        month, year = numeric_match.groups()
        month, year = int(month), int(year)
        if year < 100:
            year += 2000 if year < 70 else 1900
        if 1 <= month <= 12:
            return f"{year:04d}-{month:02d}"

    return None




def _extract_expiry(text: str) -> str | None:
    """Extract an expiry month/year without trusting incomplete OCR dates."""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    candidates = []

    for i, line in enumerate(lines):
        compact = re.sub(r"[^A-Z]", "", line.upper())

        expiry_label = any(
            label in compact
            for label in ("EXP", "EXPIRY", "EXPRY")
        )

        if not expiry_label:
            continue

        # Check the labelled line and the next two lines.
        for candidate in lines[i:i + 3]:
            normalized = _normalise_month_date(candidate)
            if normalized and normalized not in candidates:
                candidates.append(normalized)

    # Only accept a unique date found near an expiry label.
    if len(candidates) == 1:
        return candidates[0]

    return None



def extract_fields(text: str) -> dict:
    batch_match = _BATCH_RE.search(text)
    expiry = _extract_expiry(text)

    return {
        "batch": batch_match.group(1).strip() if batch_match else None,
        "expiry": expiry,
    }


def _record_expiry_month(record: dict) -> str | None:
    value = record.get("expiry")
    if value is None:
        return None

    # Blockchain adapters may expose a Unix timestamp.
    if isinstance(value, (int, float)):
        try:
            value = datetime.fromtimestamp(
                value, tz=timezone.utc
            ).date().isoformat()
        except (OverflowError, OSError, ValueError):
            return None

    # Handle ISO dates and month/year strings.
    return _normalise_month_date(str(value))


def _field_status(found: str | None, expected: str | None,
                  normalizer) -> str:
    if not found or not expected:
        return "needs_review"

    actual_normalized = normalizer(found)
    expected_normalized = normalizer(expected)

    if not actual_normalized or not expected_normalized:
        return "needs_review"

    return (
        "match"
        if actual_normalized == expected_normalized
        else "mismatch"
    )


def analyse(img: Image.Image, record: dict) -> dict:
    """Extract package fields and compare them with the registered record."""
    texts = _ocr_variants(img)
    text = "\n".join(texts)
    found = extract_fields(text)

    expected_batch = record.get("batch")
    expected_expiry = _record_expiry_month(record)

    batch_status = _field_status(
        found["batch"], expected_batch, _normalise_batch
    )
    expiry_status = _field_status(
        found["expiry"], expected_expiry, _normalise_month_date
    )

    low = text.lower()
    expected_name = str(record.get("name") or "").strip().lower()

    return {
        "ocr_available": bool(text.strip()),
        "found_batch": found["batch"],
        "found_expiry": found["expiry"],
        "name_match": bool(expected_name and expected_name in low),
        "batch_match": batch_status == "match",
        "batch_status": batch_status,
        "expiry_status": expiry_status,
        "expected_expiry_month": expected_expiry,
        "needs_review": (
            batch_status == "needs_review"
            or expiry_status == "needs_review"
        ),
    }
