import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class OfferCampaignsScreen extends StatefulWidget {
  final bool isAdmin;
  final int? initialStoreId;

  const OfferCampaignsScreen({
    super.key,
    required this.isAdmin,
    this.initialStoreId,
  });

  @override
  State<OfferCampaignsScreen> createState() => _OfferCampaignsScreenState();
}

class _OfferCampaignsScreenState extends State<OfferCampaignsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _discountValueCtrl = TextEditingController();
  final _buyQtyCtrl = TextEditingController(text: '1');
  final _getQtyCtrl = TextEditingController(text: '1');

  bool _loading = false;
  bool _saving = false;
  bool _enabled = true;
  String _campaignType = 'discount';
  String _discountType = 'percent';
  String _scope = 'all_products';
  DateTime _startAt = DateTime.now();
  DateTime _endAt = DateTime.now().add(const Duration(hours: 1));
  int? _selectedStoreId;
  int? _editingCampaignId;

  List<dynamic> _stores = [];
  List<dynamic> _products = [];
  List<dynamic> _campaigns = [];
  final Set<int> _selectedProductIds = <int>{};

  @override
  void initState() {
    super.initState();
    _selectedStoreId = widget.initialStoreId;
    _loadInitial();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _discountValueCtrl.dispose();
    _buyQtyCtrl.dispose();
    _getQtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) return;
    setState(() => _loading = true);
    try {
      if (widget.isAdmin) {
        _stores = await ApiService.getStoresForAdmin(
          token,
          includeInactive: true,
          lite: true,
        );
        if (_selectedStoreId == null && _stores.isNotEmpty) {
          _selectedStoreId = int.tryParse('${_stores.first['id']}');
        }
      } else if (_selectedStoreId == null) {
        final storeData = await ApiService.getStoreOrders(token);
        _selectedStoreId = int.tryParse('${storeData['stats']?['store_id']}');
      }
      if (_selectedStoreId != null && _selectedStoreId! > 0) {
        await _loadProductsAndCampaigns(token, _selectedStoreId!);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load campaigns: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProductsAndCampaigns(String token, int storeId) async {
    final products = await ApiService.getProductsForAdmin(token);
    _products = products
        .where((p) => int.tryParse('${p['store_id']}') == storeId)
        .toList();
    final data = await ApiService.getStoreOfferCampaigns(token, storeId: storeId);
    _campaigns = (data['campaigns'] as List<dynamic>? ?? []);
    if (mounted) setState(() {});
  }

  Future<void> _onStoreChanged(int storeId) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;
    setState(() {
      _selectedStoreId = storeId;
      _loading = true;
    });
    try {
      await _loadProductsAndCampaigns(token, storeId);
      _resetForm();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDateTime(bool isStart) async {
    final base = isStart ? _startAt : _endAt;
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      initialDate: base,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startAt = dt;
      } else {
        _endAt = dt;
      }
    });
  }

  Map<String, dynamic> _buildPayload() {
    return {
      'store_id': _selectedStoreId,
      'name': _nameCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'campaign_type': _campaignType,
      'apply_scope': _scope,
      'is_enabled': _enabled,
      'start_at': _startAt.toIso8601String(),
      'end_at': _endAt.toIso8601String(),
      'discount_type': _campaignType == 'discount' ? _discountType : null,
      'discount_value': _campaignType == 'discount'
          ? double.tryParse(_discountValueCtrl.text.trim())
          : null,
      'buy_qty': _campaignType == 'bxgy'
          ? int.tryParse(_buyQtyCtrl.text.trim())
          : null,
      'get_qty': _campaignType == 'bxgy'
          ? int.tryParse(_getQtyCtrl.text.trim())
          : null,
      'product_ids': _scope == 'selected_products'
          ? _selectedProductIds.toList()
          : <int>[],
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStoreId == null || _selectedStoreId! <= 0) return;
    if (_endAt.isBefore(_startAt) || _endAt.isAtSameMomentAs(_startAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }
    if (_scope == 'selected_products' && _selectedProductIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one product')),
      );
      return;
    }
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;
    setState(() => _saving = true);
    try {
      final payload = _buildPayload();
      if (_editingCampaignId != null && _editingCampaignId! > 0) {
        await ApiService.updateStoreOfferCampaign(
          token,
          campaignId: _editingCampaignId!,
          payload: payload,
        );
      } else {
        await ApiService.createStoreOfferCampaign(token, payload: payload);
      }
      await _loadProductsAndCampaigns(token, _selectedStoreId!);
      _resetForm();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campaign saved successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCampaign(int campaignId) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null || _selectedStoreId == null) return;
    setState(() => _saving = true);
    try {
      await ApiService.deleteStoreOfferCampaign(token, campaignId: campaignId);
      await _loadProductsAndCampaigns(token, _selectedStoreId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campaign deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _editCampaign(Map<String, dynamic> c) {
    setState(() {
      _editingCampaignId = int.tryParse('${c['id']}');
      _nameCtrl.text = (c['name'] ?? '').toString();
      _descCtrl.text = (c['description'] ?? '').toString();
      _campaignType = (c['campaign_type'] ?? 'discount').toString();
      _scope = (c['apply_scope'] ?? 'all_products').toString();
      _enabled = c['is_enabled'] == true || c['is_enabled'] == 1;
      _discountType = (c['discount_type'] ?? 'percent').toString();
      _discountValueCtrl.text = (c['discount_value'] ?? '').toString();
      _buyQtyCtrl.text = (c['buy_qty'] ?? 1).toString();
      _getQtyCtrl.text = (c['get_qty'] ?? 1).toString();
      _startAt = DateTime.tryParse('${c['start_at']}')?.toLocal() ?? DateTime.now();
      _endAt = DateTime.tryParse('${c['end_at']}')?.toLocal() ??
          DateTime.now().add(const Duration(hours: 1));
      _selectedProductIds
        ..clear()
        ..addAll((c['product_ids'] as List<dynamic>? ?? [])
            .map((e) => int.tryParse('$e'))
            .whereType<int>());
    });
  }

  void _resetForm() {
    setState(() {
      _editingCampaignId = null;
      _nameCtrl.clear();
      _descCtrl.clear();
      _campaignType = 'discount';
      _discountType = 'percent';
      _discountValueCtrl.clear();
      _buyQtyCtrl.text = '1';
      _getQtyCtrl.text = '1';
      _scope = 'all_products';
      _enabled = true;
      _startAt = DateTime.now();
      _endAt = DateTime.now().add(const Duration(hours: 1));
      _selectedProductIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offer Campaigns'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading
                ? null
                : () {
                    if (_selectedStoreId != null) {
                      _onStoreChanged(_selectedStoreId!);
                    }
                  },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.isAdmin)
                              DropdownButtonFormField<int>(
                                initialValue: _selectedStoreId,
                                decoration: const InputDecoration(
                                  labelText: 'Store',
                                ),
                                items: _stores
                                    .map(
                                      (s) => DropdownMenuItem<int>(
                                        value: int.tryParse('${s['id']}'),
                                        child: Text(
                                          '${s['name']} (#${s['id']})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) _onStoreChanged(v);
                                },
                              ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Campaign Name',
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _descCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Description',
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _campaignType,
                                    decoration: const InputDecoration(
                                      labelText: 'Type',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'discount',
                                        child: Text('Discount'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'bxgy',
                                        child: Text('Buy X Get Y'),
                                      ),
                                    ],
                                    onChanged: (v) {
                                      setState(
                                        () => _campaignType = v ?? 'discount',
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _scope,
                                    decoration: const InputDecoration(
                                      labelText: 'Scope',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'all_products',
                                        child: Text('All Products'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'selected_products',
                                        child: Text('Selected Products'),
                                      ),
                                    ],
                                    onChanged: (v) {
                                      setState(
                                        () => _scope = v ?? 'all_products',
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _enabled,
                              title: const Text('Enable Campaign'),
                              onChanged: (v) => setState(() => _enabled = v),
                            ),
                            if (_campaignType == 'discount') ...[
                              DropdownButtonFormField<String>(
                                initialValue: _discountType,
                                decoration: const InputDecoration(
                                  labelText: 'Discount Type',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'percent',
                                    child: Text('Percentage'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'amount',
                                    child: Text('Fixed Amount'),
                                  ),
                                ],
                                onChanged: (v) {
                                  setState(() => _discountType = v ?? 'percent');
                                },
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _discountValueCtrl,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Discount Value',
                                ),
                                validator: (v) {
                                  if (_campaignType != 'discount') return null;
                                  final n = double.tryParse((v ?? '').trim());
                                  if (n == null || n <= 0) return 'Must be > 0';
                                  return null;
                                },
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _buyQtyCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Buy Qty',
                                      ),
                                      validator: (v) {
                                        if (_campaignType != 'bxgy') return null;
                                        final n = int.tryParse((v ?? '').trim());
                                        if (n == null || n <= 0) {
                                          return 'Must be > 0';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _getQtyCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Get Qty',
                                      ),
                                      validator: (v) {
                                        if (_campaignType != 'bxgy') return null;
                                        final n = int.tryParse((v ?? '').trim());
                                        if (n == null || n <= 0) {
                                          return 'Must be > 0';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _pickDateTime(true),
                                    icon: const Icon(Icons.schedule),
                                    label: Text(
                                      'From: ${_startAt.toString().substring(0, 16)}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _pickDateTime(false),
                                    icon: const Icon(Icons.schedule),
                                    label: Text(
                                      'To: ${_endAt.toString().substring(0, 16)}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_scope == 'selected_products') ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Select Products',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                height: 180,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ListView.builder(
                                  itemCount: _products.length,
                                  itemBuilder: (context, index) {
                                    final p = _products[index];
                                    final pid = int.tryParse('${p['id']}');
                                    if (pid == null) return const SizedBox.shrink();
                                    final selected =
                                        _selectedProductIds.contains(pid);
                                    return CheckboxListTile(
                                      dense: true,
                                      value: selected,
                                      title: Text(
                                        '${p['name']} (#$pid)',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selectedProductIds.add(pid);
                                          } else {
                                            _selectedProductIds.remove(pid);
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _saving ? null : _save,
                                    icon: const Icon(Icons.save),
                                    label: Text(
                                      _editingCampaignId == null
                                          ? 'Create Campaign'
                                          : 'Update Campaign',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: _saving ? null : _resetForm,
                                  child: const Text('Reset'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Existing Campaigns',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  if (_campaigns.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No campaigns found for selected store'),
                      ),
                    )
                  else
                    ..._campaigns.map((c) {
                      final cid = int.tryParse('${c['id']}') ?? 0;
                      return Card(
                        child: ListTile(
                          title: Text('${c['name']} (${c['offer_badge'] ?? c['campaign_type']})'),
                          subtitle: Text(
                            '${c['start_at']} -> ${c['end_at']}\n${c['apply_scope']}',
                          ),
                          isThreeLine: true,
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editCampaign(c),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _saving
                                    ? null
                                    : () => _deleteCampaign(cid),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

