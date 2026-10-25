import 'package:flutter/material.dart';
import '../services/api_service.dart';

class MedicineLookupScreen extends StatefulWidget {
  final String? initialQuery;

  const MedicineLookupScreen({super.key, this.initialQuery});

  @override
  State<MedicineLookupScreen> createState() =>
      _MedicineLookupScreenState();
}

class _MedicineLookupScreenState
    extends State<MedicineLookupScreen> {
  final TextEditingController _controller =
      TextEditingController();

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
        const SnackBar(
          content: Text('Enter a medicine ID or batch ID.'),
        ),
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medicine Lookup'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Icon(
                Icons.manage_search,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Find Medicine Records',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter a medicine or batch ID to view its '
                'record and live supply-chain history from the blockchain.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _lookup(),
                decoration: const InputDecoration(
                  labelText: 'Medicine / Batch ID',
                  hintText: 'e.g. PT-TEST-002 or BATCH-DEMO-001',
                  prefixIcon: Icon(Icons.medication_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _lookup,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                    _loading ? 'Searching blockchain...' : 'Look up medicine',
                  ),
                ),
              ),
              if (_result != null) ...[
                const SizedBox(height: 24),
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
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cloud_off, color: Colors.orange),
          title: Text('Service unavailable'),
          subtitle: Text(
            'Could not reach the medicine lookup service. '
            'Check that the backend is running and try again.',
          ),
        ),
      );
    }

    if (result.status == VerifyStatus.unknown ||
        result.batch == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.search_off, color: Colors.red),
          title: Text('No matching record'),
          subtitle: Text(
            'No registered medicine record was found on the blockchain for this ID. '
            'Warning: This package may be counterfeit.',
          ),
        ),
      );
    }

    final batch = result.batch!;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.medication,
                  color: Colors.teal,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    batch.medicine,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Text(
                    batch.stageName,
                    style: TextStyle(
                      color: Colors.teal.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            _detail('Medicine / Batch ID', batch.id),
            _detail('Manufacturer Wallet', batch.manufacturer),
            _detail('Expiry Date', batch.expiry),
            _detail('Batch Quantity', '${batch.quantity} units'),
            _detail('Supply-Chain Stage', batch.stageName),
            if (batch.recalled)
              _status(
                'RECALLED',
                batch.recallReason.isEmpty
                    ? 'This record is marked as recalled by manufacturer or admin.'
                    : batch.recallReason,
                Colors.red,
              ),
            if (batch.expired)
              _status(
                'EXPIRED',
                'The recorded expiry date has passed. Do not consume.',
                Colors.orange,
              ),
            const SizedBox(height: 20),
            const Text(
              'Blockchain Supply-Chain History',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            if (batch.history.isEmpty)
              const Text('No transfer history is available.')
            else
              ...batch.history.map(
                (event) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.local_shipping_outlined,
                    color: Colors.teal,
                  ),
                  title: Text('${event.from} → ${event.to}'),
                  subtitle: Text(event.date),
                ),
              ),
            if (batch.distributorDetails.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.blue.shade50,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Distributor Hub Receipt Log:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(batch.distributorDetails, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
            if (batch.pharmacyDetails.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.green.shade50,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pharmacy Receipt Log:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(batch.pharmacyDetails, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.black54),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Notice: A matching database or blockchain record alone does not prove '
                      'physical packaging authenticity. For high-assurance verification, '
                      'scan the physical packaging with the Verification tool.',
                      style: TextStyle(color: Colors.black87, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 155,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54),
            ),
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

  Widget _status(String title, String message, Color color) {
    return Card(
      color: color.withValues(alpha: 0.10),
      child: ListTile(
        leading: Icon(Icons.warning_amber, color: color),
        title: Text(title),
        subtitle: Text(message),
      ),
    );
  }
}
