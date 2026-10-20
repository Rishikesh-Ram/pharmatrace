import 'package:flutter/material.dart';
import 'verify_screen.dart';
import 'register_batch_screen.dart';
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _soon(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PharmaTrace'),
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
                Icon(Icons.verified_user, size: 96, color: color.primary),
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
                    onPressed: () => _soon(context, 'QR scan'),
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
onPressed: () => Navigator.push(context,
    MaterialPageRoute(builder: (_) => const VerifyScreen())),                    icon: const Icon(Icons.keyboard),
                    label: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Enter batch ID'),
                    ),
                  ),
                ),
                                const SizedBox(height: 12),
TextButton.icon(
  onPressed: () => Navigator.push(context,
      MaterialPageRoute(
          builder: (_) => const RegisterBatchScreen())),
  icon: const Icon(Icons.factory),
  label: const Text('Manufacturer: register batch'),
),
              ],
            ),
          ),
        ),
      ),
    );
  }
}