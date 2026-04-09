import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:orderdrop/screens/store_screen.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/notification_provider.dart' as app_notif;
import '../services/api_service.dart';
import '../theme/customer_palette.dart';
import '../utils/customer_language.dart';
import '../widgets/notification_bell_widget.dart';

class CustomerDashboardTestScreen extends StatefulWidget {
  const CustomerDashboardTestScreen({super.key});

  @override
  State<CustomerDashboardTestScreen> createState() =>
      _CustomerDashboardTestScreenState();
}

class _CustomerDashboardTestScreenState extends State<CustomerDashboardTestScreen> {
  List<dynamic> _allStores = [];
  List<dynamic> _filteredStores = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _serviceLimitedMessage;
  Map<String, dynamic>? _globalStatus;
  Map<String, dynamic>? _livePromotions;
  Map<String, dynamic>? _customerFlashMessage;
  Map<String, dynamic>? _supportContact;
  Map<String, dynamic>? _appUpdateStatus;
  final TextEditingController _searchController = TextEditingController();
  double? _userLat;
  double? _userLng;
  String? _userCity;
  final PageController _bannerController = PageController();
  int _activeBanner = 0;
  Timer? _bannerTimer;
  Timer? _globalStatusRefreshTimer;
  Timer? _livePromotionsRefreshTimer;
  Timer? _globalStatusPollTimer;
  int _bottomIndex = 0;
  bool _launchFlashShown = false;
  String? _launchFlashSignature;
  bool _isUrdu = false;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _fetchData();
    _globalStatusPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshGlobalStatusOnly();
    });
    _searchController.addListener(_onSearchChanged);
    _startBannerAutoScroll();
  }

  Future<void> _loadLanguagePreference() async {
    final isUrdu = await CustomerLanguage.loadIsUrdu();
    if (!mounted) return;
    setState(() {
      _isUrdu = isUrdu;
    });
  }

  Future<void> _setLanguage(bool isUrdu) async {
    await CustomerLanguage.saveIsUrdu(isUrdu);
    if (!mounted) return;
    setState(() {
      _isUrdu = isUrdu;
    });
  }

  String _tr(String english) {
    const translations = <String, String>{
      'OrderDrop Support': 'آرڈر ڈراپ سپورٹ',
      'Contact Us': 'ہم سے رابطہ کریں',
      'Support contact is not configured yet.': 'ابھی سپورٹ رابطہ معلومات شامل نہیں کی گئی ہیں۔',
      'Choose how you want to contact us.': 'رابطے کا طریقہ منتخب کریں۔',
      'Email': 'ای میل',
      'Update Required': 'اپ ڈیٹ ضروری ہے',
      'Update Available': 'اپ ڈیٹ دستیاب ہے',
      'A new version of OrderDrop is available.': 'آرڈر ڈراپ کا نیا ورژن دستیاب ہے۔',
      'A newer version of OrderDrop is available.': 'آرڈر ڈراپ کا نیا ورژن دستیاب ہے۔',
      'Installed': 'انسٹال شدہ',
      'Latest': 'تازہ ترین',
      'Unknown': 'نامعلوم',
      'Update Now': 'ابھی اپ ڈیٹ کریں',
      'Hide': 'چھپائیں',
      'OrderDrop Flash Message': 'آرڈر ڈراپ اہم پیغام',
      'Check latest updates in OrderDrop.': 'آرڈر ڈراپ کی تازہ ترین معلومات دیکھیں۔',
      'Check latest promotions and events.': 'تازہ پروموشنز اور ایونٹس دیکھیں۔',
      'Flash Message': 'اہم پیغام',
      'OK': 'ٹھیک ہے',
      'Promotion window': 'پروموشن مدت',
      'My Cart': 'میری کارٹ',
      'Welcome': 'خوش آمدید',
      'Ref Area': 'حوالہ علاقہ',
      'OrderDrop Customer': 'آرڈر ڈراپ کسٹمر',
      'Live Promotions': 'لائیو پروموشنز',
      'Live: Promotions / Events': 'لائیو: پروموشنز / ایونٹس',
      'live widgets': 'لائیو ویجٹس',
      'Live Delivery Pause': 'لائیو ڈیلیوری بندش',
      'Delivery Update': 'ڈیلیوری اپ ڈیٹ',
      'Search store by name or area': 'دکان نام یا علاقے سے تلاش کریں',
      'No stores found in this category': 'اس زمرے میں کوئی دکان نہیں ملی۔',
      'Language': 'زبان',
      'Select Language': 'زبان منتخب کریں',
      'English': 'English',
      'Urdu': 'اردو',
      'Selected': 'منتخب',
      'You are not allowed to see Store when you are out of Delivery Area': 'ڈیلیوری ایریا سے باہر ہونے پر آپ دکانیں نہیں دیکھ سکتے۔',
    };
    if (_isUrdu && translations.containsKey(english)) {
      return translations[english]!;
    }
    return CustomerLanguage.tr(_isUrdu, english);
  }

  String _languageLabel() => _isUrdu ? 'اردو' : 'EN';

  Future<void> _showLanguageOptions() async {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr('Select Language'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language),
                  title: Text(_tr('English')),
                  trailing: !_isUrdu
                      ? Text(
                          _tr('Selected'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        )
                      : null,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _setLanguage(false);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.translate),
                  title: const Text('اردو'),
                  trailing: _isUrdu
                      ? Text(
                          _tr('Selected'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        )
                      : null,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _setLanguage(true);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _globalStatusRefreshTimer?.cancel();
    _livePromotionsRefreshTimer?.cancel();
    _globalStatusPollTimer?.cancel();
    _bannerController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _startBannerAutoScroll() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final count = _liveWidgetItems.length;
      if (count <= 1 || !_bannerController.hasClients) return;
      final next = (_activeBanner + 1) % count;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  List<Map<String, dynamic>> get _liveWidgetItems {
    final includePromotionCard = _showLivePromotionsCard();
    final includeStatusCard = _showGlobalStatusBanner();
    final storeSlots =
        (5 - (includePromotionCard ? 1 : 0) - (includeStatusCard ? 1 : 0))
            .clamp(0, 5);
    final stores = _allStores
        .where((s) => (s['image_url'] ?? '').toString().trim().isNotEmpty)
        .take(storeSlots)
        .toList();
    final items = <Map<String, dynamic>>[];
    if (includePromotionCard) {
      items.add({'type': 'promotion'});
    }
    if (includeStatusCard) {
      items.add({'type': 'status'});
    }
    for (final store in stores) {
      items.add({'type': 'store', 'data': store});
    }
    return items;
  }

  void _onSearchChanged() {
    _filterStores(_searchController.text);
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      await _resolveLocationContext();
      Map<String, dynamic>? globalStatus;
      if (token != null) {
        try {
          final global = await ApiService.getGlobalDeliveryStatus(token);
          globalStatus = (global['status'] is Map<String, dynamic>)
              ? (global['status'] as Map<String, dynamic>)
              : (global['global_status'] is Map<String, dynamic>)
                  ? (global['global_status'] as Map<String, dynamic>)
                  : global;
        } catch (_) {}
      }
      Map<String, dynamic>? livePromotions;
      try {
        final promotions = await ApiService.getLivePromotions(token);
        livePromotions = (promotions['live_promotions'] is Map<String, dynamic>)
            ? (promotions['live_promotions'] as Map<String, dynamic>)
            : promotions;
      } catch (_) {}
      Map<String, dynamic>? customerFlash;
      Map<String, dynamic>? supportContact;
      Map<String, dynamic>? appUpdateStatus;
      if (token != null) {
        try {
          customerFlash = await ApiService.getCustomerFlashMessage(token);
        } catch (_) {}
        try {
          supportContact = await ApiService.getCustomerSupportContact(token);
        } catch (_) {}
        try {
          appUpdateStatus = await _resolveAppUpdateStatus(token);
        } catch (_) {}
      }
      final storesResp = await ApiService.getStores(
        latitude: _userLat,
        longitude: _userLng,
        city: _userCity,
      );

      if (!mounted) return;
      final stores = (storesResp['stores'] as List<dynamic>? ?? []);
      final limited = storesResp['service_limited'] == true;
      final limitedMessage = (storesResp['service_message'] ?? '').toString().trim();
      setState(() {
        _allStores = stores;
        _filteredStores = stores;
        _globalStatus = globalStatus;
        _livePromotions = livePromotions;
        _customerFlashMessage = customerFlash;
        _supportContact = supportContact;
        _appUpdateStatus = appUpdateStatus;
        _scheduleGlobalStatusRefresh(globalStatus);
        _scheduleLivePromotionsRefresh(livePromotions);
        _serviceLimitedMessage = limited
            ? (limitedMessage.isNotEmpty
                ? limitedMessage
                : _tr('You are not allowed to see Store when you are out of Delivery Area'))
            : null;
        _isLoading = false;
      });
      if (appUpdateStatus != null) {
        await _maybeShowDailyUpdateReminder(appUpdateStatus);
      }
      _tryShowLaunchFlash();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resolveLocationContext() async {
    try {
      if (_userLat != null && _userLng != null) return;
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      _userLat = position.latitude;
      _userLng = position.longitude;
      try {
        final places = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (places.isNotEmpty) {
          _userCity =
              (places.first.locality ?? places.first.subAdministrativeArea ?? '')
                  .toString()
                  .trim();
        }
      } catch (_) {}
    } catch (_) {}
  }

  void _filterStores(String query) {
    if (query.isEmpty) {
      setState(() => _filteredStores = _allStores);
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _filteredStores = _allStores.where((store) {
        final name = (store['name'] ?? '').toString().toLowerCase();
        final location = (store['location'] ?? '').toString().toLowerCase();
        return name.contains(q) || location.contains(q);
      }).toList();
    });
  }

  Future<void> _makeCall(String phoneNumber) async {
    final cleaned = phoneNumber.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: cleaned);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _sendEmail(String emailAddress) async {
    final cleaned = emailAddress.trim();
    if (cleaned.isEmpty) return;
    final uri = Uri(
      scheme: 'mailto',
      path: cleaned,
      queryParameters: {'subject': _tr('OrderDrop Support')},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showSupportOptions() async {
    Map<String, dynamic> contact = _supportContact ?? const <String, dynamic>{};
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if ((contact['phone'] ?? '').toString().trim().isEmpty &&
        (contact['whatsapp'] ?? '').toString().trim().isEmpty &&
        (contact['email'] ?? '').toString().trim().isEmpty &&
        token != null) {
      try {
        contact = await ApiService.getCustomerSupportContact(token);
        if (!mounted) return;
        setState(() {
          _supportContact = contact;
        });
      } catch (_) {}
    }

    final name = (contact['name'] ?? _tr('Contact Us')).toString().trim();
    final phone = (contact['phone'] ?? '').toString().trim();
    final whatsapp = (contact['whatsapp'] ?? phone).toString().trim();
    final email = (contact['email'] ?? '').toString().trim();

    if (phone.isEmpty && whatsapp.isEmpty && email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('Support contact is not configured yet.'))),
      );
      return;
    }

    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? _tr('Contact Us') : name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  _tr('Choose how you want to contact us.'),
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                if (phone.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE8F1FF),
                      child: Icon(Icons.call_outlined, color: Colors.blue),
                    ),
                    title: Text(_tr('Call')),
                    subtitle: Text(phone),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _makeCall(phone);
                    },
                  ),
                if (whatsapp.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEAF9EF),
                      child: Icon(Icons.chat_outlined, color: Colors.green),
                    ),
                    title: Text(_tr('WhatsApp')),
                    subtitle: Text(whatsapp),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openWhatsApp(whatsapp);
                    },
                  ),
                if (email.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEFF3FF),
                      child: Icon(Icons.email_outlined, color: CustomerPalette.primary),
                    ),
                    title: Text(_tr('Email')),
                    subtitle: Text(email),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _sendEmail(email);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _compareVersionStrings(String current, String target) {
    List<int> parseParts(String value) {
      final cleaned = value.split('+').first.trim();
      if (cleaned.isEmpty) return const <int>[0];
      return cleaned
          .split('.')
          .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    final currentParts = parseParts(current);
    final targetParts = parseParts(target);
    final maxLen =
        currentParts.length > targetParts.length ? currentParts.length : targetParts.length;
    for (int i = 0; i < maxLen; i++) {
      final a = i < currentParts.length ? currentParts[i] : 0;
      final b = i < targetParts.length ? targetParts[i] : 0;
      if (a < b) return -1;
      if (a > b) return 1;
    }
    return 0;
  }

  Future<Map<String, dynamic>> _resolveAppUpdateStatus(String token) async {
    final status = await ApiService.getAppUpdateStatus(token);
    String installedVersion = '';
    String installedBuild = '';
    try {
      final info = await PackageInfo.fromPlatform();
      installedVersion = info.version.trim();
      installedBuild = info.buildNumber.trim();
    } catch (_) {}

    final latestVersion = (status['latest_version'] ?? '').toString().trim();
    final minimumSupportedVersion =
        (status['minimum_supported_version'] ?? '').toString().trim();
    final installedComparableVersion = installedVersion.isEmpty
        ? ''
        : (installedBuild.isNotEmpty
              ? '$installedVersion+$installedBuild'
              : installedVersion);
    final updateAvailable =
        latestVersion.isNotEmpty &&
        _compareVersionStrings(installedComparableVersion, latestVersion) < 0;
    final forcedByVersion = minimumSupportedVersion.isNotEmpty &&
        _compareVersionStrings(installedComparableVersion, minimumSupportedVersion) < 0;
    final reminderHour =
        int.tryParse((status['reminder_hour'] ?? '12').toString()) ?? 12;

    return {
      ...status,
      'installed_version': installedVersion,
      'installed_build': installedBuild,
      'installed_comparable_version': installedComparableVersion,
      'update_available': updateAvailable,
      'force_update_active':
          (status['force_update'] == true || status['force_update'] == 1) || forcedByVersion,
      'reminder_hour': reminderHour.clamp(0, 23),
    };
  }

  Future<void> _openAppUpdateLink([Map<String, dynamic>? status]) async {
    final update = status ?? _appUpdateStatus ?? const <String, dynamic>{};
    final url = (update['play_store_url'] ??
            'https://play.google.com/store/apps/details?id=com.onenetsol.orderdrop')
        .toString()
        .trim();
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _maybeShowDailyUpdateReminder(Map<String, dynamic> status) async {
    return;
  }

  bool _showAppUpdateBanner() {
    return false;
  }

  Widget _buildAppUpdateBanner() {
    final status = _appUpdateStatus ?? const <String, dynamic>{};
    final latestVersion = (status['latest_version'] ?? '').toString().trim();
    final installedVersion = (status['installed_version'] ?? '').toString().trim();
    final forceUpdate = status['force_update_active'] == true;
    final message = (status['message'] ?? _tr('A new version of OrderDrop is available.'))
        .toString()
        .trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD5A8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_alt, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  forceUpdate ? _tr('Update Required') : _tr('Update Available'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message.isNotEmpty ? message : _tr('A newer version of OrderDrop is available.'),
            style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '${_tr('Installed')}: ${installedVersion.isNotEmpty ? installedVersion : _tr('Unknown')}'
            '${latestVersion.isNotEmpty ? '   ${_tr('Latest')}: $latestVersion' : ''}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openAppUpdateLink(status),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(_tr('Update Now')),
                  style: FilledButton.styleFrom(
                    backgroundColor: CustomerPalette.primary,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              if (!forceUpdate) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _appUpdateStatus = {
                        ...status,
                        'update_available': false,
                      };
                    });
                  },
                  child: Text(_tr('Hide')),
                ),
              ],
            ],
          ),
        ],
      ),
    );
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

  DateTime? _parseDateTime(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  void _scheduleGlobalStatusRefresh(Map<String, dynamic>? status) {
    _globalStatusRefreshTimer?.cancel();
    if (status == null) return;

    final now = DateTime.now();
    final startAt = _parseDateTime(status['start_at']);
    final endAt = _parseDateTime(status['end_at']);
    final candidates = <DateTime>[
      if (startAt != null && startAt.isAfter(now)) startAt,
      if (endAt != null && endAt.isAfter(now)) endAt,
    ];
    if (candidates.isEmpty) return;

    candidates.sort();
    final nextTick = candidates.first;
    final delay = nextTick.difference(now) + const Duration(seconds: 1);
    _globalStatusRefreshTimer = Timer(delay, _refreshGlobalStatusOnly);
  }

  void _scheduleLivePromotionsRefresh(Map<String, dynamic>? promotions) {
    _livePromotionsRefreshTimer?.cancel();
    if (promotions == null) return;

    final now = DateTime.now();
    final startAt = _parseDateTime(promotions['start_at']);
    final endAt = _parseDateTime(promotions['end_at']);
    final candidates = <DateTime>[
      if (startAt != null && startAt.isAfter(now)) startAt,
      if (endAt != null && endAt.isAfter(now)) endAt,
    ];
    if (candidates.isEmpty) return;

    candidates.sort();
    final nextTick = candidates.first;
    final delay = nextTick.difference(now) + const Duration(seconds: 1);
    _livePromotionsRefreshTimer = Timer(delay, _refreshGlobalStatusOnly);
  }

  Future<void> _refreshGlobalStatusOnly() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      Map<String, dynamic>? status;
      Map<String, dynamic>? customerFlash;
      Map<String, dynamic>? supportContact;
      Map<String, dynamic>? appUpdateStatus;
      if (token != null) {
        status = await ApiService.getGlobalDeliveryStatus(token);
        try {
          customerFlash = await ApiService.getCustomerFlashMessage(token);
        } catch (_) {}
        try {
          supportContact = await ApiService.getCustomerSupportContact(token);
        } catch (_) {}
        try {
          appUpdateStatus = await _resolveAppUpdateStatus(token);
        } catch (_) {}
      }
      final promotions = await ApiService.getLivePromotions(token);
      if (!mounted) return;
      setState(() {
        _globalStatus = status;
        _livePromotions = promotions;
        _customerFlashMessage = customerFlash;
        _supportContact = supportContact;
        _appUpdateStatus = appUpdateStatus ?? _appUpdateStatus;
      });
      if (appUpdateStatus != null) {
        await _maybeShowDailyUpdateReminder(appUpdateStatus);
      }
      _scheduleGlobalStatusRefresh(status);
      _scheduleLivePromotionsRefresh(promotions);
      _tryShowLaunchFlash();
    } catch (_) {}
  }

  Map<String, dynamic>? _promotionFlashData() {
    final flash = _customerFlashMessage;
    if (flash != null && _toBool(flash['is_enabled'])) {
      final isVisible = _toBool(flash['is_visible']) ||
          (_toBool(flash['is_window_active']) &&
              (_toBool(flash['is_target_matched']) ||
                  (flash['notification_target'] ?? 'all').toString() == 'all'));
      if (isVisible) {
        final title =
            (flash['title'] ?? _tr('OrderDrop Flash Message')).toString().trim();
        final message = (flash['status_message'] ?? '').toString().trim();
        final imageUrl = ApiService.getImageUrl(
          (flash['image_url'] ?? '').toString().trim(),
        );
        final signature =
            '${flash['updated_at'] ?? ''}|$title|$message|$imageUrl|${flash['start_at'] ?? ''}|${flash['end_at'] ?? ''}';
        return {
          'title': title.isNotEmpty ? title : _tr('OrderDrop Flash Message'),
          'message': message.isNotEmpty
              ? message
              : _tr('Check latest updates in OrderDrop.'),
          'imageUrl': imageUrl,
          'signature': signature,
        };
      }
    }

    final promo = _livePromotions;
    if (promo == null) return null;
    if (!_toBool(promo['is_enabled'])) return null;
    if (!_toBool(promo['is_window_active']) && !_isGlobalWindowActive(promo)) {
      return null;
    }
    final title = (promo['title'] ?? _tr('OrderDrop Flash Message')).toString().trim();
    final message = _livePromotionMessage().trim();
    final images = _promotionImages();
    final imageUrl =
        images.isNotEmpty ? ApiService.getImageUrl(images.first) : '';
    final signature =
        '${promo['id'] ?? ''}|${promo['updated_at'] ?? ''}|$title|$message|$imageUrl';

    return {
      'title': title.isNotEmpty ? title : _tr('OrderDrop Flash Message'),
      'message': message.isNotEmpty
          ? message
          : _tr('Check latest promotions and events.'),
      'imageUrl': imageUrl,
      'signature': signature,
    };
  }

  void _tryShowLaunchFlash() {
    if (!mounted || _launchFlashShown) return;
    final flash = _promotionFlashData();
    if (flash == null) return;
    _launchFlashShown = true;

    final signature = (flash['signature'] ?? '').toString();
    if (signature.isNotEmpty && _launchFlashSignature != signature) {
      _launchFlashSignature = signature;
      try {
        Provider.of<app_notif.NotificationProvider>(context, listen: false)
            .addNotification(
              title: (flash['title'] ?? _tr('OrderDrop Flash Message')).toString(),
              message: (flash['message'] ?? '').toString(),
              type: 'promotion',
              icon: 'campaign',
            );
      } catch (_) {}
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showLaunchFlashDialog(flash);
    });
  }

  void _showLaunchFlashDialog(Map<String, dynamic> flash) {
    final title = (flash['title'] ?? _tr('OrderDrop Flash Message')).toString();
    final message = (flash['message'] ?? '').toString();
    final imageUrl = (flash['imageUrl'] ?? '').toString();

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: _tr('Flash Message'),
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.campaign, color: CustomerPalette.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 190,
                      width: double.infinity,
                      child: imageUrl.isNotEmpty
                          ? TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.92, end: 1.0),
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeOutBack,
                              builder: (context, scale, child) => Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: const Color(0xFFFDEBD0),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.image_not_supported_outlined,
                                    size: 34,
                                    color: Color(0xFFB35A00),
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              color: const Color(0xFFFDEBD0),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.celebration_outlined,
                                size: 44,
                                color: Color(0xFFB35A00),
                              ),
                            ),
                    ),
                  ),
                  if (message.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: CustomerPalette.primary,
                      ),
                      child: Text(_tr('OK')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  bool _isGlobalWindowActive(Map<String, dynamic> status) {
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

  bool _showGlobalStatusBanner() {
    final status = _globalStatus;
    if (status == null) return false;
    if (!_toBool(status['is_enabled'])) return false;
    return _isGlobalWindowActive(status);
  }

  bool _isGlobalOrderingBlocked() {
    final status = _globalStatus;
    if (status == null) return false;
    if (!_showGlobalStatusBanner()) return false;
    if (_toBool(status['block_ordering_active'])) return true;
    return _toBool(status['block_ordering']) && _isGlobalWindowActive(status);
  }

  String _globalStatusMessage() {
    final status = _globalStatus;
    if (status == null) return '';
    final message = (status['status_message'] ?? '').toString().trim();
    final when = _formatDeliveryWindow(status['start_at'], status['end_at']);
    if (message.isNotEmpty && when.isNotEmpty) return '$message ($when)';
    if (message.isNotEmpty) return message;
    if (when.isNotEmpty) return '${_tr('Delivery update')}: $when';
    final title = (status['title'] ?? '').toString().trim();
    return title;
  }

  String _formatDeliveryWindow(dynamic startRaw, dynamic endRaw) {
    final start = DateTime.tryParse((startRaw ?? '').toString());
    final end = DateTime.tryParse((endRaw ?? '').toString());
    if (start == null || end == null) return '';
    final startLocal = start.toLocal();
    final endLocal = end.toLocal();
    return '${startLocal.toString().substring(0, 16)} - ${endLocal.toString().substring(0, 16)}';
  }

  bool _showLivePromotionsCard() {
    final promo = _livePromotions;
    if (promo == null) return false;
    if (!_toBool(promo['is_enabled'])) return false;
    if (!_toBool(promo['is_window_active']) && !_isGlobalWindowActive(promo)) {
      return false;
    }
    return _promotionImages().isNotEmpty;
  }

  List<String> _promotionImages() {
    final promo = _livePromotions;
    if (promo == null) return const [];
    final raw = promo['widget_images'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .take(5)
        .toList();
  }

  String _livePromotionMessage() {
    final promo = _livePromotions;
    if (promo == null) return '';
    final reason = (promo['status_message'] ?? '').toString().trim();
    final when = _formatDeliveryWindow(promo['start_at'], promo['end_at']);
    if (reason.isNotEmpty && when.isNotEmpty) return '$reason ($when)';
    if (reason.isNotEmpty) return reason;
    if (when.isNotEmpty) return '${_tr('Promotion window')}: $when';
    return '';
  }

  Widget _buildGlobalStatusBanner() {
    final blocked = _isGlobalOrderingBlocked();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: blocked ? Colors.red.shade50 : Colors.orange.shade50,
        border: Border.all(
          color: blocked ? Colors.red.shade200 : Colors.orange.shade200,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            blocked ? Icons.block : Icons.info_outline,
            color: blocked ? Colors.red.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _globalStatusMessage(),
              style: TextStyle(
                color: blocked ? Colors.red.shade800 : Colors.orange.shade900,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openQuickActions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.shopping_bag_outlined),
                title: Text(_tr('My Orders')),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushNamed('/orders');
                },
              ),
              ListTile(
                leading: const Icon(Icons.shopping_cart_outlined),
                title: Text(_tr('My Cart')),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushNamed('/cart');
                },
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(_tr('Change Password')),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushNamed('/change-password');
                },
              ),
              ListTile(
                leading: const Icon(Icons.support_agent_outlined),
                title: Text(_tr('Contact Us')),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showSupportOptions();
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: Text(_tr('Logout'), style: const TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Provider.of<AuthProvider>(context, listen: false).logout();
                  Navigator.of(context).pushReplacementNamed('/login');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final crossAxisCount = isLandscape ? 4 : 2;

    return Directionality(
      textDirection: _isUrdu ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: CustomerPalette.background,
        body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(),
                if (user != null) _buildWelcomeText(user),
                if (user != null) _buildHeroCard(user),
                if (_showAppUpdateBanner()) _buildAppUpdateBanner(),
                _buildBannerSection(),
                _buildSearchField(),
                if (_showGlobalStatusBanner()) _buildGlobalStatusBanner(),
                if (_serviceLimitedMessage != null) _buildServiceLimitWarning(),
                _buildStoreSection(crossAxisCount),
                const SizedBox(height: 90),
              ],
            ),
          ),
        ),
      ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 2),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, size: 28),
            onPressed: _openQuickActions,
          ),
          Expanded(
            child: Text(
              _tr('Home'),
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
            ),
          ),
          TextButton.icon(
            onPressed: _showLanguageOptions,
            icon: const Icon(Icons.language, color: CustomerPalette.primary),
            label: Text(
              _languageLabel(),
              style: const TextStyle(
                color: CustomerPalette.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const NotificationBellWidget(),
          Consumer<CartProvider>(
            builder: (ctx, cart, child) => Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined),
                  onPressed: () => Navigator.of(context).pushNamed('/cart'),
                  tooltip: 'Cart',
                ),
                if (cart.itemCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${cart.itemCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
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

  Widget _buildWelcomeText(User user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr('Welcome'),
            style: TextStyle(fontSize: 18, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(User user) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [CustomerPalette.primary, CustomerPalette.primaryDark],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${user.firstName} ${user.lastName}'.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  _userCity?.isNotEmpty == true
                      ? '${_tr('Ref Area')}: $_userCity'
                      : _tr('OrderDrop Customer'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pushNamed('/orders'),
                        icon: const Icon(Icons.shopping_bag, size: 16),
                        label: Text(_tr('My Orders')),
                        style: FilledButton.styleFrom(
                          backgroundColor: CustomerPalette.accent,
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showSupportOptions,
                        icon: const Icon(Icons.support_agent, size: 16),
                        label: Text(_tr('Contact Us')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.storefront_outlined, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerSection() {
    final items = _liveWidgetItems;
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          SizedBox(
            height: 165,
            child: PageView.builder(
              controller: _bannerController,
              onPageChanged: (index) {
                setState(() => _activeBanner = index);
              },
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                if (item['type'] == 'promotion') {
                  final promoImages = _promotionImages();
                  final promoTitle = (_livePromotions?['title'] ?? _tr('Live Promotions'))
                      .toString()
                      .trim();
                  final promoMessage = _livePromotionMessage();
                  final bg = promoImages.isNotEmpty
                      ? ApiService.getImageUrl(promoImages.first)
                      : '';
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (bg.isNotEmpty)
                          Image.network(
                            bg,
                            fit: BoxFit.cover,
                            errorBuilder: (_, error, stackTrace) => Container(
                              color: CustomerPalette.primaryDark,
                            ),
                          )
                        else
                          Container(color: CustomerPalette.primaryDark),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.74),
                                Colors.black.withValues(alpha: 0.2),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Text(
                                  _tr('Live: Promotions / Events'),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                promoTitle.isNotEmpty
                                    ? promoTitle
                                    : _tr('Live Promotions'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (promoMessage.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  promoMessage,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (promoImages.length > 1) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '${promoImages.length} ${_tr('live widgets')}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                if (item['type'] == 'status') {
                  final blocked = _isGlobalOrderingBlocked();
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: blocked
                            ? const [Color(0xFFB71C1C), Color(0xFFE53935)]
                            : const [Color(0xFFEF6C00), Color(0xFFFFA726)],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                blocked ? Icons.block : Icons.info_outline,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  blocked
                                      ? _tr('Live Delivery Pause')
                                      : _tr('Delivery Update'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: Text(
                              _globalStatusMessage(),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final store = item['data'];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        ApiService.getImageUrl(store['image_url']),
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, _) => Container(
                          color: CustomerPalette.primaryDark,
                          child: const Icon(
                            Icons.store,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.58),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Text(
                          (store['name'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(items.length, (i) {
              final active = i == _activeBanner;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color:
                      active ? CustomerPalette.primaryDark : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: _tr('Search store by name or area'),
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(14),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildServiceLimitWarning() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        border: Border.all(color: const Color(0xFFFFCC80)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFE65100)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _serviceLimitedMessage ?? '',
              style: const TextStyle(
                color: Color(0xFFE65100),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreSection(int crossAxisCount) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 50.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(child: Text('Error: $_errorMessage')),
      );
    }
    if (_filteredStores.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Text(_serviceLimitedMessage ?? _tr('No stores found in this category')),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.73,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: _filteredStores.length,
        itemBuilder: (context, index) => _buildStoreCard(_filteredStores[index]),
      ),
    );
  }

  Widget _buildStoreCard(dynamic store) {
    final bool isOpen = store['is_open'] == true || store['is_open'] == 1;
    final String closedReason = (store['status_message'] ?? '').toString().trim();

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (ctx) => StoreScreen(storeId: store['id'])),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: isOpen ? Colors.green.shade100 : Colors.red.shade100,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Center(
                child: Text(
                  isOpen ? _tr('OPEN') : _tr('CLOSED'),
                  style: TextStyle(
                    color: isOpen ? Colors.green.shade800 : Colors.red.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(0),
                    ),
                    child: Image.network(
                      ApiService.getImageUrl(store['image_url']),
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, _) => Container(
                        color: Colors.grey[300],
                        child: const Center(
                          child: Icon(Icons.store, size: 38, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  if (!isOpen && closedReason.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        color: Colors.red.withValues(alpha: 0.88),
                        child: Text(
                          closedReason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (store['name'] ?? _tr('Unknown Store')).toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (store['location'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 11, color: Colors.blueGrey),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          '${_formatTimeOnly(store['opening_time'])} - ${_formatTimeOnly(store['closing_time'])}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.blueGrey,
                            fontWeight: FontWeight.w600,
                          ),
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
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildBottomIcon(
              index: 0,
              icon: Icons.home_filled,
              label: _tr('Home'),
              onTap: () => setState(() => _bottomIndex = 0),
            ),
            _buildBottomIcon(
              index: 1,
              icon: Icons.storefront,
              label: _tr('Stores'),
              onTap: () => setState(() => _bottomIndex = 1),
            ),
            _buildBottomIcon(
              index: 2,
              icon: Icons.shopping_bag,
              label: _tr('Orders'),
              onTap: () {
                setState(() => _bottomIndex = 2);
                Navigator.of(context).pushNamed('/orders');
              },
            ),
            _buildBottomIcon(
              index: 3,
              icon: Icons.shopping_cart,
              label: _tr('Cart'),
              badgeCount: context.watch<CartProvider>().itemCount,
              onTap: () {
                setState(() => _bottomIndex = 3);
                Navigator.of(context).pushNamed('/cart');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomIcon({
    required int index,
    required IconData icon,
    required String label,
    int badgeCount = 0,
    required VoidCallback onTap,
  }) {
    final active = _bottomIndex == index;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: active
                      ? CustomerPalette.primaryDark
                      : Colors.grey.shade600,
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -9,
                    top: -7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: CustomerPalette.primaryDark,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color:
                    active ? CustomerPalette.primaryDark : Colors.grey.shade600,
              ),
            ),
          ],
        ),
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

}


