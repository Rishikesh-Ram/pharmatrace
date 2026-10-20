import 'medicine_lookup_screen.dart';
import 'package:flutter/material.dart';

import '../models/user_role.dart';
import 'home_screen.dart';
import 'register_batch_screen.dart';
import 'role_login_screen.dart';

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
    switch (widget.role) {
      case UserRole.admin:
        return const [
          _StatData('Organizations', '08', Icons.business_outlined),
          _StatData('Pending approvals', '03', Icons.pending_actions),
          _StatData('Medicine records', '24', Icons.medication_outlined),
          _StatData('Recent activities', '12', Icons.history),
        ];
      case UserRole.manufacturer:
        return const [
          _StatData('Registered batches', '12', Icons.inventory_2_outlined),
          _StatData('Distributors', '05', Icons.local_shipping_outlined),
          _StatData('Pending requests', '02', Icons.pending_actions),
          _StatData('Medicine recalls', '00', Icons.report_outlined),
        ];
      case UserRole.distributor:
        return const [
          _StatData('Incoming batches', '06', Icons.move_to_inbox_outlined),
          _StatData('Shipments', '09', Icons.local_shipping_outlined),
          _StatData('Receipts pending', '02', Icons.receipt_long_outlined),
          _StatData('Flagged batches', '01', Icons.flag_outlined),
        ];
      case UserRole.pharmacy:
        return const [
          _StatData('Medicine stock', '18', Icons.inventory_2_outlined),
          _StatData('Incoming batches', '04', Icons.move_to_inbox_outlined),
          _StatData('Receipts pending', '01', Icons.receipt_long_outlined),
          _StatData('Flagged batches', '00', Icons.flag_outlined),
        ];
      case UserRole.consumer:
        return const [
          _StatData('Scan medicine', 'QR', Icons.qr_code_scanner),
          _StatData('Medicine lookup', 'ID', Icons.search_outlined),
          _StatData('Supply history', 'View', Icons.timeline),
          _StatData('Safety information', 'Info', Icons.health_and_safety_outlined),
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
        selectedPage == 'Distributors';
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
    final title = isAdmin ? 'Organization requests' : 'Distributor requests';
    final names = isAdmin
        ? ['Demo Manufacturer', 'Demo Distributor', 'Demo Pharmacy']
        : ['Northside Distribution', 'CityCare Logistics'];

    return _sectionCard(
      title,
      Column(
        children: [
          for (final name in names)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE5F4F1),
                child: Icon(Icons.business_outlined, color: teal),
              ),
              title: Text(name),
              subtitle: const Text('Sample request • Demo status'),
              trailing: OutlinedButton(
                onPressed: () => _showDemoMessage(
                  'Approval actions will be connected later.',
                ),
                child: const Text('Review'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReceiptSection() {
    return _sectionCard(
      'Record a medicine receipt',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This demo form previews the receipt workflow. '
            'It does not save a receipt to the backend or blockchain.',
            style: TextStyle(color: Colors.black54, height: 1.5),
          ),
          const SizedBox(height: 16),
          const _DemoInput(label: 'Medicine / batch ID'),
          const SizedBox(height: 12),
          const _DemoInput(label: 'Quantity received'),
          const SizedBox(height: 12),
          const _DemoInput(label: 'Supplier / dispatched by'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _showDemoMessage(
              'Receipt form preview only. Saving will be implemented later.',
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Preview receipt action'),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchSection() {
    final rows = [
      ['PT-DEMO-001', 'Sample medicine A', 'Demo'],
      ['PT-DEMO-002', 'Sample medicine B', 'Demo'],
      ['PT-DEMO-003', 'Sample medicine C', 'Demo'],
    ];

    return _sectionCard(
      'Medicine records',
      Column(
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'BATCH ID',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'MEDICINE',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                'SOURCE',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          for (final row in rows) ...[
            Row(
              children: [
                Expanded(child: Text(row[0])),
                Expanded(child: Text(row[1])),
                Text(
                  row[2],
                  style: const TextStyle(
                    color: Colors.deepOrange,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
          ],
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'These are sample display rows, not live database records.',
              style: TextStyle(color: Colors.black45, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildUserManagementSection() {
    final users = [
      ['Demo Manufacturer', 'Manufacturer', 'Approved'],
      ['Demo Distributor', 'Distributor', 'Approved'],
      ['Demo Pharmacy', 'Pharmacy', 'Pending'],
      ['Demo Consumer', 'Consumer', 'Active'],
    ];

    return _sectionCard(
      'Registered users',
      Column(
        children: [
          for (final user in users)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE5F4F1),
                child: Icon(Icons.person_outline, color: teal),
              ),
              title: Text(user[0]),
              subtitle: Text(user[1]),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    user[2],
                    style: TextStyle(
                      color: user[2] == 'Pending'
                          ? Colors.deepOrange
                          : teal,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Demo',
                    style: TextStyle(
                      color: Colors.black45,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Sample accounts only. Live user management '
              'will be connected to the backend later.',
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

class _DemoInput extends StatelessWidget {
  final String label;

  const _DemoInput({required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF7FAF9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5ECEB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5ECEB)),
        ),
      ),
    );
  }
}
