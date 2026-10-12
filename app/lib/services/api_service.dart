class TransferEvent {
  final String from, to, date;
  const TransferEvent(this.from, this.to, this.date);
}

class Batch {
  final String id, medicine, manufacturer, expiry;
  final int quantity;
  final List<TransferEvent> history;
  const Batch(this.id, this.medicine, this.manufacturer, this.expiry,
      this.quantity, this.history);
}

enum VerifyStatus { found, unknown, unavailable }

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
    if (key == 'OFFLINE') return const VerifyResult(VerifyStatus.unavailable);
    if (key == 'BATCH101') {
      return const VerifyResult(
        VerifyStatus.found,
        Batch('BATCH101', 'Paracetamol 500mg', 'Sun Pharma', '2027-08-31', 5000, [
          TransferEvent('Sun Pharma', 'MedLine Distributors', '2026-09-02'),
          TransferEvent('MedLine Distributors', 'City Wholesale', '2026-09-10'),
          TransferEvent('City Wholesale', 'Apollo Pharmacy', '2026-09-20'),
        ]),
      );
    }
    return const VerifyResult(VerifyStatus.unknown);
  }
}

final ApiService api = MockApiService();