import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../providers/cart_provider.dart';
import '../models/cart_item.dart';
import 'package:servenow/services/notifier.dart';

class StoreScreen extends StatefulWidget {
  final int storeId;

  const StoreScreen({super.key, required this.storeId});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  late Future<Map<String, dynamic>> _storeDetailsFuture;
  final Map<int, String> _selectedVariantKeyByProductId = {};

  String _variantKey(ProductVariant v) {
    return '${v.sizeId ?? 'n'}:${v.unitId ?? 'n'}';
  }

  int _crossAxisCountFor(double width, Orientation orientation) {
    if (orientation == Orientation.landscape) {
      if (width >= 1000) return 3;
      return 2;
    }
    return 2;
  }

  @override
  void initState() {
    super.initState();
    _storeDetailsFuture = ApiService.getStoreDetails(widget.storeId);
  }

  Future<void> _refresh() async {
    setState(() {
      _storeDetailsFuture = ApiService.getStoreDetails(widget.storeId);
    });
    await _storeDetailsFuture;
  }

  List<List<T>> _chunk<T>(List<T> list, int size) {
    return List.generate(
      (list.length / size).ceil(),
      (i) => list.sublist(
        i * size,
        (i + 1) * size > list.length ? list.length : (i + 1) * size,
      ),
    );
  }

  void _addToCart(
    BuildContext context,
    Product product,
    ProductVariant? variant, {
    required bool isOpen,
  }) {
    if (!isOpen) {
      if (!mounted) return;
      Notifier.error(
        context,
        'This store is currently closed. You cannot place orders at this time.',
        duration: const Duration(seconds: 4),
        sanitize: false,
      );
      Navigator.of(context).pop(); // Go back to main home screen
      return;
    }

    final cart = Provider.of<CartProvider>(context, listen: false);

    if (product.stockQuantity <= 0) {
      Notifier.info(context, 'Out of stock');
      return;
    }

    // Check if adding more exceeds stock
    final existingItem = cart.items.firstWhere(
      (item) =>
          item.product.id == product.id &&
          item.variant?.sizeId == variant?.sizeId &&
          item.variant?.unitId == variant?.unitId,
      orElse: () => CartItem(product: product, quantity: 0),
    );

    if (existingItem.quantity >= product.stockQuantity) {
      Notifier.info(context, 'Only ${product.stockQuantity} available');
      return;
    }

    try {
      final warning = cart.addItem(product, 1, variant: variant);
      if (warning != null) {
        Notifier.info(context, warning);
      } else {
        Notifier.success(
          context,
          'Added to cart',
          duration: const Duration(seconds: 1),
        );
      }
    } catch (e) {
      Notifier.error(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Details'),
        actions: [
          Consumer<CartProvider>(
            builder: (ctx, cart, child) => Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart),
                  onPressed: () {
                    Navigator.of(context).pushNamed('/cart');
                  },
                ),
                if (cart.itemCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '${cart.itemCount}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _storeDetailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final data = snapshot.data;
          if (data == null || data['success'] != true) {
            return const Center(child: Text('Store not found'));
          }

          final store = data['store'];
          final bool isOpen = store['is_open'] == true || store['is_open'] == 1;
          final String closedReason =
              (store['status_message'] ?? '').toString().trim();
          final productsList = data['products'] as List<dynamic>? ?? [];
          final products = productsList
              .map((json) => Product.fromJson(json))
              .toList();
          final media = MediaQuery.of(context);
          final crossAxisCount = _crossAxisCountFor(
            media.size.width,
            media.orientation,
          );

          final chunkedProducts = _chunk(products, crossAxisCount);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Status indicator on a separate row inside the card
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isOpen
                                      ? Colors.green.shade100
                                      : Colors.red.shade100,
                                ),
                                child: Center(
                                  child: Text(
                                    isOpen ? '🟢 OPEN' : '🔴 CLOSED',
                                    style: TextStyle(
                                      color: isOpen
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                              if (!isOpen && closedReason.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                                  child: Text(
                                    closedReason,
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (ApiService.getImageUrl(
                                store['image_url'],
                              ).isNotEmpty)
                                Image.network(
                                  ApiService.getImageUrl(store['image_url']),
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (ctx, err, _) => Container(
                                    height: 200,
                                    color: Colors.grey[300],
                                    child: const Icon(
                                      Icons.store,
                                      size: 80,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      store['name'],
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          size: 16,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            store['location'],
                                            style: const TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.access_time,
                                          size: 16,
                                          color: Colors.green,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Open: ${_formatTimeOnly(store['opening_time'])}',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        const Icon(
                                          Icons.timer_off,
                                          size: 16,
                                          color: Colors.red,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Close: ${_formatTimeOnly(store['closing_time'])}',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (store['rating'] != null)
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.star,
                                            size: 16,
                                            color: Colors.amber,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${store['rating']}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
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
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Products',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, rowIndex) {
                      final rowItems = chunkedProducts[rowIndex];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...rowItems.map((product) {
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  child: _buildProductCard(
                                    context,
                                    product,
                                    crossAxisCount,
                                    isOpen,
                                  ),
                                ),
                              );
                            }),
                            // Fill empty slots in the last row
                            if (rowItems.length < crossAxisCount)
                              ...List.generate(
                                crossAxisCount - rowItems.length,
                                (index) => const Expanded(child: SizedBox()),
                              ),
                          ],
                        ),
                      );
                    }, childCount: chunkedProducts.length),
                  ),
                ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 50)),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatTimeOnly(dynamic time) {
    if (time == null) return '--:--';
    final parts = time.toString().split(':');
    if (parts.length >= 2) {
      return '${parts[0]}:${parts[1]}';
    }
    return time.toString();
  }


  Widget _buildProductCard(
    BuildContext context,
    Product product,
    int crossAxisCount,
    bool isOpen,
  ) {
    final variants = product.sizeVariants;
    final selectedVariant = variants.isNotEmpty
        ? (() {
            final selectedKey = _selectedVariantKeyByProductId[product.id];
            if (selectedKey == null) return variants.first;
            return variants.firstWhere(
              (v) => _variantKey(v) == selectedKey,
              orElse: () => variants.first,
            );
          })()
        : null;
    final displayPrice = selectedVariant?.price ?? product.price;

    if (crossAxisCount == 1) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Product Image
              SizedBox(
                width: 110,
                child: ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(12),
                  ),
                  child: ApiService.getImageUrl(product.imageUrl).isNotEmpty
                      ? Image.network(
                          ApiService.getImageUrl(product.imageUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, _) =>
                              const Icon(Icons.image_not_supported, size: 30),
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: Icon(
                              Icons.fastfood,
                              size: 30,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                ),
              ),
              // Product Details
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'PKR $displayPrice',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (variants.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        if (variants.length == 1)
                          Text(
                            variants.first.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          )
                        else
                          RadioGroup<String>(
                            groupValue: selectedVariant == null
                                ? null
                                : _variantKey(selectedVariant),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedVariantKeyByProductId[product.id] =
                                      value;
                                });
                              }
                            },
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: variants.map((v) {
                                final key = _variantKey(v);
                                final isSelected =
                                    selectedVariant != null &&
                                    _variantKey(selectedVariant) == key;
                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedVariantKeyByProductId[product
                                              .id] =
                                          key;
                                    });
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: Radio<String>(
                                          value: key,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                      Text(
                                        v.displayLabel,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isSelected
                                              ? Colors.blue
                                              : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 32,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _addToCart(
                            context,
                            product,
                            selectedVariant,
                            isOpen: isOpen,
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: const Text('Add to Cart'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed height image container
          SizedBox(
            height: 90,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              child: ApiService.getImageUrl(product.imageUrl).isNotEmpty
                  ? Image.network(
                      ApiService.getImageUrl(product.imageUrl),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, _) =>
                          const Icon(Icons.image_not_supported, size: 30),
                    )
                  : Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(
                          Icons.fastfood,
                          size: 24,
                          color: Colors.grey,
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'PKR ${displayPrice.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (variants.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  RadioGroup<String>(
                    groupValue: selectedVariant == null
                        ? null
                        : _variantKey(selectedVariant),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedVariantKeyByProductId[product.id] = value;
                        });
                      }
                    },
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      alignment: WrapAlignment.start,
                      children: variants.map((v) {
                        final key = _variantKey(v);
                        final isSelected =
                            selectedVariant != null &&
                            _variantKey(selectedVariant) == key;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedVariantKeyByProductId[product.id] = key;
                            });
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 20,
                                width: 20,
                                child: Radio<String>(
                                  value: key,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: const VisualDensity(
                                    horizontal: VisualDensity.minimumDensity,
                                    vertical: VisualDensity.minimumDensity,
                                  ),
                                ),
                              ),
                              Text(
                                v.displayLabel,
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.blue
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  height: 28,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      elevation: 0,
                    ),
                    onPressed: product.isAvailable
                        ? () => _addToCart(
                            context,
                            product,
                            selectedVariant,
                            isOpen: isOpen,
                          )
                        : null,
                    child: Text(
                      product.isAvailable ? 'ADD' : 'N/A',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
