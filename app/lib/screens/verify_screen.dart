import 'package:flutter/material.dart';
import '../services/api_service.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _controller = TextEditingController();
  VerifyResult? _result;
  bool _loading = false;

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _result = null;
    });
    final r = await api.verifyBatch(_controller.text);
    setState(() {
      _loading = false;
      _result = r;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _banner(Color bg, IconData icon, String title, String text) {
    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 110,
              child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _resultView(VerifyResult r) {
    if (r.status == VerifyStatus.unknown) {
      return _banner(Colors.red.shade50, Icons.warning_amber, 'Unknown ID',
          'No matching record found. Be careful and report this medicine.');
    }
    if (r.status == VerifyStatus.unavailable) {
      return _banner(Colors.grey.shade200, Icons.cloud_off, 'Could not verify',
          'Network or blockchain is unavailable. Try again later.');
    }
    final b = r.batch!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _banner(Colors.green.shade50, Icons.check_circle,
            'Registered record found',
            'A record exists. This is not proof the tablets are genuine.'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _row('Medicine', b.medicine),
                _row('Batch ID', b.id),
                _row('Manufacturer', b.manufacturer),
                _row('Expiry', b.expiry),
                _row('Quantity', '${b.quantity}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Supply chain history',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        for (final e in b.history)
          ListTile(
            leading: const Icon(Icons.local_shipping),
            title: Text('${e.from} → ${e.to}'),
            subtitle: Text(e.date),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify medicine')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Batch ID',
                  hintText: 'e.g. BATCH101',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loading ? null : _verify,
                child: const Padding(
                    padding: EdgeInsets.all(12), child: Text('Verify')),
              ),
              const SizedBox(height: 20),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_result != null) _resultView(_result!),
            ],
          ),
        ),
      ),
    );
  }
}