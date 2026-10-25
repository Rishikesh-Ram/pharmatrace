import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pharma_artwork.dart';
import 'consumer/scan_screen.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, this.initialMedicineId});

  final String? initialMedicineId;
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  late final TextEditingController _controller;

  VerifyResult? _result;
  bool _loading = false;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  Map<String, dynamic>? _imageResult;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMedicineId ?? '');
    if (widget.initialMedicineId != null &&
        widget.initialMedicineId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
    }
  }

  Future<void> _pickMedicineImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (!mounted || image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;

    setState(() {
      _selectedImage = image;
      _selectedImageBytes = bytes;
      _imageResult = null;
    });
  }

  Future<void> _verifyImage() async {
    final medId = _controller.text.trim();
    if (medId.isEmpty ||
        _selectedImage == null ||
        _selectedImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a batch ID and select a package photo first.'),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _imageResult = null;
    });

    try {
      if (_result == null ||
          _result?.batch?.id.toUpperCase() != medId.toUpperCase()) {
        _result = await api.verifyBatch(medId);
      }

      final result = await api.verifyImage(
        medId,
        _selectedImageBytes!,
        _selectedImage!.name,
      );

      if (!mounted) return;
      setState(() => _imageResult = result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imageResult = {'error': e.toString().replaceAll('Exception: ', '')};
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanQr() async {
    final scannedValue = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );

    if (!mounted || scannedValue == null || scannedValue.isEmpty) return;

    setState(() => _controller.text = scannedValue);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Medicine Verification')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            children: [
              // Primary Search & Package Upload Card
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: AppColors.hairline),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Verify a Medicine',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Scan a QR code, enter a batch ID, or compare a package photo.',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          labelText: 'Medicine or Batch ID',
                          hintText: 'e.g. PT-TEST-002 or 13606265',
                          prefixIcon: const Icon(Icons.qr_code_2_rounded),
                          suffixIcon: IconButton(
                            tooltip: 'Scan QR Code',
                            onPressed: _loading ? null : _scanQr,
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                          ),
                        ),
                        onSubmitted: (_) => _verify(),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _loading ? null : _verify,
                              child: const Text('Check Batch Record'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _pickMedicineImage,
                            icon: const Icon(
                              Icons.add_a_photo_outlined,
                              size: 18,
                            ),
                            label: Text(
                              _selectedImage == null
                                  ? 'Package Photo'
                                  : 'Change Photo',
                            ),
                          ),
                        ],
                      ),
                      if (_selectedImage != null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.tealDark,
                            ),
                            onPressed: _loading ? null : _verifyImage,
                            icon: const Icon(
                              Icons.fact_check_outlined,
                              size: 18,
                            ),
                            label: Text(
                              'Run Optical & OCR Check (${_selectedImage!.name})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_imageResult != null) ...[
                _buildImageResultCard(_imageResult!),
                const SizedBox(height: 18),
              ],
              if (_selectedImageBytes != null) ...[
                _buildSideBySideComparison(),
                const SizedBox(height: 18),
              ],
              if (_result != null) _resultView(_result!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _verdictHero({
    required Color accent,
    required Color bg,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.ink,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultView(VerifyResult r) {
    if (r.status == VerifyStatus.unknown) {
      return _verdictHero(
        accent: AppColors.danger,
        bg: const Color(0xFFFEF2F2),
        icon: Icons.gpp_bad_outlined,
        title: 'Unregistered Batch',
        subtitle:
            'No matching medicine record exists on the blockchain for this ID.',
      );
    }

    if (r.status == VerifyStatus.unavailable) {
      return _verdictHero(
        accent: AppColors.warning,
        bg: const Color(0xFFFFFBEB),
        icon: Icons.cloud_off_rounded,
        title: 'Unable to Verify — Service Offline',
        subtitle: 'Could not reach the verification service. Check your connection and try again.',
      );
    }

    final b = r.batch!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (b.recalled)
          _verdictHero(
            accent: AppColors.danger,
            bg: const Color(0xFFFEF2F2),
            icon: Icons.report_gmailerrorred_rounded,
            title: 'Recalled Medicine',
            subtitle: b.recallReason.isEmpty
                ? 'This batch has been recalled on the blockchain.'
                : 'Recall reason: ${b.recallReason}',
          )
        else if (b.expired)
          _verdictHero(
            accent: AppColors.warning,
            bg: const Color(0xFFFFFBEB),
            icon: Icons.event_busy_rounded,
            title: 'Expired Batch (${b.expiry})',
            subtitle: 'The registered expiry date has passed. Do not consume.',
          )
        else if (b.stage < 3)
          _verdictHero(
            accent: AppColors.warning,
            bg: const Color(0xFFFFFBEB),
            icon: Icons.local_shipping_outlined,
            title: 'Incomplete Custody (${b.stageName})',
            subtitle:
                'Registered on-chain at Stage ${b.stage}, but not yet received by a retail pharmacy.',
          )
        else
          _verdictHero(
            accent: AppColors.tealDark,
            bg: AppColors.mintTint,
            icon: Icons.verified_rounded,
            title: 'On-Chain Custody Verified',
            subtitle: 'All supply-chain stages (Manufacturer → Distributor → Pharmacy) are confirmed on-chain.',
          ),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppColors.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.medicine,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Batch ${b.id} • Expires ${b.expiry} • ${b.quantity} units',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.mintSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        b.stageName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Supply-Chain Journey',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 14),
                if (b.journey.isNotEmpty)
                  VerticalJourneyTimeline(
                    stages: b.journey,
                    stage4CompletedOverride: _imageResult != null,
                  ),
                // Secondary Technical Details Drawer
                const Divider(height: 24),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Technical & Blockchain Audit Details',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                    children: [
                      _row(
                        'Manufacturer',
                        b.manufacturerName.isNotEmpty
                            ? '${b.manufacturerName} (${b.manufacturer})'
                            : b.manufacturer,
                      ),
                      if (b.distributorName.isNotEmpty)
                        _row(
                          'Distributor',
                          '${b.distributorName} (${b.distributor})',
                        ),
                      if (b.pharmacyName.isNotEmpty)
                        _row('Pharmacy', '${b.pharmacyName} (${b.pharmacy})'),
                      if (b.ipfsCid.isNotEmpty)
                        _row('IPFS Reference CID', b.ipfsCid),
                      for (final ev in b.events)
                        _row(
                          '${ev["event"] ?? "Event"} (#${ev["block_number"] ?? ""})',
                          (ev['tx_hash'] ?? '').toString(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSideBySideComparison() {
    final medId = _controller.text.trim();
    final refUrl = medId.isNotEmpty
        ? api.resolveReferenceImageUrl(
            _imageResult?['reference_image_url']?.toString() ??
                _result?.batch?.referenceImageUrl ??
                '/api/reference-image/$medId',
          )
        : '';

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Packaging Comparison (Off-Chain Analysis)',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: refUrl.isEmpty
                            ? const Center(
                                child: Text(
                                  'Reference Image',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.muted,
                                  ),
                                ),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: Image.network(
                                  refUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Text(
                                      'No reference on file',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'IPFS Reference',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.memory(
                            _selectedImageBytes!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Uploaded Photo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageResultCard(Map<String, dynamic> res) {
    if (res.containsKey('error')) {
      return _verdictHero(
        accent: AppColors.warning,
        bg: const Color(0xFFFFFBEB),
        icon: Icons.cloud_off_rounded,
        title: 'Unable to Verify Photo',
        subtitle: res['error'].toString(),
      );
    }

    final explainable = res['explainable'] as Map<String, dynamic>? ?? {};
    final category = (explainable['category'] ?? res['verdict'] ?? 'Unverified')
        .toString();
    final headline = (explainable['headline'] ?? 'Assessment: $category')
        .toString();
    final reasons = (explainable['reasons'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final mismatches = (explainable['field_mismatches'] as List? ?? [])
        .map((e) => e.toString())
        .toList();

    final isVerified = category == 'Verified';
    final isSuspicious = category == 'Suspicious';

    final Color badgeColor = isVerified
        ? AppColors.tealDark
        : isSuspicious
        ? AppColors.warning
        : AppColors.danger;

    final details = res['details'] as Map<String, dynamic>? ?? {};
    final ocr = res['ocr'] as Map<String, dynamic>? ?? {};

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: badgeColor.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isVerified
                      ? Icons.verified_rounded
                      : isSuspicious
                      ? Icons.warning_amber_rounded
                      : Icons.gpp_bad_outlined,
                  color: badgeColor,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
                      ),
                      Text(
                        headline,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...reasons.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 6, color: badgeColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(r, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _metricChip(
                  'On-Chain Custody',
                  details['blockchain_ok'] == true ? 'Verified' : 'Incomplete',
                  details['blockchain_ok'] == true,
                ),
                _metricChip(
                  'Visual Similarity',
                  details['similarity'] != null
                      ? '${(details['similarity'] * 100).toStringAsFixed(1)}%'
                      : 'Checked',
                  details['image_ok'] == true,
                ),
                if (ocr.isNotEmpty)
                  _metricChip(
                    'OCR Batch (${ocr['found_batch'] ?? 'N/A'})',
                    ocr['batch_match'] == true ? 'Matched' : 'Mismatch',
                    ocr['batch_match'] == true,
                  ),
              ],
            ),
            if (mismatches.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final m in mismatches)
                Text(
                  '• $m',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metricChip(String label, String value, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ok ? AppColors.mintTint : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: ok ? AppColors.tealDark : const Color(0xFF92400E),
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
            width: 145,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
