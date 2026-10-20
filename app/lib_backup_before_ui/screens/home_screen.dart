
import 'package:flutter/material.dart';

import 'verify_screen.dart';
import 'consumer/scan_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _scanQr(BuildContext context) async {
    final scannedValue = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanScreen(),
      ),
    );

    if (!context.mounted ||
        scannedValue == null ||
        scannedValue.trim().isEmpty) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerifyScreen(
          initialMedicineId: scannedValue.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PharmaTrace | Consumer'),
        backgroundColor: color.primaryContainer,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user,
                  size: 96,
                  color: color.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Check if your medicine is genuine',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _scanQr(context),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Scan QR code'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VerifyScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.keyboard),
                    label: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Enter batch ID'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
