import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/notification_bell_widget.dart';
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

    final message = notification['message'] as String? ?? 'New notification';
    final type = notification['type'] as String?;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'REFRESH',
          textColor: Colors.white,
          onPressed: _loadOrders,
        ),
      ),
    );

    if (type == 'new_order' || type == 'rider_assigned') {
      _loadOrders();
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

      final orders = await ApiService.getStoreOrders(token);

      if (mounted) {
        setState(() {
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
                    o['status'] == 'out_for_delivery',
              )
              .toList();
          _historyOrders = orders
              .where(
                (o) => o['status'] == 'delivered' || o['status'] == 'cancelled',
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order marked as ${newStatus.toUpperCase()}')),
        );
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

  void _logout() {
    Provider.of<AuthProvider>(context, listen: false).logout();
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Store Dashboard'),
        actions: [
          const NotificationBellWidget(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadOrders),
          IconButton(
            icon: const Icon(Icons.key),
            onPressed: () =>
                Navigator.of(context).pushNamed('/change-password'),
            tooltip: 'Change Password',
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
        bottom: TabBar(
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOrderList(_pendingOrders, showActions: true),
                _buildOrderList(_activeOrders, showActions: true),
                _buildOrderList(_historyOrders, showActions: false),
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
    final status = order['status'] ?? 'unknown';
    final items = (order['items'] as List?) ?? [];

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
                    color: _getStatusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _getStatusColor(status)),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: _getStatusColor(status),
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
                children: _buildActionButtons(order),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActionButtons(Map<String, dynamic> order) {
    final status = order['status'];
    final id = order['id'];
    List<Widget> buttons = [];

    if (status == 'pending' || status == 'confirmed') {
      buttons.add(
        ElevatedButton(
          onPressed: () => _updateStatus(id, 'preparing'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          child: const Text(
            'Start Preparing',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    } else if (status == 'preparing') {
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
        return Colors.blue;
      case 'preparing':
        return Colors.orange;
      case 'ready':
        return Colors.indigo;
      case 'pending':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }
}
