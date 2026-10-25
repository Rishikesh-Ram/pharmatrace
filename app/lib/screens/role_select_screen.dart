import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../theme/app_theme.dart';
import 'organization_registration_screen.dart';
import 'role_login_screen.dart';

class RoleSelectScreen extends StatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen> {
  UserRole _selectedRole = UserRole.manufacturer;

  static const List<UserRole> _supplyChainRoles = [
    UserRole.manufacturer,
    UserRole.distributor,
    UserRole.pharmacy,
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
        return 'Authorized platform administrators only.';
      case UserRole.consumer:
        return '';
    }
  }

  void _openLogin(UserRole role) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RoleLoginScreen(initialRole: role)),
    );
  }

  void _openRegistration() {
    final targetRole = _selectedRole.isSupplyChainOrganization
        ? _selectedRole
        : UserRole.manufacturer;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OrganizationRegistrationScreen(preselectedRole: targetRole),
      ),
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
                    'Choose your supply-chain organization role to sign in or register.',
                    style: TextStyle(fontSize: 15, color: AppColors.muted),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final threeCols = constraints.maxWidth >= 600;
                      final twoCols = constraints.maxWidth >= 420;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _supplyChainRoles.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: threeCols
                              ? 3
                              : twoCols
                              ? 2
                              : 1,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          mainAxisExtent: 176,
                        ),
                        itemBuilder: (context, index) {
                          final role = _supplyChainRoles[index];
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
                                padding: const EdgeInsets.all(18),
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
                                            fontSize: 16.5,
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
                                            fontSize: 12,
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
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton.icon(
                      onPressed: _openRegistration,
                      icon: const Icon(Icons.add_business_outlined, size: 18),
                      label: const Text(
                        'New to PharmaTrace? Register your organization.',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryTeal,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Platform Governance',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: _selectedRole == UserRole.admin
                            ? AppColors.emerald
                            : AppColors.hairline,
                        width: _selectedRole == UserRole.admin ? 1.8 : 1.0,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        setState(() => _selectedRole = UserRole.admin);
                        _openLogin(UserRole.admin);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.softMint,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.shield_outlined,
                                color: AppColors.deepTeal,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Administrator',
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _roleSummary(UserRole.admin),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: AppColors.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
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
