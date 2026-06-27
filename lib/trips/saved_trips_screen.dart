import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'load_details_screen.dart';

class SavedTripsScreen extends StatefulWidget {
  const SavedTripsScreen({super.key});
  @override
  State<SavedTripsScreen> createState() => _SavedTripsScreenState();
}

enum TripSort { date, pro, gross, net, hourly }

// trips.stage drives the two views: quotes vs real (booked/won) loads.
enum StageView { all, quotes, booked }

class _SavedTripsScreenState extends State<SavedTripsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _trips = [];
  bool _loading = true;
  TripSort _sort = TripSort.date;
  StageView _view = StageView.all;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final rows = await _supabase
          .from('trips')
          .select('*, contacts(*)')
          .eq('user_id', user.id)
          .order('trip_date', ascending: false);

      setState(() {
        _trips = List<Map<String, dynamic>>.from(rows);
        _sortTrips();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading trips: $e')),
        );
      }
    }
  }

  // stage: 'quote' (default) -> 'won' / 'lost' -> 'completed'.
  String _stageOf(Map<String, dynamic> t) {
    final s = (t['stage'] ?? '').toString().toLowerCase();
    return s.isEmpty ? 'quote' : s;
  }

  bool _isReal(Map<String, dynamic> t) {
    final s = _stageOf(t);
    // booked/won/completed OR the operational status flipped to booked
    return s == 'won' || s == 'completed' || (t['status'] ?? '').toString() == 'booked';
  }

  List<Map<String, dynamic>> get _visibleTrips {
    switch (_view) {
      case StageView.all:
        return _trips;
      case StageView.quotes:
        return _trips.where((t) => !_isReal(t)).toList();
      case StageView.booked:
        return _trips.where((t) => _isReal(t)).toList();
    }
  }

  void _sortTrips() {
    switch (_sort) {
      case TripSort.date:
        _trips.sort((a, b) => (b['trip_date'] ?? '').compareTo(a['trip_date'] ?? ''));
        break;
      case TripSort.pro:
        // Biggest PRO# first; loads with no PRO# sink to the bottom so the
        // ones still needing a number are easy to spot at the end.
        _trips.sort((a, b) {
          final pa = _proSortKey(a);
          final pb = _proSortKey(b);
          return pb.compareTo(pa);
        });
        break;
      case TripSort.gross:
        _trips.sort((a, b) => _grossOf(b).compareTo(_grossOf(a)));
        break;
      case TripSort.net:
        _trips.sort((a, b) => _netOf(b).compareTo(_netOf(a)));
        break;
      case TripSort.hourly:
        _trips.sort((a, b) => _getHourly(b).compareTo(_getHourly(a)));
        break;
    }
  }

  double _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  // Read the first column that has a real value. Booked loads write the new
  // canonical columns (agreed_gross / net_to_operator / effective_hourly);
  // older quotes used gross_pay / estimated_net or stashed values in the
  // estimate JSON. This keeps the list correct across all of them.
  double _firstNum(Map<String, dynamic> trip, List<String> keys) {
    for (final k in keys) {
      final v = trip[k];
      if (v != null) {
        final n = _toNum(v);
        if (n != 0) return n;
      }
    }
    return 0;
  }

  double _grossOf(Map<String, dynamic> trip) =>
      _firstNum(trip, ['agreed_gross', 'quoted_gross', 'offer_gross', 'gross_pay']);

  double _netOf(Map<String, dynamic> trip) {
    final n = _firstNum(trip, ['net_to_operator', 'estimated_net']);
    if (n != 0) return n;
    final json = trip['estimate_json'];
    return json is Map ? _toNum(json['netToOperator']) : 0;
  }

  double _getHourly(Map<String, dynamic> trip) {
    final direct = _firstNum(trip, ['effective_hourly']);
    if (direct != 0) return direct;
    final json = trip['estimate_json'];
    if (json is Map) return _toNum(json['effectiveHourlyRate']);
    return 0;
  }

  String _usd(double v) => '\$${v.toStringAsFixed(2)}';

  // True when this load has no PRO# yet (so we can flag it for follow-up).
  bool _hasPro(Map<String, dynamic> trip) {
    final p = (trip['pro_number'] ?? '').toString().trim();
    return p.isNotEmpty;
  }

  // Sort key for PRO#: the trailing number, zero-padded wide so numeric order
  // holds. Missing PRO# returns empty string, which sorts below any real one
  // (we sort descending, so empty lands at the bottom).
  String _proSortKey(Map<String, dynamic> trip) {
    final p = (trip['pro_number'] ?? '').toString().trim();
    if (p.isEmpty) return '';
    final m = RegExp(r'(\d+)$').firstMatch(p);
    if (m == null) return p; // non-numeric — sort lexically
    return m.group(1)!.padLeft(20, '0');
  }

  String _sortLabel(TripSort s) {
    switch (s) {
      case TripSort.date: return 'Date';
      case TripSort.pro: return 'PRO #';
      case TripSort.gross: return 'Gross';
      case TripSort.net: return 'Net';
      case TripSort.hourly: return '\$/hr';
    }
  }

  String _viewLabel(StageView v) {
    switch (v) {
      case StageView.all: return 'All';
      case StageView.quotes: return 'Quotes';
      case StageView.booked: return 'Booked';
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleTrips;
    return Scaffold(
      appBar: AppBar(title: const Text('Loads')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stage view: Quotes vs Booked vs All
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.grey[100],
                  child: Row(
                    children: [
                      Text('Show: ',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      const SizedBox(width: 4),
                      ...StageView.values.map((v) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(_viewLabel(v), style: const TextStyle(fontSize: 12)),
                              selected: _view == v,
                              onSelected: (_) => setState(() => _view = v),
                              visualDensity: VisualDensity.compact,
                            ),
                          )),
                    ],
                  ),
                ),
                // Sort
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.grey[50],
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text('Sort by: ',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                        const SizedBox(width: 4),
                        ...TripSort.values.map((s) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(_sortLabel(s), style: const TextStyle(fontSize: 12)),
                                selected: _sort == s,
                                onSelected: (_) {
                                  setState(() {
                                    _sort = s;
                                    _sortTrips();
                                  });
                                },
                                visualDensity: VisualDensity.compact,
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${visible.length} ${_view == StageView.quotes ? "quote" : "load"}${visible.length != 1 ? 's' : ''}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                              _view == StageView.booked
                                  ? 'No booked loads yet.'
                                  : 'No saved loads yet.\nQuote a load and tap Save.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16, color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _loadTrips,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: visible.length,
                            itemBuilder: (ctx, i) => _buildTripCard(visible[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip) {
    final name = trip['trip_name'] ?? 'Unnamed';
    final date = trip['trip_date'] ?? '';
    final gross = _grossOf(trip);
    final net = _netOf(trip);
    final fuel = _toNum(trip['estimated_fuel_cost']);
    final miles = _toNum(trip['total_miles']);
    final hourly = _getHourly(trip);
    final origin = trip['origin'] ?? '';
    final destination = trip['destination'] ?? '';
    final isWinner = net >= 0;
    final real = _isReal(trip);
    final contact = trip['contacts'];
    final contactName = contact is Map ? (contact['name'] ?? '') : '';
    final contactCompany = contact is Map ? (contact['company'] ?? '') : '';
    final contactPhone = contact is Map ? (contact['phone'] ?? '') : '';
    final contactLine = contactName.isNotEmpty
        ? '$contactName${contactCompany.isNotEmpty ? ' — $contactCompany' : ''}'
        : '';

    final json = trip['estimate_json'];
    final costPerMile = json is Map ? _toNum(json['costPerMile']) : 0.0;
    final offerPerMile = json is Map ? _toNum(json['offerPerMile']) : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (origin.isNotEmpty && destination.isNotEmpty)
              Text('$origin → $destination',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              if (contactLine.isNotEmpty)
              Text(contactLine,
                  style: TextStyle(fontSize: 11, color: Colors.blue[600], fontWeight: FontWeight.w500)),    
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _badge(real ? 'BOOKED' : 'QUOTE', real ? Colors.green : Colors.orange),
                if (real && !_hasPro(trip)) _badge('NO PRO #', Colors.deepOrange),
                _badge(date, Colors.grey),
                _badge('${miles.round()} mi', Colors.blueGrey),
                _badge(_usd(gross), Colors.blue),
                _badge(_usd(net), isWinner ? Colors.green : Colors.red),
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                const Divider(),
                _detailRow('Gross Pay', _usd(gross)),
                _detailRow('Estimated Fuel', _usd(fuel)),
                _detailRow('Estimated Net', _usd(net),
                    valueColor: isWinner ? Colors.green : Colors.red),
                _detailRow('Effective Hourly', '${_usd(hourly)}/hr',
                    valueColor: isWinner ? Colors.green : Colors.red),
                _detailRow('Cost per Mile', '${_usd(costPerMile)}/mi'),
                _detailRow('Offer per Mile', '${_usd(offerPerMile)}/mi'),
                _detailRow('Fuel Price Used',
                    _usd(_toNum(trip['fuel_price_used']))),
                if (contactName.isNotEmpty) _detailRow('Contact', contactLine),
                if (contactPhone.isNotEmpty) _detailRow('Phone', contactPhone),
                
                _detailRow('Deadhead', '${_toNum(trip['deadhead_miles']).round()} mi'),
                _detailRow('Loaded', '${_toNum(trip['loaded_miles']).round()} mi'),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: Icon(real ? Icons.local_shipping : Icons.check_circle_outline, size: 18),
                    label: Text(real ? 'Load Details' : 'Book This Load'),
                    onPressed: () async {
                      final changed = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LoadDetailsScreen(tripId: trip['id'].toString()),
                        ),
                      );
                      if (changed == true) _loadTrips();
                    },
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    label: const Text('Delete Load', style: TextStyle(color: Colors.red)),
                    onPressed: () => _confirmAndDelete(trip),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDelete(Map<String, dynamic> trip) async {
    final id = trip['id'].toString();
    final name = (trip['trip_name'] ?? 'this load').toString();
    int receipts = 0, docs = 0;
    try {
      final r = await _supabase.from('expenses').select('id').eq('trip_id', id);
      receipts = (r as List).length;
    } catch (_) {}
    try {
      final d = await _supabase.from('trip_documents').select('id').eq('trip_id', id);
      docs = (d as List).length;
    } catch (_) {}
    if (!mounted) return;

    final msg = StringBuffer('Delete "$name"?');
    if (receipts > 0 || docs > 0) {
      final parts = <String>[];
      if (receipts > 0) parts.add('$receipts receipt${receipts == 1 ? '' : 's'}');
      if (docs > 0) parts.add('$docs document${docs == 1 ? '' : 's'}');
      msg.write('\n\nThis load has ${parts.join(' and ')}. '
          'Receipts will be kept but unlinked from any load; documents on this load will be removed.');
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete load'),
        content: Text(msg.toString()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      // Unlink receipts (kept, just no longer tied to a load) and clear the
      // load's documents first so the trip row deletes cleanly.
      await _supabase.from('expenses').update({'trip_id': null}).eq('trip_id', id);
      await _supabase.from('trip_documents').delete().eq('trip_id', id);
      await _supabase.from('trips').delete().eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Load deleted')));
      }
      _loadTrips();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.black87)),
        ],
      ),
    );
  }
}
