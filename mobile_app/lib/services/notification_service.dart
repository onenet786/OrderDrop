import 'package:logger/logger.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api_service.dart';

class NotificationService {
  static final Logger _logger = Logger();
  static io.Socket? _socket;
  static Function(Map<String, dynamic>)? _onNotification;

  static void initialize({
    required Function(Map<String, dynamic>) onNotification,
  }) {
    _onNotification = onNotification;
  }

  static void connect(int userId, String userType) {
    if (_socket != null && _socket!.connected) {
      _logger.d('Socket.IO already connected');
      return;
    }

    try {
      _socket = io.io(
        ApiService.baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .setReconnectionAttempts(10)
            .build(),
      );

      _socket!.onConnect((_) {
        _logger.d('Socket.IO connected');
        _socket!.emit('identify_user', {
          'user_id': userId,
          'user_type': userType,
        });
      });

      _socket!.on('rider_notification', (data) {
        _logger.d('Rider notification: $data');
        if (_onNotification != null) {
          _onNotification!(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('store_owner_notification', (data) {
        _logger.d('Store Owner notification: $data');
        if (_onNotification != null) {
          _onNotification!(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('user_notification', (data) {
        _logger.d('User notification: $data');
        if (_onNotification != null) {
          _onNotification!(Map<String, dynamic>.from(data));
        }
      });

      _socket!.on('payment_status_update', (data) {
        _logger.d('Payment status update: $data');
        if (_onNotification != null) {
          _onNotification!({
            'type': 'payment_status_update',
            'data': Map<String, dynamic>.from(data),
          });
        }
      });

      _socket!.on('order_completed', (data) {
        _logger.d('Order completed notification: $data');
        if (_onNotification != null) {
          _onNotification!({
            'type': 'order_completed',
            'data': Map<String, dynamic>.from(data),
          });
        }
      });

      _socket!.on('order_status_update', (data) {
        _logger.d('Order status update: $data');
        if (_onNotification != null) {
          _onNotification!(Map<String, dynamic>.from(data));
        }
      });

      _socket!.onDisconnect((_) {
        _logger.d('Socket.IO disconnected');
      });

      _socket!.onError((error) {
        _logger.e('Socket.IO error: $error');
      });
    } catch (e) {
      _logger.e('Error initializing Socket.IO: $e');
    }
  }

  static void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
    }
  }

  static bool isConnected() {
    return _socket != null && _socket!.connected;
  }
}
