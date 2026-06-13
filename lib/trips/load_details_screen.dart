import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The load record for one trip — used to BOOK a load and to EDIT it later.
///
/// Open it right after saving a trip to book it (capture the broker #), or
/// open it from Saved Trips weeks later to drop in the PRO # and BOL # once
/// the carrier and shipper hand those over.
///
/// The numbers, in the order they show up in real life:
///   • broker_number  — the TQL#/confirmation #, known at BOOKING
///   • pickup_number  — optional, sometimes given by the broker
///   • pro_number     — the carrier's PRO #, arrives LATER, settlements list by it
///   • bol_number     — page 3 of the shipping order, filled at pickup, can change
///
/// Goes in: lib/trips/load_details_screen.dart

class LoadDetailsScreen extends StatefulWidget {
  final String tripId;
  const LoadDetailsScreen({super.key, required this.tripId});

  @override
  State<LoadDetailsScreen> createState() => _LoadDetailsScreenState();
}

class _LoadDetailsScreenState extends State<LoadDetailsScreen> {
  final _supabase = Supabase.instance.client;

  final _brokerCtrl = TextEditingController();
  final _pickupCtrl = TextEditingController();
  final _proCtrl = TextEditingController();
  final _bolCtrl = TextEditingController();
  final _proFocus = FocusNode();

  bool _loading = true;
  bool _saving = false;
  bool _booked = false;
  String? _bookedAt;

  // Route summary pulled defensively from whatever columns the trip has.
  String _routeLine = '';
  String _milesLine = '';
  String _moneyLine = '';

  // Linked-expense rollup (the estimated-vs-actual payoff).
  int _expenseCount = 0;
  double _expenseTotal = 0;

  // PRO# pre-fill: if this load has no PRO# yet, we seed the field with the
  // driver's last one and highlight the tail so they overtype just the end.
  // But that seeded value belongs to ANOTHER load — if they never change it,
  // we must NOT save it (it'd collide on the unique index). So we track it.
  String? _proGuess;
  bool _proIsGuess = false;

  @override
  void initState() {
    super.initState();
    _proFocus.addListener(_onProFocus);
    _init();
  }

  void _onProFocus() {
    // When they tap into a pre-filled PRO#, highlight the last 4 so the first
    // keystroke replaces the tail instead of the whole 12-digit string.
    if (_proFocus.hasFocus && _proIsGuess && _proCtrl.text == _proGuess) {
      final len = _proCtrl.text.length;
      final start = len > 4 ? len - 4 : 0;
      _proCtrl.selection = TextSelection(baseOffset: start, extentOffset: len);
    }
  }

  Future<void> _init() async {
    try {
      final trip = await _supabase
          .from('trips')
          .select('*')
          .eq('id', widget.tripId)
          .single();

      _brokerCtrl.text = (trip['broker_number'] ?? '').toString();
      _pickupCtrl.text = (trip['pickup_number'] ?? '').toString();
      _bolCtrl.text = (trip['bol_number'] ?? '').toString();

      final existingPro = (trip['pro_number'] ?? '').toString();
      _booked = (trip['status'] ?? '').toString() == 'booked';
      _bookedAt = trip['booked_at']?.toString();

      _buildSummary(trip);

      if (existingPro.isNotEmpty) {
        _proCtrl.text = existingPro; // real, already-assigned PRO#
      } else {
        await _seedProGuess(); // no PRO# yet — pre-fill from the last load
      }

      await _loadLinkedExpenses();
    } catch (e) {
      _toast('Could not load this load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Grab the driver's most recent PRO# from any OTHER load and use it as the
  // starting point. PRO#s are carrier-sequential, so last + edit-the-tail is
  // a great guess. (Broker# gets no such treatment — brokers vary every load.)
  Future<void> _seedProGuess() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final rows = await _supabase
          .from('trips')
          .select('pro_number')
          .eq('user_id', user.id)
          .not('pro_number', 'is', null)
          .neq('id', widget.tripId)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows is List && rows.isNotEmpty) {
        final last = (rows.first['pro_number'] ?? '').toString();
        if (last.isNotEmpty) {
          _proGuess = last;
          _proIsGuess = true;
          _proCtrl.text = last;
        }
      }
    } catch (_) {
      // no prior PRO# — fine, field just starts empty
    }
  }

  Future<void> _loadLinkedExpenses() async {
    try {
      final rows = await _supabase
          .from('expenses')
          .select('amount')
          .eq('trip_id', widget.tripId);
      if (rows is List) {
        double total = 0;
        for (final r in rows) {
          total += (r['amount'] is num) ? (r['amount'] as num).toDouble() : 0;
        }
        _expenseCount = rows.length;
        _expenseTotal = total;
      }
    } catch (_) {
      // non-fatal
    }
  }

  // Pull a friendly summary out of whatever columns this trip happens to have,
  // so this screen works regardless of the calculator's exact schema.
  void _buildSummary(Map<String, dynamic> trip) {
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = trip[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return null;
    }

    final origin = pick(['origin', 'origin_city', 'from', 'start', 'pickup_city']);
    final dest = pick(['destination', 'dest_city', 'to', 'end', 'delivery_city']);
    if (origin != null && dest != null) {
      _routeLine = '$origin  →  $dest';
    } else if (origin != null) {
      _routeLine = origin;
    } else if (dest != null) {
      _routeLine = dest;
    }

    final miles = pick(['total_miles', 'miles', 'loaded_miles', 'distance']);
    if (miles != null) {
      final m = double.tryParse(miles);
      _milesLine = m != null ? '${m.round()} mi' : '$miles mi';
    }

    final net = pick(['net', 'net_profit', 'estimated_net', 'take_home', 'profit']);
    if (net != null) {
      final n = double.tryParse(net);
      _moneyLine = n != null ? 'Est. net \$${n.toStringAsFixed(0)}' : 'Est. net $net';
    }
  }

  Future<void> _save({required bool book}) async {
    final broker = _brokerCtrl.text.trim();
    if (book && broker.isEmpty) {
      _toast('Enter the broker # (TQL#) to book this load.');
      return;
    }

    // If the PRO# field still shows the seeded guess untouched, it isn't this
    // load's number — save it as empty so we don't duplicate another load's PRO#.
    String? proToSave;
    final proText = _proCtrl.text.trim();
    if (proText.isNotEmpty && !(_proIsGuess && proText == _proGuess)) {
      proToSave = proText;
    }

    setState(() => _saving = true);
    try {
      final update = <String, dynamic>{
        'broker_number': broker.isEmpty ? null : broker,
        'pickup_number': _pickupCtrl.text.trim().isEmpty ? null : _pickupCtrl.text.trim(),
        'pro_number': proToSave,
        'bol_number': _bolCtrl.text.trim().isEmpty ? null : _bolCtrl.text.trim(),
      };
      if (book && !_booked) {
        update['status'] = 'booked';
        update['booked_at'] = DateTime.now().toUtc().toIso8601String();
      }

      await _supabase.from('trips').update(update).eq('id', widget.tripId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(book && !_booked ? 'Load booked' : 'Load saved'),
            backgroundColor: Colors.green[700],
          ),
        );
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (e) {
      final msg = '${e.message} ${e.details ?? ''}';
      if (msg.contains('trips_user_pro_number')) {
        _toast('You already have a load with that PRO #.');
      } else if (msg.contains('trips_user_broker_number')) {
        _toast('You already have a load with that broker #.');
      } else {
        _toast('Save failed: ${e.message}');
      }
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  void dispose() {
    _proFocus.removeListener(_onProFocus);
    _proFocus.dispose();
    _brokerCtrl.dispose();
    _pickupCtrl.dispose();
    _proCtrl.dispose();
    _bolCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_booked ? 'Load Details' : 'Book This Load'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summaryCard(),
                const SizedBox(height: 20),
                _label('Broker # (TQL#)', 'Given by the broker when you book'),
                _field(_brokerCtrl, 'e.g. 88421307', autofocus: !_booked),
                const SizedBox(height: 16),
                _label('Pickup #', 'Optional — if the broker gave you one'),
                _field(_pickupCtrl, 'Optional'),
                const SizedBox(height: 16),
                _label('PRO #', _proIsGuess
                    ? 'Pre-filled from your last load — just change the last few digits'
                    : 'Your carrier assigns this — settlements list by it'),
                _field(_proCtrl, 'Carrier PRO #',
                    focusNode: _proFocus,
                    onChanged: (_) {
                      if (_proIsGuess) setState(() => _proIsGuess = false);
                    }),
                const SizedBox(height: 16),
                _label('BOL #', 'From the shipping order — usually added at pickup'),
                _field(_bolCtrl, 'Optional — can be added later'),
                const SizedBox(height: 28),
                _primaryButton(),
                if (_booked) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _bookedAt != null
                          ? 'Booked ${_prettyDate(_bookedAt!)}'
                          : 'Booked',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _summaryCard() {
    final hasRoute = _routeLine.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_booked ? Icons.local_shipping : Icons.add_road,
                  size: 20, color: Colors.blueGrey[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasRoute ? _routeLine : 'This Load',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              if (_booked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green[600],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('BOOKED',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
            ],
          ),
          if (_milesLine.isNotEmpty || _moneyLine.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [_milesLine, _moneyLine].where((s) => s.isNotEmpty).join('   •   '),
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ],
          if (_expenseCount > 0) ...[
            const Divider(height: 20),
            Row(
              children: [
                Icon(Icons.receipt_long, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  '$_expenseCount receipt${_expenseCount == 1 ? '' : 's'} linked  •  '
                  '\$${_expenseTotal.toStringAsFixed(2)} logged',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _primaryButton() {
    final booking = !_booked;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : () => _save(book: booking),
        icon: _saving
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(booking ? Icons.check_circle : Icons.save),
        label: Text(_saving
            ? 'Saving…'
            : booking
                ? 'Book This Load'
                : 'Save Changes'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: booking ? Colors.green[700] : Colors.blueGrey[700],
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _label(String title, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Text(hint, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    FocusNode? focusNode,
    bool autofocus = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      focusNode: focusNode,
      autofocus: autofocus,
      onChanged: onChanged,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  String _prettyDate(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
