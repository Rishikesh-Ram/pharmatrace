// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

void printQrCode({
  required String drugName,
  required String batchId,
  required String base64Png,
}) {
  final cleanDrug =
      drugName.trim().isEmpty ? 'Medicine Batch' : drugName.trim();
  final cleanBatch = batchId.trim();

  final htmlContent = '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>PharmaTrace QR - $cleanBatch</title>
  <style>
    @media print {
      body { margin: 0; padding: 20px; background: #ffffff !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
      @page { margin: 10mm; size: auto; }
      .no-print { display: none !important; }
    }
    body {
      margin: 0;
      padding: 40px;
      background: #ffffff;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      box-sizing: border-box;
    }
    .print-card {
      background: #ffffff;
      border: 2px solid #205B58;
      border-radius: 16px;
      padding: 28px 36px;
      text-align: center;
      max-width: 320px;
      width: 100%;
      box-shadow: 0 4px 12px rgba(0,0,0,0.08);
      box-sizing: border-box;
    }
    .med-name {
      font-size: 20px;
      font-weight: 800;
      color: #205B58;
      margin: 0 0 6px 0;
      word-break: break-word;
    }
    .batch-id {
      font-size: 15px;
      font-weight: 700;
      color: #333333;
      margin: 0 0 16px 0;
      letter-spacing: 0.5px;
    }
    .qr-container {
      background: #ffffff;
      display: inline-block;
      margin: 0 auto 16px auto;
    }
    .qr-image {
      width: 220px;
      height: 220px;
      display: block;
    }
    .tagline {
      font-size: 11px;
      font-weight: 700;
      color: #238F88;
      letter-spacing: 0.3px;
      margin: 0;
      text-transform: uppercase;
    }
  </style>
</head>
<body>
  <div class="print-card">
    <div class="med-name">$cleanDrug</div>
    <div class="batch-id">Batch: $cleanBatch</div>
    <div class="qr-container">
      <img class="qr-image" src="data:image/png;base64,$base64Png" alt="PharmaTrace QR Code" />
    </div>
    <div class="tagline">PharmaTrace — Trust Every Dose. Trace Every Batch.</div>
  </div>
  <script>
    window.onload = function() {
      setTimeout(function() {
        window.focus();
        window.print();
      }, 250);
    };
  </script>
</body>
</html>''';

  final blob = html.Blob([htmlContent], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  Future.delayed(const Duration(minutes: 1), () {
    html.Url.revokeObjectUrl(url);
  });
}

void saveQrPng({
  required String batchId,
  required Uint8List pngBytes,
}) {
  final cleanBatch = batchId.trim().isEmpty ? 'batch' : batchId.trim();
  final blob = html.Blob([pngBytes], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..target = '_blank'
    ..download = 'PharmaTrace_QR_$cleanBatch.png';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
