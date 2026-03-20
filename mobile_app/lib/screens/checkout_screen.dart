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
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _instructionsController = TextEditingController();
  String _paymentMethod = 'cash';
  String? _selectedDeliveryTime;
  bool _isLoading = false;
  double? _walletBalance;
  bool _isUrdu = false;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
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
      if (_walletBalance! < cart.totalAmount) {
        if (!mounted) return;
        Notifier.error(
          context,
          '${_tr('Insufficient wallet balance. Need')} ${_tr('PKR')} ${(cart.totalAmount - _walletBalance!).toStringAsFixed(2)} ${_tr('more.')}',
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
          appBar: AppBar(title: Text(_tr('Checkout'))),
          body: Center(child: Text(_tr('Your cart is empty'))),
        ),
      );
    }

    return Directionality(
      textDirection: CustomerLanguage.textDirection(_isUrdu),
      child: Scaffold(
      appBar: AppBar(title: Text(_tr('Checkout'))),
      resizeToAvoidBottomInset: true,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 800;
                  final sidePadding = isWide
                      ? (constraints.maxWidth - 800) / 2
                      : 0.0;

                  final content = Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Order Summary Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.receipt_long, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      _tr('Order Summary'),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Builder(
                                  builder: (context) {
                                    final Map<String, List<CartItem>>
                                    itemsByStore = {};
                                    for (var item in cart.items) {
                                      final store =
                                          item.product.storeName ??
                                          _tr('Unknown Store');
                                      if (!itemsByStore.containsKey(store)) {
                                        itemsByStore[store] = [];
                                      }
                                      itemsByStore[store]!.add(item);
                                    }

                                    final numStores = itemsByStore.length;

                                    double getDeliveryFee(int stores) {
                                      if (stores == 1) {
                                        return 70;
                                      } else if (stores == 2) {
                                        return 100;
                                      } else if (stores >= 3) {
                                        return 130 + (stores - 3) * 30;
                                      } else {
                                        return 70;
                                      }
                                    }

                                    final deliveryFee = getDeliveryFee(
                                      numStores,
                                    );
                                    double grandTotal =
                                        cart.totalAmount + deliveryFee;

                                    List<Widget> allChildren = [];

                                    for (var entry in itemsByStore.entries) {
                                      double storeSubtotal = entry.value.fold(
                                        0.0,
                                        (sum, item) => sum + item.total,
                                      );

                                      allChildren.add(
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8.0,
                                            bottom: 8.0,
                                          ),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .primaryColor
                                                  .withAlpha(
                                                    (0.15 * 255).round(),
                                                  ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border(
                                                left: BorderSide(
                                                  color: Theme.of(
                                                    context,
                                                  ).primaryColor,
                                                  width: 3,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              entry.key,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Theme.of(
                                                  context,
                                                ).primaryColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );

                                      for (var item in entry.value) {
                                        allChildren.add(
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6.0,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        item.product.name,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      Text(
                                                        item.variantLabel !=
                                                                null
                                                            ? '${item.variantLabel} • ${item.quantity} x PKR ${item.unitPrice}'
                                                            : '${item.quantity} x PKR ${item.unitPrice}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              Colors.grey[600],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'PKR ${item.total.toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      allChildren.add(
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8.0,
                                            bottom: 4.0,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${_tr('Subtotal')} (${entry.key}):',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 2,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'PKR ${storeSubtotal.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );

                                      allChildren.add(
                                        const Divider(height: 12),
                                      );
                                    }

                                    allChildren.add(const SizedBox(height: 8));

                                    allChildren.add(
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8.0,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${_tr('Delivery Fee')} ($numStores ${_tr('Stores')}):',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 2,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'PKR ${deliveryFee.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );

                                    allChildren.add(
                                      Container(
                                        padding: const EdgeInsets.only(top: 8),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            top: BorderSide(
                                              color: Colors.grey[300]!,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _tr('Grand Total'),
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 2,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'PKR ${grandTotal.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: allChildren,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Delivery Details Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.local_shipping, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      _tr('Delivery Details'),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _nameController,
                                  decoration: InputDecoration(
                                    label: Text(
                                      _tr('Full Name'),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.person),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return _tr('Full Name');
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _phoneController,
                                  decoration: InputDecoration(
                                    label: Text(
                                      _tr('Phone Number'),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.phone),
                                  ),
                                  keyboardType: TextInputType.phone,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return _tr('Phone Number');
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _addressController,
                                  decoration: InputDecoration(
                                    label: Text(
                                      _tr('Delivery Address'),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.location_on),
                                  ),
                                  maxLines: 2,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return _tr('Delivery Address');
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedDeliveryTime,
                                  decoration: InputDecoration(
                                    label: Text(
                                      _tr('Preferred Delivery Time'),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.access_time),
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: 'asap',
                                      child: Text(_tr('ASAP (30-45 mins)')),
                                    ),
                                    DropdownMenuItem(
                                      value: '1hour',
                                      child: Text(_tr('Within 1 hour')),
                                    ),
                                    DropdownMenuItem(
                                      value: '2hours',
                                      child: Text(_tr('Within 2 hours')),
                                    ),
                                    DropdownMenuItem(
                                      value: 'tomorrow',
                                      child: Text(_tr('Tomorrow')),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedDeliveryTime = value;
                                    });
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _instructionsController,
                                  decoration: InputDecoration(
                                    label: Text(
                                      _tr('Special Instructions'),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.note),
                                  ),
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Payment Method Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.payment, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      _tr('Payment Method'),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
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
                                if (_paymentMethod == 'wallet' &&
                                    _walletBalance != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 12,
                                      left: 4,
                                      right: 4,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color:
                                            _walletBalance! >= cart.totalAmount
                                            ? Colors.green.shade50
                                            : Colors.red.shade50,
                                        border: Border.all(
                                          color:
                                              _walletBalance! >=
                                                  cart.totalAmount
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _walletBalance! >= cart.totalAmount
                                                ? Icons.check_circle
                                                : Icons.error,
                                            color:
                                                _walletBalance! >=
                                                    cart.totalAmount
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${_tr('Wallet')}: ${_tr('PKR')} ${_walletBalance!.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        _walletBalance! >=
                                                            cart.totalAmount
                                                        ? Colors.green
                                                        : Colors.red,
                                                  ),
                                                ),
                                                if (_walletBalance! <
                                                    cart.totalAmount)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
                                                    child: Text(
                                                      '${_tr('Insufficient wallet balance. Need')} ${_tr('PKR')} ${(cart.totalAmount - _walletBalance!).toStringAsFixed(2)} ${_tr('more.')}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.lock_outline),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: _submitOrder,
                            label: Text(
                              _tr('Place Order'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  );

                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16 + sidePadding,
                      16,
                      16 + sidePadding,
                      16,
                    ),
                    child: content,
                  );
                },
              ),
            ),
    ));
  }
}
