
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
  });
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
            TransferEvent(
              'Sun Pharma',
              'MedLine Distributors',
              '2026-09-02',
            ),
            TransferEvent(
              'MedLine Distributors',
              'City Wholesale',
              '2026-09-10',
            ),
            TransferEvent(
              'City Wholesale',
              'Apollo Pharmacy',
              '2026-09-20',
            ),
          ],
        ),
      );
    }

    return const VerifyResult(VerifyStatus.unknown);
  }
}

class FlaskApiService implements ApiService {
  // For Flutter Web running on the same computer as Flask.
  // Override this with --dart-define when testing on another device.
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

      final batch = Batch(
        (data['batch'] ?? data['medicine_id'] ?? query).toString(),
        (data['name'] ?? 'Unknown medicine').toString(),
        (data['manufacturer'] ?? 'Not recorded').toString(),
        _formatDate(data['expiry']),
        0, // Quantity is not stored in the current smart contract.
        history,
        expired: data['expired'] == true,
        recalled: data['recalled'] == true,
        recallReason: (data['recall_reason'] ?? '').toString(),
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

  void dispose() {
    _client.close();
  }
}

// The application now uses Flask instead of fake data.
final FlaskApiService api = FlaskApiService();