import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
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
  Timer? _graceAlertTimer;
  final Map<String, DateTime> _lastGraceAlertAt = {};

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
  List<dynamic> _assignableOrdersList = [];
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
    _graceAlertTimer?.cancel();
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

    _graceAlertTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      _checkStoreGraceAlerts();
    });
    _checkStoreGraceAlerts();
  }

  Future<void> _checkStoreGraceAlerts() async {
    if (!mounted) return;
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null || token.trim().isEmpty) return;
      final data = await ApiService.getStoreGraceAlerts(
        token,
        channel: 'mobile',
      );
      final alerts = (data['alerts'] as List?) ?? const [];
      if (alerts.isEmpty || !mounted) return;
      final alert = (alerts.first as Map?)?.cast<String, dynamic>() ?? {};
      final storeId = int.tryParse((alert['store_id'] ?? '').toString());
      if (storeId == null || storeId <= 0) return;
      final storeName = (alert['store_name'] ?? 'Store').toString();
      final dueDate = (alert['due_date'] ?? '-').toString();
      final pending =
          double.tryParse((alert['pending_amount'] ?? '0').toString()) ?? 0;
      final daysLeft = int.tryParse((alert['days_left'] ?? '').toString());
      final lead = (daysLeft != null && daysLeft < 0)
          ? 'Overdue by ${daysLeft.abs()} day(s)'
          : (daysLeft != null ? 'Due in $daysLeft day(s)' : 'Payment due');
      final key = '$storeId|$dueDate|${pending.toStringAsFixed(2)}';
      final now = DateTime.now();
      final lastAt = _lastGraceAlertAt[key];
      // Keep periodic reminders, but avoid a notification every minute.
      if (lastAt != null &&
          now.difference(lastAt) < const Duration(minutes: 30)) {
        return;
      }
      _lastGraceAlertAt[key] = now;

      final notificationProvider = Provider.of<NotificationProvider>(
        context,
        listen: false,
      );
      notificationProvider.addNotification(
        title: 'Store Due Alert',
        message:
            '$storeName: $lead | Due: $dueDate | Pending: PKR ${pending.toStringAsFixed(2)}',
        type: 'warning',
        icon: 'warning',
        persistUntilDismissed: true,
      );
    } catch (e) {
      _logger.w('Grace alert poll skipped: $e');
    }
  }

  Future<void> _loadStats() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;
      final currentUserId = Provider.of<AuthProvider>(
        context,
        listen: false,
      ).user?.id;

      final results = await Future.wait([
        ApiService.getOrders(
          token,
          includeItemsCount: false,
          includeStoreStatuses: false,
        ),
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

      final assignableOrders =
          orders.where((o) {
            final s = (o['status'] ?? '').toString().toLowerCase();
            final customerId = int.tryParse(
              (o['customer_id'] ?? '').toString(),
            );
            final isOwnOrder =
                currentUserId != null && customerId == currentUserId;
            return s != 'delivered' && s != 'cancelled' && !isOwnOrder;
          }).toList()..sort((a, b) {
            DateTime ad = DateTime.fromMillisecondsSinceEpoch(0);
            DateTime bd = DateTime.fromMillisecondsSinceEpoch(0);
            try {
              ad = DateTime.parse((a['created_at'] ?? '').toString());
            } catch (_) {}
            try {
              bd = DateTime.parse((b['created_at'] ?? '').toString());
            } catch (_) {}
            return bd.compareTo(ad);
          });

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
        _assignableOrdersList = assignableOrders;
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
        iconTheme: const IconThemeData(color: Colors.black87),
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
            leading: const Icon(Icons.receipt_long),
            title: const Text('Manage Orders'),
            onTap: () {
              Navigator.of(context).pop();
              _openManageOrdersForAssignment();
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
    final cards = [
      (
        title: 'Total',
        value: total.toString(),
        icon: Icons.shopping_cart,
        gradient: [Colors.blue.shade400, Colors.blue.shade700],
      ),
      (
        title: 'Delivered',
        value: delivered.toString(),
        icon: Icons.check_circle,
        gradient: [Colors.green.shade400, Colors.green.shade700],
      ),
      (
        title: 'Pending',
        value: pending.toString(),
        icon: Icons.pending_actions,
        gradient: [Colors.orange.shade400, Colors.orange.shade700],
      ),
      (
        title: 'Cancelled',
        value: cancelled.toString(),
        icon: Icons.cancel,
        gradient: [Colors.red.shade400, Colors.red.shade700],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final cardWidth = (((width - (spacing * 3)) / 4).clamp(
          62.0,
          140.0,
        )).toDouble();
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              SizedBox(
                width: cardWidth,
                child: _buildStatCard(
                  title: cards[i].title,
                  value: cards[i].value,
                  icon: cards[i].icon,
                  color: cards[i].gradient.first,
                  gradient: cards[i].gradient,
                ),
              ),
              if (i != cards.length - 1) const SizedBox(width: spacing),
            ],
          ],
        );
      },
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
          .map(
            (s) => {
              'id': int.tryParse((s['id'] ?? '').toString()),
              'name': (s['name'] ?? 'Store').toString(),
            },
          )
          .where((s) => s['id'] != null)
          .toList();
      if (normalizedStores.isEmpty) {
        Notifier.error(context, 'No valid stores found');
        return;
      }

      int selectedStoreId = normalizedStores.first['id'] as int;
      bool isClosed = false;
      bool websiteEnabled = false;
      bool websiteBlockOrdering = false;
      bool storeSaving = false;
      bool websiteSaving = false;
      final messageCtrl = TextEditingController();
      final searchCtrl = TextEditingController();
      final websiteTitleCtrl = TextEditingController();
      final websiteMessageCtrl = TextEditingController();
      final websiteStartCtrl = TextEditingController();
      final websiteEndCtrl = TextEditingController();
      List<Map<String, dynamic>> visibleStores =
          List<Map<String, dynamic>>.from(normalizedStores);

      bool toBool(dynamic value) {
        if (value is bool) return value;
        if (value is num) return value != 0;
        if (value is String) {
          final normalized = value.trim().toLowerCase();
          return normalized == 'true' ||
              normalized == '1' ||
              normalized == 'yes';
        }
        return false;
      }

      String toDateTimeLocalString(DateTime dateTime) {
        final d = dateTime.toLocal();
        final m = d.month.toString().padLeft(2, '0');
        final day = d.day.toString().padLeft(2, '0');
        final h = d.hour.toString().padLeft(2, '0');
        final min = d.minute.toString().padLeft(2, '0');
        return '${d.year}-$m-${day}T$h:$min';
      }

      String formatForDisplay(dynamic raw) {
        final parsed = DateTime.tryParse((raw ?? '').toString());
        if (parsed == null) return '';
        return toDateTimeLocalString(parsed);
      }

      Future<void> pickDateTime(
        TextEditingController ctrl,
        void Function(VoidCallback) setDialogState,
      ) async {
        final now = DateTime.now();
        final current = DateTime.tryParse(ctrl.text.trim())?.toLocal() ?? now;
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: current,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 5),
        );
        if (pickedDate == null) return;
        if (!mounted) return;
        final pickedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(current),
        );
        if (pickedTime == null) return;
        final merged = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        setDialogState(() => ctrl.text = toDateTimeLocalString(merged));
      }

      Future<void> loadStoreStatus(
        int storeId,
        void Function(VoidCallback) setDialogState,
      ) async {
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

      try {
        final data = await ApiService.getGlobalDeliveryStatus(token);
        final status = (data['status'] is Map<String, dynamic>)
            ? (data['status'] as Map<String, dynamic>)
            : (data['global_status'] is Map<String, dynamic>)
            ? (data['global_status'] as Map<String, dynamic>)
            : data;
        websiteEnabled = toBool(status['is_enabled']);
        websiteBlockOrdering = toBool(status['block_ordering']);
        websiteTitleCtrl.text = (status['title'] ?? '').toString();
        websiteMessageCtrl.text = (status['status_message'] ?? '').toString();
        websiteStartCtrl.text = formatForDisplay(status['start_at']);
        websiteEndCtrl.text = formatForDisplay(status['end_at']);
      } catch (_) {}

      if (websiteStartCtrl.text.trim().isEmpty) {
        websiteStartCtrl.text = toDateTimeLocalString(DateTime.now());
      }
      if (websiteEndCtrl.text.trim().isEmpty) {
        websiteEndCtrl.text = toDateTimeLocalString(DateTime.now());
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return AlertDialog(
                title: const Text('Store Status'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Per-Store Status',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
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
                                !visibleStores.any(
                                  (s) => s['id'] == selectedStoreId,
                                )) {
                              selectedStoreId =
                                  visibleStores.first['id'] as int;
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
                          initialValue:
                              visibleStores.any(
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
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: storeSaving
                              ? null
                              : () async {
                                  setDialogState(() => storeSaving = true);
                                  try {
                                    await ApiService.setStoreStatusMessage(
                                      token,
                                      storeId: selectedStoreId,
                                      statusMessage: messageCtrl.text.trim(),
                                      isClosed: isClosed,
                                    );
                                    if (!mounted) return;
                                    Notifier.success(
                                      context,
                                      'Store message updated successfully',
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    Notifier.error(
                                      context,
                                      'Failed to save store status: $e',
                                    );
                                  } finally {
                                    if (ctx.mounted) {
                                      setDialogState(() => storeSaving = false);
                                    }
                                  }
                                },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save Store Status'),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1),
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Website-Wide Delivery Status',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable Website-Wide Message'),
                        value: websiteEnabled,
                        onChanged: (v) =>
                            setDialogState(() => websiteEnabled = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Block Add to Cart / Place Order'),
                        subtitle: const Text(
                          'If enabled, ordering is blocked during active time window.',
                        ),
                        value: websiteBlockOrdering,
                        onChanged: (v) =>
                            setDialogState(() => websiteBlockOrdering = v),
                      ),
                      TextField(
                        controller: websiteTitleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          hintText: 'Delivery Unavailable',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: websiteMessageCtrl,
                        maxLines: 4,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Website Message',
                          hintText:
                              'Delivery will be unavailable from ... to ...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: websiteStartCtrl,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Start At',
                                hintText: 'YYYY-MM-DDTHH:mm',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Pick start time',
                            onPressed: () =>
                                pickDateTime(websiteStartCtrl, setDialogState),
                            icon: const Icon(Icons.schedule),
                          ),
                          IconButton(
                            tooltip: 'Clear start time',
                            onPressed: () =>
                                setDialogState(() => websiteStartCtrl.clear()),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: websiteEndCtrl,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'End At',
                                hintText: 'YYYY-MM-DDTHH:mm',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Pick end time',
                            onPressed: () =>
                                pickDateTime(websiteEndCtrl, setDialogState),
                            icon: const Icon(Icons.schedule),
                          ),
                          IconButton(
                            tooltip: 'Clear end time',
                            onPressed: () =>
                                setDialogState(() => websiteEndCtrl.clear()),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: websiteSaving
                              ? null
                              : () async {
                                  setDialogState(() => websiteSaving = true);
                                  try {
                                    if (websiteStartCtrl.text.trim().isEmpty) {
                                      websiteStartCtrl.text =
                                          toDateTimeLocalString(DateTime.now());
                                    }
                                    if (websiteEndCtrl.text.trim().isEmpty) {
                                      websiteEndCtrl.text =
                                          toDateTimeLocalString(DateTime.now());
                                    }
                                    final startAt = websiteStartCtrl.text
                                        .trim();
                                    final endAt = websiteEndCtrl.text.trim();
                                    if (startAt.isNotEmpty &&
                                        endAt.isNotEmpty) {
                                      final start = DateTime.tryParse(startAt);
                                      final end = DateTime.tryParse(endAt);
                                      if (start == null ||
                                          end == null ||
                                          !end.isAfter(start)) {
                                        Notifier.error(
                                          context,
                                          'End time must be greater than start time.',
                                        );
                                        return;
                                      }
                                    }

                                    await ApiService.setGlobalDeliveryStatus(
                                      token,
                                      isEnabled: websiteEnabled,
                                      blockOrdering: websiteBlockOrdering,
                                      title: websiteTitleCtrl.text,
                                      statusMessage: websiteMessageCtrl.text
                                          .trim(),
                                      startAt: startAt,
                                      endAt: endAt,
                                    );
                                    if (!mounted) return;
                                    Notifier.success(
                                      context,
                                      'Website delivery status updated successfully',
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    Notifier.error(
                                      context,
                                      'Failed to save website status: $e',
                                    );
                                  } finally {
                                    if (ctx.mounted) {
                                      setDialogState(
                                        () => websiteSaving = false,
                                      );
                                    }
                                  }
                                },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save Website Status'),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ],
              );
            },
          );
        },
      );
      messageCtrl.dispose();
      searchCtrl.dispose();
      websiteTitleCtrl.dispose();
      websiteMessageCtrl.dispose();
      websiteStartCtrl.dispose();
      websiteEndCtrl.dispose();
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
              icon: Icons.receipt_long,
              label: 'Orders',
              onTap: _openManageOrdersForAssignment,
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
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 9.5,
              ),
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
      height: 59,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
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
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
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
    if (_selectedActivityType == 'orders') {
      return _buildNewOrdersList();
    }

    List<dynamic> list;
    switch (_selectedActivityType) {
      case 'users':
        list = _recentUsersList;
        break;
      case 'stores':
        list = _recentStoresList;
        break;
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

  Widget _buildNewOrdersList() {
    if (_assignableOrdersList.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No new orders to assign'),
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
          ..._assignableOrdersList.map((raw) {
            if (raw is! Map) return const SizedBox.shrink();
            final order = raw.cast<String, dynamic>();
            final id = int.tryParse((order['id'] ?? '').toString()) ?? 0;
            final orderNo = (order['order_number'] ?? '#$id').toString();
            final status = (order['status'] ?? 'pending').toString();
            final riderId = int.tryParse((order['rider_id'] ?? '').toString());
            final total =
                double.tryParse((order['total_amount'] ?? '0').toString()) ?? 0;
            final subtitle =
                'PKR ${total.toStringAsFixed(0)} | ${riderId == null ? "Unassigned" : "Assigned"} | $status';

            return Column(
              children: [
                InkWell(
                  onTap: id > 0
                      ? () => _openOrderAssignmentDialog({
                          'type': 'order',
                          'order_id': id,
                        })
                      : null,
                  child: _buildActivityItem(
                    title: 'Order $orderNo',
                    subtitle: subtitle,
                    icon: Icons.receipt_long,
                    color: riderId == null ? Colors.orange : Colors.blue,
                  ),
                ),
                if (raw != _assignableOrdersList.last) const Divider(height: 1),
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
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600])),
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

  int? _extractOrderIdFromActivity(Map<String, dynamic> activity) {
    final direct = int.tryParse((activity['order_id'] ?? '').toString());
    if (direct != null && direct > 0) return direct;

    final details = activity['details'];
    if (details is Map<String, dynamic>) {
      final rawOrderId = (details['Order ID'] ?? details['order_id'] ?? '')
          .toString()
          .trim();
      final clean = rawOrderId.replaceAll(RegExp(r'[^0-9]'), '');
      final parsed = int.tryParse(clean);
      if (parsed != null && parsed > 0) return parsed;
    }

    final title = (activity['title'] ?? '').toString();
    final match = RegExp(r'#\s*(\d+)').firstMatch(title);
    if (match != null) {
      final parsed = int.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  Future<void> _openOrderAssignmentDialog(Map<String, dynamic> activity) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null || token.trim().isEmpty) {
      Notifier.error(context, 'Session expired. Please login again.');
      return;
    }

    final orderId = _extractOrderIdFromActivity(activity);
    if (orderId == null) {
      Notifier.error(context, 'Order ID not found in activity.');
      return;
    }

    try {
      final results = await Future.wait<List<dynamic>>([
        ApiService.getOrders(
          token,
          includeItemsCount: false,
          includeStoreStatuses: false,
        ),
        ApiService.getAvailableRiders(token),
      ]);
      final orders = results[0];
      final riders = results[1];
      Map<String, dynamic>? order;
      for (final raw in orders) {
        if (raw is! Map) continue;
        final map = raw.cast<String, dynamic>();
        if (int.tryParse((map['id'] ?? '').toString()) == orderId) {
          order = map;
          break;
        }
      }
      if (!mounted) return;
      if (order == null) {
        Notifier.error(context, 'Order #$orderId not found.');
        return;
      }

      final orderNumber = (order['order_number'] ?? orderId).toString();
      final totalAmount =
          double.tryParse((order['total_amount'] ?? '0').toString()) ?? 0;
      final currentStatus = (order['status'] ?? 'pending').toString();
      final initialRiderId = int.tryParse((order['rider_id'] ?? '').toString());

      String selectedStatus = currentStatus;
      int? selectedRiderId = initialRiderId;
      bool isSaving = false;
      const statusOptions = <String>[
        'pending',
        'confirmed',
        'preparing',
        'ready',
        'ready_for_pickup',
        'out_for_delivery',
        'delivered',
        'cancelled',
      ];

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              return AlertDialog(
                title: Text('Order #$orderNumber Assignment'),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total: PKR ${totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int?>(
                          key: ValueKey<int?>(selectedRiderId),
                          initialValue: selectedRiderId,
                          decoration: const InputDecoration(
                            labelText: 'Assign Rider',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Unassigned'),
                            ),
                            ...riders.map((r) {
                              final id = int.tryParse(
                                (r['id'] ?? '').toString(),
                              );
                              if (id == null) {
                                return const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('Invalid Rider'),
                                );
                              }
                              final name =
                                  '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'
                                      .trim();
                              return DropdownMenuItem<int?>(
                                value: id,
                                child: Text(name.isEmpty ? 'Rider #$id' : name),
                              );
                            }),
                          ],
                          onChanged: isSaving
                              ? null
                              : (v) => setModalState(() => selectedRiderId = v),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey<String>(selectedStatus),
                          initialValue: selectedStatus,
                          decoration: const InputDecoration(
                            labelText: 'Order Status',
                            border: OutlineInputBorder(),
                          ),
                          items: statusOptions
                              .map(
                                (s) => DropdownMenuItem<String>(
                                  value: s,
                                  child: Text(s),
                                ),
                              )
                              .toList(),
                          onChanged: isSaving
                              ? null
                              : (v) {
                                  if (v != null) {
                                    setModalState(() => selectedStatus = v);
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setModalState(() => isSaving = true);
                            try {
                              bool changed = false;
                              if (selectedRiderId != null &&
                                  selectedRiderId != initialRiderId) {
                                await ApiService.assignOrderRider(
                                  token,
                                  orderId,
                                  selectedRiderId!,
                                );
                                changed = true;
                              }
                              if (selectedStatus != currentStatus) {
                                await ApiService.updateOrderStatus(
                                  token,
                                  orderId,
                                  selectedStatus,
                                );
                                changed = true;
                              }
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              if (!mounted) return;
                              if (changed) {
                                Notifier.success(
                                  context,
                                  'Order #$orderNumber updated successfully.',
                                );
                                _loadStats();
                              } else {
                                Notifier.info(context, 'No changes applied.');
                              }
                            } catch (e) {
                              if (mounted) {
                                Notifier.error(
                                  context,
                                  'Failed to update order: $e',
                                );
                              }
                            } finally {
                              if (ctx.mounted) {
                                setModalState(() => isSaving = false);
                              }
                            }
                          },
                    child: isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Notifier.error(context, 'Failed to load assignment data: $e');
    }
  }

  Future<void> _openManageOrdersForAssignment() async {
    await _loadStats();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            height: MediaQuery.of(ctx).size.height * 0.86,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Manage Orders (Assign Riders)',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _assignableOrdersList.isEmpty
                      ? const Center(
                          child: Text('No new orders pending assignment'),
                        )
                      : ListView.separated(
                          itemCount: _assignableOrdersList.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final raw = _assignableOrdersList[index];
                            if (raw is! Map) return const SizedBox.shrink();
                            final order = raw.cast<String, dynamic>();
                            final id =
                                int.tryParse((order['id'] ?? '').toString()) ??
                                0;
                            final orderNo = (order['order_number'] ?? '#$id')
                                .toString();
                            final status = (order['status'] ?? 'pending')
                                .toString();
                            final total =
                                double.tryParse(
                                  (order['total_amount'] ?? '0').toString(),
                                ) ??
                                0;
                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0x1AF57C00),
                                child: Icon(
                                  Icons.receipt_long,
                                  color: Colors.orange,
                                ),
                              ),
                              title: Text(
                                'Order $orderNo',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'PKR ${total.toStringAsFixed(0)} | $status',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: id <= 0
                                  ? null
                                  : () {
                                      Navigator.of(ctx).pop();
                                      _openOrderAssignmentDialog({
                                        'type': 'order',
                                        'order_id': id,
                                      });
                                    },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showActivityDetails(Map<String, dynamic> activity) {
    final type = (activity['type'] ?? '').toString().toLowerCase();
    if (type == 'order') {
      _openOrderAssignmentDialog(activity);
      return;
    }
    String detailsStr = '';
    if (activity['details'] != null) {
      detailsStr = (activity['details'] as Map<String, dynamic>).entries
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
