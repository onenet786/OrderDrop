import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
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

  Future<void> _promptGuestRegistration() async {
    final shouldRegister = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('Register Required')),
        content: Text(
          _tr(
            'Guest users can add items to cart, but registration is required before placing an order.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_tr('Later')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_tr('Register')),
          ),
        ],
      ),
    );

    if (shouldRegister == true && mounted) {
      Navigator.of(context).pushNamed('/register');
    }
  }

  Future<void> _refresh() async {
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CartProvider>(
      builder: (context, cart, child) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final user = auth.user;
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
        final deliveryName =
            user == null
                ? _tr('Guest Customer')
                : '${user.firstName} ${user.lastName}'.trim().isEmpty
                ? _tr('Customer')
                : '${user.firstName} ${user.lastName}'.trim();
        final deliveryAddress =
            (user?.address ?? '').trim().isNotEmpty
                ? user!.address!.trim()
                : _tr('Add your delivery address at checkout');

        return Directionality(
          textDirection: CustomerLanguage.textDirection(_isUrdu),
          child: Scaffold(
            backgroundColor: const Color(0xFFD8EED3),
            body: Stack(
              children: [
                const _CustomerGlassBackdrop(),
                RefreshIndicator(
                  onRefresh: _refresh,
                  child: SafeArea(
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(34),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.34),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF4A7F74,
                                  ).withValues(alpha: 0.14),
                                  blurRadius: 32,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                              child: cart.items.isEmpty
                                  ? _buildEmptyCartState(context)
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildCartHeader(context, cart),
                                        const SizedBox(height: 20),
                                        Center(
                                          child: Text(
                                            _tr('Order Details'),
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF202522),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.94),
                                            borderRadius: BorderRadius.circular(18),
                                          ),
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _tr('Order Summary'),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              ...cart.items.map(
                                                (item) => Padding(
                                                  padding: const EdgeInsets.only(bottom: 10),
                                                  child: _buildOrderSummaryRow(item),
                                                ),
                                              ),
                                              const Divider(height: 22),
                                              _buildSummaryValueRow(
                                                _tr('Subtotal'),
                                                'PKR ${cart.totalAmount.toStringAsFixed(2)}',
                                              ),
                                              const SizedBox(height: 8),
                                              _buildSummaryValueRow(
                                                _tr('Delivery Fee'),
                                                _tr('At checkout'),
                                              ),
                                              const SizedBox(height: 10),
                                              _buildSummaryValueRow(
                                                _tr('Total'),
                                                'PKR ${cart.totalAmount.toStringAsFixed(2)}',
                                                highlight: true,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.94),
                                            borderRadius: BorderRadius.circular(18),
                                          ),
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _tr('Delivery Information'),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '${_tr('Address')}: ${_tr('Today')}',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    width: 82,
                                                    height: 58,
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(
                                                        colors: [
                                                          Color(0xFFEAF3F2),
                                                          Color(0xFFD8EAF3),
                                                        ],
                                                      ),
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: const Icon(
                                                      Icons.location_on_rounded,
                                                      color: Color(0xFF8BCB45),
                                                      size: 28,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          deliveryName,
                                                          style: const TextStyle(
                                                            fontSize: 15,
                                                            fontWeight: FontWeight.w700,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          deliveryAddress,
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: Colors.grey.shade700,
                                                            height: 1.3,
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
                                        const SizedBox(height: 18),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF88C84A),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              padding: const EdgeInsets.symmetric(vertical: 18),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                            ),
                                            onPressed: () {
                                              if (auth.isGuest) {
                                                _promptGuestRegistration();
                                                return;
                                              }
                                              Navigator.of(context).pushNamed('/checkout');
                                            },
                                            child: Text(
                                              _tr('Proceed to Checkout'),
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                                          children: [
                                            TextButton(
                                              onPressed: () => cart.clear(),
                                              child: Text(_tr('Clear Cart')),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.of(context).pushReplacementNamed('/home'),
                                              child: Text(_tr('Continue Shopping')),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(_tr('Support is available at checkout')),
                                                  ),
                                                );
                                              },
                                              child: Text(_tr('Contact Support')),
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
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: _buildSummaryMetaTile(
                                                label: _tr('Items'),
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
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: _buildBottomBar(),
          ),
        );
      },
    );
  }

  Widget _buildCartHeader(BuildContext context, CartProvider cart) {
    return Row(
      children: [
        _GlassIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Image.asset(
            'assets/icon/logo_w.png',
            height: 64,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            errorBuilder: (_, _, _) => const Text(
              'OrderDrop',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Color(0xFF13201B),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _GlassIconButton(
          icon: Icons.delete_outline_rounded,
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(_tr('Clear Cart?')),
                content: Text(_tr('Are you sure you want to remove all items?')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(_tr('No')),
                  ),
                  TextButton(
                    onPressed: () {
                      cart.clear();
                      Navigator.of(ctx).pop();
                    },
                    child: Text(_tr('Yes')),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildOrderSummaryRow(dynamic item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.product.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                item.variantLabel != null
                    ? item.variantLabel!
                    : (item.product.storeName ?? _tr('Unknown Store')),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'x ${item.quantity}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              'PKR ${item.total.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryValueRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: highlight ? 15 : 14,
            fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: highlight ? 15 : 14,
            fontWeight: highlight ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCartState(BuildContext context) {
    return Column(
      children: [
        _buildCartHeader(context, Provider.of<CartProvider>(context, listen: false)),
        const SizedBox(height: 28),
        const Icon(
          Icons.shopping_cart_outlined,
          size: 64,
          color: Color(0xFF88C84A),
        ),
        const SizedBox(height: 14),
        Text(
          _tr('Your cart is empty'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
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
              color: active ? CustomerPalette.primaryDark : Colors.grey.shade600,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? CustomerPalette.primaryDark : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerGlassBackdrop extends StatelessWidget {
  const _CustomerGlassBackdrop();

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
              colors: [
                Color(0xFFD3EEB8),
                Color(0xFFD3EFE3),
                Color(0xFFAFD9F7),
              ],
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

  const _BackdropOrb({
    required this.alignment,
    required this.size,
    required this.color,
  });

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
            boxShadow: [
              BoxShadow(color: color, blurRadius: 80, spreadRadius: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _GlassIconButton({required this.icon, this.onTap});

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
