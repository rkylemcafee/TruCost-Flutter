import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Two-step login: enter email → enter 6-digit code.
/// No password anywhere. Auth state change triggers AuthGate redirect.
///
/// Goes in: lib/auth/login_page.dart

enum _LoginStep { email, otp }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _supabase = Supabase.instance.client;
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();

  _LoginStep _step = _LoginStep.email;
  bool _loading = false;
  String _email = '';

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // ── Step 1: send the 6-digit code ──────────────────────────
  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _loading = true);
    try {
      await _supabase.auth.signInWithOtp(email: email);
      setState(() {
        _email = email;
        _step = _LoginStep.otp;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending code: $e')),
        );
      }
    }
  }

  // ── Step 2: verify the code ────────────────────────────────
  Future<void> _verifyOtp() async {
    final token = _otpController.text.trim();
    if (token.isEmpty) return;

    setState(() => _loading = true);
    try {
      await _supabase.auth.verifyOTP(
        email: _email,
        token: token,
        type: OtpType.email,
      );
      // Success → auth state changes → AuthGate redirects to HomePage.
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid code. Try again.')),
        );
      }
    }
  }

  // ── Resend ─────────────────────────────────────────────────
  Future<void> _resendOtp() async {
    setState(() => _loading = true);
    try {
      await _supabase.auth.signInWithOtp(email: _email);
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New code sent. Check your email.')),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: SingleChildScrollView(
              child: _step == _LoginStep.email
                  ? _buildEmailStep()
                  : _buildOtpStep(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Email entry ────────────────────────────────────────────
  Widget _buildEmailStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'TruCost',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Owner-Operator Co-Pilot',
          style: TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.go,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'you@example.com',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email_outlined),
          ),
          onSubmitted: (_) => _sendOtp(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loading ? null : _sendOtp,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _loading
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send Code', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  // ── OTP entry ──────────────────────────────────────────────
  Widget _buildOtpStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 64, color: Colors.blueGrey),
        const SizedBox(height: 16),
        const Text(
          'Check Your Email',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'We sent a 6-digit code to\n$_email',
          style: const TextStyle(fontSize: 14, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 8,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, letterSpacing: 12),
          decoration: const InputDecoration(
            labelText: 'Code',
            border: OutlineInputBorder(),
            counterText: '', // hides the "0/6" counter
          ),
          onSubmitted: (_) => _verifyOtp(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loading ? null : _verifyOtp,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _loading
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading ? null : _resendOtp,
          child: const Text("Didn't get it? Resend code"),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _step = _LoginStep.email;
              _otpController.clear();
            });
          },
          child: const Text('Use a different email'),
        ),
      ],
    );
  }
}
