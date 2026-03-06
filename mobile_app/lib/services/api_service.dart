import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class ApiService {
  static final Logger _logger = Logger();

  static String get baseUrl {
    if (kDebugMode) {
      if (kIsWeb) {
        return 'http://23.137.84.249:3002';
      } else if (Platform.isAndroid) {
        return 'http://23.137.84.249:3002'; // Android Emulator localhost
      } else if (Platform.isIOS) {
        return 'http://23.137.84.249:3002'; // iOS Simulator localhost
      }
    }

    // Fallback to production/remote URL
    return 'http://23.137.84.249:3002';
  }

  static String getImageUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$baseUrl$url';
    return '$baseUrl/$url';
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      try {
        final errorData = jsonDecode(response.body);
        throw Exception(
          errorData['message'] ?? 'API Error: ${response.statusCode}',
        );
      } catch (e) {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
    }
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final uri = Uri.parse('$baseUrl/api/auth/login');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? phone,
    String? address,
  }) async {
    final uri = Uri.parse('$baseUrl/api/auth/register');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'password': password,
        'phone': phone,
        'address': address,
        'userType': 'customer',
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> verifyEmail(
    String email,
    String code,
  ) async {
    final uri = Uri.parse('$baseUrl/api/auth/verify-email');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> resendVerificationCode(
    String email,
  ) async {
    final uri = Uri.parse('$baseUrl/api/auth/resend-code');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final uri = Uri.parse('$baseUrl/api/auth/forgot-password');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> verifyResetOTP(
    String email,
    String otp,
  ) async {
    final uri = Uri.parse('$baseUrl/api/auth/verify-reset-otp');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'otp': otp}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> resetPassword(
    String token,
    String newPassword,
  ) async {
    final uri = Uri.parse('$baseUrl/api/auth/reset-password');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'password': newPassword}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> changePassword(
    String token,
    String currentPassword,
    String newPassword,
  ) async {
    final uri = Uri.parse('$baseUrl/api/auth/change-password');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getProfile(String token) async {
    final uri = Uri.parse('$baseUrl/api/auth/me');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> deleteAccount(String token) async {
    final uri = Uri.parse('$baseUrl/api/auth/account');
    _logger.d('ApiService: DELETE $uri');
    final response = await http.delete(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> registerPushDeviceToken(
    String token, {
    required String deviceToken,
    required String platform,
    String? deviceId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/auth/push-token');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'device_token': deviceToken.trim(),
        'platform': platform.trim(),
        if (deviceId != null && deviceId.trim().isNotEmpty)
          'device_id': deviceId.trim(),
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> unregisterPushDeviceToken(
    String token, {
    required String deviceToken,
  }) async {
    final uri = Uri.parse('$baseUrl/api/auth/push-token');
    _logger.d('ApiService: DELETE $uri');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'device_token': deviceToken.trim()}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getStores({
    int? categoryId,
    double? latitude,
    double? longitude,
    String? city,
  }) async {
    final query = <String, String>{};
    if (categoryId != null) {
      query['category_id'] = categoryId.toString();
    }
    if (latitude != null && longitude != null) {
      query['latitude'] = latitude.toString();
      query['longitude'] = longitude.toString();
    }
    if (city != null && city.trim().isNotEmpty) {
      query['city'] = city.trim();
    }

    final uri = Uri.parse('$baseUrl/api/stores').replace(
      queryParameters: query.isEmpty ? null : query,
    );
    _logger.d('ApiService: GET $uri');
    final response = await http.get(uri);
    return _handleResponse(response);
  }

  static Future<List<dynamic>> getCategories() async {
    final uri = Uri.parse('$baseUrl/api/categories');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(uri);
    final data = _handleResponse(response);
    return data['categories'] ?? [];
  }

  static Future<Map<String, dynamic>> getStoreDetails(int id) async {
    final uri = Uri.parse('$baseUrl/api/stores/$id');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(uri);
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getStoreStatusMessage(
    String token, {
    int? storeId,
  }) async {
    final query = (storeId != null && storeId > 0) ? '?store_id=$storeId' : '';
    final uri = Uri.parse('$baseUrl/api/stores/status-message$query');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> setStoreStatusMessage(
    String token, {
    int? storeId,
    required String statusMessage,
    required bool isClosed,
  }) async {
    final uri = Uri.parse('$baseUrl/api/stores/status-message');
    _logger.d('ApiService: PUT $uri');
    final body = <String, dynamic>{
      'status_message': statusMessage,
      'is_closed': isClosed,
    };
    if (storeId != null && storeId > 0) {
      body['store_id'] = storeId;
    }
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getGlobalDeliveryStatus(
    String token,
  ) async {
    final uri = Uri.parse('$baseUrl/api/stores/global-delivery-status');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _handleResponse(response);
    if (data['global_delivery_status'] is Map<String, dynamic>) {
      return data['global_delivery_status'] as Map<String, dynamic>;
    }
    if (data['status'] is Map<String, dynamic>) {
      return data['status'] as Map<String, dynamic>;
    }
    if (data['global_status'] is Map<String, dynamic>) {
      return data['global_status'] as Map<String, dynamic>;
    }
    return data;
  }

  static Future<Map<String, dynamic>> getLivePromotions([String? token]) async {
    final uri = Uri.parse('$baseUrl/api/stores/live-promotions');
    _logger.d('ApiService: GET $uri');
    final headers = <String, String>{};
    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await http.get(uri, headers: headers);
    final data = _handleResponse(response);
    if (data['live_promotions'] is Map<String, dynamic>) {
      return data['live_promotions'] as Map<String, dynamic>;
    }
    if (data['promotion'] is Map<String, dynamic>) {
      return data['promotion'] as Map<String, dynamic>;
    }
    return data;
  }

  static Future<Map<String, dynamic>> getCustomerFlashMessage(
    String token,
  ) async {
    final uri = Uri.parse('$baseUrl/api/stores/customer-flash-message');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _handleResponse(response);
    if (data['customer_flash_message'] is Map<String, dynamic>) {
      return data['customer_flash_message'] as Map<String, dynamic>;
    }
    if (data['flash_message'] is Map<String, dynamic>) {
      return data['flash_message'] as Map<String, dynamic>;
    }
    return data;
  }

  static Future<Map<String, dynamic>> setGlobalDeliveryStatus(
    String token, {
    required bool isEnabled,
    required bool blockOrdering,
    String? title,
    required String statusMessage,
    String? startAt,
    String? endAt,
  }) async {
    final uri = Uri.parse('$baseUrl/api/stores/global-delivery-status');
    _logger.d('ApiService: PUT $uri');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'is_enabled': isEnabled,
        'block_ordering': blockOrdering,
        'title': title?.trim().isEmpty == true ? null : title?.trim(),
        'status_message': statusMessage.trim(),
        'start_at': startAt?.trim().isEmpty == true ? null : startAt?.trim(),
        'end_at': endAt?.trim().isEmpty == true ? null : endAt?.trim(),
      }),
    );
    return _handleResponse(response);
  }

  static Future<List<dynamic>> getOrders(
    String token, {
    String? assignment,
    String? status,
    bool includeItemsCount = true,
    bool includeStoreStatuses = true,
    String? startDate,
    String? endDate,
  }) async {
    final query = <String, String>{
      'includeItemsCount': includeItemsCount.toString(),
      'includeStoreStatuses': includeStoreStatuses.toString(),
    };
    if (assignment != null && assignment.trim().isNotEmpty) {
      query['assignment'] = assignment.trim();
    }
    if (status != null && status.trim().isNotEmpty) {
      query['status'] = status.trim();
    }
    if (startDate != null && startDate.trim().isNotEmpty) {
      query['startDate'] = startDate.trim();
    }
    if (endDate != null && endDate.trim().isNotEmpty) {
      query['endDate'] = endDate.trim();
    }
    final uri = Uri.parse(
      '$baseUrl/api/orders',
    ).replace(queryParameters: query);
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _handleResponse(response);
    return data['orders'] ?? [];
  }

  static Future<List<dynamic>> getMyOrders(String token) async {
    final uri = Uri.parse('$baseUrl/api/orders/my-orders');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _handleResponse(response);
    return data['orders'] ?? [];
  }

  static Future<Map<String, dynamic>> createOrder(
    String token, {
    int? storeId,
    required List<Map<String, dynamic>> items,
    required String deliveryAddress,
    required String paymentMethod,
    String? deliveryTime,
    String? specialInstructions,
  }) async {
    final uri = Uri.parse('$baseUrl/api/orders');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        if (storeId != null) 'store_id': storeId,
        'items': items,
        'delivery_address': deliveryAddress,
        'payment_method': paymentMethod,
        'delivery_time': deliveryTime,
        'special_instructions': specialInstructions,
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getVisitorStats(String token) async {
    final uri = Uri.parse('$baseUrl/api/admin/visitor-stats');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getRecentActivity(String token) async {
    final uri = Uri.parse('$baseUrl/api/admin/recent-activity');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _handleResponse(response);
    return data;
  }

  // Rider APIs
  static Future<Map<String, dynamic>> getRiderProfile(String token) async {
    final uri = Uri.parse('$baseUrl/api/orders/rider/profile');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<List<dynamic>> getRiderDeliveries(
    String token,
    String status,
  ) async {
    final uri = Uri.parse(
      '$baseUrl/api/orders/rider/deliveries?status=$status',
    );
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _handleResponse(response);
    return data['deliveries'] ?? [];
  }

  static Future<Map<String, dynamic>> getRiderWalletStats(
    String token,
    String period,
  ) async {
    final uri = Uri.parse(
      '$baseUrl/api/orders/rider/wallet-stats?period=$period',
    );
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getRiderFinancialHistory(
    String token, {
    String? from,
    String? to,
  }) async {
    final query = <String, String>{};
    if (from != null && from.trim().isNotEmpty) query['from'] = from.trim();
    if (to != null && to.trim().isNotEmpty) query['to'] = to.trim();
    final uri = Uri.parse('$baseUrl/api/orders/rider/financial-history').replace(
      queryParameters: query.isEmpty ? null : query,
    );
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> closeRiderDay(
    String token, {
    required String date,
    String? notes,
  }) async {
    final uri = Uri.parse('$baseUrl/api/orders/rider/close-day');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'date': date,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      }),
    );
    return _handleResponse(response);
  }

  // Store Owner APIs
  static Future<Map<String, dynamic>> getStoreOrders(
    String token, {
    String status = 'all',
  }) async {
    final uri = Uri.parse('$baseUrl/api/orders/store-dashboard?status=$status');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getStoreOwnerFinancialHistory(
    String token, {
    String? from,
    String? to,
  }) async {
    final query = <String, String>{};
    if (from != null && from.trim().isNotEmpty) query['from'] = from.trim();
    if (to != null && to.trim().isNotEmpty) query['to'] = to.trim();
    final uri = Uri.parse('$baseUrl/api/orders/store-owner/financial-history')
        .replace(queryParameters: query.isEmpty ? null : query);
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> updateOrderStatus(
    String token,
    int orderId,
    String status,
  ) async {
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/status');
    _logger.d('ApiService: PUT $uri');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'status': status}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> markOrderAsDelivered(
    String token,
    int orderId,
  ) async {
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/deliver');
    _logger.d('ApiService: PUT $uri');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> updatePaymentStatus(
    String token,
    int orderId,
    String status,
  ) async {
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/payment-status');
    _logger.d('ApiService: PUT $uri');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'payment_status': status}),
    );
    return _handleResponse(response);
  }

  // Wallet APIs
  static Future<Map<String, dynamic>> getWalletBalance(String token) async {
    final uri = Uri.parse('$baseUrl/api/wallet/balance');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getWalletTransactions(
    String token, {
    int limit = 20,
    int offset = 0,
    String? type,
  }) async {
    String query = 'limit=$limit&offset=$offset';
    if (type != null && type.isNotEmpty) {
      query += '&type=$type';
    }
    final uri = Uri.parse('$baseUrl/api/wallet/transactions?$query');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getAutoRechargeSettings(
    String token,
  ) async {
    final uri = Uri.parse('$baseUrl/api/wallet/auto-recharge');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> saveAutoRechargeSettings(
    String token, {
    required bool enabled,
    required double amount,
    required double threshold,
  }) async {
    final uri = Uri.parse('$baseUrl/api/wallet/auto-recharge');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'enabled': enabled,
        'amount': amount,
        'threshold': threshold,
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> topupWallet(
    String token, {
    required double amount,
    required String paymentMethod,
    String? cardToken,
    bool saveCard = false,
  }) async {
    final uri = Uri.parse('$baseUrl/api/wallet/topup');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'amount': amount,
        'paymentMethod': paymentMethod,
        'cardToken': cardToken,
        'saveCard': saveCard,
      }),
    );
    return _handleResponse(response);
  }

  // Payment Methods APIs
  static Future<Map<String, dynamic>> getPaymentMethods(String token) async {
    final uri = Uri.parse('$baseUrl/api/wallet/payment-methods');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> setPrimaryPaymentMethod(
    String token,
    int id,
  ) async {
    final uri = Uri.parse('$baseUrl/api/wallet/payment-methods/$id/primary');
    _logger.d('ApiService: PUT $uri');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> deletePaymentMethod(
    String token,
    int id,
  ) async {
    final uri = Uri.parse('$baseUrl/api/wallet/payment-methods/$id');
    _logger.d('ApiService: DELETE $uri');
    final response = await http.delete(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  // P2P Transfers APIs
  static Future<Map<String, dynamic>> sendMoney(
    String token, {
    int? recipientId,
    String? email,
    required double amount,
    String? description,
  }) async {
    final uri = Uri.parse('$baseUrl/api/wallet/transfers/send');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        if (recipientId != null) 'recipient_id': recipientId,
        if (email != null) 'email': email,
        'amount': amount,
        'description': description,
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getSentTransfers(
    String token, {
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/wallet/transfers/sent?limit=$limit&offset=$offset',
    );
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getReceivedTransfers(
    String token, {
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/wallet/transfers/received?limit=$limit&offset=$offset',
    );
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> acceptTransfer(
    String token,
    int id,
  ) async {
    final uri = Uri.parse('$baseUrl/api/wallet/transfers/$id/accept');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> rejectTransfer(
    String token,
    int id, {
    String? reason,
  }) async {
    final uri = Uri.parse('$baseUrl/api/wallet/transfers/$id/reject');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'reason': reason}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> cancelTransfer(
    String token,
    int id,
  ) async {
    final uri = Uri.parse('$baseUrl/api/wallet/transfers/$id/cancel');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getInventoryReport(String token) async {
    final uri = Uri.parse('$baseUrl/api/admin/inventory-report');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getStoreSalesReport(String token) async {
    final uri = Uri.parse('$baseUrl/api/admin/store-sales-report');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getStoreOrderBreakdown(
    String token,
  ) async {
    final uri = Uri.parse('$baseUrl/api/admin/store-order-breakdown');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getAdminWallets(
    String token, {
    int page = 1,
    int limit = 500,
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/wallets?page=$page&limit=$limit');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<List<dynamic>> getUsers(String token) async {
    final uri = Uri.parse('$baseUrl/api/users');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _handleResponse(response);
    return data['users'] ?? [];
  }

  static Future<List<dynamic>> getStoresForAdmin(
    String token, {
    bool includeInactive = false,
    bool lite = false,
  }) async {
    final query = <String>[];
    if (includeInactive) query.add('admin=1');
    if (lite) query.add('lite=1');
    final qs = query.isEmpty ? '' : '?${query.join('&')}';
    final uri = Uri.parse(
      '$baseUrl/api/stores$qs',
    );
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _handleResponse(response);
    return data['stores'] ?? [];
  }

  static Future<Map<String, dynamic>> getStoreOfferCampaigns(
    String token, {
    required int storeId,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/stores/offer-campaigns?store_id=$storeId',
    );
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> createStoreOfferCampaign(
    String token, {
    required Map<String, dynamic> payload,
  }) async {
    final uri = Uri.parse('$baseUrl/api/stores/offer-campaigns');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> updateStoreOfferCampaign(
    String token, {
    required int campaignId,
    required Map<String, dynamic> payload,
  }) async {
    final uri = Uri.parse('$baseUrl/api/stores/offer-campaigns/$campaignId');
    _logger.d('ApiService: PUT $uri');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> deleteStoreOfferCampaign(
    String token, {
    required int campaignId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/stores/offer-campaigns/$campaignId');
    _logger.d('ApiService: DELETE $uri');
    final response = await http.delete(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<List<dynamic>> getProductsForAdmin(String token) async {
    final uri = Uri.parse('$baseUrl/api/products');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _handleResponse(response);
    return data['products'] ?? [];
  }

  static Future<List<dynamic>> getProductsForOwner(
    String token,
    int ownerId,
  ) async {
    // Load all stores and filter by owner
    final stores = await getStoresForAdmin(token);
    final ownerStores =
        stores.where((s) => (s['owner_id']?.toString() ?? '') == ownerId.toString()).toList();
    if (ownerStores.isEmpty) return [];

    // Fetch products for each store
    final List<dynamic> products = [];
    for (final s in ownerStores) {
      final sid = s['id'];
      if (sid == null) continue;
      final uri = Uri.parse(
        '$baseUrl/api/products?store=$sid&admin=1&include_variants=1',
      );
      _logger.d('ApiService: GET $uri');
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = _handleResponse(resp);
      final list = (data['products'] as List<dynamic>? ?? []);
      products.addAll(list);
    }
    return products;
  }

  static Future<Map<String, dynamic>> updateProduct(
    String token, {
    required int productId,
    String? name,
    double? price,
    List<Map<String, dynamic>>? sizeVariants,
    double? costPrice,
    String? discountType,
    double? discountValue,
  }) async {
    final uri = Uri.parse('$baseUrl/api/products/$productId');
    _logger.d('ApiService: PUT $uri');
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (price != null) body['price'] = price;
    if (sizeVariants != null) {
      body['size_variants'] = sizeVariants;
    }
    if (costPrice != null) body['cost_price'] = costPrice;
    if (discountType != null) body['discount_type'] = discountType;
    if (discountValue != null) body['discount_value'] = discountValue;

    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  static Future<List<dynamic>> getRiders(String token) async {
    final uri = Uri.parse('$baseUrl/api/riders');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _handleResponse(response);
    return data['riders'] ?? [];
  }

  static Future<Map<String, dynamic>> updateRiderLocation(
    String token, {
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('$baseUrl/api/orders/rider/location');
    _logger.d('ApiService: PUT $uri');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
    );
    return _handleResponse(response);
  }

  static Future<List<dynamic>> getAvailableRiders(String token) async {
    final uri = Uri.parse('$baseUrl/api/orders/available-riders');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _handleResponse(response);
    return data['riders'] ?? [];
  }

  static Future<Map<String, dynamic>> assignOrderRider(
    String token,
    int orderId,
    int riderId, {
    double? deliveryFee,
  }) async {
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/assign-rider');
    _logger.d('ApiService: PUT $uri');
    final body = <String, dynamic>{'rider_id': riderId};
    if (deliveryFee != null) body['delivery_fee'] = deliveryFee;
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getStoreGraceAlerts(
    String token, {
    String channel = 'mobile',
  }) async {
    final safeChannel = channel.toLowerCase() == 'web' ? 'web' : 'mobile';
    final uri = Uri.parse('$baseUrl/api/stores/grace-alerts?channel=$safeChannel');
    _logger.d('ApiService: GET $uri');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> muteStoreGraceAlert(
    String token,
    int storeId, {
    int hours = 24,
  }) async {
    final uri = Uri.parse('$baseUrl/api/stores/$storeId/grace-alert-mute');
    _logger.d('ApiService: POST $uri');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'hours': hours}),
    );
    return _handleResponse(response);
  }
}
