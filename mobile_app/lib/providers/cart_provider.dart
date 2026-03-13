import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../models/cart_item.dart';

class CartProvider with ChangeNotifier {
  final List<CartItem> _items = [];
  static const String _cartStorageKey = 'cart_items_v1';

  CartProvider() {
    _loadCart();
  }

  List<CartItem> get items => [..._items];

  int get itemCount => _items.length;

  double get totalAmount {
    var total = 0.0;
    for (var item in _items) {
      total += item.total;
    }
    return total;
  }

  int? get currentStoreId {
    if (_items.isEmpty) return null;
    return _items.first.product.storeId;
  }

  bool _sameVariant(ProductVariant? a, ProductVariant? b) {
    return a?.sizeId == b?.sizeId && a?.unitId == b?.unitId;
  }

  String? addItem(Product product, int quantity, {ProductVariant? variant}) {
    // Check stock availability
    final int availableStock = product.stockQuantity;
    String? warning;
    
    final existingIndex = _items.indexWhere(
      (item) => item.product.id == product.id && _sameVariant(item.variant, variant),
    );

    if (existingIndex >= 0) {
      final int newQuantity = _items[existingIndex].quantity + quantity;
      if (newQuantity > availableStock) {
        _items[existingIndex].quantity = availableStock;
        warning = 'Only $availableStock items available in stock';
      } else {
        _items[existingIndex].quantity = newQuantity;
      }
    } else {
      int initialQuantity = quantity;
      if (initialQuantity > availableStock) {
        initialQuantity = availableStock;
        warning = 'Only $availableStock items available in stock';
      }
      
      if (initialQuantity > 0) {
        _items.add(CartItem(product: product, variant: variant, quantity: initialQuantity));
      } else {
        warning = 'Item is out of stock';
      }
    }
    notifyListeners();
    _persistCart();
    return warning;
  }

  void removeCartItem(CartItem item) {
    _items.remove(item);
    notifyListeners();
    _persistCart();
  }

  String? updateCartItemQuantity(CartItem item, int quantity) {
    final index = _items.indexOf(item);
    String? warning;
    if (index >= 0) {
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        // Respect stock limit
        final int availableStock = _items[index].product.stockQuantity;
        if (quantity > availableStock) {
          _items[index].quantity = availableStock;
          warning = 'Only $availableStock items available in stock';
        } else {
          _items[index].quantity = quantity;
        }
      }
      notifyListeners();
      _persistCart();
    }
    return warning;
  }

  void clear() {
    _items.clear();
    notifyListeners();
    _persistCart();
  }

  Future<void> _persistCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = _items
          .map(
            (item) => {
              'product': item.product.toJson(),
              'variant': item.variant?.toJson(),
              'quantity': item.quantity,
            },
          )
          .toList();
      await prefs.setString(_cartStorageKey, jsonEncode(payload));
    } catch (_) {}
  }

  Future<void> _loadCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cartStorageKey);
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final restored = <CartItem>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final productJson = map['product'];
        final variantJson = map['variant'];
        final quantity = int.tryParse((map['quantity'] ?? 0).toString()) ?? 0;
        if (productJson is! Map || quantity <= 0) continue;

        final product = Product.fromJson(
          Map<String, dynamic>.from(productJson),
        );
        final variant = variantJson is Map
            ? ProductVariant.fromJson(
                Map<String, dynamic>.from(variantJson),
              )
            : null;
        restored.add(CartItem(product: product, variant: variant, quantity: quantity));
      }

      if (restored.isEmpty) return;
      _items
        ..clear()
        ..addAll(restored);
      notifyListeners();
    } catch (_) {}
  }
}
