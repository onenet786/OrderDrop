import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/notification_bell_widget.dart';
import 'login_screen.dart';

class RiderDashboardScreen extends StatefulWidget {
  const RiderDashboardScreen({super.key});

  @override
  State<RiderDashboardScreen> createState() => _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends State<RiderDashboardScreen>
    with SingleTickerProviderStateMixin {
  final Logger _logger = Logger();
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic>? _riderProfile;
  List<dynamic> _assignedDeliveries = [];
  List<dynamic> _completedDeliveries = [];
  String _currentLocation = 'Getting location...';
  double _walletBalance = 0.0;
  Timer? _locationTrackingTimer;
  String _selectedStatsPeriod = 'daily';
  Map<String, dynamic>? _walletStats;
  bool _isLoadingStats = false;

  Future<void> _makeCall(String phoneNumber) async {
    final cleaned = phoneNumber.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No valid phone number')));
      }
      return;
    }
    final uri = Uri(scheme: 'tel', path: cleaned);
    if (await canLaunchUrl(uri)) {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch dialer')),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dialer app not available')));
    }
  }

  Future<void> _sendSms(String phoneNumber) async {
    final cleaned = phoneNumber.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No valid phone number')));
      }
      return;
    }
    // Try 'sms:' first, then fall back to 'smsto:' for wider compatibility
    final smsUri = Uri(scheme: 'sms', path: cleaned);
    final smstoUri = Uri(scheme: 'smsto', path: cleaned);

    bool launched = false;
    if (await canLaunchUrl(smsUri)) {
      launched = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(smstoUri)) {
      launched = await launchUrl(
        smstoUri,
        mode: LaunchMode.externalApplication,
      );
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('SMS app not available')));
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch WhatsApp')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
    _startLocationTracking();
    _setupNotifications();
  }

  void _setupNotifications() {
    NotificationService.initialize(
      onNotification: (data) {
        _handleNotification(data);
      },
    );

    // Connect to socket for real-time updates
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user != null) {
      NotificationService.connect(authProvider.user!.id, 'rider');
    }
  }

  void _handleNotification(Map<String, dynamic> notification) {
    if (!mounted) return;

    final nestedData = (notification['data'] is Map<String, dynamic>)
        ? notification['data'] as Map<String, dynamic>
        : null;
    final type =
        (notification['type'] ?? nestedData?['type'])?.toString().toLowerCase();
    final message = (notification['message'] ??
                nestedData?['message'] ??
                notification['title'] ??
                'New notification')
            .toString();

    final bool hasAssignmentPayload = notification['rider_id'] != null ||
        nestedData?['rider_id'] != null ||
        notification['order_number'] != null ||
        nestedData?['order_number'] != null;

    final bool shouldRefresh = type == 'assigned' ||
        type == 'rider_notification' ||
        type == 'order_assigned' ||
        type == 'refresh_orders' ||
        type == 'new_order' ||
        type == 'order_status_update' ||
        type == 'payment_status_update' ||
        hasAssignmentPayload;

    if (shouldRefresh) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
        ),
      );
      _loadAllData();
      _tabController.animateTo(0); // Switch to Home tab
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _locationTrackingTimer?.cancel();
    NotificationService.disconnect();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      await Future.wait([
        _loadProfile(token),
        _loadDeliveries(token, 'assigned'),
        _loadDeliveries(token, 'completed'),
        _getCurrentLocation(),
        _loadWalletBalance(token),
        _loadWalletStats(token, 'daily'),
      ]);
    } catch (e) {
      _logger.e('Error loading rider data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadProfile(String token) async {
    try {
      final data = await ApiService.getRiderProfile(token);
      if (data['success'] == true) {
        setState(() {
          _riderProfile = data['rider'];
        });
      }
    } catch (e) {
      _logger.e('Error loading profile: $e');
    }
  }

  Future<void> _loadDeliveries(String token, String status) async {
    try {
      final deliveries = await ApiService.getRiderDeliveries(token, status);
      setState(() {
        if (status == 'assigned') {
          _assignedDeliveries = deliveries;
        } else {
          _completedDeliveries = deliveries;
        }
      });
    } catch (e) {
      _logger.e('Error loading $status deliveries: $e');
    }
  }

  Future<void> _loadWalletBalance(String token) async {
    try {
      _logger.d('Loading wallet balance...');
      final data = await ApiService.getWalletBalance(token);
      _logger.d('Wallet API response: $data');

      if (data['success'] != true) {
        _logger.w('Wallet API returned success=false');
        return;
      }

      final wallet = data['wallet'];
      if (wallet == null) {
        _logger.w('Wallet object is null in response');
        return;
      }

      final balance = wallet['balance'];
      if (balance == null) {
        _logger.w('Balance field is null in wallet object');
        setState(() {
          _walletBalance = 0.0;
        });
        return;
      }

      _logger.d('Extracted balance: $balance (type: ${balance.runtimeType})');
      final parsedBalance = double.tryParse(balance.toString());
      _logger.d('Parsed balance: $parsedBalance');

      setState(() {
        _walletBalance = parsedBalance ?? 0.0;
        _logger.d('Set wallet balance to: $_walletBalance');
      });
    } catch (e) {
      _logger.e('Error loading wallet balance: $e');
      setState(() {
        _walletBalance = 0.0;
      });
    }
  }

  Future<void> _loadWalletStats(String token, String period) async {
    try {
      setState(() => _isLoadingStats = true);
      _logger.d('Loading wallet stats for period: $period');
      final data = await ApiService.getRiderWalletStats(token, period);
      _logger.d('Wallet stats API response: $data');

      if (data['success'] != true) {
        _logger.w('Wallet stats API returned success=false');
        return;
      }

      setState(() {
        _walletStats = data['stats'];
        _selectedStatsPeriod = period;
      });
    } catch (e) {
      _logger.e('Error loading wallet stats: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load stats: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  Future<void> _refreshLocation() async {
    setState(() => _currentLocation = 'Updating...');
    await _getCurrentLocation();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location updated successfully!')),
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _currentLocation = 'Location services disabled');
        }
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() => _currentLocation = 'Location permission denied');
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(
            () => _currentLocation = 'Location permission permanently denied',
          );
        }
        return;
      }

      Position position = await Geolocator.getCurrentPosition();

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (mounted && placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          String address = '';
          if (place.street != null && place.street!.isNotEmpty) {
            address += place.street!;
          }
          if (place.locality != null && place.locality!.isNotEmpty) {
            if (address.isNotEmpty) address += ', ';
            address += place.locality!;
          }

          if (address.isEmpty) {
            address =
                '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
          }

          setState(() {
            _currentLocation = address;
          });
        } else if (mounted) {
          setState(() {
            _currentLocation =
                '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _currentLocation =
                '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
          });
        }
      }
    } catch (e) {
      _logger.e('Error getting location: $e');
      if (mounted) setState(() => _currentLocation = 'Error getting location');
    }
  }

  void _startLocationTracking() {
    _locationTrackingTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) async {
      if (_assignedDeliveries.isNotEmpty) {
        await _sendLocationToServer();
      }
    });
  }

  Future<void> _sendLocationToServer() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition();

      await ApiService.updateRiderLocation(
        token,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      _logger.d(
        'Location sent to server: ${position.latitude}, ${position.longitude}',
      );
    } catch (e) {
      _logger.e('Error sending location to server: $e');
    }
  }

  Future<void> _markAsDelivered(int orderId) async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      await ApiService.markOrderAsDelivered(token, orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order marked as delivered!')),
        );
        _loadAllData(); // Refresh list
      }
    } catch (e) {
      _logger.e('Error marking delivered: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
      }
    }
  }

  Future<void> _markPaymentReceived(int orderId) async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      await ApiService.updatePaymentStatus(token, orderId, 'paid');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment marked as received! Wallet updated.'),
          ),
        );
        _loadAllData();
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          await _loadWalletBalance(token);
        }
      }
    } catch (e) {
      _logger.e('Error updating payment: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update payment: $e')));
      }
    }
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
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
        title: const Text('Rider Dashboard'),
        actions: [
          const NotificationBellWidget(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAllData),
          IconButton(
            icon: const Icon(Icons.key),
            onPressed: () =>
                Navigator.of(context).pushNamed('/change-password'),
            tooltip: 'Change Password',
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Rider Info Section
                  _buildRiderInfoCard(),

                  // Tabs
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: Colors.blue,
                    unselectedLabelColor: Colors.grey,
                    tabs: const [
                      Tab(text: 'Home'),
                      Tab(text: 'History'),
                      Tab(text: 'Wallet'),
                      Tab(text: 'Profile'),
                    ],
                  ),

                  // Tab Content
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDeliveriesList(_assignedDeliveries, true),
                        _buildDeliveriesList(_completedDeliveries, false),
                        _buildWalletTab(),
                        _buildProfileTab(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildRiderInfoCard() {
    final name = _riderProfile == null
        ? 'Rider'
        : '${_riderProfile?['first_name'] ?? ''} ${_riderProfile?['last_name'] ?? ''}'
              .trim()
              .isEmpty
        ? (_riderProfile?['first_name'] ?? 'Rider')
        : '${_riderProfile?['first_name'] ?? ''} ${_riderProfile?['last_name'] ?? ''}'
              .trim();
    final vehicle = _riderProfile?['vehicle_type'] ?? 'N/A';

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.blue.shade600, Colors.indigo.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, $name',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.directions_bike,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Vehicle: $vehicle',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.location_on, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Tracking',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveriesList(List<dynamic> deliveries, bool isAssigned) {
    if (deliveries.isEmpty) {
      return const Center(child: Text('No deliveries found.'));
    }

    final Map<String, List<dynamic>> deliveriesByStore = {};
    for (var delivery in deliveries) {
      final storeName = delivery['store_name'] ?? 'Unknown Store';
      if (!deliveriesByStore.containsKey(storeName)) {
        deliveriesByStore[storeName] = [];
      }
      deliveriesByStore[storeName]!.add(delivery);
    }

    final storeNames = deliveriesByStore.keys.toList();
    int totalItems = storeNames.length;
    for (var storeName in storeNames) {
      totalItems += deliveriesByStore[storeName]!.length;
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        int currentIndex = 0;

        for (int i = 0; i < storeNames.length; i++) {
          final storeName = storeNames[i];
          final storeDeliveries = deliveriesByStore[storeName]!;

          if (currentIndex == index) {
            return Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    storeName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 20),
                    color: Colors.blueAccent,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _showStoreInfo(storeName, storeDeliveries),
                  ),
                ],
              ),
            );
          }
          currentIndex++;

          for (int j = 0; j < storeDeliveries.length; j++) {
            if (currentIndex == index) {
              return _buildDeliveryCard(storeDeliveries[j], isAssigned);
            }
            currentIndex++;
          }
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildDeliveryCard(Map<String, dynamic> delivery, bool isAssigned) {
    final status = delivery['status'] ?? 'unknown';
    final paymentStatus = delivery['payment_status'] ?? 'pending';
    final customerPhone = (delivery['phone'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${delivery['order_number']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
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
                ),
              ],
            ),
            const Divider(),

            // Details
            _buildDetailRow(
              'Customer',
              '${delivery['first_name']} ${delivery['last_name']}',
            ),

            // Simplified Summary Card
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Grand Total',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                      ),
                      Text(
                        'PKR ${delivery['total_amount']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showOrderInfo(delivery),
                    icon: const Icon(Icons.receipt_long, size: 16),
                    label: const Text('Summary'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Address', '${delivery['delivery_address']}'),
            _buildDetailRow('Phone', '${delivery['phone'] ?? 'N/A'}'),
            if (customerPhone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _contactAction(
                      icon: Icons.phone,
                      color: Colors.blue,
                      label: 'Call',
                      onTap: () => _makeCall(customerPhone),
                    ),
                    _contactAction(
                      icon: Icons.message,
                      color: Colors.orange,
                      label: 'SMS',
                      onTap: () => _sendSms(customerPhone),
                    ),
                    _contactAction(
                      icon: Icons.chat,
                      color: Colors.green,
                      label: 'WhatsApp',
                      onTap: () => _openWhatsApp(customerPhone),
                    ),
                  ],
                ),
              ),
            _buildDetailRow(
              'Payment',
              paymentStatus,
              valueColor: paymentStatus == 'paid'
                  ? Colors.green
                  : Colors.orange,
            ),

            if (delivery['rider_location'] != null)
              _buildDetailRow('My Location', '${delivery['rider_location']}'),

            // Actions
            if (isAssigned && status == 'out_for_delivery') ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _markAsDelivered(delivery['id']),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Mark Delivered'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (paymentStatus != 'paid')
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _markPaymentReceived(delivery['id']),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Payment Recvd'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.black87,
                fontWeight: valueColor != null
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
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
      case 'pending':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  Widget _contactAction({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 36,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ),
    );
  }

  void _showStoreInfo(String storeName, List<dynamic> deliveries) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  storeName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
                Text(
                  '${deliveries.length} orders from this store',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: deliveries.length,
                    itemBuilder: (context, index) {
                      final delivery = deliveries[index];
                      final items = (delivery['items'] as List?) ?? [];

                      // Filter items for THIS store
                      final storeItems = items
                          .where(
                            (item) =>
                                (item['store_name'] ??
                                    delivery['store_name']) ==
                                storeName,
                          )
                          .toList();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Order #${delivery['order_number']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    delivery['status']
                                            ?.toString()
                                            .toUpperCase() ??
                                        '',
                                    style: TextStyle(
                                      color: _getStatusColor(
                                        delivery['status'] ?? '',
                                      ),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              ...storeItems.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${item['quantity']}x ',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text('${item['product_name']}'),
                                      ),
                                      Text('PKR ${item['price']}'),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Address: ${delivery['delivery_address']}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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

  void _showOrderInfo(Map<String, dynamic> delivery) {
    final items = (delivery['items'] as List?) ?? [];
    final deliveryStoreName = delivery['store_name'] ?? 'Unknown Store';

    Map<String, List<dynamic>> itemsByStore = {};
    for (var item in items) {
      final storeName = item['store_name'] ?? deliveryStoreName;
      if (!itemsByStore.containsKey(storeName)) {
        itemsByStore[storeName] = [];
      }
      itemsByStore[storeName]!.add(item);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long, color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Order #${delivery['order_number']}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow('Status', '${delivery['status']}'),
                  _buildDetailRow(
                    'Payment',
                    '${delivery['payment_status'] ?? 'unknown'}',
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const Text(
                    'Customer Details',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    'Name',
                    '${delivery['first_name'] ?? ''} ${delivery['last_name'] ?? ''}',
                  ),
                  _buildDetailRow('Phone', '${delivery['phone'] ?? 'N/A'}'),
                  _buildDetailRow(
                    'Delivery Address',
                    '${delivery['delivery_address'] ?? 'N/A'}',
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const Text(
                    'Items by Store',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...itemsByStore.entries.map((entry) {
                    final storeName = entry.key;
                    final storeItems = entry.value;
                    double storeSubtotal = 0;
                    for (var item in storeItems) {
                      final price =
                          double.tryParse(item['price']?.toString() ?? '0') ??
                          0;
                      final quantity =
                          int.tryParse(item['quantity']?.toString() ?? '1') ??
                          1;
                      storeSubtotal += price * quantity;
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).primaryColor.withAlpha((0.15 * 255).round()),
                            borderRadius: BorderRadius.circular(4),
                            border: Border(
                              left: BorderSide(
                                color: Theme.of(context).primaryColor,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Text(
                            storeName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...storeItems.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 4, left: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item['quantity']}x ${item['product_name'] ?? 'Product'}${item['variant_label'] != null ? ' (${item['variant_label']})' : ''}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                Text(
                                  'PKR ${(double.tryParse(item['price']?.toString() ?? '0') ?? 0) * (int.tryParse(item['quantity']?.toString() ?? '1') ?? 1)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 4,
                            bottom: 12,
                            left: 8,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  'Subtotal ($storeName):',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'PKR ${storeSubtotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 12),
                  const Divider(),
                  const Text(
                    'Pricing Breakdown',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (ctx) {
                      double itemsSubtotal = 0;
                      final storeIds = <int>{};
                      final allItems = (delivery['items'] as List?) ?? [];

                      for (var item in allItems) {
                        itemsSubtotal +=
                            (double.tryParse(
                                  item['price']?.toString() ?? '0',
                                ) ??
                                0) *
                            (int.tryParse(
                                  item['quantity']?.toString() ?? '1',
                                ) ??
                                1);
                        final storeId = item['store_id'] as int?;
                        if (storeId != null) storeIds.add(storeId);
                      }

                      final deliveryFee =
                          double.tryParse(
                            delivery['delivery_fee']?.toString() ?? '0',
                          ) ??
                          0;
                      final grandTotal = itemsSubtotal + deliveryFee;
                      final numStores = storeIds.isNotEmpty
                          ? storeIds.length
                          : 1;

                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Items Subtotal:',
                                style: TextStyle(fontSize: 13),
                              ),
                              Flexible(
                                child: Text(
                                  'PKR ${itemsSubtotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Delivery Fee ($numStores store${numStores > 1 ? 's' : ''}):',
                                style: const TextStyle(fontSize: 13),
                              ),
                              Flexible(
                                child: Text(
                                  'PKR ${deliveryFee.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Divider(color: Colors.grey[400]),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Grand Total:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  'PKR ${grandTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWalletTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [Colors.green.shade600, Colors.teal.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Wallet Balance',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet,
                            color: Colors.white.withValues(alpha: 0.8),
                            size: 28,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.refresh,
                              color: Colors.white,
                            ),
                            onPressed: () async {
                              final token = Provider.of<AuthProvider>(
                                context,
                                listen: false,
                              ).token;
                              if (token != null) {
                                await _loadWalletBalance(token);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Wallet updated'),
                                    ),
                                  );
                                }
                              }
                            },
                            iconSize: 20,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'PKR ${_walletBalance.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Tap refresh to update balance',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Financial Statistics',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildPeriodSelector(),
          const SizedBox(height: 16),
          if (_isLoadingStats)
            const Center(child: CircularProgressIndicator())
          else if (_walletStats != null)
            _buildStatsCards()
          else
            Card(
              color: Colors.grey.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('No stats available')),
              ),
            ),
          const SizedBox(height: 24),
          _walletBalance == 0
              ? Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue.shade600),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'No earnings yet',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Complete deliveries and mark payments as received to earn',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
          const SizedBox(height: 24),
          const Text(
            'Wallet Information',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWalletInfoRow('Account Type', 'Rider Wallet'),
                  const Divider(),
                  _buildWalletInfoRow('Status', 'Active'),
                  const Divider(),
                  _buildWalletInfoRow(
                    'Balance',
                    'PKR ${_walletBalance.toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'How it works',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHowItWorksItem(
                    '1',
                    'Complete Deliveries',
                    'Accept and complete delivery orders',
                  ),
                  const SizedBox(height: 12),
                  _buildHowItWorksItem(
                    '2',
                    'Mark Payment Received',
                    'Confirm when customer pays you',
                  ),
                  const SizedBox(height: 12),
                  _buildHowItWorksItem(
                    '3',
                    'Wallet Updated',
                    'Amount instantly credited to your wallet',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildWalletInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildHowItWorksItem(String number, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: Colors.blue.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'daily', label: Text('Daily')),
              ButtonSegment<String>(value: 'weekly', label: Text('Weekly')),
              ButtonSegment<String>(value: 'monthly', label: Text('Monthly')),
            ],
            selected: <String>{_selectedStatsPeriod},
            onSelectionChanged: (Set<String> newSelection) async {
              final token = Provider.of<AuthProvider>(
                context,
                listen: false,
              ).token;
              if (token != null) {
                await _loadWalletStats(token, newSelection.first);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    if (_walletStats == null) {
      return const SizedBox.shrink();
    }

    final stats = _walletStats!;
    final cashReceived = _parseDouble(stats['cash_received']);
    final deliveryFees = _parseDouble(stats['total_delivery_fees']);
    // Backend already returns cash_received as (cash total - delivery fee),
    // so do not subtract delivery fees again on client.
    final netCashReceived = cashReceived;
    final paymentSummary =
        (stats['payment_summary'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Cash Received (Net)',
                value: 'PKR ${netCashReceived.toStringAsFixed(2)}',
                icon: Icons.payments_outlined,
                backgroundColor: Colors.green.shade50,
                iconColor: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'Delivery Fees',
                value: 'PKR ${deliveryFees.toStringAsFixed(2)}',
                icon: Icons.local_shipping,
                backgroundColor: Colors.blue.shade50,
                iconColor: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (paymentSummary.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payment Summary',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...paymentSummary.map((summary) {
                    final method = summary['payment_method'] ?? 'Unknown';
                    final count = summary['order_count'] ?? 0;
                    final amount = _parseDouble(summary['total_amount']);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                method.replaceFirst(
                                  method[0],
                                  method[0].toUpperCase(),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '$count order${count != 1 ? 's' : ''}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'PKR ${amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color backgroundColor,
    required Color iconColor,
  }) {
    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Icon(icon, color: iconColor, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: iconColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    final r = _riderProfile;
    final photoUrl = (r?['image_url'] as String?) ?? '';
    final idCardUrl = (r?['id_card_url'] as String?) ?? '';

    // Image tile without label (clean top row)
    Widget imageTile(String? url) {
      final resolved = (url == null || url.isEmpty)
          ? null
          : ApiService.getImageUrl(url);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 162,
          color: Colors.grey[200],
          child: resolved == null
              ? _imagePlaceholder()
              : Image.network(
                  resolved,
                  fit: BoxFit.fill,
                  errorBuilder: (ctx, err, stack) => _imagePlaceholder(),
                ),
        ),
      );
    }

    // Two-column detail row (label left, value right)
    Widget detail2Col(String label, String value, {Color? valueColor}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: valueColor ?? Colors.black87,
                  fontWeight: valueColor != null
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final fullName = '${r?['first_name'] ?? ''} ${r?['last_name'] ?? ''}'
        .trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Images row at top: user image (left), ID card (right)
              Row(
                children: [
                  Expanded(flex: 4, child: imageTile(photoUrl)),
                  const SizedBox(width: 12),
                  Expanded(flex: 6, child: imageTile(idCardUrl)),
                ],
              ),
              const SizedBox(height: 16),
              // Details with label left, value right
              detail2Col('Name', fullName.isEmpty ? 'N/A' : fullName),
              detail2Col('Email', '${r?['email'] ?? 'N/A'}'),
              detail2Col('Phone', '${r?['phone'] ?? 'N/A'}'),
              detail2Col('Vehicle', '${r?['vehicle_type'] ?? 'N/A'}'),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.blue, size: 20),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _currentLocation,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton(
                    onPressed: _refreshLocation,
                    child: const Text('Refresh'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.image_not_supported, color: Colors.grey, size: 36),
          SizedBox(height: 6),
          Text('No image', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
