import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../services/api_service.dart';
import 'auth_provider.dart';

class NotificationProvider with ChangeNotifier {
  IO.Socket? _socket;
  final GlobalKey<NavigatorState> navigatorKey;
  AuthProvider? _authProvider;

  NotificationProvider(this.navigatorKey);

  void update(AuthProvider auth) {
    _authProvider = auth;
    _updateSocketConnection();
  }

  void _updateSocketConnection() {
    // Only connect if user is authenticated and is an admin
    if (_authProvider != null &&
        _authProvider!.isAuthenticated &&
        _authProvider!.isAdmin) {
      if (_socket == null || !_socket!.connected) {
        _initSocket();
      }
    } else {
      _disconnectSocket();
    }
  }

  void _initSocket() {
    if (_socket != null && _socket!.connected) return;

    // Ensure we don't have trailing slash for socket.io
    String baseUrl = ApiService.baseUrl;
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      debugPrint('Socket connected');
    });

    _socket!.on('new_user', (data) {
      _showNotification(
        'New User Registered',
        '${data['first_name']} ${data['last_name']} (${data['user_type']}) has joined.',
      );
    });

    _socket!.on('new_order', (data) {
      _showNotification(
        'New Order Placed',
        'Order #${data['order_number']} received. Total: \$${data['total_amount']}',
      );
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

  void _disconnectSocket() {
    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
    }
  }

  @override
  void dispose() {
    _disconnectSocket();
    super.dispose();
  }
}
