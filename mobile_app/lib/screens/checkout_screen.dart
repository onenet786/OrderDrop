import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../models/cart_item.dart';
import '../providers/wallet_provider.dart';
import '../services/api_service.dart';
import 'package:servenow/services/notifier.dart';

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

  @override
  void initState() {
    super.initState();
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
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? scheme.primary : null,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
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

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;

    final cart = Provider.of<CartProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    if (cart.items.isEmpty) return;

    if (_paymentMethod == 'wallet' && _walletBalance != null) {
      if (_walletBalance! < cart.totalAmount) {
        if (!mounted) return;
        Notifier.error(
          context,
          'Insufficient wallet balance. Need PKR ${(cart.totalAmount - _walletBalance!).toStringAsFixed(2)} more.',
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
        String contactInfo = 'Contact: ${_nameController.text} (${_phoneController.text})';
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

      // Show success dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Order Placed!'),
          content: const Text('Your order has been successfully placed.'),
          actions: [
            TextButton(
              child: const Text('View Orders'),
              onPressed: () {
                Navigator.of(ctx).pop(); // Close dialog
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/orders', (route) => false);
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Notifier.error(context, 'Failed to place order: $e');
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
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: const Center(child: Text('Your cart is empty')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
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
                                  children: const [
                                    Icon(Icons.receipt_long, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Order Summary',
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
                                          'Unknown Store';
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
                                        return 120 + (stores - 3) * 20;
                                      } else {
                                        return 70;
                                      }
                                    }
                                    
                                    final deliveryFee = getDeliveryFee(numStores);
                                    double grandTotal = cart.totalAmount + deliveryFee;

                                    List<Widget> allChildren = [];
                                    
                                    for (var entry in itemsByStore.entries) {
                                      double storeSubtotal = entry.value.fold(0.0, (sum, item) => sum + item.total);
                                      
                                      allChildren.add(
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).primaryColor.withAlpha((0.15 * 255).round()),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border(
                                                left: BorderSide(
                                                  color: Theme.of(context).primaryColor,
                                                  width: 3,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              entry.key,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Theme.of(context).primaryColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                      
                                      for (var item in entry.value) {
                                        allChildren.add(
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        item.product.name,
                                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      Text(
                                                        item.variantLabel != null
                                                            ? '${item.variantLabel} • ${item.quantity} x PKR ${item.unitPrice}'
                                                            : '${item.quantity} x PKR ${item.unitPrice}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey[600],
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
                                          padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Subtotal (${entry.key}):',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
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
                                      
                                      allChildren.add(const Divider(height: 12));
                                    }
                                    
                                    allChildren.add(const SizedBox(height: 8));
                                    
                                    allChildren.add(
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                'Total Delivery Charge ($numStores store${numStores > 1 ? 's' : ''}):',
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
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: const Text(
                                                'Grand Total',
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
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                  children: const [
                                    Icon(Icons.local_shipping, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Delivery Details',
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
                                    label: const Text(
                                      'Contact Name',
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.person),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter contact name';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _phoneController,
                                  decoration: InputDecoration(
                                    label: const Text(
                                      'Phone Number',
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.phone),
                                  ),
                                  keyboardType: TextInputType.phone,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter phone number';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _addressController,
                                  decoration: InputDecoration(
                                    label: const Text(
                                      'Delivery Address',
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.location_on),
                                  ),
                                  maxLines: 2,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter delivery address';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedDeliveryTime,
                                  decoration: InputDecoration(
                                    label: const Text(
                                      'Preferred Delivery Time (Optional)',
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.access_time),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'asap',
                                      child: Text('ASAP (30-45 mins)'),
                                    ),
                                    DropdownMenuItem(
                                      value: '1hour',
                                      child: Text('Within 1 hour'),
                                    ),
                                    DropdownMenuItem(
                                      value: '2hours',
                                      child: Text('Within 2 hours'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'tomorrow',
                                      child: Text('Tomorrow'),
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
                                    label: const Text(
                                      'Special Instructions (Optional)',
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
                                  children: const [
                                    Icon(Icons.payment, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Payment Method',
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
                                                  'Wallet Balance: PKR ${_walletBalance!.toStringAsFixed(2)}',
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
                                                      'Insufficient balance. Need PKR ${(cart.totalAmount - _walletBalance!).toStringAsFixed(2)} more.',
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
                            label: const Text(
                              'Place Order',
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
    );
  }
}
