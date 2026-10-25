import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'consumer/scan_screen.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, this.initialMedicineId});

  final String? initialMedicineId;
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialMedicineId ?? '',
    );
    if (widget.initialMedicineId != null && widget.initialMedicineId!.isNotEmpty) {
      _verify();
    }
  }

  VerifyResult? _result;
  bool _loading = false;
  XFile? _selectedImage;
  Map<String, dynamic>? _imageResult;

  Future<void> _pickMedicineImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (!mounted || image == null) return;

    setState(() {
      _selectedImage = image;
      _imageResult = null;
    });
  }

  Future<void> _verifyImage() async {
    if (_controller.text.trim().isEmpty || _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a medicine ID and select a photo first.'),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _imageResult = null;
    });

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final result = await api.verifyImage(
        _controller.text.trim(),
        bytes,
        _selectedImage!.name,
      );

      if (!mounted) return;
      setState(() {
        _imageResult = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imageResult = {'error': e.toString().replaceAll('Exception: ', '')};
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _scanQr() async {
    final scannedValue = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanScreen(),
      ),
    );

    if (!mounted || scannedValue == null || scannedValue.isEmpty) {
      return;
    }

    setState(() {
      _controller.text = scannedValue;
    });

    await _verify();
  }

  Future<void> _verify() async {
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a medicine ID or batch ID.')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final result = await api.verifyBatch(_controller.text);

      if (!mounted) return;

      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _result = const VerifyResult(VerifyStatus.unavailable);
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _banner(Color bg, IconData icon, String title, String text) {
    return Card(
      color: bg,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
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
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 130,
              child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _resultView(VerifyResult r) {
    if (r.status == VerifyStatus.unknown) {
      return _banner(
        Colors.red.shade50,
        Icons.warning_amber,
        'Unregistered Medicine Record',
        'No matching record was found on the blockchain. Be careful: this medicine may be counterfeit.',
      );
    }

    if (r.status == VerifyStatus.unavailable) {
      return _banner(
        Colors.grey.shade200,
        Icons.cloud_off,
        'Verification Service Offline',
        'Network or blockchain node is unreachable. Ensure the backend and local blockchain are running.',
      );
    }

    final b = r.batch!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (b.recalled)
          _banner(
            Colors.red.shade50,
            Icons.report,
            'RECALLED MEDICINE ALERT',
            b.recallReason.isEmpty
                ? 'This batch has been officially marked as RECALLED by the manufacturer or health authority.'
                : 'Reason: ${b.recallReason}',
          ),

        if (b.expired)
          _banner(
            Colors.orange.shade50,
            Icons.warning_amber,
            'EXPIRED MEDICINE ALERT',
            'The registered expiry date for this batch has passed. Do not consume.',
          ),

        _banner(
          Colors.teal.shade50,
          Icons.verified,
          'Blockchain Record Found: ${b.stageName}',
          'This medicine is registered on-chain at stage: ${b.stageName}. '
          'Note: QR scanning verifies blockchain registry; upload a physical package photo below for counterfeit optical verification.',
        ),

        const SizedBox(height: 8),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _row('Medicine', b.medicine),
                _row('Batch ID', b.id),
                _row('Manufacturer', b.manufacturer),
                _row('Expiry Date', b.expiry),
                _row('Batch Quantity', '${b.quantity} units'),
                _row('Current Stage', b.stageName),
              ],
            ),
          ),
        ),

        if (b.distributorDetails.isNotEmpty || b.pharmacyDetails.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Supply-Chain Stage Logs',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          if (b.distributorDetails.isNotEmpty)
            Card(
              color: Colors.blue.shade50,
              elevation: 0,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.local_shipping, color: Colors.blue),
                title: const Text('Distributor Hub', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(b.distributorDetails),
              ),
            ),
          if (b.pharmacyDetails.isNotEmpty)
            Card(
              color: Colors.green.shade50,
              elevation: 0,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.local_pharmacy, color: Colors.green),
                title: const Text('Retail Pharmacy', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(b.pharmacyDetails),
              ),
            ),
        ],

        const SizedBox(height: 12),

        const Text(
          'Blockchain Transfer History',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        if (b.history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No supply-chain history available.'),
          ),

        for (final e in b.history)
          ListTile(
            dense: true,
            leading: const Icon(Icons.timeline, color: Colors.teal),
            title: Text('${e.from} → ${e.to}'),
            subtitle: Text(e.date),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Medicine Authenticity')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Medicine ID or Batch ID',
                  hintText: 'e.g. PT-TEST-002 or BATCH-DEMO-001',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code_2),
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _loading ? null : _verify,
                      child: const Text('Lookup Record'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _scanQr,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Physical Package Verification (OCR + Vision)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                'Compare physical package markings against registered IPFS baseline.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _pickMedicineImage,
                      icon: const Icon(Icons.add_a_photo),
                      label: Text(
                        _selectedImage == null
                            ? 'Select Package Photo'
                            : 'Photo: ${_selectedImage!.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _loading ? null : _verifyImage,
                    icon: const Icon(Icons.fact_check),
                    label: const Text('Verify Photo'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_result != null) _resultView(_result!),

              if (_selectedImage != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Uploaded physical package photo:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                FutureBuilder<Uint8List>(
                  future: _selectedImage!.readAsBytes(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        snapshot.data!,
                        height: 180,
                        fit: BoxFit.contain,
                      ),
                    );
                  },
                ),
              ],
              if (_imageResult != null) ...[
                const SizedBox(height: 16),
                _buildImageResultCard(_imageResult!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageResultCard(Map<String, dynamic> res) {
    final verdict = res['verdict']?.toString() ?? 'Unverified';
    final isVerified = verdict == 'Verified';
    final isSuspicious = verdict == 'Suspicious';

    final Color badgeColor = isVerified
        ? Colors.green
        : isSuspicious
            ? Colors.orange
            : Colors.red;

    final details = res['details'] as Map<String, dynamic>? ?? {};
    final ocr = res['ocr'] as Map<String, dynamic>? ?? {};

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: badgeColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isVerified
                      ? Icons.verified
                      : isSuspicious
                          ? Icons.warning
                          : Icons.cancel,
                  color: badgeColor,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  'Authenticity Verdict: $verdict',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _row('Blockchain Check', details['blockchain_ok'] == true ? 'PASSED' : 'FLAGGED'),
            _row(
              'Package Visual Similarity',
              details['similarity'] != null
                  ? '${(details['similarity'] * 100).toStringAsFixed(1)}%'
                  : (details['image_ok'] == true ? 'PASSED' : 'NOT VERIFIED'),
            ),
            if (ocr.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('OCR Package Inspection:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              _row('Found Batch', ocr['found_batch']?.toString() ?? 'Unreadable'),
              _row('Batch Match', ocr['batch_match'] == true ? 'YES (Match)' : 'NO (Check manual)'),
              _row('Found Expiry', ocr['found_expiry']?.toString() ?? 'Unreadable'),
            ],
            if (res['reason'] != null) ...[
              const SizedBox(height: 8),
              Text('Note: ${res['reason']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ],
        ),
      ),
    );
  }
}
