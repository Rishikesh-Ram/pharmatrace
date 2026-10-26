"""Uploads and fetches images via Pinata with local cache fallback."""
import io
import os
from pathlib import Path

import requests
from PIL import Image

PINATA_JWT = os.getenv("PINATA_JWT", "")
PINATA_GATEWAY = os.getenv("PINATA_GATEWAY", "https://gateway.pinata.cloud/ipfs/")
PINATA_UPLOAD_URL = "https://api.pinata.cloud/pinning/pinFileToIPFS"
PINATA_JSON_URL = "https://api.pinata.cloud/pinning/pinJSONToIPFS"

CACHE_DIR = Path(__file__).resolve().parent.parent / "data" / "ipfs_cache"
MANIFEST_DIR = Path(__file__).resolve().parent.parent / "data" / "manifests"
DEMO_REFERENCE_CID = "QmRPfUZb5v52nNjgV6wWE7biJnaHJbY9voczuVT25qujvr"
DEMO_REFERENCE_PATH = Path(__file__).resolve().parent.parent / "dataset" / "reference" / "packet_back.jpg"


def _cache_path(cid: str, suffix: str = ".jpg") -> Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    safe_cid = "".join(c for c in cid if c.isalnum() or c in ("_", "-"))
    return CACHE_DIR / f"{safe_cid}{suffix}"


def upload_image(data: bytes, filename: str = "reference.jpg") -> str:
    """Pins an image on Pinata and returns its CID (store this on the blockchain)."""
    if not PINATA_JWT:
        raise RuntimeError("PINATA_JWT is not set in .env")
    ext = os.path.splitext(filename)[1].lower() or ".jpg"
    r = requests.post(
        PINATA_UPLOAD_URL,
        headers={"Authorization": f"Bearer {PINATA_JWT}"},
        files={"file": (filename, data)},
        timeout=60,
    )
    r.raise_for_status()
    cid = r.json()["IpfsHash"]
    try:
        _cache_path(cid, suffix=ext).write_bytes(data)
        # Also cache as .jpg for fetch_image fallback
        if ext != ".jpg":
            _cache_path(cid, suffix=".jpg").write_bytes(data)
    except Exception:
        pass
    return cid


def upload_json(payload: dict, name: str = "manifest.json") -> str:
    """Pins a JSON manifest to Pinata and returns its CID."""
    if not PINATA_JWT:
        raise RuntimeError("PINATA_JWT is not set in .env")
    r = requests.post(
        PINATA_JSON_URL,
        headers={
            "Authorization": f"Bearer {PINATA_JWT}",
            "Content-Type": "application/json",
        },
        json={"pinataContent": payload, "pinataMetadata": {"name": name}},
        timeout=60,
    )
    r.raise_for_status()
    cid = r.json()["IpfsHash"]
    try:
        import json
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        safe_cid = "".join(c for c in cid if c.isalnum() or c in ("_", "-"))
        (CACHE_DIR / f"{safe_cid}.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    except Exception:
        pass
    return cid


def save_local_manifest(batch_id: str, manifest: dict) -> Path:
    """Saves package manifest to local data directory."""
    import json
    MANIFEST_DIR.mkdir(parents=True, exist_ok=True)
    safe_id = "".join(c for c in batch_id if c.isalnum() or c in ("_", "-"))
    p = MANIFEST_DIR / f"{safe_id}.json"
    p.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return p


def get_local_manifest(batch_id: str) -> dict | None:
    """Retrieves local package manifest for a batch if present."""
    import json
    safe_id = "".join(c for c in batch_id if c.isalnum() or c in ("_", "-"))
    p = MANIFEST_DIR / f"{safe_id}.json"
    if p.is_file():
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            return None
    return None


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
