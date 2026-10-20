
import 'package:flutter/material.dart';

import '../models/user_role.dart';
import 'home_screen.dart';
import 'register_batch_screen.dart';
import 'role_login_screen.dart';

class RoleDashboardScreen extends StatelessWidget {
  final UserRole role;

  const RoleDashboardScreen({
    super.key,
    required this.role,
  });

  static const Color teal = Color(0xFF008577);

  @override
  Widget build(BuildContext context) {
    final actions = _actionsFor(role);

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF173C38),
        title: const Text('PharmaTrace'),
        actions: [
          IconButton(
            tooltip: 'Switch role',
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => const RoleLoginScreen(),
                ),
                (route) => false,
              );
            },
            icon: const Icon(Icons.switch_account_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF008577), Color(0xFF36A99A)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.health_and_safety_outlined,
                        color: Colors.white,
                        size: 36,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${role.title} Dashboard',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 26,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        role.description,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Quick actions',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF173C38),
                  ),
                ),
                const SizedBox(height: 12),
                ...actions.map(
                  (action) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: const BorderSide(
                          color: Color(0xFFE0E8E6),
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFE0F2F1),
                          foregroundColor: teal,
                          child: Icon(action.icon),
                        ),
                        title: Text(
                          action.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(action.description),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _openAction(context, action),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Medicine records and verification are provided by the '
                  'PharmaTrace backend and blockchain integration.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_DashboardAction> _actionsFor(UserRole role) {
    switch (role) {
      case UserRole.consumer:
        return [
          _DashboardAction(
            title: 'Verify medicine',
            description: 'Look up a medicine and inspect its record.',
            icon: Icons.verified_outlined,
            kind: 'verify',
          ),
          _DashboardAction(
            title: 'Scan QR code',
            description: 'Open the existing QR scanning flow.',
            icon: Icons.qr_code_scanner,
            kind: 'verify',
          ),
        ];

      case UserRole.manufacturer:
  return [
    _DashboardAction(
      title: 'Register medicine batch',
      description: 'Register a new medicine and its original batch details.',
      icon: Icons.add_box_outlined,
      kind: 'register',
    ),
  ];

      case UserRole.distributor:
  return [
    _DashboardAction(
      title: 'Verify received batch',
      description: 'Check a medicine batch received from a manufacturer.',
      icon: Icons.fact_check_outlined,
      kind: 'verify',
    ),
    _DashboardAction(
      title: 'Record medicine receipt',
      description: 'Record distributor details without overwriting existing records.',
      icon: Icons.local_shipping_outlined,
      kind: 'record_receipt',
    ),
  ];

     case UserRole.pharmacy:
  return [
    _DashboardAction(
      title: 'Verify incoming medicine',
      description: 'Check a medicine batch received from a distributor.',
      icon: Icons.fact_check_outlined,
      kind: 'verify',
    ),
    _DashboardAction(
      title: 'Record medicine receipt',
      description: 'Record pharmacy receipt details while preserving earlier records.',
      icon: Icons.store_outlined,
      kind: 'record_receipt',
    ),
  ];

      case UserRole.admin:
        return [
          _DashboardAction(
            title: 'Medicine record lookup',
            description: 'Inspect records on the connected local chain.',
            icon: Icons.manage_search,
            kind: 'verify',
          ),
          _DashboardAction(
            title: 'Organization management',
            description: 'UI placeholder until admin API actions are wired.',
            icon: Icons.approval_outlined,
            kind: 'placeholder',
          ),
        ];
    }
  }

  void _openAction(BuildContext context, _DashboardAction action) {
    switch (action.kind) {
      case 'verify':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        break;

      case 'register':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RegisterBatchScreen()),
        );
        break;

      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This demo screen is not connected to a backend action yet.',
            ),
          ),
        );
    }
  }
}

class _DashboardAction {
  final String title;
  final String description;
  final IconData icon;
  final String kind;

  const _DashboardAction({
    required this.title,
    required this.description,
    required this.icon,
    required this.kind,
  });
}
