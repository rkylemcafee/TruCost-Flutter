import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../help/help_content.dart';

/// Fuel-by-state for a load. Shows miles + gallons burned in each state so the
/// driver can decide where (and how much) to fuel to keep the IFTA bill down.
/// Defaults to the loaded haul (pickup -> delivery); enter a "starting from"
/// city to fold in the empty deadhead leg too.
///
/// Goes in: lib/trips/state_fuel_screen.dart

class StateFuelScreen extends StatefulWidget {
  final String pickup;
  final String delivery;
  final String? tripName;

  const StateFuelScreen({
    super.key,
    required this.pickup,
    required this.delivery,
    this.tripName,
  });

  @override
  State<StateFuelScreen> createState() => _StateFuelScreenState();
}

class _StateFuelScreenState extends State<StateFuelScreen> {
  final _supabase = Supabase.instance.client;
  final _startCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  double _totalMiles = 0;
  double _totalGallons = 0;
  double _emptyMpg = 0;
  double _loadedMpg = 0;
  bool _hasDeadhead = false;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final start = _startCtrl.text.trim();
      final res = await _supabase.functions.invoke('state-fuel', body: {
        'pickup': widget.pickup,
        'delivery': widget.delivery,
        if (start.isNotEmpty) 'current_location': start,
      });
      final data = res.data;
      if (data is Map && data['error'] == null && data['rows'] is List) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(data['rows']);
          _totalMiles = (data['totalMiles'] ?? 0).toDouble();
          _totalGallons = (data['totalGallons'] ?? 0).toDouble();
          _emptyMpg = (data['emptyMpg'] ?? 0).toDouble();
          _loadedMpg = (data['loadedMpg'] ?? 0).toDouble();
          _hasDeadhead = data['hasDeadhead'] == true;
        });
      } else {
        setState(() => _error =
            (data is Map ? data['error']?.toString() : null) ?? 'Could not pull the route.');
      }
    } catch (e) {
      setState(() => _error = 'Lookup failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fuel by State'), actions: const [HelpButton(HelpScreens.fuelByState)]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.tripName ?? '${widget.pickup}  \u2192  ${widget.delivery}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Optional deadhead start
          TextField(
            controller: _startCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Starting from (optional)',
              helperText: 'Add your current city to include the empty deadhead to pickup',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Recalculate',
                onPressed: _loading ? null : _compute,
              ),
            ),
            onSubmitted: (_) => _compute(),
          ),
          const SizedBox(height: 20),

          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _errorBox()
          else ...[
            _totalCard(),
            const SizedBox(height: 16),
            ..._rows.map(_stateRow),
            const SizedBox(height: 16),
            _guidanceNote(),
          ],
        ],
      ),
    );
  }

  Widget _totalCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey[700],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _totalStat('${_totalGallons.round()}', 'gallons total'),
          Container(width: 1, height: 40, color: Colors.white24),
          _totalStat('${_totalMiles.round()}', 'miles'),
        ],
      ),
    );
  }

  Widget _totalStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }

  Widget _stateRow(Map<String, dynamic> r) {
    final miles = (r['miles'] ?? 0).toDouble();
    final gallons = (r['gallons'] ?? 0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              (r['state'] ?? '?').toString(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text('${miles.round()} mi', style: TextStyle(color: Colors.grey[700])),
          ),
          Text(
            '${gallons.round()} gal',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _guidanceNote() {
    final mpgNote = _hasDeadhead
        ? 'Deadhead at $_emptyMpg mpg empty, haul at $_loadedMpg mpg loaded.'
        : 'Loaded haul at $_loadedMpg mpg. Add your starting city above to include the empty deadhead.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_gas_station, size: 18, color: Colors.amber[800]),
              const SizedBox(width: 6),
              const Text('How to use this', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Each row is the fuel you\'ll burn in that state. Try to buy about that many '
            'gallons in each state you drive through — matching your fill-ups to your burn '
            'keeps your IFTA fuel tax down.',
            style: TextStyle(fontSize: 13, color: Colors.grey[800]),
          ),
          const SizedBox(height: 8),
          Text(mpgNote, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _errorBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        children: [
          Text(_error!, style: TextStyle(color: Colors.red[900])),
          const SizedBox(height: 8),
          TextButton(onPressed: _compute, child: const Text('Try again')),
        ],
      ),
    );
  }
}
