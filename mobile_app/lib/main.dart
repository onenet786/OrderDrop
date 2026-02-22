import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/notification_provider.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/rider_dashboard_screen.dart';
import 'screens/store_owner_dashboard_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/inventory_report_screen.dart';
import 'screens/manage_stores_screen.dart';
import 'screens/manage_products_screen.dart';
import 'screens/manage_users_screen.dart';
import 'screens/manage_riders_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/store_balances_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/ui_test_home_screen.dart';
import 'screens/customer_dashboard_test_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProxyProvider<AuthProvider, NotificationProvider>(
          create: (_) => NotificationProvider(navigatorKey),
          update: (_, auth, previous) =>
              (previous ?? NotificationProvider(navigatorKey))..update(auth),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'ServeNow',
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          return SafeArea(
            top: false,
            left: false,
            right: false,
            bottom: true,
            child: Stack(
              children: [
                if (child != null) child,
                const Positioned(
                  right: 6,
                  bottom: 4,
                  child: _VersionBadge(),
                ),
              ],
            ),
          );
        },
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          fontFamily: 'Roboto',
          scaffoldBackgroundColor: Colors.grey[50],
          useMaterial3: true,
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            elevation: 2,
            showCloseIcon: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            contentTextStyle: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        home: const AuthWrapper(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const CustomerDashboardTestScreen(),
          '/admin': (context) => const AdminDashboardScreen(),
          '/store-balances': (context) => const StoreBalancesScreen(),
          '/rider': (context) => const RiderDashboardScreen(),
          '/store_owner': (context) => const StoreOwnerDashboardScreen(),
          '/orders': (context) => const OrdersScreen(),
          '/cart': (context) => const CartScreen(),
          '/checkout': (context) => const CheckoutScreen(),
          '/wallet': (context) => const HomeScreen(), // Redirect to home
          '/inventory-report': (context) => const InventoryReportScreen(),
          '/manage-stores': (context) => const ManageStoresScreen(),
          '/manage-products': (context) => const ManageProductsScreen(),
          '/manage-users': (context) => const ManageUsersScreen(),
          '/manage-riders': (context) => const ManageRidersScreen(),
          '/change-password': (context) => const ChangePasswordScreen(),
          '/forgot-password': (context) => const ForgotPasswordScreen(),
          '/ui-test-home': (context) => const UiTestHomeScreen(),
          '/customer-test-dashboard': (context) =>
              const CustomerDashboardTestScreen(),
        },
      ),
    );
  }
}

class _VersionBadge extends StatefulWidget {
  const _VersionBadge();

  @override
  State<_VersionBadge> createState() => _VersionBadgeState();
}

class _VersionBadgeState extends State<_VersionBadge> {
  static const String _envTag =
      String.fromEnvironment('APP_VERSION_TAG', defaultValue: '');
  String _tag = _envTag;

  @override
  void initState() {
    super.initState();
    _loadVersionTag();
  }

  Future<void> _loadVersionTag() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (!mounted) return;
      if (version.isNotEmpty) {
        setState(() {
          _tag = build.isNotEmpty ? 'v$version+$build' : 'v$version';
        });
      }
    } catch (_) {
      // Keep environment tag fallback if package info is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tag.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _tag,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.black54,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final startTime = DateTime.now();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.tryAutoLogin();

    final endTime = DateTime.now();
    final elapsed = endTime.difference(startTime).inMilliseconds;
    if (elapsed < 2000) {
      await Future.delayed(Duration(milliseconds: 2000 - elapsed));
    }

    if (!mounted) return;

    if (auth.isAuthenticated) {
      if (auth.isAdmin) {
        Navigator.of(context).pushReplacementNamed('/admin');
      } else if (auth.isRider) {
        Navigator.of(context).pushReplacementNamed('/rider');
      } else if (auth.isStoreOwner) {
        Navigator.of(context).pushReplacementNamed('/store_owner');
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
