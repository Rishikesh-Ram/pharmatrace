from app import decide


def test_no_record_is_unverified():
    assert decide(False, True, True) == "Unverified"


def test_both_pass_is_verified():
    assert decide(True, True, True) == "Verified"


def test_one_pass_is_suspicious():
    assert decide(True, True, False) == "Suspicious"
    assert decide(True, False, True) == "Suspicious"


def test_both_fail_is_unverified():
    assert decide(True, False, False) == "Unverified"
