"""Server-side authentication, password hashing, and session token management for PharmaTrace.

Note on architecture:
- Passwords are never stored in plaintext; all credentials use salted PBKDF2-SHA256 hashes via Werkzeug.
- Session tokens are HMAC-SHA256 signed server tokens validated on protected endpoints.
- Normal application startup begins with a clean credential store (no pre-seeded demo organizations).
- The initial Administrator account can be provisioned once via environment variables
  (PHARMATRACE_ADMIN_USERNAME, PHARMATRACE_ADMIN_EMAIL, PHARMATRACE_ADMIN_PASSWORD),
  the CLI script `backend/scripts/provision_admin.py`, or the one-time bootstrap endpoint
  `POST /api/auth/bootstrap-admin` (which is permanently disabled once an Admin exists).
"""
import hashlib
import hmac
import json
import os
import secrets
import time
from pathlib import Path
from werkzeug.security import check_password_hash, generate_password_hash

from services import blockchain

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
DEFAULT_AUTH_STORE_PATH = DATA_DIR / "auth_store.json"
DEFAULT_SERVER_KEYS_PATH = DATA_DIR / "server_keys.json"

_SECRET_KEY = os.getenv("PHARMATRACE_AUTH_SECRET", "pharmatrace-local-dev-hmac-secret-2026")
_ACTIVE_SESSIONS: dict[str, dict] = {}


def _get_auth_store_path() -> Path:
    custom = os.getenv("PHARMATRACE_AUTH_STORE_PATH", "").strip()
    if custom:
        return Path(custom)
    return DEFAULT_AUTH_STORE_PATH


def _get_server_keys_path() -> Path:
    custom = os.getenv("PHARMATRACE_KEY_STORE_PATH", "").strip()
    if custom:
        return Path(custom)
    return DEFAULT_SERVER_KEYS_PATH


def _ensure_data_dir() -> None:
    store_path = _get_auth_store_path()
    store_path.parent.mkdir(parents=True, exist_ok=True)


def _resolve_admin_address() -> str:
    """Resolve the on-chain administrator address (smart contract admin() or deployer wallet)."""
    try:
        if blockchain.is_connected():
            contract = blockchain._get_contract()
            chain_admin = contract.functions.admin().call()
            if chain_admin and chain_admin != blockchain.ZERO_ADDRESS:
                return chain_admin
    except Exception:
        pass
    return blockchain.w3.eth.account.from_key(blockchain.DEFAULT_ADMIN_KEY).address


def _maybe_provision_env_admin(store: dict[str, dict]) -> bool:
    """If no admin exists in `store` and PHARMATRACE_ADMIN_PASSWORD is set in env, provision it."""
    if any(acct.get("role", "").lower() == "admin" for acct in store.values()):
        return False

    env_pw = os.getenv("PHARMATRACE_ADMIN_PASSWORD", "").strip()
    if not env_pw:
        return False

    admin_addr = _resolve_admin_address()
    env_user = os.getenv("PHARMATRACE_ADMIN_USERNAME", "admin").strip().lower() or "admin"
    env_email = os.getenv("PHARMATRACE_ADMIN_EMAIL", f"{env_user}@pharmatrace.org").strip().lower()
    env_org = os.getenv("PHARMATRACE_ADMIN_ORG", "PharmaTrace Regulatory Authority").strip()

    store[admin_addr.lower()] = {
        "address": admin_addr,
        "username": env_user,
        "email": env_email,
        "password_hash": generate_password_hash(env_pw, method="pbkdf2:sha256"),
        "role": "admin",
        "org_name": env_org,
        "license_number": "REG-AUTH-ROOT",
        "contact_phone": "",
        "location": "",
        "created_at": int(time.time()),
        "is_demo_seed": False,
    }
    return True


def load_store() -> dict[str, dict]:
    _ensure_data_dir()
    store_path = _get_auth_store_path()
    if not store_path.is_file():
        empty_store: dict[str, dict] = {}
        if _maybe_provision_env_admin(empty_store):
            save_store(empty_store)
        return empty_store
    try:
        raw = store_path.read_text(encoding="utf-8").strip()
        data = json.loads(raw) if raw else {}
        if not isinstance(data, dict):
            data = {}
        if _maybe_provision_env_admin(data):
            save_store(data)
        return data
    except Exception:
        return {}


def save_store(store: dict[str, dict]) -> None:
    _ensure_data_dir()
    store_path = _get_auth_store_path()
    store_path.write_text(json.dumps(store, indent=2), encoding="utf-8")


def has_admin_account() -> bool:
    """Return True if an administrator account has been provisioned in the auth store."""
    store = load_store()
    return any(acct.get("role", "").lower() == "admin" for acct in store.values())


def provision_admin_account(
    *,
    username: str,
    email: str,
    password: str,
    name: str = "",
    org_name: str = "PharmaTrace Regulatory Authority",
) -> tuple[dict, bool]:
    """Provision an administrator account idempotently.
    Returns (account_record, created_boolean).
    If an administrator account with the same username or email already exists,
    returns (existing_record, False) without altering the password.
    """
    user_clean = (username or "").strip()
    email_clean = (email or "").strip().lower()
    pw_clean = (password or "").strip()
    name_clean = (name or user_clean).strip()

    if not user_clean or not email_clean:
        raise ValueError("Username and email are required to provision an administrator.")

    store = load_store()

    # Check if an admin with the same username or email already exists
    for key, acct in store.items():
        if acct.get("role", "").lower() == "admin":
            if acct.get("username", "").lower() == user_clean.lower() or acct.get("email", "").lower() == email_clean:
                return {k: v for k, v in acct.items() if k != "password_hash"}, False

    if not pw_clean or len(pw_clean) < 6:
        raise ValueError("Administrator password must be at least 6 characters.")

    admin_addr = _resolve_admin_address()
    account_key = f"admin:{user_clean.lower()}"

    record = {
        "address": admin_addr,
        "name": name_clean,
        "username": user_clean,
        "email": email_clean,
        "password_hash": generate_password_hash(pw_clean, method="pbkdf2:sha256"),
        "role": "admin",
        "org_name": (org_name or "PharmaTrace Regulatory Authority").strip(),
        "license_number": "REG-AUTH-ROOT",
        "contact_phone": "",
        "location": "",
        "must_change_password": True,
        "created_at": int(time.time()),
        "is_demo_seed": False,
    }
    store[account_key] = record
    save_store(store)
    return {k: v for k, v in record.items() if k != "password_hash"}, True


def provision_initial_admin(
    *,
    username: str,
    email: str,
    password: str,
    org_name: str = "PharmaTrace Regulatory Authority",
) -> dict:
    """One-time secure provisioning of the initial Administrator account.
    Raises PermissionError if an administrator account already exists.
    """
    if has_admin_account():
        raise PermissionError(
            "An administrator account has already been provisioned. Public or duplicate admin creation is disabled."
        )

    user_clean = (username or "").strip().lower()
    email_clean = (email or "").strip().lower()
    pw_clean = (password or "").strip()

    if not user_clean or not email_clean or not pw_clean:
        raise ValueError("Username, email, and password are required to provision the initial administrator.")
    if len(pw_clean) < 6:
        raise ValueError("Administrator password must be at least 6 characters.")

    admin_addr = _resolve_admin_address()
    store = load_store()
    record = {
        "address": admin_addr,
        "username": user_clean,
        "email": email_clean,
        "password_hash": generate_password_hash(pw_clean, method="pbkdf2:sha256"),
        "role": "admin",
        "org_name": (org_name or "PharmaTrace Regulatory Authority").strip(),
        "license_number": "REG-AUTH-ROOT",
        "contact_phone": "",
        "location": "",
        "created_at": int(time.time()),
        "is_demo_seed": False,
    }
    store[admin_addr.lower()] = record
    save_store(store)
    return {k: v for k, v in record.items() if k != "password_hash"}


def seed_test_accounts() -> dict[str, dict]:
    """Explicit test-fixture helper for automated test suites ONLY.
    Never called during normal application startup.
    """
    admin_addr = blockchain.w3.eth.account.from_key(blockchain.DEFAULT_ADMIN_KEY).address
    mfr_addr = blockchain.w3.eth.account.from_key(blockchain.DEFAULT_MFR_KEY).address
    dist_addr = blockchain.w3.eth.account.from_key(blockchain.DEFAULT_DIST_KEY).address
    pharm_addr = blockchain.w3.eth.account.from_key(blockchain.DEFAULT_PHARM_KEY).address

    fixtures = {
        admin_addr.lower(): {
            "address": admin_addr,
            "username": "admin",
            "email": "admin@pharmatrace.local",
            "password_hash": generate_password_hash("Admin@123", method="pbkdf2:sha256"),
            "role": "admin",
            "org_name": "PharmaTrace Regulatory Authority",
            "license_number": "REG-AUTH-ROOT",
            "contact_phone": "+91-11-2300-0000",
            "location": "New Delhi, IN",
            "created_at": 1760000000,
            "is_demo_seed": True,
        },
        mfr_addr.lower(): {
            "address": mfr_addr,
            "username": "manufacturer",
            "email": "manufacturer@elnova.local",
            "password_hash": generate_password_hash("Mfr@123", method="pbkdf2:sha256"),
            "role": "manufacturer",
            "org_name": "Elnova Pharmaceuticals",
            "license_number": "MFG-LIC-2026-001",
            "contact_phone": "+91-22-4001-1001",
            "location": "Baddi, Himachal Pradesh",
            "created_at": 1760000100,
            "is_demo_seed": True,
        },
        dist_addr.lower(): {
            "address": dist_addr,
            "username": "distributor",
            "email": "distributor@medline.local",
            "password_hash": generate_password_hash("Dist@123", method="pbkdf2:sha256"),
            "role": "distributor",
            "org_name": "MedLine National Logistics",
            "license_number": "DIST-LIC-2026-014",
            "contact_phone": "+91-80-4112-2002",
            "location": "Bengaluru, Karnataka",
            "linked_manufacturer": mfr_addr,
            "created_at": 1760000200,
            "is_demo_seed": True,
        },
        pharm_addr.lower(): {
            "address": pharm_addr,
            "username": "pharmacy",
            "email": "pharmacy@apollocare.local",
            "password_hash": generate_password_hash("Pharm@123", method="pbkdf2:sha256"),
            "role": "pharmacy",
            "org_name": "Apollo Care Pharmacy",
            "license_number": "PHARM-LIC-2026-089",
            "contact_phone": "+91-484-255-3003",
            "location": "Kochi, Kerala",
            "linked_manufacturer": mfr_addr,
            "linked_distributor": dist_addr,
            "created_at": 1760000300,
            "is_demo_seed": True,
        },
    }
    store = load_store()
    store.update(fixtures)
    save_store(store)
    return store


def save_server_key(address: str, private_key: str) -> None:
    """Persist a generated organization private key strictly on the backend."""
    _ensure_data_dir()
    keys_path = _get_server_keys_path()
    keys = {}
    if keys_path.is_file():
        try:
            keys = json.loads(keys_path.read_text(encoding="utf-8"))
        except Exception:
            keys = {}
    keys[address.lower()] = private_key
    keys_path.write_text(json.dumps(keys, indent=2), encoding="utf-8")


def get_signing_key_for_address(address: str | None, fallback_role: str = "") -> str:
    """Resolve the server-side private key for an address, falling back to default role key."""
    if address:
        addr_low = address.lower()
        for key in (
            blockchain.DEFAULT_ADMIN_KEY,
            blockchain.DEFAULT_MFR_KEY,
            blockchain.DEFAULT_DIST_KEY,
            blockchain.DEFAULT_PHARM_KEY,
        ):
            if blockchain.w3.eth.account.from_key(key).address.lower() == addr_low:
                return key
        keys_path = _get_server_keys_path()
        if keys_path.is_file():
            try:
                keys = json.loads(keys_path.read_text(encoding="utf-8"))
                if addr_low in keys:
                    return keys[addr_low]
            except Exception:
                pass
    return blockchain.get_key_for_role(fallback_role)


def get_org_metadata(address: str) -> dict:
    """Return non-sensitive metadata (email, license, phone, location) for an address."""
    store = load_store()
    entry = store.get((address or "").lower())
    if not entry:
        for acct in store.values():
            if acct.get("address", "").lower() == (address or "").lower():
                entry = acct
                break
    entry = entry or {}
    return {
        "name": entry.get("name", ""),
        "username": entry.get("username", ""),
        "email": entry.get("email", ""),
        "license_number": entry.get("license_number", ""),
        "contact_phone": entry.get("contact_phone", ""),
        "location": entry.get("location", ""),
        "created_at": entry.get("created_at"),
        "tx_hash": entry.get("tx_hash", ""),
        "block_number": entry.get("block_number"),
    }


def register_organization_credentials(
    *,
    address: str,
    role: str,
    org_name: str,
    email: str = "",
    username: str = "",
    password: str = "",
    license_number: str = "",
    contact_phone: str = "",
    location: str = "",
    linked_manufacturer: str = "",
    linked_distributor: str = "",
    tx_hash: str = "",
    block_number: int | None = None,
    private_key: str | None = None,
) -> dict:
    """Store salted password hash and organization profile for a newly registered org."""
    role_clean = role.lower().strip()
    if role_clean == "admin":
        raise PermissionError("Public registration for Admin role is strictly prohibited.")

    store = load_store()
    email_clean = (email or "").strip().lower()
    user_clean = (username or email_clean.split("@")[0] or org_name.lower().replace(" ", "_")).strip().lower()

    # Check for duplicate email/username on a different address
    for addr_key, existing in store.items():
        if addr_key == address.lower():
            continue
        if email_clean and existing.get("email", "").lower() == email_clean:
            raise ValueError(f"An organization with email '{email_clean}' is already registered.")
        if user_clean and existing.get("username", "").lower() == user_clean:
            raise ValueError(f"Username '{user_clean}' is already taken.")

    pw_to_hash = password.strip() if password and password.strip() else secrets.token_urlsafe(12)
    record = {
        "address": address,
        "username": user_clean,
        "email": email_clean or f"{user_clean}@org.pharmatrace.local",
        "password_hash": generate_password_hash(pw_to_hash, method="pbkdf2:sha256"),
        "role": role_clean,
        "org_name": org_name.strip(),
        "license_number": license_number.strip() or f"{role_clean.upper()[:4]}-LIC-{int(time.time()) % 100000}",
        "contact_phone": contact_phone.strip(),
        "location": location.strip(),
        "linked_manufacturer": linked_manufacturer,
        "linked_distributor": linked_distributor,
        "tx_hash": tx_hash,
        "block_number": block_number,
        "created_at": int(time.time()),
        "is_demo_seed": False,
    }
    store[address.lower()] = record
    save_store(store)

    if private_key:
        save_server_key(address, private_key)

    return {k: v for k, v in record.items() if k != "password_hash"}


def _issue_token(address: str, role: str, username: str) -> str:
    nonce = secrets.token_hex(16)
    issued = int(time.time())
    payload = f"{address.lower()}:{role.lower()}:{username}:{issued}:{nonce}"
    sig = hmac.new(_SECRET_KEY.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).hexdigest()
    token = f"{payload}:{sig}"
    _ACTIVE_SESSIONS[token] = {
        "address": address,
        "role": role.lower(),
        "username": username,
        "issued_at": issued,
    }
    return token


def verify_token(token: str | None) -> dict | None:
    if not token:
        return None
    raw = token.strip()
    if raw.lower().startswith("bearer "):
        raw = raw[7:].strip()
    if not raw:
        return None

    parts = raw.split(":")
    if len(parts) != 6:
        return None
    addr_low, role, username, issued_str, nonce, sig = parts
    payload = f"{addr_low}:{role}:{username}:{issued_str}:{nonce}"
    expected_sig = hmac.new(_SECRET_KEY.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(sig, expected_sig):
        return None

    store = load_store()
    acct = None
    user_low = username.lower()
    for candidate in store.values():
        if candidate.get("username", "").lower() == user_low:
            acct = candidate
            break
    if not acct:
        acct = store.get(addr_low)
    if not acct:
        return None

    return {
        "address": acct["address"],
        "role": acct["role"],
        "name": acct.get("name", acct["username"]),
        "username": acct["username"],
        "email": acct["email"],
        "org_name": acct["org_name"],
        "license_number": acct.get("license_number", ""),
        "must_change_password": acct.get("must_change_password", False),
    }


def revoke_token(token: str | None) -> None:
    if not token:
        return
    raw = token.strip()
    if raw.lower().startswith("bearer "):
        raw = raw[7:].strip()
    _ACTIVE_SESSIONS.pop(raw, None)


def find_account_by_identifier(identifier: str) -> dict | None:
    ident = (identifier or "").strip().lower()
    if not ident:
        return None
    store = load_store()
    if ident in store:
        return store[ident]
    if f"admin:{ident}" in store:
        return store[f"admin:{ident}"]
    for acct in store.values():
        if acct.get("email", "").lower() == ident or acct.get("username", "").lower() == ident:
            return acct
    return None


def find_admin_account(
    identifier: str | None = None,
    username: str | None = None,
    email: str | None = None,
) -> tuple[dict | None, str | None]:
    """Find an administrator account, validating that username and email match the SAME account.
    Returns (account_dict_or_None, error_code_or_None).
    """
    store = load_store()
    admin_accounts = [acct for acct in store.values() if acct.get("role", "").lower() == "admin"]
    if not admin_accounts:
        return None, "ADMIN_NOT_PROVISIONED"

    u_clean = (username or "").strip().lower()
    e_clean = (email or "").strip().lower()
    i_clean = (identifier or "").strip().lower()

    if not e_clean and "@" in i_clean:
        e_clean = i_clean
    if not u_clean and i_clean and "@" not in i_clean:
        u_clean = i_clean

    acct_by_email = None
    acct_by_user = None

    if e_clean:
        for acct in admin_accounts:
            if acct.get("email", "").lower() == e_clean:
                acct_by_email = acct
                break

    if u_clean:
        for acct in admin_accounts:
            if acct.get("username", "").lower() == u_clean:
                acct_by_user = acct
                break

    if e_clean and u_clean:
        if not acct_by_email or not acct_by_user:
            return None, "INVALID_CREDENTIALS"
        if acct_by_email.get("username", "").lower() != acct_by_user.get("username", "").lower():
            return None, "CREDENTIAL_MISMATCH"
        return acct_by_email, None

    if acct_by_email:
        return acct_by_email, None
    if acct_by_user:
        return acct_by_user, None

    return None, "INVALID_CREDENTIALS"


def authenticate_user(
    identifier: str | None = None,
    password: str = "",
    expected_role: str | None = None,
    username: str | None = None,
    email: str | None = None,
) -> tuple[dict | None, dict | None, int]:
    """Validate credentials and verify live on-chain organization approval state.
    Returns (session_response_dict, error_dict_or_none, http_status).
    """
    req_role = (expected_role or "").strip().lower() if expected_role else None

    if req_role == "admin":
        if not has_admin_account():
            return None, {
                "error": "No administrator account has been provisioned yet. Please complete initial Administrator setup first.",
                "code": "ADMIN_NOT_PROVISIONED",
            }, 403

        acct, err_code = find_admin_account(identifier=identifier, username=username, email=email)
        if err_code == "CREDENTIAL_MISMATCH":
            return None, {
                "error": "Administrator email and username do not match the same account.",
                "code": "CREDENTIAL_MISMATCH",
            }, 401
        if not acct:
            return None, {
                "error": "Invalid administrator username/email or password.",
                "code": "INVALID_CREDENTIALS",
            }, 401

        if not check_password_hash(acct.get("password_hash", ""), password or ""):
            return None, {
                "error": "Invalid administrator username/email or password.",
                "code": "INVALID_CREDENTIALS",
            }, 401

        actual_role = "admin"
        address = acct["address"]
    else:
        ident = (identifier or username or email or "").strip().lower()
        acct = find_account_by_identifier(ident)
        if not acct or not check_password_hash(acct.get("password_hash", ""), password or ""):
            return None, {
                "error": "Invalid username/email or password.",
                "code": "INVALID_CREDENTIALS",
            }, 401

        actual_role = acct.get("role", "").lower()
        if req_role and actual_role != req_role:
            return None, {
                "error": f"Role mismatch: This account is registered as '{actual_role.capitalize()}', not '{req_role.capitalize()}'. Please use the {actual_role.capitalize()} sign-in page.",
                "code": "ROLE_MISMATCH",
                "registered_role": actual_role,
            }, 403

        address = acct["address"]

    if not blockchain.is_connected():
        return None, {
            "error": "Blockchain node is currently unreachable. Cannot verify on-chain organization authorization.",
            "code": "BLOCKCHAIN_UNAVAILABLE",
        }, 503

    try:
        chain_user = blockchain.get_user(address)
    except Exception as exc:
        return None, {
            "error": f"Failed to read on-chain account status: {exc}",
            "code": "BLOCKCHAIN_READ_ERROR",
        }, 500

    if actual_role == "admin":
        expected_admin_addr = _resolve_admin_address()
        if address.lower() != expected_admin_addr.lower() or chain_user.get("role", 0) != 1:
            return None, {
                "error": "Access denied: Account is not bound to the authorized smart-contract Administrator wallet.",
                "code": "UNAUTHORIZED_ADMIN_ADDRESS",
            }, 403
    else:
        status_name = chain_user.get("status_name", "Pending")
        role_num = chain_user.get("role", 0)
        if role_num == 0:
            return None, {
                "error": "This organization account is not registered on the active smart contract (the local blockchain may have been reset). Please register the organization on-chain.",
                "code": "NOT_REGISTERED_ON_CHAIN",
                "address": address,
            }, 403

        if status_name == "Rejected":
            return None, {
                "error": "Access denied: Your organization registration was rejected on-chain by an authorizing authority.",
                "code": "REGISTRATION_REJECTED",
                "address": address,
                "user": {**chain_user, **get_org_metadata(address)},
            }, 403

        if status_name != "Active":
            missing = []
            if not chain_user.get("adminOk"):
                missing.append("Admin")
            if actual_role in ("distributor", "pharmacy") and not chain_user.get("mfrOk"):
                missing.append("Manufacturer")
            if actual_role == "pharmacy" and not chain_user.get("distOk"):
                missing.append("Distributor")
            missing_str = ", ".join(missing) if missing else "required authorities"
            return None, {
                "error": f"Your organization registration is currently Pending Approval. Waiting for on-chain approval from: {missing_str}.",
                "code": "PENDING_APPROVAL",
                "address": address,
                "missing_approvals": missing,
                "user": {**chain_user, **get_org_metadata(address)},
            }, 403

    token = _issue_token(address, actual_role, acct["username"])
    profile = {
        **chain_user,
        "address": address,
        "name": acct.get("name", acct["username"]),
        "username": acct["username"],
        "email": acct["email"],
        "org_name": chain_user.get("name") or acct["org_name"],
        "role": actual_role,
        "role_name": actual_role.capitalize(),
        "status_name": "Active" if actual_role == "admin" else chain_user.get("status_name", "Active"),
        "license_number": acct.get("license_number", ""),
        "contact_phone": acct.get("contact_phone", ""),
        "location": acct.get("location", ""),
        "must_change_password": acct.get("must_change_password", False),
    }
    return {
        "success": True,
        "token": token,
        "user": profile,
        "auth_mode": "server_hmac_session_with_onchain_rbac",
    }, None, 200


def change_password(*, identifier_or_username: str, current_password: str, new_password: str) -> tuple[bool, str | None]:
    """Change an account's password securely."""
    if not new_password or len(new_password.strip()) < 6:
        return False, "New password must be at least 6 characters."

    store = load_store()
    ident = (identifier_or_username or "").strip().lower()
    target_key = None
    target_acct = None

    for key, acct in store.items():
        if acct.get("username", "").lower() == ident or acct.get("email", "").lower() == ident:
            target_key = key
            target_acct = acct
            break

    if not target_acct:
        return False, "Account not found."

    if not check_password_hash(target_acct.get("password_hash", ""), current_password):
        return False, "Current password is incorrect."

    target_acct["password_hash"] = generate_password_hash(new_password.strip(), method="pbkdf2:sha256")
    target_acct["must_change_password"] = False
    store[target_key] = target_acct
    save_store(store)
    return True, None


def get_admin_profiles() -> list[dict]:
    """Return non-sensitive profile summaries for all provisioned administrators."""
    store = load_store()
    profiles = []
    for acct in store.values():
        if acct.get("role", "").lower() == "admin":
            profiles.append({
                "name": acct.get("name", acct.get("username", "")),
                "username": acct.get("username", ""),
                "email": acct.get("email", ""),
                "role": "admin",
                "org_name": acct.get("org_name", ""),
                "created_at": acct.get("created_at"),
                "must_change_password": acct.get("must_change_password", False),
            })
    return profiles
