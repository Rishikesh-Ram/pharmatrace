# PharmaTrace Architecture

## High-Level Architecture

PharmaTrace couples blockchain verification with multi-factor computer vision and OCR to combat counterfeit medicines.

```
+-------------------------------------------------------------+
|                      Flutter Web Client                     |
|  - Consumer Verification (QR Scanner + Photo Upload)        |
|  - Role Dashboards (Admin, Manufacturer, Distributor, Pharm)|
+------------------------------+------------------------------+
                               | REST API (HTTP)
                               v
+-------------------------------------------------------------+
|                     Flask Backend Service                   |
|  - Multi-Factor Decision Engine (/verify)                   |
|  - OCR Processing (Tesseract)                               |
|  - Vision Feature Matching (Keras / Cosine Embedding)       |
|  - IPFS Gateway Connector (Pinata)                          |
|  - Web3 Smart Contract Transactor                           |
+---------------+-----------------------------+---------------+
                |                             |
                v                             v
+-------------------------------+ +---------------------------+
|    Hardhat / Ethereum Node    | |      Pinata / IPFS        |
|  - Pharmatrace.sol            | |  - High-res reference     |
|  - Role Registry & Approvals  | |    packaging images       |
|  - Immutability & Stages 1->3 | |  - Content Address (CID)  |
+-------------------------------+ +---------------------------+
```

## Security & Verification Rules
1. **Blockchain Record**: Checks existence, expiry timestamp, and recall flags.
2. **OCR Analysis**: Extracts batch number and expiration date from physical pack; checks for matching text.
3. **Vision Analysis**: Compares uploaded photo against the manufacturer's pinned IPFS reference image using deep embeddings.
4. **Authenticity Verdict**:
   - `Verified`: Both blockchain record and optical verification pass.
   - `Suspicious`: Discrepancy between packaging and blockchain records.
   - `Unverified`: No matching record found on the blockchain or critical mismatch.
