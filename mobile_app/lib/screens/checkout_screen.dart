import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../models/cart_item.dart';
import '../providers/wallet_provider.dart';
import '../services/api_service.dart';
import 'package:servenow/services/notifier.dart';
import '../utils/customer_language.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  static const double _defaultDeliveryFeeBase = 70;
  static const double _defaultDeliveryFeeAdditional = 30;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _instructionsController = TextEditingController();
  String _paymentMethod = 'cash';
  String? _selectedDeliveryTime;
  bool _isLoading = false;
  bool _isDeliveryFeeConfigLoading = true;
  double? _walletBalance;
  bool _isUrdu = false;
  double _deliveryFeeBase = _defaultDeliveryFeeBase;
  double _deliveryFeeAdditional = _defaultDeliveryFeeAdditional;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _loadDeliveryFeeConfig();
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null) {
      _nameController.text = '${user.firstName} ${user.lastName}'.trim();
      if (user.phone != null) {
        _phoneController.text = user.phone!;
      }
      if (user.address != null) {
        _addressController.text = user.address!;
      }
    }
    _loadWalletBalance();
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
            'You are using guest mode. Please register your account before placing an order.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_tr('Cancel')),
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

  Future<void> _loadDeliveryFeeConfig() async {
    try {
      final data = await ApiService.getDeliveryFeeConfig();
      final base = _parseAmount(data['base_fee']);
      final additional = _parseAmount(data['additional_per_store']);
      if (!mounted) return;
      setState(() {
        if (base != null && base >= 0) {
          _deliveryFeeBase = base;
        }
        if (additional != null && additional >= 0) {
          _deliveryFeeAdditional = additional;
        }
        _isDeliveryFeeConfigLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading delivery fee config: $e');
      if (!mounted) return;
      setState(() {
        _isDeliveryFeeConfigLoading = false;
      });
    }
  }

  double? _parseAmount(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int _getStoreCount(CartProvider cart) {
    return cart.items
        .map((item) => item.product.storeId ?? item.product.storeName ?? item.product.id)
        .toSet()
        .length;
  }

  double _calculateDeliveryFee(int storeCount) {
    if (storeCount <= 0) return 0;
    return _deliveryFeeBase + ((storeCount - 1) * _deliveryFeeAdditional);
  }

  double _calculateGrandTotal(CartProvider cart) {
    return cart.totalAmount + _calculateDeliveryFee(_getStoreCount(cart));
  }

  Future<void> _loadWalletBalance() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final wallet = Provider.of<WalletProvider>(context, listen: false);

      if (auth.token != null) {
        await wallet.loadWalletBalance(auth.token!);
        if (wallet.wallet != null) {
          setState(() {
            _walletBalance = wallet.wallet!.balance;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading wallet balance: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Widget _buildPaymentOption({
    required String title,
    required String value,
    required IconData icon,
    String? subtitle,
  }) {
    final isSelected = _paymentMethod == value;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => setState(() => _paymentMethod = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? scheme.primary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? scheme.primaryContainer.withAlpha((0.25 * 255).round())
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? scheme.primary : Colors.grey[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr(title),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? scheme.primary : null,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _tr(subtitle),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  bool _checkIsOpen(dynamic openTimeStr, dynamic closeTimeStr) {
    if (openTimeStr == null || closeTimeStr == null) return false;

    try {
      final now = DateTime.now();
      final currentTime = TimeOfDay.fromDateTime(now);

      TimeOfDay parseTime(String timeStr) {
        final parts = timeStr.split(':');
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }

      final openTime = parseTime(openTimeStr.toString());
      final closeTime = parseTime(closeTimeStr.toString());

      final double nowDouble = currentTime.hour + currentTime.minute / 60.0;
      final double openDouble = openTime.hour + openTime.minute / 60.0;
      final double closeDouble = closeTime.hour + closeTime.minute / 60.0;

      if (openDouble <= closeDouble) {
        return nowDouble >= openDouble && nowDouble <= closeDouble;
      } else {
        // Handle overnight hours (e.g., 22:00 - 04:00)
        return nowDouble >= openDouble || nowDouble <= closeDouble;
      }
    } catch (e) {
      return false;
    }
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      return v == 'true' || v == '1' || v == 'yes';
    }
    return false;
  }

  bool _isWindowActive(Map<String, dynamic> status) {
    if (_toBool(status['is_window_active'])) return true;
    final startRaw = (status['start_at'] ?? '').toString().trim();
    final endRaw = (status['end_at'] ?? '').toString().trim();
    if (startRaw.isEmpty || endRaw.isEmpty) return true;
    final start = DateTime.tryParse(startRaw);
    final end = DateTime.tryParse(endRaw);
    if (start == null || end == null) return true;
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }

  bool _isGlobalOrderingBlocked(Map<String, dynamic> status) {
    final enabled = _toBool(status['is_enabled']);
    if (!enabled) return false;
    if (_toBool(status['block_ordering_active'])) return true;
    final blockOrdering = _toBool(status['block_ordering']);
    return blockOrdering && _isWindowActive(status);
  }

  String _formatDeliveryWindow(dynamic startRaw, dynamic endRaw) {
    final start = DateTime.tryParse((startRaw ?? '').toString());
    final end = DateTime.tryParse((endRaw ?? '').toString());
    if (start == null || end == null) return '';
    final startLocal = start.toLocal();
    final endLocal = end.toLocal();
    return '${startLocal.toString().substring(0, 16)} - ${endLocal.toString().substring(0, 16)}';
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;

    final cart = Provider.of<CartProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    if (cart.items.isEmpty) return;
    if (auth.isGuest) {
      await _promptGuestRegistration();
      return;
    }

    final grandTotal = _calculateGrandTotal(cart);

    setState(() {
      _isLoading = true;
    });

    // Check if website-wide delivery status blocks ordering
    try {
      if (auth.token != null) {
        final data = await ApiService.getGlobalDeliveryStatus(auth.token!);
        final status = (data['status'] is Map<String, dynamic>)
            ? (data['status'] as Map<String, dynamic>)
            : (data['global_status'] is Map<String, dynamic>)
                ? (data['global_status'] as Map<String, dynamic>)
                : data;

        if (_isGlobalOrderingBlocked(status)) {
          final title = (status['title'] ?? '').toString().trim();
          final message = (status['status_message'] ?? '').toString().trim();
          final when = _formatDeliveryWindow(status['start_at'], status['end_at']);
          final displayMessage = message.isNotEmpty
              ? (when.isNotEmpty ? '$message ($when)' : message)
              : (title.isNotEmpty
                    ? (when.isNotEmpty ? '$title ($when)' : title)
                    : _tr('Ordering is temporarily unavailable.'));
          if (!mounted) return;
          setState(() {
            _isLoading = false;
          });
          Notifier.error(
            context,
            displayMessage,
            duration: const Duration(seconds: 4),
            sanitize: false,
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking global delivery status: $e');
    }

    // Check if stores are open
    try {
      final uniqueStoreIds = cart.items
          .map((e) => e.product.storeId)
          .whereType<int>()
          .toSet();

      for (final storeId in uniqueStoreIds) {
        final data = await ApiService.getStoreDetails(storeId);
        if (data['success'] == true) {
          final store = data['store'];
          final bool isOpen = store['is_open'] == true || store['is_open'] == 1;
          if (!isOpen || !_checkIsOpen(store['opening_time'], store['closing_time'])) {
            final reason = (store['status_message'] ?? '').toString().trim();
            if (!mounted) return;
            setState(() {
              _isLoading = false;
            });
            Notifier.error(
              context,
              reason.isNotEmpty
                  ? '${_tr('Store')}: "${store['name']}" ${_tr('Closed')}. $reason'
                  : '${_tr('Store')}: "${store['name']}" ${_tr('This store is currently closed. You cannot place orders at this time.')}',
              duration: const Duration(seconds: 4),
              sanitize: false,
            );
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/home', (route) => false);
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking store status: $e');
    }

    if (_paymentMethod == 'wallet' && _walletBalance != null) {
      if (_walletBalance! < grandTotal) {
        if (!mounted) return;
        Notifier.error(
          context,
          '${_tr('Insufficient wallet balance. Need')} ${_tr('PKR')} ${(grandTotal - _walletBalance!).toStringAsFixed(2)} ${_tr('more.')}',
          sanitize: false,
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final List<Map<String, dynamic>> orderItems = [];

      for (var item in cart.items) {
        final payload = <String, dynamic>{
          'product_id': item.product.id,
          'quantity': item.quantity,
        };
        if (item.variant?.sizeId != null) {
          payload['size_id'] = item.variant!.sizeId;
        }
        if (item.variant?.unitId != null) {
          payload['unit_id'] = item.variant!.unitId;
        }
        if (item.variantLabel != null) {
          payload['variant_label'] = item.variantLabel;
        }
        orderItems.add(payload);
      }

      String combinedInstructions = _instructionsController.text;
      if (_nameController.text.isNotEmpty || _phoneController.text.isNotEmpty) {
        String contactInfo =
            'Contact: ${_nameController.text} (${_phoneController.text})';
        combinedInstructions = combinedInstructions.isEmpty
            ? contactInfo
            : '$contactInfo\n$combinedInstructions';
      }

      await ApiService.createOrder(
        auth.token!,
        storeId: null, // Let backend handle store splitting
        items: orderItems,
        deliveryAddress: _addressController.text,
        paymentMethod: _paymentMethod,
        deliveryTime: _selectedDeliveryTime,
        specialInstructions: combinedInstructions.isNotEmpty
            ? combinedInstructions
            : null,
      );

      // Clear cart
      cart.clear();

      if (!mounted) return;

      // Show success toast and redirect
      Notifier.success(
        context,
        'Your order has been successfully placed.',
        duration: const Duration(seconds: 3),
      );
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/orders', (route) => false);
    } catch (e) {
      if (!mounted) return;
      if (auth.sessionExpired) return;
      Notifier.error(context, '${_tr('Failed to place order')}: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);

    if (cart.items.isEmpty) {
      return Directionality(
        textDirection: CustomerLanguage.textDirection(_isUrdu),
        child: Scaffold(
          backgroundColor: const Color(0xFFD8EED3),
          body: const Center(child: _CheckoutEmptyState()),
        ),
      );
    }

    final deliveryFee = _calculateDeliveryFee(_getStoreCount(cart));
    final grandTotal = _calculateGrandTotal(cart);

    return Directionality(
      textDirection: CustomerLanguage.textDirection(_isUrdu),
      child: Scaffold(
        backgroundColor: const Color(0xFFD8EED3),
        resizeToAvoidBottomInset: true,
        body: (_isLoading || _isDeliveryFeeConfigLoading)
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  const _CheckoutBackdrop(),
                  SafeArea(
                    child: Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
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
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildCheckoutHeader(context),
                                    const SizedBox(height: 18),
                                    Text(
                                      _tr('Checkout'),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF202522),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ...cart.items.map(
                                      (item) => Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: _buildCheckoutItemCard(item),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Divider(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      thickness: 2,
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.94),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
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
                                          const SizedBox(height: 12),
                                          _buildCheckoutSummaryRow(
                                            _tr('Subtotal'),
                                            'PKR ${cart.totalAmount.toStringAsFixed(2)}',
                                          ),
                                          const SizedBox(height: 6),
                                          _buildCheckoutSummaryRow(
                                            _tr('Delivery Fee'),
                                            'PKR ${deliveryFee.toStringAsFixed(2)}',
                                          ),
                                          const SizedBox(height: 6),
                                          _buildCheckoutSummaryRow(
                                            _tr('Total'),
                                            'PKR ${grandTotal.toStringAsFixed(2)}',
                                            highlight: true,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            _tr('Delivery Address'),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF8FBF8),
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                            child: Column(
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: TextFormField(
                                                        controller: _nameController,
                                                        decoration: InputDecoration(
                                                          labelText: _tr('Full Name'),
                                                          isDense: true,
                                                          border: InputBorder.none,
                                                        ),
                                                        validator: (value) => value == null || value.isEmpty ? _tr('Full Name') : null,
                                                      ),
                                                    ),
                                                    TextButton(
                                                      onPressed: () {},
                                                      child: Text(_tr('Edit')),
                                                    ),
                                                  ],
                                                ),
                                                const Divider(height: 8),
                                                TextFormField(
                                                  controller: _addressController,
                                                  decoration: InputDecoration(
                                                    labelText: _tr('Delivery Address'),
                                                    isDense: true,
                                                    border: InputBorder.none,
                                                  ),
                                                  maxLines: 2,
                                                  validator: (value) => value == null || value.isEmpty ? _tr('Delivery Address') : null,
                                                ),
                                                TextFormField(
                                                  controller: _phoneController,
                                                  decoration: InputDecoration(
                                                    labelText: _tr('Phone Number'),
                                                    isDense: true,
                                                    border: InputBorder.none,
                                                  ),
                                                  keyboardType: TextInputType.phone,
                                                  validator: (value) => value == null || value.isEmpty ? _tr('Phone Number') : null,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          DropdownButtonFormField<String>(
                                            initialValue: _selectedDeliveryTime,
                                            decoration: InputDecoration(
                                              labelText: _tr('Preferred Delivery Time'),
                                              filled: true,
                                              fillColor: const Color(0xFFF8FBF8),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(14),
                                                borderSide: BorderSide.none,
                                              ),
                                            ),
                                            items: [
                                              DropdownMenuItem(value: 'asap', child: Text(_tr('ASAP (30-45 mins)'))),
                                              DropdownMenuItem(value: '1hour', child: Text(_tr('Within 1 hour'))),
                                              DropdownMenuItem(value: '2hours', child: Text(_tr('Within 2 hours'))),
                                              DropdownMenuItem(value: 'tomorrow', child: Text(_tr('Tomorrow'))),
                                            ],
                                            onChanged: (value) {
                                              setState(() => _selectedDeliveryTime = value);
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: _instructionsController,
                                            maxLines: 2,
                                            decoration: InputDecoration(
                                              labelText: _tr('Special Instructions'),
                                              filled: true,
                                              fillColor: const Color(0xFFF8FBF8),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(14),
                                                borderSide: BorderSide.none,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          Text(
                                            _tr('Payment Method'),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          RadioGroup<String>(
                                            groupValue: _paymentMethod,
                                            onChanged: (newValue) {
                                              if (newValue != null) {
                                                setState(() => _paymentMethod = newValue);
                                              }
                                            },
                                            child: Column(
                                              children: [
                                                _buildPaymentOption(
                                                  title: 'Cash on Delivery',
                                                  value: 'cash',
                                                  icon: Icons.delivery_dining,
                                                  subtitle: 'Pay with cash at delivery',
                                                ),
                                                const SizedBox(height: 8),
                                                _buildPaymentOption(
                                                  title: 'Credit/Debit Card',
                                                  value: 'card',
                                                  icon: Icons.credit_card,
                                                  subtitle: 'Pay securely with your card',
                                                ),
                                                const SizedBox(height: 8),
                                                _buildPaymentOption(
                                                  title: 'Wallet',
                                                  value: 'wallet',
                                                  icon: Icons.account_balance_wallet,
                                                  subtitle: 'Use your in-app wallet',
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (_paymentMethod == 'wallet' && _walletBalance != null) ...[
                                            const SizedBox(height: 12),
                                            Text(
                                              '${_tr('Wallet')}: ${_tr('PKR')} ${_walletBalance!.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                color: _walletBalance! >= grandTotal ? Colors.green : Colors.red,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: _submitOrder,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF88C84A),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(vertical: 18),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                        ),
                                        child: Text(
                                          _tr('Place Order'),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
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
      ),
    );
  }

  Widget _buildCheckoutHeader(BuildContext context) {
    return Row(
      children: [
        _CheckoutIconButton(
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
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutItemCard(CartItem item) {
    final imageUrl = ApiService.getImageUrl(item.product.imageUrl);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7F3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: imageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.fastfood_rounded),
                    ),
                  )
                : const Icon(Icons.fastfood_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'x ${item.quantity}',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'PKR ${item.total.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutSummaryRow(String label, String value, {bool highlight = false}) {
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
}

class _CheckoutBackdrop extends StatelessWidget {
  const _CheckoutBackdrop();

  @override
  Widget build(BuildContext context) {
    return const _SharedBackdrop();
  }
}

class _CheckoutIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CheckoutIconButton({required this.icon, this.onTap});

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

class _CheckoutEmptyState extends StatelessWidget {
  const _CheckoutEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Text(
        'Your cart is empty',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SharedBackdrop extends StatelessWidget {
  const _SharedBackdrop();

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
        _SharedBackdropOrb(alignment: Alignment(-1.15, -0.88), size: 260, color: Color(0x40BCE08A)),
        _SharedBackdropOrb(alignment: Alignment(1.05, -0.15), size: 220, color: Color(0x30E2B6AE)),
        _SharedBackdropOrb(alignment: Alignment(0.95, 0.78), size: 240, color: Color(0x3089B8F1)),
        _SharedBackdropOrb(alignment: Alignment(-1.1, 0.72), size: 180, color: Color(0x38CDE7CC)),
      ],
    );
  }
}

class _SharedBackdropOrb extends StatelessWidget {
  final Alignment alignment;
  final double size;
  final Color color;

  const _SharedBackdropOrb({required this.alignment, required this.size, required this.color});

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
