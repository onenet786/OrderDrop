import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../theme/customer_palette.dart';
import '../widgets/notification_bell_widget.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const int _activeBottomIndex = 2;
  bool _isLoading = true;
  List<dynamic> _orders = [];
  String? _error;
  String _statusFilter = 'all';
  final Set<String> _expandedOrders = {};

  @override
  void initState() {
    super.initState();
    _fetchOrders();
    _setupNotifications();
  }

  void _setupNotifications() {
    NotificationService.initialize(
      onNotification: (data) {
        _handleNotification(data);
      },
    );
  }

  void _handleNotification(Map<String, dynamic> notification) {
    if (!mounted) return;

    final type = (notification['type'] ?? '').toString().toLowerCase();
    final message = (notification['message'] ?? 'Order update').toString();
    if (type == 'order_update' ||
        type == 'refresh_orders' ||
        type == 'payment_status_update' ||
        type == 'order_completed') {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor:
                type == 'payment_status_update' ? Colors.green : CustomerPalette.primaryDark,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            showCloseIcon: true,
          ),
        );
      _fetchOrders();
    }
  }

  Future<void> _fetchOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      final orders = await ApiService.getMyOrders(token);
      orders.sort((a, b) {
        final aDate = DateTime.tryParse((a['created_at'] ?? '').toString());
        final bDate = DateTime.tryParse((b['created_at'] ?? '').toString());
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _makeCall(String phoneNumber) async {
    final cleaned = phoneNumber.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not launch dialer')));
  }

  Future<void> _sendSms(String phoneNumber) async {
    final cleaned = phoneNumber.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'sms', path: cleaned);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not launch SMS app')));
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final whatsappUri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(whatsappUri)) {
      await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not launch WhatsApp')));
  }

  List<dynamic> get _visibleOrders {
    if (_statusFilter == 'all') return _orders;
    if (_statusFilter == 'active') {
      return _orders.where((order) {
        final status = (order['status'] ?? '').toString().toLowerCase();
        return status != 'delivered' && status != 'cancelled';
      }).toList();
    }
    return _orders.where((order) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      return status == 'delivered' || status == 'cancelled';
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final userName = authProvider.user?.firstName ?? 'Customer';
    final activeCount = _orders.where((o) {
      final status = (o['status'] ?? '').toString().toLowerCase();
      return status != 'delivered' && status != 'cancelled';
    }).length;
    final completedCount = _orders.where((o) {
      final status = (o['status'] ?? '').toString().toLowerCase();
      return status == 'delivered';
    }).length;

    return Scaffold(
      backgroundColor: CustomerPalette.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacementNamed('/home');
            }
          },
        ),
        title: const Text('My Orders'),
        actions: [
          const NotificationBellWidget(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchOrders),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchOrders,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildErrorState()
                : Column(
                    children: [
                      _buildSummaryCard(
                        userName: userName,
                        total: _orders.length,
                        active: activeCount,
                        completed: completedCount,
                      ),
                      _buildFilterChips(),
                      const SizedBox(height: 6),
                      Expanded(
                        child: _visibleOrders.isEmpty
                            ? const Center(child: Text('No orders found.'))
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                                itemCount: _visibleOrders.length,
                                itemBuilder: (context, index) {
                                  final order = Map<String, dynamic>.from(
                                    _visibleOrders[index] as Map,
                                  );
                                  return _buildOrderCard(order);
                                },
                              ),
                      ),
                    ],
                  ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: CustomerPalette.card,
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
            _buildBottomIcon(
              index: 0,
              icon: Icons.home_filled,
              label: 'Home',
              onTap: () => Navigator.of(context).pushReplacementNamed('/home'),
            ),
            _buildBottomIcon(
              index: 1,
              icon: Icons.storefront,
              label: 'Stores',
              onTap: () => Navigator.of(context).pushReplacementNamed('/home'),
            ),
            _buildBottomIcon(
              index: 2,
              icon: Icons.shopping_bag,
              label: 'Orders',
              onTap: () {},
            ),
            _buildBottomIcon(
              index: 3,
              icon: Icons.shopping_cart,
              label: 'Cart',
              onTap: () => Navigator.of(context).pushReplacementNamed('/cart'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomIcon({
    required int index,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final active = _activeBottomIndex == index;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color:
                  active ? CustomerPalette.primaryDark : Colors.grey.shade600,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color:
                    active ? CustomerPalette.primaryDark : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 34),
            const SizedBox(height: 8),
            Text(
              'Failed to load orders\n$_error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _fetchOrders,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String userName,
    required int total,
    required int active,
    required int completed,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CustomerPalette.primary, CustomerPalette.primaryDark],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Hello, $userName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildMetricTile('Total', '$total')),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricTile('Active', '$active')),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricTile('Delivered', '$completed')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _filterChip('all', 'All'),
          const SizedBox(width: 8),
          _filterChip('active', 'Active'),
          const SizedBox(width: 8),
          _filterChip('history', 'History'),
        ],
      ),
    );
  }

  Widget _filterChip(String id, String label) {
    final selected = _statusFilter == id;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) {
        setState(() => _statusFilter = id);
      },
      selectedColor: CustomerPalette.primaryDark,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final isGroup = order['is_group'] == true;
    final subOrders = (order['sub_orders'] as List?) ?? const [];
    final orderNumber = (order['order_number'] ?? '').toString();
    final isExpanded = _expandedOrders.contains(orderNumber);
    final status = (order['status'] ?? 'pending').toString();
    final createdAt = DateTime.tryParse((order['created_at'] ?? '').toString());
    final riderPhone = (order['rider_phone'] ?? '').toString().trim();
    final storePhone = (order['store_phone'] ?? '').toString().trim();
    final riderName =
        "${order['rider_first_name'] ?? ''} ${order['rider_last_name'] ?? ''}".trim();

    final deliveryFee = _toDouble(order['delivery_fee']);
    final grandTotal = _toDouble(order['total_amount']);
    final subtotal = (grandTotal - deliveryFee).clamp(0, double.infinity);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #$orderNumber',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        createdAt != null
                            ? _formatDateTime(createdAt)
                            : 'Date not available',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(status),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _amountBlock(
                        label: 'Subtotal',
                        value: _formatPkr(subtotal),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _amountBlock(
                        label: 'Delivery',
                        value: _formatPkr(deliveryFee),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _amountBlock(
                        label: 'Grand Total',
                        value: _formatPkr(grandTotal),
                        highlight: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _lineInfo(
                  icon: Icons.location_on_outlined,
                  label: 'Address',
                  value: (order['delivery_address'] ?? 'N/A').toString(),
                ),
                if (isGroup)
                  _lineInfo(
                    icon: Icons.store_mall_directory_outlined,
                    label: 'Shipments',
                    value: '${subOrders.length} stores',
                  )
                else
                  _lineInfo(
                    icon: Icons.storefront_outlined,
                    label: 'Store',
                    value: (order['store_name'] ?? 'N/A').toString(),
                  ),
                if ((order['payment_method'] ?? '').toString().trim().isNotEmpty)
                  _lineInfo(
                    icon: Icons.payments_outlined,
                    label: 'Payment',
                    value: '${order['payment_method']}',
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  if (isExpanded) {
                    _expandedOrders.remove(orderNumber);
                  } else {
                    _expandedOrders.add(orderNumber);
                  }
                });
              },
              icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
              label: Text(isExpanded ? 'Hide details' : 'View details'),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: isGroup
                  ? _buildGroupDetails(subOrders)
                  : _buildSingleOrderDetails(order),
            ),
            if (riderPhone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _buildRiderContact(riderName, riderPhone),
              ),
            if (storePhone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _buildStoreContact(
                  (order['store_name'] ?? 'Store').toString(),
                  storePhone,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupDetails(List subOrders) {
    if (subOrders.isEmpty) {
      return const Text('No shipment details available');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Shipment Details',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ...subOrders.map<Widget>((entry) {
          final sub = Map<String, dynamic>.from(entry as Map);
          final items = (sub['items'] as List?) ?? const [];
          final storePhone = (sub['store_phone'] ?? '').toString().trim();
          final subtotal = items.fold<double>(0.0, (sum, it) {
            final item = Map<String, dynamic>.from(it as Map);
            final qty = _toInt(item['quantity']);
            final price = _toDouble(item['price']);
            return sum + (qty * price);
          });
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4EA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFDFC9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (sub['store_name'] ?? 'Store').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _buildStatusBadge((sub['status'] ?? 'pending').toString()),
                  ],
                ),
                if (storePhone.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _makeCall(storePhone),
                      icon: const Icon(Icons.call_outlined, size: 16),
                      label: const Text('Call Store'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                ...items.map<Widget>((it) {
                  final item = Map<String, dynamic>.from(it as Map);
                  final qty = _toInt(item['quantity']);
                  final price = _toDouble(item['price']);
                  final label = (item['variant_label'] ?? '').toString().trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '$qty x ${item['product_name'] ?? 'Item'}${label.isNotEmpty ? ' ($label)' : ''}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatPkr(qty * price),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: CustomerPalette.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Store Total',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      _formatPkr(subtotal),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: CustomerPalette.primaryDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSingleOrderDetails(Map<String, dynamic> order) {
    final items = (order['items'] as List?) ?? const [];
    if (items.isEmpty) {
      return const Text('No items found for this order');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Items',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ...items.map<Widget>((entry) {
          final item = Map<String, dynamic>.from(entry as Map);
          final qty = _toInt(item['quantity']);
          final price = _toDouble(item['price']);
          final label = (item['variant_label'] ?? '').toString().trim();
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4EA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '$qty x ${item['product_name'] ?? 'Item'}${label.isNotEmpty ? ' ($label)' : ''}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatPkr(qty * price),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: CustomerPalette.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRiderContact(String riderName, String riderPhone) {
    final displayName = riderName.trim().isEmpty ? 'Assigned Rider' : riderName;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7EF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFDFC9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rider: $displayName',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _contactButton(
                  icon: Icons.call_outlined,
                  color: Colors.blue,
                  label: 'Call',
                  onPressed: () => _makeCall(riderPhone),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _contactButton(
                  icon: Icons.sms_outlined,
                  color: Colors.orange,
                  label: 'SMS',
                  onPressed: () => _sendSms(riderPhone),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _contactButton(
                  icon: Icons.chat_outlined,
                  color: Colors.green,
                  label: 'WhatsApp',
                  onPressed: () => _openWhatsApp(riderPhone),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStoreContact(String storeName, String storePhone) {
    final displayStore =
        storeName.trim().isEmpty ? 'Store' : storeName.trim();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F0FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCCEFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Store: $displayStore',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _contactButton(
              icon: Icons.call_outlined,
              color: Colors.deepPurple,
              label: 'Call Store',
              onPressed: () => _makeCall(storePhone),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountBlock({
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFFFEEDD) : const Color(0xFFFFF7EF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: highlight ? CustomerPalette.primaryDark : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineInfo({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey[700]),
          const SizedBox(width: 6),
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final normalized = status.toLowerCase();
    Color color;
    switch (normalized) {
      case 'pending':
        color = Colors.orange;
        break;
      case 'confirmed':
        color = CustomerPalette.primaryDark;
        break;
      case 'preparing':
        color = Colors.deepPurple;
        break;
      case 'ready':
      case 'ready_for_pickup':
        color = Colors.indigo;
        break;
      case 'picked_up':
      case 'out_for_delivery':
        color = Colors.teal;
        break;
      case 'delivered':
        color = Colors.green;
        break;
      case 'cancelled':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        status.toUpperCase().replaceAll('_', ' '),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _contactButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = months[dt.month - 1];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $m ${dt.year}, $hh:$mm';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString()) ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _formatPkr(num value) {
    final doubleV = value.toDouble();
    if (doubleV == doubleV.roundToDouble()) {
      return 'PKR ${doubleV.toInt()}';
    }
    return 'PKR ${doubleV.toStringAsFixed(2)}';
  }
}
