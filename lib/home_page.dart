import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'calculator/calculator_screen.dart';
import 'route/route_screen.dart';
import 'trips/saved_trips_screen.dart';
import 'contacts/contacts_screen.dart';
import 'copilot/copilot_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _supabase = Supabase.instance.client;
  File? _rigPhoto;

  @override
  void initState() {
    super.initState();
    _loadRigPhoto();
  }

  Future<void> _loadRigPhoto() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File('${appDir.path}/rig_photo.jpg');
      if (await file.exists()) {
        setState(() => _rigPhoto = file);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_rigPhoto != null)
            Opacity(
              opacity: 0.3,
              child: Image.file(_rigPhoto!, fit: BoxFit.cover),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.blueGrey.shade800, Colors.blueGrey.shade400],
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white),
                    tooltip: 'Sign out',
                    onPressed: () => _supabase.auth.signOut(),
                  ),
                ),
                const Spacer(),
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
                      _navButton(context, Icons.people, 'Contacts', const ContactsScreen()),
                      const SizedBox(height: 12),
                      _navButton(context, Icons.mic, 'Co-Pilot', const CopilotScreen()),
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
    return SizedBox(
      width: double.infinity,
      child: filled
          ? ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
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
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
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