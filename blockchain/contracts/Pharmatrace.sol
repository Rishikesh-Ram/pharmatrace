// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PharmaTrace - role-gated medicine supply-chain tracking
contract PharmaTrace {
    // ---------------- Types ----------------
    enum Role { None, Admin, Manufacturer, Distributor, Pharmacy }
    enum Status { Pending, Active, Rejected }

    struct User {
        Role role;
        Status status;
        string name;
        address manufacturer;   // set for Distributor and Pharmacy
        address distributor;    // set for Pharmacy
        bool adminOk;
        bool mfrOk;
        bool distOk;
    }

    struct Medicine {
        string id;
        string name;
        string batch;
        uint256 expiry;
        string imageHash;
        address manufacturer;
        address currentOwner;
        uint256 registeredAt;
        bool exists;
        // new fields, appended so old tuple indexes stay the same
        uint256 quantity;
        uint8 stage;            // 1 = manufactured, 2 = distributor, 3 = pharmacy
        address distributor;
        address pharmacy;
    }

    struct TransferRecord {
        address from;
        address to;
        uint256 timestamp;
    }

    struct StageRecord {
        address actor;
        uint256 timestamp;
        string details;         // JSON string: received date, storage, stock...
    }

    // ---------------- Storage ----------------
    address public admin;
    mapping(address => User) public users;

    mapping(string => Medicine) private medicines;
    mapping(string => TransferRecord[]) private history;
    mapping(string => StageRecord) private distRecord;
    mapping(string => StageRecord) private pharmRecord;

    mapping(string => bool) public recalled;
    mapping(string => string) public recallReason;

    // ---------------- Events ----------------
    event UserRegistered(address indexed user, Role role);
    event UserStatus(address indexed user, Status status);
    event MedicineRegistered(string indexed idHash, string id, address indexed manufacturer);
    event DistributorReceived(string id, address indexed distributor);
    event PharmacyReceived(string id, address indexed pharmacy);
    event MedicineRecalled(string indexed idHash, string id, address indexed by, string reason);

    // ---------------- Modifiers ----------------
    modifier onlyActive(Role r) {
        require(
            users[msg.sender].role == r && users[msg.sender].status == Status.Active,
            "Not approved for this role"
        );
        _;
    }

    constructor() {
        admin = msg.sender;
        users[msg.sender].role = Role.Admin;
        users[msg.sender].status = Status.Active;
        users[msg.sender].name = "Admin";
    }

    // ---------------- Registration ----------------
    function register(
        Role role,
        string calldata name,
        address linkedManufacturer,
        address linkedDistributor
    ) external {
        require(users[msg.sender].role == Role.None, "Already registered");
        require(
            role == Role.Manufacturer || role == Role.Distributor || role == Role.Pharmacy,
            "Invalid role"
        );

        User storage u = users[msg.sender];
        u.role = role;
        u.name = name;
        u.status = Status.Pending;

        if (role == Role.Distributor) {
            User storage m = users[linkedManufacturer];
            require(m.role == Role.Manufacturer && m.status == Status.Active, "Invalid manufacturer");
            u.manufacturer = linkedManufacturer;
        } else if (role == Role.Pharmacy) {
            User storage d = users[linkedDistributor];
            require(d.role == Role.Distributor && d.status == Status.Active, "Invalid distributor");
            u.distributor = linkedDistributor;
            u.manufacturer = d.manufacturer;
        }
        emit UserRegistered(msg.sender, role);
    }

    // ---------------- Approvals ----------------
    function _canDecide(User storage u) private view returns (bool) {
        return msg.sender == admin
            || (u.role != Role.Manufacturer && msg.sender == u.manufacturer)
            || (u.role == Role.Pharmacy && msg.sender == u.distributor);
    }

    function approve(address target) external {
        User storage u = users[target];
        require(u.role != Role.None && u.status == Status.Pending, "Not pending");
        require(_canDecide(u), "Not allowed to approve");

        if (msg.sender == admin) u.adminOk = true;
        else if (msg.sender == u.manufacturer) u.mfrOk = true;
        else u.distOk = true;

        bool done = u.adminOk;
        if (u.role == Role.Distributor) done = done && u.mfrOk;
        if (u.role == Role.Pharmacy)    done = done && u.mfrOk && u.distOk;

        if (done) {
            u.status = Status.Active;
            emit UserStatus(target, Status.Active);
        }
    }

    function reject(address target) external {
        User storage u = users[target];
        require(u.role != Role.None && u.status == Status.Pending, "Not pending");
        require(_canDecide(u), "Not allowed to reject");
        u.status = Status.Rejected;
        emit UserStatus(target, Status.Rejected);
    }

    // ---------------- Stage 1: Manufacturer ----------------
    function registerMedicine(
        string calldata id,
        string calldata name,
        string calldata batch,
        uint256 expiry,
        string calldata imageHash,
        uint256 quantity
    ) external onlyActive(Role.Manufacturer) {
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
            exists: true,
            quantity: quantity,
            stage: 1,
            distributor: address(0),
            pharmacy: address(0)
        });
        history[id].push(TransferRecord(address(0), msg.sender, block.timestamp));
        emit MedicineRegistered(id, id, msg.sender);
    }

    // ---------------- Stage 2: Distributor ----------------
    function distributorReceive(string calldata id, string calldata details)
        external onlyActive(Role.Distributor)
    {
        Medicine storage m = medicines[id];
        require(m.exists && m.stage == 1, "Wrong stage");
        require(!recalled[id], "Medicine is recalled");
        require(block.timestamp <= m.expiry, "Medicine has expired");
        require(users[msg.sender].manufacturer == m.manufacturer, "Not your manufacturer");

        address from = m.currentOwner;
        m.distributor = msg.sender;
        m.currentOwner = msg.sender;
        m.stage = 2;
        distRecord[id] = StageRecord(msg.sender, block.timestamp, details);
        history[id].push(TransferRecord(from, msg.sender, block.timestamp));
        emit DistributorReceived(id, msg.sender);
    }

    // ---------------- Stage 3: Pharmacy ----------------
    function pharmacyReceive(string calldata id, string calldata details)
        external onlyActive(Role.Pharmacy)
    {
        Medicine storage m = medicines[id];
        require(m.exists && m.stage == 2, "Wrong stage");
        require(!recalled[id], "Medicine is recalled");
        require(block.timestamp <= m.expiry, "Medicine has expired");
        require(users[msg.sender].distributor == m.distributor, "Not your distributor");

        address from = m.currentOwner;
        m.pharmacy = msg.sender;
        m.currentOwner = msg.sender;
        m.stage = 3;
        pharmRecord[id] = StageRecord(msg.sender, block.timestamp, details);
        history[id].push(TransferRecord(from, msg.sender, block.timestamp));
        emit PharmacyReceived(id, msg.sender);
    }

    // ---------------- Recall ----------------
    function recallMedicine(string calldata id, string calldata reason) external {
        Medicine storage m = medicines[id];
        require(m.exists, "Medicine not found");
        require(msg.sender == m.manufacturer || msg.sender == admin, "Only manufacturer or admin");
        require(!recalled[id], "Already recalled");
        recalled[id] = true;
        recallReason[id] = reason;
        emit MedicineRecalled(id, id, msg.sender, reason);
    }

    // ---------------- Public reads (consumers) ----------------
    function getMedicine(string calldata id) external view returns (Medicine memory) {
        require(medicines[id].exists, "Medicine not found");
        return medicines[id];
    }

    function getHistory(string calldata id) external view returns (TransferRecord[] memory) {
        require(medicines[id].exists, "Medicine not found");
        return history[id];
    }

    function getStages(string calldata id)
        external view returns (StageRecord memory dist, StageRecord memory pharm)
    {
        require(medicines[id].exists, "Medicine not found");
        return (distRecord[id], pharmRecord[id]);
    }

    function getHistoryLength(string calldata id) external view returns (uint256) {
        return history[id].length;
    }

    function isExpired(string calldata id) external view returns (bool) {
        require(medicines[id].exists, "Medicine not found");
        return block.timestamp > medicines[id].expiry;
    }
}