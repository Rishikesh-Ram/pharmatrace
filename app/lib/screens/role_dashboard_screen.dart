import 'medicine_lookup_screen.dart';
import 'package:flutter/material.dart';

import '../models/user_role.dart';
import 'home_screen.dart';
import 'register_batch_screen.dart';
import 'role_login_screen.dart';
import '../services/api_service.dart';

class RoleDashboardScreen extends StatefulWidget {
  final UserRole role;

  const RoleDashboardScreen({
    super.key,
    required this.role,
  });

  @override
  State<RoleDashboardScreen> createState() =>
      _RoleDashboardScreenState();
}

class _RoleDashboardScreenState extends State<RoleDashboardScreen> {
  static const Color teal = Color(0xFF008577);
  static const Color ink = Color(0xFF173C38);
  static const Color canvas = Color(0xFFF5F8F8);
  static const Color line = Color(0xFFE5ECEB);

  String selectedPage = 'Dashboard';

  final _receiptMedIdController = TextEditingController();
  final _receiptDetailsController = TextEditingController();
  final _quickLookupController = TextEditingController();
  bool _receiptLoading = false;
  String? _receiptFeedback;
  bool _receiptSuccess = false;

  List<Map<String, dynamic>>? _liveUsers;
  bool _loadingUsers = false;

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

  void _openRegisterOrgDialog() {
    final nameCtrl = TextEditingController();
    String selectedOrgRole = widget.role == UserRole.distributor ? 'pharmacy' : 'distributor';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Register Organization'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Organization Name',
                  hintText: 'e.g. CityCare Logistics',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedOrgRole,
                items: const [
                  DropdownMenuItem(value: 'manufacturer', child: Text('Manufacturer')),
                  DropdownMenuItem(value: 'distributor', child: Text('Distributor')),
                  DropdownMenuItem(value: 'pharmacy', child: Text('Pharmacy')),
                ],
                onChanged: (v) => setDialogState(() => selectedOrgRole = v ?? 'distributor'),
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
                  await api.registerUser(role: selectedOrgRole, name: name);
                  _showDemoMessage('Registration submitted for $name. Awaiting approval.');
                  _fetchLiveUsers();
                } catch (e) {
                  _showDemoMessage('Registration failed: $e');
                }
              },
              child: const Text('Register'),
            ),
          ],
        ),
      ),
    );
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
              'Recalling ${batch.medicine} will permanently mark this batch as recalled on the blockchain and block any further supply-chain receipts or consumer verification.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Recall Reason',
                hintText: 'e.g. Packaging seal defect detected in QC',
                border: OutlineInputBorder(),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final res = await api.recallMedicine(
                  medicineId: batch.id,
                  reason: reason,
                  role: widget.role == UserRole.admin ? 'admin' : 'manufacturer',
                );
                _showDemoMessage(res['message'] ?? 'Batch recalled on blockchain');
                _fetchBatches();
              } catch (e) {
                _showDemoMessage('Recall failed: $e');
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
          _NavItem('Dashboard', Icons.dashboard_outlined),
          _NavItem('Organization approvals', Icons.approval_outlined),
          _NavItem('User management', Icons.people_outline),
          _NavItem('Medicine records', Icons.medication_outlined),
          _NavItem('Activity log', Icons.history),
          _NavItem('Settings', Icons.settings_outlined),
        ];

      case UserRole.manufacturer:
        return const [
          _NavItem('Dashboard', Icons.dashboard_outlined),
          _NavItem('Register medicine', Icons.add_box_outlined),
          _NavItem('Medicine batches', Icons.inventory_2_outlined),
          _NavItem('Distributors', Icons.local_shipping_outlined),
          _NavItem('Activity log', Icons.history),
          _NavItem('Settings', Icons.settings_outlined),
        ];

      case UserRole.distributor:
        return const [
          _NavItem('Dashboard', Icons.dashboard_outlined),
          _NavItem('Verify medicine', Icons.fact_check_outlined),
          _NavItem('Incoming batches', Icons.move_to_inbox_outlined),
          _NavItem('Record receipt', Icons.receipt_long_outlined),
          _NavItem('Partner approvals', Icons.approval_outlined),
          _NavItem('Shipments', Icons.local_shipping_outlined),
          _NavItem('Activity log', Icons.history),
        ];

      case UserRole.pharmacy:
        return const [
          _NavItem('Dashboard', Icons.dashboard_outlined),
          _NavItem('Verify medicine', Icons.fact_check_outlined),
          _NavItem('Incoming stock', Icons.inventory_2_outlined),
          _NavItem('Record receipt', Icons.receipt_long_outlined),
          _NavItem('Medicine lookup', Icons.search_outlined),
          _NavItem('Activity log', Icons.history),
        ];

      case UserRole.consumer:
        return const [
          _NavItem('Dashboard', Icons.dashboard_outlined),
          _NavItem('Scan QR code', Icons.qr_code_scanner),
          _NavItem('Verify medicine', Icons.verified_outlined),
          _NavItem('Medicine lookup', Icons.search_outlined),
          _NavItem('Settings', Icons.settings_outlined),
        ];
    }
  }


void openExistingScreen(String page) {
  debugPrint('NAVIGATION CLICKED: $page');

  if (page == 'Register medicine') {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RegisterBatchScreen(),
      ),
    );
    return;
  }

  if (page == 'Medicine lookup') {
    debugPrint('OPENING DEDICATED MEDICINE LOOKUP');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MedicineLookupScreen(),
      ),
    );
    return;
  }

  if (page == 'Verify medicine' ||
      page == 'Scan QR code') {
    debugPrint('OPENING HOME SCREEN');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const HomeScreen(),
      ),
    );
    return;
  }

  setState(() => selectedPage = page);
}

  void switchRole() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const RoleLoginScreen(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 850;

        return Scaffold(
          backgroundColor: canvas,
          drawer: compact
              ? Drawer(
                  backgroundColor: Colors.white,
                  child: SafeArea(
                    child: _buildSidebar(),
                  ),
                )
              : null,
          body: SafeArea(
            child: Row(
              children: [
                if (!compact)
                  SizedBox(
                    width: 250,
                    child: _buildSidebar(),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      _buildTopBar(compact),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(
                            compact ? 16 : 28,
                          ),
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
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 16, 24),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: teal.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.health_and_safety_outlined,
                    color: teal,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PharmaTrace',
                        style: TextStyle(
                          color: ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'MEDICINE TRUST PLATFORM',
                        style: TextStyle(
                          color: Colors.black45,
                          fontSize: 9,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 12, 12),
            child: Text(
              'WORKSPACE',
              style: TextStyle(
                color: Colors.black45,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final item in navItems)
                  _buildNavTile(item),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: canvas,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: line),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_circle_outlined,
                  color: teal,
                  size: 32,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.role.title,
                        style: const TextStyle(
                          color: ink,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Demo workspace',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Switch role',
                  onPressed: switchRole,
                  icon: const Icon(
                    Icons.logout,
                    size: 19,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile(_NavItem item) {
    final active = selectedPage == item.label;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
        selected: active,
        selectedTileColor: const Color(0xFFE5F4F1),
        leading: Icon(
          item.icon,
          color: active ? teal : Colors.black54,
          size: 21,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: active ? teal : const Color(0xFF455A57),
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
       onTap: () {
  debugPrint('Sidebar tapped: ${item.label}');
  openExistingScreen(item.label);
},
      ),
    );
  }

  Widget _buildTopBar(bool compact) {
    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 28,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: line),
        ),
      ),
      child: Row(
        children: [
          if (compact)
            Builder(
              builder: (context) => IconButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu),
              ),
            ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedPage,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.role.title} workspace',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.circle,
                  color: Color(0xFF2E9D62),
                  size: 8,
                ),
                SizedBox(width: 6),
                Text(
                  'Demo mode',
                  style: TextStyle(
                    color: Color(0xFF27764C),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Switch role',
            onPressed: switchRole,
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final title = _welcomeTitle();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF087F73), Color(0xFF35A99A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.health_and_safety_outlined,
                color: Colors.white,
                size: 34,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 25,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                widget.role.description,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: teal,
                    ),
                    onPressed: () {
                      final destination =
                          widget.role == UserRole.manufacturer
                              ? 'Register medicine'
                              : widget.role == UserRole.consumer
                                  ? 'Scan QR code'
                                  : 'Verify medicine';
                      openExistingScreen(destination);
                    },
                    icon: Icon(
                      widget.role == UserRole.manufacturer
                          ? Icons.add
                          : Icons.qr_code_scanner,
                    ),
                    label: Text(
                      widget.role == UserRole.manufacturer
                          ? 'Register a batch'
                          : widget.role == UserRole.consumer
                              ? 'Scan medicine'
                              : 'Verify medicine',
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                    ),
                    onPressed: () {
                      setState(() {
                        selectedPage = navItems.length > 1
                            ? navItems[1].label
                            : 'Dashboard';
                      });
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Explore workspace'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 27),
        const Text(
          'Workspace overview',
          style: TextStyle(
            color: ink,
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'A quick overview of your PharmaTrace workspace.',
          style: TextStyle(
            color: Colors.black54,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000
                ? 4
                : constraints.maxWidth >= 570
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
                mainAxisExtent: 135,
              ),
              itemBuilder: (context, index) {
                final card = cards[index];
                return _statCard(card);
              },
            );
          },
        ),
        const SizedBox(height: 26),
        _buildRecentActivity(),
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'PharmaTrace • Counterfeit medicine traceability',
            style: TextStyle(
              color: Colors.black45,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  String _welcomeTitle() {
    switch (widget.role) {
      case UserRole.admin:
        return 'Platform administration';
      case UserRole.manufacturer:
        return 'Medicine starts with trust.';
      case UserRole.distributor:
        return 'Your supply chain, at a glance.';
      case UserRole.pharmacy:
        return 'Safer stock. Trusted medicines.';
      case UserRole.consumer:
        return 'Know your medicine.';
    }
  }

  List<_StatData> _overviewCards() {
    final batchCount = (_liveBatches?.length ?? 0).toString().padLeft(2, '0');
    final userCount = (_liveUsers?.length ?? 0).toString().padLeft(2, '0');
    final pendingCount = (_liveUsers?.where((u) => u['status_name'] == 'Pending').length ?? 0).toString().padLeft(2, '0');
    final distCount = (_liveUsers?.where((u) => u['role_name'] == 'Distributor').length ?? 0).toString().padLeft(2, '0');
    final stage1Count = (_liveBatches?.where((b) => b.stage == 1).length ?? 0).toString().padLeft(2, '0');
    final stage2Count = (_liveBatches?.where((b) => b.stage == 2).length ?? 0).toString().padLeft(2, '0');
    final stage3Count = (_liveBatches?.where((b) => b.stage == 3).length ?? 0).toString().padLeft(2, '0');

    switch (widget.role) {
      case UserRole.admin:
        return [
          _StatData('Organizations', userCount, Icons.business_outlined),
          _StatData('Pending approvals', pendingCount, Icons.pending_actions),
          _StatData('Medicine records', batchCount, Icons.medication_outlined),
          const _StatData('Blockchain node', 'Active', Icons.verified_user_outlined),
        ];
      case UserRole.manufacturer:
        return [
          _StatData('Registered batches', batchCount, Icons.inventory_2_outlined),
          _StatData('Distributors', distCount, Icons.local_shipping_outlined),
          _StatData('Pending requests', pendingCount, Icons.pending_actions),
          _StatData('Medicine recalls', (_liveBatches?.where((b) => b.recalled).length ?? 0).toString().padLeft(2, '0'), Icons.report_outlined),
        ];
      case UserRole.distributor:
        return [
          _StatData('Incoming batches', stage1Count, Icons.move_to_inbox_outlined),
          _StatData('In custody (Stage 2)', stage2Count, Icons.local_shipping_outlined),
          _StatData('Delivered (Stage 3)', stage3Count, Icons.inventory_outlined),
          _StatData('Total batches', batchCount, Icons.receipt_long_outlined),
        ];
      case UserRole.pharmacy:
        return [
          _StatData('Medicine stock (Stage 3)', stage3Count, Icons.inventory_2_outlined),
          _StatData('Incoming stock (Stage 2)', stage2Count, Icons.move_to_inbox_outlined),
          _StatData('Receipts pending', stage2Count, Icons.receipt_long_outlined),
          const _StatData('Flagged batches', '00', Icons.flag_outlined),
        ];
      case UserRole.consumer:
        return [
          const _StatData('Scan medicine', 'QR', Icons.qr_code_scanner),
          const _StatData('Medicine lookup', 'ID', Icons.search_outlined),
          _StatData('Verified batches', stage3Count, Icons.timeline),
          const _StatData('Safety status', 'Active', Icons.health_and_safety_outlined),
        ];
    }
  }

  Widget _statCard(_StatData data) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(17),
      ),
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
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ),
              Icon(
                data.icon,
                color: teal,
                size: 21,
              ),
            ],
          ),
          Text(
            data.value,
            style: const TextStyle(
              color: ink,
              fontSize: 27,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity() {
    final entries = _activityEntries();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent activity',
            style: TextStyle(
              color: ink,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Sample entries for the interface preview.',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: line),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE5F4F1),
                child: Icon(entries[i].icon, color: teal, size: 20),
              ),
              title: Text(
                entries[i].title,
                style: const TextStyle(
                  color: ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  entries[i].subtitle,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              trailing: const Text(
                'Demo',
                style: TextStyle(
                  color: Colors.black45,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<_ActivityData> _activityEntries() {
    switch (widget.role) {
      case UserRole.admin:
        return const [
          _ActivityData('Organization awaiting approval',
              'A sample organization request', Icons.business_outlined),
          _ActivityData('Medicine record created',
              'Sample record for dashboard preview', Icons.medication_outlined),
          _ActivityData('Account review',
              'Sample access review entry', Icons.people_outline),
        ];
      case UserRole.manufacturer:
        return const [
          _ActivityData('Medicine batch registered',
              'Sample batch activity', Icons.add_box_outlined),
          _ActivityData('Distributor request received',
              'Sample distributor activity', Icons.local_shipping_outlined),
          _ActivityData('Packaging details reviewed',
              'Sample quality-control activity', Icons.fact_check_outlined),
        ];
      case UserRole.distributor:
        return const [
          _ActivityData('Incoming batch listed',
              'Sample manufacturer delivery', Icons.move_to_inbox_outlined),
          _ActivityData('Receipt awaiting entry',
              'Sample receiving activity', Icons.receipt_long_outlined),
          _ActivityData('Shipment prepared',
              'Sample outgoing shipment', Icons.local_shipping_outlined),
        ];
      case UserRole.pharmacy:
        return const [
          _ActivityData('Incoming stock listed',
              'Sample distributor delivery', Icons.inventory_2_outlined),
          _ActivityData('Receipt awaiting entry',
              'Sample pharmacy receiving activity', Icons.receipt_long_outlined),
          _ActivityData('Medicine lookup',
              'Sample lookup activity', Icons.search_outlined),
        ];
      case UserRole.consumer:
        return const [
          _ActivityData('Ready to scan',
              'Scan a medicine QR code to begin', Icons.qr_code_scanner),
          _ActivityData('Medicine lookup available',
              'Search using a medicine ID', Icons.search_outlined),
          _ActivityData('Supply-chain history',
              'View history when a record is available', Icons.timeline),
        ];
    }
  }

  Widget _buildSection() {
    final isAdmin = widget.role == UserRole.admin;

    final description = switch (selectedPage) {
      'Organization approvals' =>
        'Review organization requests and approval status.',
      'User management' =>
        'View workspace accounts and access status.',
      'Medicine batches' =>
        'Browse registered medicine batches.',
      'Distributors' =>
        'Review distributor relationships and requests.',
      'Incoming batches' =>
        'Review medicine batches received from upstream partners.',
      'Incoming stock' =>
        'Review medicine stock received by the pharmacy.',
      'Record receipt' =>
        'Enter receipt details for a received batch.',
      'Shipments' =>
        'Review outgoing medicine shipments.',
      'Activity log' =>
        'Review recent workspace activity.',
      'Settings' =>
        'Workspace preferences and account options.',
      _ => 'Manage ${selectedPage.toLowerCase()} in your workspace.',
    };

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          selectedPage,
          style: const TextStyle(
            color: ink,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 22),
        if (showApprovals)
  _buildApprovalSection(isAdmin)
else if (showReceipts)
  _buildReceiptSection()
else if (showBatches || selectedPage == 'Medicine records')
  _buildBatchSection()
else if (selectedPage == 'User management')
  _buildUserManagementSection()
else if (selectedPage == 'Activity log')
  _buildActivityLogSection()
else if (selectedPage == 'Settings')
  _buildSettingsSection()
else
  _buildGenericSection(),
      ],
    );
  }

  Widget _buildApprovalSection(bool isAdmin) {
    final title = isAdmin ? 'Organization Approvals' : 'Partner Approvals';

    return _sectionCard(
      title,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Live Blockchain Registry',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Refresh',
                    onPressed: _fetchLiveUsers,
                  ),
                  TextButton.icon(
                    onPressed: _openRegisterOrgDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Register New Org'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingUsers)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_liveUsers == null || _liveUsers!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No registered organizations found on the blockchain.'),
            )
          else
            ..._liveUsers!.map((u) {
              final isPending = u['status_name'] == 'Pending';
              final isActive = u['status_name'] == 'Active';
              final roleName = u['role_name'] ?? 'Unknown';
              final name = u['name'] ?? 'Unnamed';
              final addr = u['address'] ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: isActive ? Colors.green.shade50 : Colors.orange.shade50,
                      child: Icon(
                        roleName == 'Manufacturer'
                            ? Icons.factory_outlined
                            : roleName == 'Distributor'
                                ? Icons.local_shipping_outlined
                                : Icons.local_pharmacy_outlined,
                        color: isActive ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isActive ? Colors.green.shade50 : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  u['status_name'] ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isActive ? Colors.green.shade800 : Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$roleName • $addr',
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (roleName != 'Admin') ...[
                            const SizedBox(height: 3),
                            Text(
                              roleName == 'Manufacturer'
                                  ? 'Approvals: Admin ${u["adminOk"] == true ? "✓" : "Pending"}'
                                  : roleName == 'Distributor'
                                      ? 'Approvals: Admin ${u["adminOk"] == true ? "✓" : "Pending"} • Manufacturer ${u["mfrOk"] == true ? "✓" : "Pending"}'
                                      : 'Approvals: Admin ${u["adminOk"] == true ? "✓" : "Pending"} • Mfr ${u["mfrOk"] == true ? "✓" : "Pending"} • Dist ${u["distOk"] == true ? "✓" : "Pending"}',
                              style: const TextStyle(fontSize: 11, color: teal, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isPending)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.tonal(
                            onPressed: () async {
                              try {
                                final res = await api.approveUser(
                                  target: addr,
                                  approverRole: widget.role.name,
                                );
                                _showDemoMessage(res['message'] ?? 'Approved successfully');
                                _fetchLiveUsers();
                              } catch (e) {
                                _showDemoMessage('Approval failed: $e');
                              }
                            },
                            child: const Text('Approve'),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () async {
                              try {
                                final res = await api.rejectUser(
                                  target: addr,
                                  rejecterRole: widget.role.name,
                                );
                                _showDemoMessage(res['message'] ?? 'Rejected');
                                _fetchLiveUsers();
                              } catch (e) {
                                _showDemoMessage('Rejection failed: $e');
                              }
                            },
                            child: const Text('Reject'),
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

  Widget _buildReceiptSection() {
    final isPharmacy = widget.role == UserRole.pharmacy;
    final stageTarget = isPharmacy ? 'Pharmacy (Stage 3)' : 'Distributor (Stage 2)';

    return _sectionCard(
      'Record Medicine Receipt — $stageTarget',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Confirm receipt of medicine batch and append immutable receipt details to the blockchain supply-chain timeline.',
            style: TextStyle(color: Colors.black54, height: 1.5),
          ),
          const SizedBox(height: 18),
          if (_receiptFeedback != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _receiptSuccess ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _receiptSuccess ? Colors.green.shade300 : Colors.red.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _receiptSuccess ? Icons.check_circle : Icons.error_outline,
                    color: _receiptSuccess ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _receiptFeedback!,
                      style: TextStyle(
                        color: _receiptSuccess ? Colors.green.shade900 : Colors.red.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _receiptMedIdController,
            decoration: const InputDecoration(
              labelText: 'Medicine ID or Batch Number',
              hintText: 'e.g. PT-TEST-002 or BATCH-DEMO-001',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.qr_code),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _receiptDetailsController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Receipt & Inspection Notes',
              hintText: isPharmacy
                  ? 'e.g. Stock received from distributor. Sealed packaging intact. Shelf location A-4.'
                  : 'e.g. Batch received from manufacturer at Central Hub. Storage temp 20C.',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.notes),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _receiptLoading
                  ? null
                  : () async {
                      final id = _receiptMedIdController.text.trim();
                      final details = _receiptDetailsController.text.trim();
                      if (id.isEmpty) {
                        _showDemoMessage('Please enter a medicine or batch ID');
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
                            details: details.isEmpty ? 'Received at pharmacy' : details,
                          );
                        } else {
                          res = await api.recordDistributorReceipt(
                            medicineId: id,
                            details: details.isEmpty ? 'Received at distributor' : details,
                          );
                        }

                        setState(() {
                          _receiptLoading = false;
                          _receiptSuccess = true;
                          _receiptFeedback = res['message'] ?? 'Receipt successfully recorded on blockchain!';
                        });
                        _fetchBatches();
                      } catch (e) {
                        setState(() {
                          _receiptLoading = false;
                          _receiptSuccess = false;
                          _receiptFeedback = e.toString().replaceAll('Exception: ', '');
                        });
                      }
                    },
              icon: _receiptLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.verified),
              label: Text(
                _receiptLoading
                    ? 'Recording on blockchain...'
                    : isPharmacy
                        ? 'Confirm Pharmacy Receipt (Stage 3)'
                        : 'Confirm Distributor Receipt (Stage 2)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchSection() {
    final title = switch (selectedPage) {
      'Incoming batches' => 'Incoming Batches from Manufacturers (Stage 1)',
      'Incoming stock' => 'Incoming Stock from Distributors (Stage 2)',
      'Medicine records' => 'All Blockchain Medicine Records',
      'Shipments' => 'Supply Chain Transfers & Shipments',
      _ => 'Registered Medicine Batches',
    };

    final isDistributorIncoming = selectedPage == 'Incoming batches';
    final isPharmacyIncoming = selectedPage == 'Incoming stock';

    List<Batch> displayedBatches = _liveBatches ?? [];
    if (isDistributorIncoming) {
      displayedBatches = displayedBatches.where((b) => b.stage == 1).toList();
    } else if (isPharmacyIncoming) {
      displayedBatches = displayedBatches.where((b) => b.stage == 2).toList();
    }

    return _sectionCard(
      title,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quickLookupController,
                  decoration: const InputDecoration(
                    hintText: 'Lookup batch ID (e.g. PT-TEST-002)',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MedicineLookupScreen(initialQuery: v.trim()),
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
                child: const Text('Search'),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh batches',
                onPressed: _fetchBatches,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loadingBatches)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (displayedBatches.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: teal, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isDistributorIncoming
                          ? 'No batches currently at Stage 1 waiting for distributor receipt. Register new batches from the Manufacturer workspace.'
                          : isPharmacyIncoming
                              ? 'No batches currently at Stage 2 waiting for pharmacy receipt. Record distributor receipt first.'
                              : 'No medicine batches found on the blockchain.',
                      style: const TextStyle(fontSize: 13, color: ink, height: 1.4),
                    ),
                  ),
                ],
              ),
            )
          else
            ...displayedBatches.map((batch) {
              final stageColor = switch (batch.stage) {
                1 => Colors.blue,
                2 => Colors.orange,
                3 => Colors.green,
                _ => Colors.grey,
              };

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: stageColor.withValues(alpha: 0.12),
                      child: Icon(Icons.medication, color: stageColor),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                batch.medicine,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: stageColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Stage ${batch.stage}: ${batch.stageName}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: stageColor,
                                  ),
                                ),
                              ),
                              if (batch.recalled) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'RECALLED',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ID: ${batch.id}  •  Qty: ${batch.quantity}  •  Exp: ${batch.expiry}',
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Mfr: ${batch.manufacturer}',
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      children: [
                        if (isDistributorIncoming || (widget.role == UserRole.distributor && batch.stage == 1))
                          FilledButton.tonal(
                            onPressed: () {
                              setState(() {
                                _receiptMedIdController.text = batch.id;
                                selectedPage = 'Record receipt';
                              });
                            },
                            child: const Text('Receive Batch'),
                          )
                        else if (isPharmacyIncoming || (widget.role == UserRole.pharmacy && batch.stage == 2))
                          FilledButton.tonal(
                            onPressed: () {
                              setState(() {
                                _receiptMedIdController.text = batch.id;
                                selectedPage = 'Record receipt';
                              });
                            },
                            child: const Text('Receive Stock'),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!batch.recalled &&
                                  (widget.role == UserRole.manufacturer ||
                                      widget.role == UserRole.admin)) ...[
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                    side: BorderSide(color: Colors.red.shade300),
                                  ),
                                  onPressed: () => _openRecallDialog(batch),
                                  child: const Text('Recall'),
                                ),
                                const SizedBox(width: 8),
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
                                child: const Text('View Details'),
                              ),
                            ],
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

  Widget _buildUserManagementSection() {
    return _sectionCard(
      'Registered Organization Users',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Live On-Chain Organization Accounts',
                style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Refresh',
                    onPressed: _fetchLiveUsers,
                  ),
                  TextButton.icon(
                    onPressed: _openRegisterOrgDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Register New Org'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingUsers)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_liveUsers == null || _liveUsers!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No registered organization accounts found on blockchain.'),
            )
          else
            ..._liveUsers!.map((u) {
              final isActive = u['status_name'] == 'Active';
              final isPending = u['status_name'] == 'Pending';
              final roleName = u['role_name'] ?? 'Unknown';
              final name = u['name'] ?? 'Unnamed';
              final addr = u['address'] ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: isActive ? Colors.green.shade50 : Colors.orange.shade50,
                      child: Icon(
                        roleName == 'Manufacturer'
                            ? Icons.factory_outlined
                            : roleName == 'Distributor'
                                ? Icons.local_shipping_outlined
                                : roleName == 'Pharmacy'
                                    ? Icons.local_pharmacy_outlined
                                    : Icons.admin_panel_settings_outlined,
                        color: isActive ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isActive ? Colors.green.shade50 : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  u['status_name'] ?? 'Active',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isActive ? Colors.green.shade800 : Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$roleName • $addr',
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (isPending && widget.role == UserRole.admin)
                      FilledButton.tonal(
                        onPressed: () async {
                          try {
                            final res = await api.approveUser(
                              target: addr,
                              approverRole: 'admin',
                            );
                            _showDemoMessage(res['message'] ?? 'Approved');
                            _fetchLiveUsers();
                          } catch (e) {
                            _showDemoMessage('Approval failed: $e');
                          }
                        },
                        child: const Text('Approve'),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildActivityLogSection() {
    final activities = [
      [
        Icons.verified_outlined,
        'Medicine verification requested',
        'PT-DEMO-001 • Demo event',
      ],
      [
        Icons.business_outlined,
        'Organization registration submitted',
        'Demo Pharmacy • Demo event',
      ],
      [
        Icons.inventory_2_outlined,
        'Medicine batch registered',
        'PT-DEMO-002 • Demo event',
      ],
      [
        Icons.qr_code_scanner,
        'QR code scanned',
        'PT-DEMO-003 • Demo event',
      ],
    ];

    return _sectionCard(
      'Recent activity',
      Column(
        children: [
          for (final activity in activities)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE5F4F1),
                child: Icon(
                  activity[0] as IconData,
                  color: teal,
                ),
              ),
              title: Text(activity[1] as String),
              subtitle: Text(activity[2] as String),
              trailing: const Icon(
                Icons.history,
                color: Colors.black38,
              ),
            ),
          const Divider(),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Illustrative events only. These are not live '
              'blockchain transactions or audit records.',
              style: TextStyle(
                color: Colors.black45,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Column(
      children: [
        _sectionCard(
          'Application preferences',
          Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.notifications_outlined,
                  color: teal,
                ),
                title: const Text('Notifications'),
                subtitle: const Text(
                  'Manage organization and verification alerts.',
                ),
                trailing: OutlinedButton(
                  onPressed: () => _showDemoMessage(
                    'Notification preferences are a UI preview.',
                  ),
                  child: const Text('Configure'),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.security_outlined,
                  color: teal,
                ),
                title: const Text('Security'),
                subtitle: const Text(
                  'Authentication and access-control settings.',
                ),
                trailing: OutlinedButton(
                  onPressed: () => _showDemoMessage(
                    'Security settings will be connected later.',
                  ),
                  child: const Text('View'),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.hub_outlined,
                  color: teal,
                ),
                title: const Text('Blockchain connection'),
                subtitle: const Text(
                  'View network and contract configuration.',
                ),
                trailing: OutlinedButton(
                  onPressed: () => _showDemoMessage(
                    'Live blockchain status will be added later.',
                  ),
                  child: const Text('View'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _sectionCard(
          'About PharmaTrace',
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PharmaTrace',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: ink,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Medicine authenticity verification and '
                'supply-chain traceability.',
                style: TextStyle(
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Development demo • Version 1.0',
                style: TextStyle(
                  color: Colors.black45,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  
Widget _buildGenericSection() {
    return _sectionCard(
      'Workspace tools',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This section is part of the application structure. '
            'Its real data and actions can be connected in a later step.',
            style: TextStyle(color: Colors.black54, height: 1.5),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => selectedPage = 'Dashboard'),
                icon: const Icon(Icons.dashboard_outlined),
                label: const Text('Back to dashboard'),
              ),
              if (widget.role == UserRole.consumer ||
                  widget.role == UserRole.distributor ||
                  widget.role == UserRole.pharmacy ||
                  widget.role == UserRole.admin)
                FilledButton.icon(
                  onPressed: () => openExistingScreen('Verify medicine'),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Open verification'),
                ),
              if (widget.role == UserRole.manufacturer)
                FilledButton.icon(
                  onPressed: () => openExistingScreen('Register medicine'),
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Register medicine'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: ink,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  void _showDemoMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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

class _ActivityData {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ActivityData(this.title, this.subtitle, this.icon);
}
