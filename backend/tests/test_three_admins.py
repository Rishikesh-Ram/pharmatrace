"""Verification suite for PharmaTrace's Three Individually Authenticated Administrators:
- Lekshmy (admin_L / admin_L@gmail.com)
- Meenakshi (admin_M / admin_M@gmail.com)
- Rishi (admin_R / admin_R@gmail.com)

Tests:
1. Valid authentication for all 3 administrators.
2. Cross-account negative test cases (email, username, password mismatches).
3. Non-admin role mismatch protections.
4. Protected admin endpoints & token resolution.
5. Non-admin access denial to administrator endpoints.
6. Public admin registration & bootstrap blocks.
7. Provisioning idempotency (no password reset, no duplicates).
8. Clean state preservation (0 supply-chain orgs, 0 batches).
"""
import os
import sys
from pathlib import Path

backend_dir = str(Path(__file__).resolve().parent.parent)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app import app
from services import auth, blockchain


def test_three_individually_authenticated_admins():
    client = app.test_client()

    print("=" * 70)
    print("PHARMATRACE: THREE INDIVIDUALLY AUTHENTICATED ADMINISTRATORS TEST")
    print("=" * 70)

    # 1. Clean State Check
    res_users = client.get("/api/users")
    assert res_users.status_code == 200
    assert res_users.json["organization_count"] == 0, "Clean install must have 0 supply-chain organizations"
    assert res_users.json["organizations"] == []

    res_batches = client.get("/api/batches")
    assert res_batches.status_code == 200
    assert res_batches.json["count"] == 0, "Clean install must have 0 medicine batches"

    res_status = client.get("/api/auth/admin-status")
    assert res_status.status_code == 200
    assert res_status.json["admin_provisioned"] is True
    print("[PASS] 1. Initial clean state verified (0 organizations, 0 batches, admin provisioned).")

    # 2. Public Admin Registration and Bootstrap are permanently disabled
    res_pub = client.post("/api/register-user", json={
        "role": "admin",
        "name": "Rogue Admin",
    })
    assert res_pub.status_code == 403
    assert res_pub.json["code"] == "ADMIN_SIGNUP_FORBIDDEN"

    res_boot = client.post("/api/auth/bootstrap-admin", json={
        "username": "rogue_admin",
        "email": "rogue@admin.local",
        "password": "Password123",
    })
    assert res_boot.status_code == 403
    assert res_boot.json["code"] == "ADMIN_ALREADY_PROVISIONED"
    print("[PASS] 2. Public Admin registration and bootstrap endpoints blocked.")

    # 3. Valid Login for each of the three administrators
    admin_creds = [
        ("Lekshmy", "admin_L@gmail.com", "admin_L", "adminLekshmy"),
        ("Meenakshi", "admin_M@gmail.com", "admin_M", "adminMeenakshi"),
        ("Rishi", "admin_R@gmail.com", "admin_R", "adminRishi"),
    ]

    tokens = {}

    for name, email, user, pw in admin_creds:
        res = client.post("/api/auth/login", json={
            "email": email,
            "username": user,
            "password": pw,
            "expected_role": "admin",
        })
        assert res.status_code == 200, f"Login failed for {name}: {res.json}"
        data = res.json
        assert data["success"] is True
        assert data["token"]
        assert data["user"]["role"] == "admin"
        assert data["user"]["username"].lower() == user.lower()
        assert data["user"]["email"].lower() == email.lower()
        tokens[user] = data["token"]

        # Validate with /api/auth/me
        res_me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {data['token']}"})
        assert res_me.status_code == 200
        assert res_me.json["user"]["username"].lower() == user.lower()
        assert res_me.json["user"]["name"] == name
        print(f"[PASS] 3. Valid authentication confirmed for {name} ({user} | {email}).")

    # 4. Cross-Account Negative Cases (Email + Username Mismatch)
    # 4a. Lekshmy's email with Meenakshi's username
    res_mismatch_1 = client.post("/api/auth/login", json={
        "email": "admin_L@gmail.com",
        "username": "admin_M",
        "password": "adminLekshmy",
        "expected_role": "admin",
    })
    assert res_mismatch_1.status_code == 401
    assert res_mismatch_1.json["code"] == "CREDENTIAL_MISMATCH"

    res_mismatch_2 = client.post("/api/auth/login", json={
        "email": "admin_L@gmail.com",
        "username": "admin_M",
        "password": "adminMeenakshi",
        "expected_role": "admin",
    })
    assert res_mismatch_2.status_code == 401
    assert res_mismatch_2.json["code"] == "CREDENTIAL_MISMATCH"

    # 4b. Meenakshi's email with Rishi's username
    res_mismatch_3 = client.post("/api/auth/login", json={
        "email": "admin_M@gmail.com",
        "username": "admin_R",
        "password": "adminMeenakshi",
        "expected_role": "admin",
    })
    assert res_mismatch_3.status_code == 401
    assert res_mismatch_3.json["code"] == "CREDENTIAL_MISMATCH"

    # 4c. Rishi's email with Lekshmy's username
    res_mismatch_4 = client.post("/api/auth/login", json={
        "email": "admin_R@gmail.com",
        "username": "admin_L",
        "password": "adminRishi",
        "expected_role": "admin",
    })
    assert res_mismatch_4.status_code == 401
    assert res_mismatch_4.json["code"] == "CREDENTIAL_MISMATCH"
    print("[PASS] 4. Cross-account email/username mismatches rejected (CREDENTIAL_MISMATCH).")

    # 5. Cross-Account Negative Cases (Password Mismatches)
    # Lekshmy credentials with Meenakshi's password
    res_pw_mismatch_1 = client.post("/api/auth/login", json={
        "email": "admin_L@gmail.com",
        "username": "admin_L",
        "password": "adminMeenakshi",
        "expected_role": "admin",
    })
    assert res_pw_mismatch_1.status_code == 401
    assert res_pw_mismatch_1.json["code"] == "INVALID_CREDENTIALS"

    # Meenakshi credentials with Rishi's password
    res_pw_mismatch_2 = client.post("/api/auth/login", json={
        "email": "admin_M@gmail.com",
        "username": "admin_M",
        "password": "adminRishi",
        "expected_role": "admin",
    })
    assert res_pw_mismatch_2.status_code == 401
    assert res_pw_mismatch_2.json["code"] == "INVALID_CREDENTIALS"

    # Rishi credentials with Lekshmy's password
    res_pw_mismatch_3 = client.post("/api/auth/login", json={
        "email": "admin_R@gmail.com",
        "username": "admin_R",
        "password": "adminLekshmy",
        "expected_role": "admin",
    })
    assert res_pw_mismatch_3.status_code == 401
    assert res_pw_mismatch_3.json["code"] == "INVALID_CREDENTIALS"
    print("[PASS] 5. Cross-account password mismatches rejected (INVALID_CREDENTIALS).")

    # 6. Role Mismatch Protection
    # Admin attempting to sign in as Manufacturer
    res_role_mismatch = client.post("/api/auth/login", json={
        "identifier": "admin_L@gmail.com",
        "password": "adminLekshmy",
        "expected_role": "manufacturer",
    })
    assert res_role_mismatch.status_code == 403
    assert res_role_mismatch.json["code"] == "ROLE_MISMATCH"
    print("[PASS] 6. Cross-role authentication blocks verified (ROLE_MISMATCH).")

    # 7. Non-Admin Endpoint Protection & Unauthorized Access Denial
    # 7a. Invalid bearer token rejected with 401
    res_bad_token = client.post("/api/approve-user", headers={"Authorization": "Bearer bad:token"}, json={
        "target": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
        "approver_role": "admin",
    })
    assert res_bad_token.status_code == 401
    assert res_bad_token.json["code"] == "UNAUTHORIZED"

    # 7b. Non-admin session token attempting to perform admin operations rejected with 401/403
    mfr_token = auth._issue_token("0x70997970c51812dc3a010c7d01b50e0d17dc79c8", "manufacturer", "test_mfr")
    res_non_admin = client.post("/api/approve-user", headers={"Authorization": f"Bearer {mfr_token}"}, json={
        "target": "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
        "approver_role": "admin",
    })
    assert res_non_admin.status_code in (401, 403)
    assert res_non_admin.json["code"] in ("UNAUTHORIZED", "UNAUTHORIZED_ROLE")
    print("[PASS] 7. Unauthorized and non-admin access to admin endpoints blocked (401/403).")

    # 8. Idempotency Check: Rerunning provisioning does not reset passwords
    for name, email, user, pw in admin_creds:
        rec, created = auth.provision_admin_account(
            username=user,
            email=email,
            password="NewRoguePassword999",  # Attempt to overwrite password
            name=name,
        )
        assert created is False, "Re-provisioning existing administrator must return created=False"

        # Confirm the ORIGINAL password still works!
        res_still_works = client.post("/api/auth/login", json={
            "email": email,
            "username": user,
            "password": pw,
            "expected_role": "admin",
        })
        assert res_still_works.status_code == 200, f"Original password failed after re-provision for {user}"

        # Confirm the rogue password is NOT accepted
        res_rogue = client.post("/api/auth/login", json={
            "email": email,
            "username": user,
            "password": "NewRoguePassword999",
            "expected_role": "admin",
        })
        assert res_rogue.status_code == 401
    print("[PASS] 8. Provisioning idempotency confirmed: existing passwords were not modified.")

    print("\n" + "=" * 70)
    print("ALL THREE ADMINISTRATOR ACCOUNTS VERIFIED SUCCESSFULLY (8/8)!")
    print("=" * 70)


if __name__ == "__main__":
    test_three_individually_authenticated_admins()
