import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../services/api_service.dart';
import 'auth_provider.dart';

class NotificationProvider with ChangeNotifier {
  socket_io.Socket? _socket;
  final GlobalKey<NavigatorState> navigatorKey;
  AuthProvider? _authProvider;

  NotificationProvider(this.navigatorKey);

  void update(AuthProvider auth) {
    _authProvider = auth;
    _updateSocketConnection();
  }

  void _updateSocketConnection() {
    // Connect if user is authenticated (Admin, Rider, or User)
    if (_authProvider != null && _authProvider!.isAuthenticated) {
      if (_socket == null || !_socket!.connected) {
        _initSocket();
      }
    } else {
      _disconnectSocket();
    }
  }

  void _disconnectSocket() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
    }
  }

  void _initSocket() {
    if (_socket != null && _socket!.connected) return;

    // Ensure we don't have trailing slash for socket.io
    String baseUrl = ApiService.baseUrl;
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    _socket = socket_io.io(
      baseUrl,
      socket_io.OptionBuilder()
          .setTransports(['polling', 'websocket'])
          .enableAutoConnect()
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      debugPrint('Socket connected');
    });

    // Admin Notifications
    _socket!.on('new_user', (data) {
      if (_authProvider?.isAdmin == true) {
        _showNotification(
          'New User Registered',
          '${data['first_name']} ${data['last_name']} (${data['user_type']}) has joined.',
        );
      }
    });

    _socket!.on('new_order', (data) {
      if (_authProvider?.isAdmin == true) {
        _showNotification(
          'New Order Placed',
          'Order #${data['order_number']} received. Total: \$${data['total_amount']}',
        );
      }
    });

    _socket!.on('order_assigned', (data) {
      if (_authProvider?.isAdmin == true) {
        _showNotification(
          'Order Assigned',
          'Order #${data['order_number']} assigned to ${data['rider_name']}',
        );
      }
    });

    _socket!.on('order_status_update', (data) {
      // Admin sees all updates; User sees their own
      if (_authProvider?.isAdmin == true) {
        _showNotification(
          'Order Status Updated',
          'Order #${data['order_number']} is now ${data['status']}',
        );
      } else if (_authProvider?.user?.id == data['user_id']) {
        // Optionally notify user here, but user_notification is preferred if backend sends it
      }
    });

    // Rider Notifications
    _socket!.on('rider_notification', (data) {
      if (_authProvider?.isRider == true &&
          _authProvider?.user?.id == data['rider_id']) {
        _showNotification(
          'New Assignment',
          data['message'] ?? 'You have a new order assignment.',
        );
      }
    });

    // User Notifications
    _socket!.on('user_notification', (data) {
      if (_authProvider?.user?.id == data['user_id']) {
        _showNotification(
          'Order Update',
          data['message'] ?? 'Your order has been updated.',
        );
      }
    });

    _socket!.on('payment_status_update', (data) {
      if (_authProvider?.isAdmin == true) {
        _showNotification(
          'Payment Status Updated',
          'Order #${data['order_number']} payment is now ${data['payment_status']}',
        );
      } else if (_authProvider?.user?.id == data['user_id']) {
        // Optional: User usually checks app, but we can notify
        _showNotification(
          'Payment Update',
          'Payment status for Order #${data['order_number']} is now ${data['payment_status']}',
        );
      }
    });

    _socket!.on('order_completed', (data) {
      if (_authProvider?.isAdmin == true) {
        _showNotification(
          'Order Completed',
          'Order #${data['order_number']} delivered and paid.',
        );
      } else if (_authProvider?.user?.id == data['user_id']) {
        _showNotification(
          'Order Completed',
          data['message'] ?? 'Your order has been delivered and paid.',
        );
      }
    });

    _socket!.onDisconnect((_) => debugPrint('Socket disconnected'));
  }

  void _showNotification(String title, String message) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(message, style: const TextStyle(color: Colors.white)),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          showCloseIcon: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    _disconnectSocket();
    super.dispose();
  }
}
