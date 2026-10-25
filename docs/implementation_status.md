# PharmaTrace — Implementation Status & Handover Report

**Repository:** `C:\Users\LENOVO\Desktop\pharmatrace`  
**Active Branch:** `feature/pharmatrace-completion` (preserving `frontend_work` untouched)  
**Smart Contract Address (Hardhat Localnet):** `0x5FbDB2315678afecb367f032d93F642f64180aa3`

---

## 1. Completed Features

### A. Blockchain & Smart Contract (`blockchain/contracts/PharmaTrace.sol`)
- **Synchronized Full ABI**: Updated `backend/contract_abi.json` with all 16 functions and events from compiled `PharmaTrace.sol` (`register`, `approve`, `reject`, `registerMedicine`, `distributorReceive`, `pharmacyReceive`, `recallMedicine`, `getMedicine`, `getHistory`, `getStages`, `getHistoryLength`, `isExpired`, `users`, `admin`, `recalled`, `recallReason`).
- **Role-Based Access Control (RBAC)**:
  - **Admin** (`Account #0`: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`): Root authority deployed via constructor; approves/rejects Manufacturers, Distributors, and Pharmacies; can recall medicines.
  - **Manufacturer** (`Account #1`: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`): Requires Admin approval (`adminOk`); registers medicine batches (`Stage 1`), approves linked Distributors and Pharmacies (`mfrOk`), and can initiate recalls on its batches.
  - **Distributor** (`Account #2`: `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`): Requires Admin + Manufacturer approval (`adminOk && mfrOk`); verifies and records batch receipt (`Stage 1 -> Stage 2`), appends immutable distributor receipt details without overwriting manufacturer metadata, and approves linked Pharmacies (`distOk`).
  - **Pharmacy** (`Account #3`: `0x90F79bf6EB2c4f870365E785982E1f101E93b906`): Requires Admin + Manufacturer + Distributor approval (`adminOk && mfrOk && distOk`); verifies and records final retail receipt (`Stage 2 -> Stage 3`) and appends pharmacy storage/shelf notes.
  - **Consumer**: Public read-only access to verify medicine authenticity, inspect 3-stage supply-chain provenance, and run packaging OCR + visual verification without requiring a wallet or approval.

### B. Flask Backend & Verification Pipeline (`backend/`)
- **Blockchain Service (`backend/services/blockchain.py`)**:
  - Multi-role transaction signing (`register_user`, `approve_user`, `reject_user`, `register_medicine`, `distributor_receive`, `pharmacy_receive`, `recall_medicine`).
  - Automatic account funding & provisioning when registering additional organizations from the UI.
  - Event-indexed batch discovery (`get_all_batches`) with stage (`?stage=1|2|3`) and manufacturer filtering, plus ID and batch-number resolution (`find_record`).
- **OCR Service (`backend/services/ocr.py`)**:
  - Multi-variant image preprocessing (grayscale, autocontrast, 2x upscaling, sharpen, contrast enhancement across PSM 6 & 11).
  - Word-boundary batch regex (`_BATCH_RE`) to prevent false-positive substring matches on noisy packaging text, and ISO `YYYY-MM` expiry normalization (`_normalise_month_date`).
- **Vision & Packaging Comparison (`backend/services/vision.py`)**:
  - Exact SHA-256 hash comparison against the Pinata/IPFS reference image (`exact_image_match`).
  - Siamese / MobileNetV2 cosine similarity with deterministic PIL/NumPy spatial color-histogram + grid-structure embedding fallback when Windows Smart App Control blocks native TensorFlow DLLs.
- **REST API Endpoints (`backend/app.py`)**:
  - `GET /health` — Backend, Hardhat RPC, and vision status check.
  - `POST /register` — Pins reference packaging image to Pinata/IPFS and registers batch on-chain (`Stage 1`).
  - `GET /lookup/<medicine_id>` — Looks up by Medicine ID or Batch Number; returns metadata, recall/expiry flags, current stage, transfer history, and distributor/pharmacy receipt logs.
  - `POST /verify` — Multi-factor verification combining on-chain status (`blockchain_ok`), OCR text comparison (`ocr`), and reference packaging comparison (`image_ok`) into `"Verified"`, `"Suspicious"`, or `"Unverified"`.
  - `GET /api/roles`, `GET /api/users`, `GET /api/users/<address>` — Live organization registry and role account mapping.
  - `POST /api/register-user`, `POST /api/approve-user`, `POST /api/reject-user` — On-chain organization onboarding and multi-party approval workflows.
  - `POST /api/distributor/receive`, `POST /api/pharmacy/receive`, `GET /api/stages/<id>` — Supply-chain custody progression (`Stage 1 -> 2 -> 3`).
  - `GET /api/batches` — Lists on-chain batches with optional `?stage=` and `?manufacturer=` filters.
  - `POST /api/recall` — On-chain batch recall by Manufacturer or Admin.

### C. Flutter Web Frontend (`app/`)
- **Role Selection & Onboarding (`app/lib/screens/role_login_screen.dart`)**:
  - Displays all 5 roles with their mapped Hardhat account addresses, active status badges, and an on-chain **"Register New Organization"** dialog.
- **Role Dashboards (`app/lib/screens/role_dashboard_screen.dart`)**:
  - Live blockchain metrics (organizations, pending approvals, stage counts, recall counts).
  - **Admin / Manufacturer / Distributor Approvals**: Displays multi-party approval status (`Admin ✓/Pending`, `Manufacturer ✓/Pending`, `Distributor ✓/Pending`) and executes on-chain `approve` / `reject` transactions.
  - **Dynamic Batch Queues**:
    - Distributor **"Incoming batches"** fetches Stage 1 batches (`/api/batches?stage=1`) with one-click **"Receive Batch"** autofill.
    - Pharmacy **"Incoming stock"** fetches Stage 2 batches (`/api/batches?stage=2`) with one-click **"Receive Stock"** autofill.
    - Manufacturer & Admin batch views include live **"Recall"** action and **"View Details"** deep-linking into `MedicineLookupScreen`.
- **Manufacturer Batch Registration (`app/lib/screens/register_batch_screen.dart`)**:
  - Image picker, quantity & expiry inputs, Pinata/IPFS upload, and on-chain `registerMedicine` transaction display.
- **Consumer Lookup & Verification (`app/lib/screens/medicine_lookup_screen.dart`, `verify_screen.dart`, `consumer/result_screen.dart`)**:
  - QR scanner + manual Medicine ID / Batch Number lookup, 3-stage supply-chain timeline with distributor and pharmacy inspection notes, and multi-factor optical + OCR verification breakdown.

---

## 2. Verification & Test Outcomes

All tests and static checks were executed against the live Hardhat node (`http://127.0.0.1:8545`) and Flask backend:

| Check / Test Suite | Command | Outcome |
| :--- | :--- | :--- |
| **Smart Contract Deployment & Seeding** | `npx hardhat run scripts/deploy.js --network localhost` & `node register_test_medicine.mjs` | **PASSED** — Deployed at `0x5FbDB2315678afecb367f032d93F642f64180aa3`; active demo batches seeded across Stages 1, 2, and 3. |
| **OCR Unit Tests** | `cd backend && .venv312\Scripts\python.exe tests\test_ocr.py` | **PASSED** — Batch number (`13606265`) and normalized ISO expiry (`2027-08`) extracted accurately. |
| **Verdict Logic Unit Tests** | `cd backend && .venv312\Scripts\python.exe tests\test_verdict.py` | **PASSED** — Multi-factor decision matrix (`Verified`, `Suspicious`, `Unverified`) verified. |
| **13-Step End-to-End Integration Suite** | `cd backend && .venv312\Scripts\python.exe tests\test_end_to_end_workflow.py` | **PASSED (13/13)** — Verified `/health`, `/api/roles`, multi-party approvals (Admin + Mfr + Dist), Stage 1 registration, `/api/batches` filtering, Stage 2 distributor receipt, Stage 3 pharmacy receipt, ID & batch lookup, `/verify` packaging check, counterfeit rejection, and `/api/recall`. |
| **Flutter Static Analysis** | `cd app && dart analyze` | **PASSED** — `No issues found!`. |
| **Flutter Widget Smoke Test** | `cd app && flutter test` | **PASSED** — `PharmaTraceApp initial screen smoke test` passed. |

---

## 3. Known Environment Notes & Limitations

1. **Windows 11 Smart App Control (SAC) & TensorFlow DLLs**:
   - On Windows machines with Smart App Control enabled (`VerifiedAndReputablePolicyState: 1`), unsigned native `.pyd` extensions in user virtual environments (such as TensorFlow's `_pywrap_py_exception_registry.pyd`) are blocked by the OS kernel.
   - `backend/services/vision.py` automatically detects this and falls back to a deterministic PIL/NumPy spatial color-histogram and structural grid cosine-similarity engine, plus SHA-256 exact reference matching, so `/verify` operates reliably without crashing.
2. **Local Hardhat State Persistence**:
   - Hardhat's in-memory blockchain resets when the Hardhat node process is terminated. Always run the deployment and demo-seeding commands below if restarting the Hardhat terminal.

---

## 4. Exact Commands to Launch & Demonstrate PharmaTrace

Open **three terminals** in VS Code at `C:\Users\LENOVO\Desktop\pharmatrace`:

### Terminal 1 — Start Local Blockchain (Hardhat)
```powershell
cd C:\Users\LENOVO\Desktop\pharmatrace\blockchain
npx hardhat node
```
*(If starting a fresh Hardhat node, run once in another shell to deploy & seed demo data)*:
```powershell
cd C:\Users\LENOVO\Desktop\pharmatrace\blockchain
npx hardhat run scripts/deploy.js --network localhost
cd C:\Users\LENOVO\Desktop\pharmatrace
$env:OPENBLAS_NUM_THREADS="1"
.\backend\.venv312\Scripts\python.exe .\backend\tests\test_end_to_end_workflow.py
```

### Terminal 2 — Start Flask Backend (Port 5001)
```powershell
cd C:\Users\LENOVO\Desktop\pharmatrace\backend
$env:OPENBLAS_NUM_THREADS="1"
.\.venv312\Scripts\python.exe app.py
```

### Terminal 3 — Launch Flutter Web Application
```powershell
cd C:\Users\LENOVO\Desktop\pharmatrace\app
flutter run -d chrome --dart-define=PHARMATRACE_API_URL=http://127.0.0.1:5001
```

### Suggested Live Demonstration Flow for Evaluation
1. **Admin Workspace**: Select **Admin** -> Open **Organization approvals** / **User management** to show active on-chain organizations and multi-party approval statuses (`Admin ✓`, `Manufacturer ✓`, `Distributor ✓`).
2. **Manufacturer Workspace**: Select **Manufacturer** -> Open **Register medicine**, upload `backend/dataset/reference/packet_back.jpg`, and register a new batch on-chain (pins to Pinata/IPFS and mints at **Stage 1**).
3. **Distributor Workspace**: Select **Distributor** -> Open **Incoming batches** (`Stage 1` queue), click **Receive Batch** on `PT-STAGE1-DEMO` (or your newly registered batch), enter inspection notes, and confirm **Stage 2** receipt on-chain.
4. **Pharmacy Workspace**: Select **Pharmacy** -> Open **Incoming stock** (`Stage 2` queue), click **Receive Stock** on `PT-STAGE2-DEMO`, enter shelf notes, and confirm **Stage 3** receipt on-chain.
5. **Consumer Verification**: Select **Consumer** ->
   - Open **Medicine lookup** and search `PT-TEST-002` (or batch `13606265`) to display the full 3-stage blockchain custody timeline.
   - Open **Verify medicine**, enter `PT-TEST-002`, and upload `backend/dataset/reference/packet_back.jpg` to demonstrate a **Verified** multi-factor result, or upload `backend/dataset/tampered/wrong_batch.jpg` / enter `FAKE-999` to demonstrate **Suspicious / Unverified** counterfeit detection.
