import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../providers/cart_provider.dart';
import '../theme/customer_palette.dart';
import '../utils/customer_language.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  static const int _activeBottomIndex = 3;
  bool _isUrdu = false;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  Future<void> _loadLanguagePreference() async {
    final isUrdu = await CustomerLanguage.loadIsUrdu();
    if (!mounted) return;
    setState(() => _isUrdu = isUrdu);
  }

  String _tr(String text) => CustomerLanguage.tr(_isUrdu, text);

  Future<void> _refresh() async {
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CartProvider>(
      builder: (context, cart, child) {
        final uniqueStoreCount = cart.items
            .map(
              (item) =>
                  item.product.storeId?.toString() ??
                  'name:${item.product.storeName ?? item.product.id}',
            )
            .toSet()
            .length;
        final totalProductsCount = cart.items.fold<int>(
          0,
          (sum, item) => sum + item.quantity,
        );

        return Directionality(
          textDirection: CustomerLanguage.textDirection(_isUrdu),
          child: Scaffold(
          appBar: AppBar(
            title: Text(_tr('Your Cart')),
            actions: [
              if (cart.items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(_tr('Clear Cart?')),
                        content: Text(
                          _tr('Are you sure you want to remove all items?'),
                        ),
                        actions: [
                          TextButton(
                            child: Text(_tr('No')),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                          TextButton(
                            child: Text(_tr('Yes')),
                            onPressed: () {
                              cart.clear();
                              Navigator.of(ctx).pop();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: cart.items.isEmpty
                ? Center(
                    child: Text(
                      _tr('Your cart is empty'),
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  )
                : Column(
                    children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: cart.items.length,
                        itemBuilder: (context, index) {
                          final item = cart.items[index];
                          final dismissKey =
                              '${item.product.id}-${item.variant?.sizeId ?? 'n'}-${item.variant?.unitId ?? 'n'}';
                          return Dismissible(
                            key: ValueKey(dismissKey),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) {
                              cart.removeCartItem(item);
                            },
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child:
                                  const Icon(Icons.delete, color: Colors.white),
                            ),
                            child: Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 4,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.product.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.product.storeName ?? _tr('Unknown Store'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: CustomerPalette.primaryDark,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        ApiService.getImageUrl(
                                          item.product.imageUrl,
                                        ).isNotEmpty
                                            ? Image.network(
                                                ApiService.getImageUrl(
                                                  item.product.imageUrl,
                                                ),
                                                width: 50,
                                                height: 50,
                                                fit: BoxFit.cover,
                                                errorBuilder: (ctx, err, _) =>
                                                    const Icon(Icons
                                                        .image_not_supported),
                                              )
                                            : const Icon(Icons.fastfood,
                                                size: 50),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item.variantLabel != null
                                                ? '${item.variantLabel} • PKR ${item.total.toStringAsFixed(2)}'
                                                : '${_tr('Total')}: ${_tr('PKR')} ${item.total.toStringAsFixed(2)}',
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 28,
                                              height: 28,
                                              child: IconButton(
                                                padding: EdgeInsets.zero,
                                                icon: const Icon(Icons.remove,
                                                    size: 16),
                                                onPressed: () {
                                                  if (item.quantity > 1) {
                                                    cart.updateCartItemQuantity(
                                                      item,
                                                      item.quantity - 1,
                                                    );
                                                  } else {
                                                    cart.removeCartItem(item);
                                                  }
                                                },
                                              ),
                                            ),
                                            SizedBox(
                                              width: 24,
                                              child: Center(
                                                child: Text(
                                                  '${item.quantity}',
                                                  style: const TextStyle(
                                                      fontSize: 14, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 28,
                                              height: 28,
                                              child: IconButton(
                                                padding: EdgeInsets.zero,
                                                icon: const Icon(Icons.add,
                                                    size: 16),
                                                onPressed: () {
                                                  final warning = cart.updateCartItemQuantity(
                                                    item,
                                                    item.quantity + 1,
                                                  );
                                                  if (warning != null) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text(warning)),
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Card(
                      margin: const EdgeInsets.all(15),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _tr('Total'),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${_tr('PKR')} ${cart.totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: CustomerPalette.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildSummaryMetaTile(
                                    label: _tr('Total Stores'),
                                    value: '$uniqueStoreCount',
                                    icon: Icons.storefront,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildSummaryMetaTile(
                                    label: _tr('Total Products'),
                                    value: '$totalProductsCount',
                                    icon: Icons.shopping_bag_outlined,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: CustomerPalette.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            Navigator.of(context).pushNamed('/checkout');
                          },
                          child: Text(
                            _tr('Proceed to Checkout'),
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                    ),
                  ],
            ),
          ),
          bottomNavigationBar: _buildBottomBar(),
        ));
      },
    );
  }

  Widget _buildSummaryMetaTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: CustomerPalette.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: CustomerPalette.primaryDark),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: CustomerPalette.primaryDark,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
              label: _tr('Home'),
              onTap: () => Navigator.of(context).pushReplacementNamed('/home'),
            ),
            _buildBottomIcon(
              index: 1,
              icon: Icons.storefront,
              label: _tr('Stores'),
              onTap: () => Navigator.of(context).pushReplacementNamed('/home'),
            ),
            _buildBottomIcon(
              index: 2,
              icon: Icons.shopping_bag,
              label: _tr('Orders'),
              onTap: () => Navigator.of(context).pushReplacementNamed('/orders'),
            ),
            _buildBottomIcon(
              index: 3,
              icon: Icons.shopping_cart,
              label: _tr('Cart'),
              onTap: () {},
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
}
