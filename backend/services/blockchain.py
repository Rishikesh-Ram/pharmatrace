"""Talks to the smart contract (web3.py)."""
from datetime import datetime, timezone
import json
import time
import os
from pathlib import Path
from dotenv import load_dotenv
from web3 import Web3

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

RPC_URL = os.getenv("RPC_URL", "http://127.0.0.1:8545")
CONTRACT_ADDRESS = os.getenv("CONTRACT_ADDRESS", "")
ABI_PATH = os.getenv("ABI_PATH", "contract_abi.json")
CONTRACT_GETTER = os.getenv("CONTRACT_GETTER", "getMedicine")

# Standard Hardhat development keys for multi-role simulation
DEFAULT_ADMIN_KEY = os.getenv(
    "ADMIN_PRIVATE_KEY",
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
)
DEFAULT_MFR_KEY = os.getenv(
    "MANUFACTURER_PRIVATE_KEY",
    "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
)
DEFAULT_DIST_KEY = os.getenv(
    "DISTRIBUTOR_PRIVATE_KEY",
    "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
)
DEFAULT_PHARM_KEY = os.getenv(
    "PHARMACY_PRIVATE_KEY",
    "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
)

ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

ROLE_NAMES = {0: "None", 1: "Admin", 2: "Manufacturer", 3: "Distributor", 4: "Pharmacy"}
ROLE_MAP = {"none": 0, "admin": 1, "manufacturer": 2, "distributor": 3, "pharmacy": 4}
STATUS_NAMES = {0: "Pending", 1: "Active", 2: "Rejected"}

w3 = Web3(Web3.HTTPProvider(RPC_URL))
_contract = None
VERIFICATIONS_STORE_PATH = Path(__file__).resolve().parent.parent / "data" / "consumer_verifications.json"


def _load_consumer_verifications() -> dict[str, list[dict]]:
    if not VERIFICATIONS_STORE_PATH.is_file():
        return {}
    try:
        return json.loads(VERIFICATIONS_STORE_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _save_consumer_verifications(store: dict[str, list[dict]]) -> None:
    VERIFICATIONS_STORE_PATH.parent.mkdir(parents=True, exist_ok=True)
    VERIFICATIONS_STORE_PATH.write_text(json.dumps(store, indent=2), encoding="utf-8")


def record_consumer_verification(medicine_id: str, verdict: str, details: str = "", method: str = "verification") -> dict:
    """Persist an authentic consumer verification event for a medicine batch."""
    norm_id = medicine_id.strip()
    store = _load_consumer_verifications()
    events = store.setdefault(norm_id, [])
    now = int(time.time())
    ev = {
        "medicine_id": norm_id,
        "timestamp": now,
        "verdict": verdict,
        "method": method,
        "details": details,
        "verified_at_utc": datetime.fromtimestamp(now, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
    }
    events.append(ev)
    _save_consumer_verifications(store)
    return ev


def get_consumer_verification(medicine_id: str) -> dict | None:
    """Retrieve the latest persisted consumer verification event for a batch."""
    norm_id = medicine_id.strip()
    store = _load_consumer_verifications()
    events = store.get(norm_id) or []
    if not events:
        for k, v in store.items():
            if k.upper() == norm_id.upper() and v:
                return v[-1]
        return None
    return events[-1]


def is_connected() -> bool:
    try:
        return w3.is_connected()
    except Exception:
        return False


def _load_abi():
    abi_file = Path(ABI_PATH)
    if not abi_file.is_file():
        abi_file = Path(__file__).resolve().parent.parent / ABI_PATH
    with open(abi_file, encoding="utf-8") as f:
        return json.load(f)


def _get_contract():
    global _contract
    if _contract is None:
        abi = _load_abi()
        contract_addr = os.getenv("CONTRACT_ADDRESS", CONTRACT_ADDRESS)
        _contract = w3.eth.contract(
            address=Web3.to_checksum_address(contract_addr), abi=abi
        )
    return _contract


def get_key_for_role(role_name: str) -> str:
    r = role_name.lower().strip()
    if r == "admin":
        return DEFAULT_ADMIN_KEY
    if r == "manufacturer":
        return DEFAULT_MFR_KEY
    if r == "distributor":
        return DEFAULT_DIST_KEY
    if r == "pharmacy":
        return DEFAULT_PHARM_KEY
    return DEFAULT_ADMIN_KEY


_LAST_TX_META: dict[str, dict] = {}


def get_tx_meta(tx_hash: str) -> dict:
    """Return block number and confirmation metadata for a transaction hash."""
    if not tx_hash:
        return {}
    clean = tx_hash.lower().removeprefix("0x")
    if clean in _LAST_TX_META:
        return _LAST_TX_META[clean]
    try:
        receipt = w3.eth.get_transaction_receipt(tx_hash if tx_hash.startswith("0x") else f"0x{tx_hash}")
        blk = w3.eth.get_block(receipt.blockNumber)
        meta = {
            "transaction_hash": receipt.transactionHash.hex(),
            "block_number": int(receipt.blockNumber),
            "gas_used": int(receipt.gasUsed),
            "timestamp": int(blk["timestamp"]),
            "confirmation_status": "Confirmed" if receipt.status == 1 else "Failed",
        }
        _LAST_TX_META[clean] = meta
        return meta
    except Exception:
        return {"transaction_hash": tx_hash, "confirmation_status": "Confirmed"}


def _send_tx(func_call, private_key: str) -> str:
    account = w3.eth.account.from_key(private_key)
    gas_est = 600000
    try:
        gas_est = int(func_call.estimate_gas({"from": account.address}) * 1.3)
    except Exception:
        pass

    tx = func_call.build_transaction({
        "from": account.address,
        "nonce": w3.eth.get_transaction_count(account.address),
        "chainId": w3.eth.chain_id,
        "gas": gas_est,
        "gasPrice": w3.eth.gas_price,
    })

    signed = w3.eth.account.sign_transaction(tx, private_key)
    raw = getattr(signed, "raw_transaction", None) or getattr(signed, "rawTransaction", None)
    tx_hash = w3.eth.send_raw_transaction(raw)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
    if receipt.status != 1:
        raise RuntimeError("Transaction execution reverted on blockchain")
    hex_hash = tx_hash.hex()
    try:
        blk = w3.eth.get_block(receipt.blockNumber)
        ts = int(blk["timestamp"])
    except Exception:
        ts = 0
    _LAST_TX_META[hex_hash.lower().removeprefix("0x")] = {
        "transaction_hash": hex_hash,
        "block_number": int(receipt.blockNumber),
        "gas_used": int(receipt.gasUsed),
        "from": account.address,
        "timestamp": ts,
        "confirmation_status": "Confirmed",
    }
    return hex_hash


def _components(function_name: str):
    """Field names of the struct returned by the given contract function (from the ABI)."""
    abi = _load_abi()
    for item in abi:
        if item.get("type") == "function" and item.get("name") == function_name:
            outs = item.get("outputs", [])
            if outs and outs[0].get("components"):
                return [c["name"] for c in outs[0]["components"]]
    return []


def _pick(data: dict, *names, default=""):
    for n in names:
        if n in data and data[n] not in (None, ""):
            return data[n]
    return default


def build_record(names, raw):
    """Turns the struct returned by getMedicine into a plain dict, using the ABI field names."""
    values = raw
    if isinstance(values, (tuple, list)) and len(values) == 1 and isinstance(values[0], (tuple, list)):
        values = values[0]
    if isinstance(values, dict):
        data = values
    else:
        data = dict(zip(names, values))

    return {
        "id": str(_pick(data, "id")),
        "name": _pick(data, "name"),
        "batch": _pick(data, "batch", "batchNumber"),
        "manufacturer": str(_pick(data, "manufacturer", "currentOwner", "owner")),
        "current_owner": str(_pick(data, "currentOwner", "current_owner", "manufacturer", default=ZERO_ADDRESS)),
        "ipfs_cid": _pick(data, "imageHash", "ipfsHash", "imageCid"),
        "expiry": _pick(data, "expiry", default=None),
        "quantity": int(_pick(data, "quantity", default=0) or 0),
        "stage": int(_pick(data, "stage", default=1) or 1),
        "distributor": str(_pick(data, "distributor", default=ZERO_ADDRESS)),
        "pharmacy": str(_pick(data, "pharmacy", default=ZERO_ADDRESS)),
        "raw": {k: (v if isinstance(v, (str, int, bool)) else str(v)) for k, v in data.items()},
    }



ARCHIVED_BATCHES_FILE = Path(__file__).resolve().parent.parent / "data" / "archived_batches.json"


def get_archived_batches() -> set:
    """Returns a set of medicine/batch IDs that are archived or removed from active views."""
    archived = {"TEST_MULTI_OVERFLOW"}
    if ARCHIVED_BATCHES_FILE.exists():
        try:
            with open(ARCHIVED_BATCHES_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    archived.update(str(x).strip() for x in data if x)
        except Exception:
            pass
    return archived


def is_batch_archived(medicine_id: str) -> bool:
    """Checks whether a medicine ID or batch number is marked as archived."""
    if not medicine_id:
        return False
    clean = str(medicine_id).strip()
    archived = get_archived_batches()
    return clean in archived or any(b.casefold() == clean.casefold() for b in archived)

def read_record(medicine_id: str):
    if is_batch_archived(medicine_id):
        return None

    """
    Returns {"name","batch","manufacturer","ipfs_cid","expiry","recalled","expired",
    "recall_reason","raw"} or None if the medicine is not registered.
    """
    try:
        c = _get_contract()
        raw = getattr(c.functions, CONTRACT_GETTER)(medicine_id).call()
        record = build_record(_components(CONTRACT_GETTER), raw)
    except Exception:
        return None  # revert ("not found"), bad config, or node unreachable

    if not record["name"] and not record["ipfs_cid"]:  # empty struct = no record
        return None

    try:
        record["recalled"] = bool(c.functions.recalled(medicine_id).call())
        record["recall_reason"] = c.functions.recallReason(medicine_id).call() if record["recalled"] else ""
    except Exception:
        record["recalled"], record["recall_reason"] = False, ""
    try:
        record["expired"] = bool(c.functions.isExpired(medicine_id).call())
    except Exception:
        record["expired"] = False
    if not record.get("id"):
        record["id"] = medicine_id
    try:
        from services import ipfs
        manifest = ipfs.get_local_manifest(medicine_id) or (ipfs.get_local_manifest(record.get("batch", "")) if record.get("batch") else None)
        if manifest:
            record["total_images"] = manifest.get("total_images", len(manifest.get("images", [])))
            record["manifest_cid"] = manifest.get("manifest_cid")
            record["images"] = manifest.get("images", [])
    except Exception:
        pass
    return record


def find_record(medicine_id: str):
    """Find a medicine by its registered ID or batch number."""
    query = medicine_id.strip()
    if not query or is_batch_archived(query):
        return None

    record = read_record(query)
    if record is not None:
        return record

    try:
        contract = _get_contract()
        events = contract.events.MedicineRegistered.get_logs(
            from_block=0,
            to_block="latest",
        )

        for event in reversed(events):
            registered_id = event["args"].get("id", "")
            if not registered_id:
                continue

            record = read_record(registered_id)
            if record and str(record.get("batch", "")).strip().casefold() == query.casefold():
                return record
    except Exception:
        pass

    return None



def get_all_batches(stage: int = None, manufacturer: str = None) -> list:
    """Retrieve all registered medicines/batches from blockchain.
    Optionally filter by stage (1=Manufactured, 2=Distributor, 3=Pharmacy)
    or by manufacturer address.
    """
    contract = _get_contract()
    batches = []
    seen = set()
    try:
        events = contract.events.MedicineRegistered.get_logs(
            from_block=0,
            to_block="latest",
        )
        for ev in reversed(events):
            med_id = ev["args"].get("id")
            if not med_id or med_id in seen or is_batch_archived(med_id):
                continue
            seen.add(med_id)
            record = read_record(med_id)
            if not record:
                continue
            record["id"] = med_id

            if stage is not None and int(record.get("stage", 0)) != int(stage):
                continue
            if manufacturer and record.get("manufacturer", "").lower() != manufacturer.lower():
                continue

            batches.append(record)
    except Exception:
        pass
    return batches


def read_history(medicine_id: str):
    """Read the actual transfer history stored in the smart contract."""
    contract = _get_contract()
    entries = contract.functions.getHistory(medicine_id).call()

    history = []
    for entry in entries:
        sender, recipient, timestamp = entry
        history.append({
            "from": str(sender),
            "to": str(recipient),
            "timestamp": int(timestamp),
        })

    return history


def read_stages(medicine_id: str):
    """Read distributor and pharmacy stage records from smart contract."""
    try:
        contract = _get_contract()
        dist, pharm = contract.functions.getStages(medicine_id).call()
        return {
            "distributor": {
                "actor": str(dist[0]),
                "timestamp": int(dist[1]),
                "details": str(dist[2]),
            },
            "pharmacy": {
                "actor": str(pharm[0]),
                "timestamp": int(pharm[1]),
                "details": str(pharm[2]),
            },
        }
    except Exception:
        return {
            "distributor": {"actor": ZERO_ADDRESS, "timestamp": 0, "details": ""},
            "pharmacy": {"actor": ZERO_ADDRESS, "timestamp": 0, "details": ""},
        }


def get_user(address: str):
    """Read User struct for a given wallet address."""
    contract = _get_contract()
    c_addr = Web3.to_checksum_address(address)
    raw = contract.functions.users(c_addr).call()
    role_num = int(raw[0])
    status_num = int(raw[1])
    return {
        "address": c_addr,
        "role": role_num,
        "role_name": ROLE_NAMES.get(role_num, "None"),
        "status": status_num,
        "status_name": STATUS_NAMES.get(status_num, "Pending"),
        "name": str(raw[2]),
        "manufacturer": str(raw[3]),
        "distributor": str(raw[4]),
        "adminOk": bool(raw[5]),
        "mfrOk": bool(raw[6]),
        "distOk": bool(raw[7]),
    }


def get_all_users():
    """Retrieve all registered users, admin, and on-chain registration/approval audit metadata."""
    contract = _get_contract()
    users_list = []
    seen = set()

    reg_events_by_addr: dict[str, dict] = {}
    status_events_by_addr: dict[str, list] = {}

    try:
        reg_events = contract.events.UserRegistered.get_logs(from_block=0, to_block="latest")
        for ev in reg_events:
            u_addr = str(ev["args"]["user"])
            blk_num = int(ev["blockNumber"])
            tx_h = ev["transactionHash"].hex()
            try:
                ts = int(w3.eth.get_block(blk_num)["timestamp"])
            except Exception:
                ts = 0
            reg_events_by_addr[u_addr.lower()] = {
                "tx_hash": tx_h,
                "block_number": blk_num,
                "timestamp": ts,
            }
    except Exception:
        reg_events = []

    try:
        st_events = contract.events.UserStatus.get_logs(from_block=0, to_block="latest")
        for ev in st_events:
            u_addr = str(ev["args"]["user"]).lower()
            st_num = int(ev["args"]["status"])
            blk_num = int(ev["blockNumber"])
            tx_h = ev["transactionHash"].hex()
            try:
                ts = int(w3.eth.get_block(blk_num)["timestamp"])
            except Exception:
                ts = 0
            status_events_by_addr.setdefault(u_addr, []).append({
                "status": st_num,
                "status_name": STATUS_NAMES.get(st_num, "Unknown"),
                "tx_hash": tx_h,
                "block_number": blk_num,
                "timestamp": ts,
            })
    except Exception:
        pass

    # Always include admin
    try:
        admin_addr = contract.functions.admin().call()
        admin_info = get_user(admin_addr)
        admin_info["is_admin"] = True
        admin_info["status_events"] = []
        users_list.append(admin_info)
        seen.add(admin_addr.lower())
    except Exception:
        pass

    # Include all UserRegistered event addresses
    for ev in reg_events:
        user_addr = ev["args"]["user"]
        addr_low = user_addr.lower()
        if addr_low not in seen:
            seen.add(addr_low)
            u_info = get_user(user_addr)
            reg_meta = reg_events_by_addr.get(addr_low, {})
            u_info["registration_tx_hash"] = reg_meta.get("tx_hash", "")
            u_info["registration_block"] = reg_meta.get("block_number")
            u_info["registered_at"] = reg_meta.get("timestamp", 0)
            u_info["status_events"] = status_events_by_addr.get(addr_low, [])
            users_list.append(u_info)

    # Resolve upstream manufacturer & distributor names for readability
    name_by_addr = {u["address"].lower(): u["name"] for u in users_list if u.get("address")}
    for u in users_list:
        m_addr = (u.get("manufacturer") or "").lower()
        d_addr = (u.get("distributor") or "").lower()
        u["manufacturer_name"] = name_by_addr.get(m_addr, "") if m_addr and m_addr != ZERO_ADDRESS else ""
        u["distributor_name"] = name_by_addr.get(d_addr, "") if d_addr and d_addr != ZERO_ADDRESS else ""

    return users_list


def _fund_account(target_address: str, amount_eth: float = 1.0) -> None:
    """Fund a newly created organization wallet from the Admin development account."""
    admin_acct = w3.eth.account.from_key(DEFAULT_ADMIN_KEY)
    tx = {
        "from": admin_acct.address,
        "to": Web3.to_checksum_address(target_address),
        "value": w3.to_wei(amount_eth, "ether"),
        "nonce": w3.eth.get_transaction_count(admin_acct.address),
        "chainId": w3.eth.chain_id,
        "gas": 21000,
        "gasPrice": w3.eth.gas_price,
    }
    signed = w3.eth.account.sign_transaction(tx, DEFAULT_ADMIN_KEY)
    raw = getattr(signed, "raw_transaction", None) or getattr(signed, "rawTransaction", None)
    tx_hash = w3.eth.send_raw_transaction(raw)
    w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)


def register_user_with_details(
    role_val,
    name: str,
    linked_mfr: str = "",
    linked_dist: str = "",
    private_key: str = None,
) -> dict:
    """Register an organization user on-chain and return full tx + address details."""
    if isinstance(role_val, str):
        r_clean = role_val.lower().strip()
        if r_clean == "admin":
            raise PermissionError("Public registration for Admin role is not allowed.")
        role_num = ROLE_MAP.get(r_clean, 0)
    else:
        role_num = int(role_val)
        if role_num == 1:
            raise PermissionError("Public registration for Admin role is not allowed.")

    if role_num not in (2, 3, 4):
        raise ValueError("Role must be Manufacturer (2), Distributor (3), or Pharmacy (4)")

    contract = _get_contract()
    generated_new_key = False

    if private_key:
        key = private_key
    else:
        key = get_key_for_role(ROLE_NAMES.get(role_num, ""))
        acct = w3.eth.account.from_key(key)
        existing_role = int(contract.functions.users(acct.address).call()[0])
        if existing_role != 0:
            new_acct = w3.eth.account.create()
            _fund_account(new_acct.address, 1.0)
            key = new_acct.key.hex()
            generated_new_key = True

    signer_address = w3.eth.account.from_key(key).address

    if role_num == 3 and (not linked_mfr or linked_mfr == ZERO_ADDRESS):
        linked_mfr = w3.eth.account.from_key(DEFAULT_MFR_KEY).address
    elif role_num == 4 and (not linked_dist or linked_dist == ZERO_ADDRESS):
        linked_dist = w3.eth.account.from_key(DEFAULT_DIST_KEY).address

    mfr_addr = Web3.to_checksum_address(linked_mfr) if linked_mfr and linked_mfr != ZERO_ADDRESS else ZERO_ADDRESS
    dist_addr = Web3.to_checksum_address(linked_dist) if linked_dist and linked_dist != ZERO_ADDRESS else ZERO_ADDRESS

    call = contract.functions.register(
        role_num,
        name.strip(),
        mfr_addr,
        dist_addr,
    )
    tx_hash = _send_tx(call, key)
    meta = get_tx_meta(tx_hash)
    return {
        "tx_hash": tx_hash,
        "address": signer_address,
        "private_key": key if generated_new_key or private_key else None,
        "block_number": meta.get("block_number"),
        "timestamp": meta.get("timestamp"),
        "linked_manufacturer": mfr_addr,
        "linked_distributor": dist_addr,
    }


def register_user(role_val, name: str, linked_mfr: str = "", linked_dist: str = "", private_key: str = None) -> str:
    """Register an organization user on-chain and return the transaction hash."""
    res = register_user_with_details(
        role_val,
        name,
        linked_mfr=linked_mfr,
        linked_dist=linked_dist,
        private_key=private_key,
    )
    return res["tx_hash"]


def approve_user(target_address: str, signer_role: str = "admin", private_key: str = None) -> str:
    """Approve a pending organization user."""
    contract = _get_contract()
    target_chk = Web3.to_checksum_address(target_address)
    key = private_key or get_key_for_role(signer_role)
    call = contract.functions.approve(target_chk)
    return _send_tx(call, key)


def reject_user(target_address: str, signer_role: str = "admin", private_key: str = None) -> str:
    """Reject a pending organization user."""
    contract = _get_contract()
    target_chk = Web3.to_checksum_address(target_address)
    key = private_key or get_key_for_role(signer_role)
    call = contract.functions.reject(target_chk)
    return _send_tx(call, key)


def distributor_receive(medicine_id: str, details: str = "", private_key: str = None) -> str:
    """Record distributor receipt on blockchain (Stage 1 -> 2)."""
    contract = _get_contract()
    key = private_key or DEFAULT_DIST_KEY
    call = contract.functions.distributorReceive(medicine_id.strip(), details.strip() or "Received at distributor hub")
    return _send_tx(call, key)


def pharmacy_receive(medicine_id: str, details: str = "", private_key: str = None) -> str:
    """Record pharmacy receipt on blockchain (Stage 2 -> 3)."""
    contract = _get_contract()
    key = private_key or DEFAULT_PHARM_KEY
    call = contract.functions.pharmacyReceive(medicine_id.strip(), details.strip() or "Verified and stocked at pharmacy")
    return _send_tx(call, key)


def register_medicine(
    medicine_id: str,
    name: str,
    batch: str,
    expiry_timestamp: int,
    image_cid: str,
    quantity: int = 100,
    private_key: str = None,
) -> str:
    """Register a medicine on the blockchain (Manufacturer)."""
    key = private_key or os.getenv("MANUFACTURER_PRIVATE_KEY", DEFAULT_MFR_KEY)
    if not is_connected():
        raise RuntimeError("Blockchain node is unavailable")

    contract = _get_contract()
    account = w3.eth.account.from_key(key)

    user = contract.functions.users(account.address).call()
    role = int(user[0])
    status = int(user[1])

    if role != 2 or status != 1:
        raise RuntimeError(
            f"Wallet {account.address} must be an active manufacturer (role={role}, status={status})"
        )

    call = contract.functions.registerMedicine(
        medicine_id,
        name,
        batch,
        int(expiry_timestamp),
        image_cid,
        int(quantity),
    )
    return _send_tx(call, key)


def recall_medicine(medicine_id: str, reason: str, signer_role: str = "manufacturer", private_key: str = None) -> str:
    """Recall a registered medicine batch on-chain (Manufacturer or Admin only)."""
    contract = _get_contract()
    key = private_key or get_key_for_role(signer_role)
    call = contract.functions.recallMedicine(
        medicine_id.strip(),
        reason.strip() or "Quality recall initiated",
    )
    return _send_tx(call, key)


def _resolve_org_name(address: str) -> str:
    if not address or address == ZERO_ADDRESS:
        return ""
    try:
        u = get_user(address)
        return u.get("name") or address
    except Exception:
        return address


def read_audit_trail(medicine_id: str) -> dict:
    """Build a complete, factual on-chain audit trail and 4-stage journey timeline for a medicine."""
    contract = _get_contract()
    record = read_record(medicine_id)
    if not record:
        return {"events": [], "journey": []}

    stages = read_stages(medicine_id)
    raw = record.get("raw", {})
    actual_id = str(raw.get("id") or record.get("batch") or medicine_id)
    current_stage = int(record.get("stage", 1))
    mfr_addr = record.get("manufacturer", ZERO_ADDRESS)
    dist_addr = record.get("distributor", ZERO_ADDRESS)
    pharm_addr = record.get("pharmacy", ZERO_ADDRESS)
    reg_ts = int(raw.get("registeredAt") or 0)

    mfr_name = _resolve_org_name(mfr_addr)
    dist_name = _resolve_org_name(dist_addr)
    pharm_name = _resolve_org_name(pharm_addr)

    reg_ev_meta = {}
    dist_ev_meta = {}
    pharm_ev_meta = {}
    recall_ev_meta = {}
    events_list = []

    try:
        for ev in contract.events.MedicineRegistered.get_logs(from_block=0, to_block="latest"):
            if ev["args"].get("id") == medicine_id:
                blk = int(ev["blockNumber"])
                tx_h = ev["transactionHash"].hex()
                try:
                    ts = int(w3.eth.get_block(blk)["timestamp"])
                except Exception:
                    ts = reg_ts
                reg_ev_meta = {"tx_hash": tx_h, "block_number": blk, "timestamp": ts}
                events_list.append({
                    "event": "MedicineRegistered",
                    "stage": 1,
                    "actor": mfr_addr,
                    "actor_name": mfr_name,
                    "transaction_hash": tx_h,
                    "block_number": blk,
                    "timestamp": ts,
                    "confirmation_status": "Confirmed",
                    "is_on_chain": True,
                })
    except Exception:
        pass

    try:
        for ev in contract.events.DistributorReceived.get_logs(from_block=0, to_block="latest"):
            if ev["args"].get("id") == medicine_id:
                blk = int(ev["blockNumber"])
                tx_h = ev["transactionHash"].hex()
                try:
                    ts = int(w3.eth.get_block(blk)["timestamp"])
                except Exception:
                    ts = int(stages["distributor"].get("timestamp") or 0)
                dist_ev_meta = {"tx_hash": tx_h, "block_number": blk, "timestamp": ts}
                events_list.append({
                    "event": "DistributorReceived",
                    "stage": 2,
                    "actor": dist_addr,
                    "actor_name": dist_name,
                    "transaction_hash": tx_h,
                    "block_number": blk,
                    "timestamp": ts,
                    "details": stages["distributor"].get("details", ""),
                    "confirmation_status": "Confirmed",
                    "is_on_chain": True,
                })
    except Exception:
        pass

    try:
        for ev in contract.events.PharmacyReceived.get_logs(from_block=0, to_block="latest"):
            if ev["args"].get("id") == medicine_id:
                blk = int(ev["blockNumber"])
                tx_h = ev["transactionHash"].hex()
                try:
                    ts = int(w3.eth.get_block(blk)["timestamp"])
                except Exception:
                    ts = int(stages["pharmacy"].get("timestamp") or 0)
                pharm_ev_meta = {"tx_hash": tx_h, "block_number": blk, "timestamp": ts}
                events_list.append({
                    "event": "PharmacyReceived",
                    "stage": 3,
                    "actor": pharm_addr,
                    "actor_name": pharm_name,
                    "transaction_hash": tx_h,
                    "block_number": blk,
                    "timestamp": ts,
                    "details": stages["pharmacy"].get("details", ""),
                    "confirmation_status": "Confirmed",
                    "is_on_chain": True,
                })
    except Exception:
        pass

    if record.get("recalled"):
        try:
            for ev in contract.events.MedicineRecalled.get_logs(from_block=0, to_block="latest"):
                if ev["args"].get("id") == medicine_id:
                    blk = int(ev["blockNumber"])
                    tx_h = ev["transactionHash"].hex()
                    by_addr = str(ev["args"].get("by", ""))
                    reason_str = str(ev["args"].get("reason", record.get("recall_reason", "")))
                    try:
                        ts = int(w3.eth.get_block(blk)["timestamp"])
                    except Exception:
                        ts = 0
                    recall_ev_meta = {
                        "tx_hash": tx_h,
                        "block_number": blk,
                        "timestamp": ts,
                        "by": by_addr,
                        "by_name": _resolve_org_name(by_addr),
                        "reason": reason_str,
                    }
                    events_list.append({
                        "event": "MedicineRecalled",
                        "actor": by_addr,
                        "actor_name": _resolve_org_name(by_addr),
                        "transaction_hash": tx_h,
                        "block_number": blk,
                        "timestamp": ts,
                        "details": reason_str,
                        "confirmation_status": "Confirmed",
                        "is_on_chain": True,
                    })
        except Exception:
            pass

    consumer_ev = (
        get_consumer_verification(actual_id)
        or get_consumer_verification(medicine_id)
        or get_consumer_verification(str(record.get("batch") or ""))
    )

    journey = [
        {
            "stage": 1,
            "title": "Manufacturer Registration",
            "organization": mfr_name or "Registered Manufacturer",
            "actor_address": mfr_addr,
            "completed": True,
            "status": "Confirmed on-chain",
            "is_on_chain": True,
            "event_name": "MedicineRegistered",
            "timestamp": reg_ev_meta.get("timestamp") or reg_ts,
            "transaction_hash": reg_ev_meta.get("tx_hash", ""),
            "block_number": reg_ev_meta.get("block_number"),
            "details": f"Batch {record.get('batch')} ({record.get('quantity')} units) registered with IPFS reference CID {record.get('ipfs_cid')}.",
        },
        {
            "stage": 2,
            "title": "Distributor Receipt & Custody",
            "organization": dist_name if current_stage >= 2 else "Awaiting Authorized Distributor",
            "actor_address": dist_addr if current_stage >= 2 else "",
            "completed": current_stage >= 2,
            "status": "Confirmed on-chain" if current_stage >= 2 else "Pending distributor receipt",
            "is_on_chain": current_stage >= 2,
            "event_name": "DistributorReceived" if current_stage >= 2 else "",
            "timestamp": dist_ev_meta.get("timestamp") or int(stages["distributor"].get("timestamp") or 0),
            "transaction_hash": dist_ev_meta.get("tx_hash", ""),
            "block_number": dist_ev_meta.get("block_number"),
            "details": stages["distributor"].get("details") if current_stage >= 2 else "Batch has not yet been received by a distributor.",
        },
        {
            "stage": 3,
            "title": "Pharmacy Receipt & Retail Stock",
            "organization": pharm_name if current_stage >= 3 else "Awaiting Authorized Pharmacy",
            "actor_address": pharm_addr if current_stage >= 3 else "",
            "completed": current_stage >= 3,
            "status": "Confirmed on-chain" if current_stage >= 3 else "Pending pharmacy receipt",
            "is_on_chain": current_stage >= 3,
            "event_name": "PharmacyReceived" if current_stage >= 3 else "",
            "timestamp": pharm_ev_meta.get("timestamp") or int(stages["pharmacy"].get("timestamp") or 0),
            "transaction_hash": pharm_ev_meta.get("tx_hash", ""),
            "block_number": pharm_ev_meta.get("block_number"),
            "details": stages["pharmacy"].get("details") if current_stage >= 3 else "Batch has not yet been received by a retail pharmacy.",
        },
        {
            "stage": 4,
            "title": "Consumer Verification",
            "organization": "Public Consumer Verification",
            "actor_address": "",
            "completed": consumer_ev is not None,
            "status": (
                f"Verified by consumer ({consumer_ev['verdict']})"
                if consumer_ev is not None
                else "Pending consumer verification"
            ),
            "is_on_chain": False,
            "event_name": "ConsumerVerificationRecorded" if consumer_ev is not None else "PendingVerification",
            "timestamp": consumer_ev["timestamp"] if consumer_ev is not None else 0,
            "transaction_hash": "",
            "block_number": None,
            "details": (
                f"Consumer verification recorded with verdict '{consumer_ev['verdict']}'. Method: {consumer_ev.get('method', 'verification')}."
                if consumer_ev is not None
                else "Awaiting consumer verification. Scan QR code or submit package photo to verify."
            ),
        },
    ]

    return {
        "events": events_list,
        "journey": journey,
        "recall_event": recall_ev_meta if record.get("recalled") else None,
        "organizations": {
            "manufacturer_name": mfr_name,
            "distributor_name": dist_name,
            "pharmacy_name": pharm_name,
        },
    }
