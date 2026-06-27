import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'quotes.dart';
import 'quotes_screen.dart';
import 'developer_bio_screen.dart';

/// About TruCost — Flutter port of AboutUsView. Leads with the 10%-to-Moffitt
/// pledge, then the developer story and quote library.
///
/// Goes in: lib/about/about_screen.dart

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // Android fix: do NOT gate on canLaunchUrl. On Android 11+ canLaunchUrl
  // returns false for https/tel/mailto unless the schemes are declared in
  // AndroidManifest.xml, which silently blocked the link (worked on iPhone,
  // did nothing on Android). Calling launchUrl directly fixes it.
  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _go(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBrandGreen,
        foregroundColor: Colors.white,
        title: const Text('About TruCost'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          const Text('About TruCost',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Realistic cost tracking for owner-operators',
              style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          const SizedBox(height: 20),

          // ── OUR PROMISE — 10% to Moffitt (the new centerpiece) ──
          // NOTE TO KYLE: tweak the pledge wording to taste — this is the
          // public-facing commitment, so make it sound exactly how you mean it.
          _promiseCard(context),

          const SizedBox(height: 16),

          _navCard(
            context,
            icon: Icons.format_quote,
            title: 'Quotes & Wisdom',
            subtitle: 'Trucking, inspiration, business, spiritual',
            onTap: () => _go(context, const QuotesScreen()),
          ),
          const SizedBox(height: 10),
          _navCard(
            context,
            icon: Icons.person,
            title: 'Meet the Developer',
            subtitle: '30+ years in heavy haul — the story behind TruCost',
            onTap: () => _go(context, const DeveloperBioScreen()),
          ),

          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 16),

          _section('What TruCost Does'),
          Text(
            'TruCost helps owner-operators find the true cost of every trip by '
            'factoring in what really comes out of the settlement:',
            style: TextStyle(color: Colors.grey[700], height: 1.4),
          ),
          const SizedBox(height: 10),
          _bullet('Fuel — empty and loaded'),
          _bullet('Driver pay and your time'),
          _bullet('Equipment depreciation and reserves'),
          _bullet('Overhead and carrier cut'),
          _bullet('Load / unload and wait time'),
          _bullet('Tolls, permits, and trip-specific costs'),

          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 16),

          _section('How It Works'),
          _step('Setup', 'Set your truck, trailer, fuel, pay, and overhead once.'),
          _step('Route a Load / Enter Trip',
              'Pull miles from addresses or enter them yourself.'),
          _step('Co-Pilot',
              'Ask hands-free — your voice assistant runs the numbers and saves the trip.'),
          _step('Saved Trips & Trip Sheets',
              'Keep a record and a clean sheet for every load.'),

          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 16),

          _section('Your Privacy'),
          // Honest summary for the account-based Flutter build (replaces the
          // iOS "stays on device / no account" text, which isn't true here).
          // NOTE TO KYLE: have this reviewed before it's your published policy.
          Text(
            'TruCost uses a secure account so your rigs, trips, and settings sync '
            'across your devices. Your data is stored on our managed cloud '
            '(Supabase) and is tied to your account. Voice features send what you '
            'say to the assistant to a server to process your request. We do not '
            'sell your data and there are no ads or third-party ad trackers in the '
            'app.',
            style: TextStyle(color: Colors.grey[700], height: 1.45, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text('Last updated: June 2026',
              style: TextStyle(fontSize: 11, color: Colors.grey[400])),

          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 16),

          _section('Contact & Support'),
          _contactRow(
            icon: Icons.email,
            title: 'Email Support',
            value: 'kyle@trucost.app',
            onTap: () => _open('mailto:kyle@trucost.app?subject=TruCost%20Support'),
          ),
          const SizedBox(height: 10),
          _contactRow(
            icon: Icons.phone,
            title: 'Call Support',
            value: '(321) 467-0491',
            onTap: () => _open('tel:3214670491'),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text('Version 1.0 (Flutter)',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Text('© 2026 TruCost',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text('Made for owner-operators, by people who understand the road.',
              style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _promiseCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kMoffittCrimson, kMoffittCrimsonDark],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.pink.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.favorite, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text('Our Promise',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'TruCost donates 10% of every dollar it earns — gross, not profit — '
            'to Moffitt Cancer Center in Tampa, Florida.',
            style: TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 8),
          const Text(
            "It's not a marketing line. Moffitt gave our family our future back, "
            "and every subscription helps give that back to someone else.",
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () =>
                _open('https://fundraise.moffitt.org/campaign/760949/donate?c_src=mainyellowbutton'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.favorite, color: kMoffittCrimson, size: 18),
                  SizedBox(width: 8),
                  Text('Donate to Moffitt directly',
                      style: TextStyle(
                          color: kMoffittCrimson,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  SizedBox(width: 6),
                  Icon(Icons.north_east, color: kMoffittCrimson, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kBrandGreen.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBrandGreen.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: kBrandGreen, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  ', style: TextStyle(color: kBrandGreen, fontSize: 15)),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: Colors.grey[700], fontSize: 14)),
            ),
          ],
        ),
      );

  Widget _step(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kBrandGreen)),
            Text(body,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey[700], height: 1.35)),
          ],
        ),
      );

  Widget _contactRow({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(icon, color: kBrandGreen, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(value,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
