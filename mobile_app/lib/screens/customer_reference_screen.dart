import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:orderdrop/screens/store_screen.dart';

import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../services/api_service.dart';

class CustomerReferenceScreen extends StatefulWidget {
  const CustomerReferenceScreen({super.key});

  @override
  State<CustomerReferenceScreen> createState() => _CustomerReferenceScreenState();
}

class _CustomerReferenceScreenState extends State<CustomerReferenceScreen> {
  static const tabs = ['All Stores', 'Open Now', 'Nearby', 'Popular'];
  final _searchController = TextEditingController();
  List<dynamic> _allStores = [];
  List<dynamic> _filteredStores = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedTab = tabs.first;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilters);
    _fetchData();
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilters);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final resp = await ApiService.getStores();
      _allStores = (resp['stores'] as List<dynamic>? ?? []);
      if (!mounted) return;
      setState(() {
        _filteredStores = _allStores;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    final q = _searchController.text.trim().toLowerCase();
    final filtered = _allStores.where((store) {
      final name = (store['name'] ?? '').toString().toLowerCase();
      final location = (store['location'] ?? '').toString().toLowerCase();
      final matchesQuery = q.isEmpty || name.contains(q) || location.contains(q);
      if (!matchesQuery) return false;
      if (_selectedTab == 'Open Now') {
        return store['is_open'] == true || store['is_open'] == 1;
      }
      return true;
    }).toList();
    if (!mounted) return;
    setState(() => _filteredStores = filtered);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final columns = width >= 980 ? 3 : 2;
    final isGuest = context.watch<AuthProvider>().isGuest;

    return Scaffold(
      backgroundColor: const Color(0xFFE5F4EA),
      body: Stack(
        children: [
          const _Backdrop(),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _fetchData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(14),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width >= 760 ? 680 : width - 28),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.34),
                            const Color(0xFFE3F5EB).withValues(alpha: 0.54),
                            const Color(0xFFD2EEF5).withValues(alpha: 0.42),
                          ],
                        ),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6BA79F).withValues(alpha: 0.18),
                            blurRadius: 30,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Header(isGuest: isGuest),
                          const SizedBox(height: 18),
                          _SearchBar(controller: _searchController),
                          const SizedBox(height: 16),
                          const Text('Stores', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF14221C))),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: tabs.map((tab) {
                              final selected = tab == _selectedTab;
                              return GestureDetector(
                                onTap: () {
                                  setState(() => _selectedTab = tab);
                                  _applyFilters();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected ? const Color(0xFF8CD23D) : Colors.white.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(tab, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : const Color(0xFF34443A))),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),
                          if (_isLoading)
                            const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator()))
                          else if (_errorMessage != null)
                            _EmptyState(message: 'Error: $_errorMessage')
                          else if (_filteredStores.isEmpty)
                            const _EmptyState(message: 'No stores found')
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                childAspectRatio: width >= 980 ? 0.82 : 0.73,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                              ),
                              itemCount: _filteredStores.length,
                              itemBuilder: (context, index) => _StoreCard(store: _filteredStores[index]),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isGuest});
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Image.asset('assets/icon/logo_w.png', height: 58, fit: BoxFit.contain)),
        Consumer<CartProvider>(
          builder: (context, cart, _) => _RoundIcon(
            icon: Icons.shopping_cart_checkout_rounded,
            badge: cart.itemCount > 0 ? '${cart.itemCount}' : null,
            onTap: () => Navigator.of(context).pushNamed('/cart'),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'orders' && isGuest) {
              Navigator.of(context).pushNamed('/register');
              return;
            }
            if (value == 'orders') Navigator.of(context).pushNamed('/orders');
            if (value == 'register') Navigator.of(context).pushNamed('/register');
            if (value == 'password') Navigator.of(context).pushNamed('/change-password');
            if (value == 'logout') {
              context.read<AuthProvider>().logout();
              Navigator.of(context).pushReplacementNamed('/login');
            }
          },
          itemBuilder: (context) => [
            if (isGuest) const PopupMenuItem(value: 'register', child: Text('Register')),
            const PopupMenuItem(value: 'orders', child: Text('My Orders')),
            if (!isGuest) const PopupMenuItem(value: 'password', child: Text('Change Password')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'logout', child: Text('Logout')),
          ],
          child: const _RoundIcon(icon: Icons.person),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Search stores...',
          prefixIcon: const Icon(Icons.search, color: Color(0xFF909A93)),
          suffixIcon: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFEFF6EF), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.shopping_cart_rounded, size: 20, color: Color(0xFF98A29A)),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.transparent,
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store});
  final dynamic store;

  @override
  Widget build(BuildContext context) {
    final isOpen = store['is_open'] == true || store['is_open'] == 1;
    final title = (store['name'] ?? 'Store').toString();
    final subtitle = (store['location'] ?? '').toString();
    final imageUrl = ApiService.getImageUrl(store['image_url']);

    void openStore() {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoreScreen(storeId: store['id'])));
    }

    return GestureDetector(
      onTap: openStore,
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: const Color(0xFF538B80).withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 10))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE7F5EF), Color(0xFFD3EEF2)]))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                      child: Image.network(imageUrl, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.storefront_rounded, size: 44, color: Color(0xFF95AFA6))),
                    ),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: isOpen ? const Color(0xFF8CD23D) : const Color(0xFFE56E6E)),
                        alignment: Alignment.center,
                        child: Text(isOpen ? 'OPEN' : 'CLOSE', textAlign: TextAlign.center, style: const TextStyle(fontSize: 8, height: 1.05, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF21342C))),
                  const SizedBox(height: 4),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF8C9892), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: openStore,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(color: Color(0xFF8CD23D), shape: BoxShape.circle),
                        child: const Icon(Icons.add, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(22)),
      child: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF4A5D54))),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFD7F0C0), Color(0xFFCCEADF), Color(0xFFADD7F6)]))),
        Positioned(left: -60, top: 80, child: _Orb(size: 240, color: const Color(0xFFBDE06A).withValues(alpha: 0.22))),
        Positioned(right: -40, top: 140, child: _Orb(size: 190, color: const Color(0xFF83C7F8).withValues(alpha: 0.22))),
        Positioned(right: -70, bottom: 120, child: _Orb(size: 250, color: const Color(0xFF85C7FF).withValues(alpha: 0.22))),
        Positioned(left: -20, bottom: 60, child: _Orb(size: 180, color: const Color(0xFFEBD36B).withValues(alpha: 0.18))),
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, this.badge, this.onTap});
  final IconData icon;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: Icon(icon, size: 20, color: const Color(0xFF182720))),
          if (badge != null)
            Positioned(
              right: -1,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: const BoxDecoration(color: Color(0xFF8CD23D), shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(badge!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(999), child: child);
  }
}

