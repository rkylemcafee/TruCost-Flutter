import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SavedTripsScreen extends StatefulWidget {
  const SavedTripsScreen({super.key});
  @override
  State<SavedTripsScreen> createState() => _SavedTripsScreenState();
}

enum TripSort { date, gross, net, hourly }

class _SavedTripsScreenState extends State<SavedTripsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _trips = [];
  bool _loading = true;
  TripSort _sort = TripSort.date;

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

  void _sortTrips() {
    switch (_sort) {
      case TripSort.date:
        _trips.sort((a, b) => (b['trip_date'] ?? '').compareTo(a['trip_date'] ?? ''));
        break;
      case TripSort.gross:
        _trips.sort((a, b) => _toNum(b['gross_pay']).compareTo(_toNum(a['gross_pay'])));
        break;
      case TripSort.net:
        _trips.sort((a, b) => _toNum(b['estimated_net']).compareTo(_toNum(a['estimated_net'])));
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

  double _getHourly(Map<String, dynamic> trip) {
    final json = trip['estimate_json'];
    if (json == null) return 0;
    if (json is Map) return _toNum(json['effectiveHourlyRate']);
    return 0;
  }

  String _usd(double v) => '\$${v.toStringAsFixed(2)}';

  String _sortLabel(TripSort s) {
    switch (s) {
      case TripSort.date: return 'Date';
      case TripSort.gross: return 'Gross';
      case TripSort.net: return 'Net';
      case TripSort.hourly: return '\$/hr';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Trips')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trips.isEmpty
              ? const Center(
                  child: Text('No saved trips yet.\nCalculate a load and tap Save.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey)))
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      color: Colors.grey[100],
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
                        child: Text('${_trips.length} trip${_trips.length != 1 ? 's' : ''}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadTrips,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _trips.length,
                          itemBuilder: (ctx, i) => _buildTripCard(_trips[i]),
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
    final gross = _toNum(trip['gross_pay']);
    final net = _toNum(trip['estimated_net']);
    final fuel = _toNum(trip['estimated_fuel_cost']);
    final miles = _toNum(trip['total_miles']);
    final hourly = _getHourly(trip);
    final origin = trip['origin'] ?? '';
    final destination = trip['destination'] ?? '';
    final isWinner = net >= 0;
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
              ],
            ),
          ),
        ],
      ),
    );
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