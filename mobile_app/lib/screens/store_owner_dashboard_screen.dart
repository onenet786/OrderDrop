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
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0, // Remove shadow to blend with body container
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Dashboard Stats Header
                Container(
                  color: primaryColor,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      _buildDashboardStats(),
                      const SizedBox(height: 16),
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
    );
  }

  Widget _buildDashboardStats() {
    if (_stats.isEmpty) return const SizedBox.shrink();

    final storeName = _stats['store_name'] ?? 'Loading...';
    final storeId = _stats['store_id']?.toString() ?? '-';
    final totalOrders = _stats['total_orders']?.toString() ?? '0';
    final delivered = _stats['delivered']?.toString() ?? '0';
    final preparing = _stats['preparing']?.toString() ?? '0';
    final ready = _stats['ready']?.toString() ?? '0';
    final totalAmount =
        double.tryParse(_stats['total_amount']?.toString() ?? '0')
                ?.toStringAsFixed(2) ??
            '0.00';
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
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Store ID: $storeId',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Balance',
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
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem('Total Orders', totalOrders, Colors.blue),
              _buildStatItem('Delivered', delivered, Colors.green),
              _buildStatItem('Preparing', preparing, Colors.orange),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem('Ready', ready, Colors.purple),
              _buildStatItem('Revenue', 'PKR $totalAmount', Colors.teal, flex: 2),
            ],
          ),
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

    if (currentStatus == 'pending' || currentStatus == 'confirmed') {
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
    } else if (currentStatus == 'preparing') {
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
    } else if (currentStatus == 'ready') {
      buttons.add(
        ElevatedButton(
          onPressed: () => _updateStatus(id, 'ready_for_pickup'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          child: const Text(
            'Ready to Pick Up',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    } else if (currentStatus == 'ready_for_pickup' && order['rider_id'] != null) {
      // Only show "Picked Up" if a rider is assigned
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
