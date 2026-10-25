import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class OrganizationRegistrationScreen extends StatefulWidget {
  final UserRole preselectedRole;

  const OrganizationRegistrationScreen({
    super.key,
    required this.preselectedRole,
  });

  @override
  State<OrganizationRegistrationScreen> createState() =>
      _OrganizationRegistrationScreenState();
}

class _OrganizationRegistrationScreenState
    extends State<OrganizationRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  late UserRole _selectedRole;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _submitting = false;
  bool _loadingPartners = false;

  String? _selectedManufacturerAddr;
  String? _selectedDistributorAddr;
  List<Map<String, dynamic>> _activeManufacturers = [];
  List<Map<String, dynamic>> _activeDistributors = [];

  String? _errorMessage;
  Map<String, dynamic>? _registrationResult;

  @override
  void initState() {
    super.initState();
    _selectedRole =
        (widget.preselectedRole == UserRole.admin ||
            widget.preselectedRole == UserRole.consumer)
        ? UserRole.manufacturer
        : widget.preselectedRole;
    _loadActivePartners();
  }

  Future<void> _loadActivePartners() async {
    setState(() => _loadingPartners = true);
    try {
      final users = await api.getUsers();
      final mfrs = users
          .where(
            (u) =>
                u['role_name'] == 'Manufacturer' &&
                u['status_name'] == 'Active',
          )
          .toList();
      final dists = users
          .where(
            (u) =>
                u['role_name'] == 'Distributor' && u['status_name'] == 'Active',
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _activeManufacturers = mfrs;
        _activeDistributors = dists;
        if (mfrs.isNotEmpty && _selectedManufacturerAddr == null) {
          _selectedManufacturerAddr = mfrs.first['address']?.toString();
        }
        if (dists.isNotEmpty && _selectedDistributorAddr == null) {
          _selectedDistributorAddr = dists.first['address']?.toString();
        }
        _loadingPartners = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPartners = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _licenseCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitRegistration() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final res = await api.registerUser(
        role: _selectedRole.name,
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        licenseNumber: _licenseCtrl.text.trim(),
        contactPhone: _phoneCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        linkedManufacturer: _selectedRole == UserRole.distributor
            ? (_selectedManufacturerAddr ?? '')
            : '',
        linkedDistributor: _selectedRole == UserRole.pharmacy
            ? (_selectedDistributorAddr ?? '')
            : '',
      );

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _registrationResult = res;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Organization Registration')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: _registrationResult != null
                  ? _buildRegistrationReceipt(_registrationResult!)
                  : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Material(
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
                'Register as ${_selectedRole.title}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'New organizations start in Pending status until approved.',
                style: TextStyle(fontSize: 13.5, color: AppColors.muted),
              ),
              const SizedBox(height: 22),
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFF991B1B),
                      fontSize: 13,
                    ),
                  ),
                ),
              DropdownButtonFormField<UserRole>(
                initialValue: _selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.badge_outlined, size: 20),
                ),
                items: const [
                  DropdownMenuItem(
                    value: UserRole.manufacturer,
                    child: Text('Manufacturer'),
                  ),
                  DropdownMenuItem(
                    value: UserRole.distributor,
                    child: Text('Distributor'),
                  ),
                  DropdownMenuItem(
                    value: UserRole.pharmacy,
                    child: Text('Pharmacy'),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (val) {
                        if (val != null) setState(() => _selectedRole = val);
                      },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Organization Name',
                  hintText: 'e.g. Horizon BioPharma Pvt. Ltd.',
                  prefixIcon: Icon(Icons.business_outlined, size: 20),
                ),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Enter your organization name'
                    : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline, size: 20),
                      ),
                      validator: (v) => (v == null || v.trim().length < 3)
                          ? 'Min 3 chars'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined, size: 20),
                      ),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Valid email'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Min 6 characters' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _licenseCtrl,
                      decoration: const InputDecoration(
                        labelText: 'License Number',
                        prefixIcon: Icon(Icons.verified_outlined, size: 20),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        prefixIcon: Icon(Icons.phone_outlined, size: 20),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _locationCtrl,
                decoration: const InputDecoration(
                  labelText: 'City / State',
                  prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              if (_selectedRole == UserRole.distributor) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _selectedManufacturerAddr,
                  decoration: InputDecoration(
                    labelText: 'Upstream Manufacturer',
                    prefixIcon: const Icon(Icons.factory_outlined, size: 20),
                    helperText: _loadingPartners ? 'Loading...' : null,
                  ),
                  items: _activeManufacturers
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m['address']?.toString(),
                          child: Text(
                            m['name']?.toString() ?? '',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setState(() => _selectedManufacturerAddr = val),
                ),
              ],
              if (_selectedRole == UserRole.pharmacy) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _selectedDistributorAddr,
                  decoration: InputDecoration(
                    labelText: 'Upstream Distributor',
                    prefixIcon: const Icon(
                      Icons.local_shipping_outlined,
                      size: 20,
                    ),
                    helperText: _loadingPartners ? 'Loading...' : null,
                  ),
                  items: _activeDistributors
                      .map(
                        (d) => DropdownMenuItem<String>(
                          value: d['address']?.toString(),
                          child: Text(
                            d['name']?.toString() ?? '',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setState(() => _selectedDistributorAddr = val),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _submitting ? null : _submitRegistration,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit Registration'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegistrationReceipt(Map<String, dynamic> res) {
    final statusName = (res['status_name'] ?? 'Pending').toString();
    final txHash = (res['transaction_hash'] ?? '').toString();
    final blockNum = res['block_number']?.toString() ?? 'Confirmed';
    final address = (res['address'] ?? '').toString();
    final reqApprovals = (res['required_approvals'] as List? ?? [])
        .map((e) => e.toString())
        .toList();

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.centerLeft,
              child: CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFFFFBEB),
                child: Icon(
                  Icons.schedule_rounded,
                  color: Colors.amber.shade800,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Registration Submitted',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Status: $statusName (${reqApprovals.isEmpty ? "Admin" : reqApprovals.join(" + ")} approval required before sign-in).',
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
            const Divider(height: 28),
            _receiptRow('Organization', (res['name'] ?? '').toString()),
            _receiptRow('Role', _selectedRole.title),
            _receiptRow('Username', _usernameCtrl.text.trim()),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'On-Chain Technical Details',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                children: [
                  _receiptRow('Wallet', address),
                  _receiptRow('Transaction', txHash),
                  _receiptRow('Block', blockNum),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Return to Sign In'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 115,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
