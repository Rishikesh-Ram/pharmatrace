import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'organization_registration_screen.dart';
import 'role_dashboard_screen.dart';

class RoleLoginScreen extends StatefulWidget {
  final UserRole? initialRole;

  const RoleLoginScreen({super.key, this.initialRole});

  @override
  State<RoleLoginScreen> createState() => _RoleLoginScreenState();
}

class _RoleLoginScreenState extends State<RoleLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  late UserRole _selectedRole;
  bool _obscurePassword = true;
  bool _loading = false;

  String? _errorTitle;
  String? _errorMessage;
  String? _errorCode;

  static const List<UserRole> _orgRoles = [
    UserRole.manufacturer,
    UserRole.distributor,
    UserRole.pharmacy,
    UserRole.admin,
  ];

  @override
  void initState() {
    super.initState();
    final init = widget.initialRole;
    _selectedRole = (init == null || init == UserRole.consumer)
        ? UserRole.manufacturer
        : init;
  }

  @override
  void didUpdateWidget(covariant RoleLoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRole != null &&
        widget.initialRole != oldWidget.initialRole &&
        widget.initialRole != UserRole.consumer) {
      _selectedRole = widget.initialRole!;
    }
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Map<String, String> _demoCredentialsForRole(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return {
          'email': 'admin@pharmatrace.local',
          'password': 'Admin@123',
          'org': 'PharmaTrace Regulatory Authority',
        };
      case UserRole.manufacturer:
        return {
          'email': 'manufacturer@elnova.local',
          'password': 'Mfr@123',
          'org': 'Elnova Pharmaceuticals',
        };
      case UserRole.distributor:
        return {
          'email': 'distributor@medline.local',
          'password': 'Dist@123',
          'org': 'MedLine National Logistics',
        };
      case UserRole.pharmacy:
        return {
          'email': 'pharmacy@apollocare.local',
          'password': 'Pharm@123',
          'org': 'Apollo Care Pharmacy',
        };
      case UserRole.consumer:
        return {'email': '', 'password': '', 'org': ''};
    }
  }

  void _autofillDemoCredentials() {
    final creds = _demoCredentialsForRole(_selectedRole);
    setState(() {
      _identifierCtrl.text = creds['email'] ?? '';
      _passwordCtrl.text = creds['password'] ?? '';
      _errorMessage = null;
      _errorTitle = null;
      _errorCode = null;
    });
  }

  Future<void> _submitLogin() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
      _errorTitle = null;
      _errorCode = null;
    });

    try {
      await api.login(
        identifier: _identifierCtrl.text.trim(),
        password: _passwordCtrl.text,
        expectedRole: _selectedRole.name,
      );

      if (!mounted) return;
      setState(() => _loading = false);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RoleDashboardScreen(role: _selectedRole),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      String title = 'Sign-In Failed';
      if (e.code == 'PENDING_APPROVAL') {
        title = 'Account Pending Approval';
      } else if (e.code == 'REGISTRATION_REJECTED') {
        title = 'Registration Rejected';
      } else if (e.code == 'ROLE_MISMATCH') {
        title = 'Role Mismatch';
      } else if (e.code == 'INVALID_CREDENTIALS') {
        title = 'Invalid Credentials';
      }
      setState(() {
        _loading = false;
        _errorTitle = title;
        _errorMessage = e.message;
        _errorCode = e.code;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorTitle = 'Service Unreachable';
        _errorMessage = 'Could not connect to the PharmaTrace server. Verify the backend is running on port 5001.';
        _errorCode = 'NETWORK_ERROR';
      });
    }
  }

  void _openOrganizationRegistration() {
    if (_selectedRole == UserRole.admin) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OrganizationRegistrationScreen(preselectedRole: _selectedRole),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _selectedRole == UserRole.admin;
    final demoCreds = _demoCredentialsForRole(_selectedRole);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text('${_selectedRole.title} Sign In')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: AppColors.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Sign in as ${_selectedRole.title}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Enter your organization credentials to continue.',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: 18),
                            // Compact role switcher pills
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _orgRoles.map((r) {
                                  final selected = r == _selectedRole;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(r.title),
                                      selected: selected,
                                      selectedColor: AppColors.mintSoft,
                                      labelStyle: TextStyle(
                                        fontSize: 12,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: AppColors.ink,
                                      ),
                                      onSelected: _loading
                                          ? null
                                          : (_) {
                                              setState(() {
                                                _selectedRole = r;
                                                _errorMessage = null;
                                                _errorTitle = null;
                                              });
                                            },
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (_errorMessage != null) _buildErrorBanner(),
                            TextFormField(
                              controller: _identifierCtrl,
                              enabled: !_loading,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Username or Email',
                                prefixIcon: Icon(
                                  Icons.person_outline,
                                  size: 20,
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Enter your username or email.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordCtrl,
                              enabled: !_loading,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submitLogin(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  size: 20,
                                ),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    );
                                  },
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 20,
                                  ),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Enter your password.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              height: 50,
                              child: FilledButton(
                                onPressed: _loading ? null : _submitLogin,
                                child: _loading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Sign In'),
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Divider(),
                            const SizedBox(height: 8),
                            if (!isAdmin)
                              Center(
                                child: TextButton(
                                  onPressed: _loading
                                      ? null
                                      : _openOrganizationRegistration,
                                  child: const Text(
                                    'New to PharmaTrace? Register your organization.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.tealDark,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: Text(
                                  'Public registration is disabled for Admin.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Compact Dev Autofill bar
                  Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: AppColors.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            color: AppColors.tealDark,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Demo: ${demoCreds['org']}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : _autofillDemoCredentials,
                            child: const Text(
                              'Autofill',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
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

  Widget _buildErrorBanner() {
    final isPending = _errorCode == 'PENDING_APPROVAL';
    final bg = isPending ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2);
    final fg = isPending ? const Color(0xFF92400E) : const Color(0xFF991B1B);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _errorTitle ?? 'Sign-In Error',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: fg,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _errorMessage!,
            style: TextStyle(fontSize: 12.5, color: fg, height: 1.35),
          ),
        ],
      ),
    );
  }
}
