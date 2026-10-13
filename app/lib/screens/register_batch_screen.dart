import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class MockRegistry {
  static final List<Map<String, String>> batches = [];
}

class RegisterBatchScreen extends StatefulWidget {
  const RegisterBatchScreen({super.key});
  @override
  State<RegisterBatchScreen> createState() => _RegisterBatchScreenState();
}

class _RegisterBatchScreenState extends State<RegisterBatchScreen> {
  final _form = GlobalKey<FormState>();
  final _drug = TextEditingController();
  final _batch = TextEditingController();
  final _mfg = TextEditingController();
  final _exp = TextEditingController();
  bool _loading = false;
  String? _registeredId;

  @override
  void dispose() {
    _drug.dispose();
    _batch.dispose();
    _mfg.dispose();
    _exp.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController c) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (d != null) c.text = d.toIso8601String().substring(0, 10);
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 600));
    MockRegistry.batches.add({
      'drug': _drug.text.trim(),
      'batchId': _batch.text.trim(),
      'mfgDate': _mfg.text.trim(),
      'expDate': _exp.text.trim(),
    });
    setState(() {
      _loading = false;
      _registeredId = _batch.text.trim();
    });
  }

  void _reset() {
    _drug.clear();
    _batch.clear();
    _mfg.clear();
    _exp.clear();
    setState(() => _registeredId = null);
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Widget _dateField(String label, TextEditingController c) => TextFormField(
        controller: c,
        readOnly: true,
        validator: _req,
        onTap: () => _pickDate(c),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register Batch')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _registeredId == null ? _formView() : _successView(),
          ),
        ),
      ),
    );
  }

  Widget _formView() => Form(
        key: _form,
        child: Column(children: [
          TextFormField(
            controller: _drug,
            validator: _req,
            decoration: const InputDecoration(
                labelText: 'Drug name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _batch,
            validator: _req,
            decoration: const InputDecoration(
                labelText: 'Batch ID', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          _dateField('Manufacture date', _mfg),
          const SizedBox(height: 14),
          _dateField('Expiry date', _exp),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _loading ? null : _register,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Register on blockchain'),
            ),
          ),
        ]),
      );

  Widget _successView() => Column(children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 48),
        const SizedBox(height: 8),
        Text('Batch $_registeredId registered',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: QrImageView(data: _registeredId!, size: 220),
        ),
        const SizedBox(height: 8),
        const Text('Print this QR on the packaging'),
        const SizedBox(height: 24),
        OutlinedButton(
            onPressed: _reset, child: const Text('Register another batch')),
      ]);
}