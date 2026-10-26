import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/qr_print_helper.dart';

class SelectedPackageImage {
  final XFile file;
  final Uint8List bytes;
  String viewLabel;

  SelectedPackageImage({
    required this.file,
    required this.bytes,
    this.viewLabel = 'Front View',
  });
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

  int _currentStep = 1;
  final List<SelectedPackageImage> _packageImages = [];
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

  void _proceedToStep2() {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _currentStep = 2;
      _errorMessage = null;
    });
  }

  Future<void> _openPrintQrDialog(String batchId) async {
    final cleanDrug =
        _drug.text.trim().isEmpty ? 'Medicine Batch' : _drug.text.trim();
    final cleanBatch = batchId.trim().toUpperCase();

    // Pre-render QR to PNG bytes to ensure it is 100% rendered before print/save
    Uint8List? pngBytes;
    String? base64Png;
    try {
      final painter = QrPainter(
        data: cleanBatch,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF000000),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF000000),
        ),
      );
      final byteData =
          await painter.toImageData(600, format: ui.ImageByteFormat.png);
      if (byteData != null) {
        pngBytes = byteData.buffer.asUint8List();
        base64Png = base64Encode(pngBytes);
      }
    } catch (_) {
      // Fallback if painter fails
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.print_outlined,
                        color: AppColors.primaryTeal, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Print / Save QR Code',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.deepTeal,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: 20, color: AppColors.secondaryText),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Clean white print layout containing ONLY the 4 required items
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 26),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.deepTeal, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0C000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Medicine Name
                      Text(
                        cleanDrug,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.deepTeal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 2. Batch ID
                      Text(
                        'Batch: $cleanBatch',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 3. PharmaTrace QR code at scannable size
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(8),
                        child: QrImageView(
                          data: cleanBatch,
                          size: 200,
                          backgroundColor: Colors.white,
                          gapless: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      // 4. Exact tagline label
                      const Text(
                        'PharmaTrace — Trust Every Dose. Trace Every Batch.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryTeal,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                // Print and Save/Download actions
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.deepTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: base64Png != null
                            ? () {
                                QrPrintHelper.printQr(
                                  drugName: cleanDrug,
                                  batchId: cleanBatch,
                                  base64Png: base64Png!,
                                );
                              }
                            : null,
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text(
                          'Print QR',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.deepTeal,
                          side: const BorderSide(
                              color: AppColors.primaryTeal, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: pngBytes != null
                            ? () {
                                QrPrintHelper.savePng(
                                  batchId: cleanBatch,
                                  pngBytes: pngBytes!,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Downloaded PharmaTrace_QR_$cleanBatch.png',
                                    ),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            : null,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text(
                          'Save PNG',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _completeRegistration() async {
    if (_packageImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select at least one package photo showing the attached QR code.',
          ),
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
      final uploadItems = _packageImages
          .map((img) => PackageImageUpload(
                bytes: img.bytes,
                filename: img.file.name,
                viewLabel: img.viewLabel,
              ))
          .toList();

      final response = await api.registerMedicine(
        id: batchId,
        name: _drug.text.trim(),
        batch: batchId,
        expiry: _exp.text.trim(),
        mfg: _mfg.text.trim(),
        quantity: int.tryParse(_qty.text.trim()) ?? 100,
        imageBytes: uploadItems.first.bytes,
        filename: uploadItems.first.filename,
        packageImages: uploadItems,
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _registeredId = batchId;
        _txHash = response['transaction_hash']?.toString();
        _blockNumber = response['block_number']?.toString();
        _confirmationStatus =
            (response['confirmation_status'] ?? 'Confirmed').toString();
        _imageCid = response['image_cid']?.toString();
        _currentStep = 3;
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
      _currentStep = 1;
      _packageImages.clear();
      _registeredId = null;
      _txHash = null;
      _blockNumber = null;
      _confirmationStatus = null;
      _imageCid = null;
      _errorMessage = null;
      _loading = false;
    });
  }

  List<int>? _parseMonthYear(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    final myMatch = RegExp(r'^(\d{1,2})[/-](\d{4})$').firstMatch(clean);
    if (myMatch != null) {
      final m = int.tryParse(myMatch.group(1)!);
      final y = int.tryParse(myMatch.group(2)!);
      if (m != null && y != null && m >= 1 && m <= 12) {
        return [m, y];
      }
    }
    final ymMatch =
        RegExp(r'^(\d{4})[/-](\d{1,2})(?:[/-]\d{1,2})?$').firstMatch(clean);
    if (ymMatch != null) {
      final y = int.tryParse(ymMatch.group(1)!);
      final m = int.tryParse(ymMatch.group(2)!);
      if (m != null && y != null && m >= 1 && m <= 12) {
        return [m, y];
      }
    }
    return null;
  }

  Future<void> _pickMonthYear(TextEditingController c) async {
    final isMfg = (c == _mfg);
    final now = DateTime.now();

    final parsedCurrent = _parseMonthYear(c.text);
    int selectedYear = parsedCurrent != null
        ? parsedCurrent[1]
        : (isMfg ? now.year : now.year + 1);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final monthNames = [
              'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
            ];

            return AlertDialog(
              backgroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              actionsPadding: const EdgeInsets.all(12),
              title: Row(
                children: [
                  const Icon(
                    Icons.calendar_month_outlined,
                    color: AppColors.primaryTeal,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isMfg ? 'Manufacturing Date' : 'Expiry Date',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.deepTeal,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Select Month & Year (as printed on medicine packet)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warmIvory,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            color: AppColors.deepTeal,
                            onPressed: selectedYear > 2015
                                ? () => setDialogState(() => selectedYear--)
                                : null,
                          ),
                          Text(
                            '$selectedYear',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.deepTeal,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            color: AppColors.deepTeal,
                            onPressed: selectedYear < 2040
                                ? () => setDialogState(() => selectedYear++)
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 12,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.8,
                      ),
                      itemBuilder: (ctx, idx) {
                        final mNum = idx + 1;
                        final mName = monthNames[idx];

                        bool enabled = true;
                        if (isMfg) {
                          if (selectedYear > now.year ||
                              (selectedYear == now.year && mNum > now.month)) {
                            enabled = false;
                          }
                          if (_exp.text.trim().isNotEmpty) {
                            final expParts = _parseMonthYear(_exp.text);
                            if (expParts != null) {
                              if (selectedYear > expParts[1] ||
                                  (selectedYear == expParts[1] &&
                                      mNum >= expParts[0])) {
                                enabled = false;
                              }
                            }
                          }
                        } else {
                          if (selectedYear < now.year ||
                              (selectedYear == now.year && mNum < now.month)) {
                            enabled = false;
                          }
                          if (_mfg.text.trim().isNotEmpty) {
                            final mfgParts = _parseMonthYear(_mfg.text);
                            if (mfgParts != null) {
                              if (selectedYear < mfgParts[1] ||
                                  (selectedYear == mfgParts[1] &&
                                      mNum <= mfgParts[0])) {
                                enabled = false;
                              }
                            }
                          }
                        }

                        final isCurrentSelected =
                            (parsedCurrent != null &&
                                parsedCurrent[0] == mNum &&
                                parsedCurrent[1] == selectedYear);

                        return Material(
                          color: isCurrentSelected
                              ? AppColors.primaryTeal
                              : (enabled
                                  ? AppColors.softMint.withValues(alpha: 0.5)
                                  : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: enabled
                                ? () {
                                    final mStr =
                                        mNum.toString().padLeft(2, '0');
                                    Navigator.pop(
                                        context, '$mStr/$selectedYear');
                                  }
                                : null,
                            child: Center(
                              child: Text(
                                '$mName (${mNum.toString().padLeft(2, '0')})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isCurrentSelected
                                      ? Colors.white
                                      : (enabled
                                          ? AppColors.deepTeal
                                          : Colors.grey.shade400),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        c.text = result;
      });
      _form.currentState?.validate();
    }
  }

  Future<void> _pickMultipleImages() async {
    final picker = ImagePicker();
    final pickedList = await picker.pickMultiImage();
    if (pickedList.isEmpty) return;

    if (_packageImages.length + pickedList.length > 10) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum 10 images allowed. You already selected ${_packageImages.length} images; cannot add ${pickedList.length} more.',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final allowedExts = {'.jpg', '.jpeg', '.png', '.webp'};
    for (final picked in pickedList) {
      final ext = picked.name.contains('.')
          ? '.${picked.name.split('.').last.toLowerCase()}'
          : '';
      if (!allowedExts.contains(ext)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${picked.name}: Unsupported image format. Use JPG, PNG, or WebP.'),
            backgroundColor: AppColors.danger,
          ),
        );
        continue;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${picked.name} exceeds the 10MB limit.'),
            backgroundColor: AppColors.danger,
          ),
        );
        continue;
      }

      final count = _packageImages.length;
      String defaultLabel = 'Front View';
      if (count == 0) {
        defaultLabel = 'Front View';
      } else if (count == 1) {
        defaultLabel = 'Back (Batch & Expiry)';
      } else if (count == 2) {
        defaultLabel = 'Attached QR Sticker';
      } else if (count == 3) {
        defaultLabel = 'Side Panel';
      } else {
        defaultLabel = 'View ${count + 1}';
      }

      _packageImages.add(SelectedPackageImage(
        file: picked,
        bytes: bytes,
        viewLabel: defaultLabel,
      ));
    }

    if (mounted) setState(() {});
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _validateMfgDate(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final parts = _parseMonthYear(v.trim());
    if (parts == null) return 'Enter MM/YYYY (e.g. 01/2026)';
    final m = parts[0];
    final y = parts[1];
    final now = DateTime.now();
    if (y > now.year || (y == now.year && m > now.month)) {
      return 'Mfg date cannot be in the future';
    }
    if (_exp.text.trim().isNotEmpty) {
      final expParts = _parseMonthYear(_exp.text.trim());
      if (expParts != null) {
        final expM = expParts[0];
        final expY = expParts[1];
        if (y > expY || (y == expY && m >= expM)) {
          return 'Mfg month must be before expiry month';
        }
      }
    }
    return null;
  }

  String? _validateExpDate(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final parts = _parseMonthYear(v.trim());
    if (parts == null) return 'Enter MM/YYYY (e.g. 06/2027)';
    final m = parts[0];
    final y = parts[1];
    final now = DateTime.now();
    if (y < now.year || (y == now.year && m < now.month)) {
      return 'Expiry date cannot be in the past';
    }
    if (_mfg.text.trim().isNotEmpty) {
      final mfgParts = _parseMonthYear(_mfg.text.trim());
      if (mfgParts != null) {
        final mfgM = mfgParts[0];
        final mfgY = mfgParts[1];
        if (y < mfgY || (y == mfgY && m <= mfgM)) {
          return 'Expiry month must be later than manufacturing month';
        }
      }
    }
    return null;
  }

  Widget _dateField(
    String label,
    TextEditingController c, {
    String? Function(String?)? validator,
    String? hintText,
  }) => TextFormField(
    controller: c,
    readOnly: true,
    validator: validator ?? _req,
    onTap: () => _pickMonthYear(c),
    decoration: InputDecoration(
      labelText: label,
      hintText: hintText ?? 'MM/YYYY',
      suffixIcon: const Icon(Icons.calendar_month_outlined, size: 18),
    ),
  );

  @override
  Widget build(BuildContext context) {
    Widget content;
    String appBarTitle;

    if (_registeredId != null || _currentStep == 3) {
      content = _successView();
      appBarTitle = 'Batch Registered';
    } else if (_currentStep == 2) {
      content = _step2View();
      appBarTitle = 'Attach QR & Upload Photo';
    } else {
      content = _formView();
      appBarTitle = 'Register Medicine Batch';
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(appBarTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: content,
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
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.softMint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Step 1 of 2',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.deepTeal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
              'Enter batch details to generate your unique PharmaTrace QR code.',
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
                      hintText: 'e.g. BATCH-2026-001',
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
                Expanded(
                  child: _dateField(
                    'Mfg Date',
                    _mfg,
                    validator: _validateMfgDate,
                    hintText: 'e.g. 01/2026',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateField(
                    'Expiry Date',
                    _exp,
                    validator: _validateExpDate,
                    hintText: 'e.g. 06/2027',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _proceedToStep2,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text(
                  'Register Batch',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _step2View() {
    final batchId = _batch.text.trim().toUpperCase();

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back to Step 1',
                  onPressed: _loading
                      ? null
                      : () => setState(() => _currentStep = 1),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.deepTeal),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Step 2 of 2',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryTeal,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Attach QR & Upload Final Photo',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warmIvory,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medication_outlined,
                      size: 18, color: AppColors.deepTeal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_drug.text.trim()}  •  Batch: $batchId  •  Exp: ${_exp.text.trim()}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.deepTeal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
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
            // 1. Generated PharmaTrace QR Code
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.hairline),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QrImageView(
                      data: batchId,
                      size: 170,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      batchId,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.deepTeal,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => _openPrintQrDialog(batchId),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print / Save QR Code'),
              ),
            ),
            const SizedBox(height: 20),
            // 2. Professional explanatory text below the QR code
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.softMint.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: AppColors.primaryTeal.withValues(alpha: 0.2)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 18, color: AppColors.deepTeal),
                      SizedBox(width: 8),
                      Text(
                        'Your PharmaTrace QR Code Is Ready',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.deepTeal,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Print and securely attach this QR code to the corresponding medicine package. Once attached, upload a clear photograph of the final package showing the QR code and the medicine’s identifying details. This helps consumers verify the registered batch.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            // 3. Multi-Image Reference Package Photo Upload (up to 10)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Upload Package Photos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _packageImages.length >= 10
                        ? const Color(0xFFFEF2F2)
                        : AppColors.softMint.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _packageImages.length >= 10
                          ? AppColors.danger
                          : AppColors.primaryTeal,
                    ),
                  ),
                  child: Text(
                    '${_packageImages.length} / 10 images',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _packageImages.length >= 10
                          ? AppColors.danger
                          : AppColors.deepTeal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Upload up to 10 photos of the packaging (Front view, Back with Batch & Expiry, attached QR sticker, side panels, blister foil). The primary view will be pinned on-chain, and the full collection stored in a verifiable IPFS manifest.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.secondaryText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            if (_packageImages.isNotEmpty) ...[
              ..._packageImages.asMap().entries.map((entry) {
                final idx = entry.key;
                final img = entry.value;
                const viewOptions = [
                  'Front View',
                  'Back (Batch & Expiry)',
                  'Attached QR Sticker',
                  'Side Panel',
                  'Blister Foil / Strip',
                  'Other View',
                ];
                final currentView = viewOptions.contains(img.viewLabel)
                    ? img.viewLabel
                    : viewOptions.first;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          img.bytes,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              img.file.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            DropdownButton<String>(
                              value: currentView,
                              isDense: true,
                              underline: const SizedBox(),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.deepTeal,
                                fontWeight: FontWeight.w600,
                              ),
                              items: viewOptions
                                  .map((v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(v),
                                      ))
                                  .toList(),
                              onChanged: (newVal) {
                                if (newVal != null) {
                                  setState(() => img.viewLabel = newVal);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove photo',
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: AppColors.danger, size: 20),
                        onPressed: _loading
                            ? null
                            : () => setState(() => _packageImages.removeAt(idx)),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 6),
            ],
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepTeal,
                side: const BorderSide(color: AppColors.primaryTeal),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: (_packageImages.length >= 10 || _loading)
                  ? null
                  : _pickMultipleImages,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
              label: Text(
                _packageImages.isEmpty
                    ? 'Select Package Photos (up to 10)'
                    : 'Add More Photos (${_packageImages.length}/10)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 24),
            // 4. Complete Registration Button
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: (_packageImages.isEmpty || _loading)
                    ? null
                    : _completeRegistration,
                child: _loading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Registering on Blockchain & IPFS...'),
                        ],
                      )
                    : Text(
                        'Complete Batch Registration (${_packageImages.length} ${_packageImages.length == 1 ? "Photo" : "Photos"})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
