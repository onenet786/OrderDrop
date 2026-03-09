import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/notification_bell_widget.dart';
import 'offer_campaigns_screen.dart';
import 'login_screen.dart';

class StoreOwnerDashboardScreen extends StatefulWidget {
  const StoreOwnerDashboardScreen({super.key});

  @override
  State<StoreOwnerDashboardScreen> createState() =>
      _StoreOwnerDashboardScreenState();
}

class _StoreOwnerDashboardScreenState extends State<StoreOwnerDashboardScreen>
    with SingleTickerProviderStateMixin {
  final Logger _logger = Logger();
  late TabController _tabController;
  bool _isLoading = true;
  List<dynamic> _pendingOrders = [];
  List<dynamic> _activeOrders = []; // Preparing, Ready
  List<dynamic> _historyOrders = []; // Delivered, Cancelled
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadOrders();
    _setupNotifications();
  }

  void _setupNotifications() {
    NotificationService.initialize(
      onNotification: (data) {
        _handleNotification(data);
      },
    );

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user != null) {
      NotificationService.connect(authProvider.user!.id, 'store_owner');
    }
  }

  void _handleNotification(Map<String, dynamic> notification) {
    if (!mounted) return;

    final nestedData = (notification['data'] is Map<String, dynamic>)
        ? notification['data'] as Map<String, dynamic>
        : null;
    final message = (notification['message'] ??
                nestedData?['message'] ??
                notification['title'] ??
                'New notification')
            .toString();
    final type =
        (notification['type'] ?? nestedData?['type'])?.toString().toLowerCase();
    final status = (notification['status'] ?? nestedData?['status'])
        ?.toString()
        .toLowerCase();
    final isSilentRefresh = type == 'silent_refresh';
    final isSilentOrderRefresh =
        type == 'refresh_orders' && message.trim().isEmpty;

    if (!isSilentRefresh && !isSilentOrderRefresh) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
        ),
      );
    }

    final isNewOrder = type == 'new_order';
    final isHistoryUpdate = status == 'delivered' ||
        status == 'cancelled' ||
        status == 'picked_up' ||
        type == 'order_completed' ||
        type == 'delivered';
    final isActiveUpdate = status == 'preparing' ||
        status == 'ready' ||
        status == 'ready_for_pickup' ||
        status == 'out_for_delivery' ||
        type == 'rider_assigned';

    if (isNewOrder ||
        isHistoryUpdate ||
        isActiveUpdate ||
        isSilentRefresh ||
        type == 'refresh_orders' ||
        type == 'order_status_update') {
      _loadOrders();

      if (isNewOrder) {
        _tabController.animateTo(0); // Switch to New Orders tab
      } else if (isHistoryUpdate) {
        _tabController.animateTo(2); // Switch to History tab
      } else if (isActiveUpdate) {
        _tabController.animateTo(1); // Switch to Active tab
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    NotificationService.disconnect();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      final data = await ApiService.getStoreOrders(token);
      final orders = (data['orders'] as List?) ?? [];
      final stats = (data['stats'] as Map<String, dynamic>?) ?? {};

      if (mounted) {
        setState(() {
          _stats = stats;
          _pendingOrders = orders
              .where(
                (o) => o['status'] == 'pending' || o['status'] == 'confirmed',
              )
              .toList();
          _activeOrders = orders
              .where(
                (o) =>
                    o['status'] == 'preparing' ||
                    o['status'] == 'ready' ||
                    o['status'] == 'ready_for_pickup' || // Include ready_for_pickup in Active
                    o['status'] == 'out_for_delivery',
              )
              .toList();
          _historyOrders = orders
              .where(
                (o) =>
                    o['status'] == 'delivered' ||
                    o['status'] == 'cancelled' ||
                    o['status'] == 'picked_up' || // Show picked_up in history as it's done for the store
                    o['status'] == 'out_for_delivery', // Also show out_for_delivery in history
              )
              .toList();
        });
      }
    } catch (e) {
      _logger.e('Error loading store orders: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load orders: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateStatus(int orderId, String newStatus) async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      await ApiService.updateOrderStatus(token, orderId, newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order marked as ${newStatus.toUpperCase()}'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            showCloseIcon: true,
          ),
        );
        if (newStatus == 'ready') {
          _tabController.animateTo(1); // Switch to Active tab
        } else if (newStatus == 'picked_up') {
          _tabController.animateTo(2); // Move to History after pickup confirmation
        }
        _loadOrders();
      }
    } catch (e) {
      _logger.e('Error updating status: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
      }
    }
  }

  String _dateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _fmtDateTime(dynamic raw) {
    if (raw == null) return '-';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return raw.toString();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  Future<void> _openStoreFinancialHistory() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;
    final now = DateTime.now();
    final fromDate = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDate: now.subtract(const Duration(days: 6)),
      helpText: 'Select Start Date',
    );
    if (fromDate == null || !mounted) return;

    final toDate = await showDatePicker(
      context: context,
      firstDate: fromDate,
      lastDate: DateTime(now.year + 1),
      initialDate: now.isAfter(fromDate) ? now : fromDate,
      helpText: 'Select End Date',
    );
    if (toDate == null || !mounted) return;
    try {
      final data = await ApiService.getStoreOwnerFinancialHistory(
        token,
        from: _dateOnly(fromDate),
        to: _dateOnly(toDate),
      );
      if (!mounted) return;
      final summary = (data['summary'] as Map<String, dynamic>?) ?? {};
      final entries = (data['entries'] as List?) ?? const [];
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final fromText = _dateOnly(fromDate);
          final toText = _dateOnly(toDate);

          Color statusColor(String status) {
            final s = status.toLowerCase();
            if (s == 'delivered' || s == 'paid') return Colors.green;
            if (s == 'cancelled') return Colors.red;
            if (s == 'picked_up' || s == 'out_for_delivery') return Colors.blue;
            if (s == 'ready' || s == 'preparing') return Colors.orange;
            return Colors.grey;
          }

          Widget summaryTile({
            required String label,
            required dynamic value,
            required IconData icon,
            required Color color,
          }) {
            final amount = _toDouble(value).toStringAsFixed(2);
            return Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PKR $amount',
                      style: TextStyle(
                        fontSize: 15,
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return SafeArea(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.9,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Store Financial History',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.date_range, color: Color(0xFFE65100), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$fromText  to  $toText',
                              style: const TextStyle(
                                color: Color(0xFFE65100),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        summaryTile(
                          label: 'Gross Amount',
                          value: summary['gross_store_amount'],
                          icon: Icons.payments_outlined,
                          color: const Color(0xFF0F766E),
                        ),
                        const SizedBox(width: 10),
                        summaryTile(
                          label: 'Rider Paid',
                          value: summary['rider_store_payment'],
                          icon: Icons.local_shipping_outlined,
                          color: const Color(0xFF1D4ED8),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: entries.isEmpty
                          ? const Center(child: Text('No financial entries found'))
                          : ListView.separated(
                              itemCount: entries.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final e =
                                    (entries[i] as Map?)?.cast<String, dynamic>() ?? {};
                                final status = (e['order_status'] ?? '-').toString();
                                final statusClr = statusColor(status);
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${e['store_name'] ?? 'Store'} | Order #${e['order_number'] ?? '-'}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusClr.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              status.toUpperCase(),
                                              style: TextStyle(
                                                color: statusClr,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _fmtDateTime(e['order_date']),
                                        style: const TextStyle(
                                            color: Colors.black54, fontSize: 12),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Gross: PKR ${_toDouble(e['gross_store_amount']).toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF0F766E),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            'Rider: PKR ${_toDouble(e['rider_store_payment']).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF1D4ED8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load financial history: $e')),
      );
    }
  }
  Future<void> _openStoreStatusMessageDialog() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      final storeId = int.tryParse((_stats['store_id'] ?? '').toString());
      if (storeId == null || storeId <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Store info not loaded yet')),
        );
        return;
      }

      String initialMessage = '';
      bool initialClosed = false;
      try {
        final status = await ApiService.getStoreStatusMessage(token);
        initialMessage = (status['status_message'] ?? '').toString();
        initialClosed = status['is_closed'] == true;
      } catch (_) {}

      if (!mounted) return;
      final messageCtrl = TextEditingController(text: initialMessage);
      bool isClosed = initialClosed;
      bool saving = false;

      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return AlertDialog(
                title: const Text('Update Store Status'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                                statusMessage: messageCtrl.text.trim(),
                                isClosed: isClosed,
                              );
                              if (!mounted || !ctx.mounted) return;
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Store message updated'),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              setDialogState(() => saving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to save: $e')),
                              );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open store message dialog: $e')),
      );
    }
  }

  void _logout() {
    Provider.of<AuthProvider>(context, listen: false).logout();
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0, // Remove shadow to blend with body container
        title: const Text('Store Dashboard'),
        actions: [
          const NotificationBellWidget(),
          IconButton(
            icon: const Icon(Icons.query_stats),
            tooltip: 'Financial History',
            onPressed: _openStoreFinancialHistory,
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadOrders,
              child: Column(
                children: [
                  // Dashboard Stats Header
                  Container(
                    color: primaryColor,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        _buildDashboardStats(),
                        const SizedBox(height: 10),
                        TabBar(
                          controller: _tabController,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white70,
                          indicatorColor: Colors.white,
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicatorWeight: 3,
                          tabs: const [
                            Tab(text: 'New Orders'),
                            Tab(text: 'Active'),
                            Tab(text: 'History'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Order Lists
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOrderList(_pendingOrders, showActions: true),
                        _buildOrderList(_activeOrders, showActions: true),
                        _buildOrderList(_historyOrders, showActions: false),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildBottomActionItem(
              icon: Icons.inventory_2_outlined,
              label: 'Products',
              onTap: () => Navigator.of(context).pushNamed('/manage-products'),
            ),
            _buildBottomActionItem(
              icon: Icons.campaign_outlined,
              label: 'Offers',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OfferCampaignsScreen(
                    isAdmin: false,
                    initialStoreId: int.tryParse(
                      (_stats['store_id'] ?? '').toString(),
                    ),
                  ),
                ),
              ),
            ),
            _buildBottomActionItem(
              icon: Icons.flag_outlined,
              label: 'Status',
              onTap: _openStoreStatusMessageDialog,
            ),
            _buildBottomActionItem(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Financial',
              onTap: _openStoreFinancialHistory,
            ),
            _buildBottomActionItem(
              icon: Icons.refresh,
              label: 'Refresh',
              onTap: _loadOrders,
            ),
            _buildBottomActionItem(
              icon: Icons.key_outlined,
              label: 'Password',
              onTap: () => Navigator.of(context).pushNamed('/change-password'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 21,
              color: const Color(0xFFE65100),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE65100),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardStats() {
    if (_stats.isEmpty) return const SizedBox.shrink();

    final storeName = _stats['store_name'] ?? 'Loading...';
    final storeId = _stats['store_id']?.toString() ?? '-';
    final ownerName = (_stats['owner_name'] ?? 'N/A').toString();
    final ownerEmail = (_stats['owner_email'] ?? 'N/A').toString();
    final ownerPhone = (_stats['owner_phone'] ?? 'N/A').toString();
    final paymentTerm = (_stats['payment_term'] ?? '').toString().trim();
    final totalOrders = _stats['total_orders']?.toString() ?? '0';
    final delivered = _stats['delivered']?.toString() ?? '0';
    final preparing = _stats['preparing']?.toString() ?? '0';
    final ready = _stats['ready']?.toString() ?? '0';
    final balance = double.tryParse(_stats['received_balance']?.toString() ?? '0')
            ?.toStringAsFixed(2) ??
        '0.00';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth <= 340;
              final leftInfo = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$storeName ($storeId)',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Store Dashboard',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Owner: $ownerName',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Email: $ownerEmail',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                    ),
                  ),
                  Text(
                    'Phone: $ownerPhone',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                    ),
                  ),
                ],
              );

              final receivable = Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Net Receivable',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  Text(
                    'PKR $balance',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leftInfo,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: receivable),
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: leftInfo),
                  const SizedBox(width: 12),
                  receivable,
                ],
              );
            },
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem('Total Orders', totalOrders, Colors.blue, flex: 2),
              _buildStatItem('Delivered', delivered, Colors.green, flex: 2),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem('Preparing', preparing, Colors.orange, flex: 2),
              _buildStatItem('Ready', ready, Colors.purple, flex: 2),
            ],
          ),
          if (paymentTerm.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE65100), width: 0.8),
                ),
                child: Text(
                  paymentTerm,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFFE65100),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderList(List<dynamic> orders, {required bool showActions}) {
    if (orders.isEmpty) {
      return const Center(child: Text('No orders found'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        return _buildOrderCard(orders[index], showActions);
      },
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, bool showActions) {
    // Use item_status if available (specific to this store), otherwise fallback to global order status
    String displayStatus = order['status'] ?? 'unknown';
    final items = (order['items'] as List?) ?? [];
    
    if (items.isNotEmpty && items[0]['item_status'] != null) {
      displayStatus = items[0]['item_status'];
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${order['order_number']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (order['rider_first_name'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.delivery_dining,
                                size: 16,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Rider: ${order['rider_first_name']}',
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(displayStatus).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _getStatusColor(displayStatus)),
                  ),
                  child: Text(
                    displayStatus.toUpperCase(),
                    style: TextStyle(
                      color: _getStatusColor(displayStatus),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '${item['quantity']}x ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Text(
                        '${item['product_name'] ?? 'Product'}${item['variant_label'] != null ? ' (${item['variant_label']})' : ''}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Customer: ${order['first_name']} ${order['last_name']}',
              style: const TextStyle(color: Colors.grey),
            ),
            if (showActions) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: _buildActionButtons(order, displayStatus),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActionButtons(Map<String, dynamic> order, String currentStatus) {
    final id = order['id'];
    List<Widget> buttons = [];

    final hasRider = order['rider_id'] != null;
    if (currentStatus == 'pending' || currentStatus == 'confirmed' || currentStatus == 'preparing') {
      buttons.add(
        ElevatedButton(
          onPressed: () => _updateStatus(id, 'ready'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text(
            'Mark Ready',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    } else if ((currentStatus == 'ready' || currentStatus == 'ready_for_pickup') && hasRider) {
      buttons.add(
        ElevatedButton(
          onPressed: () => _updateStatus(id, 'picked_up'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          child: const Text(
            'Confirm Picked Up',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return buttons;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'out_for_delivery':
      case 'picked_up': // Treat as out for delivery visually
        return Colors.blue;
      case 'preparing':
        return Colors.orange;
      case 'ready':
        return Colors.indigo;
      case 'ready_for_pickup':
        return Colors.cyan;
      case 'pending':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }
}

