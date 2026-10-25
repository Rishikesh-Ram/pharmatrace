import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'continue_choice_screen.dart';
import 'home_screen.dart';
import 'medicine_lookup_screen.dart';
import 'organization_registration_screen.dart';
import 'register_batch_screen.dart';

class RoleDashboardScreen extends StatefulWidget {
  final UserRole role;

  const RoleDashboardScreen({super.key, required this.role});

  @override
  State<RoleDashboardScreen> createState() => _RoleDashboardScreenState();
}

class _RoleDashboardScreenState extends State<RoleDashboardScreen> {
  static const Color teal = AppColors.tealDark;
  static const Color ink = AppColors.ink;
  static const Color canvas = AppColors.surface;
  static const Color line = AppColors.hairline;

  String selectedPage = 'Dashboard';

  final _receiptMedIdController = TextEditingController();
  final _receiptDetailsController = TextEditingController();
  final _quickLookupController = TextEditingController();
  bool _receiptLoading = false;
  String? _receiptFeedback;
  bool _receiptSuccess = false;

  List<Map<String, dynamic>>? _liveUsers;
  bool _loadingUsers = false;
  String _approvalFilter = 'All';
  String? _approvalActionFeedback;
  String? _approvalActionTxHash;

  List<Batch>? _liveBatches;
  bool _loadingBatches = false;

  @override
  void initState() {
    super.initState();
    _fetchLiveUsers();
    _fetchBatches();
  }

  Future<void> _fetchBatches() async {
    setState(() => _loadingBatches = true);
    try {
      final batches = await api.getBatches();
      if (mounted) {
        setState(() {
          _liveBatches = batches;
          _loadingBatches = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  Future<void> _fetchLiveUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final users = await api.getUsers();
      if (mounted) {
        setState(() {
          _liveUsers = users;
          _loadingUsers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  @override
  void dispose() {
    _receiptMedIdController.dispose();
    _receiptDetailsController.dispose();
    _quickLookupController.dispose();
    super.dispose();
  }

  Future<void> _openRegisterOrgDialog() async {
    final targetRole = widget.role == UserRole.distributor
        ? UserRole.pharmacy
        : UserRole.distributor;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OrganizationRegistrationScreen(preselectedRole: targetRole),
      ),
    );
    _fetchLiveUsers();
  }

  void _openRecallDialog(Batch batch) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Recall Batch ${batch.id}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark ${batch.medicine} as recalled on the blockchain.',
              style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Recall Reason',
                hintText: 'e.g. Packaging seal defect in QC',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final res = await api.recallMedicine(
                  medicineId: batch.id,
                  reason: reason,
                  role: widget.role == UserRole.admin
                      ? 'admin'
                      : 'manufacturer',
                );
                _showMessage(res['message'] ?? 'Batch recalled on blockchain');
                _fetchBatches();
              } catch (e) {
                _showMessage('Recall failed: $e');
              }
            },
            child: const Text('Confirm Recall'),
          ),
        ],
      ),
    );
  }

  List<_NavItem> get navItems {
    switch (widget.role) {
      case UserRole.admin:
        return const [
          _NavItem('Dashboard', Icons.grid_view_rounded),
          _NavItem('Organization approvals', Icons.verified_user_outlined),
          _NavItem('User management', Icons.people_outline),
          _NavItem('Medicine records', Icons.medication_outlined),
          _NavItem('Activity log', Icons.history_rounded),
          _NavItem('Settings', Icons.settings_outlined),
        ];
      case UserRole.manufacturer:
        return const [
          _NavItem('Dashboard', Icons.grid_view_rounded),
          _NavItem('Register medicine', Icons.add_box_outlined),
          _NavItem('Medicine batches', Icons.inventory_2_outlined),
          _NavItem('Distributors', Icons.local_shipping_outlined),
          _NavItem('Activity log', Icons.history_rounded),
          _NavItem('Settings', Icons.settings_outlined),
        ];
      case UserRole.distributor:
        return const [
          _NavItem('Dashboard', Icons.grid_view_rounded),
          _NavItem('Verify medicine', Icons.fact_check_outlined),
          _NavItem('Incoming batches', Icons.move_to_inbox_outlined),
          _NavItem('Record receipt', Icons.receipt_long_outlined),
          _NavItem('Partner approvals', Icons.verified_user_outlined),
          _NavItem('Shipments', Icons.local_shipping_outlined),
          _NavItem('Activity log', Icons.history_rounded),
        ];
      case UserRole.pharmacy:
        return const [
          _NavItem('Dashboard', Icons.grid_view_rounded),
          _NavItem('Verify medicine', Icons.fact_check_outlined),
          _NavItem('Incoming stock', Icons.inventory_2_outlined),
          _NavItem('Record receipt', Icons.receipt_long_outlined),
          _NavItem('Medicine lookup', Icons.search_rounded),
          _NavItem('Activity log', Icons.history_rounded),
        ];
      case UserRole.consumer:
        return const [
          _NavItem('Dashboard', Icons.grid_view_rounded),
          _NavItem('Scan QR code', Icons.qr_code_scanner_rounded),
          _NavItem('Verify medicine', Icons.verified_outlined),
          _NavItem('Medicine lookup', Icons.search_rounded),
          _NavItem('Settings', Icons.settings_outlined),
        ];
    }
  }

  void openExistingScreen(String page) {
    if (page == 'Register medicine') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const RegisterBatchScreen()))
          .then((_) => _fetchBatches());
      return;
    }

    if (page == 'Medicine lookup') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MedicineLookupScreen()));
      return;
    }

    if (page == 'Verify medicine' || page == 'Scan QR code') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const HomeScreen()));
      return;
    }

    setState(() => selectedPage = page);
  }

  Future<void> switchRole() async {
    await api.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ContinueChoiceScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;

        return Scaffold(
          backgroundColor: canvas,
          drawer: compact
              ? Drawer(
                  backgroundColor: AppColors.white,
                  child: SafeArea(child: _buildSidebar()),
                )
              : null,
          body: SafeArea(
            child: Row(
              children: [
                if (!compact) SizedBox(width: 256, child: _buildSidebar()),
                Expanded(
                  child: Column(
                    children: [
                      _buildTopBar(compact),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(compact ? 18 : 30),
                          child: selectedPage == 'Dashboard'
                              ? _buildDashboard()
                              : _buildSection(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(right: BorderSide(color: line)),
      ),
      child: Material(
        color: AppColors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 18, 26),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.softMint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: AppColors.primaryTeal,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'PharmaTrace',
                      style: TextStyle(
                        color: AppColors.deepTeal,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [for (final item in navItems) _buildNavTile(item)],
              ),
            ),
            Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warmIvory,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 17,
                    backgroundColor: AppColors.softMint,
                    child: Icon(
                      Icons.person_outline,
                      color: AppColors.deepTeal,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (api.currentUser?['org_name'] ?? widget.role.title)
                              .toString(),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.deepTeal,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.role == UserRole.consumer
                              ? 'Public Access'
                              : widget.role == UserRole.admin
                              ? 'Platform Administrator'
                              : widget.role.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Exit / Switch Role',
                    onPressed: switchRole,
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: AppColors.secondaryText,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile(_NavItem item) {
    final active = selectedPage == item.label;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: active,
        selectedTileColor: AppColors.softMint,
        leading: Icon(
          item.icon,
          color: active ? AppColors.primaryTeal : AppColors.secondaryText,
          size: 20,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: active ? AppColors.deepTeal : AppColors.secondaryText,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
        onTap: () => openExistingScreen(item.label),
      ),
    );
  }

  Widget _buildTopBar(bool compact) {
    return Container(
      height: 70,
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 30),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          if (compact)
            Builder(
              builder: (context) => IconButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
            ),
          Expanded(
            child: Text(
              selectedPage,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.mintSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.circle, color: teal, size: 7),
                const SizedBox(width: 6),
                Text(
                  widget.role == UserRole.consumer
                      ? 'Public Access'
                      : widget.role == UserRole.admin
                      ? 'Restricted Admin Portal'
                      : 'On-Chain Session',
                  style: const TextStyle(
                    color: ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Switch role',
            onPressed: switchRole,
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.deepTeal, AppColors.primaryTeal],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _welcomeTitle(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.role.description,
                style: const TextStyle(
                  color: AppColors.softMint,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.white,
                      foregroundColor: AppColors.deepTeal,
                    ),
                    onPressed: () {
                      final destination = widget.role == UserRole.manufacturer
                          ? 'Register medicine'
                          : widget.role == UserRole.consumer
                          ? 'Scan QR code'
                          : widget.role == UserRole.admin
                          ? 'Organization approvals'
                          : 'Record receipt';
                      openExistingScreen(destination);
                    },
                    icon: Icon(
                      widget.role == UserRole.manufacturer
                          ? Icons.add_rounded
                          : widget.role == UserRole.admin
                          ? Icons.verified_user_outlined
                          : Icons.qr_code_scanner_rounded,
                      size: 19,
                    ),
                    label: Text(
                      widget.role == UserRole.manufacturer
                          ? 'Register Batch'
                          : widget.role == UserRole.admin
                          ? 'Review Approvals'
                          : widget.role == UserRole.consumer
                          ? 'Verify a Medicine'
                          : 'Record Receipt',
                    ),
                  ),
                  if (widget.role == UserRole.consumer)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      onPressed: () => openExistingScreen('Medicine lookup'),
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Batch Lookup'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 960
                ? 4
                : constraints.maxWidth >= 540
                ? 2
                : 1;
            final cards = _overviewCards();

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                mainAxisExtent: 136,
              ),
              itemBuilder: (context, index) => _statCard(cards[index]),
            );
          },
        ),
        const SizedBox(height: 24),
        _buildRecentActivity(),
      ],
    );
  }

  String _welcomeTitle() {
    switch (widget.role) {
      case UserRole.admin:
        return 'Network Governance';
      case UserRole.manufacturer:
        return 'Batch Registration & Custody';
      case UserRole.distributor:
        return 'Wholesale Custody & Dispatch';
      case UserRole.pharmacy:
        return 'Retail Stock Verification';
      case UserRole.consumer:
        return 'Verify Your Medicine';
    }
  }

  List<_StatData> _overviewCards() {
    final batchCount = (_liveBatches?.length ?? 0).toString();
    final orgCount =
        (_liveUsers
                    ?.where(
                      (u) =>
                          (u['role_name'] ?? '') != 'Admin' &&
                          u['is_admin'] != true,
                    )
                    .length ??
                0)
            .toString();
    final pendingCount =
        (_liveUsers
                    ?.where(
                      (u) =>
                          u['status_name'] == 'Pending' &&
                          (u['role_name'] ?? '') != 'Admin' &&
                          u['is_admin'] != true,
                    )
                    .length ??
                0)
            .toString();
    final stage1Count = (_liveBatches?.where((b) => b.stage == 1).length ?? 0)
        .toString();
    final stage2Count = (_liveBatches?.where((b) => b.stage == 2).length ?? 0)
        .toString();
    final stage3Count = (_liveBatches?.where((b) => b.stage == 3).length ?? 0)
        .toString();

    switch (widget.role) {
      case UserRole.admin:
        return [
          _StatData('Organizations', orgCount, Icons.business_outlined),
          _StatData('Pending Approvals', pendingCount, Icons.schedule_rounded),
          _StatData('Total Batches', batchCount, Icons.medication_outlined),
          const _StatData('Chain Status', 'Online', Icons.hub_outlined),
        ];
      case UserRole.manufacturer:
        return [
          _StatData(
            'Registered Batches',
            batchCount,
            Icons.inventory_2_outlined,
          ),
          _StatData(
            'At Factory (Stage 1)',
            stage1Count,
            Icons.factory_outlined,
          ),
          _StatData('Pending Partners', pendingCount, Icons.schedule_rounded),
          _StatData(
            'Recalled',
            (_liveBatches?.where((b) => b.recalled).length ?? 0).toString(),
            Icons.report_gmailerrorred_rounded,
          ),
        ];
      case UserRole.distributor:
        return [
          _StatData(
            'Awaiting Receipt',
            stage1Count,
            Icons.move_to_inbox_outlined,
          ),
          _StatData('In Custody', stage2Count, Icons.local_shipping_outlined),
          _StatData('Delivered', stage3Count, Icons.check_circle_outline),
          _StatData('Total Batches', batchCount, Icons.receipt_long_outlined),
        ];
      case UserRole.pharmacy:
        return [
          _StatData('Retail Stock', stage3Count, Icons.inventory_2_outlined),
          _StatData(
            'Incoming Stock',
            stage2Count,
            Icons.move_to_inbox_outlined,
          ),
          _StatData('Total Batches', batchCount, Icons.medication_outlined),
          const _StatData('Verification', 'Ready', Icons.verified_outlined),
        ];
      case UserRole.consumer:
        return [
          _StatData('Pharmacy Verified', stage3Count, Icons.verified_outlined),
          _StatData('Tracked Batches', batchCount, Icons.medication_outlined),
          const _StatData(
            'Optical Check',
            'OCR + AI',
            Icons.camera_alt_outlined,
          ),
          const _StatData('Access', 'Public', Icons.lock_open_rounded),
        ];
    }
  }

  Widget _statCard(_StatData data) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data.label,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(data.icon, color: teal, size: 20),
              ],
            ),
            Text(
              data.value,
              style: const TextStyle(
                color: ink,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    final batches = (_liveBatches ?? []).take(4).toList();

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Batches',
                  style: TextStyle(
                    color: ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextButton(
                  onPressed: _fetchBatches,
                  child: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (batches.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No medicines registered yet.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              )
            else
              for (int i = 0; i < batches.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.mintSoft,
                    child: const Icon(
                      Icons.medication_outlined,
                      color: teal,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    batches[i].medicine,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Batch ${batches[i].id} • ${batches[i].stageName} • Exp ${batches[i].expiry}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MedicineLookupScreen(initialQuery: batches[i].id),
                        ),
                      );
                    },
                    child: const Text('Inspect'),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildSection() {
    final isAdmin = widget.role == UserRole.admin;
    final showApprovals =
        selectedPage == 'Organization approvals' ||
        selectedPage == 'Distributors' ||
        selectedPage == 'Partner approvals';
    final showReceipts = selectedPage == 'Record receipt';
    final showBatches =
        selectedPage == 'Medicine batches' ||
        selectedPage == 'Incoming batches' ||
        selectedPage == 'Incoming stock' ||
        selectedPage == 'Shipments';

    if (showApprovals) return _buildApprovalSection(isAdmin);
    if (showReceipts) return _buildReceiptSection();
    if (showBatches || selectedPage == 'Medicine records') {
      return _buildBatchSection();
    }
    if (selectedPage == 'User management') {
      return _buildUserManagementSection();
    }
    if (selectedPage == 'Activity log') return _buildActivityLogSection();
    if (selectedPage == 'Settings') return _buildSettingsSection();
    return _buildDashboard();
  }

  Widget _buildApprovalSection(bool isAdmin) {
    final title = isAdmin
        ? 'Organization Approvals'
        : 'Partner Approvals (${widget.role.title})';

    final allOrgs = (_liveUsers ?? [])
        .where(
          (u) => (u['role_name'] ?? '') != 'Admin' && u['is_admin'] != true,
        )
        .toList();

    final filteredOrgs = allOrgs.where((u) {
      if (_approvalFilter == 'All') return true;
      return (u['status_name'] ?? 'Pending') == _approvalFilter;
    }).toList();

    return _sectionCard(
      title,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['All', 'Pending', 'Active', 'Rejected'].map((
                  filter,
                ) {
                  final active = _approvalFilter == filter;
                  return ChoiceChip(
                    label: Text(filter),
                    selected: active,
                    selectedColor: AppColors.mintSoft,
                    onSelected: (_) => setState(() => _approvalFilter = filter),
                  );
                }).toList(),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: _fetchLiveUsers,
                  ),
                  TextButton.icon(
                    onPressed: _openRegisterOrgDialog,
                    icon: const Icon(Icons.add_business_outlined, size: 18),
                    label: const Text('New Organization'),
                  ),
                ],
              ),
            ],
          ),
          if (_approvalActionFeedback != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.mintTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _approvalActionTxHash != null &&
                        _approvalActionTxHash!.isNotEmpty
                    ? '$_approvalActionFeedback (Tx: ${_approvalActionTxHash!.substring(0, _approvalActionTxHash!.length > 16 ? 16 : _approvalActionTxHash!.length)}...)'
                    : _approvalActionFeedback!,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: ink,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_loadingUsers)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (filteredOrgs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                allOrgs.isEmpty
                    ? 'No organizations registered yet.'
                    : (_approvalFilter == 'Pending'
                          ? 'No organizations awaiting approval.'
                          : 'No organizations matching "$_approvalFilter".'),
                style: const TextStyle(color: AppColors.muted),
              ),
            )
          else
            ...filteredOrgs.map((u) {
              final statusName = (u['status_name'] ?? 'Pending').toString();
              final isPending = statusName == 'Pending';
              final isActive = statusName == 'Active';
              final isRejected = statusName == 'Rejected';
              final roleName = (u['role_name'] ?? 'Unknown').toString();
              final name = (u['name'] ?? 'Unnamed').toString();
              final addr = (u['address'] ?? '').toString();
              final licenseNo = (u['license_number'] ?? '').toString();
              final loc = (u['location'] ?? '').toString();
              final mfrName = (u['manufacturer_name'] ?? '').toString();
              final distName = (u['distributor_name'] ?? '').toString();

              final adminOk = u['adminOk'] == true;
              final mfrOk = u['mfrOk'] == true;
              final distOk = u['distOk'] == true;

              final canCurrentRoleApprove =
                  isPending &&
                  ((widget.role == UserRole.admin && !adminOk) ||
                      (widget.role == UserRole.manufacturer &&
                          roleName != 'Manufacturer' &&
                          !mfrOk) ||
                      (widget.role == UserRole.distributor &&
                          roleName == 'Pharmacy' &&
                          !distOk));

              final statusColor = isActive
                  ? AppColors.tealDark
                  : isRejected
                  ? AppColors.danger
                  : AppColors.warning;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                  color: ink,
                                ),
                              ),
                              _pill(roleName, AppColors.mintSoft, ink),
                              _pill(
                                statusName,
                                statusColor.withValues(alpha: 0.14),
                                statusColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                                  if (licenseNo.isNotEmpty) 'Lic: $licenseNo',
                                  if (loc.isNotEmpty) loc,
                                  if (mfrName.isNotEmpty) 'Mfr: $mfrName',
                                  if (distName.isNotEmpty) 'Dist: $distName',
                                ].isEmpty
                                ? addr
                                : [
                                    if (licenseNo.isNotEmpty) 'Lic: $licenseNo',
                                    if (loc.isNotEmpty) loc,
                                    if (mfrName.isNotEmpty) 'Mfr: $mfrName',
                                    if (distName.isNotEmpty) 'Dist: $distName',
                                  ].join(' • '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _approvalPill('Admin', adminOk),
                              if (roleName == 'Distributor' ||
                                  roleName == 'Pharmacy')
                                _approvalPill('Manufacturer', mfrOk),
                              if (roleName == 'Pharmacy')
                                _approvalPill('Distributor', distOk),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isPending) ...[
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.tonal(
                            onPressed: canCurrentRoleApprove
                                ? () async {
                                    try {
                                      final res = await api.approveUser(
                                        target: addr,
                                        approverRole: widget.role.name,
                                      );
                                      setState(() {
                                        _approvalActionFeedback = res['message']
                                            ?.toString();
                                        _approvalActionTxHash =
                                            res['transaction_hash']?.toString();
                                      });
                                      _showMessage(
                                        res['message'] ?? 'Approved on-chain',
                                      );
                                      _fetchLiveUsers();
                                    } catch (e) {
                                      _showMessage('Approval failed: $e');
                                    }
                                  }
                                : null,
                            child: Text(
                              canCurrentRoleApprove ? 'Approve' : 'Approved',
                            ),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () async {
                              try {
                                final res = await api.rejectUser(
                                  target: addr,
                                  rejecterRole: widget.role.name,
                                );
                                setState(() {
                                  _approvalActionFeedback = res['message']
                                      ?.toString();
                                  _approvalActionTxHash =
                                      res['transaction_hash']?.toString();
                                });
                                _showMessage(res['message'] ?? 'Rejected');
                                _fetchLiveUsers();
                              } catch (e) {
                                _showMessage('Rejection failed: $e');
                              }
                            },
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _approvalPill(String label, bool approved) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: approved ? AppColors.mintSoft : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: ${approved ? "✓" : "Pending"}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: approved ? teal : const Color(0xFF92400E),
        ),
      ),
    );
  }

  Widget _buildReceiptSection() {
    final isPharmacy = widget.role == UserRole.pharmacy;
    final stageTarget = isPharmacy ? 'Pharmacy Receipt' : 'Distributor Receipt';

    return _sectionCard(
      stageTarget,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_receiptFeedback != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _receiptSuccess
                    ? AppColors.mintTint
                    : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _receiptFeedback!,
                style: TextStyle(
                  color: _receiptSuccess ? teal : AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          TextField(
            controller: _receiptMedIdController,
            decoration: const InputDecoration(
              labelText: 'Medicine or Batch ID',
              hintText: 'Enter registered medicine or batch ID',
              prefixIcon: Icon(Icons.qr_code_rounded),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _receiptDetailsController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Inspection & Storage Notes',
              hintText: isPharmacy
                  ? 'e.g. Sealed packaging intact. Shelf B-4.'
                  : 'e.g. Received at Central Hub. Cold-chain 20C.',
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _receiptLoading
                  ? null
                  : () async {
                      final id = _receiptMedIdController.text.trim();
                      final details = _receiptDetailsController.text.trim();
                      if (id.isEmpty) {
                        _showMessage('Enter a medicine or batch ID.');
                        return;
                      }

                      setState(() {
                        _receiptLoading = true;
                        _receiptFeedback = null;
                      });

                      try {
                        final Map<String, dynamic> res;
                        if (isPharmacy) {
                          res = await api.recordPharmacyReceipt(
                            medicineId: id,
                            details: details.isEmpty
                                ? 'Received at pharmacy'
                                : details,
                          );
                        } else {
                          res = await api.recordDistributorReceipt(
                            medicineId: id,
                            details: details.isEmpty
                                ? 'Received at distributor'
                                : details,
                          );
                        }

                        setState(() {
                          _receiptLoading = false;
                          _receiptSuccess = true;
                          _receiptFeedback =
                              res['message'] ?? 'Receipt recorded on-chain.';
                        });
                        _fetchBatches();
                      } catch (e) {
                        setState(() {
                          _receiptLoading = false;
                          _receiptSuccess = false;
                          _receiptFeedback = e.toString().replaceAll(
                            'Exception: ',
                            '',
                          );
                        });
                      }
                    },
              child: Text(
                _receiptLoading ? 'Recording...' : 'Confirm $stageTarget',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchSection() {
    final isDistributorIncoming = selectedPage == 'Incoming batches';
    final isPharmacyIncoming = selectedPage == 'Incoming stock';

    List<Batch> displayedBatches = _liveBatches ?? [];
    if (isDistributorIncoming) {
      displayedBatches = displayedBatches.where((b) => b.stage == 1).toList();
    } else if (isPharmacyIncoming) {
      displayedBatches = displayedBatches.where((b) => b.stage == 2).toList();
    }

    return _sectionCard(
      selectedPage,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quickLookupController,
                  decoration: const InputDecoration(
                    hintText: 'Search by medicine or batch ID',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MedicineLookupScreen(initialQuery: v.trim()),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MedicineLookupScreen(
                        initialQuery: _quickLookupController.text.trim(),
                      ),
                    ),
                  );
                },
                child: const Text('Lookup'),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _fetchBatches,
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_loadingBatches)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (displayedBatches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No medicines registered yet.',
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            ...displayedBatches.map((batch) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                batch.medicine,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: ink,
                                ),
                              ),
                              _pill(batch.stageName, AppColors.mintSoft, ink),
                              if (batch.recalled)
                                _pill(
                                  'Recalled',
                                  const Color(0xFFFEF2F2),
                                  AppColors.danger,
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Batch ${batch.id} • ${batch.quantity} units • Exp ${batch.expiry}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (isDistributorIncoming ||
                        (widget.role == UserRole.distributor &&
                            batch.stage == 1))
                      FilledButton.tonal(
                        onPressed: () {
                          setState(() {
                            _receiptMedIdController.text = batch.id;
                            selectedPage = 'Record receipt';
                          });
                        },
                        child: const Text('Receive'),
                      )
                    else if (isPharmacyIncoming ||
                        (widget.role == UserRole.pharmacy && batch.stage == 2))
                      FilledButton.tonal(
                        onPressed: () {
                          setState(() {
                            _receiptMedIdController.text = batch.id;
                            selectedPage = 'Record receipt';
                          });
                        },
                        child: const Text('Receive'),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!batch.recalled &&
                              (widget.role == UserRole.manufacturer ||
                                  widget.role == UserRole.admin)) ...[
                            TextButton(
                              onPressed: () => _openRecallDialog(batch),
                              child: const Text(
                                'Recall',
                                style: TextStyle(color: AppColors.danger),
                              ),
                            ),
                          ],
                          OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MedicineLookupScreen(
                                    initialQuery: batch.id,
                                  ),
                                ),
                              );
                            },
                            child: const Text('Timeline'),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildUserManagementSection() => _buildApprovalSection(true);

  Widget _buildActivityLogSection() => _buildRecentActivity();

  Widget _buildSettingsSection() {
    return _sectionCard(
      'Workspace Settings',
      Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.hub_outlined, color: teal),
            title: const Text('Blockchain Node'),
            subtitle: const Text('Hardhat Localnet (127.0.0.1:8545)'),
            trailing: _pill('Connected', AppColors.mintSoft, teal),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout_rounded, color: AppColors.ink),
            title: const Text('Sign Out / Switch Access Path'),
            trailing: OutlinedButton(
              onPressed: switchRole,
              child: const Text('Switch'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, Widget child) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _NavItem {
  final String label;
  final IconData icon;

  const _NavItem(this.label, this.icon);
}

class _StatData {
  final String label;
  final String value;
  final IconData icon;

  const _StatData(this.label, this.value, this.icon);
}
