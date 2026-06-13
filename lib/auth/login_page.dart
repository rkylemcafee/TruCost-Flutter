import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Email + password login.
///   • Existing users sign in and land straight on their data (onboarding is skipped).
///   • New users create an account and go through onboarding.
///   • "Email me a code" is the fallback — first-time, forgot password, or
///     accounts created before passwords existed (use it once, then set a
///     password in Settings).
///
/// Goes in: lib/auth/login_page.dart (replaces the code-only version)

enum _Mode { signIn, signUp }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _supabase = Supabase.instance.client;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _loading = false;
  bool _obscure = true;
  bool _codeSent = false;
  String _otpEmail = '';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  // ── Password sign in / sign up ─────────────────────────────
  Future<void> _submitPassword() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      _toast('Enter your email and password.');
      return;
    }
    if (_mode == _Mode.signUp && password.length < 6) {
      _toast('Pick a password at least 6 characters long.');
      return;
    }

    setState(() => _loading = true);
    try {
      if (_mode == _Mode.signIn) {
        await _supabase.auth.signInWithPassword(email: email, password: password);
        // success → AuthGate takes over and routes to Home
      } else {
        final res = await _supabase.auth.signUp(email: email, password: password);
        if (res.session == null) {
          // email confirmation is on — they must confirm before signing in
          _toast('Account created. Check your email to confirm, then sign in.');
          setState(() {
            _mode = _Mode.signIn;
            _loading = false;
          });
          return;
        }
        // confirmation off → signed in → AuthGate routes to onboarding
      }
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Forgot password (email reset link) ─────────────────────
  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _toast('Type your email first, then tap "Forgot password".');
      return;
    }
    setState(() => _loading = true);
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      _toast('Reset link sent to $email.');
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Could not send reset: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Email-code fallback: send ──────────────────────────────
  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _toast('Enter your email first.');
      return;
    }
    setState(() => _loading = true);
    try {
      await _supabase.auth.signInWithOtp(email: email);
      setState(() {
        _otpEmail = email;
        _codeSent = true;
        _loading = false;
      });
    } on AuthException catch (e) {
      setState(() => _loading = false);
      _toast(e.message);
    } catch (e) {
      setState(() => _loading = false);
      _toast('Could not send code: $e');
    }
  }

  // ── Email-code fallback: verify ────────────────────────────
  Future<void> _verifyCode() async {
    final token = _codeCtrl.text.trim();
    if (token.isEmpty) {
      _toast('Enter the code from your email.');
      return;
    }
    setState(() => _loading = true);
    try {
      await _supabase.auth.verifyOTP(email: _otpEmail, token: token, type: OtpType.email);
      // success → AuthGate takes over
    } on AuthException catch (e) {
      setState(() => _loading = false);
      _toast(e.message);
    } catch (e) {
      setState(() => _loading = false);
      _toast('Invalid code. Try again.');
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
              child: _codeSent ? _buildCodeStep() : _buildPasswordStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() => Column(
        children: const [
          Text('TruCost',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          SizedBox(height: 8),
          Text('Owner-Operator Co-Pilot',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center),
        ],
      );

  Widget _buildPasswordStep() {
    final signIn = _mode == _Mode.signIn;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 40),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'you@example.com',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => _submitPassword(),
        ),
        if (signIn)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading ? null : _forgotPassword,
              child: const Text('Forgot password?'),
            ),
          ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _loading ? null : _submitPassword,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _loading
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(signIn ? 'Sign In' : 'Create Account',
                  style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _loading
              ? null
              : () => setState(() => _mode = signIn ? _Mode.signUp : _Mode.signIn),
          child: Text(signIn
              ? 'New here? Create an account'
              : 'Already have an account? Sign in'),
        ),
        const Divider(height: 24),
        TextButton.icon(
          onPressed: _loading ? null : _sendCode,
          icon: const Icon(Icons.mail_outline, size: 18),
          label: const Text('Email me a sign-in code instead'),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 64, color: Colors.blueGrey),
        const SizedBox(height: 16),
        const Text('Check Your Email',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('We sent a sign-in code to\n$_otpEmail',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 8,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, letterSpacing: 12),
          decoration: const InputDecoration(
            labelText: 'Code',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          onSubmitted: (_) => _verifyCode(),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _loading ? null : _verifyCode,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _loading
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Verify', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _codeSent = false;
            _codeCtrl.clear();
          }),
          child: const Text('Back'),
        ),
      ],
    );
  }
}
