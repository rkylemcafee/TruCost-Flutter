import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'calculator/calculator_screen.dart';
import 'route/route_screen.dart';
import 'trips/saved_trips_screen.dart';
import 'contacts/contacts_screen.dart';
import 'copilot/copilot_screen.dart';
import 'expenses/receipt_capture_screen.dart';
import 'settings/settings_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _supabase = Supabase.instance.client;
  String? _splashUrl;

  @override
  void initState() {
    super.initState();
    _loadSplash();
  }

  Future<void> _loadSplash() async {
    // Cloud splash photo, set by the operator in Settings. If none, we show
    // the built-in TruCost logo on a black field.
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final p = await _supabase
          .from('profiles')
          .select('splash_photo_url')
          .eq('user_id', user.id)
          .maybeSingle();
      final url = p?['splash_photo_url']?.toString();
      if (mounted) {
        setState(() => _splashUrl = (url != null && url.isNotEmpty) ? url : null);
      }
    } catch (_) {}
  }

  bool get _usingDefaultLogo => _splashUrl == null;

  Widget _buildBackground() {
    if (_splashUrl != null) {
      return Opacity(
        opacity: 0.3,
        child: Image.network(
          _splashUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: Colors.black),
        ),
      );
    }
    // Default: black field; the TruCost logo rides in the header below.
    return Container(color: Colors.black);
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white),
                        tooltip: 'Setup & Settings',
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          );
                          if (mounted) _loadSplash();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white),
                        tooltip: 'Sign out',
                        onPressed: () => _supabase.auth.signOut(),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (_usingDefaultLogo)
                  Flexible(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Image.asset(
                        'assets/images/trucost_logo.jpg',
                        fit: BoxFit.contain,
                      ),
                    ),
                  )
                else ...[
                  const Text(
                    'TruCost',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 10, color: Colors.black54)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Owner-Operator Co-Pilot',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  user?.email ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white60,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      _navButton(context, Icons.route, 'Route a Load', const RouteScreen(), filled: true),
                      const SizedBox(height: 12),
                      _navButton(context, Icons.calculate, 'I Know My Miles', const CalculatorScreen()),
                      const SizedBox(height: 12),
                      _navButton(context, Icons.bookmark, 'Saved Trips', const SavedTripsScreen()),
                      const SizedBox(height: 12),
                      _navButton(context, Icons.receipt_long, 'Scan Receipt', const ReceiptCaptureScreen()),
                      const SizedBox(height: 12),
                      _navButton(context, Icons.people, 'Contacts', const ContactsScreen()),
                      const SizedBox(height: 12),
                      _navButton(context, Icons.mic, 'Co-Pilot', const CopilotScreen()),
                      const SizedBox(height: 12),
                      _navButton(context, Icons.tune, 'Setup', const SettingsScreen()),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navButton(BuildContext context, IconData icon, String label, Widget screen, {bool filled = false}) {
    Future<void> go() async {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
      if (mounted) _loadSplash(); // pick up a home photo changed in Settings
    }
    return SizedBox(
      width: double.infinity,
      child: filled
          ? ElevatedButton.icon(
              onPressed: go,
              icon: Icon(icon, size: 24),
              label: Text(label, style: const TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.white,
                foregroundColor: Colors.blueGrey[800],
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          : OutlinedButton.icon(
              onPressed: go,
              icon: Icon(icon, size: 24),
              label: Text(label, style: const TextStyle(fontSize: 18)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
    );
  }
}
