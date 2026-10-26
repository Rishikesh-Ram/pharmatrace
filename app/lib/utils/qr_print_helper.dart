import 'dart:typed_data';

import 'qr_print_helper_stub.dart'
    if (dart.library.html) 'qr_print_helper_web.dart';

abstract class QrPrintHelper {
  static void printQr({
    required String drugName,
    required String batchId,
    required String base64Png,
  }) {
    printQrCode(
      drugName: drugName,
      batchId: batchId,
      base64Png: base64Png,
    );
  }

  static void savePng({
    required String batchId,
    required Uint8List pngBytes,
  }) {
    saveQrPng(
      batchId: batchId,
      pngBytes: pngBytes,
    );
  }
}
