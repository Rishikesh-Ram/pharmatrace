import 'dart:convert';
import 'package:http/http.dart' as http;

class TransferEvent {
  final String from, to, date;
  const TransferEvent(this.from, this.to, this.date);
}

class Batch {
  final String id, medicine, manufacturer, expiry;
  final int quantity;
  final List<TransferEvent> history;
  final bool expired, recalled;
  final String recallReason;
  final int stage;
  final String distributor;
  final String pharmacy;
  final String distributorDetails;
  final String pharmacyDetails;

  const Batch(
    this.id,
    this.medicine,
    this.manufacturer,
    this.expiry,
    this.quantity,
    this.history, {
    this.expired = false,
    this.recalled = false,
    this.recallReason = '',
    this.stage = 1,
    this.distributor = '',
    this.pharmacy = '',
    this.distributorDetails = '',
    this.pharmacyDetails = '',
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

enum VerifyStatus { found, unknown, unavailable, verified, suspicious, unverified }

class VerifyResult {
  final VerifyStatus status;
  final Batch? batch;
  const VerifyResult(this.status, [this.batch]);
}

abstract class ApiService {
  Future<VerifyResult> verifyBatch(String id);
}

class MockApiService implements ApiService {
  @override
  Future<VerifyResult> verifyBatch(String id) async {
    await Future.delayed(const Duration(milliseconds: 700));
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
            TransferEvent('MedLine Distributors', 'City Wholesale', '2026-09-10'),
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

  FlaskApiService({http.Client? client})
      : _client = client ?? http.Client();

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

  @override
  Future<VerifyResult> verifyBatch(String id) async {
    final query = id.trim();
    if (query.isEmpty) return const VerifyResult(VerifyStatus.unknown);

    try {
      final uri = Uri.parse(
        '$baseUrl/lookup/${Uri.encodeComponent(query)}',
      );

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
          _formatDate(event['timestamp']),
        );
      }).toList();

      final stages = data['stages'] as Map<String, dynamic>? ?? {};
      final distMap = stages['distributor'] as Map<String, dynamic>? ?? {};
      final pharmMap = stages['pharmacy'] as Map<String, dynamic>? ?? {};

      final batch = Batch(
        (data['batch'] ?? data['medicine_id'] ?? query).toString(),
        (data['name'] ?? 'Unknown medicine').toString(),
        (data['manufacturer'] ?? 'Not recorded').toString(),
        _formatDate(data['expiry']),
        (data['quantity'] as num?)?.toInt() ?? 0,
        history,
        expired: data['expired'] == true,
        recalled: data['recalled'] == true,
        recallReason: (data['recall_reason'] ?? '').toString(),
        stage: (data['stage'] as num?)?.toInt() ?? 1,
        distributor: (data['distributor'] ?? '').toString(),
        pharmacy: (data['pharmacy'] ?? '').toString(),
        distributorDetails: (distMap['details'] ?? '').toString(),
        pharmacyDetails: (pharmMap['details'] ?? '').toString(),
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
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/verify'),
    );

    request.fields['medicine_id'] = id.trim();
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: filename,
      ),
    );

    final streamed = await request.send().timeout(
      const Duration(seconds: 60),
    );
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw Exception(
        data['error'] ?? 'Image verification failed.',
      );
    }

    return data;
  }

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

    request.fields['medicine_id'] = id.trim();
    request.fields['name'] = name.trim();
    request.fields['batch'] = batch.trim();
    request.fields['expiry'] = expiry.trim();
    request.fields['quantity'] = quantity.toString();

    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: filename,
      ),
    );

    final streamed = await request.send().timeout(
      const Duration(seconds: 60),
    );
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Medicine registration failed.');
    }

    return data;
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/api/users'))
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
    String? linkedManufacturer,
    String? linkedDistributor,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/register-user'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'role': role.toLowerCase().trim(),
        'name': name.trim(),
        'linked_manufacturer': linkedManufacturer ?? '',
        'linked_distributor': linkedDistributor ?? '',
      }),
    ).timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Organization registration failed.');
    }
    return data;
  }

  Future<Map<String, dynamic>> approveUser({
    required String target,
    String approverRole = 'admin',
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/approve-user'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'target': target.trim(),
        'approver_role': approverRole.toLowerCase().trim(),
      }),
    ).timeout(const Duration(seconds: 15));

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
    final response = await _client.post(
      Uri.parse('$baseUrl/api/reject-user'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'target': target.trim(),
        'rejecter_role': rejecterRole.toLowerCase().trim(),
      }),
    ).timeout(const Duration(seconds: 15));

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
    final response = await _client.post(
      Uri.parse('$baseUrl/api/distributor/receive'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'medicine_id': medicineId.trim(),
        'details': details.trim(),
      }),
    ).timeout(const Duration(seconds: 15));

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
    final response = await _client.post(
      Uri.parse('$baseUrl/api/pharmacy/receive'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'medicine_id': medicineId.trim(),
        'details': details.trim(),
      }),
    ).timeout(const Duration(seconds: 15));

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

    final uri = Uri.parse('$baseUrl/api/batches').replace(
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    final response = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch batches.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['batches'] as List? ?? [];

    return list.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return Batch(
        (map['id'] ?? map['batch'] ?? '').toString(),
        (map['name'] ?? 'Unknown medicine').toString(),
        (map['manufacturer'] ?? 'Not recorded').toString(),
        _formatDate(map['expiry']),
        (map['quantity'] as num?)?.toInt() ?? 0,
        const [],
        expired: map['expired'] == true,
        recalled: map['recalled'] == true,
        recallReason: (map['recall_reason'] ?? '').toString(),
        stage: (map['stage'] as num?)?.toInt() ?? 1,
        distributor: (map['distributor'] ?? '').toString(),
        pharmacy: (map['pharmacy'] ?? '').toString(),
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
    final response = await _client.post(
      Uri.parse('$baseUrl/api/recall'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'medicine_id': medicineId.trim(),
        'reason': reason.trim(),
        'role': role.toLowerCase().trim(),
      }),
    ).timeout(const Duration(seconds: 15));

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
