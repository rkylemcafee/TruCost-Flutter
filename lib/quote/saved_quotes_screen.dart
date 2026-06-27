// lib/quote/saved_quotes_screen.dart
//
// Quote report — every load you've put a number on. Defaults to newest first;
// re-sort by gross, by take-home per hour, or grouped by contact. Take-home
// per hour is derived from what's stored on each quote, so it works on quotes
// saved before this screen existed too.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum QuoteSort { recent, gross, hourly, contact }

class SavedQuotesScreen extends StatefulWidget {
  const SavedQuotesScreen({super.key});

  @override
  State<SavedQuotesScreen> createState() => _SavedQuotesScreenState();
}

class _SavedQuotesScreenState extends State<SavedQuotesScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _quotes = [];
  Map<String, String> _contactNames = {};
  QuoteSort _sort = QuoteSort.recent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final rows = await _supabase
          .from('trips')
          .select()
          .eq('user_id', user.id)
          .eq('stage', 'quote')
          .order('created_at', ascending: false);
      final quotes = List<Map<String, dynamic>>.from(rows);

      // Resolve contact names (best-effort; never blocks the report).
      final names = <String, String>{};
      try {
        final cs = await _supabase
            .from('contacts')
            .select('id, name, company')
            .eq('user_id', user.id);
        for (final c in (cs as List)) {
          final id = c['id']?.toString();
          if (id == null) continue;
          final nm = (c['name'] ?? '').toString().trim();
          final co = (c['company'] ?? '').toString().trim();
          names[id] = (co.isNotEmpty && nm.isNotEmpty)
              ? '$nm ($co)'
              : nm.isNotEmpty
                  ? nm
                  : co;
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _quotes = quotes;
          _contactNames = names;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading quotes: $e')),
        );
      }
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _supabase.from('trips').delete().eq('id', id);
      if (mounted) {
        setState(() => _quotes.removeWhere((q) => q['id'].toString() == id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete quote?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) _delete(id);
  }

  // ── helpers ──

  double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _usd(double v) => '\$${v.toStringAsFixed(2)}';

  Map? _est(Map q) {
    final e = q['estimate_json'];
    if (e is Map) return e;
    if (e is String && e.isNotEmpty) {
      try {
        return json.decode(e) as Map;
      } catch (_) {}
    }
    return null;
  }

  /// Take-home per hour at the quoted gross:
  /// (gross after carrier cut − costs) / trip hours.
  /// Carrier cut and total cost now live in estimate_json (the trips table
  /// keeps carrier_cut_pct_at_time as a column too; we read either).
  double _hourlyOf(Map q) {
    final est = _est(q);
    final gross = _d(q['quoted_gross']);
    final cutPct = q['carrier_cut_pct_at_time'] != null
        ? _d(q['carrier_cut_pct_at_time'])
        : _d(est?['carrierCutPct']);
    final cut = cutPct / 100;
    final cost = _d(est?['totalCost'] ?? est?['totalCosts']);
    final hours = _d(est?['totalHours']);
    if (hours <= 0) return 0;
    return (gross * (1 - cut) - cost) / hours;
  }

  String _contactNameOf(Map q) {
    final id = q['contact_id']?.toString();
    if (id == null || id.isEmpty) return '';
    return _contactNames[id] ?? '';
  }

  List<Map<String, dynamic>> get _sorted {
    final list = [..._quotes];
    switch (_sort) {
      case QuoteSort.recent:
        list.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
        break;
      case QuoteSort.gross:
        list.sort((a, b) => _d(b['quoted_gross']).compareTo(_d(a['quoted_gross'])));
        break;
      case QuoteSort.hourly:
        list.sort((a, b) => _hourlyOf(b).compareTo(_hourlyOf(a)));
        break;
      case QuoteSort.contact:
        list.sort((a, b) {
          final an = _contactNameOf(a).toLowerCase();
          final bn = _contactNameOf(b).toLowerCase();
          if (an.isEmpty && bn.isEmpty) return 0;
          if (an.isEmpty) return 1; // no-contact quotes fall to the bottom
          if (bn.isEmpty) return -1;
          final c = an.compareTo(bn);
          if (c != 0) return c;
          return (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString());
        });
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final list = _sorted;
    final count = list.length;
    final totalGross = list.fold<double>(0, (s, q) => s + _d(q['quoted_gross']));
    final hrVals = list.map(_hourlyOf).where((h) => h > 0).toList();
    final avgHr = hrVals.isEmpty ? 0.0 : hrVals.reduce((a, b) => a + b) / hrVals.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Quote Report')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _quotes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No quotes yet.\nQuote a load and save it to see it here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Row(
                        children: [
                          _sortChip('Recent', QuoteSort.recent),
                          const SizedBox(width: 8),
                          _sortChip('Gross \$', QuoteSort.gross),
                          const SizedBox(width: 8),
                          _sortChip('\$/hr', QuoteSort.hourly),
                          const SizedBox(width: 8),
                          _sortChip('Contact', QuoteSort.contact),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$count quote${count == 1 ? '' : 's'}  ·  ${_usd(totalGross)} quoted'
                          '${avgHr > 0 ? '  ·  ${_usd(avgHr)}/hr avg' : ''}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _card(list[i]),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _sortChip(String label, QuoteSort sort) {
    final selected = _sort == sort;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _sort = sort),
      selectedColor: Colors.blueGrey[100],
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        color: selected ? Colors.blueGrey[900] : Colors.grey[700],
      ),
    );
  }

  Widget _card(Map<String, dynamic> q) {
    final id = q['id'].toString();
    final name = (q['trip_name'] ?? '').toString();
    final origin = (q['origin'] ?? '').toString();
    final dest = (q['destination'] ?? '').toString();
    final route = (origin.isNotEmpty && dest.isNotEmpty)
        ? '$origin → $dest'
        : (name.isNotEmpty ? name : 'Quote');
    final contact = _contactNameOf(q);
    final quoted = _d(q['quoted_gross']);
    final perLoaded = _d(_est(q)?['quotedPerLoadedMile']);
    final totalMiles = _d(q['total_miles']);
    final hourly = _hourlyOf(q);
    final date = (q['trip_date'] ?? '').toString();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(route, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                if (contact.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.person, size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(contact,
                            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${_usd(perLoaded)}/loaded mi  ·  ${totalMiles.round()} mi  ·  $date',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_usd(quoted),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.green[800])),
              if (hourly > 0)
                Text('${_usd(hourly)}/hr', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => _confirmDelete(id),
                child: Icon(Icons.delete_outline, size: 18, color: Colors.grey[400]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
