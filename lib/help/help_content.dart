import 'package:flutter/material.dart';

/// SINGLE SOURCE OF TRUTH for in-app help.
///
/// Everything reads from [kHelpTopics]:
///   • the "?" button on each screen  -> HelpButton + showHelpSheet (filtered)
///   • the general Help page          -> HelpIndexScreen (all topics)
///   • Evan (the AI co-pilot)         -> helpGuideForEvan() blurbs, appended to
///                                       the co-pilot context the app already sends
///
/// Write a topic once here; all three update. Add a topic = add to the list.

class HelpTopic {
  final String screen; // which screen's "?" shows it (see HelpScreens)
  final String title; // short heading
  final String blurb; // one-liner — used by the index and by Evan
  final String detail; // full help body — shown in the "?" sheet
  const HelpTopic({
    required this.screen,
    required this.title,
    required this.blurb,
    required this.detail,
  });
}

/// Screen keys. Use these constants on both the topic and the HelpButton so
/// they can never drift apart.
class HelpScreens {
  static const tripSheet = "trip_sheet";
  static const receipts = "receipts";
  static const documents = "documents";
  static const settings = "settings";
  static const rig = "rig";
  static const quote = "quote";
  static const fuelByState = "fuel_by_state";
  static const copilot = "copilot";
}

const List<HelpTopic> kHelpTopics = [
  // ──────────────────────────── QUOTE / ENTER TRIP ────────────────────────────
  HelpTopic(
    screen: HelpScreens.quote,
    title: "Pricing a load",
    blurb:
        "Enter the load's gross and route; it runs your real costs and tells you TAKE IT or PASS on your target hourly.",
    detail:
        "Quoting runs the numbers before you commit. Put in the gross the broker is offering and the route "
        "(or the miles), and the app figures your real cost to run it — fuel at today's prices, your truck "
        "cost, overhead, and the wage you want to clear — then tells you TAKE IT or PASS.\n\n"
        "The number that matters is your effective dollars-per-hour. Clear your target and it's a winner; "
        "fall short and the app shows the minimum gross you'd need to hit your target, so you know exactly "
        "what to counter with.",
  ),
  HelpTopic(
    screen: HelpScreens.quote,
    title: "Why it says PASS",
    blurb:
        "TAKE IT or PASS is whether the load clears your target hourly after all your real costs — not whether the gross looks big.",
    detail:
        "A big gross can still be a loser. The verdict is based on your effective hourly after fuel, truck, "
        "overhead, and your target wage — so a long cheap haul can pass while a short tight one wins.\n\n"
        "When it says PASS, it also shows the minimum gross to make it work at your target rate. That is "
        "your negotiating number — what to ask the broker for.",
  ),
  HelpTopic(
    screen: HelpScreens.quote,
    title: "Net to you vs your settlement check",
    blurb:
        "Net to you is your real profit after your own costs — different from the settlement check the carrier cuts you.",
    detail:
        "Net to you is your real take-home after everything you actually pay — fuel, truck, overhead, your "
        "wage. It is your decision number: is this load worth your time?\n\n"
        "That is different from the settlement check on the trip sheet, which is just your share of the "
        "gross plus reimbursables minus what the carrier fronted. The check can look fine while the real "
        "profit is thin — that gap is the whole reason to run the numbers.",
  ),

  // ──────────────────────────── TRIP SHEET ────────────────────────────
  HelpTopic(
    screen: HelpScreens.tripSheet,
    title: "Making a trip sheet",
    blurb:
        "You don't fill it out by hand — open Trip Sheet, pick the load, and it builds itself from the saved load. Log receipts, then Share.",
    detail:
        "You don't fill a trip sheet out by hand. Open Trip Sheet, pick the load from the dropdown at the "
        "top, and it builds itself from everything saved for that load — authority, route, miles, "
        "settlement, and fuel.\n\n"
        "Log any receipts and mark which ones are reimbursable so the expected check is right, then tap "
        "Share to send the PDF packet to your carrier.",
  ),
  HelpTopic(
    screen: HelpScreens.tripSheet,
    title: "Your expected check",
    blurb:
        "Settlement shows your expected check: your share of the gross, plus reimbursables, minus anything the carrier fronted.",
    detail:
        "The SETTLEMENT card is what the carrier should pay you for this load.\n\n"
        "It starts with the load gross, takes your share after the carrier's cut, adds any reimbursable "
        "expenses, then subtracts anything the carrier already covered for you — fuel bought on their card "
        "and cash advances. The green EXPECTED CHECK is the bottom line.\n\n"
        "It's an estimate before carrier-specific deductions like fuel tax, insurance, or trailer rent, so "
        "always reconcile it against the real settlement statement.",
  ),
  HelpTopic(
    screen: HelpScreens.tripSheet,
    title: "Why fuel and advances lower your check",
    blurb:
        "Carrier-card fuel and cash advances are money the carrier fronted, so they come back out of your settlement.",
    detail:
        "If the carrier paid for something up front, they take it back out of your check.\n\n"
        "Fuel on the carrier's card and cash advances both show as orange minus lines and reduce your "
        "expected check by what they fronted. Fuel you paid for yourself doesn't show here at all — that's "
        "your own cost, not the carrier's, so it never touches the settlement.\n\n"
        "Rule of thumb: if a cash advance paid for fuel, log the advance and leave that fuel receipt as "
        "cash-paid. Marking both would double-count.",
  ),
  HelpTopic(
    screen: HelpScreens.tripSheet,
    title: "Reimbursable vs your cost",
    blurb:
        "Reimbursables (lumpers, scales, tolls) add to your check; fuel is the exception — it's your cost.",
    detail:
        "A reimbursable is something the carrier pays you back for — lumpers, scale tickets, tolls, a "
        "permit. Those add to your expected check.\n\n"
        "Fuel is the exception: it's your cost of running the truck, kept for taxes, not billed back, so it "
        "defaults to non-reimbursable. You can flip any receipt's reimbursable switch when you log it.",
  ),
  HelpTopic(
    screen: HelpScreens.tripSheet,
    title: "Estimated gallons by state",
    blurb:
        "Splits your expected burn across the route's states to guide where to buy fuel for IFTA.",
    detail:
        "This spreads your expected fuel burn across the states the route runs through, so you can buy "
        "roughly that many gallons in each state and keep your IFTA bill even.\n\n"
        "It's an estimate — it spreads by miles, which assumes even MPG, so a heavy loaded stretch actually "
        "burns a bit more than shown and an empty deadhead a bit less. Close enough to know where to fill, "
        "not penny-exact.",
  ),
  HelpTopic(
    screen: HelpScreens.tripSheet,
    title: "Sharing the trip sheet",
    blurb:
        "The share button makes a PDF; you can attach the load's receipts and documents as image pages.",
    detail:
        "The share icon builds a PDF of this sheet and opens your phone's share options — email, text, "
        "AirDrop, or Save to Files.\n\n"
        "If the load has documents, it asks whether to attach them. Attach docs adds each receipt, BOL, "
        "POD, and slip as its own page after the summary. Only documents still in the cloud attach; older "
        "ones that aged out to your phone stay listed but aren't pulled in.\n\n"
        "The shared PDF leaves off your private profit numbers — it's the packet you hand a carrier or "
        "broker, not your decision math.",
  ),

  // ──────────────────────────── RECEIPTS / SCAN ────────────────────────────
  HelpTopic(
    screen: HelpScreens.receipts,
    title: "Scanning a receipt",
    blurb:
        "Snap a receipt and it reads the vendor, amount, and category; check it, attach it to a load, and save.",
    detail:
        "Tap Scan Documents and take a photo of the receipt. The app reads the vendor, date, amount, and "
        "category for you — crop it first for a cleaner read. Check what it pulled, pick the load it "
        "belongs to, and save.\n\n"
        "No receipt in hand? Use Enter manually and just type the amount.",
  ),
  HelpTopic(
    screen: HelpScreens.receipts,
    title: "Fuel receipts — gallons and the carrier card",
    blurb:
        "On fuel receipts, log the gallons (feeds your MPG) and mark if it was on the carrier's card (deducted from settlement).",
    detail:
        "On a fuel receipt, enter the gallons — that's what powers your actual MPG and the per-state fuel "
        "numbers.\n\n"
        "If you bought it on the carrier's fuel card, flip On carrier fuel card so it comes off your "
        "settlement. Leave it off if you paid yourself — that's your cost, not the carrier's. Fuel defaults "
        "to non-reimbursable since it's an operating cost.",
  ),
  HelpTopic(
    screen: HelpScreens.receipts,
    title: "Reimbursable or your cost",
    blurb:
        "Reimbursable receipts add to your check; flip the switch off for your own costs. Fuel is off by default.",
    detail:
        "Every receipt has a Reimbursable switch. On means the carrier pays you back and it adds to your "
        "expected check — lumpers, scales, tolls, permits. Off means it's your cost, kept for taxes but not "
        "billed back. Fuel defaults to off.",
  ),
  HelpTopic(
    screen: HelpScreens.receipts,
    title: "Logging a cash advance",
    blurb:
        "Use 'Log a cash advance' to record carrier-fronted cash; it's deducted from your settlement.",
    detail:
        "If the carrier fronted you cash (a Comdata advance), tap Log a cash advance on the Scan screen, "
        "enter the amount, pick the load, and save — photograph the slip if you have it. It shows on that "
        "load's trip sheet as a deduction from your check.\n\n"
        "If a cash advance paid for fuel, log the advance and leave that fuel receipt as cash-paid, or it "
        "will double-count against your settlement.",
  ),

  // ──────────────────────────── DOCUMENTS ────────────────────────────
  HelpTopic(
    screen: HelpScreens.documents,
    title: "Where your documents live",
    blurb:
        "Photos save to your phone permanently; the cloud keeps images for your 3 most-recent documented loads.",
    detail:
        "Every document and receipt you snap saves to your phone first — that's your permanent copy, in "
        "Files under TruCost and in a TruCost photo album.\n\n"
        "The cloud keeps the images only for your three most-recently-documented loads, then ages older "
        "ones off to save space. Your numbers and records stay forever; only the images roll off the cloud, "
        "and they're still right there on your phone.",
  ),
  HelpTopic(
    screen: HelpScreens.documents,
    title: "Viewing and attaching documents",
    blurb:
        "View Documents browses everything by type or load; the trip sheet can attach the cloud ones to its PDF.",
    detail:
        "View Documents lets you browse everything you've captured, filtered by type or by load. Tap one to "
        "see it full screen.\n\n"
        "When you share a trip sheet, it can attach the load's documents that are still in the cloud as "
        "pages in the PDF — older phone-only ones stay listed but aren't pulled in.",
  ),

  // ──────────────────────────── YOUR RIG ────────────────────────────
  HelpTopic(
    screen: HelpScreens.rig,
    title: "Your trucks and trailers",
    blurb:
        "Add each truck and trailer with its cost; the active truck drives your quotes and trip sheets.",
    detail:
        "Add your trucks and trailers under the Rig tab. For each, set whether it's owned — with its value "
        "and depreciation — or financed, with the monthly payment. That's what feeds the equipment cost in "
        "every quote.\n\n"
        "The active truck is the one your quotes and trip sheets use.",
  ),
  HelpTopic(
    screen: HelpScreens.rig,
    title: "MPG and speed live on the truck",
    blurb:
        "Set empty/loaded MPG and road speed on the truck — they drive your fuel cost and your hours.",
    detail:
        "Each truck holds its empty and loaded MPG and its empty and loaded road speed. MPG drives your "
        "fuel cost and your actual-MPG checks; speed drives how long a run takes, which sets your "
        "dollars-per-hour.\n\n"
        "Edit them in Edit Truck — they no longer live on the Settings screen, so the truck is the single "
        "place that controls how your rig runs.",
  ),

  // ──────────────────────────── SETTINGS ────────────────────────────
  HelpTopic(
    screen: HelpScreens.settings,
    title: "Your deal — carrier cut and overhead",
    blurb:
        "Set your carrier cut and overhead under Business; they shape every quote and your settlement share.",
    detail:
        "Under Settings, the Business tab holds your deal. Carrier cut is the percentage the carrier keeps; "
        "overhead is your fixed business cost as a percent. Both feed every quote and your settlement "
        "share. Change carriers or your costs shift? Update it here.",
  ),
  HelpTopic(
    screen: HelpScreens.settings,
    title: "Carrier fuel card default",
    blurb:
        "Set whether you run a carrier fuel card; new fuel receipts default to it, and you can override per receipt.",
    detail:
        "If you run a carrier fuel card or take fuel advances, turn on Carrier fuel card in the Business "
        "tab. New fuel receipts will default to being on the card — deducted from settlement — and you can "
        "flip any single one off when you pay cash for a discount.",
  ),
  HelpTopic(
    screen: HelpScreens.settings,
    title: "Your authority",
    blurb:
        "Operator name, MC, DOT, and who you're leased to print on your trip sheet — set them under Preferences.",
    detail:
        "Your authority — operator name, MC number, DOT number, and who you're leased to — fills the top of "
        "every trip sheet. Set it under Settings, in the Preferences tab, so every sheet you hand in is "
        "stamped right.",
  ),
  HelpTopic(
    screen: HelpScreens.settings,
    title: "Target hourly and work hours",
    blurb:
        "Your target hourly rate and annual work hours set the bar a load has to clear to be a winner.",
    detail:
        "Your target hourly rate is the wage you want to clear; annual working hours spreads your fixed "
        "costs across the year. Together they set the bar a load has to beat to come back TAKE IT.\n\n"
        "Set your rate in Preferences and your annual hours in Business.",
  ),

  // ──────────────────────────── FUEL BY STATE ────────────────────────────
  HelpTopic(
    screen: HelpScreens.fuelByState,
    title: "Buying fuel by state for IFTA",
    blurb:
        "Shows roughly how many gallons to buy in each state on your route to keep your IFTA bill even.",
    detail:
        "Fuel by State estimates how many gallons you'll burn in each state on the route, so you can buy "
        "about that much in each one and keep your IFTA reconciliation even instead of owing a pile at the "
        "end of the quarter.\n\n"
        "It's an estimate spread across the miles, so treat it as a buying guide, not exact to the gallon.",
  ),

  // ──────────────────────────── USING EVAN ────────────────────────────
  HelpTopic(
    screen: HelpScreens.copilot,
    title: "What your co-pilot can do",
    blurb:
        "Ask to price a load, save it, pull up past loads, manage your rig, or call/text/email a broker — by voice.",
    detail:
        "Your co-pilot is your dispatcher. Tell it a load — the gross and where to where — and it'll price "
        "it, tell you TAKE IT or PASS, and save it if you want.\n\n"
        "It can pull up loads you've run, manage your trucks and trailers, work out fuel by state, and "
        "call, text, or email a broker from your contacts. Just talk to it like you would a person.",
  ),
  HelpTopic(
    screen: HelpScreens.copilot,
    title: "It remembers your loads and notes",
    blurb:
        "Your co-pilot knows your saved loads, rig, and contacts, and remembers notes like gate codes when you tell it.",
    detail:
        "Your co-pilot has your saved loads, your rig, and your contacts in front of it, so you can ask "
        "about a run by where it went or who the broker was.\n\n"
        "Tell it something to remember — a gate code, a lumper detail, a note on a load — and it keeps it "
        "with that load and brings it back when you need it.",
  ),
];

/// Topics for one screen (for the "?" sheet).
List<HelpTopic> helpForScreen(String screen) =>
    kHelpTopics.where((t) => t.screen == screen).toList();

/// Compact app guide for Evan — title + blurb per topic. Append this to the
/// co-pilot context the app already sends so Evan is taught from the same
/// source as the help screens, without copying text into the edge function.
String helpGuideForEvan() {
  final b = StringBuffer();
  b.writeln("APP GUIDE (how TruCost works — use this to guide the driver):");
  for (final t in kHelpTopics) {
    b.writeln("- ${t.title}: ${t.blurb}");
  }
  return b.toString();
}

// ─────────────────────────────  UI  ─────────────────────────────

/// The "?" icon. Drop `const HelpButton(HelpScreens.tripSheet)` into any
/// AppBar's actions (or anywhere) and it opens help for that screen.
class HelpButton extends StatelessWidget {
  final String screen;
  const HelpButton(this.screen, {super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.help_outline),
      tooltip: "Help",
      onPressed: () => showHelpSheet(context, screen),
    );
  }
}

Future<void> showHelpSheet(BuildContext context, String screen) {
  final topics = helpForScreen(screen);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          const Text("Help", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (topics.isEmpty)
            const Text("No help for this screen yet.", style: TextStyle(color: Colors.grey))
          else
            for (final t in topics) ...[
              Text(t.title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey[800])),
              const SizedBox(height: 4),
              Text(t.detail, style: const TextStyle(fontSize: 13, height: 1.45)),
              const SizedBox(height: 20),
            ],
        ],
      ),
    ),
  );
}

/// The general Help page — every topic, grouped by screen. Reachable from a
/// Help menu entry (wire it in wherever you like, e.g. Settings or Home).
class HelpIndexScreen extends StatelessWidget {
  const HelpIndexScreen({super.key});

  static const _screenTitles = {
    HelpScreens.quote: "Quoting a Load",
    HelpScreens.tripSheet: "Trip Sheet",
    HelpScreens.receipts: "Receipts & Scanning",
    HelpScreens.documents: "Documents",
    HelpScreens.rig: "Your Rig",
    HelpScreens.settings: "Settings",
    HelpScreens.fuelByState: "Fuel by State",
    HelpScreens.copilot: "Your Co-Pilot",
  };

  @override
  Widget build(BuildContext context) {
    final order = <String>[];
    for (final t in kHelpTopics) {
      if (!order.contains(t.screen)) order.add(t.screen);
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Help")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final s in order) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(_screenTitles[s] ?? s,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey[400])),
            ),
            for (final t in helpForScreen(s))
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  title: Text(t.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedAlignment: Alignment.centerLeft,
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.detail, style: const TextStyle(fontSize: 13, height: 1.45)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
