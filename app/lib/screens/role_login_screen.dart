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
  bool _adminProvisioned = true;

  String? _errorTitle;
  String? _errorMessage;
  String? _errorCode;

  static const List<UserRole> _orgRoles = [
    UserRole.manufacturer,
    UserRole.distributor,
    UserRole.pharmacy,
  ];

  @override
  void initState() {
    super.initState();
    final init = widget.initialRole;
    _selectedRole = (init == null || init == UserRole.consumer)
        ? UserRole.manufacturer
        : init;
    _checkAdminStatus();
  }

  @override
  void didUpdateWidget(covariant RoleLoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRole != null &&
        widget.initialRole != oldWidget.initialRole &&
        widget.initialRole != UserRole.consumer) {
      _selectedRole = widget.initialRole!;
      _checkAdminStatus();
    }
  }

  Future<void> _checkAdminStatus() async {
    if (_selectedRole != UserRole.admin) return;
    final provisioned = await api.getAdminStatus();
    if (mounted) {
      setState(() => _adminProvisioned = provisioned);
    }
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
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
      } else if (e.code == 'CREDENTIAL_MISMATCH') {
        title = 'Credential Mismatch';
      } else if (e.code == 'INVALID_CREDENTIALS') {
        title = 'Invalid Credentials';
      } else if (e.code == 'ADMIN_NOT_PROVISIONED') {
        title = 'Administrator Not Provisioned';
        _adminProvisioned = false;
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

  Future<void> _openInitialAdminBootstrapDialog() async {
    final userCtrl = TextEditingController(text: 'admin');
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final orgCtrl = TextEditingController(
      text: 'PharmaTrace Regulatory Authority',
    );
    final dialogFormKey = GlobalKey<FormState>();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Initial Administrator Setup',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.deepTeal,
          ),
        ),
        content: Form(
          key: dialogFormKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Provision the one-time system Administrator bound to the smart contract deployer wallet.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: orgCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Authority / Organization Name',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: userCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Admin Username',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Admin Email'),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password (min 6 characters)',
                  ),
                  validator: (v) => (v == null || v.length < 6)
                      ? 'Minimum 6 characters'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!dialogFormKey.currentState!.validate()) return;
              try {
                await api.bootstrapInitialAdmin(
                  username: userCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  password: passCtrl.text,
                  orgName: orgCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
            child: const Text('Provision Admin'),
          ),
        ],
      ),
    );

    if (created == true && mounted) {
      setState(() {
        _adminProvisioned = true;
        _identifierCtrl.text = emailCtrl.text.trim();
        _errorMessage = null;
        _errorTitle = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Initial Administrator provisioned. You may now sign in.',
          ),
        ),
      );
    }
  }

  void _openOrganizationRegistration() {
    final targetRole =
        (_selectedRole == UserRole.admin || _selectedRole == UserRole.consumer)
        ? UserRole.manufacturer
        : _selectedRole;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OrganizationRegistrationScreen(preselectedRole: targetRole),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _selectedRole == UserRole.admin;

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
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
                    color: AppColors.white,
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
                            if (isAdmin) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.softMint,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        size: 14,
                                        color: AppColors.deepTeal,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Restricted Access Portal',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.deepTeal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            Text(
                              isAdmin ? 'Admin Sign In' : 'Sign in as ${_selectedRole.title}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.deepTeal,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isAdmin
                                  ? 'Authorized platform administrators only.'
                                  : 'Enter your organization credentials to continue.',
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: AppColors.secondaryText,
                              ),
                            ),
                            if (!isAdmin) ...[
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
                                        selectedColor: AppColors.softMint,
                                        labelStyle: TextStyle(
                                          fontSize: 12,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: AppColors.deepTeal,
                                        ),
                                        onSelected: _loading
                                            ? null
                                            : (_) {
                                                setState(() {
                                                  _selectedRole = r;
                                                  _errorMessage = null;
                                                  _errorTitle = null;
                                                });
                                                _checkAdminStatus();
                                              },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            if (_errorMessage != null) _buildErrorBanner(),
                            TextFormField(
                              key: const Key('identifier_field'),
                              controller: _identifierCtrl,
                              enabled: !_loading,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Username or email',
                                prefixIcon: Icon(
                                  Icons.person_outline,
                                  size: 20,
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return isAdmin
                                      ? 'Enter your administrator username or email.'
                                      : 'Enter your username or email.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              key: const Key('password_field'),
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
                            if (!isAdmin) ...[
                              const SizedBox(height: 18),
                              const Divider(),
                              const SizedBox(height: 8),
                              Center(
                                child: TextButton(
                                  key: const Key('register_org_button'),
                                  onPressed: _loading
                                      ? null
                                      : _openOrganizationRegistration,
                                  child: const Text(
                                    'New to PharmaTrace? Register your organization.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryTeal,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                              ),
                            ] else if (!_adminProvisioned) ...[
                              const SizedBox(height: 18),
                              const Divider(),
                              const SizedBox(height: 8),
                              Center(
                                child: TextButton.icon(
                                  onPressed: _loading
                                      ? null
                                      : _openInitialAdminBootstrapDialog,
                                  icon: const Icon(
                                    Icons.admin_panel_settings_outlined,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Complete Initial Administrator Setup',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorTitle != null)
            Text(
              _errorTitle!,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: fg,
                fontSize: 13,
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
