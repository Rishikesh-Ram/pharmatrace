// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PharmaTrace - medicine supply-chain tracking
/// @notice Manufacturers register medicines, authorized parties pass ownership
///         along the chain, and anyone can read the full history.
contract PharmaTrace {
    // ---------------------------------------------------------------
    // Data
    // ---------------------------------------------------------------
    address public admin;

    mapping(address => bool) public isManufacturer;
    mapping(address => bool) public isAuthorizedParty; // distributors, pharmacies, etc.

    struct Medicine {
        string id;
        string name;
        string batch;
        uint256 expiry;        // Unix timestamp
        string imageHash;      // e.g. IPFS CID or SHA-256 of the product image
        address manufacturer;
        address currentOwner;
        uint256 registeredAt;
        bool exists;
    }

    struct TransferRecord {
        address from;
        address to;
        uint256 timestamp;
    }

    mapping(string => Medicine) private medicines;
    mapping(string => TransferRecord[]) private history;

    // Recall status (kept separate from the struct so the data stays simple)
    mapping(string => bool) public recalled;
    mapping(string => string) public recallReason;

    // ---------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------
    event MedicineRegistered(string indexed idHash, string id, address indexed manufacturer);
    event OwnershipTransferred(string indexed idHash, string id, address indexed from, address indexed to);
    event MedicineRecalled(string indexed idHash, string id, address indexed by, string reason);
    event ManufacturerSet(address indexed account, bool status);
    event PartySet(address indexed account, bool status);

    // ---------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyManufacturer() {
        require(isManufacturer[msg.sender], "Not an authorized manufacturer");
        _;
    }

    constructor() {
        admin = msg.sender;
        // Deployer can act as a manufacturer so you can test immediately
        isManufacturer[msg.sender] = true;
        emit ManufacturerSet(msg.sender, true);
    }

    // ---------------------------------------------------------------
    // Admin: manage who is authorized
    // ---------------------------------------------------------------
    function setManufacturer(address account, bool status) external onlyAdmin {
        isManufacturer[account] = status;
        emit ManufacturerSet(account, status);
    }

    function setAuthorizedParty(address account, bool status) external onlyAdmin {
        isAuthorizedParty[account] = status;
        emit PartySet(account, status);
    }

    // ---------------------------------------------------------------
    // Core logic
    // ---------------------------------------------------------------
    function registerMedicine(
        string calldata id,
        string calldata name,
        string calldata batch,
        uint256 expiry,
        string calldata imageHash
    ) external onlyManufacturer {
        require(bytes(id).length > 0, "ID required");
        require(!medicines[id].exists, "Medicine already registered");
        require(expiry > block.timestamp, "Expiry must be in the future");

        medicines[id] = Medicine({
            id: id,
            name: name,
            batch: batch,
            expiry: expiry,
            imageHash: imageHash,
            manufacturer: msg.sender,
            currentOwner: msg.sender,
            registeredAt: block.timestamp,
            exists: true
        });

        history[id].push(TransferRecord(address(0), msg.sender, block.timestamp));

        emit MedicineRegistered(id, id, msg.sender);
    }

    function transferOwnership(string calldata id, address to) external {
        Medicine storage m = medicines[id];
        require(m.exists, "Medicine not found");
        require(m.currentOwner == msg.sender, "Only current owner can transfer");
        require(!recalled[id], "Medicine is recalled");
        require(block.timestamp <= m.expiry, "Medicine has expired");
        require(to != address(0) && to != msg.sender, "Invalid recipient");
        require(
            isAuthorizedParty[to] || isManufacturer[to],
            "Recipient is not authorized"
        );

        address from = m.currentOwner;
        m.currentOwner = to;
        history[id].push(TransferRecord(from, to, block.timestamp));

        emit OwnershipTransferred(id, id, from, to);
    }

    /// @notice Flags a medicine as recalled. Only the manufacturer that registered
    ///         it, or the admin, can do this. The record and history are kept.
    function recallMedicine(string calldata id, string calldata reason) external {
        Medicine storage m = medicines[id];
        require(m.exists, "Medicine not found");
        require(
            msg.sender == m.manufacturer || msg.sender == admin,
            "Only manufacturer or admin can recall"
        );
        require(!recalled[id], "Already recalled");

        recalled[id] = true;
        recallReason[id] = reason;

        emit MedicineRecalled(id, id, msg.sender, reason);
    }

    // ---------------------------------------------------------------
    // Public reads (anyone)
    // ---------------------------------------------------------------
    function getMedicine(string calldata id) external view returns (Medicine memory) {
        require(medicines[id].exists, "Medicine not found");
        return medicines[id];
    }

    function getHistory(string calldata id) external view returns (TransferRecord[] memory) {
        require(medicines[id].exists, "Medicine not found");
        return history[id];
    }

    function getHistoryLength(string calldata id) external view returns (uint256) {
        return history[id].length;
    }

    function isExpired(string calldata id) external view returns (bool) {
        require(medicines[id].exists, "Medicine not found");
        return block.timestamp > medicines[id].expiry;
    }
}
