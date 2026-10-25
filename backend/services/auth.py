"""Server-side authentication, password hashing, and session token management for PharmaTrace.

Note on architecture:
- Passwords are never stored in plaintext; all credentials use salted PBKDF2-SHA256 hashes via Werkzeug.
- Session tokens are HMAC-SHA256 signed server tokens validated on protected endpoints.
- In local Hardhat development mode, the four primary supply-chain roles map to deterministic
  Hardhat accounts (#0 Admin, #1 Manufacturer, #2 Distributor, #3 Pharmacy), while newly registered
  organizations receive freshly provisioned Hardhat-funded accounts whose keys remain strictly
  server-side.
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
AUTH_STORE_PATH = DATA_DIR / "auth_store.json"
SERVER_KEYS_PATH = DATA_DIR / "server_keys.json"

_SECRET_KEY = os.getenv("PHARMATRACE_AUTH_SECRET", "pharmatrace-local-dev-hmac-secret-2026")
_ACTIVE_SESSIONS: dict[str, dict] = {}


def _ensure_data_dir() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)


def _default_accounts() -> dict[str, dict]:
    """Seeded development accounts corresponding to the 4 Hardhat role wallets."""
    admin_addr = blockchain.w3.eth.account.from_key(blockchain.DEFAULT_ADMIN_KEY).address
    mfr_addr = blockchain.w3.eth.account.from_key(blockchain.DEFAULT_MFR_KEY).address
    dist_addr = blockchain.w3.eth.account.from_key(blockchain.DEFAULT_DIST_KEY).address
    pharm_addr = blockchain.w3.eth.account.from_key(blockchain.DEFAULT_PHARM_KEY).address

    admin_pw = os.getenv("ADMIN_DEMO_PASSWORD", "Admin@123")
    mfr_pw = os.getenv("MFR_DEMO_PASSWORD", "Mfr@123")
    dist_pw = os.getenv("DIST_DEMO_PASSWORD", "Dist@123")
    pharm_pw = os.getenv("PHARM_DEMO_PASSWORD", "Pharm@123")

    return {
        admin_addr.lower(): {
            "address": admin_addr,
            "username": "admin",
            "email": "admin@pharmatrace.local",
            "password_hash": generate_password_hash(admin_pw, method="pbkdf2:sha256"),
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
            "password_hash": generate_password_hash(mfr_pw, method="pbkdf2:sha256"),
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
            "password_hash": generate_password_hash(dist_pw, method="pbkdf2:sha256"),
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
            "password_hash": generate_password_hash(pharm_pw, method="pbkdf2:sha256"),
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


def load_store() -> dict[str, dict]:
    _ensure_data_dir()
    defaults = _default_accounts()
    if not AUTH_STORE_PATH.is_file():
        save_store(defaults)
        return defaults
    try:
        data = json.loads(AUTH_STORE_PATH.read_text(encoding="utf-8"))
        changed = False
        for k, v in defaults.items():
            if k not in data:
                data[k] = v
                changed = True
        if changed:
            save_store(data)
        return data
    except Exception:
        save_store(defaults)
        return defaults


def save_store(store: dict[str, dict]) -> None:
    _ensure_data_dir()
    AUTH_STORE_PATH.write_text(json.dumps(store, indent=2), encoding="utf-8")


def save_server_key(address: str, private_key: str) -> None:
    """Persist a generated organization private key strictly on the backend."""
    _ensure_data_dir()
    keys = {}
    if SERVER_KEYS_PATH.is_file():
        try:
            keys = json.loads(SERVER_KEYS_PATH.read_text(encoding="utf-8"))
        except Exception:
            keys = {}
    keys[address.lower()] = private_key
    SERVER_KEYS_PATH.write_text(json.dumps(keys, indent=2), encoding="utf-8")


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
        if SERVER_KEYS_PATH.is_file():
            try:
                keys = json.loads(SERVER_KEYS_PATH.read_text(encoding="utf-8"))
                if addr_low in keys:
                    return keys[addr_low]
            except Exception:
                pass
    return blockchain.get_key_for_role(fallback_role)


def get_org_metadata(address: str) -> dict:
    """Return non-sensitive metadata (email, license, phone, location) for an address."""
    store = load_store()
    entry = store.get((address or "").lower(), {})
    return {
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
    acct = store.get(addr_low)
    if not acct:
        return None
    return {
        "address": acct["address"],
        "role": acct["role"],
        "username": acct["username"],
        "email": acct["email"],
        "org_name": acct["org_name"],
        "license_number": acct.get("license_number", ""),
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
    # Direct address match
    if ident in store:
        return store[ident]
    for acct in store.values():
        if acct.get("email", "").lower() == ident or acct.get("username", "").lower() == ident:
            return acct
    return None


def authenticate_user(identifier: str, password: str, expected_role: str | None = None) -> tuple[dict | None, str | None, int]:
    """Validate credentials and verify live on-chain organization approval state.
    Returns (session_Response_dict, error_dict_or_none, http_status).
    """
    acct = find_account_by_identifier(identifier)
    if not acct or not check_password_hash(acct.get("password_hash", ""), password or ""):
        return None, {
            "error": "Invalid username/email or password.",
            "code": "INVALID_CREDENTIALS",
        }, 401

    actual_role = acct.get("role", "").lower()
    if expected_role:
        req_role = expected_role.strip().lower()
        if req_role and actual_role != req_role:
            return None, {
                "error": f"Role mismatch: This account is registered as '{actual_role.capitalize()}', not '{req_role.capitalize()}'. Please use the {actual_role.capitalize()} sign-in page.",
                "code": "ROLE_MISMATCH",
                "registered_role": actual_role,
            }, 403

    address = acct["address"]

    # Query on-chain status if blockchain is connected
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

    # Admin is root deployer; check non-admin roles on-chain
    if actual_role != "admin":
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
        "username": acct["username"],
        "email": acct["email"],
        "org_name": chain_user.get("name") or acct["org_name"],
        "role": actual_role,
        "role_name": actual_role.capitalize(),
        "status_name": "Active" if actual_role == "admin" else chain_user.get("status_name", "Active"),
        "license_number": acct.get("license_number", ""),
        "contact_phone": acct.get("contact_phone", ""),
        "location": acct.get("location", ""),
    }
    return {
        "success": True,
        "token": token,
        "user": profile,
        "auth_mode": "server_hmac_session_with_onchain_rbac",
    }, None, 200
