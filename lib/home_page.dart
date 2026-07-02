import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'quote/ugly_truth_screen.dart';
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
          Column(
            children: [
              // Sticky header — runs to the very top (behind the status bar) like
              // the app's other screens; its content is padded below the notch.
              // Always visible: gear, TruCost, sign-out, and the signed-in account.
              Container(
                width: double.infinity,
                color: const Color(0xFF2E7D32),
                padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
                child: Column(
                  children: [
                      Row(
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
                          const Expanded(
                            child: Text(
                              'TruCost',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout, color: Colors.white),
                            tooltip: 'Sign out',
                            onPressed: () => _supabase.auth.signOut(),
                          ),
                        ],
                      ),
                      if ((user?.email ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            user!.email!,
                            style: const TextStyle(fontSize: 13, color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
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
                ),
              ],
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
