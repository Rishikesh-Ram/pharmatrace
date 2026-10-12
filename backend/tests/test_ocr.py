from services.ocr import extract_fields


def test_extracts_batch_and_expiry():
    text = "Paracetamol 500mg\nB.No: AB1234\nEXP: 08/2027"
    f = extract_fields(text)
    assert f["batch"] == "AB1234"
    assert f["expiry"] == "08/2027"


def test_missing_fields_are_none():
    assert extract_fields("nothing useful") == {"batch": None, "expiry": None}
