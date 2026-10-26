class QrParseResult {
  final String rawValue;
  final String? candidateBatchId;
  final bool isPharmaTraceIdentifier;
  final bool isExternalUrl;
  final bool isMalformed;
  final String explanation;

  const QrParseResult({
    required this.rawValue,
    this.candidateBatchId,
    this.isPharmaTraceIdentifier = false,
    this.isExternalUrl = false,
    this.isMalformed = false,
    required this.explanation,
  });

  factory QrParseResult.parse(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) {
      return const QrParseResult(
        rawValue: '',
        isMalformed: true,
        explanation: 'The scanned QR code is empty or unreadable.',
      );
    }

    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      final uri = Uri.tryParse(clean);
      if (uri != null) {
        // Query param checks: id, batch, medicine_id
        final qId = uri.queryParameters['id'] ??
            uri.queryParameters['batch'] ??
            uri.queryParameters['medicine_id'];
        if (qId != null && qId.trim().isNotEmpty) {
          return QrParseResult(
            rawValue: clean,
            candidateBatchId: qId.trim().toUpperCase(),
            isPharmaTraceIdentifier: true,
            explanation: 'PharmaTrace web lookup link detected.',
          );
        }

        // Path segment check: /lookup/<id> or /verify/<id>
        final segments = uri.pathSegments;
        if (segments.length >= 2 &&
            (segments[segments.length - 2] == 'lookup' ||
                segments[segments.length - 2] == 'verify')) {
          final pId = segments.last.trim().toUpperCase();
          if (pId.isNotEmpty) {
            return QrParseResult(
              rawValue: clean,
              candidateBatchId: pId,
              isPharmaTraceIdentifier: true,
              explanation: 'PharmaTrace lookup link detected.',
            );
          }
        }

        // External system URL
        return QrParseResult(
          rawValue: clean,
          isExternalUrl: true,
          explanation:
              'This QR code links to an external web address from outside PharmaTrace ($clean).',
        );
      }
    }

    // Standard alphanumeric batch identifier (e.g. 2623014N, BATCH-123)
    final idRegex = RegExp(r'^[A-Za-z0-9\-_]{2,40}$');
    if (idRegex.hasMatch(clean)) {
      return QrParseResult(
        rawValue: clean,
        candidateBatchId: clean.toUpperCase(),
        isPharmaTraceIdentifier: true,
        explanation: 'Standard PharmaTrace batch identifier.',
      );
    }

    return QrParseResult(
      rawValue: clean,
      isMalformed: true,
      explanation: 'Unsupported QR code format or unreadable data encoding.',
    );
  }
}
