import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../theme/app_theme.dart';
import 'role_login_screen.dart';

class RoleSelectScreen extends StatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen> {
  UserRole _selectedRole = UserRole.manufacturer;

  static const List<UserRole> _orgRoles = [
    UserRole.manufacturer,
    UserRole.distributor,
    UserRole.pharmacy,
    UserRole.admin,
  ];

  IconData _roleIcon(UserRole role) {
    switch (role) {
      case UserRole.manufacturer:
        return Icons.precision_manufacturing_outlined;
      case UserRole.distributor:
        return Icons.local_shipping_outlined;
      case UserRole.pharmacy:
        return Icons.local_pharmacy_outlined;
      case UserRole.admin:
        return Icons.shield_outlined;
      case UserRole.consumer:
        return Icons.person_outline;
    }
  }

  String _roleSummary(UserRole role) {
    switch (role) {
      case UserRole.manufacturer:
        return 'Register batches and reference packaging.';
      case UserRole.distributor:
        return 'Confirm wholesale custody and shipments.';
      case UserRole.pharmacy:
        return 'Verify incoming stock before dispensing.';
      case UserRole.admin:
        return 'Review and authorize network organizations.';
      case UserRole.consumer:
        return '';
    }
  }

  void _openLogin(UserRole role) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RoleLoginScreen(initialRole: role)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Organization Access')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select your role',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose your supply-chain role to sign in.',
                    style: TextStyle(fontSize: 15, color: AppColors.muted),
                  ),
                  const SizedBox(height: 28),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoCols = constraints.maxWidth >= 520;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _orgRoles.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: twoCols ? 2 : 1,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 156,
                        ),
                        itemBuilder: (context, index) {
                          final role = _orgRoles[index];
                          final selected = _selectedRole == role;
                          return Material(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: selected
                                    ? AppColors.emerald
                                    : AppColors.hairline,
                                width: selected ? 1.8 : 1.0,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                setState(() => _selectedRole = role);
                                _openLogin(role);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? AppColors.mintSoft
                                                : const Color(0xFFF1F5F4),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Icon(
                                            _roleIcon(role),
                                            color: selected
                                                ? AppColors.tealDark
                                                : AppColors.ink,
                                            size: 22,
                                          ),
                                        ),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 18,
                                          color: selected
                                              ? AppColors.tealDark
                                              : AppColors.muted,
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          role.title,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.ink,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _roleSummary(role),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.muted,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
