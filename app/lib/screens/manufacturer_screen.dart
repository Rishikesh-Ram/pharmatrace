import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ManufacturerScreen extends StatefulWidget {
  const ManufacturerScreen({super.key});
  @override
  State<ManufacturerScreen> createState() => _ManufacturerScreenState();
}

class _ManufacturerScreenState extends State<ManufacturerScreen> {
  final _medicine = TextEditingController();
  final _batch = TextEditingController();
  final _expiry = TextEditingController();
  final _qty = TextEditingController();
  String? _registeredId;

  Widget _field(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register batch')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _field(_medicine, 'Medicine name'),
              _field(_batch, 'Batch ID'),
              _field(_expiry, 'Expiry (YYYY-MM-DD)'),
              _field(_qty, 'Quantity'),
              FilledButton(
                onPressed: () {
                  if (_batch.text.trim().isEmpty) return;
                  setState(() => _registeredId = _batch.text.trim());
                },
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Register batch'),
                ),
              ),
              if (_registeredId != null) ...[
                const SizedBox(height: 24),
                const Text(
                  'Batch registered. QR code:',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Center(child: QrImageView(data: _registeredId!, size: 220)),
                Center(child: Text(_registeredId!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
