import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class ManageProductsScreen extends StatefulWidget {
  const ManageProductsScreen({super.key});

  @override
  State<ManageProductsScreen> createState() => _ManageProductsScreenState();
}

class _ManageProductsScreenState extends State<ManageProductsScreen> {
  final Logger _logger = Logger();
  bool _isLoading = true;
  List<dynamic> _products = [];
  List<dynamic> _filteredProducts = [];
  final TextEditingController _searchController = TextEditingController();
  String _selectedStoreFilter = 'all';
  bool _storeWiseView = true;
  bool _onlyVariantProducts = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      final auth = Provider.of<AuthProvider>(context, listen: false);
      List<dynamic> products = [];
      if (auth.isStoreOwner && auth.user != null) {
        products = await ApiService.getProductsForOwner(token, auth.user!.id);
      } else {
        products = await ApiService.getProductsForAdmin(token);
      }

      setState(() {
        _products = products;
        _isLoading = false;
      });
      _filterProducts();
    } catch (e) {
      _logger.e('Error loading products: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading products: $e')));
      }
    }
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    final List<dynamic> filtered = _products.where((product) {
      final name = (product['name'] ?? product['product_name'] ?? '')
          .toString()
          .toLowerCase();
      final description = (product['description'] ?? '')
          .toString()
          .toLowerCase();
      final store = (product['store_name'] ?? '').toString().toLowerCase();
      final variants = (product['size_variants'] as List<dynamic>? ?? []);
      final hasVariants = variants.isNotEmpty;
      final variantsText = variants
          .map((v) => (v['size_label'] ?? v['unit_name'] ?? 'variant').toString())
          .join(' ')
          .toLowerCase();

      final queryMatch = name.contains(query) ||
          description.contains(query) ||
          store.contains(query) ||
          variantsText.contains(query);

      final selectedStore = _selectedStoreFilter.toLowerCase();
      final storeMatch = selectedStore == 'all' ||
          store == selectedStore;
      final variantMatch = !_onlyVariantProducts || hasVariants;

      return queryMatch && storeMatch && variantMatch;
    }).toList();

    setState(() => _filteredProducts = filtered);
  }

  List<String> _storeFilterOptions() {
    final stores = _products
        .map((p) => (p['store_name'] ?? 'Unknown Store').toString())
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return stores;
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isStoreOwner = auth.isStoreOwner;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          isStoreOwner ? 'My Products (Price Update)' : 'Manage Products',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProducts,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: isStoreOwner
                                ? 'Search by product, description, or variant'
                                : 'Search by product, store, description, or variant',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isStoreOwner)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.indigo.withValues(alpha: 0.20),
                                  ),
                                ),
                                child: const Text(
                                  'Showing only your store products',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              DropdownButtonFormField<String>(
                                initialValue: _selectedStoreFilter,
                                decoration: InputDecoration(
                                  labelText: 'Store',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: 'all',
                                    child: Text('All Stores'),
                                  ),
                                  ..._storeFilterOptions().map(
                                    (store) => DropdownMenuItem(
                                      value: store.toLowerCase(),
                                      child: Text(store),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _selectedStoreFilter = value);
                                  _filterProducts();
                                },
                              ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ChoiceChip(
                                  label: const Text('Store-wise'),
                                  selected: _storeWiseView,
                                  onSelected: (v) {
                                    if (!v) return;
                                    setState(() => _storeWiseView = true);
                                  },
                                ),
                                ChoiceChip(
                                  label: const Text('List'),
                                  selected: !_storeWiseView,
                                  onSelected: (v) {
                                    if (!v) return;
                                    setState(() => _storeWiseView = false);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilterChip(
                            label: const Text('Only products with variants'),
                            selected: _onlyVariantProducts,
                            onSelected: (v) {
                              setState(() => _onlyVariantProducts = v);
                              _filterProducts();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _filteredProducts.isEmpty
                        ? Center(
                            child: Text(
                              'No products found',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : _storeWiseView
                            ? _buildStoreWiseList()
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final product = _filteredProducts[index];
                                  return _buildProductCard(product);
                                },
                              ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStoreWiseList() {
    final grouped = <String, List<dynamic>>{};
    for (final p in _filteredProducts) {
      final store = (p['store_name'] ?? 'Unknown Store').toString();
      grouped.putIfAbsent(store, () => []).add(p);
    }
    final stores = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: stores.length,
      itemBuilder: (context, index) {
        final store = stores[index];
        final items = grouped[store] ?? [];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            title: Text(
              store,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${items.length} products',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            children: [
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  children: items.map<Widget>((p) => _buildProductCard(p)).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductCard(dynamic product) {
    final variants = (product['size_variants'] as List<dynamic>? ?? []);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha((0.1 * 255).round()),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProductImage(product['image_url']),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (product['name'] ?? product['product_name'] ?? 'Unknown').toString(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (product['store_name'] ?? 'Unknown Store').toString(),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'PKR ${(double.tryParse(product['price']?.toString() ?? '0') ?? 0.0).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _openEditPriceSheet(product),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoColumn('Stock', '${product['stock_quantity'] ?? 0}'),
                _buildInfoColumn('Category', product['category_name'] ?? '-'),
              ],
            ),
            if (variants.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Variants',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: variants.map<Widget>((v) {
                  final label =
                      (v['size_label'] ?? v['unit_name'] ?? 'Variant').toString();
                  final price =
                      (double.tryParse(v['price']?.toString() ?? '0') ?? 0.0)
                          .toStringAsFixed(2);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$label - PKR $price',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openEditPriceSheet(dynamic product) {
    final TextEditingController basePriceCtrl = TextEditingController(
      text: (product['price']?.toString() ?? ''),
    );
    final List<dynamic> variants = (product['size_variants'] as List<dynamic>? ?? []);
    final List<TextEditingController> variantCtrls = variants
        .map<TextEditingController>((v) => TextEditingController(text: (v['price']?.toString() ?? '')))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Update Price',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (variants.isEmpty) ...[
                TextField(
                  controller: basePriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price (PKR)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                const Text('Variant Prices', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...List.generate(variants.length, (i) {
                  final v = variants[i];
                  final label = (v['size_label'] ?? v['unit_name'] ?? 'Variant').toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: TextField(
                      controller: variantCtrls[i],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '$label (PKR)',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          final token = Provider.of<AuthProvider>(context, listen: false).token;
                          if (token == null) return;
                          final int productId = int.parse(product['id'].toString());
                          if (variants.isEmpty) {
                            final price = double.tryParse(basePriceCtrl.text);
                            if (price == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please enter a valid price')),
                              );
                              return;
                            }
                            await ApiService.updateProduct(
                              token,
                              productId: productId,
                              price: price,
                            );
                          } else {
                            final List<Map<String, dynamic>> newVariants = [];
                            for (int i = 0; i < variants.length; i++) {
                              final v = variants[i];
                              final p = double.tryParse(variantCtrls[i].text);
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter valid variant prices')),
                                );
                                return;
                              }
                              newVariants.add({
                                'size_id': v['size_id'],
                                'unit_id': v['unit_id'],
                                'price': p,
                              });
                            }
                            await ApiService.updateProduct(
                              token,
                              productId: productId,
                              sizeVariants: newVariants,
                            );
                          }
                          if (!mounted || !ctx.mounted) return;
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Price updated')),
                          );
                          _loadProducts();
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to update: $e')),
                          );
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
  Widget _buildProductImage(String? imageUrl) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(6),
      ),
      child: imageUrl != null && imageUrl.isNotEmpty
          ? Image.network(
              ApiService.getImageUrl(imageUrl),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.image_not_supported);
              },
            )
          : const Icon(Icons.shopping_bag, color: Colors.grey),
    );
  }

  Widget _buildInfoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        Text(
          value.length > 12 ? '${value.substring(0, 12)}...' : value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
