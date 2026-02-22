import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/notifier.dart';
import '../services/notification_service.dart';
import '../widgets/notification_bell_widget.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final Logger _logger = Logger();
  bool _isLoading = true;
  Timer? _liveStatsTimer;

  int _todayTotal = 0;
  int _todayDelivered = 0;
  int _todayPending = 0;
  int _todayCancelled = 0;

  int _allTotal = 0;
  int _allDelivered = 0;
  int _allPending = 0;
  int _allCancelled = 0;

  int _activeUsers = 0;
  int _todayLogins = 0;

  List<dynamic> _recentOrdersList = [];
  List<dynamic> _recentUsersList = [];
  List<dynamic> _recentStoresList = [];
  String _selectedActivityType = 'orders';

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  int _readFirstInt(Map<String, dynamic> src, List<String> keys) {
    for (final key in keys) {
      if (src.containsKey(key) && src[key] != null) {
        return _toInt(src[key]);
      }
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _loadStats();
    _setupLiveRefresh();
  }

  @override
  void dispose() {
    _liveStatsTimer?.cancel();
    NotificationService.disconnect();
    super.dispose();
  }

  void _setupLiveRefresh() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.user != null) {
      NotificationService.initialize(
        onNotification: (data) {
          if (!mounted) return;
          final type = (data['type'] ?? data['event'] ?? '')
              .toString()
              .toLowerCase();
          // Refresh stats quickly for events that can affect dashboard counters.
          if (type.contains('user') ||
              type.contains('order') ||
              type.contains('payment') ||
              type.contains('new')) {
            _loadVisitorStatsOnly();
          }
        },
      );
      NotificationService.connect(auth.user!.id, 'admin');
    }

    // Fallback polling so logins are reflected even without explicit socket events.
    _liveStatsTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      _loadVisitorStatsOnly();
    });
  }

  Future<void> _loadStats() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      final results = await Future.wait([
        ApiService.getOrders(token),
        ApiService.getVisitorStats(token),
        ApiService.getRecentActivity(token),
      ]);

      final orders = results[0] as List<dynamic>;
      final visitorStats = results[1] as Map<String, dynamic>;
      final recentActivityData = results[2] as Map<String, dynamic>;

      final now = DateTime.now();
      final todayOrders = orders.where((o) {
        try {
          final dt = DateTime.parse(o['created_at'].toString());
          return dt.year == now.year &&
              dt.month == now.month &&
              dt.day == now.day;
        } catch (_) {
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

      final stats = (visitorStats['stats'] is Map<String, dynamic>)
          ? visitorStats['stats'] as Map<String, dynamic>
          : visitorStats;

      int activeUsers = _readFirstInt(stats, const [
        'active_users',
        'activeUsers',
        'currently_logged_in',
        'currentlyLogin',
        'online_users',
        'onlineUsers',
      ]);
      if (activeUsers == 0) {
        activeUsers =
            _toInt(stats['active_customers']) +
            _toInt(stats['active_admins']) +
            _toInt(stats['active_riders']) +
            _toInt(stats['active_store_owners']) +
            _toInt(stats['active_storeOwners']) +
            _toInt(stats['active_store_managers']);
      }

      final todayLogins = _readFirstInt(stats, const [
        'today_logins',
        'todayLogins',
        'todays_logins',
        'logins_today',
      ]);

      setState(() {
        _todayTotal = todayOrders.length;
        _todayDelivered = countStatus(todayOrders, 'delivered');
        _todayPending = countPendingLike(todayOrders);
        _todayCancelled = countStatus(todayOrders, 'cancelled');

        _allTotal = orders.length;
        _allDelivered = countStatus(orders, 'delivered');
        _allPending = countPendingLike(orders);
        _allCancelled = countStatus(orders, 'cancelled');

        _activeUsers = activeUsers;
        _todayLogins = todayLogins;

        _recentOrdersList = recentActivityData['recent_orders'] ?? [];
        _recentUsersList = recentActivityData['recent_users'] ?? [];
        _recentStoresList = recentActivityData['recent_stores'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      _logger.e('Error loading stats: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadVisitorStatsOnly() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;
      final visitorStats = await ApiService.getVisitorStats(token);
      final stats = (visitorStats['stats'] is Map<String, dynamic>)
          ? visitorStats['stats'] as Map<String, dynamic>
          : visitorStats;
      final activeUsers = _readFirstInt(stats, const [
        'active_users',
        'activeUsers',
        'currently_logged_in',
        'currentlyLogin',
        'online_users',
        'onlineUsers',
      ]);
      final todayLogins = _readFirstInt(stats, const [
        'today_logins',
        'todayLogins',
        'todays_logins',
        'logins_today',
      ]);
      if (!mounted) return;
      setState(() {
        _activeUsers = activeUsers;
        _todayLogins = todayLogins;
      });
    } catch (e) {
      _logger.w('Live visitor stats refresh skipped: $e');
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
                authProvider.user?.firstName.substring(0, 1).toUpperCase() ?? 'A',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(context, authProvider),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: _buildQuickMenu(context),
        ),
      ),
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
                    const SizedBox(height: 4),
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
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 8),
                    const Text(
                      "Today's Visitors",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildVisitorsGrid(),
                    const SizedBox(height: 32),
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Drawer(
      child: ListView(
        padding: EdgeInsets.only(bottom: bottomInset + 12),
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
                authProvider.user?.firstName.substring(0, 1).toUpperCase() ?? 'A',
                style: const TextStyle(fontSize: 24, color: Colors.indigo),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            selected: true,
            onTap: () => Navigator.of(context).pop(),
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
            leading: const Icon(Icons.storefront),
            title: const Text('Store Balances'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/store-balances');
            },
          ),
          ListTile(
            leading: const Icon(Icons.campaign),
            title: const Text('Store Status'),
            onTap: () {
              Navigator.of(context).pop();
              _openStoreStatusMessageDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.shopping_bag),
            title: const Text('Products & Variants'),
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
            title: const Text('Inventory Reports'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/inventory-report');
            },
          ),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Customer Dashboard Test'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/customer-test-dashboard');
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
                title: 'Delivered',
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

  Future<void> _openStoreStatusMessageDialog() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      final stores = await ApiService.getStoresForAdmin(
        token,
        includeInactive: true,
      );
      if (!mounted) return;
      if (stores.isEmpty) {
        Notifier.error(context, 'No stores found');
        return;
      }

      final normalizedStores = stores
          .map((s) => {
                'id': int.tryParse((s['id'] ?? '').toString()),
                'name': (s['name'] ?? 'Store').toString(),
              })
          .where((s) => s['id'] != null)
          .toList();
      if (normalizedStores.isEmpty) {
        Notifier.error(context, 'No valid stores found');
        return;
      }

      int selectedStoreId = normalizedStores.first['id'] as int;
      bool isClosed = false;
      final messageCtrl = TextEditingController();
      final searchCtrl = TextEditingController();
      List<Map<String, dynamic>> visibleStores = List<Map<String, dynamic>>.from(
        normalizedStores,
      );

      Future<void> loadStoreStatus(int storeId, void Function(VoidCallback) setDialogState) async {
        try {
          final status = await ApiService.getStoreStatusMessage(
            token,
            storeId: storeId,
          );
          setDialogState(() {
            isClosed = status['is_closed'] == true;
            messageCtrl.text = (status['status_message'] ?? '').toString();
          });
        } catch (_) {
          setDialogState(() {
            isClosed = false;
            messageCtrl.text = '';
          });
        }
      }

      try {
        final initial = await ApiService.getStoreStatusMessage(
          token,
          storeId: selectedStoreId,
        );
        isClosed = initial['is_closed'] == true;
        messageCtrl.text = (initial['status_message'] ?? '').toString();
      } catch (_) {}

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          bool saving = false;
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return AlertDialog(
                title: const Text('Update Store Status'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: searchCtrl,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Search Store',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          final q = value.trim().toLowerCase();
                          setDialogState(() {
                            visibleStores = normalizedStores.where((s) {
                              final name = (s['name'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              final id = (s['id'] ?? '').toString();
                              return q.isEmpty ||
                                  name.contains(q) ||
                                  id.contains(q);
                            }).toList();
                            if (visibleStores.isNotEmpty &&
                                !visibleStores.any((s) => s['id'] == selectedStoreId)) {
                              selectedStoreId = visibleStores.first['id'] as int;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      if (visibleStores.isEmpty)
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('No stores match your search'),
                          ),
                        )
                      else
                        DropdownButtonFormField<int>(
                          key: ValueKey('store-$selectedStoreId'),
                          isExpanded: true,
                          initialValue: visibleStores.any(
                            (s) => s['id'] == selectedStoreId,
                          )
                              ? selectedStoreId
                              : (visibleStores.first['id'] as int),
                          decoration: const InputDecoration(
                            labelText: 'Select Store',
                            border: OutlineInputBorder(),
                          ),
                          items: visibleStores
                              .map(
                                (s) => DropdownMenuItem<int>(
                                  value: s['id'] as int,
                                  child: Text(
                                    (s['name'] ?? 'Store').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          selectedItemBuilder: (context) => visibleStores
                              .map(
                                (s) => Text(
                                  (s['name'] ?? 'Store').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                              .toList(),
                          onChanged: (value) async {
                            if (value == null) return;
                            setDialogState(() => selectedStoreId = value);
                            await loadStoreStatus(value, setDialogState);
                          },
                        ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mark as Closed'),
                        value: isClosed,
                        onChanged: (v) => setDialogState(() => isClosed = v),
                      ),
                      TextField(
                        controller: messageCtrl,
                        maxLines: 4,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Status Message',
                          hintText: 'Store is closed due to maintenance...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: saving
                        ? null
                        : () async {
                            setDialogState(() => saving = true);
                            try {
                              await ApiService.setStoreStatusMessage(
                                token,
                                storeId: selectedStoreId,
                                statusMessage: messageCtrl.text.trim(),
                                isClosed: isClosed,
                              );
                              if (!mounted || !ctx.mounted) return;
                              Navigator.of(ctx).pop();
                              Notifier.success(
                                context,
                                'Store message updated successfully',
                              );
                            } catch (e) {
                              if (!mounted) return;
                              setDialogState(() => saving = false);
                              Notifier.error(context, 'Failed to save: $e');
                            }
                          },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Notifier.error(context, 'Failed to open store message dialog: $e');
    }
  }

  Widget _buildQuickMenu(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white70),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildQuickMenuItem(
              context: context,
              icon: Icons.store,
              label: 'Stores',
              route: '/manage-stores',
            ),
            const SizedBox(width: 10),
            _buildQuickMenuItem(
              context: context,
              icon: Icons.shopping_bag,
              label: 'Products',
              route: '/manage-products',
            ),
            const SizedBox(width: 10),
            _buildQuickMenuItem(
              context: context,
              icon: Icons.people,
              label: 'Users',
              route: '/manage-users',
            ),
            const SizedBox(width: 10),
            _buildQuickMenuItem(
              context: context,
              icon: Icons.delivery_dining,
              label: 'Riders',
              route: '/manage-riders',
            ),
            const SizedBox(width: 10),
            _buildQuickMenuItem(
              context: context,
              icon: Icons.inventory_2,
              label: 'Inventory',
              route: '/inventory-report',
            ),
            const SizedBox(width: 10),
            _buildQuickMenuItem(
              context: context,
              icon: Icons.campaign,
              label: 'Status',
              onTap: _openStoreStatusMessageDialog,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickMenuItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    String? route,
    VoidCallback? onTap,
  }) {
    final VoidCallback handleTap =
        onTap ?? () => Navigator.of(context).pushNamed(route!);
    return InkWell(
      onTap: handleTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.indigo, size: 19),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitorsGrid() {
    return Row(
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
            title: "Today's Logins",
            value: _todayLogins.toString(),
            icon: Icons.people_alt,
            color: Colors.teal,
            gradient: [Colors.teal.shade400, Colors.teal.shade700],
          ),
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
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityFilter() {
    return Row(
      children: [
        _buildFilterChip('New Orders', 'orders'),
        const SizedBox(width: 8),
        _buildFilterChip('New Users', 'users'),
        const SizedBox(width: 8),
        _buildFilterChip('New Stores', 'stores'),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedActivityType == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (!selected) return;
        setState(() => _selectedActivityType = value);
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

  Widget _buildActivityItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[600]),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
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
}
