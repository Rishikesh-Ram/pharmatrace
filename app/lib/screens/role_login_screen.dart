import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/api_service.dart';
import 'role_dashboard_screen.dart';

class RoleLoginScreen extends StatefulWidget {
  const RoleLoginScreen({super.key});

  @override
  State<RoleLoginScreen> createState() => _RoleLoginScreenState();
}

class _RoleLoginScreenState extends State<RoleLoginScreen> {
  UserRole _selectedRole = UserRole.consumer;

  static const Color teal = Color(0xFF008577);

  IconData _roleIcon(UserRole role) {
    switch (role) {
      case UserRole.consumer:
        return Icons.person_outline;
      case UserRole.manufacturer:
        return Icons.factory_outlined;
      case UserRole.distributor:
        return Icons.local_shipping_outlined;
      case UserRole.pharmacy:
        return Icons.local_pharmacy_outlined;
      case UserRole.admin:
        return Icons.admin_panel_settings_outlined;
    }
  }

  String _roleAddress(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return '0xf39Fd6...2266 (Admin Account)';
      case UserRole.manufacturer:
        return '0x709979...79C8 (Active Manufacturer)';
      case UserRole.distributor:
        return '0x3C44Cd...93BC (Active Distributor)';
      case UserRole.pharmacy:
        return '0x90F79b...b906 (Active Pharmacy)';
      case UserRole.consumer:
        return 'Public Consumer (No Wallet Needed)';
    }
  }

  void _continue() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoleDashboardScreen(role: _selectedRole),
      ),
    );
  }

  void _openRegisterDialog() {
    final nameCtrl = TextEditingController();
    String selectedRole = 'distributor';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Register New Organization'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Organization Name',
                  hintText: 'e.g. Apex Health Logistics',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                items: const [
                  DropdownMenuItem(value: 'manufacturer', child: Text('Manufacturer')),
                  DropdownMenuItem(value: 'distributor', child: Text('Distributor')),
                  DropdownMenuItem(value: 'pharmacy', child: Text('Pharmacy')),
                ],
                onChanged: (v) => setDialogState(() => selectedRole = v ?? 'distributor'),
                decoration: const InputDecoration(labelText: 'Role'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await api.registerUser(role: selectedRole, name: name);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Registration submitted for $name. Pending Admin approval.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Registration failed: $e')),
                    );
                  }
                }
              },
              child: const Text('Register on Blockchain'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF9),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              shrinkWrap: true,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: teal,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.health_and_safety_outlined,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'PharmaTrace',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF173C38),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Blockchain Medicine Traceability & Counterfeit Packaging Detection',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Continue as',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select a participant account to manage on-chain supply-chain operations.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 16),
                ...UserRole.values.map((role) {
                  final selected = role == _selectedRole;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: selected
                          ? const Color(0xFFE0F2F1)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          setState(() => _selectedRole = role);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected
                                  ? teal
                                  : const Color(0xFFE0E8E6),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: selected
                                    ? teal
                                    : const Color(0xFFF0FDF4),
                                child: Icon(
                                  _roleIcon(role),
                                  color: selected ? Colors.white : teal,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          role.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            role == UserRole.consumer ? 'Public' : 'Active Account',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF15803D),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      role.description,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _roleAddress(role),
                                      style: const TextStyle(
                                        color: Colors.black45,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Icons.check_circle,
                                  color: teal,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _continue,
                    style: FilledButton.styleFrom(
                      backgroundColor: teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Continue as ${_selectedRole.title}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _openRegisterDialog,
                    icon: const Icon(Icons.add_business_outlined, size: 20),
                    label: const Text('Register New Organization'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: teal,
                      side: const BorderSide(color: teal),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Connected to Hardhat Local Blockchain (RPC: 8545 • Chain ID: 31337)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
