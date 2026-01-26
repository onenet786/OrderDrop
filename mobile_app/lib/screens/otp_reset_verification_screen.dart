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
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Icon Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mark_email_read_outlined,
                size: 60,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            
            Text(
              'Verify Your Email',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            RichText(
              text: TextSpan(
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.black54,
                  height: 1.5,
                ),
                children: [
                  const TextSpan(text: 'We\'ve sent a 6-digit verification code to '),
                  TextSpan(
                    text: widget.email,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            
            // OTP Input
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 20,
                color: Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: '000000',
                hintStyle: TextStyle(
                  color: Colors.grey.shade300,
                  letterSpacing: 20,
                ),
                counterText: '',
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade300, width: 2),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 48),
            
            // Verify Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: Selector<AuthProvider, bool>(
                selector: (_, auth) => auth.isLoading,
                builder: (context, isLoading, child) {
                  return ElevatedButton(
                    onPressed: isLoading ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'VERIFY OTP',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 32),
            // Resend Option
            Center(
              child: Column(
                children: [
                  const Text(
                    'Didn\'t receive the code?',
                    style: TextStyle(color: Colors.black54),
                  ),
                  TextButton(
                    onPressed: _resend,
                    child: Text(
                      'Resend Code',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
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
