import 'dart:math';
import 'package:flutter/material.dart';

/// Dart port of the iOS QuoteManager. Single source of truth for quotes.
/// Add new quotes to [QuoteLibrary.all] and they flow everywhere.
///
/// Goes in: lib/about/quotes.dart

// Shared brand colors used across the About / Developer / Quotes screens.
const Color kBrandGreen = Color(0xFF2E6E3A);
const Color kBrandGreenDark = Color(0xFF1E4D27);
const Color kMoffittCrimson = Color(0xFFBF1A4D);
const Color kMoffittCrimsonDark = Color(0xFF8C0D33);

enum QuoteCategory { trucking, inspiration, business, spiritual }

extension QuoteCategoryInfo on QuoteCategory {
  String get label {
    switch (this) {
      case QuoteCategory.trucking:
        return 'Trucking';
      case QuoteCategory.inspiration:
        return 'Inspiration';
      case QuoteCategory.business:
        return 'Business';
      case QuoteCategory.spiritual:
        return 'Spiritual';
    }
  }

  IconData get icon {
    switch (this) {
      case QuoteCategory.trucking:
        return Icons.local_shipping;
      case QuoteCategory.inspiration:
        return Icons.bolt;
      case QuoteCategory.business:
        return Icons.trending_up;
      case QuoteCategory.spiritual:
        return Icons.auto_awesome;
    }
  }
}

class TruCostQuote {
  final String text;
  final String? attribution;
  final QuoteCategory category;
  final String? story;
  const TruCostQuote(this.text,
      {this.attribution, required this.category, this.story});

  String get shareText =>
      attribution != null ? '"$text"\n— $attribution' : '"$text"';
}

class QuoteLibrary {
  static final _rand = Random();

  static const List<TruCostQuote> all = [
    // ── TRUCKING — industry veterans & TruCost originals ──
    TruCostQuote(
      "I would rather give the guys a day off than lose money and wear out my equipment and men.",
      attribution: "Mark Edwards, Edwards Moving & Rigging",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "Watch your pennies and the dollars will follow.",
      attribution: "John Vaughan, President, Buchanan Hauling & Rigging — Ft. Wayne, IN",
      category: QuoteCategory.trucking,
      story:
          "Ten years ago at Edwards Moving & Rigging, I walked into John "
          "Vaughan's office — he was VP of Finance then — and caught him "
          "carefully peeling the stamp off a piece of mail so he could use it "
          "again. I asked what in the world he was doing. He looked up and "
          "said, \"Kyle, watch your pennies and the dollars will follow.\" "
          "He's the President of Buchanan Hauling in Ft. Wayne, Indiana now, "
          "but that morning — watching the man save a single stamp — taught me "
          "more about running a business than any spreadsheet could. It's the "
          "whole idea behind TruCost: the small leaks are where the ship goes "
          "down.",
    ),
    TruCostQuote(
      "Everyone has to eat. No matter how good you are, everyone will get some of your business. That is fair and that is life.",
      attribution: "Mark Edwards, Edwards Moving & Rigging",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "Fair and consistent pricing protects you and the whole industry.",
      attribution: "John Vaughan, President, Buchanan Hauling & Rigging — Ft. Wayne, IN",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "Know your number before you say yes.",
      attribution: "TruCost",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "\$4 a mile sounds better than \$11 an hour. Until you do the math.",
      attribution: "TruCost",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "Built for the guy whose office is his cab.",
      attribution: "TruCost",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "Every cheap load you take teaches brokers you'll take cheap loads.",
      attribution: "TruCost",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "When enough drivers say no, the rate has to go up.",
      attribution: "TruCost",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "The truck doesn't care if you're profitable. The payment is due either way.",
      attribution: "TruCost",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "Deadhead miles aren't free. Your truck doesn't know the difference.",
      attribution: "TruCost",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "The load you say no to might be the one that saves your business.",
      attribution: "TruCost",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "Three hours waiting to unload is three hours you're paying for. Count them.",
      attribution: "TruCost",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "The road doesn't care about your excuses. Neither does the payment book.",
      attribution: "TruCost",
      category: QuoteCategory.trucking,
    ),
    TruCostQuote(
      "A truck sitting still is losing money. A truck running cheap is losing more.",
      attribution: "TruCost",
      category: QuoteCategory.trucking,
    ),

    // ── INSPIRATION ──
    TruCostQuote(
      "It does not matter how slowly you go as long as you do not stop.",
      attribution: "Confucius",
      category: QuoteCategory.inspiration,
    ),
    TruCostQuote(
      "Success is not final, failure is not fatal: it is the courage to continue that counts.",
      attribution: "Winston Churchill",
      category: QuoteCategory.inspiration,
    ),
    TruCostQuote(
      "The harder the battle, the sweeter the victory.",
      attribution: "Les Brown",
      category: QuoteCategory.inspiration,
    ),
    TruCostQuote(
      "You don't have to be great to start, but you have to start to be great.",
      attribution: "Zig Ziglar",
      category: QuoteCategory.inspiration,
    ),
    TruCostQuote(
      "Obstacles are those frightful things you see when you take your eyes off your goal.",
      attribution: "Henry Ford",
      category: QuoteCategory.inspiration,
    ),
    TruCostQuote(
      "The man who moves a mountain begins by carrying away small stones.",
      attribution: "Confucius",
      category: QuoteCategory.inspiration,
    ),
    TruCostQuote(
      "Don't watch the clock; do what it does. Keep going.",
      attribution: "Sam Levenson",
      category: QuoteCategory.inspiration,
    ),
    TruCostQuote(
      "Believe you can and you're halfway there.",
      attribution: "Theodore Roosevelt",
      category: QuoteCategory.inspiration,
    ),

    // ── BUSINESS ──
    TruCostQuote(
      "Price is what you pay. Value is what you get.",
      attribution: "Warren Buffett",
      category: QuoteCategory.business,
    ),
    TruCostQuote(
      "Beware of little expenses. A small leak will sink a great ship.",
      attribution: "Benjamin Franklin",
      category: QuoteCategory.business,
    ),
    TruCostQuote(
      "An investment in knowledge pays the best interest.",
      attribution: "Benjamin Franklin",
      category: QuoteCategory.business,
    ),
    TruCostQuote(
      "It's not what you make, it's what you keep.",
      category: QuoteCategory.business,
    ),
    TruCostQuote(
      "The man who knows his costs is never surprised by his losses.",
      category: QuoteCategory.business,
    ),
    TruCostQuote(
      "You can make more friends in two months by becoming interested in other people than you can in two years by trying to get other people interested in you.",
      attribution: "Dale Carnegie",
      category: QuoteCategory.business,
    ),
    TruCostQuote(
      "When dealing with people, remember you are not dealing with creatures of logic, but creatures of emotion.",
      attribution: "Dale Carnegie",
      category: QuoteCategory.business,
    ),
    TruCostQuote(
      "Any fool can criticize, condemn, and complain — and most fools do. But it takes character and self-control to be understanding and forgiving.",
      attribution: "Dale Carnegie",
      category: QuoteCategory.business,
    ),
    TruCostQuote(
      "Talk to someone about themselves and they'll listen for hours.",
      attribution: "Dale Carnegie",
      category: QuoteCategory.business,
    ),
    TruCostQuote(
      "The successful man will profit from his mistakes and try again in a different way.",
      attribution: "Dale Carnegie",
      category: QuoteCategory.business,
    ),
    TruCostQuote(
      "Rule No. 1: Never lose money. Rule No. 2: Never forget Rule No. 1.",
      attribution: "Warren Buffett",
      category: QuoteCategory.business,
    ),
    TruCostQuote(
      "It takes 20 years to build a reputation and five minutes to ruin it.",
      attribution: "Warren Buffett",
      category: QuoteCategory.business,
    ),

    // ── SPIRITUAL ──
    TruCostQuote(
      "I can do all things through Christ who strengthens me.",
      attribution: "Philippians 4:13",
      category: QuoteCategory.spiritual,
    ),
    TruCostQuote(
      "Trust in the Lord with all your heart and lean not on your own understanding.",
      attribution: "Proverbs 3:5",
      category: QuoteCategory.spiritual,
    ),
    TruCostQuote(
      "For I know the plans I have for you — plans to prosper you and not to harm you, plans to give you hope and a future.",
      attribution: "Jeremiah 29:11",
      category: QuoteCategory.spiritual,
    ),
    TruCostQuote(
      "Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you wherever you go.",
      attribution: "Joshua 1:9",
      category: QuoteCategory.spiritual,
    ),
    TruCostQuote(
      "Give thanks in all circumstances; for this is God's will for you.",
      attribution: "1 Thessalonians 5:18",
      category: QuoteCategory.spiritual,
    ),
    TruCostQuote(
      "The Lord is my shepherd; I shall not want.",
      attribution: "Psalm 23:1",
      category: QuoteCategory.spiritual,
    ),
    TruCostQuote(
      "Faith is taking the first step even when you don't see the whole staircase.",
      attribution: "Martin Luther King Jr.",
      category: QuoteCategory.spiritual,
    ),
    TruCostQuote(
      "Gratitude turns what we have into enough.",
      category: QuoteCategory.spiritual,
    ),
  ];

  static List<TruCostQuote> forCategory(QuoteCategory c) =>
      all.where((q) => q.category == c).toList();

  static TruCostQuote random() => all[_rand.nextInt(all.length)];

  static TruCostQuote randomIn(QuoteCategory c) {
    final f = forCategory(c);
    if (f.isEmpty) return random();
    return f[_rand.nextInt(f.length)];
  }

  // Anchor quotes used in key placements.
  static TruCostQuote get knowYourNumber => all.firstWhere(
        (q) => q.text.contains('Know your number'),
        orElse: () => all.first,
      );
}

/// Drop-in quote display. Mirrors the iOS QuoteView styles.
class QuoteView extends StatelessWidget {
  final TruCostQuote quote;
  final bool prominent;
  const QuoteView(this.quote, {super.key, this.prominent = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '"${quote.text}"',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontStyle: FontStyle.italic,
            fontSize: prominent ? 15 : 13,
            color: prominent ? kBrandGreen : Colors.grey[700],
            height: 1.35,
          ),
        ),
        if (quote.attribution != null) ...[
          const SizedBox(height: 4),
          Text(
            '— ${quote.attribution!}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ],
    );
  }
}

/// Shows a random quote (optionally from one category), picked once on build.
class RandomQuoteView extends StatefulWidget {
  final QuoteCategory? category;
  final bool prominent;
  const RandomQuoteView({super.key, this.category, this.prominent = false});

  @override
  State<RandomQuoteView> createState() => _RandomQuoteViewState();
}

class _RandomQuoteViewState extends State<RandomQuoteView> {
  late final TruCostQuote _quote = widget.category == null
      ? QuoteLibrary.random()
      : QuoteLibrary.randomIn(widget.category!);

  @override
  Widget build(BuildContext context) =>
      QuoteView(_quote, prominent: widget.prominent);
}
