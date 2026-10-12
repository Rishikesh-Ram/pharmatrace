"""Manual check against the running server.
Usage: python tests/send_test_request.py MED-001 path/to/photo.jpg"""
import sys

import requests

medicine_id, image_path = sys.argv[1], sys.argv[2]
with open(image_path, "rb") as f:
    r = requests.post("http://127.0.0.1:5000/verify",
                      data={"medicine_id": medicine_id}, files={"image": f})
print(r.status_code)
print(r.json())
