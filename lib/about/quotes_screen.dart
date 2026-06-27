import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'quotes.dart';

/// Browse quotes by category. Mirrors the iOS QuotesView (now reached from
/// the About page rather than a tab).
///
/// Goes in: lib/about/quotes_screen.dart

class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  static const _cats = QuoteCategory.values;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _cats.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBrandGreen,
        foregroundColor: Colors.white,
        title: const Text('Quotes & Wisdom'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: _cats
              .map((c) => Tab(
                    icon: Icon(c.icon, size: 18),
                    text: c.label,
                  ))
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: _cats.map((c) => _categoryList(c)).toList(),
      ),
    );
  }

  Widget _categoryList(QuoteCategory c) {
    final quotes = QuoteLibrary.forCategory(c);
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: quotes.length,
      itemBuilder: (_, i) => _QuoteCard(quote: quotes[i]),
    );
  }
}

class _QuoteCard extends StatefulWidget {
  final TruCostQuote quote;
  const _QuoteCard({required this.quote});

  @override
  State<_QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<_QuoteCard> {
  bool _showStory = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.quote;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5EE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBrandGreen.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.format_quote, color: kBrandGreen.withOpacity(0.4), size: 26),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  q.text,
                  style: const TextStyle(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  q.attribution == null ? '' : '— ${q.attribution!}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.ios_share, size: 20, color: kBrandGreen),
                tooltip: 'Share',
                onPressed: () => Share.share(q.shareText),
              ),
            ],
          ),
          if (q.story != null) ...[
            Divider(height: 16, color: kBrandGreen.withOpacity(0.15)),
            InkWell(
              onTap: () => setState(() => _showStory = !_showStory),
              child: Row(
                children: [
                  Icon(_showStory ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: kBrandGreen),
                  const SizedBox(width: 4),
                  Text(
                    _showStory ? 'Hide the story' : 'The story behind it',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kBrandGreen,
                    ),
                  ),
                ],
              ),
            ),
            if (_showStory)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  q.story!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[800],
                    height: 1.5,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
