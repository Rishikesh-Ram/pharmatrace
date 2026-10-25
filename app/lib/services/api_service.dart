import 'dart:convert';

import 'package:http/http.dart' as http;

class TransferEvent {
  final String from, to, date;
  const TransferEvent(this.from, this.to, this.date);
}

class JourneyStage {
  final int stage;
  final String title;
  final String organization;
  final String actorAddress;
  final bool completed;
  final String status;
  final bool isOnChain;
  final String eventName;
  final String timestamp;
  final String transactionHash;
  final int? blockNumber;
  final String details;

  const JourneyStage({
    required this.stage,
    required this.title,
    required this.organization,
    required this.actorAddress,
    required this.completed,
    required this.status,
    required this.isOnChain,
    required this.eventName,
    required this.timestamp,
    required this.transactionHash,
    this.blockNumber,
    required this.details,
  });
}

class Batch {
  final String id, medicine, manufacturer, expiry;
  final String medicineId;
  final String manufacturerName;
  final int quantity;
  final List<TransferEvent> history;
  final bool expired, recalled;
  final String recallReason;
  final int stage;
  final String distributor;
  final String distributorName;
  final String pharmacy;
  final String pharmacyName;
  final String distributorDetails;
  final String pharmacyDetails;
  final String ipfsCid;
  final String referenceImageUrl;
  final List<JourneyStage> journey;
  final List<Map<String, dynamic>> events;
  final Map<String, dynamic>? recallEvent;

  const Batch(
    this.id,
    this.medicine,
    this.manufacturer,
    this.expiry,
    this.quantity,
    this.history, {
    this.medicineId = '',
    this.manufacturerName = '',
    this.expired = false,
    this.recalled = false,
    this.recallReason = '',
    this.stage = 1,
    this.distributor = '',
    this.distributorName = '',
    this.pharmacy = '',
    this.pharmacyName = '',
    this.distributorDetails = '',
    this.pharmacyDetails = '',
    this.ipfsCid = '',
    this.referenceImageUrl = '',
    this.journey = const [],
    this.events = const [],
    this.recallEvent,
  });

  String get stageName {
    switch (stage) {
      case 1:
        return 'Manufactured';
      case 2:
        return 'With Distributor';
      case 3:
        return 'At Pharmacy';
      default:
        return 'Unknown Stage';
    }
  }
}

enum VerifyStatus {
  found,
  unknown,
  unavailable,
  verified,
  suspicious,
  unverified,
}

class VerifyResult {
  final VerifyStatus status;
  final Batch? batch;
  const VerifyResult(this.status, [this.batch]);
}

class ApiException implements Exception {
  final String message;
  final String code;
  final int statusCode;
  final Map<String, dynamic> data;

  const ApiException(
    this.message, {
    this.code = 'ERROR',
    this.statusCode = 400,
    this.data = const {},
  });

  @override
  String toString() => message;
}

abstract class ApiService {
  Future<VerifyResult> verifyBatch(String id);
}

class MockApiService implements ApiService {
  @override
  Future<VerifyResult> verifyBatch(String id) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final key = id.trim().toUpperCase();

    if (key == 'OFFLINE') {
      return const VerifyResult(VerifyStatus.unavailable);
    }

    if (key == 'BATCH101') {
      return const VerifyResult(
        VerifyStatus.found,
        Batch(
          'BATCH101',
          'Paracetamol 500mg',
          'Sun Pharma',
          '2027-08-31',
          5000,
          [
            TransferEvent('Sun Pharma', 'MedLine Distributors', '2026-09-02'),
            TransferEvent(
              'MedLine Distributors',
              'City Wholesale',
              '2026-09-10',
            ),
            TransferEvent('City Wholesale', 'Apollo Pharmacy', '2026-09-20'),
          ],
        ),
      );
    }

    return const VerifyResult(VerifyStatus.unknown);
  }
}

class FlaskApiService implements ApiService {
  static const String baseUrl = String.fromEnvironment(
    'PHARMATRACE_API_URL',
    defaultValue: 'http://127.0.0.1:5001',
  );

  final http.Client _client;
  String? _authToken;
  Map<String, dynamic>? _currentUser;

  FlaskApiService({http.Client? client}) : _client = client ?? http.Client();

  String? get authToken => _authToken;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _authToken != null && _currentUser != null;

  bool isAuthorizedForRole(String roleName) {
    if (roleName.toLowerCase() == 'consumer') return true;
    if (!isAuthenticated) return false;
    final currentRole = (_currentUser?['role'] ?? '').toString().toLowerCase();
    final statusName = (_currentUser?['status_name'] ?? 'Active').toString();
    return currentRole == roleName.toLowerCase() && statusName == 'Active';
  }

  Map<String, String> _headers({bool jsonBody = true}) {
    final headers = <String, String>{};
    if (jsonBody) {
      headers['Content-Type'] = 'application/json';
    }
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  String formatTimestamp(dynamic value) {
    if (value == null || value == 0 || value == '0') return 'Not recorded';

    DateTime? date;
    if (value is num) {
      if (value.toInt() <= 0) return 'Not recorded';
      date = DateTime.fromMillisecondsSinceEpoch(
        value.toInt() * 1000,
        isUtc: true,
      );
    } else {
      final asInt = int.tryParse(value.toString());
      if (asInt != null && asInt > 0) {
        date = DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true);
      } else {
        date = DateTime.tryParse(value.toString());
      }
    }

    if (date == null) return 'Not recorded';

    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'Not recorded';

    DateTime? date;
    if (value is num) {
      date = DateTime.fromMillisecondsSinceEpoch(
        value.toInt() * 1000,
        isUtc: true,
      );
    } else {
      date = DateTime.tryParse(value.toString());
    }

    if (date == null) return 'Not recorded';

    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  List<JourneyStage> parseJourney(dynamic rawJourney) {
    final list = rawJourney as List? ?? [];
    return list.map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      final tsVal = m['timestamp'];
      return JourneyStage(
        stage: (m['stage'] as num?)?.toInt() ?? 0,
        title: (m['title'] ?? '').toString(),
        organization: (m['organization'] ?? '').toString(),
        actorAddress: (m['actor_address'] ?? '').toString(),
        completed: m['completed'] == true,
        status: (m['status'] ?? '').toString(),
        isOnChain: m['is_on_chain'] == true,
        eventName: (m['event_name'] ?? '').toString(),
        timestamp: (tsVal == null || tsVal == 0)
            ? 'Real-time query'
            : formatTimestamp(tsVal),
        transactionHash: (m['transaction_hash'] ?? '').toString(),
        blockNumber: (m['block_number'] as num?)?.toInt(),
        details: (m['details'] ?? '').toString(),
      );
    }).toList();
  }

  String resolveReferenceImageUrl(String? relativeOrFullUrl) {
    if (relativeOrFullUrl == null || relativeOrFullUrl.isEmpty) return '';
    if (relativeOrFullUrl.startsWith('http')) return relativeOrFullUrl;
    return '$baseUrl$relativeOrFullUrl';
  }

  // ---------------------------------------------------------------------------
  // AUTHENTICATION
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
    required String expectedRole,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'identifier': identifier.trim(),
              'password': password,
              'expected_role': expectedRole.toLowerCase().trim(),
            }),
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      throw const ApiException(
        'Cannot connect to PharmaTrace backend server. Ensure Flask (port 5001) and Hardhat (port 8545) are running.',
        code: 'NETWORK_ERROR',
        statusCode: 503,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(
        (data['error'] ?? 'Authentication failed.').toString(),
        code: (data['code'] ?? 'AUTH_FAILED').toString(),
        statusCode: response.statusCode,
        data: data,
      );
    }

    _authToken = data['token']?.toString();
    if (data['user'] is Map) {
      _currentUser = Map<String, dynamic>.from(data['user'] as Map);
    }
    return data;
  }

  Future<void> logout() async {
    try {
      if (_authToken != null) {
        await _client
            .post(Uri.parse('$baseUrl/api/auth/logout'), headers: _headers())
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      // Ignore network errors during sign-out cleanup
    } finally {
      _authToken = null;
      _currentUser = null;
    }
  }

  void clearSession() {
    _authToken = null;
    _currentUser = null;
  }

  // ---------------------------------------------------------------------------
  // LOOKUP & VERIFICATION
  // ---------------------------------------------------------------------------

  @override
  Future<VerifyResult> verifyBatch(String id) async {
    final query = id.trim();
    if (query.isEmpty) return const VerifyResult(VerifyStatus.unknown);

    try {
      final uri = Uri.parse('$baseUrl/lookup/${Uri.encodeComponent(query)}');

      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) {
        return const VerifyResult(VerifyStatus.unknown);
      }

      if (response.statusCode != 200) {
        return const VerifyResult(VerifyStatus.unavailable);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['found'] != true) {
        return const VerifyResult(VerifyStatus.unknown);
      }

      final rawHistory = data['history'] as List? ?? [];
      final history = rawHistory.map((item) {
        final event = Map<String, dynamic>.from(item as Map);
        final from = (event['from'] ?? '').toString();
        final to = (event['to'] ?? '').toString();

        return TransferEvent(
          from == '0x0000000000000000000000000000000000000000'
              ? 'Registration'
              : from,
          to,
          formatTimestamp(event['timestamp']),
        );
      }).toList();

      final stages = data['stages'] as Map<String, dynamic>? ?? {};
      final distMap = stages['distributor'] as Map<String, dynamic>? ?? {};
      final pharmMap = stages['pharmacy'] as Map<String, dynamic>? ?? {};
      final rawEvents = data['events'] as List? ?? [];

      final medId = (data['medicine_id'] ?? query).toString();
      final batch = Batch(
        (data['batch'] ?? medId).toString(),
        (data['name'] ?? 'Unknown medicine').toString(),
        (data['manufacturer'] ?? 'Not recorded').toString(),
        _formatDate(data['expiry']),
        (data['quantity'] as num?)?.toInt() ?? 0,
        history,
        medicineId: medId,
        manufacturerName: (data['manufacturer_name'] ?? '').toString(),
        expired: data['expired'] == true,
        recalled: data['recalled'] == true,
        recallReason: (data['recall_reason'] ?? '').toString(),
        stage: (data['stage'] as num?)?.toInt() ?? 1,
        distributor: (data['distributor'] ?? '').toString(),
        distributorName: (data['distributor_name'] ?? '').toString(),
        pharmacy: (data['pharmacy'] ?? '').toString(),
        pharmacyName: (data['pharmacy_name'] ?? '').toString(),
        distributorDetails: (distMap['details'] ?? '').toString(),
        pharmacyDetails: (pharmMap['details'] ?? '').toString(),
        ipfsCid: (data['ipfs_cid'] ?? '').toString(),
        referenceImageUrl: resolveReferenceImageUrl(
          data['reference_image_url']?.toString(),
        ),
        journey: parseJourney(data['journey']),
        events: rawEvents
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        recallEvent: data['recall_event'] is Map
            ? Map<String, dynamic>.from(data['recall_event'] as Map)
            : null,
      );

      return VerifyResult(VerifyStatus.found, batch);
    } catch (_) {
      return const VerifyResult(VerifyStatus.unavailable);
    }
  }

  Future<Map<String, dynamic>> verifyImage(
    String id,
    List<int> imageBytes,
    String filename,
  ) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/verify'));

    request.fields['medicine_id'] = id.trim();
    request.files.add(
      http.MultipartFile.fromBytes('image', imageBytes, filename: filename),
    );

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw ApiException(
        (data['error'] ?? 'Image verification failed.').toString(),
        code: (data['code'] ?? 'VERIFY_ERROR').toString(),
        statusCode: response.statusCode,
        data: data,
      );
    }

    return data;
  }

  // ---------------------------------------------------------------------------
  // ORGANIZATION & SUPPLY-CHAIN OPERATIONS
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> registerMedicine({
    required String id,
    required String name,
    required String batch,
    required String expiry,
    required int quantity,
    required List<int> imageBytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/register'),
    );

    if (_authToken != null && _authToken!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $_authToken';
    }

    request.fields['medicine_id'] = id.trim();
    request.fields['name'] = name.trim();
    request.fields['batch'] = batch.trim();
    request.fields['expiry'] = expiry.trim();
    request.fields['quantity'] = quantity.toString();

    request.files.add(
      http.MultipartFile.fromBytes('image', imageBytes, filename: filename),
    );

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Medicine registration failed.');
    }

    return data;
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/api/users'), headers: _headers())
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch organization users.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['users'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> registerUser({
    required String role,
    required String name,
    String? email,
    String? username,
    String? password,
    String? licenseNumber,
    String? contactPhone,
    String? location,
    String? linkedManufacturer,
    String? linkedDistributor,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/register-user'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'role': role.toLowerCase().trim(),
            'name': name.trim(),
            'email': (email ?? '').trim(),
            'username': (username ?? '').trim(),
            'password': password ?? '',
            'license_number': (licenseNumber ?? '').trim(),
            'contact_phone': (contactPhone ?? '').trim(),
            'location': (location ?? '').trim(),
            'linked_manufacturer': linkedManufacturer ?? '',
            'linked_distributor': linkedDistributor ?? '',
          }),
        )
        .timeout(const Duration(seconds: 20));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(
        (data['error'] ?? 'Organization registration failed.').toString(),
        code: (data['code'] ?? 'REGISTRATION_FAILED').toString(),
        statusCode: response.statusCode,
        data: data,
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> approveUser({
    required String target,
    String approverRole = 'admin',
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/approve-user'),
          headers: _headers(),
          body: jsonEncode({
            'target': target.trim(),
            'approver_role': approverRole.toLowerCase().trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Approval failed.');
    }
    return data;
  }

  Future<Map<String, dynamic>> rejectUser({
    required String target,
    String rejecterRole = 'admin',
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/reject-user'),
          headers: _headers(),
          body: jsonEncode({
            'target': target.trim(),
            'rejecter_role': rejecterRole.toLowerCase().trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Rejection failed.');
    }
    return data;
  }

  Future<Map<String, dynamic>> recordDistributorReceipt({
    required String medicineId,
    required String details,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/distributor/receive'),
          headers: _headers(),
          body: jsonEncode({
            'medicine_id': medicineId.trim(),
            'details': details.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Distributor receipt failed.');
    }
    return data;
  }

  Future<Map<String, dynamic>> recordPharmacyReceipt({
    required String medicineId,
    required String details,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/pharmacy/receive'),
          headers: _headers(),
          body: jsonEncode({
            'medicine_id': medicineId.trim(),
            'details': details.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Pharmacy receipt failed.');
    }
    return data;
  }

  Future<List<Batch>> getBatches({int? stage, String? manufacturer}) async {
    final queryParams = <String, String>{};
    if (stage != null) queryParams['stage'] = stage.toString();
    if (manufacturer != null && manufacturer.isNotEmpty) {
      queryParams['manufacturer'] = manufacturer;
    }

    final uri = Uri.parse('$baseUrl/api/batches')
        .replace(queryParameters: queryParams.isEmpty ? null : queryParams);

    final response = await _client
        .get(uri, headers: _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch batches.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['batches'] as List? ?? [];

    return list.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final medId = (map['id'] ?? map['batch'] ?? '').toString();
      return Batch(
        medId,
        (map['name'] ?? 'Unknown medicine').toString(),
        (map['manufacturer'] ?? 'Not recorded').toString(),
        _formatDate(map['expiry']),
        (map['quantity'] as num?)?.toInt() ?? 0,
        const [],
        medicineId: medId,
        expired: map['expired'] == true,
        recalled: map['recalled'] == true,
        recallReason: (map['recall_reason'] ?? '').toString(),
        stage: (map['stage'] as num?)?.toInt() ?? 1,
        distributor: (map['distributor'] ?? '').toString(),
        pharmacy: (map['pharmacy'] ?? '').toString(),
        ipfsCid: (map['ipfs_cid'] ?? '').toString(),
      );
    }).toList();
  }

  Future<Map<String, dynamic>> getSystemRoles() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/api/roles'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch system roles.');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> recallMedicine({
    required String medicineId,
    required String reason,
    String role = 'manufacturer',
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/recall'),
          headers: _headers(),
          body: jsonEncode({
            'medicine_id': medicineId.trim(),
            'reason': reason.trim(),
            'role': role.toLowerCase().trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Medicine recall failed.');
    }
    return data;
  }

  void dispose() {
    _client.close();
  }
}

final FlaskApiService api = FlaskApiService();
