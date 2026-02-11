import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../services/api_service.dart';
import 'auth_provider.dart';

class Notification {
  final int id;
  final String title;
  final String message;
  final String type;
  final String icon;
  final DateTime timestamp;
  bool unread;

  Notification({
    required this.id,
    required this.title,
    required this.message,
    this.type = 'info',
    this.icon = 'info',
    required this.timestamp,
    this.unread = true,
  });

  factory Notification.fromJson(Map<String, dynamic> json) {
    return Notification(
      id: json['id'],
      title: json['title'],
      message: json['message'],
      type: json['type'] ?? 'info',
      icon: json['icon'] ?? 'info',
      timestamp: DateTime.parse(json['timestamp']),
      unread: json['unread'] ?? true,
    );
  }
}

class NotificationProvider with ChangeNotifier {
  socket_io.Socket? _socket;
  final GlobalKey<NavigatorState> navigatorKey;
  AuthProvider? _authProvider;

  final List<Notification> _notifications = [];
  static const int _maxNotifications = 20;

  NotificationProvider(this.navigatorKey);

  List<Notification> get notifications => _notifications;
  int get unreadCount => _notifications.where((n) => n.unread).length;

  void addNotification({
    required String title,
    required String message,
    String type = 'info',
    String icon = 'info',
  }) {
    final notification = Notification(
      id: DateTime.now().millisecondsSinceEpoch,
      title: title,
      message: message,
      type: type,
      icon: icon,
      timestamp: DateTime.now(),
      unread: true,
    );

    _notifications.insert(0, notification);

    if (_notifications.length > _maxNotifications) {
      _notifications.removeRange(_maxNotifications, _notifications.length);
    }

    notifyListeners();
    _showNotification(title, message);
  }

  void clearNotifications() {
    _notifications.clear();
    notifyListeners();
  }

  void markAsRead(int notificationId) {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      _notifications[index].unread = false;
      notifyListeners();
    }
  }

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

  void _identifyUser() {
    if (_socket == null || !_socket!.connected) {
      debugPrint(
        '[NotificationProvider] Socket not connected, cannot identify user',
      );
      return;
    }

    if (_authProvider != null && _authProvider!.user != null) {
      final userId = _authProvider!.user!.id;
      final userType = _authProvider!.user!.userType;

      _socket!.emit('identify_user', {
        'user_id': userId,
        'user_type': userType,
      });
      debugPrint(
        '[NotificationProvider] User identified: ID=$userId, Type=$userType, SocketID=${_socket?.id}',
      );
    } else {
      debugPrint(
        '[NotificationProvider] Cannot identify: auth or user not available',
      );
    }
  }

  void _initSocket() {
    if (_socket != null && _socket!.connected) return;

    // Normalize base URL to origin for socket.io (strip any path like /api)
    String baseUrl = ApiService.baseUrl;
    try {
      final uri = Uri.parse(baseUrl);
      final origin =
          '${uri.scheme.isEmpty ? 'http' : uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      baseUrl = origin.endsWith('/')
          ? origin.substring(0, origin.length - 1)
          : origin;
    } catch (e) {
      debugPrint(
        '[NotificationProvider] Invalid baseUrl "$baseUrl", using as-is. Error: $e',
      );
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
    }

    debugPrint(
      '[NotificationProvider] Initializing socket connection to: $baseUrl',
    );

    _socket = socket_io.io(
      baseUrl,
      socket_io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setReconnectionAttempts(20)
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      debugPrint('[NotificationProvider] Socket connected: ${_socket?.id}');
      _identifyUser();
    });

    _socket!.onReconnect((_) {
      debugPrint('[NotificationProvider] Socket reconnected: ${_socket?.id}');
      _identifyUser();
    });
    _socket!.onReconnectAttempt((attempt) {
      debugPrint(
        '[NotificationProvider] Socket reconnect attempt: $attempt to $baseUrl',
      );
    });

    _socket!.onConnectError((data) {
      debugPrint(
        '[NotificationProvider] Socket connection error to $baseUrl: $data',
      );
    });

    _socket!.onError((data) {
      debugPrint('[NotificationProvider] Socket error: $data');
    });

    _socket!.onDisconnect((_) {
      debugPrint('[NotificationProvider] Socket disconnected');
    });

    _socket!.on('new_user', (data) {
      debugPrint('Socket: new_user received');
      if (_authProvider?.isAdmin == true) {
        addNotification(
          title: 'New User Registered',
          message:
              '${data['first_name']} ${data['last_name']} (${data['user_type']}) has joined.',
          type: 'success',
          icon: 'person_add',
        );
      }
    });

    _socket!.on('new_order', (data) {
      debugPrint('Socket: new_order received');
      if (_authProvider?.isAdmin == true) {
        addNotification(
          title: 'New Order Placed',
          message:
              'Order #${data['order_number']} received. Total: PKR ${data['total_amount']}',
          type: 'success',
          icon: 'shopping_bag',
        );
      }
    });

    _socket!.on('order_assigned', (data) {
      debugPrint('Socket: order_assigned received');
      if (_authProvider?.isAdmin == true) {
        addNotification(
          title: 'Order Assigned',
          message:
              'Order #${data['order_number']} assigned to ${data['rider_name']}',
          type: 'info',
          icon: 'assignment',
        );
      }
    });

    _socket!.on('order_status_update', (data) {
      debugPrint(
        'Socket: order_status_update received for user ${data['user_id']}',
      );
      if (_authProvider?.isAdmin == true) {
        String icon = 'schedule';
        if (data['status'] == 'delivered') icon = 'check_circle';
        if (data['status'] == 'confirmed') icon = 'check';

        addNotification(
          title:
              'Order ${data['status']?.toString().toUpperCase() ?? 'UPDATED'}',
          message: 'Order #${data['order_number']}',
          type: 'info',
          icon: icon,
        );
      } else if (_authProvider?.user?.id.toString() ==
          data['user_id'].toString()) {
        String icon = 'schedule';
        if (data['status'] == 'delivered') icon = 'check_circle';
        if (data['status'] == 'confirmed') icon = 'check';

        addNotification(
          title:
              'Order ${data['status']?.toString().toUpperCase() ?? 'UPDATED'}',
          message: 'Your order #${data['order_number']}',
          type: 'info',
          icon: icon,
        );
      }
    });

    _socket!.on('rider_notification', (data) {
      final riderId = data['rider_id'].toString();
      final currentUserId = _authProvider?.user?.id.toString();
      debugPrint(
        '[NotificationProvider] rider_notification: received=$riderId, currentUser=$currentUserId, isRider=${_authProvider?.isRider}',
      );

      if (_authProvider?.isRider == true && currentUserId == riderId) {
        debugPrint('[NotificationProvider] Showing rider notification');
        addNotification(
          title: 'New Assignment',
          message: data['message'] ?? 'You have a new order assignment.',
          type: 'info',
          icon: 'assignment_turned_in',
        );
      } else {
        debugPrint(
          '[NotificationProvider] Rider notification filtered out - not matching rider',
        );
      }
    });

    _socket!.on('user_notification', (data) {
      final userId = data['user_id'].toString();
      final currentUserId = _authProvider?.user?.id.toString();
      debugPrint(
        '[NotificationProvider] user_notification: received=$userId, currentUser=$currentUserId',
      );

      if (currentUserId == userId) {
        debugPrint('[NotificationProvider] Showing user notification');
        addNotification(
          title: 'Order Update',
          message: data['message'] ?? 'Your order has been updated.',
          type: 'info',
          icon: 'inventory_2',
        );
      } else {
        debugPrint(
          '[NotificationProvider] User notification filtered out - not matching user',
        );
      }
    });

    _socket!.on('store_owner_notification', (data) {
      final storeId = data['store_id'].toString();
      debugPrint('[NotificationProvider] store_owner_notification: $data');

      // Since we don't track which stores the user owns in AuthProvider easily,
      // we rely on the backend sending this event to the correct user room.
      // The backend emits to `user_{owner_id}`, so if we receive it, it's for us.

      addNotification(
        title: 'Store Order Update',
        message: data['message'] ?? 'New update for your store.',
        type: 'info', // You can change this based on data['type']
        icon: 'store', // Need to make sure 'store' icon is handled or use 'inventory_2'
      );
    });

    _socket!.on('payment_status_update', (data) {
      debugPrint(
        'Socket: payment_status_update received for user ${data['user_id']}',
      );
      if (_authProvider?.isAdmin == true) {
        addNotification(
          title:
              'Payment ${data['payment_status'] == 'paid' ? 'Received' : 'Update'}',
          message: 'Order #${data['order_number']}',
          type: data['payment_status'] == 'paid' ? 'success' : 'info',
          icon: data['payment_status'] == 'paid' ? 'check_circle' : 'payment',
        );
      } else if (_authProvider?.user?.id.toString() ==
          data['user_id'].toString()) {
        addNotification(
          title:
              'Payment ${data['payment_status'] == 'paid' ? 'Received' : 'Update'}',
          message: 'Order #${data['order_number']}',
          type: data['payment_status'] == 'paid' ? 'success' : 'info',
          icon: data['payment_status'] == 'paid' ? 'check_circle' : 'payment',
        );
      }
    });

    _socket!.on('order_completed', (data) {
      debugPrint(
        'Socket: order_completed received for user ${data['user_id']}',
      );
      if (_authProvider?.isAdmin == true) {
        addNotification(
          title: 'Order Fully Completed',
          message: 'Order #${data['order_number']}',
          type: 'success',
          icon: 'task_alt',
        );
      } else if (_authProvider?.user?.id.toString() ==
          data['user_id'].toString()) {
        addNotification(
          title: 'Order Completed',
          message:
              data['message'] ?? 'Your order has been delivered. Thank you!',
          type: 'success',
          icon: 'check_circle',
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
