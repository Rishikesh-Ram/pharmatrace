"""Uploads and fetches images via Pinata with local cache fallback."""
import io
import os
from pathlib import Path

import requests
from PIL import Image

PINATA_JWT = os.getenv("PINATA_JWT", "")
PINATA_GATEWAY = os.getenv("PINATA_GATEWAY", "https://gateway.pinata.cloud/ipfs/")
PINATA_UPLOAD_URL = "https://api.pinata.cloud/pinning/pinFileToIPFS"

CACHE_DIR = Path(__file__).resolve().parent.parent / "data" / "ipfs_cache"
DEMO_REFERENCE_CID = "QmRPfUZb5v52nNjgV6wWE7biJnaHJbY9voczuVT25qujvr"
DEMO_REFERENCE_PATH = Path(__file__).resolve().parent.parent / "dataset" / "reference" / "packet_back.jpg"


def _cache_path(cid: str) -> Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    safe_cid = "".join(c for c in cid if c.isalnum() or c in ("_", "-"))
    return CACHE_DIR / f"{safe_cid}.jpg"


def upload_image(data: bytes, filename: str = "reference.jpg") -> str:
    """Pins an image on Pinata and returns its CID (store this on the blockchain)."""
    if not PINATA_JWT:
        raise RuntimeError("PINATA_JWT is not set in .env")
    r = requests.post(
        PINATA_UPLOAD_URL,
        headers={"Authorization": f"Bearer {PINATA_JWT}"},
        files={"file": (filename, data)},
        timeout=60,
    )
    r.raise_for_status()
    cid = r.json()["IpfsHash"]
    try:
        _cache_path(cid).write_bytes(data)
    except Exception:
        pass
    return cid


def fetch_image(cid: str) -> Image.Image:
    """Downloads the reference image for a CID through the gateway or local cache."""
    cid = cid.replace("ipfs://", "").strip()
    if not cid:
        raise ValueError("Empty IPFS CID")

    cached = _cache_path(cid)
    if cached.is_file():
        return Image.open(cached).convert("RGB")

    try:
        r = requests.get(PINATA_GATEWAY + cid, timeout=12)
        r.raise_for_status()
        try:
            cached.write_bytes(r.content)
        except Exception:
            pass
        return Image.open(io.BytesIO(r.content)).convert("RGB")
    except Exception:
        if cid == DEMO_REFERENCE_CID and DEMO_REFERENCE_PATH.is_file():
            return Image.open(DEMO_REFERENCE_PATH).convert("RGB")
        raise
