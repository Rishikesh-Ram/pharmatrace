
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class MedicineLookupScreen extends StatefulWidget {
  const MedicineLookupScreen({super.key});

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
                'record and available supply-chain history.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _lookup(),
                decoration: InputDecoration(
                  labelText: 'Medicine / Batch ID',
                  hintText: 'e.g. PT-DEMO-003',
                  prefixIcon: const Icon(Icons.medication_outlined),
                  border: const OutlineInputBorder(),
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
                          ),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                    _loading ? 'Searching...' : 'Look up medicine',
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
            'No medicine record was found for this ID.',
          ),
        ),
      );
    }

    final batch = result.batch!;

    return Card(
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
              ],
            ),
            const Divider(height: 28),
            _detail('Medicine / Batch ID', batch.id),
            _detail('Manufacturer', batch.manufacturer),
            _detail('Expiry', batch.expiry),
            if (batch.recalled)
              _status(
                'RECALLED',
                batch.recallReason.isEmpty
                    ? 'This record is marked as recalled.'
                    : batch.recallReason,
                Colors.red,
              ),
            if (batch.expired)
              _status(
                'EXPIRED',
                'The recorded expiry date has passed.',
                Colors.orange,
              ),
            const SizedBox(height: 20),
            const Text(
              'Supply-chain history',
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
            const SizedBox(height: 8),
            const Text(
              'A matching record does not by itself prove that '
              'the physical medicine is genuine. Use the '
              'verification process for authenticity checks.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
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
