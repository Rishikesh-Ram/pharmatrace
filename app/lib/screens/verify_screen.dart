import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/qr_parser.dart';
import '../widgets/pharma_artwork.dart';
import 'consumer/scan_screen.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({
    super.key,
    this.initialMedicineId,
    this.initialIsLookup = false,
  });

  final String? initialMedicineId;
  final bool initialIsLookup;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _UnknownQrState {
  final String rawScan;
  final String? candidateId;
  final String reason;
  final String? technicalDetail;

  const _UnknownQrState({
    required this.rawScan,
    this.candidateId,
    required this.reason,
    this.technicalDetail,
  });
}

class _VerifyScreenState extends State<VerifyScreen> {
  late final TextEditingController _controller;

  // 5 Extracted / Editable Package Fields
  late final TextEditingController _medicineNameController;
  late final TextEditingController _batchNumberController;
  late final TextEditingController _mfrNameController;
  late final TextEditingController _mfgDateController;
  late final TextEditingController _expiryDateController;

  VerifyResult? _result;
  bool _loading = false;
  bool _extractingFields = false;
  bool _showExtractedReview = false;
  bool _unregisteredSearch = false;
  String? _unregisteredSearchQuery;

  _UnknownQrState? _unknownQr;
  String? _lastSearchedBatchId;

  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  Map<String, dynamic>? _imageResult;
  Map<String, dynamic>? _extractedPackageData;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMedicineId ?? '');
    _medicineNameController = TextEditingController();
    _batchNumberController = TextEditingController();
    _mfrNameController = TextEditingController();
    _mfgDateController = TextEditingController();
    _expiryDateController = TextEditingController();

    if (widget.initialMedicineId != null &&
        widget.initialMedicineId!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleScannedIdentifier(widget.initialMedicineId!.trim());
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _medicineNameController.dispose();
    _batchNumberController.dispose();
    _mfrNameController.dispose();
    _mfgDateController.dispose();
    _expiryDateController.dispose();
    super.dispose();
  }



  Future<void> _pickPackageImageAndExtract() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (!mounted || image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;

    setState(() {
      _selectedImage = image;
      _selectedImageBytes = bytes;
      _extractingFields = true;
      _unknownQr = null;
      _unregisteredSearch = false;
    });

    try {
      final data = await api.extractPackageFields(bytes, image.name);
      if (!mounted) return;

      final fields = (data['fields'] as Map<String, dynamic>?) ?? {};
      _medicineNameController.text = (fields['medicine_name'] ?? '').toString();
      _batchNumberController.text = (fields['batch_number'] ?? '').toString();
      _mfrNameController.text = (fields['manufacturer_name'] ?? '').toString();
      _mfgDateController.text = (fields['mfg_date'] ?? '').toString();
      _expiryDateController.text = (fields['expiry_date'] ?? '').toString();

      setState(() {
        _extractingFields = false;
        _extractedPackageData = data;
        _showExtractedReview = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _extractingFields = false;
        _showExtractedReview = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR extraction notice: $e')),
      );
    }
  }

  Future<void> _verifyImage() async {
    final medId = _controller.text.trim().isNotEmpty
        ? _controller.text.trim()
        : _batchNumberController.text.trim();

    if (medId.isEmpty ||
        _selectedImage == null ||
        _selectedImageBytes == null) {
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

    if (!mounted || scannedValue == null || scannedValue.trim().isEmpty) return;
    await _handleScannedIdentifier(scannedValue.trim());
  }

  Future<void> _handleScannedIdentifier(String rawValue) async {
    final parsed = QrParseResult.parse(rawValue);

    if (parsed.isMalformed || parsed.isExternalUrl || parsed.candidateBatchId == null) {
      setState(() {
        _unknownQr = _UnknownQrState(
          rawScan: rawValue,
          candidateId: null,
          reason:
              "We couldn't find a matching PharmaTrace registration for this QR code. You can upload a clear image of the medicine package so we can extract its printed details.",
          technicalDetail: parsed.explanation,
        );
        _result = null;
        _showExtractedReview = false;
        _unregisteredSearch = false;
      });
      return;
    }

    final candidate = parsed.candidateBatchId!;
    _controller.text = candidate;
    _lastSearchedBatchId = candidate;

    setState(() {
      _loading = true;
      _unknownQr = null;
      _result = null;
      _imageResult = null;
      _showExtractedReview = false;
      _unregisteredSearch = false;
    });

    try {
      final res = await api.verifyBatch(candidate);
      if (!mounted) return;

      if (res.status == VerifyStatus.unknown) {
        setState(() {
          _loading = false;
          _unknownQr = _UnknownQrState(
            rawScan: rawValue,
            candidateId: candidate,
            reason:
                "We couldn't find a matching PharmaTrace registration for this QR code. You can upload a clear image of the medicine package so we can extract its printed details.",
            technicalDetail: "No matching batch or medicine record found on the blockchain.",
          );
        });
      } else {
        setState(() {
          _loading = false;
          _result = res;
        });

        if (_selectedImageBytes != null && _selectedImage != null) {
          _verifyImage();
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _result = const VerifyResult(VerifyStatus.unavailable);
      });
    }
  }

  Future<void> _verifyManualBatch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a medicine batch ID.')),
      );
      return;
    }

    _lastSearchedBatchId = query;
    setState(() {
      _loading = true;
      _unknownQr = null;
      _result = null;
      _imageResult = null;
      _unregisteredSearch = false;
    });

    try {
      final result = await api.verifyBatch(query);
      if (!mounted) return;

      if (result.status == VerifyStatus.unknown) {
        setState(() {
          _unregisteredSearch = true;
          _unregisteredSearchQuery = query;
          _result = null;
          _loading = false;
        });
      } else {
        setState(() {
          _result = result;
          _unregisteredSearch = false;
          _loading = false;
        });

        if (_selectedImageBytes != null && _selectedImage != null && result.batch != null) {
          _verifyImage();
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _result = const VerifyResult(VerifyStatus.unavailable);
        _loading = false;
      });
    }
  }

  Future<void> _searchPharmaTraceWithExtractedFields() async {
    final batchQuery = _batchNumberController.text.trim();
    final nameQuery = _medicineNameController.text.trim();

    if (batchQuery.isEmpty && nameQuery.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter or verify at least a batch number or medicine name.'),
        ),
      );
      return;
    }

    final searchTarget = batchQuery.isNotEmpty ? batchQuery : nameQuery;
    _controller.text = searchTarget;
    _lastSearchedBatchId = searchTarget;

    setState(() {
      _loading = true;
      _result = null;
      _imageResult = null;
      _unregisteredSearch = false;
    });

    try {
      final res = await api.verifyBatch(searchTarget);
      if (!mounted) return;

      if (res.status == VerifyStatus.unknown) {
        setState(() {
          _loading = false;
          _unregisteredSearch = true;
          _unregisteredSearchQuery = searchTarget;
        });
      } else {
        setState(() {
          _loading = false;
          _result = res;
          _unregisteredSearch = false;
        });

        if (_selectedImageBytes != null && _selectedImage != null) {
          _verifyImage();
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _result = const VerifyResult(VerifyStatus.unavailable);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      appBar: AppBar(
        title: const Text('Medicine Verification & Lookup'),
        backgroundColor: Colors.white,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            children: [
              // 1. Unrecognized QR Banner
              if (_unknownQr != null) ...[
                _buildUnknownQrCard(_unknownQr!),
                const SizedBox(height: 18),
              ],

              // 2. Extracted Package Review & Correction Form
              if (_showExtractedReview) ...[
                _buildExtractedReviewCard(),
                const SizedBox(height: 18),
              ],

              // 3. Primary Input & Lookup Card
              _buildInputCard(),
              const SizedBox(height: 20),

              // 4. Loading indicator
              if (_loading || _extractingFields)
                Padding(
                  padding: const EdgeInsets.all(36),
                  child: Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(color: AppColors.tealDark),
                        const SizedBox(height: 14),
                        Text(
                          _extractingFields
                              ? 'Extracting printed medicine packaging details using OCR...'
                              : 'Inspecting blockchain custody & cryptographic records...',
                          style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),

              // 5. Unregistered Search Result
              if (_unregisteredSearch && !_loading) ...[
                _buildUnregisteredResult(_unregisteredSearchQuery ?? _controller.text.trim()),
                const SizedBox(height: 18),
              ],

              // 6. Image Analysis Verdict Card
              if (_imageResult != null && !_loading) ...[
                _buildImageResultCard(_imageResult!),
                const SizedBox(height: 18),
              ],

              // 7. Side-by-side Packaging Visual Comparison
              if (_selectedImageBytes != null && _result?.batch != null && !_loading) ...[
                _buildSideBySideComparison(),
                const SizedBox(height: 18),
              ],

              // 8. Main Evidence & Custody Results
              if (_result != null && !_loading) _buildResultView(_result!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnknownQrCard(_UnknownQrState unk) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB), // Warm amber background
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDE68A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Color(0xFFB45309),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This medicine is not registered through PharmaTrace.',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Unmatched PharmaTrace Registration',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFB45309),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            unk.reason,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.ink,
              height: 1.45,
            ),
          ),
          if (unk.technicalDetail != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Details: ${unk.technicalDetail} (${unk.rawScan})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: AppColors.ink,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.deepTeal,
                foregroundColor: Colors.white,
              ),
              onPressed: _pickPackageImageAndExtract,
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 20),
              label: const Text(
                'Upload Medicine Package Image',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedReviewCard() {
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.softMint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.document_scanner_rounded,
                    color: AppColors.primaryTeal,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Extracted Medicine Package Details',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Review or correct the 4 printed fields below before searching PharmaTrace.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_extractedPackageData?['quality'] != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  _metricChip(
                    'Lighting',
                    (_extractedPackageData!['quality']['lighting'] ?? 'normal').toString(),
                    _extractedPackageData!['quality']['lighting'] == 'normal',
                  ),
                  _metricChip(
                    'Sharpness',
                    _extractedPackageData!['quality']['is_blurry'] == true ? 'Blurry' : 'Sharp',
                    _extractedPackageData!['quality']['is_blurry'] != true,
                  ),
                ],
              ),
            ],
            const Divider(height: 24),

            // 1. Medicine Name
            _buildFieldEditor(
              label: '1. Medicine Name',
              controller: _medicineNameController,
              icon: Icons.medication_outlined,
              hint: 'Unable to read (e.g. Becosules Capsules)',
            ),
            const SizedBox(height: 12),

            // 2. Batch Number
            _buildFieldEditor(
              label: '2. Batch Number',
              controller: _batchNumberController,
              icon: Icons.tag_rounded,
              hint: 'Unable to read (e.g. 2623014N)',
            ),
            const SizedBox(height: 12),

            // 3. Manufacturing Date
            _buildFieldEditor(
              label: '3. Manufacturing Date (MM/YYYY)',
              controller: _mfgDateController,
              icon: Icons.calendar_today_outlined,
              hint: 'Unable to read (e.g. 01/2026)',
            ),
            const SizedBox(height: 12),

            // 4. Expiry Date
            _buildFieldEditor(
              label: '4. Expiry Date (MM/YYYY)',
              controller: _expiryDateController,
              icon: Icons.event_busy_outlined,
              hint: 'Unable to read (e.g. 06/2028)',
            ),
            const SizedBox(height: 18),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.deepTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _loading ? null : _searchPharmaTraceWithExtractedFields,
                    icon: const Icon(Icons.search_rounded, size: 20),
                    label: const Text(
                      'Search PharmaTrace Record',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                  onPressed: _loading ? null : _pickPackageImageAndExtract,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Change Photo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldEditor({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
  }) {
    final hasValue = controller.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: hasValue ? AppColors.mintTint : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                hasValue ? 'Extracted' : 'Unable to read',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: hasValue ? AppColors.tealDark : const Color(0xFFB45309),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            prefixIcon: Icon(icon, size: 18),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildInputCard() {
    return Material(
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Batch Verification & Lookup',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: -0.4,
                  ),
                ),
                TextButton.icon(
                  onPressed: (_loading || _extractingFields) ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan QR'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter a medicine batch ID or upload a packaging photo to extract and verify details.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 16),

            // Batch ID Textfield
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Medicine Batch ID',
                hintText: 'e.g. 2623014N',
                prefixIcon: const Icon(Icons.tag_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Search Batch',
                  icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.primaryTeal),
                  onPressed: (_loading || _extractingFields) ? null : _verifyManualBatch,
                ),
              ),
              onSubmitted: (_) => _verifyManualBatch(),
            ),
            const SizedBox(height: 14),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.deepTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: (_loading || _extractingFields) ? null : _verifyManualBatch,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text(
                      'Look Up Batch',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: (_loading || _extractingFields) ? null : _pickPackageImageAndExtract,
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    label: const Text(
                      'Upload Package Photo',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),

            if (_selectedImage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warmIvory,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.image_outlined, size: 20, color: AppColors.deepTeal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Attached: ${_selectedImage!.name}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.deepTeal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        setState(() {
                          _selectedImage = null;
                          _selectedImageBytes = null;
                          _imageResult = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultView(VerifyResult r) {
    if (r.status == VerifyStatus.unknown) {
      return _buildUnregisteredResult(_lastSearchedBatchId ?? _controller.text.trim());
    }

    if (r.status == VerifyStatus.unavailable) {
      return _verdictHero(
        accent: AppColors.warning,
        bg: const Color(0xFFFFFBEB),
        icon: Icons.cloud_off_rounded,
        title: 'Unable to Verify — Service Unavailable',
        subtitle:
            'Could not connect to the PharmaTrace verification network. Verify that Hardhat (8545) and Flask (5001) are active.',
      );
    }

    final b = r.batch!;
    return _buildAuthenticResult(b);
  }

  Widget _buildUnregisteredResult(String searchedId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _verdictHero(
          accent: const Color(0xFF64748B),
          bg: const Color(0xFFF8FAFC),
          icon: Icons.help_outline_rounded,
          title: 'This medicine/batch is not registered through PharmaTrace.',
          subtitle:
              "We couldn't find a matching PharmaTrace registration for '$searchedId'. This does not by itself prove the medicine is counterfeit, but the batch is not registered in the PharmaTrace network.",
        ),
        const SizedBox(height: 16),
        Material(
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
                  'Query & Evidence Summary',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const Divider(height: 20),
                _row('Queried Identifier', searchedId.isNotEmpty ? searchedId : 'None specified'),
                _row('Blockchain Record', 'Not found on blockchain'),
                _row('Traceability Status', 'Not tracked in PharmaTrace'),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _pickPackageImageAndExtract,
                    icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                    label: const Text(
                      'Upload Package Image to Extract Printed Details',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.warmIvory,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 18, color: AppColors.primaryTeal),
                          SizedBox(width: 8),
                          Text(
                            'Consumer Next Steps',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.deepTeal,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Check the spelling of the batch ID printed on your packaging.\n'
                        '• Upload a clear photo of the medicine box/foil to auto-extract printed details.\n'
                        '• Contact the manufacturer directly using the consumer support contact on the packaging.\n'
                        '• If packaging shows signs of tampering, damaged seals, or suspicious printing, consult your pharmacist or report to the drug regulatory authority.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.secondaryText,
                          height: 1.5,
                        ),
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

  Widget _buildAuthenticResult(Batch b) {
    final mfrDisplay = b.manufacturerName.isNotEmpty
        ? b.manufacturerName
        : (b.manufacturer != '0x0000000000000000000000000000000000000000' && b.manufacturer.isNotEmpty
            ? b.manufacturer
            : 'Manufacturer information unavailable');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (b.recalled)
          _verdictHero(
            accent: AppColors.danger,
            bg: const Color(0xFFFEF2F2),
            icon: Icons.report_gmailerrorred_rounded,
            title: 'Recalled Medicine Batch',
            subtitle: b.recallReason.isEmpty
                ? 'This medicine batch has been officially recalled on the blockchain.'
                : 'Recall reason: ${b.recallReason}',
          )
        else if (b.expired)
          _verdictHero(
            accent: AppColors.warning,
            bg: const Color(0xFFFFFBEB),
            icon: Icons.event_busy_rounded,
            title: 'Expired Medicine Batch (${b.expiry})',
            subtitle: 'The registered expiry date has passed. Do not consume this medication.',
          )
        else if (b.stage < 3)
          _verdictHero(
            accent: AppColors.warning,
            bg: const Color(0xFFFFFBEB),
            icon: Icons.local_shipping_outlined,
            title: 'Incomplete Supply Custody (${b.stageName})',
            subtitle:
                'Batch is registered on-chain at Stage ${b.stage}, but has not yet been received into retail pharmacy inventory.',
          )
        else
          _verdictHero(
            accent: AppColors.tealDark,
            bg: AppColors.mintTint,
            icon: Icons.verified_rounded,
            title: 'Verified — Authenticity & On-Chain Custody Confirmed',
            subtitle:
                'Blockchain registration confirmed. All custody stages (Manufacturer → Distributor → Pharmacy) are verified on-chain.',
          ),
        const SizedBox(height: 16),

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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.medicine,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Batch ${b.id} • Registered Units: ${b.quantity} • Exp: ${b.expiry}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Registered Information
                const Text(
                  'Registered Information (Blockchain Record)',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepTeal,
                  ),
                ),
                const SizedBox(height: 8),
                _row('Medicine Name', b.medicine),
                _row('Batch ID', b.id),
                _row('Manufacturer', mfrDisplay),
                _row('Expiry Date', b.expiry),
                _row('Quantity', '${b.quantity} units'),
                if (b.ipfsCid.isNotEmpty)
                  _row('Reference IPFS CID', b.ipfsCid),
                const SizedBox(height: 20),

                // 4-Field Comparison Table (Extracted vs Registered)
                if (_showExtractedReview || _imageResult != null) ...[
                  _buildFourFieldComparisonTable(b),
                  const SizedBox(height: 24),
                ],

                // Supply-Chain Journey Timeline
                const Text(
                  'Supply-Chain Custody Journey',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 14),
                if (b.journey.isNotEmpty)
                  VerticalJourneyTimeline(stages: b.journey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool? _compareDates(String extracted, String registered, {bool isExpiry = false}) {
    final extStr = extracted.trim();
    final regStr = registered.trim();
    if (extStr.isEmpty) return null;
    if (regStr.isEmpty || regStr == 'Registered on-chain') return true;

    final extParts = _parseDateParts(extStr);
    final regParts = _parseDateParts(regStr);

    if (extParts == null || regParts == null) {
      final dExt = extStr.replaceAll(RegExp(r'[^0-9]'), '');
      final dReg = regStr.replaceAll(RegExp(r'[^0-9]'), '');
      return dExt.isNotEmpty && (dReg.contains(dExt) || dExt.contains(dReg));
    }

    int regEffectiveYear = regParts.year;
    int regEffectiveMonth = regParts.month;

    // Exclusive upper-bound convention for expiry:
    // Stored on-chain timestamp on day 1 (e.g. 2027-07-01 00:00:00 UTC) represents
    // the exclusive boundary for the previous month (i.e. valid through end of June 2027).
    if (isExpiry && regParts.day == 1) {
      if (regEffectiveMonth == 1) {
        regEffectiveYear -= 1;
        regEffectiveMonth = 12;
      } else {
        regEffectiveMonth -= 1;
      }
    }

    // When extracted date provides month/year precision (MM/YYYY):
    if (extParts.isMonthYearOnly || regParts.isMonthYearOnly) {
      return extParts.year == regEffectiveYear && extParts.month == regEffectiveMonth;
    }

    // When registered date is exclusive boundary on day 1, any day in the effective month matches
    if (isExpiry && regParts.day == 1) {
      return extParts.year == regEffectiveYear && extParts.month == regEffectiveMonth;
    }

    return extParts.year == regParts.year &&
        extParts.month == regParts.month &&
        extParts.day == regParts.day;
  }

  static _DateParts? _parseDateParts(String str) {
    final s = str.trim();
    // 1. MM/YYYY or MM-YYYY
    final myMatch = RegExp(r'^(\d{1,2})[-/](\d{4})$').firstMatch(s);
    if (myMatch != null) {
      final m = int.tryParse(myMatch.group(1)!) ?? 0;
      final y = int.tryParse(myMatch.group(2)!) ?? 0;
      if (m >= 1 && m <= 12 && y > 1900) {
        return _DateParts(year: y, month: m, isMonthYearOnly: true);
      }
    }

    // 2. YYYY-MM or YYYY/MM
    final ymMatch = RegExp(r'^(\d{4})[-/](\d{1,2})$').firstMatch(s);
    if (ymMatch != null) {
      final y = int.tryParse(ymMatch.group(1)!) ?? 0;
      final m = int.tryParse(ymMatch.group(2)!) ?? 0;
      if (m >= 1 && m <= 12 && y > 1900) {
        return _DateParts(year: y, month: m, isMonthYearOnly: true);
      }
    }

    // 3. YYYY-MM-DD
    final isoMatch = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(s);
    if (isoMatch != null) {
      final y = int.tryParse(isoMatch.group(1)!) ?? 0;
      final m = int.tryParse(isoMatch.group(2)!) ?? 0;
      final d = int.tryParse(isoMatch.group(3)!) ?? 0;
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31 && y > 1900) {
        return _DateParts(year: y, month: m, day: d, isMonthYearOnly: false);
      }
    }

    // 4. DD/MM/YYYY or DD-MM-YYYY
    final dmyMatch = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(s);
    if (dmyMatch != null) {
      final d = int.tryParse(dmyMatch.group(1)!) ?? 0;
      final m = int.tryParse(dmyMatch.group(2)!) ?? 0;
      final y = int.tryParse(dmyMatch.group(3)!) ?? 0;
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31 && y > 1900) {
        return _DateParts(year: y, month: m, day: d, isMonthYearOnly: false);
      }
    }

    return null;
  }

  Widget _buildFourFieldComparisonTable(Batch b) {
    final extractedName = _medicineNameController.text.trim();
    final extractedBatch = _batchNumberController.text.trim();
    final extractedMfg = _mfgDateController.text.trim();
    final extractedExp = _expiryDateController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Package Printed Details vs Registered On-Chain Record',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: AppColors.deepTeal,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.warmIvory,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            children: [
              _comparisonRow(
                field: 'Medicine Name',
                extracted: extractedName,
                registered: b.medicine,
                match: extractedName.isEmpty
                    ? null
                    : b.medicine.toLowerCase().contains(extractedName.toLowerCase()) ||
                        extractedName.toLowerCase().contains(b.medicine.toLowerCase()),
              ),
              const Divider(height: 1),
              _comparisonRow(
                field: 'Batch Number',
                extracted: extractedBatch,
                registered: b.id,
                match: extractedBatch.isEmpty
                    ? null
                    : b.id.toUpperCase() == extractedBatch.toUpperCase(),
              ),
              const Divider(height: 1),
              _comparisonRow(
                field: 'Mfg Date',
                extracted: extractedMfg,
                registered: b.mfg.isNotEmpty ? b.mfg : 'Registered on-chain',
                match: extractedMfg.isEmpty
                    ? null
                    : (b.mfg.isNotEmpty
                        ? _compareDates(extractedMfg, b.mfg, isExpiry: false)
                        : true),
              ),
              const Divider(height: 1),
              _comparisonRow(
                field: 'Expiry Date',
                extracted: extractedExp,
                registered: b.expiry,
                match: extractedExp.isEmpty
                    ? null
                    : _compareDates(extractedExp, b.expiry, isExpiry: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _comparisonRow({
    required String field,
    required String extracted,
    required String registered,
    required bool? match,
  }) {
    final statusText = match == null
        ? 'Unable to read'
        : match
            ? 'Matches'
            : 'Mismatch';
    final statusColor = match == null
        ? const Color(0xFF64748B)
        : match
            ? AppColors.tealDark
            : AppColors.danger;
    final statusBg = match == null
        ? const Color(0xFFF1F5F9)
        : match
            ? AppColors.mintTint
            : const Color(0xFFFEF2F2);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 115,
            child: Text(
              field,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  extracted.isNotEmpty ? extracted : 'Unable to read from image',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: extracted.isEmpty ? FontStyle.italic : FontStyle.normal,
                    color: extracted.isNotEmpty ? AppColors.ink : AppColors.muted,
                  ),
                ),
                Text(
                  'On-Chain: $registered',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
        ],
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
      margin: const EdgeInsets.only(bottom: 4),
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

  Widget _buildSideBySideComparison() {
    final medId = _result?.batch?.id ?? _controller.text.trim();
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
                                  style: TextStyle(fontSize: 11, color: AppColors.muted),
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
                                      style: TextStyle(fontSize: 11, color: AppColors.muted),
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
    final category = (explainable['category'] ?? res['verdict'] ?? 'Unverified').toString();
    final headline = (explainable['headline'] ?? 'Assessment: $category').toString();
    final reasons = (explainable['reasons'] as List? ?? []).map((e) => e.toString()).toList();
    final mismatches = (explainable['field_mismatches'] as List? ?? []).map((e) => e.toString()).toList();

    final isVerified = category == 'Verified';
    final isSuspicious = category == 'Suspicious';

    final Color badgeColor = isVerified
        ? AppColors.tealDark
        : isSuspicious
            ? AppColors.warning
            : const Color(0xFF64748B);

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
                          : Icons.info_outline_rounded,
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
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
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
                    Expanded(child: Text(r, style: const TextStyle(fontSize: 13))),
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
                if (ocr.containsKey('found_expiry') && ocr['found_expiry'] != null)
                  _metricChip(
                    'OCR Expiry (${ocr['found_expiry']})',
                    ocr['expiry_match'] == true ? 'Matched' : 'Mismatch',
                    ocr['expiry_match'] == true,
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
                fontSize: 12.5,
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

class _DateParts {
  final int year;
  final int month;
  final int? day;
  final bool isMonthYearOnly;

  const _DateParts({
    required this.year,
    required this.month,
    this.day,
    required this.isMonthYearOnly,
  });
}
