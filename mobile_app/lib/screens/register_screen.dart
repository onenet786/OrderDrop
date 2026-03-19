import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/notifier.dart';
import '../theme/customer_palette.dart';
import 'verification_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _dobController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime? _selectedDob;
  bool _updatingPhone = false;

  @override
  void initState() {
    super.initState();
    _phoneController.text = '+923';
    _phoneController.selection = TextSelection.collapsed(
      offset: _phoneController.text.length,
    );
    _phoneController.addListener(_enforcePhonePrefix);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_enforcePhonePrefix);
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final fullName = _fullNameController.text.trim();
      final nameParts =
          fullName.isEmpty ? <String>[] : fullName.split(RegExp(r'\s+'));
      final firstName = nameParts.isNotEmpty ? nameParts.first : fullName;
      final lastName = nameParts.length > 1
          ? nameParts.sublist(1).join(' ')
          : fullName;
      final requiresVerification = await Provider.of<AuthProvider>(context, listen: false).register(
        firstName: firstName,
        lastName: lastName,
        dateOfBirth: _dobController.text,
        email: _emailController.text,
        password: _passwordController.text,
        phone: _phoneController.text,
        address: _addressController.text,
      );

      if (!mounted) return;

      if (requiresVerification) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => VerificationScreen(email: _emailController.text),
          ),
        );
      } else {
        // Navigate to home or show success
        final auth = Provider.of<AuthProvider>(context, listen: false);
        if (auth.isAdmin) {
          Navigator.of(context).pushReplacementNamed('/admin');
        } else if (auth.isRider) {
          Navigator.of(context).pushReplacementNamed('/rider');
        } else {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
    } catch (e) {
      if (mounted) {
        Notifier.error(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              CustomerPalette.primary,
              CustomerPalette.primaryDark,
              CustomerPalette.accent,
            ],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                top: 36,
                bottom:
                    MediaQuery.of(context).size.height *
                    0.1, // Slightly less bottom padding for taller form
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBrandHeader(),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 350),
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: CustomerPalette.card.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Register for ServeNow',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: CustomerPalette.textDark,
                                ),
                              ),
                              const SizedBox(height: 20),
                              // First Name & Last Name Row
                              TextFormField(
                                controller: _fullNameController,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(
                                  color: CustomerPalette.textDark,
                                ),
                                decoration: _buildInputDecoration(
                                  context,
                                  'Full Name',
                                  Icons.person,
                                ),
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  if (trimmed.isEmpty) return 'Full name is required';
                                  if (trimmed.length < 2) {
                                    return 'Full name is too short';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(
                                  color: CustomerPalette.textDark,
                                ),
                                decoration: _buildInputDecoration(
                                  context,
                                  'Email Address',
                                  Icons.email,
                                ),
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  if (trimmed.isEmpty) return 'Email is required';
                                  if (!trimmed.contains('@')) {
                                    return 'Enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordController,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(
                                  color: CustomerPalette.textDark,
                                ),
                                decoration: _buildInputDecoration(
                                  context,
                                  'Password',
                                  Icons.lock,
                                ),
                                obscureText: true,
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  if (trimmed.isEmpty) return 'Password is required';
                                  if (trimmed.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _dobController,
                                readOnly: true,
                                style: const TextStyle(
                                  color: CustomerPalette.textDark,
                                ),
                                decoration: _buildInputDecoration(
                                  context,
                                  'Date of Birth',
                                  Icons.cake_outlined,
                                ).copyWith(
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.calendar_today_outlined),
                                    onPressed: () => _selectDob(context),
                                  ),
                                ),
                                onTap: () => _selectDob(context),
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  if (trimmed.isEmpty) {
                                    return 'Date of birth is required';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9+]'),
                                  ),
                                  LengthLimitingTextInputFormatter(13),
                                ],
                                style: const TextStyle(
                                  color: CustomerPalette.textDark,
                                ),
                                decoration: _buildInputDecoration(
                                  context,
                                  'Phone Number',
                                  Icons.phone,
                                ),
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  if (trimmed.isEmpty) {
                                    return 'Phone number is required';
                                  }
                                  if (!RegExp(r'^\+923\d{9}$')
                                      .hasMatch(trimmed)) {
                                    return 'Use +923 followed by 9 digits';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _addressController,
                                textInputAction: TextInputAction.done,
                                style: const TextStyle(
                                  color: CustomerPalette.textDark,
                                ),
                                decoration: _buildInputDecoration(
                                  context,
                                  'Address',
                                  Icons.location_on,
                                ),
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  if (trimmed.isEmpty) {
                                    return 'Address is required';
                                  }
                                  if (trimmed.length < 4) {
                                    return 'Address is too short';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: Selector<AuthProvider, bool>(
                                  selector: (_, auth) => auth.isLoading,
                                  builder: (context, isLoading, child) {
                                    return ElevatedButton(
                                      onPressed: isLoading ? null : _submit,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            CustomerPalette.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: isLoading
                                          ? const CircularProgressIndicator(
                                              color: Colors.white,
                                            )
                                          : const Text(
                                              'Register',
                                              style: TextStyle(
                                                fontSize: 18,
                                                color: Colors.white,
                                              ),
                                            ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context)
                                      .pop(); // Go back to login
                                },
                                child: Text(
                                  'Already have an account? Login here',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
            ),
          ),
          child: Image.asset(
            'assets/icon/servenow_brand_logo.png',
            height: 84,
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => const Text(
              'ServeNow',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Create your account',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _selectDob(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final today = DateTime.now();
    final initialDate =
        _selectedDob ?? DateTime(today.year - 18, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900, 1, 1),
      lastDate: today,
      helpText: 'Select date of birth',
      cancelText: 'Cancel',
      confirmText: 'Select',
    );
    if (picked == null) return;
    setState(() {
      _selectedDob = picked;
      _dobController.text = _formatDate(picked);
    });
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  void _enforcePhonePrefix() {
    if (_updatingPhone) return;
    final text = _phoneController.text;
    if (text.startsWith('+923')) {
      return;
    }

    _updatingPhone = true;
    final digitsOnly = text.replaceAll(RegExp(r'\D'), '');
    String suffix = digitsOnly;
    if (digitsOnly.startsWith('923')) {
      suffix = digitsOnly.substring(3);
    } else if (digitsOnly.startsWith('3')) {
      suffix = digitsOnly.substring(1);
    }
    var next = '+923$suffix';
    if (next.length > 13) {
      next = next.substring(0, 13);
    }
    _phoneController.text = next;
    _phoneController.selection = TextSelection.collapsed(
      offset: _phoneController.text.length,
    );
    _updatingPhone = false;
  }

  InputDecoration _buildInputDecoration(
    BuildContext context,
    String label,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final hintColor = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: hintColor),
      prefixIcon: Icon(icon, color: theme.colorScheme.primary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
    );
  }
}
