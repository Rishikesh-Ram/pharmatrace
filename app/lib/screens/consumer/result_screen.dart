import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class ConsumerResultScreen extends StatelessWidget {
  final Batch batch;
  final Map<String, dynamic>? imageVerification;

  const ConsumerResultScreen({
    super.key,
    required this.batch,
    this.imageVerification,
  });

  @override
  Widget build(BuildContext context) {
    final verdict = imageVerification?['verdict']?.toString() ?? 'Verified';
    final isVerified = verdict == 'Verified';
    final isSuspicious = verdict == 'Suspicious';

    final badgeColor = isVerified
        ? Colors.green
        : isSuspicious
        ? Colors.orange
        : Colors.red;

    return Scaffold(
      appBar: AppBar(title: const Text('Verification Result')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                color: badgeColor.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        isVerified
                            ? Icons.verified
                            : isSuspicious
                            ? Icons.warning_amber
                            : Icons.cancel_outlined,
                        size: 54,
                        color: badgeColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        verdict.toUpperCase(),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isVerified
                            ? 'Both blockchain record and packaging match verified.'
                            : isSuspicious
                            ? 'Warning: Discrepancies found between packaging and blockchain records.'
                            : 'Alert: Unverified or potentially counterfeit medicine.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.medicine,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(height: 20),
                      _row('Batch ID', batch.id),
                      _row('Manufacturer', batch.manufacturer),
                      _row('Expiry Date', batch.expiry),
                      _row('Stage', batch.stageName),
                      _row('Quantity', '${batch.quantity} units'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Supply-Chain History',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final e in batch.history)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.local_shipping, color: Colors.teal),
                  title: Text('${e.from} → ${e.to}'),
                  subtitle: Text(e.date),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
