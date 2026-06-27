import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'state_fuel_screen.dart';

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
  final _notesCtrl = TextEditingController();
  final _grossCtrl = TextEditingController();
  final _proFocus = FocusNode();

  // Cost basis pulled from the saved estimate. These don't change with gross,
  // so we recompute carrier cut / net / $hr off the agreed gross arithmetically.
  double _carrierCutPct = 25;
  double _totalCosts = 0;
  double _totalHours = 0;
  bool _haveBasis = false;

  bool _loading = true;
  bool _saving = false;
  bool _booked = false;
  bool _tripSheetSent = false;
  String? _bookedAt;

  // Route summary pulled defensively from whatever columns the trip has.
  String _routeLine = '';
  String _origin = '';
  String _destination = '';
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
      _notesCtrl.text = (trip['notes'] ?? '').toString();

      // Agreed gross: the number we're booking at. Falls back through the
      // gross history (agreed → quoted → offer) so the field is never blank.
      double pickNum(List<String> keys) {
        for (final k in keys) {
          final v = trip[k];
          if (v is num) return v.toDouble();
          final d = double.tryParse((v ?? '').toString());
          if (d != null && d > 0) return d;
        }
        return 0;
      }
      final agreed = pickNum(['agreed_gross', 'quoted_gross', 'offer_gross', 'gross_pay']);
      if (agreed > 0) _grossCtrl.text = agreed.toStringAsFixed(0);

      // Cost basis from the saved estimate (gross-independent).
      final est = trip['estimate_json'];
      if (est is Map) {
        _totalCosts = (est['totalCosts'] is num) ? (est['totalCosts'] as num).toDouble() : 0;
        _totalHours = (est['totalHours'] is num) ? (est['totalHours'] as num).toDouble() : 0;
        _haveBasis = _totalCosts > 0 && _totalHours > 0;
      }
      _carrierCutPct = pickNum(['carrier_cut_pct_at_time']) > 0
          ? pickNum(['carrier_cut_pct_at_time'])
          : 25;

      final existingPro = (trip['pro_number'] ?? '').toString();
      _booked = (trip['status'] ?? '').toString() == 'booked';
      _tripSheetSent = (trip['trip_sheet_sent'] ?? false) == true;
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
          // PRO#s are carrier-sequential, so the next is almost always last + 1.
          // Pre-fill that as the guess; he confirms with dispatch and overtypes
          // if it differs, or taps "Don't have one yet" to clear it.
          final guess = _nextPro(last);
          _proGuess = guess;
          _proIsGuess = true;
          _proCtrl.text = guess;
        }
      }
    } catch (_) {
      // no prior PRO# — fine, field just starts empty
    }
  }

  // Bump the trailing digits of a PRO# by one, keeping any prefix and the
  // original digit width: "20260005"->"20260006", "A0099"->"A0100",
  // "999"->"1000". No trailing number -> returned unchanged.
  String _nextPro(String pro) {
    final match = RegExp(r'^(.*?)(\d+)$').firstMatch(pro);
    if (match == null) return pro;
    final prefix = match.group(1) ?? '';
    final digits = match.group(2)!;
    final incremented = (int.parse(digits) + 1).toString();
    return '$prefix${incremented.padLeft(digits.length, '0')}';
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
    _origin = origin ?? '';
    _destination = dest ?? '';
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
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'trip_sheet_sent': _tripSheetSent,
      };

      // Agreed gross is the single locked number — all economics derive from it.
      // Costs/hours are gross-independent (from the estimate), so carrier cut,
      // net, and $/hr recompute arithmetically. No engine call needed.
      final agreed = double.tryParse(_grossCtrl.text.trim());
      if (agreed != null && agreed > 0) {
        update['agreed_gross'] = agreed;
        final cutPct = _carrierCutPct / 100.0;
        final carrierCut = agreed * cutPct;
        final operatorGross = agreed * (1 - cutPct);
        update['carrier_cut'] = carrierCut;
        if (_haveBasis) {
          final net = operatorGross - _totalCosts;
          final hourly = _totalHours > 0 ? net / _totalHours : 0.0;
          update['net_to_operator'] = net;
          update['effective_hourly'] = hourly;
        }
      }

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
    _notesCtrl.dispose();
    _grossCtrl.dispose();
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
                if (_origin.isNotEmpty && _destination.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StateFuelScreen(
                          pickup: _origin,
                          delivery: _destination,
                          tripName: _routeLine.isNotEmpty ? _routeLine : null,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.local_gas_station),
                    label: const Text('Fuel by State'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _label('Agreed gross (\$)', 'What you and the broker settled on — drives the math'),
                TextField(
                  controller: _grossCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixText: '\$ ',
                    hintText: 'e.g. 1600',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (_haveBasis && _agreedNet != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _agreedNet! >= 0
                        ? 'Nets ${_usd(_agreedNet!)} · ${_usd(_agreedHourly!)}/hr after the cut and costs'
                        : 'Loses ${_usd(_agreedNet!.abs())} at this rate',
                    style: TextStyle(
                      fontSize: 12,
                      color: (_agreedNet! >= 0) ? Colors.green[800] : Colors.red[700],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _label('Broker # (TQL#)', 'Given by the broker when you book'),
                _field(_brokerCtrl, 'e.g. 88421307', autofocus: !_booked),
                const SizedBox(height: 16),
                _label('Pickup #', 'Optional — if the broker gave you one'),
                _field(_pickupCtrl, 'Optional'),
                const SizedBox(height: 16),
                _label('PRO #', _proIsGuess
                    ? 'Guessed as last + 1 — confirm with dispatch, or tap below'
                    : 'Dispatch assigns this — settlements list by it'),
                _field(_proCtrl, 'Carrier PRO #',
                    focusNode: _proFocus,
                    onChanged: (_) {
                      if (_proIsGuess) setState(() => _proIsGuess = false);
                    }),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      _proCtrl.clear();
                      setState(() => _proIsGuess = false);
                    },
                    icon: const Icon(Icons.schedule, size: 16),
                    label: const Text('Don\'t have one yet'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _label('BOL #', 'From the shipping order — usually added at pickup'),
                _field(_bolCtrl, 'Optional — can be added later'),
                const SizedBox(height: 16),
                _label('Notes', 'Gate codes, who to ask for, anything the co-pilot jots down'),
                TextField(
                  controller: _notesCtrl,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Ask for Bob at the gate. Code 12463.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Trip sheet sent'),
                  subtitle: const Text('Flip this on once you\'ve sent the settlement / trip sheet'),
                  value: _tripSheetSent,
                  onChanged: (v) => setState(() => _tripSheetSent = v),
                ),
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

  String _usd(double v) => '\$${v.toStringAsFixed(0)}';

  // Live recompute as he edits the agreed gross — same arithmetic the save uses.
  double? get _agreedNet {
    final g = double.tryParse(_grossCtrl.text.trim());
    if (g == null || g <= 0 || !_haveBasis) return null;
    final operatorGross = g * (1 - _carrierCutPct / 100.0);
    return operatorGross - _totalCosts;
  }

  double? get _agreedHourly {
    final n = _agreedNet;
    if (n == null || _totalHours <= 0) return null;
    return n / _totalHours;
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
