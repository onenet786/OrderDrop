import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/notification_bell_widget.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  bool _isLoading = true;
  List<dynamic> _orders = [];
  String? _error;
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

    final message = notification['message'] as String? ?? 'Order update';
    final type = notification['type'] as String?;

    if (type == 'order_update') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 5),
        ),
      );
      _fetchOrders();
    } else if (type == 'payment_status_update') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Payment status updated'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
      _fetchOrders();
    } else if (type == 'order_completed') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
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
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _makeCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch dialer')),
        );
      }
    }
  }

  Future<void> _sendSms(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'sms',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch SMS app')),
        );
      }
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final Uri whatsappUri = Uri.parse("https://wa.me/$cleanPhone");

    if (await canLaunchUrl(whatsappUri)) {
      await launchUrl(whatsappUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch WhatsApp')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final userName = authProvider.user?.firstName ?? 'User';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
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
        actions: [
          const NotificationBellWidget(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchOrders,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchOrders,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Error: $_error'),
                        ElevatedButton(
                          onPressed: _fetchOrders,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _orders.isEmpty
                    ? const Center(child: Text('No orders found.'))
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Text(
                                  'Welcome, $userName',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _orders.length,
                              itemBuilder: (context, index) {
                                final order = _orders[index];
                                return _buildOrderCard(order);
                              },
                            ),
                          ),
                        ],
                      ),
              ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final isGroup = order['is_group'] == true;
    final subOrders = order['sub_orders'] as List?;
    final orderNumber = order['order_number']?.toString() ?? '';
    final isExpanded = _expandedOrders.contains(orderNumber);
    
    final deliveryFee = double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0.0;
    final grandTotal = double.tryParse(order['total_amount']?.toString() ?? '0') ?? 0.0;
    final subtotal = grandTotal - deliveryFee;

    if (isGroup && subOrders != null) {
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
                          'Order $orderNumber',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue),
                          ),
                          child: const Text(
                            'MULTIPLE STORES',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.info_outline,
                      color: Colors.blue,
                    ),
                    onPressed: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedOrders.remove(orderNumber);
                        } else {
                          _expandedOrders.add(orderNumber);
                        }
                      });
                    },
                    tooltip: isExpanded ? 'Hide items' : 'Show items',
                  ),
                ],
              ),
              const Divider(),
              _buildInfoRow('Subtotal', 'PKR $subtotal'),
              _buildInfoRow('Delivery Fee', 'PKR $deliveryFee'),
              _buildInfoRow('Grand Total', 'PKR $grandTotal', isBold: true, valueColor: Colors.blue),
              _buildInfoRow('Address', order['delivery_address'] ?? 'N/A'),
              if (isExpanded) ...[
                const SizedBox(height: 12),
                const Text(
                  'Shipments:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                ...subOrders.map<Widget>((sub) {
                  final items = sub['items'] as List? ?? [];
                  double storeTotal = 0;
                  for (var item in items) {
                    storeTotal += (double.tryParse(item['price']?.toString() ?? '0') ?? 0.0) * (int.tryParse(item['quantity']?.toString() ?? '1') ?? 1);
                  }
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                sub['store_name'] ?? 'Store',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusBadge(sub['status'] ?? 'pending'),
                          ],
                        ),
                        if (sub['rider_phone'] != null) ...[
                           const SizedBox(height: 4),
                           Row(
                             children: [
                               const Icon(Icons.delivery_dining, size: 14, color: Colors.grey),
                               const SizedBox(width: 4),
                               Expanded(
                                 child: Text(
                                   "${sub['rider_first_name'] ?? ''} ${sub['rider_last_name'] ?? ''}".trim(),
                                   style: const TextStyle(fontSize: 12, color: Colors.grey),
                                   overflow: TextOverflow.ellipsis,
                                   maxLines: 2,
                                 ),
                               ),
                             ],
                           )
                        ],
                        const SizedBox(height: 8),
                        const Text(
                          'Items:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        ...items.map<Widget>((item) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${item['quantity']}x ${item['product_name']} ${item['variant_label'] != null ? '(${item['variant_label']})' : ''}",
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                                Text(
                                  "PKR ${(double.tryParse(item['price'].toString()) ?? 0.0) * (int.tryParse(item['quantity'].toString()) ?? 1)}",
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.blue),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: Colors.grey[300]!)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Store Total:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                              ),
                              Flexible(
                                child: Text(
                                  'PKR $storeTotal',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      );
    }

    final status = order['status'] ?? 'pending';
    final riderPhone = order['rider_phone'];
    final riderName = "${order['rider_first_name'] ?? ''} ${order['rider_last_name'] ?? ''}".trim();

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
                        'Order $orderNumber',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _buildStatusBadge(status),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.info_outline,
                    color: Colors.blue,
                  ),
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedOrders.remove(orderNumber);
                      } else {
                        _expandedOrders.add(orderNumber);
                      }
                    });
                  },
                  tooltip: isExpanded ? 'Hide items' : 'Show items',
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow('Store', order['store_name'] ?? 'N/A', maxLines: 2),
            _buildInfoRow('Subtotal', 'PKR $subtotal'),
            _buildInfoRow('Delivery Fee', 'PKR $deliveryFee'),
            _buildInfoRow('Grand Total', 'PKR $grandTotal', isBold: true, valueColor: Colors.blue),
            _buildInfoRow('Address', order['delivery_address'] ?? 'N/A', maxLines: 3),
            if (order['rider_location'] != null)
              _buildInfoRow('Rider Location', order['rider_location']),
            
            if (isExpanded) ...[
              const SizedBox(height: 12),
              const Text(
                'Items:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ...(order['items'] as List? ?? []).map<Widget>((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${item['quantity']}x ${item['product_name']} ${item['variant_label'] != null ? '(${item['variant_label']})' : ''}",
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      Text(
                        "PKR ${(double.tryParse(item['price'].toString()) ?? 0.0) * (int.tryParse(item['quantity'].toString()) ?? 1)}",
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.blue),
                      ),
                    ],
                  ),
                );
              }),
            ],

            if (riderPhone != null && riderPhone.toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rider: $riderName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _contactButton(
                            icon: Icons.phone,
                            color: Colors.blue,
                            label: 'Call',
                            onPressed: () => _makeCall(riderPhone.toString()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _contactButton(
                            icon: Icons.message,
                            color: Colors.orange,
                            label: 'SMS',
                            onPressed: () => _sendSms(riderPhone.toString()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _contactButton(
                            icon: Icons.chat,
                            color: Colors.green,
                            label: 'WhatsApp',
                            onPressed: () => _openWhatsApp(riderPhone.toString()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'pending':
        color = Colors.orange;
        break;
      case 'confirmed':
        color = Colors.blue;
        break;
      case 'preparing':
        color = Colors.purple;
        break;
      case 'ready':
        color = Colors.indigo;
        break;
      case 'ready_for_pickup':
        color = Colors.cyan;
        break;
      case 'picked_up':
      case 'out_for_delivery':
        color = Colors.blue;
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        status.toUpperCase().replaceAll('_', ' '),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {int maxLines = 1, bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: valueColor,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: maxLines,
            ),
          ),
        ],
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
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
