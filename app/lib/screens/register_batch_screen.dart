import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

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
  Uint8List? _selectedImageBytes;
  bool _loading = false;
  String? _registeredId;
  String? _txHash;
  String? _blockNumber;
  String? _confirmationStatus;
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
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImage = picked;
        _selectedImageBytes = bytes;
      });
    }
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;

    if (_selectedImage == null || _selectedImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a reference package photo.'),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final batchId = _batch.text.trim().toUpperCase();

      final response = await api.registerMedicine(
        id: batchId,
        name: _drug.text.trim(),
        batch: batchId,
        expiry: _exp.text.trim(),
        quantity: int.tryParse(_qty.text.trim()) ?? 100,
        imageBytes: _selectedImageBytes!,
        filename: _selectedImage!.name,
      );

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
        _blockNumber = response['block_number']?.toString();
        _confirmationStatus = (response['confirmation_status'] ?? 'Confirmed')
            .toString();
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
      _selectedImageBytes = null;
      _registeredId = null;
      _txHash = null;
      _blockNumber = null;
      _confirmationStatus = null;
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
      suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Register Medicine Batch')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: _registeredId == null ? _formView() : _successView(),
          ),
        ),
      ),
    );
  }

  Widget _formView() => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: AppColors.hairline),
    ),
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'New Batch Registration',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Record batch details on-chain and pin the reference package image.',
              style: TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
            const SizedBox(height: 22),
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFF991B1B),
                    fontSize: 13,
                  ),
                ),
              ),
            TextFormField(
              controller: _drug,
              validator: _req,
              decoration: const InputDecoration(
                labelText: 'Medicine Name',
                hintText: 'e.g. Paracetamol 500mg',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _batch,
                    validator: _req,
                    decoration: const InputDecoration(
                      labelText: 'Batch ID',
                      hintText: 'e.g. PT-DEMO-001',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _qty,
                    keyboardType: TextInputType.number,
                    validator: _req,
                    decoration: const InputDecoration(labelText: 'Units'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _dateField('Mfg Date', _mfg)),
                const SizedBox(width: 12),
                Expanded(child: _dateField('Expiry Date', _exp)),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.image_outlined,
                        color: AppColors.tealDark,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedImage == null
                              ? 'Reference Package Photo'
                              : _selectedImage!.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _loading ? null : _pickImage,
                        child: Text(
                          _selectedImage == null ? 'Choose File' : 'Replace',
                        ),
                      ),
                    ],
                  ),
                  if (_selectedImageBytes != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        _selectedImageBytes!,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _loading ? null : _register,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Register Batch'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _successView() => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: AppColors.hairline),
    ),
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.tealDark,
            size: 52,
          ),
          const SizedBox(height: 12),
          Text(
            'Batch $_registeredId Registered',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.hairline),
              borderRadius: BorderRadius.circular(18),
            ),
            child: QrImageView(data: _registeredId!, size: 180),
          ),
          const SizedBox(height: 18),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Blockchain & IPFS Receipt',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
              children: [
                if (_imageCid != null)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('IPFS CID'),
                    subtitle: SelectableText(_imageCid!),
                  ),
                if (_txHash != null)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Transaction (${_confirmationStatus ?? "Confirmed"}${_blockNumber != null ? " • Block #$_blockNumber" : ""})',
                    ),
                    subtitle: SelectableText(_txHash!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _reset,
              child: const Text('Register Another Batch'),
            ),
          ),
        ],
      ),
    ),
  );
}
