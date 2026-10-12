"""Talks to the smart contract (web3.py)."""
import json
import os

from web3 import Web3

RPC_URL = os.getenv("RPC_URL", "http://127.0.0.1:8545")
CONTRACT_ADDRESS = os.getenv("CONTRACT_ADDRESS", "")
ABI_PATH = os.getenv("ABI_PATH", "contract_abi.json")
CONTRACT_GETTER = os.getenv("CONTRACT_GETTER", "getMedicine")

w3 = Web3(Web3.HTTPProvider(RPC_URL))
_contract = None


def is_connected() -> bool:
    try:
        return w3.is_connected()
    except Exception:
        return False


def _get_contract():
    global _contract
    if _contract is None:
        with open(ABI_PATH) as f:
            abi = json.load(f)
        _contract = w3.eth.contract(
            address=Web3.to_checksum_address(CONTRACT_ADDRESS), abi=abi
        )
    return _contract


def _components(function_name: str):
    """Field names of the struct returned by the given contract function (from the ABI)."""
    with open(ABI_PATH) as f:
        abi = json.load(f)
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
    # a single struct output can arrive wrapped in an extra tuple
    if isinstance(values, (tuple, list)) and len(values) == 1 and isinstance(values[0], (tuple, list)):
        values = values[0]
    if isinstance(values, dict):
        data = values
    else:
        data = dict(zip(names, values))

    return {
        "name": _pick(data, "name"),
        "batch": _pick(data, "batch", "batchNumber"),
        "manufacturer": str(_pick(data, "manufacturer", "currentOwner", "owner")),
        "ipfs_cid": _pick(data, "imageHash", "ipfsHash", "imageCid"),
        "expiry": _pick(data, "expiry", default=None),
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
    return record