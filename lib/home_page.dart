import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'calculator/calculator_screen.dart';
import 'quote/quote_screen.dart';
import 'quote/ugly_truth_screen.dart';
import 'route/route_screen.dart'; // kept: route screen still available for reuse
import 'trips/saved_trips_screen.dart';
import 'trips/trip_sheet_screen.dart';
import 'contacts/contacts_screen.dart';
import 'copilot/copilot_screen.dart';
import 'expenses/receipt_capture_screen.dart';
import 'expenses/document_viewer_screen.dart';
import 'settings/settings_screen.dart';
import 'admin/agent_admin_screen.dart';
import 'about/about_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _supabase = Supabase.instance.client;
  String? _splashUrl;
  String? _role;

  // Built-in default background, shown until the operator sets their own
  // splash photo in Settings.
  static const String _defaultBackgroundAsset = 'assets/images/trucost_logo.jpg';

  bool get _isAdmin => _role == 'admin' || _role == 'assistant_admin';

  @override
  void initState() {
    super.initState();
    _loadSplash();
  }

  Future<void> _loadSplash() async {
    // Cloud splash photo, set by the operator in Settings. If none, we fall
    // back to the built-in TruCost truck background.
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final p = await _supabase
          .from('profiles')
          .select('splash_photo_url, role')
          .eq('user_id', user.id)
          .maybeSingle();
      final url = p?['splash_photo_url']?.toString();
      final role = p?['role']?.toString();
      if (mounted) {
        setState(() {
          _splashUrl = (url != null && url.isNotEmpty) ? url : null;
          _role = role;
        });
      }
    } catch (_) {}
  }

  Widget _buildBackground() {
    // User has set their own photo -> show it full-screen, dimmed.
    if (_splashUrl != null) {
      return Opacity(
        opacity: 0.3,
        child: Image.network(
          _splashUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultBackground(),
        ),
      );
    }
    // No photo yet -> show the built-in truck background, same treatment.
    return _defaultBackground();
  }

  Widget _defaultBackground() {
    return Opacity(
      opacity: 0.3,
      child: Image.asset(
        _defaultBackgroundAsset,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: Colors.black),
      ),
    );
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
                        icon: const Icon(Icons.settings, color: Colors.black),
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
                        icon: const Icon(Icons.logout, color: Colors.black),
                        tooltip: 'Sign out',
                        onPressed: () => _supabase.auth.signOut(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        const Text(
                          'TruCost',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            shadows: [Shadow(blurRadius: 10, color: Colors.white70)],
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Owner-Operator Co-Pilot',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                            shadows: [Shadow(blurRadius: 8, color: Colors.white70)],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          user?.email ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                            shadows: [Shadow(blurRadius: 8, color: Colors.white70)],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            children: [
                              _navButton(context, Icons.mic, 'Co-Pilot', const CopilotScreen(), filled: true),
                              const SizedBox(height: 8),
                              _navButton(context, Icons.balance, 'The Ugly Truth', const UglyTruthScreen(),
                                  subtitle: 'Compare the offer to your real cost'),
                              const SizedBox(height: 8),
                              _navButton(context, Icons.people, 'Contacts', const ContactsScreen()),
                              const SizedBox(height: 8),
                              _navButton(context, Icons.document_scanner, 'Scan Documents', const ReceiptCaptureScreen(),
                                  subtitle: 'Receipts \u00b7 BOL \u00b7 POD \u00b7 Rate Cons \u00b7 Permits'),
                              const SizedBox(height: 8),
                              _navButton(context, Icons.calculate, 'I Know My Miles', const CalculatorScreen()),
                              const SizedBox(height: 8),
                              _navButton(context, Icons.post_add, 'Quote a Load', const QuoteScreen()),
                              const SizedBox(height: 8),
                              _navButton(context, Icons.bookmark, 'Saved Trips', const SavedTripsScreen()),
                              const SizedBox(height: 8),
                              _navButton(context, Icons.fact_check, 'Trip Sheet', const TripSheetScreen()),
                              const SizedBox(height: 8),
                              _navButton(context, Icons.folder_open, 'View Documents', const DocumentViewerScreen()),
                              const SizedBox(height: 8),
                              _navButton(context, Icons.tune, 'Setup', const SettingsScreen()),
                              const SizedBox(height: 8),
                              _navButton(context, Icons.info_outline, 'About', const AboutScreen()),
                              if (_isAdmin) ...[
                                const SizedBox(height: 8),
                                _navButton(context, Icons.admin_panel_settings, 'Admin', const AgentAdminScreen()),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
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

  Widget _navButton(BuildContext context, IconData icon, String label, Widget screen, {bool filled = false, String? subtitle}) {
    Future<void> go() async {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
      if (mounted) _loadSplash(); // pick up a home photo changed in Settings
    }
    final Widget labelWidget = subtitle == null
        ? Text(label, style: const TextStyle(fontSize: 18))
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 18)),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 11,
                      color: filled ? Colors.blueGrey[400] : Colors.black87)),
            ],
          );
    return SizedBox(
      width: double.infinity,
      child: filled
          ? ElevatedButton.icon(
              onPressed: go,
              icon: Icon(icon, size: 24),
              label: labelWidget,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: Colors.white,
                foregroundColor: Colors.blueGrey[800],
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          : OutlinedButton.icon(
              onPressed: go,
              icon: Icon(icon, size: 24),
              label: labelWidget,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.black, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
    );
  }
}
