import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'quotes.dart';

/// "Meet the Developer" — ported from the iOS DeveloperBioSheet.
/// Career story, the personal Moffitt note, donate links, and gratitude.
///
/// Goes in: lib/about/developer_bio_screen.dart

class DeveloperBioScreen extends StatelessWidget {
  const DeveloperBioScreen({super.key});

  // Do NOT gate on canLaunchUrl. On Android 11+ it returns false for
  // https/tel/mailto unless the schemes are declared in AndroidManifest.xml,
  // which silently blocked these donate links (worked on iPhone, did nothing
  // on Android). Calling launchUrl directly fixes it — same fix as AboutScreen.
  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBrandGreen,
        foregroundColor: Colors.white,
        title: const Text('Meet the Developer'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            "TruCost wasn't built in a startup. It was built by someone who has "
            "lived the heavy haul industry for over 30 years — from the sands of "
            "Saudi Arabia to the back offices of some of the most respected "
            "rigging and transport companies in the country.",
            style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.4),
          ),
          const SizedBox(height: 18),

          _careerCard(
            icon: Icons.military_tech,
            color: kBrandGreen,
            title: "U.S. Marine Corps — Operation Desert Shield / Storm",
            subtitle: "Veteran",
            body:
                "Before there was a trucking career, there was the Corps. After "
                "completing a tour in Operation Desert Shield and Desert Storm, the "
                "discipline and attention to detail instilled by the USMC became the "
                "foundation for everything that followed. While still on active duty, a "
                "compiled Clipper application was written for McAfee Trucking — an "
                "owner-operator settlement system the owner was still running three "
                "years later.",
          ),
          _careerCard(
            icon: Icons.local_shipping,
            color: const Color(0xFF6B8E23),
            title: "McAfee Trucking — Vice President",
            subtitle: "January 1992",
            body:
                "After leaving the USMC in January 1992, a full-time role at McAfee "
                "Trucking grew into the Vice President position. The early software "
                "roots — building settlement tools that actually worked — set the tone "
                "for a career where technology and heavy haul always went hand in hand.",
          ),
          _careerCard(
            icon: Icons.build,
            color: Colors.orange,
            title: "Edwards Moving & Rigging — OTR Manager",
            subtitle: "14 Years",
            body:
                "Recruited to Edwards Moving and Rigging, where 14 years were spent "
                "managing the OTR division. Responsibilities included specifying and "
                "purchasing major heavy haul assets — including the Goldhofer THP/DL — "
                "and overseeing the build-out of the Aspen 500, a top-quality "
                "specification from the ground up. Every permit for the OTR division was "
                "ordered in-house, building deep expertise in super load routing, state "
                "regulations, and the true cost of moving ultra-heavy freight.",
          ),
          _careerCard(
            icon: Icons.memory,
            color: Colors.blue,
            title: "Supor Heavy Haul — Technology & Operations",
            subtitle: "QuickBase Innovation",
            body:
                "At Supor, the first modern programming work was built in QuickBase, "
                "giving the sales team a system to produce fast, accurate estimates and "
                "proposals. Four years of historical load data was migrated into the "
                "platform so a salesperson could query a transformer between "
                "300,000–400,000 lbs moving in PA or NJ and instantly pull matching "
                "historical records. Duplicate the record with all child records — a new "
                "proposal ready in 5 minutes instead of 5 hours. Supor was later "
                "acquired by BOSS Crane & Rigging, who replaced QuickBase with Fleet "
                "Cost & Care NEXTGEN — a system that ultimately could not handle heavy "
                "haul pricing and was eventually dropped.",
          ),
          _careerCard(
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFC9A300),
            title: "Beyel Brothers Crane — Hard Lessons",
            subtitle: "The Job That Confirmed What TruCost Needed to Fix",
            body:
                "A former Edwards colleague reached out asking for help building an "
                "estimating system. The role sounded right — until permit ordering "
                "became a full-time reality. When asking management what rates to apply "
                "to each piece of equipment, the answer was simply: \"Get as much as you "
                "can.\" No published rates. No cost structure. No overhead targets. "
                "Edwards and Supor had operated on clear published rates — roughly 50% "
                "toward direct costs, 25% to overhead, 25% to profit. Without that "
                "framework, pricing heavy haul by gut is a recipe for leaving money on "
                "the table, or worse, running freight at a loss.",
          ),

          const SizedBox(height: 4),
          _quoteBox(
            "TruCost exists because of 30+ years of watching carriers — big and "
            "small — accept loads they couldn't afford to run. The math isn't "
            "complicated. It just has to be done.",
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),

          // ── A Personal Note — Cancer & Moffitt ──
          // NOTE TO KYLE: updated July 2026 to current status — three months off
          // immunotherapy, restarting August 2026 with a confirming scan. Refresh
          // this again as her treatment plan moves forward.
          Row(
            children: [
              const Icon(Icons.favorite, color: Colors.pink, size: 22),
              const SizedBox(width: 8),
              Text('A Personal Note',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[850])),
            ],
          ),
          const SizedBox(height: 10),
          _note(
            "During the development of TruCost, life handed our family its hardest "
            "load. My wife was diagnosed with Stage 3 cancer and went through "
            "brachytherapy, external radiation, and chemotherapy. When the scans "
            "came back, the news was worse — Stage 4, spread to her lymph nodes and "
            "pelvic bone.",
          ),
          _note(
            "We turned to Moffitt Cancer Center in Tampa. What they did for her "
            "is nothing short of remarkable. Scan after scan into immunotherapy, "
            "there is nothing. Not a trace — the cancer is gone from every scan.",
          ),
          _note(
            "Her doctors were confident enough to give her three months off "
            "immunotherapy. She starts back in August 2026 with a scan to make "
            "sure nothing has changed over those three months. If she's still "
            "clear, she'll continue immunotherapy for another one to two years.",
          ),
          _note(
            "If this app has brought you value, please consider honoring her fight "
            "with a donation to Moffitt. They gave us our future back.",
          ),
          const SizedBox(height: 14),

          _moffittButton(),
          const SizedBox(height: 10),
          _acsButton(),
          const SizedBox(height: 8),
          Center(
            child: Text(
              "Tapping either link opens your browser. TruCost receives nothing — "
              "100% goes directly to the organization.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),

          // ── With Gratitude ──
          Center(
            child: Column(
              children: [
                Icon(Icons.star, size: 28, color: kBrandGreen.withOpacity(0.8)),
                const SizedBox(height: 6),
                const Text('With Gratitude',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  "None of this exists without the people who believed in me, stood "
                  "beside me, and never let me quit.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _gratitude(Icons.favorite, Colors.pink, "Gertrude",
              "My wife. My strength. My reason."),
          _gratitude(Icons.auto_awesome, kBrandGreen, "Kyla, Cody, Aljean & Jose",
              "My children — everything I do is for you."),
          _gratitude(Icons.shield, Colors.orange, "Tessa",
              "My sister. A rock in every storm."),
          _gratitude(Icons.directions_walk, Colors.blue, "Josh",
              "One of the hardest working people I know."),
          const SizedBox(height: 10),
          Center(
            child: Text(
              "I love all of you. Thank you for the years of support.",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _careerCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String body,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kBrandGreen.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey[700], height: 1.4)),
        ],
      ),
    );
  }

  Widget _quoteBox(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kBrandGreen.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBrandGreen.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote, color: kBrandGreen.withOpacity(0.5), size: 26),
          const SizedBox(height: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[700],
                  height: 1.4)),
        ],
      ),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: TextStyle(
                fontSize: 13, color: Colors.grey[700], height: 1.45)),
      );

  Widget _moffittButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _open('https://fundraise.moffitt.org/campaign/760949/donate?c_src=mainyellowbutton'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [kMoffittCrimson, kMoffittCrimsonDark],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.pink.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.favorite, color: Colors.white),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Donate to Moffitt Cancer Center',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  Text('moffitt.org — Tampa, Florida',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.north_east, color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _acsButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open('https://www.cancer.org/involved/donate.html'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.pink.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.pink.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_hospital, color: Colors.pink, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('American Cancer Society',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  Text('Support cancer research nationwide',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            Icon(Icons.north_east, color: Colors.grey[400], size: 16),
          ],
        ),
      ),
    );
  }

  Widget _gratitude(IconData icon, Color color, String name, String role) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                Text(role,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
