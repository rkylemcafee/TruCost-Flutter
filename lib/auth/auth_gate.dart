import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';
import '../onboarding/onboarding_flow.dart';
import '../home_page.dart';

/// Routes: no session -> Login, session + not onboarded -> Onboarding, else -> Home.
///
/// Goes in: lib/auth/auth_gate.dart (replaces previous version)

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authStream;

  @override
  void initState() {
    super.initState();
    _authStream = Supabase.instance.client.auth.onAuthStateChange;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final session = snapshot.hasData ? snapshot.data!.session : null;
        if (session != null) {
          return const _ProfileGate();
        }
        return const LoginPage();
      },
    );
  }
}

/// Ensures a profile row exists, then checks onboarding_complete.
class _ProfileGate extends StatefulWidget {
  const _ProfileGate();
  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  bool _onboardingComplete = false;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      var profile = await _supabase
          .from('profiles')
          .select('onboarding_complete')
          .eq('user_id', user.id)
          .maybeSingle();

      if (profile == null) {
        await _supabase.from('profiles').insert({
          'user_id': user.id,
          'email': user.email,
        });
        profile = {'onboarding_complete': false};
      }

      if (mounted) {
        setState(() {
          _onboardingComplete = profile!['onboarding_complete'] == true;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_onboardingComplete) {
      return const HomePage();
    }
    return OnboardingFlow(
      onComplete: () => setState(() => _onboardingComplete = true),
    );
  }
}
