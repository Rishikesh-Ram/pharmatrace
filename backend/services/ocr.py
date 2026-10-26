"""OCR extraction and reference comparison for PharmaTrace with multi-variant consensus and image quality diagnostics."""
from collections import Counter
from datetime import date, datetime, timezone
import logging
import os
import re
import time

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps

log = logging.getLogger("pharmatrace.ocr")

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
    r"\b(?:batch(?:\s*(?:no\.?|number))?|b\.?\s*no\.?|lot(?:(?:\s*no\.?|number))?)"
    r"[\s:.\-]+([A-Z0-9][A-Z0-9/\-]{2,})",
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
    r"\b(\d{1,2})\s*[/.-]\s*(20\d{2}|\d{2,4})\b"
)


def _get_tesseract():
    import pytesseract
    from pathlib import Path

    command = os.getenv("TESSERACT_CMD")
    if not command:
        default_path = Path(r"C:\Program Files\Tesseract-OCR\tesseract.exe")
        if default_path.exists():
            command = str(default_path)

    if command:
        pytesseract.pytesseract.tesseract_cmd = command

    return pytesseract


def assess_image_quality(img: Image.Image) -> dict:
    """Computes blur, glare, lighting, and resolution diagnostics."""
    w, h = img.size
    is_res_ok = w >= 300 and h >= 300

    gray = img.convert("L")
    arr = np.asarray(gray, dtype=np.float32)

    # Blur detection via Laplacian variance
    if arr.shape[0] > 4 and arr.shape[1] > 4:
        lap = arr[1:-1, :-2] + arr[1:-1, 2:] + arr[:-2, 1:-1] + arr[2:, 1:-1] - 4.0 * arr[1:-1, 1:-1]
        lap_var = float(lap.var())
    else:
        lap_var = 0.0

    is_blurry = lap_var < 45.0
    blur_score = max(0.0, min(1.0, lap_var / 120.0))

    # Glare detection: fraction of overexposed pixels (> 248)
    glare_fraction = float((arr > 248).mean())
    has_glare = glare_fraction > 0.12

    # Exposure / lighting
    mean_lum = float(arr.mean())
    if mean_lum < 38.0:
        lighting = "underexposed"
    elif mean_lum > 228.0:
        lighting = "overexposed"
    else:
        lighting = "normal"

    feedback = []
    if not is_res_ok:
        feedback.append(f"Low resolution ({w}x{h} px); at least 300x300 recommended.")
    if is_blurry:
        feedback.append(f"Image may be blurry (sharpness metric {lap_var:.1f}). Hold camera steady.")
    if has_glare:
        feedback.append(f"High reflection/glare detected ({glare_fraction * 100:.1f}% reflective highlight).")
    if lighting == "underexposed":
        feedback.append("Image is dark; improve lighting for clearer text extraction.")

    return {
        "width": w,
        "height": h,
        "resolution_ok": is_res_ok,
        "laplacian_variance": round(lap_var, 1),
        "blur_score": round(blur_score, 2),
        "is_blurry": is_blurry,
        "glare_fraction": round(glare_fraction, 4),
        "has_glare": has_glare,
        "lighting": lighting,
        "quality_acceptable": is_res_ok and (not is_blurry or lap_var > 25.0) and not (has_glare and glare_fraction > 0.25),
        "feedback": feedback,
    }


def _ocr_variants(img: Image.Image, timeout: float = 14.0) -> list[str]:
    """Execute high-yield OCR configurations concurrently with timeout protection."""
    try:
        pytesseract = _get_tesseract()
    except Exception:
        return []

    # Auto-orient based on EXIF
    source = ImageOps.exif_transpose(img).convert("RGB")
    gray = ImageOps.grayscale(source)
    gray = ImageOps.autocontrast(gray)

    # Optimal scaling for Tesseract (avoid 3200px bloat, ensure at least 900px across)
    max_dim = max(gray.size)
    if max_dim > 1400:
        scale = 1400.0 / max_dim
        gray = gray.resize((int(gray.width * scale), int(gray.height * scale)), Image.Resampling.BILINEAR)
    elif max_dim < 700:
        scale = 1100.0 / max_dim
        gray = gray.resize((int(gray.width * scale), int(gray.height * scale)), Image.Resampling.LANCZOS)

    sharp = gray.filter(ImageFilter.SHARPEN)
    contrast = ImageEnhance.Contrast(gray).enhance(1.5)

    tasks = [
        (gray, 6),
        (sharp, 4),
        (contrast, 6),
        (contrast, 4),
        (sharp, 6),
        (gray, 4),
    ]

    def _worker(item):
        variant_img, psm = item
        return pytesseract.image_to_string(variant_img, config=f"--psm {psm}")

    results = []
    try:
        from concurrent.futures import ThreadPoolExecutor, as_completed
        workers = min(4, os.cpu_count() or 4)
        with ThreadPoolExecutor(max_workers=workers) as executor:
            future_map = {executor.submit(_worker, t): t for t in tasks}
            for fut in as_completed(future_map, timeout=timeout):
                try:
                    txt = fut.result()
                    if txt and txt.strip():
                        results.append(txt)
                except Exception:
                    pass
    except Exception as exc:
        log.warning("Concurrent OCR worker timeout or error: %s (returning %d partial results)", exc, len(results))

    return results


def read_text(img: Image.Image) -> str:
    """Returns combined OCR text, or an empty string if unavailable."""
    return "\n".join(_ocr_variants(img))


def _normalise_batch(value: str | None) -> str | None:
    if not value:
        return None
    value = re.sub(r"[^A-Z0-9]", "", value.upper())
    return value or None


def _levenshtein(s1: str, s2: str) -> int:
    """Computes Levenshtein distance between two normalized strings."""
    if s1 == s2:
        return 0
    if len(s1) < len(s2):
        return _levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)

    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row

    return previous_row[-1]


def _is_ocr_confusion_pair(c1: str, c2: str) -> bool:
    """Checks whether two characters are commonly confused by Tesseract on embossed/dot-matrix text."""
    pairs = {
        frozenset({"6", "N"}),
        frozenset({"6", "G"}),
        frozenset({"0", "O"}),
        frozenset({"8", "B"}),
        frozenset({"1", "I"}),
        frozenset({"1", "L"}),
        frozenset({"5", "S"}),
        frozenset({"2", "Z"}),
        frozenset({"D", "0"}),
    }
    return frozenset({c1, c2}) in pairs


def _normalise_month_date(value: str | None) -> str | None:
    """Normalize ISO dates (YYYY-MM-DD), year-month (YYYY-MM), month/year and numeric month/year to YYYY-MM."""
    if not value:
        return None

    value = value.strip().upper()

    # Full ISO date: YYYY-MM-DD
    iso_match = re.search(r"\b(20\d{2})-(\d{1,2})-(\d{1,2})\b", value)
    if iso_match:
        year, month, day = map(int, iso_match.groups())
        try:
            date(year, month, day)
            return f"{year:04d}-{month:02d}"
        except ValueError:
            return None

    # Year-month: YYYY-MM or YYYY/MM
    ym_match = re.search(r"\b(20\d{2})[-/.](\d{1,2})\b", value)
    if ym_match:
        year, month = int(ym_match.group(1)), int(ym_match.group(2))
        if 1 <= month <= 12:
            return f"{year:04d}-{month:02d}"

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


def _extract_expiry_candidates(variants: list[str]) -> Counter:
    """Extract expiry month/year candidates with occurrence frequency across all OCR variants."""
    candidates = Counter()
    for text in variants:
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        for i, line in enumerate(lines):
            compact = re.sub(r"[^A-Z]", "", line.upper())
            expiry_label = any(label in compact for label in ("EXP", "EXPIRY", "EXPRY", "VAL"))
            if not expiry_label:
                continue

            for candidate in lines[i:i + 3]:
                norm = _normalise_month_date(candidate)
                if norm:
                    candidates[norm] += 1
    return candidates


def _extract_batch_candidates(variants: list[str]) -> Counter:
    """Extract batch/lot candidates with frequency across all OCR variants."""
    candidates = Counter()
    for text in variants:
        for m in _BATCH_RE.finditer(text):
            raw = m.group(1).strip()
            norm = _normalise_batch(raw)
            if norm and len(norm) >= 3:
                candidates[norm] += 1
    return candidates


def _extract_mfg_candidates(variants: list[str]) -> Counter:
    """Extract manufacturing month/year candidates with occurrence frequency across all OCR variants."""
    candidates = Counter()
    for text in variants:
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        for i, line in enumerate(lines):
            compact = re.sub(r"[^A-Z]", "", line.upper())
            mfg_label = any(label in compact for label in ("MFG", "MFD", "MANUF", "PKD", "PACKED", "MFR"))
            if not mfg_label:
                continue

            for candidate in lines[i:i + 3]:
                norm = _normalise_month_date(candidate)
                if norm:
                    candidates[norm] += 1
    return candidates


def _record_expiry_month(record: dict) -> str | None:
    value = record.get("expiry")
    if value is None:
        return None

    # Blockchain adapters may expose a Unix timestamp.
    if isinstance(value, (int, float)):
        try:
            dt = datetime.fromtimestamp(value, tz=timezone.utc)
            # If timestamp was registered at 00:00:00 on the 1st of the next month (e.g. from month-end + 1 day),
            # subtracting 12 hours yields the actual registration month.
            if dt.day == 1 and dt.hour == 0 and dt.minute == 0:
                dt = datetime.fromtimestamp(value - 43200, tz=timezone.utc)
            value = dt.date().isoformat()
        except (OverflowError, OSError, ValueError):
            return None

    # Handle ISO dates and month/year strings.
    return _normalise_month_date(str(value))


def extract_consensus_fields(
    variants: list[str],
    expected_batch: str | None = None,
    expected_expiry: str | None = None,
    expected_mfg: str | None = None,
) -> dict:
    """Extract fields using multi-variant consensus and fuzzy matching against expected identifiers."""
    batch_counter = _extract_batch_candidates(variants)
    expiry_counter = _extract_expiry_candidates(variants)
    mfg_counter = _extract_mfg_candidates(variants)

    norm_exp_batch = _normalise_batch(expected_batch)
    norm_exp_expiry = _normalise_month_date(expected_expiry)
    norm_exp_mfg = _normalise_month_date(expected_mfg)

    # 1. Batch consensus resolution
    found_batch = None
    batch_status = "needs_review"
    batch_confidence = 0.0
    batch_evidence = ""

    if batch_counter:
        total_batch_votes = sum(batch_counter.values())

        if norm_exp_batch and norm_exp_batch in batch_counter:
            found_batch = norm_exp_batch
            votes = batch_counter[norm_exp_batch]
            batch_confidence = round(votes / total_batch_votes, 2)
            batch_status = "match"
            batch_evidence = f"Found exact match with {votes}/{total_batch_votes} variant consensus votes."
        elif norm_exp_batch:
            # Check for close OCR confusion (e.g. '6' instead of 'N' on dot-matrix)
            fuzzy_matched = False
            for cand, count in batch_counter.most_common():
                if len(cand) == len(norm_exp_batch) and _levenshtein(cand, norm_exp_batch) == 1:
                    diffs = [(c1, c2) for c1, c2 in zip(cand, norm_exp_batch) if c1 != c2]
                    if diffs and _is_ocr_confusion_pair(diffs[0][0], diffs[0][1]):
                        found_batch = cand
                        batch_status = "match"
                        batch_confidence = 0.85
                        batch_evidence = f"Matched registered batch via OCR character normalization ('{cand}' -> '{norm_exp_batch}')."
                        fuzzy_matched = True
                        break

            if not fuzzy_matched:
                top_cand, top_votes = batch_counter.most_common(1)[0]
                found_batch = top_cand
                batch_confidence = round(top_votes / total_batch_votes, 2)
                if top_votes >= 2 or batch_confidence >= 0.5:
                    batch_status = "mismatch"
                    batch_evidence = f"Detected conflicting batch '{top_cand}' with {top_votes}/{total_batch_votes} votes."
                else:
                    batch_status = "needs_review"
                    batch_evidence = f"Ambiguous OCR read '{top_cand}' ({top_votes}/{total_batch_votes} votes)."
        else:
            top_cand, top_votes = batch_counter.most_common(1)[0]
            found_batch = top_cand
            batch_confidence = round(top_votes / total_batch_votes, 2)
            batch_status = "needs_review"
            batch_evidence = f"Detected '{top_cand}' by consensus."
    else:
        batch_evidence = "No batch/lot numbers detected across OCR variants."

    # 2. Expiry consensus resolution
    found_expiry = None
    expiry_status = "needs_review"
    expiry_confidence = 0.0
    expiry_evidence = ""

    if expiry_counter:
        total_exp_votes = sum(expiry_counter.values())
        if norm_exp_expiry and norm_exp_expiry in expiry_counter:
            found_expiry = norm_exp_expiry
            votes = expiry_counter[norm_exp_expiry]
            expiry_confidence = round(votes / total_exp_votes, 2)
            expiry_status = "match"
            expiry_evidence = f"Matched expiry with {votes}/{total_exp_votes} consensus votes."
        else:
            top_exp, top_votes = expiry_counter.most_common(1)[0]
            found_expiry = top_exp
            expiry_confidence = round(top_votes / total_exp_votes, 2)
            if norm_exp_expiry:
                expiry_status = "mismatch" if top_votes >= 2 else "needs_review"
                expiry_evidence = f"Detected expiry '{top_exp}' vs registered '{norm_exp_expiry}'."
            else:
                expiry_status = "needs_review"
                expiry_evidence = f"Detected expiry '{top_exp}'."
    else:
        expiry_evidence = "No expiry date detected near expiry label."

    # 3. Manufacturing date consensus resolution
    found_mfg = None
    mfg_status = "not_provided"
    mfg_confidence = 0.0
    mfg_evidence = ""

    if mfg_counter:
        total_mfg_votes = sum(mfg_counter.values())
        if norm_exp_mfg and norm_exp_mfg in mfg_counter:
            found_mfg = norm_exp_mfg
            votes = mfg_counter[norm_exp_mfg]
            mfg_confidence = round(votes / total_mfg_votes, 2)
            mfg_status = "match"
            mfg_evidence = f"Matched manufacturing date with {votes}/{total_mfg_votes} votes."
        else:
            top_mfg, top_votes = mfg_counter.most_common(1)[0]
            found_mfg = top_mfg
            mfg_confidence = round(top_votes / total_mfg_votes, 2)
            if norm_exp_mfg:
                mfg_status = "mismatch" if top_votes >= 2 else "needs_review"
                mfg_evidence = f"Detected mfg date '{top_mfg}' vs registered '{norm_exp_mfg}'."
            else:
                mfg_status = "detected"
                mfg_evidence = f"Detected mfg date '{top_mfg}'."
    else:
        mfg_evidence = "No manufacturing date detected."

    return {
        "found_batch": found_batch,
        "batch_status": batch_status,
        "batch_confidence": batch_confidence,
        "batch_evidence": batch_evidence,
        "batch_candidates": dict(batch_counter),
        "found_expiry": found_expiry,
        "expiry_status": expiry_status,
        "expiry_confidence": expiry_confidence,
        "expiry_evidence": expiry_evidence,
        "expiry_candidates": dict(expiry_counter),
        "found_mfg": found_mfg,
        "mfg_status": mfg_status,
        "mfg_confidence": mfg_confidence,
        "mfg_evidence": mfg_evidence,
        "mfg_candidates": dict(mfg_counter),
    }


def extract_fields(text: str) -> dict:
    """Legacy helper for backward compatibility."""
    batch_match = _BATCH_RE.search(text)
    expiry = _extract_expiry_candidates([text]).most_common(1)
    return {
        "batch": batch_match.group(1).strip() if batch_match else None,
        "expiry": expiry[0][0] if expiry else None,
    }


def analyse(img: Image.Image, record: dict) -> dict:
    """Extract package fields with multi-variant consensus, image quality diagnostics, and reference comparison."""
    t_start = time.perf_counter()

    # Stage 1: Image Quality Assessment
    quality = assess_image_quality(img)
    t_quality = time.perf_counter() - t_start

    # Stage 2: Concurrent OCR Variant Execution
    t_ocr_start = time.perf_counter()
    variants = _ocr_variants(img)
    t_ocr = time.perf_counter() - t_ocr_start
    combined_text = "\n".join(variants)

    # Stage 3: Consensus Voting & Field Extraction
    expected_batch = record.get("batch")
    expected_expiry = _record_expiry_month(record)
    expected_mfg = _normalise_month_date(record.get("mfg") or record.get("mfg_date"))

    t_consensus_start = time.perf_counter()
    consensus = extract_consensus_fields(
        variants,
        expected_batch=expected_batch,
        expected_expiry=expected_expiry,
        expected_mfg=expected_mfg,
    )
    t_consensus = time.perf_counter() - t_consensus_start
    t_total = time.perf_counter() - t_start

    # Name and Manufacturer matching against text
    low = combined_text.lower()
    expected_name = str(record.get("name") or "").strip().lower()
    name_match = bool(expected_name and expected_name in low)

    expected_mfr = str(record.get("manufacturer_name") or record.get("org_name") or "").strip().lower()
    mfr_match = bool(expected_mfr and len(expected_mfr) > 3 and expected_mfr in low)

    batch_status = consensus["batch_status"]
    expiry_status = consensus["expiry_status"]
    mfg_status = consensus["mfg_status"]

    timing = {
        "quality_ms": round(t_quality * 1000, 1),
        "ocr_ms": round(t_ocr * 1000, 1),
        "consensus_ms": round(t_consensus * 1000, 1),
        "total_ms": round(t_total * 1000, 1),
        "variants_count": len(variants),
    }

    log.info(
        "[OCR] Completed in %.2fs (quality=%.1fms, ocr=%.1fms [%d variants], consensus=%.1fms). Batch: %s (%s, conf=%.2f), Expiry: %s (%s, conf=%.2f)",
        t_total,
        timing["quality_ms"],
        timing["ocr_ms"],
        len(variants),
        timing["consensus_ms"],
        consensus["found_batch"],
        batch_status,
        consensus["batch_confidence"],
        consensus["found_expiry"],
        expiry_status,
        consensus["expiry_confidence"],
    )

    return {
        "ocr_available": bool(combined_text.strip()),
        "found_batch": consensus["found_batch"],
        "found_expiry": consensus["found_expiry"],
        "found_mfg": consensus["found_mfg"],
        "name_match": name_match,
        "mfr_match": mfr_match,
        "batch_match": batch_status == "match",
        "batch_status": batch_status,
        "batch_confidence": consensus["batch_confidence"],
        "batch_evidence": consensus["batch_evidence"],
        "batch_candidates": consensus["batch_candidates"],
        "expiry_match": expiry_status == "match",
        "expiry_status": expiry_status,
        "expiry_confidence": consensus["expiry_confidence"],
        "expiry_evidence": consensus["expiry_evidence"],
        "expiry_candidates": consensus["expiry_candidates"],
        "mfg_match": mfg_status == "match",
        "mfg_status": mfg_status,
        "mfg_confidence": consensus["mfg_confidence"],
        "mfg_evidence": consensus["mfg_evidence"],
        "expected_expiry_month": expected_expiry,
        "expected_mfg_month": expected_mfg,
        "needs_review": (batch_status == "needs_review" or expiry_status == "needs_review"),
        "quality": quality,
        "timing": timing,
    }



def extract_package_fields(img: Image.Image, timeout: float = 8.5) -> dict:
    """
    Extracts the 5 printed medicine package fields:
    1. Medicine name
    2. Batch number
    3. Manufacturer name
    4. Manufacturing date (MM/YYYY)
    5. Expiry date (MM/YYYY)
    Includes image quality diagnostics and checks for matching on-chain records.
    """
    t_start = time.perf_counter()
    quality = assess_image_quality(img)

    # Concurrently execute high-yield OCR configurations with timeout protection
    variants = _ocr_variants(img, timeout=timeout)
    combined_text = "\n".join(variants)

    batch_candidates = _extract_batch_candidates(variants)
    mfg_candidates = _extract_mfg_candidates(variants)
    expiry_candidates = _extract_expiry_candidates(variants)

    def _to_mmyyyy(val: str | None) -> str | None:
        if not val:
            return None
        parts = val.split("-")
        if len(parts) == 2:
            return f"{parts[1]}/{parts[0]}"
        return val

    # 1. Batch number
    top_batch = None
    if batch_candidates:
        top_batch = batch_candidates.most_common(1)[0][0]

    # 2. Manufacturing date
    top_mfg = None
    if mfg_candidates:
        top_mfg = _to_mmyyyy(mfg_candidates.most_common(1)[0][0])

    # 3. Expiry date
    top_exp = None
    if expiry_candidates:
        top_exp = _to_mmyyyy(expiry_candidates.most_common(1)[0][0])

    # 4. Medicine name matching
    matched_name = None
    registered_batches = []
    try:
        from services import blockchain
        registered_batches = blockchain.get_all_batches()
    except Exception:
        pass

    low = combined_text.lower()
    for b in registered_batches:
        bname = (b.get("name") or b.get("medicine_name") or "").strip()
        if bname:
            first_word = bname.split()[0].lower()
            if bname.lower() in low or (len(first_word) >= 4 and first_word in low):
                matched_name = bname
                break

    if not matched_name:
        ignore_keywords = [
            "BATCH", "B.NO", "LOT", "EXP", "MFG", "MFD", "MRP", "RS", "INCL",
            "TAXES", "STORAGE", "KEEP", "STORE", "DOSAGE", "COMPOSITION",
            "EACH", "CONTAINS", "WARNING", "SCHEDULE", "PHARMACEUTICALS",
            "PVT", "LTD", "LIMITED", "FOR", "USE", "ONLY", "OUT OF REACH"
        ]
        for line in combined_text.splitlines():
            cleaned = line.strip()
            if len(cleaned) < 3 or len(cleaned) > 40:
                continue
            up = cleaned.upper()
            if any(k in up for k in ignore_keywords):
                continue
            alpha_ratio = sum(c.isalpha() for c in cleaned) / len(cleaned)
            if alpha_ratio > 0.65:
                matched_name = cleaned
                break

    # 5. Manufacturer name matching
    matched_mfr = None
    for b in registered_batches:
        mfr_name = b.get("manufacturer_name") or ""
        if mfr_name and len(mfr_name) > 3 and mfr_name.lower() in low:
            matched_mfr = mfr_name
            break

    if not matched_mfr:
        mfr_re = re.compile(
            r"\b(?:mfd\.?\s*by|mfg\.?\s*by|manufactured\s+by|marketed\s+by|packed\s+by)"
            r"[\s:.\-]+([A-Za-z0-9\s,\.\-&]{3,40})(?=\n|$|\.\s|[0-9]{6}|Plot|Phase|Industrial)",
            re.I
        )
        mfr_match = mfr_re.search(combined_text)
        if mfr_match:
            matched_mfr = mfr_match.group(1).strip()
        else:
            for line in combined_text.splitlines():
                cl = line.strip()
                if any(w in cl.lower() for w in ["laboratories", "pharma ", "pharmaceuticals", "ltd", "limited"]):
                    if len(cl) <= 50 and not any(k in cl.upper() for k in ["EXP", "MFG", "BATCH", "MRP"]):
                        matched_mfr = cl
                        break

    # Look up matching on-chain record if batch or name was extracted
    matching_record = None
    try:
        from services import blockchain
        if top_batch:
            matching_record = blockchain.find_record(top_batch)
        if not matching_record and matched_name:
            for b in registered_batches:
                if (b.get("name") or "").strip().lower() == matched_name.lower():
                    matching_record = b
                    break
    except Exception:
        pass

    duration = time.perf_counter() - t_start

    return {
        "success": True,
        "fields": {
            "medicine_name": matched_name,
            "batch_number": top_batch,
            "manufacturer_name": matched_mfr,
            "mfg_date": top_mfg,
            "expiry_date": top_exp,
        },
        "raw_text": combined_text,
        "has_matching_batch": bool(matching_record),
        "matching_batch_id": (matching_record.get("id") or matching_record.get("batch")) if matching_record else None,
        "matching_record": matching_record,
        "quality": quality,
        "timing_ms": round(duration * 1000, 1),
    }
