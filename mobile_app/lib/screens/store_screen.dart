import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:servenow/services/notifier.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../services/api_service.dart';
import '../utils/customer_language.dart';

class StoreScreen extends StatefulWidget {
  final int storeId;

  const StoreScreen({super.key, required this.storeId});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  late Future<Map<String, dynamic>> _storeDetailsFuture;
  final Map<int, String> _selectedVariantKeyByProductId = {};
  Map<String, dynamic>? _globalStatus;
  Timer? _globalStatusRefreshTimer;
  bool _isUrdu = false;
  int? _selectedProductId;

  @override
  void initState() {
    super.initState();
    _storeDetailsFuture = ApiService.getStoreDetails(widget.storeId);
    _loadLanguagePreference();
    _loadGlobalStatus();
  }

  @override
  void dispose() {
    _globalStatusRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLanguagePreference() async {
    final isUrdu = await CustomerLanguage.loadIsUrdu();
    if (!mounted) return;
    setState(() => _isUrdu = isUrdu);
  }

  Future<void> _refresh() async {
    setState(() {
      _storeDetailsFuture = ApiService.getStoreDetails(widget.storeId);
    });
    await _loadGlobalStatus();
    await _storeDetailsFuture;
  }

  Future<void> _loadGlobalStatus() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;
      final status = await ApiService.getGlobalDeliveryStatus(token);
      if (!mounted) return;
      setState(() => _globalStatus = status);
      _scheduleGlobalStatusRefresh(status);
    } catch (_) {}
  }

  void _scheduleGlobalStatusRefresh(Map<String, dynamic>? status) {
    _globalStatusRefreshTimer?.cancel();
    if (status == null) return;

    final now = DateTime.now();
    final startAt = _parseDateTime(status['start_at']);
    final endAt = _parseDateTime(status['end_at']);
    final candidates = <DateTime>[
      if (startAt != null && startAt.isAfter(now)) startAt,
      if (endAt != null && endAt.isAfter(now)) endAt,
    ];
    if (candidates.isEmpty) return;

    candidates.sort();
    _globalStatusRefreshTimer = Timer(
      candidates.first.difference(now) + const Duration(seconds: 1),
      _loadGlobalStatus,
    );
  }

  String _tr(String text) => CustomerLanguage.tr(_isUrdu, text);

  String _variantKey(ProductVariant variant) {
    return '${variant.sizeId ?? 'n'}:${variant.unitId ?? 'n'}';
  }

  ProductVariant? _selectedVariantFor(Product product) {
    if (product.sizeVariants.isEmpty) return null;
    final selectedKey = _selectedVariantKeyByProductId[product.id];
    if (selectedKey == null) return product.sizeVariants.first;
    return product.sizeVariants.firstWhere(
      (variant) => _variantKey(variant) == selectedKey,
      orElse: () => product.sizeVariants.first,
    );
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  DateTime? _parseDateTime(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  bool _isGlobalWindowActive(Map<String, dynamic> status) {
    if (_toBool(status['is_window_active'])) return true;
    final start = DateTime.tryParse((status['start_at'] ?? '').toString());
    final end = DateTime.tryParse((status['end_at'] ?? '').toString());
    if (start == null || end == null) return true;
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }

  bool _isGlobalStatusVisible(Map<String, dynamic>? status) {
    if (status == null || !_toBool(status['is_enabled'])) return false;
    return _isGlobalWindowActive(status);
  }

  bool _isGlobalOrderingBlocked(Map<String, dynamic>? status) {
    if (!_isGlobalStatusVisible(status) || status == null) return false;
    if (_toBool(status['block_ordering_active'])) return true;
    return _toBool(status['block_ordering']) && _isGlobalWindowActive(status);
  }

  String _globalStatusMessage(Map<String, dynamic>? status) {
    if (status == null) return _tr('Ordering is temporarily unavailable.');
    final message = (status['status_message'] ?? '').toString().trim();
    final title = (status['title'] ?? '').toString().trim();
    if (message.isNotEmpty) return message;
    if (title.isNotEmpty) return title;
    return _tr('Ordering is temporarily unavailable.');
  }

  String _formatPrice(double value) {
    return value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
  }

  String _formatTimeOnly(dynamic time) {
    if (time == null) return '--:--';
    final parts = time.toString().split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return time.toString();
  }

  int? _discountPercent(Product product, ProductVariant? variant) {
    final current = variant?.effectivePrice ?? product.effectivePrice;
    final original = variant?.price ?? product.price;
    if (original <= 0 || current >= original) return null;
    return (((original - current) / original) * 100).round();
  }

  List<String> _productFacts(Product product, ProductVariant? variant, Map<String, dynamic> store) {
    final facts = <String>[];
    final description = (product.description ?? '').trim();
    if (description.isNotEmpty) {
      facts.addAll(description.split(RegExp(r'[\r\n]+')).map((line) => line.replaceFirst(RegExp(r'^[\s\-•]+'), '').trim()).where((line) => line.isNotEmpty));
    }
    if ((variant?.displayLabel ?? '').trim().isNotEmpty) {
      facts.add('Pack size: ${variant!.displayLabel}');
    }
    if ((product.categoryName ?? '').trim().isNotEmpty) {
      facts.add('Category: ${product.categoryName!.trim()}');
    }
    if ((store['location'] ?? '').toString().trim().isNotEmpty) {
      facts.add('Prepared and delivered from ${store['location']}');
    }
    if (product.stockQuantity > 0) {
      facts.add(product.stockQuantity > 10 ? 'Fresh stock available today' : 'Only ${product.stockQuantity} left in stock');
    }
    if (facts.isEmpty) {
      facts.addAll(['Fresh and ready for delivery', 'Quality checked before dispatch', 'Packed with care by the store']);
    }
    return facts.take(5).toList();
  }

  void _addToCart(BuildContext context, Product product, ProductVariant? variant, {required bool isOpen, required bool isGlobalBlocked}) {
    if (isGlobalBlocked) {
      Notifier.error(context, _globalStatusMessage(_globalStatus));
      return;
    }
    if (!isOpen) {
      Notifier.error(context, _tr('This store is currently closed. You cannot place orders at this time.'));
      return;
    }
    if (product.stockQuantity <= 0) {
      Notifier.info(context, _tr('Out of stock'));
      return;
    }

    final cart = Provider.of<CartProvider>(context, listen: false);
    final existingItem = cart.items.firstWhere(
      (item) => item.product.id == product.id && item.variant?.sizeId == variant?.sizeId && item.variant?.unitId == variant?.unitId,
      orElse: () => CartItem(product: product, quantity: 0),
    );
    if (existingItem.quantity >= product.stockQuantity) {
      Notifier.info(context, '${_tr('Only')} ${product.stockQuantity} ${_tr('available')}');
      return;
    }

    final warning = cart.addItem(product, 1, variant: variant);
    if (warning != null) {
      Notifier.info(context, warning);
    } else {
      Notifier.success(context, _tr('Added to cart'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: CustomerLanguage.textDirection(_isUrdu),
      child: Scaffold(
        backgroundColor: const Color(0xFFD7ECD7),
        body: Stack(
          children: [
            const _StoreBackdrop(),
            FutureBuilder<Map<String, dynamic>>(
              future: _storeDetailsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('${_tr('Error')}: ${snapshot.error}'));
                }

                final data = snapshot.data;
                if (data == null || data['success'] != true) {
                  return Center(child: Text(_tr('Store not found')));
                }

                final store = (data['store'] as Map).cast<String, dynamic>();
                final products = (data['products'] as List<dynamic>? ?? []).map((json) => Product.fromJson(json)).toList();
                final isOpen = store['is_open'] == true || store['is_open'] == 1;
                final closedReason = (store['status_message'] ?? '').toString().trim();
                final featuredProduct = products.isEmpty ? null : products.firstWhere((product) => product.id == _selectedProductId, orElse: () => products.first);
                final featuredVariant = featuredProduct == null ? null : _selectedVariantFor(featuredProduct);
                final suggestions = featuredProduct == null ? <Product>[] : products.where((product) => product.id != featuredProduct.id).take(6).toList();
                final isGlobalBlocked = _isGlobalOrderingBlocked(_globalStatus);
                final showGlobalBanner = _isGlobalStatusVisible(_globalStatus);

                return SafeArea(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF3C7B74).withValues(alpha: 0.14),
                                  blurRadius: 28,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildTopBar(context),
                                  const SizedBox(height: 16),
                                  if (showGlobalBanner) ...[
                                    _StatusBanner(message: _globalStatusMessage(_globalStatus), blocked: isGlobalBlocked),
                                    const SizedBox(height: 14),
                                  ],
                                  if (featuredProduct == null)
                                    const _EmptyStoreCard()
                                  else ...[
                                    _buildFeaturedCard(context, store, featuredProduct, featuredVariant, isOpen: isOpen, isGlobalBlocked: isGlobalBlocked),
                                    const SizedBox(height: 14),
                                    _buildDetailsCard(store, featuredProduct, featuredVariant, isOpen: isOpen, closedReason: closedReason),
                                    if (suggestions.isNotEmpty) ...[
                                      const SizedBox(height: 14),
                                      _buildSuggestionsRow(context, suggestions, isOpen: isOpen, isGlobalBlocked: isGlobalBlocked),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        _CircleButton(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 12),
        Expanded(
          child: Image.asset(
            'assets/icon/logo_w.png',
            height: 46,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (_, _, _) => const Text(
              'OrderDrop',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF13201B)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Consumer<CartProvider>(
          builder: (context, cart, _) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                _CircleButton(icon: Icons.shopping_cart_outlined, onTap: () => Navigator.of(context).pushNamed('/cart')),
                if (cart.itemCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF88C84A), borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        '${cart.itemCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(width: 8),
        const _CircleButton(icon: Icons.person_rounded),
      ],
    );
  }

  Widget _buildFeaturedCard(BuildContext context, Map<String, dynamic> store, Product product, ProductVariant? variant, {required bool isOpen, required bool isGlobalBlocked}) {
    final imageUrl = ApiService.getImageUrl(product.imageUrl);
    final currentPrice = variant?.effectivePrice ?? product.effectivePrice;
    final originalPrice = variant?.price ?? product.price;
    final discount = _discountPercent(product, variant);
    final subtitle = [(store['name'] ?? '').toString().trim(), if ((variant?.displayLabel ?? '').trim().isNotEmpty) variant!.displayLabel].where((part) => part.isNotEmpty).join(' | ');

    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              height: 250,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF7FBF8), Color(0xFFE8F3ED)]),
              ),
              child: Stack(
                children: [
                  if (discount != null)
                    Positioned(
                      top: 14,
                      left: 14,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(color: Color(0xFF88C84A), shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(
                          '$discount%\nOFF',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, height: 1.05),
                        ),
                      ),
                    ),
                  Center(
                    child: imageUrl.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(18),
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Icon(Icons.fastfood_rounded, size: 72, color: Color(0xFFA6B6AD)),
                            ),
                          )
                        : const Icon(Icons.fastfood_rounded, size: 72, color: Color(0xFFA6B6AD)),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF252826))),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF7E8781), fontWeight: FontWeight.w500)),
                if (product.sizeVariants.length > 1) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: product.sizeVariants.map((item) {
                      final isSelected = _variantKey(item) == _variantKey(variant ?? item);
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedVariantKeyByProductId[product.id] = _variantKey(item);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: isSelected ? const Color(0xFF88C84A) : const Color(0xFFF1F5EF), borderRadius: BorderRadius.circular(999)),
                          child: Text(item.displayLabel, style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF405148), fontWeight: FontWeight.w700)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          Text('PKR ${_formatPrice(currentPrice)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF181A18))),
                          if (originalPrice > currentPrice)
                            Text('PKR ${_formatPrice(originalPrice)}', style: const TextStyle(fontSize: 14, color: Color(0xFF8A8A8A), decoration: TextDecoration.lineThrough)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: (isGlobalBlocked || !product.isAvailable) ? null : () => _addToCart(context, product, variant, isOpen: isOpen, isGlobalBlocked: isGlobalBlocked),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF88C84A),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFC7D5C1),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          child: Text(isGlobalBlocked ? _tr('Unavailable') : _tr('Add to Cart')),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(Map<String, dynamic> store, Product product, ProductVariant? variant, {required bool isOpen, required String closedReason}) {
    final facts = _productFacts(product, variant, store);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Product Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF252826))),
          const SizedBox(height: 10),
          ...facts.map(
            (fact) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 6, color: Color(0xFF6B756F)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(fact, style: const TextStyle(fontSize: 15, color: Color(0xFF6B756F), height: 1.35)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoPill(icon: isOpen ? Icons.check_circle : Icons.schedule, label: isOpen ? 'Open now' : 'Currently closed', color: isOpen ? const Color(0xFF88C84A) : const Color(0xFFE36A6A)),
              _InfoPill(icon: Icons.location_on_outlined, label: (store['location'] ?? 'Store location').toString(), color: const Color(0xFF74A8C7)),
              _InfoPill(icon: Icons.access_time_rounded, label: '${_formatTimeOnly(store['opening_time'])} - ${_formatTimeOnly(store['closing_time'])}', color: const Color(0xFFA2B57B)),
            ],
          ),
          if (!isOpen && closedReason.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(closedReason, style: const TextStyle(color: Color(0xFFC45454), fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionsRow(BuildContext context, List<Product> products, {required bool isOpen, required bool isGlobalBlocked}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('You Might Also Like', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF252826))),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final product = products[index];
                final variant = _selectedVariantFor(product);
                final price = variant?.effectivePrice ?? product.effectivePrice;
                final discount = _discountPercent(product, variant);
                final imageUrl = ApiService.getImageUrl(product.imageUrl);

                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() => _selectedProductId = product.id),
                  child: Container(
                    width: 145,
                    decoration: BoxDecoration(color: const Color(0xFFF8FAF7), borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF7FAF8), Color(0xFFE8F1EC)]),
                                  ),
                                ),
                                if (discount != null)
                                  Positioned(
                                    top: 10,
                                    left: 10,
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: const BoxDecoration(color: Color(0xFF88C84A), shape: BoxShape.circle),
                                      alignment: Alignment.center,
                                      child: Text('$discount%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                                    ),
                                  ),
                                Center(
                                  child: imageUrl.isNotEmpty
                                      ? Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Image.network(imageUrl, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.fastfood_rounded, size: 44, color: Color(0xFFA0B4AA))),
                                        )
                                      : const Icon(Icons.fastfood_rounded, size: 44, color: Color(0xFFA0B4AA)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF2B322E))),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('PKR ${_formatPrice(price)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF181A18))),
                                  ),
                                  InkWell(
                                    onTap: () => _addToCart(context, product, variant, isOpen: isOpen, isGlobalBlocked: isGlobalBlocked),
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: const BoxDecoration(color: Color(0xFF88C84A), shape: BoxShape.circle),
                                      child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
    );
  }
}

class _StoreBackdrop extends StatelessWidget {
  const _StoreBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: const [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFD3EEB8), Color(0xFFD3EFE3), Color(0xFFAFD9F7)],
            ),
          ),
        ),
        _BackdropOrb(alignment: Alignment(-1.15, -0.88), size: 260, color: Color(0x40BCE08A)),
        _BackdropOrb(alignment: Alignment(1.05, -0.15), size: 220, color: Color(0x30E2B6AE)),
        _BackdropOrb(alignment: Alignment(0.95, 0.78), size: 240, color: Color(0x3089B8F1)),
        _BackdropOrb(alignment: Alignment(-1.1, 0.72), size: 180, color: Color(0x38CDE7CC)),
      ],
    );
  }
}

class _BackdropOrb extends StatelessWidget {
  final Alignment alignment;
  final double size;
  final Color color;

  const _BackdropOrb({required this.alignment, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [BoxShadow(color: color, blurRadius: 80, spreadRadius: 10)],
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CircleButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.84),
        foregroundColor: const Color(0xFF12221A),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String message;
  final bool blocked;

  const _StatusBanner({required this.message, required this.blocked});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: blocked ? const Color(0xFFFFF0EF) : const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: blocked ? const Color(0xFFF2B5AE) : const Color(0xFFE8D3A1)),
      ),
      child: Row(
        children: [
          Icon(blocked ? Icons.block_rounded : Icons.info_outline_rounded, color: blocked ? const Color(0xFFD75B4D) : const Color(0xFF9C7A20)),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF364239)))),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoPill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _EmptyStoreCard extends StatelessWidget {
  const _EmptyStoreCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(24)),
      child: const Text('No products are available in this store right now.', style: TextStyle(fontSize: 16, color: Color(0xFF5F6A64), fontWeight: FontWeight.w600)),
    );
  }
}

