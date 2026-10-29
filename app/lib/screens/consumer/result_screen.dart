import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pharma_artwork.dart';

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
    final verdict = imageVerification?['verdict']?.toString() ??
        (batch.recalled
            ? 'Suspicious'
            : (batch.expired
                ? 'Suspicious'
                : (batch.stage < 3 ? 'Unverified' : 'Verified')));

    final isVerified = verdict == 'Verified';
    final isSuspicious = verdict == 'Suspicious';

    final badgeColor = isVerified
        ? AppColors.tealDark
        : isSuspicious
            ? AppColors.warning
            : const Color(0xFF64748B);

    final String reasonText;
    if (batch.recalled) {
      reasonText = batch.recallReason.isNotEmpty
          ? 'Notice: This batch has been recalled on the blockchain (${batch.recallReason}).'
          : 'Notice: This batch has been recalled on the blockchain.';
    } else if (batch.expired) {
      reasonText = 'Notice: The registered expiry date (${batch.expiry}) has passed. Do not consume.';
    } else if (isVerified) {
      reasonText = 'Authentic blockchain registration and confirmed supply-chain custody verified.';
    } else if (isSuspicious) {
      reasonText = 'Discrepancies or warnings found between packaging evidence and blockchain record.';
    } else {
      reasonText = 'Verification evidence is pending or incomplete (e.g. custody transition pending at retail pharmacy).';
    }

    final mfrDisplay = batch.manufacturerName.isNotEmpty
        ? batch.manufacturerName
        : (batch.manufacturer != '0x0000000000000000000000000000000000000000' && batch.manufacturer.isNotEmpty
            ? batch.manufacturer
            : 'Manufacturer information unavailable');

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      appBar: AppBar(
        title: const Text('Medicine Verification Result'),
        backgroundColor: Colors.white,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                color: badgeColor.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: badgeColor.withValues(alpha: 0.35)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      Icon(
                        isVerified
                            ? Icons.verified
                            : isSuspicious
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline_rounded,
                        size: 52,
                        color: badgeColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        verdict.toUpperCase(),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        reasonText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.ink,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: AppColors.hairline),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              batch.medicine,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _row('Batch ID', batch.id),
                      _row('Manufacturer', mfrDisplay),
                      _row('Expiry Date', batch.expiry),
                      _row('Batch Units', '${batch.quantity} units'),
                      if (batch.distributorName.isNotEmpty)
                        _row('Distributor', batch.distributorName),
                      if (batch.pharmacyName.isNotEmpty)
                        _row('Pharmacy', batch.pharmacyName),
                    ],
                  ),
                ),
              ),
              if (batch.journey.isNotEmpty) ...[
                const SizedBox(height: 18),
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: AppColors.hairline),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Supply-Chain Journey',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 14),
                        VerticalJourneyTimeline(stages: batch.journey),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
