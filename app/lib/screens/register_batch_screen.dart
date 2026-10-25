import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/api_service.dart';

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
  final _qty = TextEditingController(text: '100');

  XFile? _selectedImage;
  bool _loading = false;
  String? _registeredId;
  String? _txHash;
  String? _imageCid;
  String? _errorMessage;

  @override
  void dispose() {
    _drug.dispose();
    _batch.dispose();
    _mfg.dispose();
    _exp.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController c) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2040),
    );
    if (d != null) c.text = d.toIso8601String().substring(0, 10);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedImage = picked;
      });
    }
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;

    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload a reference packaging photo for IPFS.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final imageBytes = await _selectedImage!.readAsBytes();
      final batchId = _batch.text.trim().toUpperCase();

      final response = await api.registerMedicine(
        id: batchId,
        name: _drug.text.trim(),
        batch: batchId,
        expiry: _exp.text.trim(),
        quantity: int.tryParse(_qty.text.trim()) ?? 100,
        imageBytes: imageBytes,
        filename: _selectedImage!.name,
      );

      // Keep MockRegistry updated for backwards compatibility
      MockRegistry.batches.add({
        'drug': _drug.text.trim(),
        'batchId': batchId,
        'mfgDate': _mfg.text.trim(),
        'expDate': _exp.text.trim(),
      });

      if (!mounted) return;

      setState(() {
        _loading = false;
        _registeredId = batchId;
        _txHash = response['transaction_hash']?.toString();
        _imageCid = response['image_cid']?.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _reset() {
    _drug.clear();
    _batch.clear();
    _mfg.clear();
    _exp.clear();
    _qty.text = '100';
    setState(() {
      _selectedImage = null;
      _registeredId = null;
      _txHash = null;
      _imageCid = null;
      _errorMessage = null;
    });
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
      appBar: AppBar(title: const Text('Register Medicine Batch')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _registeredId == null ? _formView() : _successView(),
          ),
        ),
      ),
    );
  }

  Widget _formView() => Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            TextFormField(
              controller: _drug,
              validator: _req,
              decoration: const InputDecoration(
                labelText: 'Medicine name',
                hintText: 'e.g. Paracetamol 500mg',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _batch,
              validator: _req,
              decoration: const InputDecoration(
                labelText: 'Batch / Medicine ID',
                hintText: 'e.g. PT-DEMO-001',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _qty,
              keyboardType: TextInputType.number,
              validator: _req,
              decoration: const InputDecoration(
                labelText: 'Quantity / Units',
                hintText: 'e.g. 100',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            _dateField('Manufacture date', _mfg),
            const SizedBox(height: 14),
            _dateField('Expiry date (YYYY-MM-DD)', _exp),
            const SizedBox(height: 18),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reference Package Photo (IPFS)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'This image will be stored on Pinata IPFS as the reference baseline for counterfeit detection.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _pickImage,
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(
                            _selectedImage == null ? 'Select photo' : 'Change photo',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedImage == null
                                ? 'No file chosen'
                                : _selectedImage!.name,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _loading ? null : _register,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Register on Blockchain & Pin to IPFS',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      );

  Widget _successView() => Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 56),
          const SizedBox(height: 12),
          Text(
            'Batch $_registeredId Registered!',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Successfully written to blockchain and pinned to IPFS.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(data: _registeredId!, size: 200),
          ),
          const SizedBox(height: 12),
          Text(
            _registeredId!,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          if (_imageCid != null)
            Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.cloud_done, color: Colors.teal),
                title: const Text('IPFS CID'),
                subtitle: Text(_imageCid!),
              ),
            ),
          if (_txHash != null)
            Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.receipt_long, color: Colors.teal),
                title: const Text('Transaction Hash'),
                subtitle: Text(_txHash!),
              ),
            ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _reset,
            child: const Text('Register Another Batch'),
          ),
        ],
      );
}
