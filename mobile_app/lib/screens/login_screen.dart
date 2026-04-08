import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/notifier.dart';
import '../utils/customer_language.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _isUrdu = false;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  Future<void> _loadLanguagePreference() async {
    final isUrdu = await CustomerLanguage.loadIsUrdu();
    if (!mounted) return;
    setState(() => _isUrdu = isUrdu);
  }

  Future<void> _setLanguage(bool isUrdu) async {
    await CustomerLanguage.saveIsUrdu(isUrdu);
    if (!mounted) return;
    setState(() => _isUrdu = isUrdu);
  }

  String _tr(String text) => CustomerLanguage.tr(_isUrdu, text);

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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
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
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await Provider.of<AuthProvider>(
        context,
        listen: false,
      ).login(_emailController.text, _passwordController.text);

      if (!mounted) return;

      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.isAdmin) {
        Navigator.of(context).pushReplacementNamed('/admin');
      } else if (auth.isRider) {
        Navigator.of(context).pushReplacementNamed('/rider');
      } else if (auth.isStoreOwner) {
        Navigator.of(context).pushReplacementNamed('/store_owner');
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        Notifier.error(context, e.toString());
      }
    }
  }

  Future<void> _continueAsGuest() async {
    try {
      await Provider.of<AuthProvider>(context, listen: false).guestLogin();

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      if (mounted) {
        Notifier.error(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: CustomerLanguage.textDirection(_isUrdu),
      child: Scaffold(
        body: Stack(
          children: [
            const _LoginBackground(),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: _LanguageChip(
                    label: _languageLabel(),
                    onTap: _showLanguageOptions,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth > 560
                      ? 410.0
                      : constraints.maxWidth - 36;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 48,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: cardWidth,
                          child: _GlassCard(
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/icon/logo_w.png',
                                    height: 128,
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, stack) =>
                                        const Text(
                                          'OrderDrop',
                                          style: TextStyle(
                                            fontSize: 40,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF121212),
                                          ),
                                        ),
                                  ),
                                  const SizedBox(height: 6),

                                  const SizedBox(height: 34),
                                  _RoundedInput(
                                    controller: _emailController,
                                    hintText: _tr('EMAIL'),
                                    textInputAction: TextInputAction.next,
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return _tr('Please enter email');
                                      }
                                      if (!value.contains('@')) {
                                        return _tr('Enter a valid email');
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 18),
                                  _RoundedInput(
                                    controller: _passwordController,
                                    hintText: _tr('PASSWORD'),
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _submit(),
                                    suffixIcon: IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: const Color(0xFF859198),
                                      ),
                                    ),
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                        ? _tr('Please enter password')
                                        : null,
                                  ),
                                  const SizedBox(height: 24),
                                  Selector<AuthProvider, bool>(
                                    selector: (_, auth) => auth.isLoading,
                                    builder: (context, isLoading, child) {
                                      return SizedBox(
                                        width: double.infinity,
                                        height: 58,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              29,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFF7DBD38,
                                                ).withValues(alpha: 0.32),
                                                blurRadius: 20,
                                                offset: const Offset(0, 12),
                                              ),
                                            ],
                                          ),
                                          child: ElevatedButton(
                                            onPressed: isLoading
                                                ? null
                                                : _submit,
                                            style: ElevatedButton.styleFrom(
                                              elevation: 0,
                                              foregroundColor: Colors.white,
                                              padding: EdgeInsets.zero,
                                              backgroundColor:
                                                  Colors.transparent,
                                              disabledBackgroundColor:
                                                  Colors.transparent,
                                              shadowColor: Colors.transparent,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(29),
                                              ),
                                            ),
                                            child: Ink(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(29),
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFF9BDA45),
                                                    Color(0xFF74BF38),
                                                  ],
                                                ),
                                              ),
                                              child: Center(
                                                child: isLoading
                                                    ? const SizedBox(
                                                        height: 24,
                                                        width: 24,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2.6,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      )
                                                    : Text(
                                                        _tr('LOG IN'),
                                                        style: const TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          letterSpacing: 0.4,
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(
                                        context,
                                      ).pushNamed('/forgot-password');
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF3D4A4F),
                                      textStyle: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    child: Text(_tr('Forgot Password?')),
                                  ),
                                  Transform.translate(
                                    offset: const Offset(0, -4),
                                    child: TextButton(
                                      onPressed: () {
                                        Navigator.of(
                                          context,
                                        ).pushNamed('/register');
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFFF8F9FB,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      child: Text(_tr('Create Account')),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _SocialButton(
                                        background: Colors.white,
                                        foreground: const Color(0xFF4267B2),
                                        icon: const Icon(
                                          Icons.facebook,
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(width: 26),
                                      const _SocialButton(
                                        background: Colors.white,
                                        foreground: Color(0xFFDB4437),
                                        label: 'G',
                                      ),
                                      const SizedBox(width: 26),
                                      const _SocialButton(
                                        background: Colors.white,
                                        foreground: Color(0xFFF4F7FA),
                                        icon: Icon(
                                          Icons.apple,
                                          size: 28,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Selector<AuthProvider, bool>(
                                    selector: (_, auth) => auth.isLoading,
                                    builder: (context, isLoading, child) {
                                      return TextButton(
                                        onPressed: isLoading
                                            ? null
                                            : _continueAsGuest,
                                        style: TextButton.styleFrom(
                                          foregroundColor: const Color(
                                            0xFF516167,
                                          ),
                                        ),
                                        child: Text(_tr('Continue as Guest')),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFD5EBA8), Color(0xFFBEDFD3), Color(0xFF9EC7F1)],
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.03),
                ],
              ),
            ),
          ),
        ),
        const _BlurBlob(
          alignment: Alignment.topLeft,
          color: Color(0xFFF4E58C),
          size: 170,
          xOffset: -36,
          yOffset: 84,
        ),
        const _BlurBlob(
          alignment: Alignment.centerRight,
          color: Color(0xFFB3DBFF),
          size: 200,
          xOffset: 54,
          yOffset: 10,
        ),
        const _BlurBlob(
          alignment: Alignment.bottomLeft,
          color: Color(0xFFE7F0B2),
          size: 190,
          xOffset: -34,
          yOffset: -36,
        ),
      ],
    );
  }
}

class _BlurBlob extends StatelessWidget {
  const _BlurBlob({
    required this.alignment,
    required this.color,
    required this.size,
    this.xOffset = 0,
    this.yOffset = 0,
  });

  final Alignment alignment;
  final Color color;
  final double size;
  final double xOffset;
  final double yOffset;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: Offset(xOffset, yOffset),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(26, 34, 26, 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            color: Colors.white.withValues(alpha: 0.28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6A8CA1).withValues(alpha: 0.18),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _RoundedInput extends StatelessWidget {
  const _RoundedInput({
    required this.controller,
    required this.hintText,
    required this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w500,
        color: Color(0xFF39474E),
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF9AA2A8),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.94),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 20,
        ),
        errorStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.75)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF81C93C), width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFC75353)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFC75353), width: 1.2),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.background,
    required this.foreground,
    this.icon,
    this.label,
  });

  final Color background;
  final Color foreground;
  final Widget? icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background.withValues(alpha: 0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child:
            icon ??
            Text(
              label ?? '',
              style: TextStyle(
                color: foreground,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
