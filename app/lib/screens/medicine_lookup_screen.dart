import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pharma_artwork.dart';
import 'verify_screen.dart';

class MedicineLookupScreen extends StatefulWidget {
  final String? initialQuery;

  const MedicineLookupScreen({super.key, this.initialQuery});

  @override
  State<MedicineLookupScreen> createState() => _MedicineLookupScreenState();
}

class _MedicineLookupScreenState extends State<MedicineLookupScreen> {
  final TextEditingController _controller = TextEditingController();

  VerifyResult? _result;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _controller.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  Future<void> _lookup() async {
    final id = _controller.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a medicine ID or batch ID.')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _result = null;
    });

    final result = await api.verifyBatch(id);
    if (!mounted) return;

    setState(() {
      _result = result;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Batch Lookup')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            children: [
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: AppColors.hairline),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Search Batch Records',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Enter a medicine or batch ID to view its supply-chain timeline.',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _lookup(),
                        decoration: const InputDecoration(
                          labelText: 'Medicine or Batch ID',
                          hintText: 'Enter medicine or batch ID',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _loading ? null : _lookup,
                          child: Text(
                            _loading ? 'Searching...' : 'Look Up Batch',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_result != null) ...[
                const SizedBox(height: 20),
                _buildResult(_result!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult(VerifyResult result) {
    if (result.status == VerifyStatus.unavailable) {
      return Material(
        color: const Color(0xFFFFFBEB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const ListTile(
          contentPadding: EdgeInsets.all(16),
          leading: Icon(Icons.cloud_off_rounded, color: AppColors.warning),
          title: Text(
            'Unable to verify — Service unavailable',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            'Check that the backend and blockchain node are running.',
          ),
        ),
      );
    }

    if (result.status == VerifyStatus.unknown || result.batch == null) {
      return Material(
        color: const Color(0xFFFEF2F2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const ListTile(
          contentPadding: EdgeInsets.all(16),
          leading: Icon(Icons.search_off_rounded, color: AppColors.danger),
          title: Text(
            'Unregistered Batch',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            'No matching medicine record was found on the blockchain.',
          ),
        ),
      );
    }

    final batch = result.batch!;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.medicine,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Batch ${batch.id} • Expires ${batch.expiry} • ${batch.quantity} units',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: batch.recalled
                        ? const Color(0xFFFEF2F2)
                        : AppColors.mintSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    batch.recalled ? 'Recalled' : batch.stageName,
                    style: TextStyle(
                      color: batch.recalled ? AppColors.danger : AppColors.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (batch.recalled) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  batch.recallReason.isEmpty
                      ? 'Recalled on blockchain.'
                      : 'Recall reason: ${batch.recallReason}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'Supply-Chain Journey',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 14),
            VerticalJourneyTimeline(stages: batch.journey),
            const Divider(height: 24),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Technical & Blockchain Audit Details',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                children: [
                  _detail('Batch ID', batch.id),
                  _detail(
                    'Manufacturer',
                    batch.manufacturerName.isNotEmpty
                        ? '${batch.manufacturerName} (${batch.manufacturer})'
                        : batch.manufacturer,
                  ),
                  if (batch.distributorName.isNotEmpty)
                    _detail(
                      'Distributor',
                      '${batch.distributorName} (${batch.distributor})',
                    ),
                  if (batch.pharmacyName.isNotEmpty)
                    _detail(
                      'Pharmacy',
                      '${batch.pharmacyName} (${batch.pharmacy})',
                    ),
                  if (batch.ipfsCid.isNotEmpty)
                    _detail('IPFS CID', batch.ipfsCid),
                  for (final ev in batch.events)
                    _detail(
                      '${ev["event"] ?? "Event"} (#${ev["block_number"] ?? ""})',
                      (ev['tx_hash'] ?? '').toString(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VerifyScreen(initialMedicineId: batch.id),
                    ),
                  );
                },
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Verify Package Photo'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 12,
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
