import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/notifier.dart';
import '../widgets/notification_bell_widget.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final Logger _logger = Logger();
  bool _isLoading = true;

  // Today's Orders Stats
  int _todayTotal = 0;
  int _todayDelivered = 0;
  int _todayPending = 0;
  int _todayCancelled = 0;

  // All Orders Stats
  int _allTotal = 0;
  int _allDelivered = 0;
  int _allPending = 0;
  int _allCancelled = 0;

  // Today's Visitors Stats
  int _activeUsers = 0;
  int _todayLogins = 0;

  // Recent Activity
  List<dynamic> _recentOrdersList = [];
  List<dynamic> _recentUsersList = [];
  List<dynamic> _recentStoresList = [];
  String _selectedActivityType = 'orders';

  List<Map<String, dynamic>> _storeBalanceRows = [];
  List<Map<String, dynamic>> _storeFilterOptions = [];
  int? _selectedStoreFilterId;
  String _selectedStoreTab = 'all';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      // Fetch Orders, Visitor Stats, Recent Activity, and Store Balance context in parallel
      final results = await Future.wait([
        ApiService.getOrders(token),
        ApiService.getVisitorStats(token),
        ApiService.getRecentActivity(token),
        ApiService.getStoresForAdmin(token),
        ApiService.getStoreSalesReport(token),
        ApiService.getStoreOrderBreakdown(token),
      ]);

      final orders = results[0] as List<dynamic>;
      final visitorStats = results[1] as Map<String, dynamic>;
      final recentActivityData = results[2] as Map<String, dynamic>;
      final stores = results[3] as List<dynamic>;
      final storeSalesReport = results[4] as Map<String, dynamic>;
      final storeSales = (storeSalesReport['store_sales'] as List?) ?? [];
      final storeOrders =
          (results[5] as Map<String, dynamic>)['store_orders'] as List? ?? [];

      // Wallet endpoint can be permission-gated; keep dashboard resilient.
      Map<String, dynamic> walletsResponse = {};
      try {
        walletsResponse = await ApiService.getAdminWallets(token, limit: 1000);
      } catch (e) {
        _logger.w('Admin wallets fetch skipped: $e');
      }
      final wallets = (walletsResponse['wallets'] as List?) ?? [];

      final now = DateTime.now();
      final todayOrders = orders.where((o) {
        try {
          final dt = DateTime.parse(o['created_at'].toString());
          return dt.year == now.year &&
              dt.month == now.month &&
              dt.day == now.day;
        } catch (e) {
          return false;
        }
      }).toList();

      int countStatus(List list, String status) {
        return list
            .where(
              (o) => (o['status'] ?? '').toString().toLowerCase() == status,
            )
            .length;
      }

      int countPendingLike(List list) {
        return list.where((o) {
          final s = (o['status'] ?? '').toString().toLowerCase();
          return s != 'delivered' && s != 'cancelled';
        }).length;
      }

      final Map<int, double> storeWalletBalances = {};
      for (final w in wallets) {
        final sidRaw = w['store_id'];
        if (sidRaw == null) continue;
        final sid = int.tryParse(sidRaw.toString());
        if (sid == null) continue;
        final bal = double.tryParse(w['balance']?.toString() ?? '0') ?? 0;
        storeWalletBalances[sid] = bal;
      }

      final Map<int, String> storeNameLookup = {};
      final Map<int, Map<String, dynamic>> storeSummaryMap = {};
      for (final s in stores) {
        final sid = int.tryParse(s['id']?.toString() ?? '');
        if (sid == null) continue;
        final name = (s['name'] ?? 'Store #$sid').toString();
        storeNameLookup[sid] = name;
        storeSummaryMap[sid] = {
          'store_id': sid,
          'store_name': name,
          'total_orders': 0,
          'served_orders': 0,
          'pending_orders': 0,
          'cancelled_orders': 0,
          'gross_sales': 0.0,
          'served_sales': 0.0,
          'pending_sales': 0.0,
          'wallet_balance': storeWalletBalances[sid] ?? 0.0,
          'orders': <Map<String, dynamic>>[],
        };
      }

      for (final o in storeOrders) {
        final sid = int.tryParse(o['store_id']?.toString() ?? '');
        if (sid == null) continue;
        final summary = storeSummaryMap.putIfAbsent(sid, () {
          final name =
              storeNameLookup[sid] ?? (o['store_name'] ?? 'Store #$sid');
          return {
            'store_id': sid,
            'store_name': name.toString(),
            'total_orders': 0,
            'served_orders': 0,
            'pending_orders': 0,
            'cancelled_orders': 0,
            'gross_sales': 0.0,
            'served_sales': 0.0,
            'pending_sales': 0.0,
            'wallet_balance': storeWalletBalances[sid] ?? 0.0,
            'orders': <Map<String, dynamic>>[],
          };
        });

        final status = (o['status'] ?? '').toString().toLowerCase();
        final amount =
            double.tryParse(o['store_order_amount']?.toString() ?? '0') ?? 0;
        summary['total_orders'] = (summary['total_orders'] as int) + 1;
        summary['gross_sales'] = (summary['gross_sales'] as double) + amount;

        if (status == 'delivered') {
          summary['served_orders'] = (summary['served_orders'] as int) + 1;
          summary['served_sales'] = (summary['served_sales'] as double) + amount;
        } else if (status == 'cancelled') {
          summary['cancelled_orders'] = (summary['cancelled_orders'] as int) + 1;
        } else {
          summary['pending_orders'] = (summary['pending_orders'] as int) + 1;
          summary['pending_sales'] = (summary['pending_sales'] as double) + amount;
        }

        final parsedDate =
            DateTime.tryParse(o['created_at']?.toString() ?? '') ?? DateTime(1970);
        (summary['orders'] as List<Map<String, dynamic>>).add({
          'id': o['order_id'],
          'order_number': o['order_number'],
          'status': status,
          'amount': amount,
          'created_at': parsedDate,
        });
      }

      for (final ss in storeSales) {
        final sid = int.tryParse(ss['store_id']?.toString() ?? '');
        if (sid == null || !storeSummaryMap.containsKey(sid)) continue;
        final summary = storeSummaryMap[sid]!;
        final totalSales =
            double.tryParse(ss['total_sales']?.toString() ?? '0') ?? 0;
        final avgOrder =
            double.tryParse(ss['average_order_value']?.toString() ?? '0') ?? 0;
        summary['gross_sales'] =
            totalSales > 0 ? totalSales : summary['gross_sales'];
        summary['average_order_value'] = avgOrder;
        summary['unique_customers'] =
            int.tryParse(ss['unique_customers']?.toString() ?? '0') ?? 0;
      }

      final storeBalanceRows = storeSummaryMap.values.toList();
      storeBalanceRows.sort((a, b) {
        final ba = (a['wallet_balance'] as double?) ?? 0.0;
        final bb = (b['wallet_balance'] as double?) ?? 0.0;
        return bb.compareTo(ba);
      });
      for (final row in storeBalanceRows) {
        final list = row['orders'] as List<Map<String, dynamic>>;
        list.sort((a, b) {
          final da = a['created_at'] as DateTime;
          final db = b['created_at'] as DateTime;
          return db.compareTo(da);
        });
      }

      final storeFilterOptions = storeNameLookup.entries
          .map((e) => {
                'store_id': e.key,
                'store_name': e.value,
              })
          .toList()
        ..sort((a, b) =>
            a['store_name'].toString().compareTo(b['store_name'].toString()));

      setState(() {
        // Today
        _todayTotal = todayOrders.length;
        _todayDelivered = countStatus(todayOrders, 'delivered');
        _todayPending = countPendingLike(todayOrders);
        _todayCancelled = countStatus(todayOrders, 'cancelled');

        // All
        _allTotal = orders.length;
        _allDelivered = countStatus(orders, 'delivered');
        _allPending = countPendingLike(orders);
        _allCancelled = countStatus(orders, 'cancelled');

        // Visitors
        _activeUsers = visitorStats['active_users'] ?? 0;
        _todayLogins = visitorStats['today_logins'] ?? 0;

        // Recent Activity
        _recentOrdersList = recentActivityData['recent_orders'] ?? [];
        _recentUsersList = recentActivityData['recent_users'] ?? [];
        _recentStoresList = recentActivityData['recent_stores'] ?? [];
        _storeBalanceRows = storeBalanceRows;
        _storeFilterOptions = storeFilterOptions;
        if (!_storeFilterOptions
            .any((o) => o['store_id'] == _selectedStoreFilterId)) {
          _selectedStoreFilterId = null;
        }

        _isLoading = false;
      });
    } catch (e) {
      _logger.e('Error loading stats: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        actions: [
          const NotificationBellWidget(),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              backgroundColor: Colors.indigo,
              child: Text(
                authProvider.user?.firstName.substring(0, 1).toUpperCase() ??
                    'A',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(context, authProvider),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dashboard Overview',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Today's Orders Section
                    const Text(
                      "Today's Orders",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildStatGrid(
                      total: _todayTotal,
                      delivered: _todayDelivered,
                      pending: _todayPending,
                      cancelled: _todayCancelled,
                    ),

                    const SizedBox(height: 4),

                    // All Orders Section
                    const Text(
                      "All Orders",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildStatGrid(
                      total: _allTotal,
                      delivered: _allDelivered,
                      pending: _allPending,
                      cancelled: _allCancelled,
                    ),

                    const SizedBox(height: 4),

                    // Today's Visitors Section (Mocked for now as per request)
                    const Text(
                      "Today's Visitors",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildVisitorsGrid(),

                    const SizedBox(height: 20),
                    _buildStoreBalancesSection(),

                    const SizedBox(height: 24),
                    const Text(
                      'Recent Activity',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildActivityFilter(),
                    const SizedBox(height: 16),
                    _buildRecentActivityList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDrawer(BuildContext context, AuthProvider authProvider) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo, Colors.blueAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            accountName: Text(
              '${authProvider.user?.firstName} ${authProvider.user?.lastName}',
            ),
            accountEmail: Text(authProvider.user?.email ?? ''),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                authProvider.user?.firstName.substring(0, 1).toUpperCase() ??
                    'A',
                style: const TextStyle(fontSize: 24, color: Colors.indigo),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            selected: true,
            onTap: () {
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.store),
            title: const Text('Manage Stores'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/manage-stores');
            },
          ),
          ListTile(
            leading: const Icon(Icons.shopping_bag),
            title: const Text('Manage Products'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/manage-products');
            },
          ),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Manage Users'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/manage-users');
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: const Text('Wallet'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/wallet');
            },
          ),
          ListTile(
            leading: const Icon(Icons.delivery_dining),
            title: const Text('Riders'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/manage-riders');
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory),
            title: const Text('Inventory Report'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/inventory-report');
            },
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Change Password'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/change-password');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () {
              authProvider.logout();
              Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatGrid({
    required int total,
    required int delivered,
    required int pending,
    required int cancelled,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Total Orders',
                value: total.toString(),
                icon: Icons.shopping_cart,
                color: Colors.blue,
                gradient: [Colors.blue.shade400, Colors.blue.shade700],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                title: 'Total Delivered',
                value: delivered.toString(),
                icon: Icons.check_circle,
                color: Colors.green,
                gradient: [Colors.green.shade400, Colors.green.shade700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Pending Orders',
                value: pending.toString(),
                icon: Icons.pending_actions,
                color: Colors.orange,
                gradient: [Colors.orange.shade400, Colors.orange.shade700],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                title: 'Cancelled',
                value: cancelled.toString(),
                icon: Icons.cancel,
                color: Colors.red,
                gradient: [Colors.red.shade400, Colors.red.shade700],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVisitorsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Currently Login',
                value: _activeUsers.toString(),
                icon: Icons.person,
                color: Colors.purple,
                gradient: [Colors.purple.shade400, Colors.purple.shade700],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                title: "Today's Total Logins/Visitors",
                value: _todayLogins.toString(),
                icon: Icons.people_alt,
                color: Colors.teal,
                gradient: [Colors.teal.shade400, Colors.teal.shade700],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required List<Color> gradient,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12), // Smaller radius
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20, // Smaller font
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ), // Smaller font
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreBalancesSection() {
    final filtered = _filteredStoreRows();
    final totals = _storeSummaryTotals(filtered);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Store Balances',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'All stores with order pricing and wallet balances',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        _buildStoreFilterDropdown(),
        const SizedBox(height: 10),
        _buildStoreFilterTabs(),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSmallInfoCard(
                label: 'Stores',
                value: '${filtered.length}',
                color: Colors.indigo,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSmallInfoCard(
                label: 'Orders',
                value: '${totals['orders']}',
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSmallInfoCard(
                label: 'Sales',
                value: 'PKR ${(totals['sales'] as double).toStringAsFixed(0)}',
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No store data available for selected tab'),
          )
        else
          ...filtered.map(_buildStoreBalanceCard),
      ],
    );
  }

  Widget _buildStoreFilterDropdown() {
    return DropdownButton<int?>(
      value: _selectedStoreFilterId,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down),
      underline: Container(height: 1, color: Colors.grey.shade300),
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('All stores'),
        ),
        ..._storeFilterOptions.map(
          (opt) => DropdownMenuItem(
            value: opt['store_id'] as int?,
            child: Text(opt['store_name']?.toString() ?? 'Store'),
          ),
        ),
      ],
      onChanged: (value) {
        setState(() => _selectedStoreFilterId = value);
      },
    );
  }

  Widget _buildStoreFilterTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildStoreTabChip('All', 'all'),
          const SizedBox(width: 8),
          _buildStoreTabChip('Delivered', 'delivered'),
          const SizedBox(width: 8),
          _buildStoreTabChip('Pending', 'pending'),
          const SizedBox(width: 8),
          _buildStoreTabChip('Cancelled', 'cancelled'),
        ],
      ),
    );
  }

  Widget _buildStoreTabChip(String label, String value) {
    final selected = _selectedStoreTab == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) {
        if (!v) return;
        setState(() => _selectedStoreTab = value);
      },
      selectedColor: Colors.indigo.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? Colors.indigo : Colors.grey[700],
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? Colors.indigo : Colors.grey[300]!),
      ),
    );
  }

  Widget _buildSmallInfoCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildStoreBalanceCard(Map<String, dynamic> row) {
    final storeName = (row['store_name'] ?? 'Store').toString();
    final totalOrders = row['total_orders'] as int? ?? 0;
    final delivered = row['served_orders'] as int? ?? 0;
    final pending = row['pending_orders'] as int? ?? 0;
    final cancelled = row['cancelled_orders'] as int? ?? 0;
    final wallet = row['wallet_balance'] as double? ?? 0;
    final gross = row['gross_sales'] as double? ?? 0;
    final servedSales = row['served_sales'] as double? ?? 0;
    final pendingSales = row['pending_sales'] as double? ?? 0;
    final orders = (row['orders'] as List<Map<String, dynamic>>?) ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: Text(
          storeName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(
          'Balance: PKR ${wallet.toStringAsFixed(2)} | Total: $totalOrders',
          style: TextStyle(
            color: wallet < 0 ? Colors.red : Colors.green[700],
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metricChip('Delivered', '$delivered', Colors.green),
              _metricChip('Pending', '$pending', Colors.orange),
              _metricChip('Cancelled', '$cancelled', Colors.red),
              _metricChip('Gross', 'PKR ${gross.toStringAsFixed(0)}', Colors.blue),
              _metricChip(
                'Served Sales',
                'PKR ${servedSales.toStringAsFixed(0)}',
                Colors.teal,
              ),
              _metricChip(
                'Pending Sales',
                'PKR ${pendingSales.toStringAsFixed(0)}',
                Colors.deepOrange,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (orders.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No orders found', style: TextStyle(color: Colors.black54)),
            )
          else ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent Orders',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 4),
            ...orders.take(5).map((o) {
              final number = (o['order_number'] ?? '').toString();
              final status = (o['status'] ?? '').toString();
              final amount = o['amount'] as double? ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '#$number',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: _statusColor(status),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PKR ${amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 11),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s == 'delivered') return Colors.green;
    if (s == 'cancelled') return Colors.red;
    if (s == 'pending' || s == 'confirmed' || s == 'preparing' || s == 'ready') {
      return Colors.orange;
    }
    return Colors.blueGrey;
  }

  List<Map<String, dynamic>> _filteredStoreRows() {
    final baseRows = _storeBalanceRows.where((r) {
      if (_selectedStoreFilterId == null) return true;
      return r['store_id'] == _selectedStoreFilterId;
    }).toList();

    switch (_selectedStoreTab) {
      case 'delivered':
        return baseRows
            .where((r) => (r['served_orders'] as int? ?? 0) > 0)
            .toList();
      case 'pending':
        return baseRows
            .where((r) => (r['pending_orders'] as int? ?? 0) > 0)
            .toList();
      case 'cancelled':
        return baseRows
            .where((r) => (r['cancelled_orders'] as int? ?? 0) > 0)
            .toList();
      case 'all':
      default:
        return baseRows;
    }
  }

  Map<String, dynamic> _storeSummaryTotals(List<Map<String, dynamic>> rows) {
    int orderCount = 0;
    double sales = 0;
    for (final r in rows) {
      orderCount += r['total_orders'] as int? ?? 0;
      sales += r['gross_sales'] as double? ?? 0;
    }
    return {'orders': orderCount, 'sales': sales};
  }

  Widget _buildRecentActivityList() {
    List<dynamic> list;
    switch (_selectedActivityType) {
      case 'users':
        list = _recentUsersList;
        break;
      case 'stores':
        list = _recentStoresList;
        break;
      case 'orders':
      default:
        list = _recentOrdersList;
        break;
    }

    if (list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No recent activity'),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          ...list.map((activity) {
            return Column(
              children: [
                InkWell(
                  onTap: () => _showActivityDetails(activity),
                  child: _buildActivityItem(
                    title: activity['title'] ?? '',
                    subtitle: activity['subtitle'] ?? '',
                    icon: _getIconData(activity['icon']),
                    color: _getColor(activity['color']),
                  ),
                ),
                if (activity != list.last) const Divider(height: 1),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActivityFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('New Orders', 'orders'),
          const SizedBox(width: 8),
          _buildFilterChip('New Users', 'users'),
          const SizedBox(width: 8),
          _buildFilterChip('New Stores', 'stores'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedActivityType == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedActivityType = value;
          });
        }
      },
      selectedColor: Colors.indigo.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? Colors.indigo : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? Colors.indigo : Colors.grey[300]!),
      ),
    );
  }

  void _showActivityDetails(Map<String, dynamic> activity) {
    String detailsStr = '';
    if (activity['details'] != null) {
      detailsStr = (activity['details'] as Map<String, dynamic>)
          .entries
          .map((e) => '${e.key}: ${e.value ?? "N/A"}')
          .join('\n');
    }

    Notifier.info(
      context,
      '${activity['title'] ?? "Activity Details"}\n$detailsStr',
      duration: const Duration(seconds: 5),
    );
  }

  IconData _getIconData(String? iconName) {
    switch (iconName) {
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'person_add':
        return Icons.person_add;
      case 'store':
        return Icons.store;
      default:
        return Icons.notifications;
    }
  }

  Color _getColor(String? colorName) {
    switch (colorName) {
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'orange':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _buildActivityItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 14,
        color: Colors.grey,
      ),
    );
  }
}
