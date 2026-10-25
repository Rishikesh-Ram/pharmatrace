"""Talks to the smart contract (web3.py)."""
import json
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
    return tx_hash.hex()


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


def read_record(medicine_id: str):
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
    return record


def find_record(medicine_id: str):
    """Find a medicine by its registered ID or batch number."""
    query = medicine_id.strip()
    if not query:
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
            if not med_id or med_id in seen:
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
    """Retrieve all registered users and admin."""
    contract = _get_contract()
    users_list = []
    seen = set()

    # Always include admin
    try:
        admin_addr = contract.functions.admin().call()
        admin_info = get_user(admin_addr)
        admin_info["is_admin"] = True
        users_list.append(admin_info)
        seen.add(admin_addr.lower())
    except Exception:
        pass

    # Read all UserRegistered events from block 0
    try:
        events = contract.events.UserRegistered.get_logs(from_block=0, to_block="latest")
        for ev in events:
            user_addr = ev["args"]["user"]
            if user_addr.lower() not in seen:
                seen.add(user_addr.lower())
                users_list.append(get_user(user_addr))
    except Exception:
        pass

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


def register_user(role_val, name: str, linked_mfr: str = "", linked_dist: str = "", private_key: str = None) -> str:
    """Register an organization user on-chain."""
    if isinstance(role_val, str):
        role_num = ROLE_MAP.get(role_val.lower().strip(), 0)
    else:
        role_num = int(role_val)

    if role_num not in (2, 3, 4):
        raise ValueError("Role must be Manufacturer (2), Distributor (3), or Pharmacy (4)")

    contract = _get_contract()

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
    return _send_tx(call, key)


def approve_user(target_address: str, signer_role: str = "admin") -> str:
    """Approve a pending organization user."""
    contract = _get_contract()
    target_chk = Web3.to_checksum_address(target_address)
    key = get_key_for_role(signer_role)
    call = contract.functions.approve(target_chk)
    return _send_tx(call, key)


def reject_user(target_address: str, signer_role: str = "admin") -> str:
    """Reject a pending organization user."""
    contract = _get_contract()
    target_chk = Web3.to_checksum_address(target_address)
    key = get_key_for_role(signer_role)
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
