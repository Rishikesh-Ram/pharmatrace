
from pathlib import Path
from dotenv import load_dotenv
from PIL import Image, ImageEnhance, ImageFilter
import pytesseract

load_dotenv()

import os

if os.getenv("TESSERACT_CMD"):
    pytesseract.pytesseract.tesseract_cmd = os.environ["TESSERACT_CMD"]

BASE_DIR = Path(__file__).resolve().parent
REF_DIR = BASE_DIR / "dataset" / "reference"

images = [
    "packet_back.jpg",
    "strip_front.jpg",
    "strip_back.jpg",
]

for filename in images:
    path = REF_DIR / filename

    with Image.open(path) as original:
        img = original.convert("RGB")

        # Enlarge the image for OCR
        img = img.resize(
            (img.width * 2, img.height * 2),
            Image.Resampling.LANCZOS,
        )

        # Enhance contrast and sharpen text
        img = ImageEnhance.Contrast(img).enhance(1.8)
        img = img.filter(ImageFilter.SHARPEN)

        text = pytesseract.image_to_string(
            img,
            config="--psm 11",
        )

    print(f"\n{'=' * 50}")
    print(f"IMAGE: {filename}")
    print("-" * 50)
    print(text.strip() or "[No text detected]")
