import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/notifier.dart';
import 'reset_password_screen.dart';

class OTPResetVerificationScreen extends StatefulWidget {
  final String email;
  const OTPResetVerificationScreen({super.key, required this.email});

  @override
  State<OTPResetVerificationScreen> createState() => _OTPResetVerificationScreenState();
}

class _OTPResetVerificationScreenState extends State<OTPResetVerificationScreen> {
  final _codeController = TextEditingController();

  Future<void> _verify() async {
    if (_codeController.text.length != 6) {
      Notifier.error(context, 'Please enter a 6-digit code');
      return;
    }

    try {
      final resetToken = await Provider.of<AuthProvider>(context, listen: false).verifyResetOTP(
        widget.email,
        _codeController.text,
      );
      
      if (!mounted) return;
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (ctx) => ResetPasswordScreen(token: resetToken),
        ),
      );
    } catch (e) {
      if (mounted) {
        Notifier.error(context, e.toString());
      }
    }
  }

  Future<void> _resend() async {
    try {
      await Provider.of<AuthProvider>(context, listen: false).forgotPassword(widget.email);
      if (!mounted) return;
      Notifier.success(context, 'Verification code resent!');
    } catch (e) {
      if (mounted) {
        Notifier.error(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/login.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.3),
              BlendMode.darken,
            ),
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).size.height * 0.2,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 350),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 250, 250, 248),
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Verify OTP',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Please enter the 6-digit code sent to\n${widget.email}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, letterSpacing: 5, color: Colors.black87),
                          decoration: const InputDecoration(
                            hintText: '000000',
                            counterText: '',
                            border: OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.black26),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.blueAccent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: Selector<AuthProvider, bool>(
                            selector: (_, auth) => auth.isLoading,
                            builder: (context, isLoading, child) {
                              return ElevatedButton(
                                onPressed: isLoading ? null : _verify,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: isLoading
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : const Text(
                                        'Verify OTP',
                                        style: TextStyle(fontSize: 18, color: Colors.white),
                                      ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _resend,
                          child: const Text(
                            'Resend Code',
                            style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
