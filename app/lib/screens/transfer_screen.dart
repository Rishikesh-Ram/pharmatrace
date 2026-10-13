import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});
  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _batch = TextEditingController();
  final _orgs = [
    'Sun Pharma (Manufacturer)',
    'MedLine Distributors',
    'City Wholesale',
    'Apollo Pharmacy',
  ];
  String _from = 'Sun Pharma (Manufacturer)';
  String _to = 'MedLine Distributors';
  String? _message;
  bool _ok = false;
  bool _loading = false;

  Future<void> _transfer() async {
    if (_from == _to) {
      setState(() {
        _ok = false;
        _message = 'Sender and receiver must be different.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    final r = await api.verifyBatch(_batch.text);
    setState(() {
      _loading = false;
      if (r.status == VerifyStatus.found) {
        _ok = true;
        _message =
            'Transfer recorded: ${_batch.text.trim().toUpperCase()}\n$_from → $_to';
      } else {
        _ok = false;
        _message = 'Transfer rejected: this batch is not registered.';
      }
    });
  }

  Widget _dropdown(String label, String value, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            items: _orgs
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer batch')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _batch,
                decoration: const InputDecoration(
                    labelText: 'Batch ID (try BATCH101)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              _dropdown('From', _from, (v) => setState(() => _from = v!)),
              _dropdown('To', _to, (v) => setState(() => _to = v!)),
              FilledButton(
                onPressed: _loading ? null : _transfer,
                child: const Padding(
                    padding: EdgeInsets.all(12), child: Text('Transfer')),
              ),
              const SizedBox(height: 20),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_message != null)
                Card(
                  color: _ok ? Colors.green.shade50 : Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(_ok ? Icons.check_circle : Icons.error),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_message!)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}