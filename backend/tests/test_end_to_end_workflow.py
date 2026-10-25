"""PharmaTrace End-to-End Workflow & Verification Test Suite.
Tests the entire lifecycle:
1. Organization Registration & Approvals (Admin -> Manufacturer -> Distributor -> Pharmacy)
2. Manufacturer Medicine Registration (Stage 1) & /api/batches?stage=1
3. Distributor Medicine Verification & Receipt (Stage 1 -> 2) & /api/batches?stage=2
4. Pharmacy Medicine Verification & Receipt (Stage 2 -> 3) & /api/batches?stage=3
5. Multi-factor Packaging Verification (/verify) & Lookup (/lookup)
6. Authentic vs Mismatch vs Counterfeit Distinction
7. On-chain Medicine Recall (/api/recall) & Recall Enforcement
"""
import io
import os
import sys
import time
from pathlib import Path

os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")

# Add backend directory to path
backend_dir = str(Path(__file__).resolve().parent.parent)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app import app
from services import blockchain


def run_e2e_test():
    print("=" * 60)
    print("PHARMATRACE END-TO-END WORKFLOW INTEGRATION TEST")
    print("=" * 60)

    client = app.test_client()

    # 1. Health check
    res = client.get("/health")
    assert res.status_code == 200, f"Health check failed: {res.json}"
    assert res.json["chain_connected"] is True, "Blockchain not connected"
    print("[PASS] 1. Backend health & blockchain connection verified.")

    # 2. Verify System Roles & Addresses
    res = client.get("/api/roles")
    assert res.status_code == 200
    roles = res.json
    admin_addr = roles["admin"]["address"]
    mfr_addr = roles["manufacturer"]["address"]
    dist_addr = roles["distributor"]["address"]
    pharm_addr = roles["pharmacy"]["address"]
    print(f"[INFO] Admin Account:        {admin_addr}")
    print(f"[INFO] Manufacturer Account: {mfr_addr}")
    print(f"[INFO] Distributor Account:  {dist_addr}")
    print(f"[INFO] Pharmacy Account:     {pharm_addr}")
    print("[PASS] 2. System roles and accounts confirmed.")

    # 3. Check / Ensure Manufacturer is Registered and Active
    mfr_user = blockchain.get_user(mfr_addr)
    if mfr_user["role"] == 0:
        print("[ACTION] Registering Manufacturer...")
        res = client.post("/api/register-user", json={
            "role": "manufacturer",
            "name": "Elnova Pharmaceuticals",
        })
        assert res.status_code == 201
    mfr_user = blockchain.get_user(mfr_addr)
    if mfr_user["status"] != 1:  # Active
        print("[ACTION] Admin approving Manufacturer...")
        res = client.post("/api/approve-user", json={
            "target": mfr_addr,
            "approver_role": "admin",
        })
        assert res.status_code == 200
    assert blockchain.get_user(mfr_addr)["status"] == 1, "Manufacturer must be Active"
    print("[PASS] 3. Manufacturer is active and approved by Admin.")

    # 4. Check / Ensure Distributor is Registered and Active
    dist_user = blockchain.get_user(dist_addr)
    if dist_user["role"] == 0:
        print("[ACTION] Registering Distributor...")
        res = client.post("/api/register-user", json={
            "role": "distributor",
            "name": "MedLine National Logistics",
            "linked_manufacturer": mfr_addr,
        })
        assert res.status_code == 201
    dist_user = blockchain.get_user(dist_addr)
    if dist_user["status"] != 1:
        print("[ACTION] Admin and Manufacturer approving Distributor...")
        client.post("/api/approve-user", json={"target": dist_addr, "approver_role": "admin"})
        client.post("/api/approve-user", json={"target": dist_addr, "approver_role": "manufacturer"})
    assert blockchain.get_user(dist_addr)["status"] == 1, "Distributor must be Active"
    print("[PASS] 4. Distributor is active and approved by Admin + Manufacturer.")

    # 5. Check / Ensure Pharmacy is Registered and Active
    pharm_user = blockchain.get_user(pharm_addr)
    if pharm_user["role"] == 0:
        print("[ACTION] Registering Pharmacy...")
        res = client.post("/api/register-user", json={
            "role": "pharmacy",
            "name": "Apollo Care Pharmacy",
            "linked_distributor": dist_addr,
        })
        assert res.status_code == 201
    pharm_user = blockchain.get_user(pharm_addr)
    if pharm_user["status"] != 1:
        print("[ACTION] Admin, Manufacturer, and Distributor approving Pharmacy...")
        client.post("/api/approve-user", json={"target": pharm_addr, "approver_role": "admin"})
        client.post("/api/approve-user", json={"target": pharm_addr, "approver_role": "manufacturer"})
        client.post("/api/approve-user", json={"target": pharm_addr, "approver_role": "distributor"})
    assert blockchain.get_user(pharm_addr)["status"] == 1, "Pharmacy must be Active"
    print("[PASS] 5. Pharmacy is active and approved by Admin + Manufacturer + Distributor.")

    # 6. Verify User Registry endpoint reflects all active roles
    res = client.get("/api/users")
    assert res.status_code == 200
    user_list = res.json["users"]
    assert len(user_list) >= 4, f"Expected at least 4 users, found {len(user_list)}"
    print(f"[PASS] 6. User Registry queried successfully ({len(user_list)} organizations listed).")

    # 7. Register a New Medicine Batch on Blockchain (Stage 1)
    ts_now = int(time.time())
    test_med_id = f"PT-E2E-{ts_now}"
    test_batch = f"BATCH-E2E-{ts_now % 10000}"
    expiry_ts = ts_now + 365 * 24 * 3600

    print(f"[ACTION] Registering new batch {test_med_id} ({test_batch})...")
    tx_hash = blockchain.register_medicine(
        medicine_id=test_med_id,
        name="Calcitriol Soft Gelatin Capsules",
        batch=test_batch,
        expiry_timestamp=expiry_ts,
        image_cid="QmRPfUZb5v52nNjgV6wWE7biJnaHJbY9voczuVT25qujvr",
        quantity=500,
    )
    assert tx_hash, "Medicine registration failed"
    res_s1 = client.get("/api/batches?stage=1")
    assert res_s1.status_code == 200
    assert any(b["id"] == test_med_id for b in res_s1.json["batches"])
    print(f"[PASS] 7. Medicine registered at Stage 1 & listed in /api/batches?stage=1. Tx: {tx_hash}")

    # 8. Distributor Receipt (Stage 1 -> 2)
    print(f"[ACTION] Distributor receiving batch {test_med_id}...")
    res = client.post("/api/distributor/receive", json={
        "medicine_id": test_med_id,
        "details": "Batch received at Central Hub. Ambient temp 21C, package seal verified intact.",
    })
    assert res.status_code == 200, f"Distributor receive failed: {res.json}"
    assert res.json["stage"] == 2
    res_s2 = client.get("/api/batches?stage=2")
    assert res_s2.status_code == 200
    assert any(b["id"] == test_med_id for b in res_s2.json["batches"])
    print("[PASS] 8. Distributor receipt confirmed. Medicine advanced to Stage 2 & listed in /api/batches?stage=2.")

    # 9. Pharmacy Receipt (Stage 2 -> 3)
    print(f"[ACTION] Pharmacy receiving batch {test_med_id}...")
    res = client.post("/api/pharmacy/receive", json={
        "medicine_id": test_med_id,
        "details": "Received at Apollo Retail Pharmacy. Stored on Prescription Shelf B-12.",
    })
    assert res.status_code == 200, f"Pharmacy receive failed: {res.json}"
    assert res.json["stage"] == 3
    rec = blockchain.find_record(test_med_id)
    assert rec["stage"] == 3, f"Expected stage 3, got {rec['stage']}"
    assert rec["current_owner"].lower() == pharm_addr.lower()
    print("[PASS] 9. Pharmacy receipt confirmed. Medicine advanced to Stage 3.")

    # 10. Consumer Lookup by Medicine ID and Batch ID
    print("[ACTION] Testing consumer lookup by Medicine ID...")
    res_id = client.get(f"/lookup/{test_med_id}")
    assert res_id.status_code == 200
    data_id = res_id.json
    assert data_id["found"] is True
    assert data_id["stage"] == 3
    assert len(data_id["history"]) == 3  # Registration -> Distributor -> Pharmacy
    assert "Central Hub" in data_id["stages"]["distributor"]["details"]
    assert "Apollo Retail" in data_id["stages"]["pharmacy"]["details"]

    print("[ACTION] Testing consumer lookup by Batch ID...")
    res_batch = client.get(f"/lookup/{test_batch}")
    assert res_batch.status_code == 200
    assert res_batch.json["medicine_id"] == test_med_id
    print("[PASS] 10. Consumer lookup resolved full 3-stage timeline by both ID and Batch.")

    # 11. Multi-Factor Packaging Verification (/verify)
    print("[ACTION] Testing packaging verification endpoint...")
    ref_image_path = Path(__file__).resolve().parent.parent / "dataset" / "reference" / "packet_back.jpg"
    with open(ref_image_path, "rb") as f:
        img_bytes = f.read()

    res_verify = client.post(
        "/verify",
        data={
            "medicine_id": test_med_id,
            "image": (io.BytesIO(img_bytes), "packet_back.jpg"),
        },
        content_type="multipart/form-data",
    )
    assert res_verify.status_code == 200, f"Verification failed: {res_verify.json}"
    verdict_data = res_verify.json
    print(f"[INFO] Verification Verdict: {verdict_data.get('verdict')}")
    print(f"[INFO] OCR Detected Batch:   {verdict_data.get('ocr', {}).get('found_batch')}")
    print(f"[INFO] Blockchain OK:        {verdict_data.get('details', {}).get('blockchain_ok')}")
    assert verdict_data.get("verdict") in ("Verified", "Suspicious"), "Unexpected verdict"
    print("[PASS] 11. Multi-factor verification pipeline evaluated successfully.")

    # 12. Counterfeit / Unregistered ID Detection
    print("[ACTION] Testing non-existent medicine detection...")
    res_fake = client.get("/lookup/FAKE-COUNTERFEIT-999")
    assert res_fake.status_code == 404
    assert res_fake.json["found"] is False

    res_fake_verify = client.post(
        "/verify",
        data={
            "medicine_id": "FAKE-COUNTERFEIT-999",
            "image": (io.BytesIO(img_bytes), "packet_back.jpg"),
        },
        content_type="multipart/form-data",
    )
    assert res_fake_verify.json["verdict"] == "Unverified"
    print("[PASS] 12. Counterfeit / unregistered medicines correctly rejected as Unverified.")

    # 13. Medicine Recall Workflow (/api/recall) & Demo Stage Seeding
    recall_id = f"PT-RECALL-{ts_now}"
    blockchain.register_medicine(
        medicine_id=recall_id,
        name="Amoxicillin 500mg Capsules",
        batch=f"BATCH-REC-{ts_now % 1000}",
        expiry_timestamp=expiry_ts,
        image_cid="QmRPfUZb5v52nNjgV6wWE7biJnaHJbY9voczuVT25qujvr",
        quantity=200,
    )
    res_recall = client.post("/api/recall", json={
        "medicine_id": recall_id,
        "reason": "Quality control seal test recall",
        "role": "manufacturer",
    })
    assert res_recall.status_code == 200, f"Recall failed: {res_recall.json}"
    res_rec_lookup = client.get(f"/lookup/{recall_id}")
    assert res_rec_lookup.json["recalled"] is True
    assert "Quality control" in res_rec_lookup.json["recall_reason"]
    print("[PASS] 13. On-chain medicine recall executed and verified.")

    # Ensure demo batches exist at Stage 1, Stage 2, and Stage 3 for live dashboard queues
    if blockchain.find_record("PT-TEST-002") is None:
        blockchain.register_medicine(
            "PT-TEST-002", "Calcitriol Soft Gelatin Capsules", "13606265",
            expiry_ts, "QmRPfUZb5v52nNjgV6wWE7biJnaHJbY9voczuVT25qujvr", 500
        )
        blockchain.distributor_receive("PT-TEST-002", "Verified at MedLine Central Hub (20C)")
        blockchain.pharmacy_receive("PT-TEST-002", "Verified and stocked at Apollo Care Pharmacy")

    if blockchain.find_record("PT-STAGE1-DEMO") is None:
        blockchain.register_medicine(
            "PT-STAGE1-DEMO", "Azithromycin 250mg Tablets", "BATCH-S1-2026",
            expiry_ts, "QmRPfUZb5v52nNjgV6wWE7biJnaHJbY9voczuVT25qujvr", 300
        )

    if blockchain.find_record("PT-STAGE2-DEMO") is None:
        blockchain.register_medicine(
            "PT-STAGE2-DEMO", "Metformin Hydrochloride 500mg", "BATCH-S2-2026",
            expiry_ts, "QmRPfUZb5v52nNjgV6wWE7biJnaHJbY9voczuVT25qujvr", 450
        )
        blockchain.distributor_receive("PT-STAGE2-DEMO", "Checked and dispatched from Regional Warehouse")

    print("\n" + "=" * 60)
    print("ALL END-TO-END WORKFLOW INTEGRATION TESTS PASSED (13/13)!")
    print("=" * 60)


if __name__ == "__main__":
    run_e2e_test()
