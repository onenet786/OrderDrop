import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/notification_bell_widget.dart';

class StoreBalancesScreen extends StatefulWidget {
  const StoreBalancesScreen({super.key});

  @override
  State<StoreBalancesScreen> createState() => _StoreBalancesScreenState();
}

class _StoreBalancesScreenState extends State<StoreBalancesScreen> {
  final Logger _logger = Logger();
  final TextEditingController _storeSearchController = TextEditingController();
  bool _isLoading = true;
  String? _error;

  List<Map<String, dynamic>> _storeBalanceRows = [];
  List<Map<String, dynamic>> _storeFilterOptions = [];
  int? _selectedStoreFilterId;
  String _storeSearchQuery = '';
  String _selectedBalanceFilter = 'all';
  String _selectedStoreTab = 'all';

  @override
  void initState() {
    super.initState();
    _loadStoreBalances();
  }

  @override
  void dispose() {
    _storeSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadStoreBalances() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      final stores = await ApiService.getStoresForAdmin(token);
      final storeSalesResponse = await ApiService.getStoreSalesReport(token);
      final storeSales = (storeSalesResponse['store_sales'] as List?) ?? [];
      final storeOrdersResponse =
          await ApiService.getStoreOrderBreakdown(token);
      final storeOrders = (storeOrdersResponse['store_orders'] as List?) ?? [];
      Map<String, dynamic> walletResponse = {};
      try {
        walletResponse = await ApiService.getAdminWallets(token, limit: 1000);
      } catch (e) {
        _logger.w('Wallet lookup blocked: $e');
      }

      final storeWalletBalances = <int, double>{};
      for (final w in (walletResponse['wallets'] as List? ?? [])) {
        final sidRaw = w['store_id'];
        if (sidRaw == null) continue;
        final sid = int.tryParse(sidRaw.toString());
        if (sid == null) continue;
        final bal = double.tryParse(w['balance']?.toString() ?? '0') ?? 0;
        storeWalletBalances[sid] = bal;
      }

      final storeNameLookup = <int, String>{};
      final storeSummaryMap = <int, Map<String, dynamic>>{};
      for (final s in stores) {
        final sid = int.tryParse(s['id']?.toString() ?? '');
        if (sid == null) continue;
        final name = (s['name'] ?? 'Store #$sid').toString();
        storeNameLookup[sid] = name;
        storeSummaryMap[sid] = {
          'store_id': sid,
          'store_name': name,
          'total_orders': 0,
          'served_orders': 0,
          'pending_orders': 0,
          'cancelled_orders': 0,
          'gross_sales': 0.0,
          'net_sales': 0.0,
          'total_discount': 0.0,
          'total_cost': 0.0,
          'estimated_profit': 0.0,
          'served_sales': 0.0,
          'pending_sales': 0.0,
          'wallet_balance': storeWalletBalances[sid] ?? 0.0,
          'orders': <Map<String, dynamic>>[],
        };
      }

      for (final o in storeOrders) {
        final sid = int.tryParse(o['store_id']?.toString() ?? '');
        if (sid == null) continue;
        final summary = storeSummaryMap.putIfAbsent(sid, () {
          final name =
              storeNameLookup[sid] ?? (o['store_name'] ?? 'Store #$sid');
          return {
            'store_id': sid,
            'store_name': name.toString(),
            'total_orders': 0,
            'served_orders': 0,
            'pending_orders': 0,
            'cancelled_orders': 0,
            'gross_sales': 0.0,
            'net_sales': 0.0,
            'total_discount': 0.0,
            'total_cost': 0.0,
            'estimated_profit': 0.0,
            'served_sales': 0.0,
            'pending_sales': 0.0,
            'wallet_balance': storeWalletBalances[sid] ?? 0.0,
            'orders': <Map<String, dynamic>>[],
          };
        });

        final status = (o['status'] ?? '').toString().toLowerCase();
        final amount =
            double.tryParse(o['store_order_amount']?.toString() ?? '0') ?? 0;
        summary['total_orders'] = (summary['total_orders'] as int) + 1;
        summary['gross_sales'] = (summary['gross_sales'] as double) + amount;
        summary['net_sales'] = (summary['net_sales'] as double) + amount;

        if (status == 'delivered') {
          summary['served_orders'] = (summary['served_orders'] as int) + 1;
          summary['served_sales'] = (summary['served_sales'] as double) + amount;
        } else if (status == 'cancelled') {
          summary['cancelled_orders'] = (summary['cancelled_orders'] as int) + 1;
        } else {
          summary['pending_orders'] = (summary['pending_orders'] as int) + 1;
          summary['pending_sales'] = (summary['pending_sales'] as double) + amount;
        }

        final parsedDate =
            DateTime.tryParse(o['created_at']?.toString() ?? '') ?? DateTime(1970);
        (summary['orders'] as List<Map<String, dynamic>>).add({
          'id': o['order_id'],
          'order_number': o['order_number'],
          'status': status,
          'amount': amount,
          'created_at': parsedDate,
        });
      }

      for (final ss in storeSales) {
        final sid = int.tryParse(ss['store_id']?.toString() ?? '');
        if (sid == null || !storeSummaryMap.containsKey(sid)) continue;
        final summary = storeSummaryMap[sid]!;
        final totalGrossSales =
            double.tryParse(ss['total_sales_gross']?.toString() ?? '0') ?? 0;
        final totalNetSales =
            double.tryParse(ss['total_sales_net']?.toString() ?? '0') ?? 0;
        final totalDiscount =
            double.tryParse(ss['total_discount']?.toString() ?? '0') ?? 0;
        final totalCost =
            double.tryParse(ss['total_cost']?.toString() ?? '0') ?? 0;
        final estimatedProfit =
            double.tryParse(ss['estimated_profit']?.toString() ?? '0') ?? 0;
        final avgOrder =
            double.tryParse(ss['average_order_value']?.toString() ?? '0') ?? 0;
        summary['gross_sales'] = totalGrossSales;
        summary['net_sales'] = totalNetSales;
        summary['total_discount'] = totalDiscount;
        summary['total_cost'] = totalCost;
        summary['estimated_profit'] = estimatedProfit;
        summary['average_order_value'] = avgOrder;
        summary['unique_customers'] =
            int.tryParse(ss['unique_customers']?.toString() ?? '0') ?? 0;
      }

      final rows = storeSummaryMap.values.toList();
      rows.sort((a, b) {
        final ba = (a['wallet_balance'] as double?) ?? 0.0;
        final bb = (b['wallet_balance'] as double?) ?? 0.0;
        return bb.compareTo(ba);
      });
      for (final row in rows) {
        final list = row['orders'] as List<Map<String, dynamic>>;
        list.sort((a, b) {
          final da = a['created_at'] as DateTime;
          final db = b['created_at'] as DateTime;
          return db.compareTo(da);
        });
      }

      final filters = storeNameLookup.entries
          .map((e) => {
                'store_id': e.key,
                'store_name': e.value,
              })
          .toList()
        ..sort((a, b) =>
            a['store_name'].toString().compareTo(b['store_name'].toString()));

      setState(() {
        _storeBalanceRows = rows;
        _storeFilterOptions = filters;
        if (!_storeFilterOptions
            .any((o) => o['store_id'] == _selectedStoreFilterId)) {
          _selectedStoreFilterId = null;
        }
        _isLoading = false;
      });
    } catch (e, stack) {
      _logger.e(
        'Failed loading store balances',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        setState(() {
          _error = 'Could not load store balances';
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _filteredStoreRows() {
    final baseRows = _storeBalanceRows.where((r) {
      if (_selectedStoreFilterId == null) return true;
      return r['store_id'] == _selectedStoreFilterId;
    }).toList();

    final query = _storeSearchQuery.trim().toLowerCase();
    final searchFilteredRows = baseRows.where((r) {
      if (query.isEmpty) return true;
      final name = (r['store_name'] ?? '').toString().toLowerCase();
      final id = (r['store_id'] ?? '').toString();
      return name.contains(query) || id.contains(query);
    }).toList();

    final balanceFilteredRows = searchFilteredRows.where((r) {
      final wallet = r['wallet_balance'] as double? ?? 0;
      switch (_selectedBalanceFilter) {
        case 'positive':
          return wallet > 0;
        case 'negative':
          return wallet < 0;
        case 'zero':
          return wallet == 0;
        case 'all':
        default:
          return true;
      }
    }).toList();

    switch (_selectedStoreTab) {
      case 'delivered':
        return balanceFilteredRows
            .where((r) => (r['served_orders'] as int? ?? 0) > 0)
            .toList();
      case 'pending':
        return balanceFilteredRows
            .where((r) => (r['pending_orders'] as int? ?? 0) > 0)
            .toList();
      case 'cancelled':
        return balanceFilteredRows
            .where((r) => (r['cancelled_orders'] as int? ?? 0) > 0)
            .toList();
      case 'all':
      default:
        return balanceFilteredRows;
    }
  }

  Widget _buildStoreSearchField() {
    return TextField(
      controller: _storeSearchController,
      onChanged: (value) => setState(() => _storeSearchQuery = value),
      decoration: InputDecoration(
        hintText: 'Search specific store (name or ID)',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _storeSearchQuery.trim().isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _storeSearchController.clear();
                  setState(() => _storeSearchQuery = '');
                },
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Map<String, dynamic> _summaryTotals(List<Map<String, dynamic>> rows) {
    int orders = 0;
    double netSales = 0;
    for (final r in rows) {
      orders += r['total_orders'] as int? ?? 0;
      netSales += r['net_sales'] as double? ?? 0;
    }
    return {'orders': orders, 'net_sales': netSales};
  }

  Widget _buildFilterDropdown() {
    return DropdownButton<int?>(
      value: _selectedStoreFilterId,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down),
      underline: Container(height: 1, color: Colors.grey.shade300),
      items: [
        const DropdownMenuItem(value: null, child: Text('All stores')),
        ..._storeFilterOptions.map(
          (opt) => DropdownMenuItem(
            value: opt['store_id'] as int?,
            child: Text(opt['store_name']?.toString() ?? 'Store'),
          ),
        ),
      ],
      onChanged: (value) {
        setState(() => _selectedStoreFilterId = value);
      },
    );
  }

  Widget _buildBalanceFilterDropdown() {
    return DropdownButton<String>(
      value: _selectedBalanceFilter,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down),
      underline: Container(height: 1, color: Colors.grey.shade300),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('All balances')),
        DropdownMenuItem(value: 'positive', child: Text('Positive balances')),
        DropdownMenuItem(value: 'negative', child: Text('Negative balances')),
        DropdownMenuItem(value: 'zero', child: Text('Zero balances')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selectedBalanceFilter = value);
      },
    );
  }

  Widget _buildTabChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildTabChip('All', 'all'),
          const SizedBox(width: 8),
          _buildTabChip('Delivered', 'delivered'),
          const SizedBox(width: 8),
          _buildTabChip('Pending', 'pending'),
          const SizedBox(width: 8),
          _buildTabChip('Cancelled', 'cancelled'),
        ],
      ),
    );
  }

  Widget _buildTabChip(String label, String value) {
    final selected = _selectedStoreTab == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) {
        if (!v) return;
        setState(() => _selectedStoreTab = value);
      },
      selectedColor: Colors.indigo.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? Colors.indigo : Colors.grey[700],
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? Colors.indigo : Colors.grey[300]!),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> row) {
    final storeName = (row['store_name'] ?? 'Store').toString();
    final totalOrders = row['total_orders'] as int? ?? 0;
    final delivered = row['served_orders'] as int? ?? 0;
    final pending = row['pending_orders'] as int? ?? 0;
    final cancelled = row['cancelled_orders'] as int? ?? 0;
    final wallet = row['wallet_balance'] as double? ?? 0;
    final gross = row['gross_sales'] as double? ?? 0;
    final net = row['net_sales'] as double? ?? 0;
    final discount = row['total_discount'] as double? ?? 0;
    final cost = row['total_cost'] as double? ?? 0;
    final profit = row['estimated_profit'] as double? ?? 0;
    final deliveredSales = row['served_sales'] as double? ?? 0;
    final pendingSales = row['pending_sales'] as double? ?? 0;
    final orders = (row['orders'] as List<Map<String, dynamic>>?) ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: Text(
          storeName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(
          'Balance: PKR ${wallet.toStringAsFixed(2)} • Orders: $totalOrders',
          style: TextStyle(
            color: wallet < 0 ? Colors.red : Colors.green[700],
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metricChip('Delivered', '$delivered', Colors.green),
              _metricChip('Pending', '$pending', Colors.orange),
              _metricChip('Cancelled', '$cancelled', Colors.red),
              _metricChip('Gross', 'PKR ${gross.toStringAsFixed(0)}', Colors.blue),
              _metricChip('Net', 'PKR ${net.toStringAsFixed(0)}', Colors.indigo),
              _metricChip(
                'Discount',
                'PKR ${discount.toStringAsFixed(0)}',
                Colors.purple,
              ),
              _metricChip('Cost', 'PKR ${cost.toStringAsFixed(0)}', Colors.brown),
              _metricChip(
                'Profit',
                'PKR ${profit.toStringAsFixed(0)}',
                profit >= 0 ? Colors.teal : Colors.red,
              ),
              _metricChip(
                'Delivered Sales',
                'PKR ${deliveredSales.toStringAsFixed(0)}',
                Colors.teal,
              ),
              _metricChip(
                'Pending Sales',
                'PKR ${pendingSales.toStringAsFixed(0)}',
                Colors.deepOrange,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (orders.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No orders found', style: TextStyle(color: Colors.black54)),
            )
          else ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent Orders',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 4),
            ...orders.take(5).map((o) {
              final number = (o['order_number'] ?? '').toString();
              final status = (o['status'] ?? '').toString();
              final amount = o['amount'] as double? ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '#$number',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: _statusColor(status),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PKR ${amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 11),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s == 'delivered') return Colors.green;
    if (s == 'cancelled') return Colors.red;
    if (['pending', 'confirmed', 'preparing', 'ready'].contains(s)) {
      return Colors.orange;
    }
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStoreRows();
    final totals = _summaryTotals(filtered);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Balances'),
        actions: const [NotificationBellWidget()],
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadStoreBalances,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Store Balances',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Review wallet balances, sales, and order counts per store.',
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        _buildStoreSearchField(),
                        const SizedBox(height: 8),
                        if (_storeFilterOptions.isNotEmpty) _buildFilterDropdown(),
                        const SizedBox(height: 8),
                        _buildBalanceFilterDropdown(),
                        const SizedBox(height: 8),
                        _buildTabChips(),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _infoBadge(
                                label: 'Stores',
                                value: '${filtered.length}',
                                color: Colors.indigo,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _infoBadge(
                                label: 'Orders',
                                value: '${totals['orders']}',
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _infoBadge(
                                label: 'Net Sales',
                                value:
                                    'PKR ${(totals['net_sales'] as double).toStringAsFixed(0)}',
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (filtered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text('No data for the selected filters.'),
                          )
                        else
                          ...filtered.map(_buildCard),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _infoBadge({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
