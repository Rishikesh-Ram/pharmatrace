
from pathlib import Path
from PIL import Image
from services import vision

BASE_DIR = Path(__file__).resolve().parent
REF_DIR = BASE_DIR / "dataset" / "reference"

IMAGES = [
    "packet_front.jpg",
    "packet_back.jpg",
    "packet_longside1.jpg",
    "packet_longside2.jpg",
    "packet_shortside1.jpg",
    "packet_shortside2.jpg",
    "strip_front.jpg",
    "strip_back.jpg",
]


def compare(image_a, image_b):
    with Image.open(image_a) as a, Image.open(image_b) as b:
        return vision.similarity(a, b)


if __name__ == "__main__":
    print("Comparing all reference image pairs...\n")

    for i, name_a in enumerate(IMAGES):
        for name_b in IMAGES[i + 1:]:
            score = compare(
                REF_DIR / name_a,
                REF_DIR / name_b,
            )
            print(f"{name_a} vs {name_b}: {score:.4f}")

    print("\nAll comparisons complete.")
    print("Scores are exploratory, not authenticity verdicts.")
