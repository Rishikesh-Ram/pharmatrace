"""Uploads and fetches images via Pinata."""
import io
import os

import requests
from PIL import Image

PINATA_JWT = os.getenv("PINATA_JWT", "")
PINATA_GATEWAY = os.getenv("PINATA_GATEWAY", "https://gateway.pinata.cloud/ipfs/")
PINATA_UPLOAD_URL = "https://api.pinata.cloud/pinning/pinFileToIPFS"


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
    return r.json()["IpfsHash"]


def fetch_image(cid: str) -> Image.Image:
    """Downloads the reference image for a CID through the gateway."""
    cid = cid.replace("ipfs://", "")
    r = requests.get(PINATA_GATEWAY + cid, timeout=20)
    r.raise_for_status()
    return Image.open(io.BytesIO(r.content)).convert("RGB")
