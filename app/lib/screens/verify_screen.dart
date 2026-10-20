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
}  VerifyResult? _result;
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
      _imageResult = {'error': e.toString()};
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
    return _banner(
      Colors.red.shade50,
      Icons.warning_amber,
      'Unknown ID',
      'No matching record found. Be careful and report this medicine.',
    );
  }

  if (r.status == VerifyStatus.unavailable) {
    return _banner(
      Colors.grey.shade200,
      Icons.cloud_off,
      'Could not verify',
      'Network or blockchain is unavailable. Try again later.',
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
          'Medicine recalled',
          b.recallReason.isEmpty
              ? 'The blockchain record is marked as recalled.'
              : b.recallReason,
        ),

      if (b.expired)
        _banner(
          Colors.orange.shade50,
          Icons.warning_amber,
          'Medicine expired',
          'The blockchain record indicates this medicine has expired.',
        ),

      _banner(
        Colors.green.shade50,
        Icons.check_circle,
        'Registered record found',
        'A blockchain record exists. This does not prove the medicine is genuine.',
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
              _row('Expiry', b.expiry),
              _row(
                'Quantity',
                b.quantity > 0
                    ? '${b.quantity}'
                    : 'Not recorded on blockchain',
              ),
            ],
          ),
        ),
      ),

      const SizedBox(height: 8),

      const Text(
        'Supply chain history',
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
                  labelText: 'Medicine ID or Batch ID',
                  hintText: 'e.g. PT-TEST-001',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 12),
              FilledButton(
  onPressed: _loading ? null : _verify,
  child: const Padding(
    padding: EdgeInsets.all(12),
    child: Text('Verify'),
  ),
),
const SizedBox(height: 8),
OutlinedButton.icon(
  onPressed: _loading ? null : _scanQr,
  icon: const Icon(Icons.qr_code_scanner),
  label: const Padding(
    padding: EdgeInsets.all(12),
    child: Text('Scan QR Code'),
  ),
),

const SizedBox(height: 8),
OutlinedButton.icon(
  onPressed: _loading ? null : _pickMedicineImage,
  icon: const Icon(Icons.add_a_photo),
  label: Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      _selectedImage == null
          ? 'Choose Medicine Photo'
          : 'Photo: ${_selectedImage!.name}',
    ),
  ),
),
const SizedBox(height: 8),
FilledButton.tonalIcon(
  onPressed: _loading ? null : _verifyImage,
  icon: const Icon(Icons.verified_outlined),
  label: const Padding(
    padding: EdgeInsets.all(12),
    child: Text('Verify Photo'),
  ),
),
const SizedBox(height: 20),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_result != null) _resultView(_result!),

if (_selectedImage != null) ...[
  const SizedBox(height: 12),
  const Text(
    'Selected medicine photo',
    style: TextStyle(fontWeight: FontWeight.bold),
  ),
  const SizedBox(height: 8),
  FutureBuilder<Uint8List>(
    future: _selectedImage!.readAsBytes(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return Image.memory(
        snapshot.data!,
        height: 180,
        fit: BoxFit.contain,
      );
    },
  ),
],
if (_imageResult != null) ...[
  const SizedBox(height: 12),
  Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Image Verification Result',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Verdict: ${_imageResult!['verdict'] ?? 'Unavailable'}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (_imageResult!['error'] != null)
            Text('Error: ${_imageResult!['error']}'),
          if (_imageResult!['details'] is Map)
            Text(
              'Image similarity: ${_imageResult!['details']['similarity'] ?? 'Not available'}',
            ),
          if (_imageResult!['reason'] != null)
            Text('Reason: ${_imageResult!['reason']}'),
        ],
      ),
    ),
  ),
],

            ],
          ),
        ),
      ),
    );
  }
}