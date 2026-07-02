import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../help/help_content.dart';

/// The trip sheet — a per-load settlement packet. Pick a booked load and it
/// assembles the header (your authority + the load), the financials (gross →
/// deductions → net and real $/hr), miles, a fuel reconciliation (gallons
/// bought vs expected + actual MPG), receipts itemized by category, and the
/// documents attached to the load.
///
/// This screen is the on-screen review. PDF + Excel export build on top of it.
///
/// Goes in: lib/trips/trip_sheet_screen.dart

class TripSheetScreen extends StatefulWidget {
  const TripSheetScreen({super.key, this.tripId});
  final String? tripId; // optional: open straight to a load
  @override
  State<TripSheetScreen> createState() => _TripSheetScreenState();
}

class _TripSheetScreenState extends State<TripSheetScreen> {
  final _supabase = Supabase.instance.client;

  bool _loadingList = true;
  bool _building = false;
  List<Map<String, dynamic>> _loads = [];
  String? _tripId;

  // Assembled sheet pieces.
  Map<String, dynamic>? _trip;
  Map<String, dynamic> _ej = {};
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _docs = [];
  String? _truckLabel;
  String? _trailerLabel;

  // IFTA: per-jurisdiction diesel rate + surcharge (from ifta_fuel_tax_rates),
  // and the gallons burned per state for this load. Used to estimate the fuel
  // tax the carrier deducts from the settlement check.
  final Map<String, double> _iftaRate = {};
  final Map<String, double> _iftaSurcharge = {};
  List<MapEntry<String, double>> _stateGallons = [];
  bool _iftaExpanded = false; // settlement IFTA breakdown open/closed

  @override
  void initState() {
    super.initState();
    _tripId = widget.tripId;
    _loadLoads();
  }

  double? _n(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String _money(dynamic v, {int dp = 0}) {
    final d = _n(v);
    if (d == null) return '—';
    return '\$${d.toStringAsFixed(dp)}';
  }

  Future<void> _loadLoads() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final rows = await _supabase
          .from('trips')
          .select('id, trip_name, origin, destination, trip_date')
          .eq('user_id', user.id)
          .or('stage.in.(won,completed),status.eq.booked')
          .order('trip_date', ascending: false)
          .limit(60);
      _loads = List<Map<String, dynamic>>.from(rows);
      if (mounted) setState(() => _loadingList = false);
      if (_tripId != null) _assemble(_tripId!);
    } catch (_) {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  String _loadLabel(Map<String, dynamic> t) {
    final name = (t['trip_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return '${t['origin'] ?? '?'} \u2192 ${t['destination'] ?? '?'}';
  }

  Future<void> _assemble(String tripId) async {
    setState(() {
      _building = true;
      _trip = null;
    });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final trip = await _supabase.from('trips').select().eq('id', tripId).maybeSingle();
      final profile = await _supabase
          .from('profiles')
          .select('operator_name, mc_number, dot_number, carrier_name')
          .eq('user_id', user.id)
          .maybeSingle();
      final exp = await _supabase
          .from('expenses')
          .select('category, vendor, amount, gallons, expense_date, reimbursable, carrier_fuel_card, is_advance, receipt_url, purchase_state')
          .eq('user_id', user.id)
          .eq('trip_id', tripId);
      final docs = await _supabase
          .from('trip_documents')
          .select('doc_type, reference, storage_path, created_at')
          .eq('user_id', user.id)
          .eq('trip_id', tripId)
          .order('created_at');

      _truckLabel = await _unitLabel(trip?['truck_unit_id']);
      _trailerLabel = await _unitLabel(trip?['trailer_unit_id']);

      final ejRaw = trip?['estimate_json'];
      _ej = ejRaw is Map ? Map<String, dynamic>.from(ejRaw) : {};
      // Newer estimates nest the numbers under breakdown / rates / levers
      // (schemaVersion 2). Flatten those up so every existing read — equipment,
      // overhead, net, carrier cut % — resolves the same for old and new loads.
      // These are the frozen values captured at book time; nothing here is
      // recomputed from the current profile.
      if (_ej['breakdown'] is Map || _ej['rates'] is Map || _ej['levers'] is Map) {
        final flat = Map<String, dynamic>.from(_ej);
        for (final section in const ['breakdown', 'rates', 'levers']) {
          if (_ej[section] is Map) {
            flat.addAll(Map<String, dynamic>.from(_ej[section] as Map));
          }
        }
        _ej = flat;
      }
      _trip = trip;
      _profile = profile;
      _expenses = List<Map<String, dynamic>>.from(exp);
      _docs = List<Map<String, dynamic>>.from(docs);
      await _loadIfta(trip);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not build trip sheet: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  Future<String?> _unitLabel(dynamic unitId) async {
    if (unitId == null) return null;
    try {
      final u = await _supabase
          .from('units')
          .select('unit_number, unit_type')
          .eq('id', unitId)
          .maybeSingle();
      if (u == null) return null;
      final num = (u['unit_number'] ?? '').toString().trim();
      final type = (u['unit_type'] ?? '').toString().trim();
      if (num.isEmpty && type.isEmpty) return null;
      return [type, if (num.isNotEmpty) '#$num'].where((s) => s.isNotEmpty).join(' ');
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Sheet'),
        actions: [
          if (_trip != null)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share trip sheet',
              onPressed: _sharePdf,
            ),
          const HelpButton(HelpScreens.tripSheet),
        ],
      ),
      body: _loadingList
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _loadPicker(),
                const SizedBox(height: 12),
                if (_building)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_trip != null) ...[
                  _authorityCard(),
                  _loadCard(),
                  _settlementCard(),
                  _truecostCard(),
                  _milesCard(),
                  _fuelCard(),
                  _receiptsCard(),
                  _documentsCard(),
                  const SizedBox(height: 8),
                  Text(
                    'On-screen review. PDF + Excel export coming next.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text(
                      _loads.isEmpty
                          ? 'No booked loads yet. Book a load and it shows up here.'
                          : 'Pick a booked load to build its trip sheet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600], fontSize: 15),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _loadPicker() {
    return DropdownButtonFormField<String?>(
      value: _tripId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Which load?',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: _loads
          .map((t) => DropdownMenuItem<String?>(
                value: t['id'].toString(),
                child: Text(_loadLabel(t), overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (v) {
        setState(() => _tripId = v);
        if (v != null) _assemble(v);
      },
    );
  }

  // ── Cards ──────────────────────────────────────────────────
  Widget _card(String title, List<Widget> rows, {Color? accent}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: accent ?? Colors.blueGrey[700])),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          ),
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _str(dynamic v) => (v ?? '').toString().trim();

  Widget _authorityCard() {
    final p = _profile ?? {};
    final name = _str(p['operator_name']);
    final mc = _str(p['mc_number']);
    final dot = _str(p['dot_number']);
    final carrier = _str(p['carrier_name']);
    final rows = <Widget>[];
    if (name.isNotEmpty) rows.add(_row('Operator', name));
    if (mc.isNotEmpty) rows.add(_row('MC #', mc));
    if (dot.isNotEmpty) rows.add(_row('DOT #', dot));
    if (carrier.isNotEmpty) rows.add(_row('Leased to', carrier));
    if (rows.isEmpty) {
      rows.add(_row('—', 'Add your authority in Settings'));
    }
    return _card('AUTHORITY', rows);
  }

  Widget _loadCard() {
    final t = _trip!;
    final origin = _str(t['origin']);
    final dest = _str(t['destination']);
    final rows = <Widget>[
      _row('Route', '${origin.isEmpty ? '?' : origin}  \u2192  ${dest.isEmpty ? '?' : dest}', bold: true),
    ];
    final date = _str(t['trip_date']);
    if (date.isNotEmpty) rows.add(_row('Load date', date));
    final booked = _str(t['booked_at']);
    if (booked.isNotEmpty) rows.add(_row('Booked', booked.split('T').first));

    void ref(String label, String key) {
      final v = _str(t[key]);
      if (v.isNotEmpty) rows.add(_row(label, v));
    }

    ref('Broker / TQL #', 'broker_number');
    ref('Pickup #', 'pickup_number');
    ref('BOL #', 'bol_number');
    ref('PRO #', 'pro_number');

    if (_truckLabel != null) rows.add(_row('Truck', _truckLabel!));
    if (_trailerLabel != null) rows.add(_row('Trailer', _trailerLabel!));

    return _card('LOAD', rows);
  }

  double _reimbursableTotal() {
    double s = 0;
    for (final e in _expenses) {
      if (e['is_advance'] == true) continue; // an advance is not a reimbursable expense
      // default true (only fuel/explicit false is excluded)
      if (e['reimbursable'] != false) s += _n(e['amount']) ?? 0;
    }
    return s;
  }

  // Fuel bought on the carrier's card/advance — the carrier deducts this from
  // the settlement, so it makes the check smaller. Operator-paid fuel is NOT
  // here (that's his own cost, already in TruCost).
  double _carrierCardFuel() {
    double s = 0;
    for (final e in _expenses) {
      if (e['is_advance'] == true) continue;
      final cat = (e['category'] ?? '').toString().toLowerCase();
      final isFuel = cat.contains('fuel') || cat.contains('diesel');
      if (isFuel && e['carrier_fuel_card'] == true) s += _n(e['amount']) ?? 0;
    }
    return s;
  }

  // Cash advances the carrier fronted — taken back out of the settlement.
  double _advanceTotal() {
    double s = 0;
    for (final e in _expenses) {
      if (e['is_advance'] == true) s += _n(e['amount']) ?? 0;
    }
    return s;
  }

  // What the carrier actually pays: your share of gross + reimbursables
  // − fuel they fronted on the card − cash advances.
  Widget _settlementCard() {
    final t = _trip!;
    final gross = _n(t['agreed_gross']) ?? _n(t['quoted_gross']) ?? _n(t['offer_gross']) ?? _n(t['gross_pay']) ?? _n(_ej['bookedGross']) ?? _n(_ej['quotedGross']);
    final carrierPct = _n(t['carrier_cut_pct_at_time']) ?? _n(_ej['carrierCutPct']);
    final hisShare = (gross != null && carrierPct != null) ? gross * (1 - carrierPct / 100) : null;
    final reimb = _reimbursableTotal();
    final cardFuel = _carrierCardFuel();
    final advances = _advanceTotal();
    final ifta = _estIfta();
    final expectedCheck = hisShare != null
        ? hisShare + reimb - cardFuel - advances - ifta.tax
        : null;

    final rows = <Widget>[
      _row('Load gross', _money(gross)),
    ];
    if (hisShare != null) {
      final keepPct = carrierPct != null ? (100 - carrierPct).toStringAsFixed(0) : '?';
      rows.add(_row('Your share ($keepPct% after carrier cut)', _money(hisShare)));
    }
    rows.add(_row('+ Reimbursable expenses', _money(reimb, dp: 2)));
    if (cardFuel > 0) {
      rows.add(_row('− Fuel on carrier card', '-${_money(cardFuel, dp: 2)}',
          valueColor: Colors.orange[800]));
    }
    if (advances > 0) {
      rows.add(_row('− Cash advances', '-${_money(advances, dp: 2)}',
          valueColor: Colors.orange[800]));
    }
    if (_stateGallons.isNotEmpty && _iftaRate.isNotEmpty) {
      final prepaid = ifta.tax <= 0;
      rows.add(InkWell(
        onTap: () => setState(() => _iftaExpanded = !_iftaExpanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(_iftaExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: Colors.grey[600]),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  prepaid
                      ? 'Fuel tax (IFTA) — you\'re prepaid'
                      : 'They\'ll likely deduct for fuel tax (IFTA${ifta.worstCase ? ', worst case' : ''})',
                  style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                ),
              ),
              Text(prepaid ? '\$0.00' : '-${_money(ifta.tax, dp: 2)}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: prepaid ? Colors.green[700] : Colors.orange[800])),
            ],
          ),
        ),
      ));
      if (_iftaExpanded) rows.addAll(_iftaBreakdownWidgets());
    }
    rows.add(const Divider());
    rows.add(_row('EXPECTED CHECK', _money(expectedCheck), bold: true, valueColor: Colors.green[800]));
    rows.add(const SizedBox(height: 6));
    rows.add(Text(
      (_stateGallons.isNotEmpty && _iftaRate.isNotEmpty)
          ? (ifta.worstCase
              ? 'Fuel tax is a worst-case IFTA estimate — it assumes you bought no '
                  'fuel on this load. Log fuel receipts (tagged by state) to lower it. '
                  'Still excludes insurance, ELD, and trailer rent. Reconcile against '
                  'your settlement statement.'
              : 'Fuel tax is an IFTA estimate — what you owe on the fuel you burned, '
                  'minus credit for fuel you bought. Still excludes insurance, ELD, '
                  'and trailer rent. Reconcile against your settlement statement.')
          : 'Before any carrier-specific deductions (fuel tax, insurance, ELD, '
              'trailer rent). Reconcile this against your settlement statement.',
      style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.3),
    ));
    return _card('SETTLEMENT — YOUR CHECK', rows, accent: Colors.green[800]);
  }

  // The decision number: your real profit after YOUR costs (not the check).
  Widget _truecostCard() {
    final t = _trip!;
    final fuel = _n(t['estimated_fuel_cost']) ?? _n(_ej['totalFuelCost']);
    final equip = _n(_ej['equipmentCost']);
    final overhead = _n(_ej['overheadCost']);
    final net = _n(t['net_to_operator']) ??
        _n(t['estimated_net']) ??
        _n(_ej['netToOperator']) ??
        _n(_ej['netAtQuote']);
    final hourly = _n(t['effective_hourly']) ?? _n(_ej['effectiveHourlyRate']);
    final target = _n(_ej['hourlyBar']) ?? _n(_ej['targetHourly']);

    final rows = <Widget>[];
    if (fuel != null) rows.add(_row('Your fuel', '-${_money(fuel)}'));
    if (equip != null) rows.add(_row('Truck/trailer', '-${_money(equip)}'));
    if (overhead != null) rows.add(_row('Overhead', '-${_money(overhead)}'));
    rows.add(const Divider());
    rows.add(_row('TruCost net (real profit)', _money(net),
        bold: true, valueColor: (net ?? 0) >= 0 ? Colors.green[800] : Colors.red[700]));
    if (hourly != null) {
      final clears = target != null && hourly >= target;
      rows.add(_row(
        'Real \$/hr${target != null ? ' (target ${_money(target)})' : ''}',
        '${_money(hourly)}/hr',
        bold: true,
        valueColor: clears ? Colors.green[800] : Colors.orange[800],
      ));
    }
    rows.add(const SizedBox(height: 6));
    rows.add(Text(
      'Your decision number — not your check. It subtracts costs the carrier doesn\'t: '
      'your fuel, truck payment, overhead, and target wage.',
      style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.3),
    ));
    return _card('TRUCOST — REAL PROFIT', rows);
  }

  Widget _milesCard() {
    final t = _trip!;
    final loaded = _n(t['loaded_miles']);
    final deadhead = _n(t['deadhead_miles']);
    final total = _n(t['total_miles']) ?? _n(_ej['totalMiles']);
    final hours = _n(_ej['totalHours']);
    final rows = <Widget>[];
    if (loaded != null) rows.add(_row('Loaded miles', loaded.round().toString()));
    if (deadhead != null) rows.add(_row('Deadhead miles', deadhead.round().toString()));
    if (total != null) rows.add(_row('Total miles', total.round().toString(), bold: true));
    if (hours != null) rows.add(_row('Total hours', hours.toStringAsFixed(1)));
    if (rows.isEmpty) rows.add(_row('—', 'no mileage on file'));
    return _card('MILES', rows);
  }

  // Per-state fuel as GALLONS. New bookings store gallonsByState directly. Older
  // ones only saved miles by state (the estimate snapshot reused the route's
  // mileage map), so we spread the expected burn across those miles — an even-MPG
  // estimate, close enough to guide where to fill for IFTA.
  List<MapEntry<String, double>> _gallonsByState(double? expectedGal) {
    final gbs = _ej['gallonsByState'];
    if (gbs is Map && gbs.isNotEmpty) {
      final out = <String, double>{};
      gbs.forEach((k, v) => out[k.toString()] = _n(v) ?? 0);
      return out.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    }
    final fbs = _ej['fuelByState'];
    if (fbs is! Map || fbs.isEmpty || expectedGal == null) return [];
    final miles = <String, double>{};
    double sum = 0;
    fbs.forEach((k, v) {
      final d = _n(v) ?? 0;
      miles[k.toString()] = d;
      sum += d;
    });
    if (sum <= 0) return [];
    final out = <String, double>{};
    miles.forEach((k, v) => out[k] = v / sum * expectedGal);
    return out.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  // Gallons actually BOUGHT per state, from this load's fuel receipts and the
  // purchase_state tagged on each. The '' key holds gallons on fuel receipts
  // with no state tagged, so we can show that honestly rather than hiding it.
  Map<String, double> _boughtByState() {
    final m = <String, double>{};
    for (final e in _expenses) {
      final cat = _str(e['category']).toLowerCase();
      if (!cat.contains('fuel') && !cat.contains('diesel') && !cat.contains('def')) continue;
      final gal = _n(e['gallons']) ?? 0;
      if (gal <= 0) continue;
      final st = _str(e['purchase_state']).toUpperCase().trim();
      m[st] = (m[st] ?? 0) + gal; // '' = no state tagged
    }
    return m;
  }

  // Pull IFTA diesel rates + this load's gallons-burned-by-state, so the
  // settlement can estimate the fuel tax the carrier deducts. Best-effort —
  // any failure just leaves the estimate off; it never breaks the sheet.
  Future<void> _loadIfta(Map<String, dynamic>? trip) async {
    try {
      final rows = await _supabase
          .from('ifta_fuel_tax_rates')
          .select('jurisdiction, rate_usd_gal, surcharge_usd_gal')
          .eq('country', 'US')
          .eq('fuel_type', 'diesel');
      _iftaRate.clear();
      _iftaSurcharge.clear();
      for (final r in rows) {
        final j = (r['jurisdiction'] ?? '').toString().toUpperCase().trim();
        if (j.isEmpty) continue;
        _iftaRate[j] = _n(r['rate_usd_gal']) ?? 0;
        _iftaSurcharge[j] = _n(r['surcharge_usd_gal']) ?? 0;
      }

      // Gallons burned per state. Prefer the frozen estimate; if the load has no
      // state breakdown (new Ugly Truth bookings only store total miles), pull
      // it live from the same route service the Fuel-by-State screen uses.
      final fuelCost = _n(trip?['estimated_fuel_cost']) ?? _n(_ej['totalFuelCost']);
      final price = _n(trip?['fuel_price_used']) ?? _n(_ej['fuelPriceUsed']);
      final expectedGal =
          (fuelCost != null && price != null && price > 0) ? fuelCost / price : null;

      var gbs = _gallonsByState(expectedGal);
      if (gbs.isEmpty) {
        final origin = (trip?['origin'] ?? '').toString();
        final dest = (trip?['destination'] ?? '').toString();
        if (origin.isNotEmpty && dest.isNotEmpty) {
          final res = await _supabase.functions
              .invoke('state-fuel', body: {'pickup': origin, 'delivery': dest});
          final data = res.data;
          if (data is Map && data['rows'] is List) {
            final out = <String, double>{};
            for (final row in (data['rows'] as List)) {
              if (row is Map) {
                final s = (row['state'] ?? '').toString().toUpperCase().trim();
                final gal = _n(row['gallons']) ?? 0;
                if (s.isNotEmpty && gal > 0) out[s] = (out[s] ?? 0) + gal;
              }
            }
            gbs = out.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          }
        }
      }
      _stateGallons = gbs;
    } catch (_) {
      // leave the IFTA estimate off on any failure
    }
  }

  // Fair estimate of the fuel tax the carrier nets out of the check — not a
  // full IFTA/HUT filing. You owe each state's diesel rate (plus any surcharge)
  // on the gallons you burn there; fuel bought in-state credits back the base
  // rate you already paid at the pump. Net it, floor at zero: buy none and it's
  // the full worst case; prepay enough and they "zero it and move on."
  ({double tax, bool worstCase, double owed, double credit}) _estIfta() {
    if (_stateGallons.isEmpty || _iftaRate.isEmpty) {
      return (tax: 0.0, worstCase: false, owed: 0.0, credit: 0.0);
    }
    final bought = _boughtByState();
    double owed = 0, credit = 0, boughtTotal = 0;
    for (final e in _stateGallons) {
      final st = e.key.toUpperCase();
      owed += e.value * ((_iftaRate[st] ?? 0) + (_iftaSurcharge[st] ?? 0));
      credit += (bought[st] ?? 0) * (_iftaRate[st] ?? 0);
    }
    bought.forEach((_, v) => boughtTotal += v);
    final net = owed - credit;
    return (
      tax: net > 0 ? net : 0.0,
      worstCase: boughtTotal <= 0,
      owed: owed,
      credit: credit,
    );
  }

  // The proof: per-state IFTA in alphabetical order — what you bought there,
  // what you owe on the fuel you burned there, and any credit if you bought
  // more than you burned. Makes plain that cheap-state fuel only credits that
  // state's low rate, so it barely offsets the high-tax miles you ran.
  List<Widget> _iftaBreakdownWidgets() {
    final burned = {for (final e in _stateGallons) e.key.toUpperCase(): e.value};
    final bought = _boughtByState();
    final states = <String>{
      ...burned.keys,
      ...bought.keys.where((k) => k.isNotEmpty),
    }.toList()
      ..sort();

    final out = <Widget>[
      const SizedBox(height: 8),
      _iftaRow4('St', 'Bought', 'Owe', 'Credit', header: true),
      Divider(height: 10, color: Colors.grey[300]),
    ];
    double totOwe = 0, totCredit = 0, totBought = 0;
    bool anySurcharge = false;
    for (final st in states) {
      final b = burned[st] ?? 0;
      final bt = bought[st] ?? 0;
      final rate = _iftaRate[st] ?? 0;
      final sur = _iftaSurcharge[st] ?? 0;
      if (sur > 0) anySurcharge = true;
      final owe = b * (rate + sur);
      final credit = bt * rate;
      totOwe += owe;
      totCredit += credit;
      totBought += bt;
      out.add(_iftaRow4(
        '$st${sur > 0 ? '*' : ''}',
        bt > 0 ? '${bt.toStringAsFixed(0)}g' : '—',
        owe > 0 ? _money(owe, dp: 0) : '—',
        credit > 0 ? _money(credit, dp: 0) : '—',
      ));
    }
    final untagged = bought[''] ?? 0;
    if (untagged > 0) {
      totBought += untagged;
      out.add(_iftaRow4('?', '${untagged.toStringAsFixed(0)}g', '—', '—'));
    }
    out.add(Divider(height: 10, color: Colors.grey[300]));
    out.add(_iftaRow4('Tot', totBought > 0 ? '${totBought.toStringAsFixed(0)}g' : '—',
        _money(totOwe, dp: 0), totCredit > 0 ? _money(totCredit, dp: 0) : '—',
        bold: true));
    out.add(const SizedBox(height: 6));
    final prepaid = totCredit >= totOwe && totCredit > 0;
    out.add(Text(
      (prepaid
              ? 'Your pump credit covers what you owe on this load, so nothing\'s '
                  'deducted here. Any overpayment comes back on your quarterly IFTA '
                  'filing — not this check.'
              : 'You owe each state\'s tax on the fuel you burn there — no matter '
                  'where you bought it. Buying cheap in a low-tax state only credits '
                  'that state\'s low rate, so it barely offsets your high-tax miles.') +
          (untagged > 0 ? ' Tag fuel receipts by state to credit them.' : '') +
          (anySurcharge ? ' (* state charges an extra surcharge.)' : ''),
      style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.3),
    ));
    return out;
  }

  Widget _iftaRow4(String a, String b, String c, String d,
      {bool header = false, bool bold = false}) {
    final base = TextStyle(
        fontSize: 12, fontWeight: (header || bold) ? FontWeight.w700 : FontWeight.normal);
    final grey = base.copyWith(color: header ? Colors.grey[700] : Colors.grey[800]);
    final oweStyle = base.copyWith(color: header ? Colors.grey[700] : Colors.orange[800]);
    final credStyle = base.copyWith(color: header ? Colors.grey[700] : Colors.green[700]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text(a, style: grey)),
          Expanded(child: Text(b, style: grey, textAlign: TextAlign.right)),
          const SizedBox(width: 6),
          Expanded(child: Text(c, style: oweStyle, textAlign: TextAlign.right)),
          const SizedBox(width: 6),
          Expanded(child: Text(d, style: credStyle, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  // Same per-state IFTA proof, rendered for the PDF so the itemization prints —
  // useful if a carrier deducts your shortfalls but conveniently forgets your
  // credits.
  List<pw.Widget> _pIftaBreakdown() {
    final burned = {for (final e in _stateGallons) e.key.toUpperCase(): e.value};
    final bought = _boughtByState();
    final states = <String>{
      ...burned.keys,
      ...bought.keys.where((k) => k.isNotEmpty),
    }.toList()
      ..sort();
    final out = <pw.Widget>[
      pw.SizedBox(height: 4),
      _pIftaRow4('St', 'Bought', 'Owe', 'Credit', header: true),
      _pDivider(),
    ];
    double totOwe = 0, totCredit = 0, totBought = 0;
    bool anySur = false;
    for (final st in states) {
      final b = burned[st] ?? 0;
      final bt = bought[st] ?? 0;
      final rate = _iftaRate[st] ?? 0;
      final sur = _iftaSurcharge[st] ?? 0;
      if (sur > 0) anySur = true;
      final owe = b * (rate + sur);
      final credit = bt * rate;
      totOwe += owe;
      totCredit += credit;
      totBought += bt;
      out.add(_pIftaRow4(
        '$st${sur > 0 ? '*' : ''}',
        bt > 0 ? '${bt.toStringAsFixed(0)}g' : '-',
        owe > 0 ? _money(owe, dp: 0) : '-',
        credit > 0 ? _money(credit, dp: 0) : '-',
      ));
    }
    final untagged = bought[''] ?? 0;
    if (untagged > 0) {
      totBought += untagged;
      out.add(_pIftaRow4('?', '${untagged.toStringAsFixed(0)}g', '-', '-'));
    }
    out.add(_pDivider());
    out.add(_pIftaRow4('Tot', totBought > 0 ? '${totBought.toStringAsFixed(0)}g' : '-',
        _money(totOwe, dp: 0), totCredit > 0 ? _money(totCredit, dp: 0) : '-',
        bold: true));
    out.add(pw.SizedBox(height: 3));
    final prepaid = totCredit >= totOwe && totCredit > 0;
    out.add(pw.Text(
      (prepaid
              ? 'Your pump credit covers what you owe on this load, so nothing is '
                  'deducted here. Any overpayment comes back on your quarterly IFTA '
                  'filing, not this check.'
              : 'You owe each state\'s tax on the fuel you burn there, no matter '
                  'where you bought it. Buying cheap in a low-tax state only credits '
                  'that state\'s low rate.') +
          (anySur ? ' (* state charges an extra surcharge.)' : ''),
      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
    ));
    return out;
  }

  pw.Widget _pIftaRow4(String a, String b, String c, String d,
      {bool header = false, bool bold = false}) {
    final w = (header || bold) ? pw.FontWeight.bold : pw.FontWeight.normal;
    pw.Widget cell(String t, PdfColor col) => pw.Expanded(
          child: pw.Text(_ascii(t),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 9, fontWeight: w, color: col)),
        );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        children: [
          pw.SizedBox(
              width: 34,
              child: pw.Text(_ascii(a),
                  style: pw.TextStyle(fontSize: 9, fontWeight: w, color: PdfColors.grey800))),
          cell(b, PdfColors.grey800),
          cell(c, header ? PdfColors.grey700 : PdfColors.orange800),
          cell(d, header ? PdfColors.grey700 : PdfColors.green700),
        ],
      ),
    );
  }

  Widget _fuelCard() {
    final t = _trip!;
    final fuelCost = _n(t['estimated_fuel_cost']) ?? _n(_ej['totalFuelCost']);
    final price = _n(t['fuel_price_used']) ?? _n(_ej['fuelPriceUsed']);
    final expectedGal = (fuelCost != null && price != null && price > 0) ? fuelCost / price : null;
    final total = _n(t['total_miles']) ?? _n(_ej['totalMiles']);

    double boughtGal = 0;
    for (final e in _expenses) {
      final cat = _str(e['category']).toLowerCase();
      if (cat.contains('fuel') || cat.contains('diesel')) {
        boughtGal += _n(e['gallons']) ?? 0;
      }
    }
    final actualMpg = (total != null && boughtGal > 0) ? total / boughtGal : null;

    final rows = <Widget>[];
    if (expectedGal != null) {
      rows.add(_row('Expected burn', '${expectedGal.toStringAsFixed(0)} gal (${_money(fuelCost)})'));
    }
    rows.add(_row('Gallons bought', boughtGal > 0 ? boughtGal.toStringAsFixed(1) : 'none logged'));
    if (actualMpg != null) {
      rows.add(_row('Actual MPG', actualMpg.toStringAsFixed(2), bold: true));
    } else {
      rows.add(_row('Actual MPG', 'log fuel gallons to calc'));
    }

    // Per-state burn if the load stored it.
    final byState = _gallonsByState(expectedGal);
    if (byState.isNotEmpty) {
      rows.add(const Divider());
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('Est. gallons by state',
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ));
      for (final e in byState) {
        rows.add(_row(e.key, '${e.value.toStringAsFixed(1)} gal'));
      }
    }

    // What you've actually BOUGHT per state (from the receipts) — the other
    // half of IFTA, and what tells you if you've fueled enough in a state.
    final bought = _boughtByState();
    final boughtTagged = bought.entries.where((e) => e.key.isNotEmpty).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final boughtUntagged = bought[''] ?? 0;
    if (boughtTagged.isNotEmpty || boughtUntagged > 0) {
      rows.add(const Divider());
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('Gallons bought by state',
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ));
      for (final e in boughtTagged) {
        rows.add(_row(e.key, '${e.value.toStringAsFixed(1)} gal'));
      }
      if (boughtUntagged > 0) {
        rows.add(_row('No state tagged', '${boughtUntagged.toStringAsFixed(1)} gal'));
      }
    }
    return _card('FUEL', rows);
  }

  Widget _receiptsCard() {
    final byCat = <String, double>{};
    double total = 0;
    for (final e in _expenses) {
      if (e['is_advance'] == true) continue; // advances aren't expenses, shown in settlement
      final cat = _str(e['category']).isEmpty ? 'Other' : _str(e['category']);
      final amt = _n(e['amount']) ?? 0;
      byCat[cat] = (byCat[cat] ?? 0) + amt;
      total += amt;
    }
    final advances = _advanceTotal();
    final rows = <Widget>[];
    if (byCat.isEmpty) {
      rows.add(_row('—', 'no receipts on this load'));
    } else {
      final entries = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final e in entries) {
        rows.add(_row(e.key, _money(e.value, dp: 2)));
      }
      rows.add(const Divider());
      rows.add(_row('Total expenses', _money(total, dp: 2), bold: true));
      rows.add(_row('Reimbursable (in settlement)', _money(_reimbursableTotal(), dp: 2),
          valueColor: Colors.green[800]));
    }
    if (advances > 0) {
      rows.add(const SizedBox(height: 4));
      rows.add(_row('Cash advances (deducted from check)', _money(advances, dp: 2),
          valueColor: Colors.orange[800]));
    }
    return _card('RECEIPTS', rows);
  }

  Widget _documentsCard() {
    const labels = {
      'ratecon': 'Rate Confirmation',
      'bol': 'Bill of Lading',
      'pod': 'Proof of Delivery',
      'permit': 'Oversize Permit',
      'other': 'Other Document',
    };
    final rows = <Widget>[];
    if (_docs.isEmpty) {
      rows.add(_row('—', 'no documents attached'));
    } else {
      for (final d in _docs) {
        final type = labels[_str(d['doc_type'])] ?? _str(d['doc_type']);
        final ref = _str(d['reference']);
        final onPhone = _str(d['storage_path']).isEmpty;
        final note = [if (ref.isNotEmpty) 'Ref $ref', if (onPhone) 'on phone'].join(' \u00b7 ');
        rows.add(_row(type, note.isEmpty ? '\u2713' : note));
      }
    }
    return _card('DOCUMENTS', rows);
  }

  // ─────────────────────────────  SHARE / PDF  ─────────────────────────────

  static const _docTypeLabels = {
    'ratecon': 'Rate Confirmation',
    'bol': 'Bill of Lading',
    'pod': 'Proof of Delivery',
    'permit': 'Oversize Permit',
    'other': 'Other Document',
  };

  // Document/receipt images still in the cloud (storage path set). Phone-only
  // images (aged out of cloud) can't be embedded — they live on your device.
  List<Map<String, String>> _attachableImages() {
    final out = <Map<String, String>>[];
    for (final e in _expenses) {
      final path = _str(e['receipt_url']);
      if (path.isEmpty) continue;
      final advance = e['is_advance'] == true;
      final cat = _str(e['category']);
      out.add({'path': path, 'label': advance ? 'Cash Advance Slip' : (cat.isEmpty ? 'Receipt' : cat)});
    }
    for (final d in _docs) {
      final path = _str(d['storage_path']);
      if (path.isEmpty) continue;
      final type = _docTypeLabels[_str(d['doc_type'])] ?? _str(d['doc_type']);
      final ref = _str(d['reference']);
      out.add({'path': path, 'label': ref.isEmpty ? type : '$type  \u00b7  Ref $ref'});
    }
    return out;
  }

  // Modal that makes the driver enter a PRO# before the sheet can be sent.
  // Returns the entered PRO# on success, or null if he cancelled. Saves it to
  // the trip and refreshes _trip so the PDF picks it up.
  Future<String?> _promptForPro() async {
    final ctrl = TextEditingController();
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('PRO # needed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your carrier lists settlements and fuel tickets by PRO #. '
                'Add it before you send this trip sheet.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Carrier PRO #',
                  hintText: 'e.g. 20260006',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (v.isEmpty) {
                  setLocal(() => errorText = 'Enter a PRO # to continue');
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: const Text('Save & continue'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return null;

    // Persist it. PRO# is uniquely indexed, so catch a collision and reprompt.
    try {
      await _supabase
          .from('trips')
          .update({'pro_number': result}).eq('id', _trip!['id']);
      setState(() => _trip!['pro_number'] = result);
      return result;
    } on PostgrestException catch (e) {
      final msg = '${e.message} ${e.details ?? ''}';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg.contains('trips_user_pro_number')
              ? 'That PRO # is already on another load. Use a different one.'
              : 'Could not save PRO #: ${e.message}'),
          backgroundColor: Colors.red,
        ));
      }
      return null; // don't send with an unsaved/duplicate PRO#
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save PRO #: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    }
  }

  Future<void> _sharePdf() async {
    if (_trip == null) return;

    // The carrier tracks fuel tickets by PRO#/carrier#, so a trip sheet without
    // one is useless to them. This is the moment we make it mandatory: if there's
    // no PRO# yet, make him enter one before the sheet can go out.
    final existingPro = (_trip!['pro_number'] ?? '').toString().trim();
    if (existingPro.isEmpty) {
      final entered = await _promptForPro();
      if (entered == null) return; // cancelled — don't send
    }

    final images = _attachableImages();
    var attach = false;

    if (images.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Share trip sheet'),
          content: Text(
              'Attach the ${images.length} supporting document${images.length == 1 ? '' : 's'} '
              '(receipts, BOL, POD, slips) to the PDF?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'summary'), child: const Text('Summary only')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, 'full'), child: const Text('Attach docs')),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      attach = choice == 'full';
    }

    // Building with images means network fetches — show a blocker.
    var loaderUp = false;
    if (attach && mounted) {
      loaderUp = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final bytes = await _buildPdf(attachImages: attach ? images : const []);
      if (loaderUp && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loaderUp = false;
      }
      final raw = _str(_trip!['trip_name']);
      final safe = raw.isEmpty
          ? 'load'
          : raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
      await Printing.sharePdf(bytes: bytes, filename: 'trip-sheet-$safe.pdf');
    } catch (e) {
      if (loaderUp && mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create PDF: $e')),
        );
      }
    }
  }

  // The PDF font is Latin-only, so any fancy Unicode (arrows, em/en dashes,
  // bullets, middots, minus sign) renders as a missing-glyph box. Fold them to
  // plain ASCII for anything we draw into the PDF.
  String _ascii(String s) => s
      .replaceAll('\u2192', ' to ') // →
      .replaceAll('\u2014', ' - ') // —
      .replaceAll('\u2013', '-') // –
      .replaceAll('\u2212', '-') // −
      .replaceAll('\u2022', '-') // •
      .replaceAll('\u00b7', '-') // ·
      .replaceAll('  ', ' ')
      .trim();

  pw.Widget _pRow(String label, String value, {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(_ascii(label), style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ),
          pw.SizedBox(width: 12),
          pw.Text(_ascii(value),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color,
              )),
        ],
      ),
    );
  }

  pw.Widget _pCard(String title, List<pw.Widget> rows, {PdfColor? accent}) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(_ascii(title),
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: accent ?? PdfColors.blueGrey700)),
          pw.SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }

  pw.Widget _pDivider() =>
      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Divider(height: 1, thickness: 0.5));

  Future<Uint8List> _buildPdf({List<Map<String, String>> attachImages = const []}) async {
    final doc = pw.Document();
    final t = _trip!;
    final p = _profile ?? {};

    // ── Authority ──
    final authRows = <pw.Widget>[];
    void authRow(String label, String key) {
      final v = _str(p[key]);
      if (v.isNotEmpty) authRows.add(_pRow(label, v));
    }
    authRow('Operator', 'operator_name');
    authRow('MC #', 'mc_number');
    authRow('DOT #', 'dot_number');
    authRow('Leased to', 'carrier_name');
    if (authRows.isEmpty) authRows.add(_pRow('—', 'no authority on file'));

    // ── Load ──
    final loadRows = <pw.Widget>[
      _pRow('Route',
          '${_str(t['origin']).isEmpty ? '?' : _str(t['origin'])}  \u2192  ${_str(t['destination']).isEmpty ? '?' : _str(t['destination'])}',
          bold: true),
    ];
    void loadRef(String label, String key) {
      final v = _str(t[key]);
      if (v.isNotEmpty) loadRows.add(_pRow(label, v));
    }
    if (_str(t['trip_date']).isNotEmpty) loadRows.add(_pRow('Load date', _str(t['trip_date'])));
    loadRef('Broker / TQL #', 'broker_number');
    loadRef('Pickup #', 'pickup_number');
    loadRef('BOL #', 'bol_number');
    loadRef('PRO #', 'pro_number');
    if (_truckLabel != null) loadRows.add(_pRow('Truck', _truckLabel!));
    if (_trailerLabel != null) loadRows.add(_pRow('Trailer', _trailerLabel!));

    // ── Settlement ──
    final gross = _n(t['agreed_gross']) ?? _n(t['quoted_gross']) ?? _n(t['offer_gross']) ?? _n(t['gross_pay']) ?? _n(_ej['bookedGross']) ?? _n(_ej['quotedGross']);
    final carrierPct = _n(t['carrier_cut_pct_at_time']) ?? _n(_ej['carrierCutPct']);
    final hisShare = (gross != null && carrierPct != null) ? gross * (1 - carrierPct / 100) : null;
    final reimb = _reimbursableTotal();
    final cardFuel = _carrierCardFuel();
    final advances = _advanceTotal();
    final ifta = _estIfta();
    final expectedCheck = hisShare != null
        ? hisShare + reimb - cardFuel - advances - ifta.tax
        : null;

    final setRows = <pw.Widget>[_pRow('Load gross', _money(gross))];
    if (hisShare != null) {
      final keepPct = carrierPct != null ? (100 - carrierPct).toStringAsFixed(0) : '?';
      setRows.add(_pRow('Your share ($keepPct% after carrier cut)', _money(hisShare)));
    }
    setRows.add(_pRow('+ Reimbursable expenses', _money(reimb, dp: 2)));
    if (cardFuel > 0) setRows.add(_pRow('- Fuel on carrier card', '-${_money(cardFuel, dp: 2)}', color: PdfColors.orange800));
    if (advances > 0) setRows.add(_pRow('- Cash advances', '-${_money(advances, dp: 2)}', color: PdfColors.orange800));
    if (_stateGallons.isNotEmpty && _iftaRate.isNotEmpty) {
      final prepaid = ifta.tax <= 0;
      setRows.add(_pRow(
          prepaid
              ? 'Fuel tax (IFTA) - prepaid'
              : '- Est. fuel tax (IFTA${ifta.worstCase ? ', worst case' : ''})',
          prepaid ? '\$0.00' : '-${_money(ifta.tax, dp: 2)}',
          color: prepaid ? PdfColors.green700 : PdfColors.orange800));
      setRows.addAll(_pIftaBreakdown());
    }
    setRows.add(_pDivider());
    setRows.add(_pRow('EXPECTED CHECK', _money(expectedCheck), bold: true, color: PdfColors.green800));
    setRows.add(pw.SizedBox(height: 4));
    setRows.add(pw.Text(
      (_stateGallons.isNotEmpty && _iftaRate.isNotEmpty)
          ? (ifta.worstCase
              ? _ascii('Fuel tax is a worst-case IFTA estimate, and assumes no fuel '
                  'bought on this load. Log state-tagged fuel receipts to lower it. '
                  'Still excludes insurance, ELD, trailer rent. Reconcile against your '
                  'settlement statement.')
              : _ascii('Fuel tax is an IFTA estimate - what you owe on the fuel you '
                  'burned, minus credit for fuel you bought. Still excludes insurance, '
                  'ELD, trailer rent. Reconcile against your settlement statement.'))
          : _ascii('Before any carrier-specific deductions (fuel tax, insurance, '
              'ELD, trailer rent). Reconcile against your settlement statement.'),
      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
    ));

    // ── Miles ──
    final loaded = _n(t['loaded_miles']);
    final deadhead = _n(t['deadhead_miles']);
    final totalMiles = _n(t['total_miles']) ?? _n(_ej['totalMiles']);
    final hours = _n(_ej['totalHours']);
    final mileRows = <pw.Widget>[];
    if (loaded != null) mileRows.add(_pRow('Loaded miles', loaded.round().toString()));
    if (deadhead != null) mileRows.add(_pRow('Deadhead miles', deadhead.round().toString()));
    if (totalMiles != null) mileRows.add(_pRow('Total miles', totalMiles.round().toString(), bold: true));
    if (hours != null) mileRows.add(_pRow('Total hours', hours.toStringAsFixed(1)));
    if (mileRows.isEmpty) mileRows.add(_pRow('—', 'no mileage on file'));

    // ── Fuel ──
    final fuelCost = _n(t['estimated_fuel_cost']) ?? _n(_ej['totalFuelCost']);
    final price = _n(t['fuel_price_used']) ?? _n(_ej['fuelPriceUsed']);
    final expectedGal = (fuelCost != null && price != null && price > 0) ? fuelCost / price : null;
    double boughtGal = 0;
    for (final e in _expenses) {
      final cat = _str(e['category']).toLowerCase();
      if (cat.contains('fuel') || cat.contains('diesel')) boughtGal += _n(e['gallons']) ?? 0;
    }
    final actualMpg = (totalMiles != null && boughtGal > 0) ? totalMiles / boughtGal : null;
    final fuelRows = <pw.Widget>[];
    if (expectedGal != null) {
      fuelRows.add(_pRow('Expected burn', '${expectedGal.toStringAsFixed(0)} gal (${_money(fuelCost)})'));
    }
    fuelRows.add(_pRow('Gallons bought', boughtGal > 0 ? boughtGal.toStringAsFixed(1) : 'none logged'));
    if (actualMpg != null) fuelRows.add(_pRow('Actual MPG', actualMpg.toStringAsFixed(2), bold: true));
    final fbGal = _gallonsByState(expectedGal);
    if (fbGal.isNotEmpty) {
      fuelRows.add(_pDivider());
      fuelRows.add(pw.Text('Est. gallons by state',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)));
      for (final e in fbGal) {
        fuelRows.add(_pRow(e.key, '${e.value.toStringAsFixed(1)} gal'));
      }
    }
    final pBought = _boughtByState();
    final pBoughtTagged = pBought.entries.where((e) => e.key.isNotEmpty).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final pBoughtUntagged = pBought[''] ?? 0;
    if (pBoughtTagged.isNotEmpty || pBoughtUntagged > 0) {
      fuelRows.add(_pDivider());
      fuelRows.add(pw.Text('Gallons bought by state',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)));
      for (final e in pBoughtTagged) {
        fuelRows.add(_pRow(e.key, '${e.value.toStringAsFixed(1)} gal'));
      }
      if (pBoughtUntagged > 0) {
        fuelRows.add(_pRow('No state tagged', '${pBoughtUntagged.toStringAsFixed(1)} gal'));
      }
    }

    // ── Receipts ──
    final byCat = <String, double>{};
    double rTotal = 0;
    for (final e in _expenses) {
      if (e['is_advance'] == true) continue;
      final cat = _str(e['category']).isEmpty ? 'Other' : _str(e['category']);
      final amt = _n(e['amount']) ?? 0;
      byCat[cat] = (byCat[cat] ?? 0) + amt;
      rTotal += amt;
    }
    final recRows = <pw.Widget>[];
    if (byCat.isEmpty) {
      recRows.add(_pRow('—', 'no receipts on this load'));
    } else {
      final entries = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final e in entries) {
        recRows.add(_pRow(e.key, _money(e.value, dp: 2)));
      }
      recRows.add(_pDivider());
      recRows.add(_pRow('Total expenses', _money(rTotal, dp: 2), bold: true));
      recRows.add(_pRow('Reimbursable (in settlement)', _money(reimb, dp: 2), color: PdfColors.green800));
    }
    if (advances > 0) {
      recRows.add(_pRow('Cash advances (deducted from check)', _money(advances, dp: 2), color: PdfColors.orange800));
    }

    // ── Documents ──
    const docLabels = {
      'ratecon': 'Rate Confirmation',
      'bol': 'Bill of Lading',
      'pod': 'Proof of Delivery',
      'permit': 'Oversize Permit',
      'other': 'Other Document',
    };
    final docRows = <pw.Widget>[];
    if (_docs.isEmpty) {
      docRows.add(_pRow('—', 'no documents attached'));
    } else {
      for (final d in _docs) {
        final type = docLabels[_str(d['doc_type'])] ?? _str(d['doc_type']);
        final ref = _str(d['reference']);
        docRows.add(_pRow(type, ref.isEmpty ? '\u2713' : 'Ref $ref'));
      }
    }

    final genDate = DateTime.now().toString().split(' ').first;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('TRIP SHEET', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text(_str(t['trip_name']), style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            ]),
            pw.Text('Generated $genDate', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 1),
        pw.SizedBox(height: 8),
        _pCard('AUTHORITY', authRows),
        _pCard('LOAD', loadRows),
        _pCard('SETTLEMENT — YOUR CHECK', setRows, accent: PdfColors.green800),
        _pCard('MILES', mileRows),
        _pCard('FUEL', fuelRows),
        _pCard('RECEIPTS', recRows),
        _pCard('DOCUMENTS', docRows),
      ],
    ));

    // Append each supporting document image as its own page.
    for (final img in attachImages) {
      final path = img['path'];
      if (path == null || path.isEmpty) continue;
      try {
        final bytes = await _supabase.storage.from('receipts').download(path);
        final image = pw.MemoryImage(bytes);
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(36),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(img['label'] ?? 'Document',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Expanded(child: pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))),
            ],
          ),
        ));
      } catch (_) {
        // Couldn't fetch (purged or offline) — skip; it's still listed on the summary.
      }
    }

    return doc.save();
  }
}
