import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class ManageStoresScreen extends StatefulWidget {
  const ManageStoresScreen({super.key});

  @override
  State<ManageStoresScreen> createState() => _ManageStoresScreenState();
}

class _ManageStoresScreenState extends State<ManageStoresScreen> {
  final Logger _logger = Logger();
  bool _isLoading = true;
  List<dynamic> _stores = [];
  List<dynamic> _filteredStores = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStores();
    _searchController.addListener(_applySearch);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applySearch);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStores() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      final stores = await ApiService.getStoresForAdmin(
        token,
        includeInactive: true,
      );

      setState(() {
        _stores = stores;
        _filteredStores = stores;
        _isLoading = false;
      });
    } catch (e) {
      _logger.e('Error loading stores: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading stores: $e')));
      }
    }
  }

  void _applySearch() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filteredStores = _stores);
      return;
    }
    setState(() {
      _filteredStores = _stores.where((s) {
        final name = (s['name'] ?? s['store_name'] ?? '').toString().toLowerCase();
        final id = (s['id'] ?? '').toString();
        final location = (s['location'] ?? '').toString().toLowerCase();
        return name.contains(q) || id.contains(q) || location.contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Manage Stores',
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
              onRefresh: _loadStores,
              child: _filteredStores.isEmpty && _searchController.text.isNotEmpty
                  ? Center(
                      child: Text(
                        'No matching store found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : _stores.isEmpty
                  ? Center(
                      child: Text(
                        'No stores found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search store by name, id, location...',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredStores.length,
                            itemBuilder: (context, index) {
                              final store = _filteredStores[index];
                              return _buildStoreCard(store);
                            },
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }

  Widget _buildStoreCard(dynamic store) {
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              store['name'] ?? store['store_name'] ?? 'Unknown',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(store),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 14, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime(store['opening_time']),
                            style: TextStyle(fontSize: 14, color: Colors.blue[600], fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.timer_off, size: 14, color: Colors.red),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime(store['closing_time']),
                            style: TextStyle(fontSize: 14, color: Colors.blue[600], fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        store['email'] ?? 'No email',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (store['status'] ?? 'inactive')
                                .toString()
                                .toLowerCase() ==
                            'active'
                        ? Colors.green.withAlpha((0.2 * 255).round())
                        : Colors.orange.withAlpha((0.2 * 255).round()),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    store['status'] ?? 'inactive',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color:
                          (store['status'] ?? 'inactive')
                                  .toString()
                                  .toLowerCase() ==
                              'active'
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _buildInfoColumn('Phone', store['phone'] ?? '-')),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoColumn('Address', store['address'] ?? '-'),
                ),
              ],
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

  Widget _buildStatusBadge(dynamic store) {
    final manuallyClosed = store['is_closed'] == true || store['is_closed'] == 1;
    final bool isOpen =
        !manuallyClosed && _checkIsOpen(store['opening_time'], store['closing_time']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOpen ? Colors.green : Colors.red,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isOpen ? 'OPEN' : 'CLOSED',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  String _formatTime(dynamic time) {
    if (time == null) return '--:--';
    final parts = time.toString().split(':');
    if (parts.length >= 2) {
      return '${parts[0]}:${parts[1]}';
    }
    return time.toString();
  }

  Widget _buildInfoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
