# PharmaTrace Architecture

## 1. High-Level System Architecture

PharmaTrace couples Ethereum/Hardhat smart-contract traceability with role-based authentication, Pinata/IPFS content-addressed storage, Tesseract OCR, and visual packaging comparison to detect counterfeit medicines.

```
+-------------------------------------------------------------------------+
|                           Flutter Web Client                            |
|  1. WelcomeScreen ("Trust Every Dose. Trace Every Batch.")              |
|  2. ContinueChoiceScreen ("I'm a Consumer" / "I'm an Organization")     |
|  3. Consumer Path (Direct Public Access):                               |
|     - QR Scanner, Medicine Lookup, 4-Stage Journey Timeline             |
|     - Side-by-Side Packaging Comparison, OCR & Explainable Verdict      |
|  4. Supply-Chain Organization Path:                                     |
|     - RoleSelectScreen (Manufacturer, Distributor, Pharmacy, Admin)     |
|     - RoleLoginScreen (Salted PBKDF2-SHA256 + Bearer Session Token)     |
|     - OrganizationRegistrationScreen (Non-Admin Only -> Pending Status) |
|     - RoleDashboardScreen (Governance, Batch Registration, Receipts)    |
+------------------------------------+------------------------------------+
                                     | REST API (HTTP + Bearer Token)
                                     v
+-------------------------------------------------------------------------+
|                          Flask Backend Service                          |
|  - Auth & Role Guard (services/auth.py: PBKDF2-SHA256 + HMAC Tokens)    |
|  - Multi-Factor Decision & Explainability Engine (/verify)              |
|  - OCR Processing (services/ocr.py: Tesseract + Multi-Variant Filters)  |
|  - Vision Feature Matching (services/vision.py: SHA-256 + Cosine Sim)   |
|  - IPFS Gateway & Local Cache Connector (services/ipfs.py + Pinata)     |
|  - Web3 Smart Contract Transactor & Event Indexer (blockchain.py)       |
+-------------------+---------------------------------+-------------------+
                    |                                 |
                    v                                 v
+-----------------------------------+ +-----------------------------------+
|      Hardhat / Ethereum Node      | |           Pinata / IPFS           |
|  - PharmaTrace.sol                | |  - Reference packaging images     |
|  - Multi-Party Role Approvals     | |  - Content Address (CID) stored   |
|    (Admin -> Mfr -> Dist -> Pharm)| |    immutably on-chain             |
|  - Immutable Custody Stages 1->3  | |  - Served via /api/reference-image|
|  - Event Logs & Tx Receipts       | |    with local fallback cache      |
+-----------------------------------+ +-----------------------------------+
```

---

## 2. Entry, Authentication & Multi-Party Approval Architecture

1. **Consumer Path (Login-Free Public Access)**:
   - `WelcomeScreen` → `ContinueChoiceScreen` → **"I'm a Consumer"** → opens the Consumer dashboard directly without login.
   - Consumers can scan QR codes, look up batch IDs, inspect the 4-stage journey timeline and confirmed blockchain events, and upload physical package photos for side-by-side comparison.
2. **Supply-Chain Organization Path (Authenticated & Role-Gated)**:
   - `WelcomeScreen` → `ContinueChoiceScreen` → **"I'm a Supply-Chain Organization"** → `RoleSelectScreen` (`Manufacturer`, `Distributor`, `Pharmacy`, `Admin`) → `RoleLoginScreen`.
   - Credentials are verified by `backend/services/auth.py` using salted PBKDF2-SHA256 hashes and live on-chain status checks against `PharmaTrace.sol`:
     - **Role Mismatch** (`403 ROLE_MISMATCH`): Credentials belonging to one role cannot sign into another role's workspace.
     - **Pending Approval** (`403 PENDING_APPROVAL`): Newly registered organizations cannot sign in or execute supply-chain transactions until all required upstream approvals are confirmed on-chain.
     - **Rejected** (`403 REGISTRATION_REJECTED`): Rejected organizations are blocked from signing in.
3. **Self-Registration & Upstream Approval Hierarchy**:
   - Public self-registration (`OrganizationRegistrationScreen` / `POST /api/register-user`) is available **only** for `Manufacturer`, `Distributor`, and `Pharmacy`. Public `Admin` registration is blocked in both the UI and backend (`403 Forbidden`).
   - Every new organization is registered on-chain with initial status `Pending`:
     - **Manufacturer** requires: `Admin` approval (`adminOk`).
     - **Distributor** requires: `Admin` + linked `Manufacturer` approval (`adminOk && mfrOk`).
     - **Pharmacy** requires: `Admin` + `Manufacturer` + linked `Distributor` approval (`adminOk && mfrOk && distOk`).
4. **Local Development Key Management Note**:
   - In local Hardhat development, the Flask backend manages transaction signing keys server-side (`backend/.env` for the 4 default Hardhat role accounts and `backend/data/server_keys.json` for newly registered organizations) so private keys are never exposed to the Flutter Web client.

---

## 3. 4-Stage Traceability & Explainable Verification Rules

1. **Stage 1 — Manufacturer Registration (On-Chain Fact + IPFS Pin)**:
   - Manufacturer uploads reference packaging image (pinned to Pinata/IPFS) and mints immutable batch metadata on-chain (`MedicineRegistered` event).
2. **Stage 2 — Distributor Receipt (On-Chain Fact)**:
   - Active Distributor verifies Stage 1 batch and records custody receipt and inspection notes on-chain (`DistributorReceived` event) without overwriting manufacturer metadata.
3. **Stage 3 — Pharmacy Receipt (On-Chain Fact)**:
   - Active Pharmacy verifies Stage 2 batch and records retail receipt and storage notes on-chain (`PharmacyReceived` event).
4. **Stage 4 — Consumer Verification (On-Chain Custody + Off-Chain Vision & OCR)**:
   - Evaluates on-chain existence, recall status, expiry date, and custody stage (`Stage 3` required for retail sale), then compares the submitted package photo against the IPFS reference baseline (`similarity >= 0.75`) and OCR-extracted batch/expiry fields.
   - Returns structured explainable verdicts (`Verified`, `Suspicious`, `Unregistered`, `Expired`, `Recalled`, or `Unable to verify` on network outage) with explicit reasons, field mismatches, and side-by-side image comparison.
