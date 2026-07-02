// lib/quote/ugly_truth_screen.dart
//
// The Ugly Truth — fast "should I take this load?" gut-check.
//
// PHASE 1 (keyboard): From (GPS) -> Pickup -> Delivery -> Offer -> RUN.
//   Run pulls miles from Google Directions, hides the keyboard for good.
// PHASE 2 (sliders only): two bars race — the OFFER vs WHERE IT GOES. Drag
//   the levers that actually move (your hourly bar, the clock, detention).
//   Red verdict opens the exact counter-offer to ask the broker for.
//
// Same TruCostEngine as Quote a Load, so the numbers never disagree.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../engine/trucost_engine.dart';
import '../services/fuel_price_service.dart';
import '../services/location_service.dart';
import '../trips/load_details_screen.dart';

class UglyTruthScreen extends StatefulWidget {
  const UglyTruthScreen({super.key});

  @override
  State<UglyTruthScreen> createState() => _UglyTruthScreenState();
}

class _UglyTruthScreenState extends State<UglyTruthScreen> {
  final _supabase = Supabase.instance.client;
  final FuelPriceService _fuelSvc = FuelPriceService();

  // Phase 1 inputs
  final _pickupCtrl = TextEditingController();
  final _deliveryCtrl = TextEditingController();
  final _offerCtrl = TextEditingController();
  String _currentLocation = '';
  bool _gettingLocation = false;
  bool _calculating = false;
  String? _error;

  // Step 2: which job the driver is doing. null = show the picker first.
  //   'quote'    = no offer yet — find my number / what to ask for
  //   'evaluate' = a broker gave a price — take it or pass
  String? _mode;
  bool get _isQuote => _mode == 'quote';

  // computed by Run
  bool _hasRun = false;
  double _loadedMiles = 0;
  double _deadheadMiles = 0;
  double _offer = 0;

  // operator profile / equipment
  double _carrierCutPct = 25;
  double _overheadPct = 15;
  double _fscPct = 6;            // FSC as % of gross
  double _fscPctReceived = 100;  // % of FSC the operator keeps
  double _insPct = 3;            // carrier insurance as % of gross
  double _fuelPrice = 4.00;
  double _emptyMpg = 8;
  double _loadedMpg = 6;
  double _speedEmpty = 60;
  double _speedLoaded = 55;
  double _annualHours = 2500;
  double _hotelRate = 120;       // nightly hotel rate for non-sleeper trucks
  bool _hasSleeper = true;       // active truck has a sleeper berth → no hotels
  UnitCost _truck = UnitCost.owned(value: 140000);
  UnitCost _trailer = UnitCost.owned(value: 40000);

  // Phase 2 live levers
  double _hourlyRate = 50;
  double _loadUnloadHours = 2;
  double _detentionPerHour = 0;
  double _freeHours = 2;

  // When true, we preview the load at the minimum gross needed to hit the bar,
  // instead of the broker's real offer. This is a what-if view only — booking
  // always uses the real offer.
  bool _previewMinimum = false;
  bool _booking = false;

  bool _loadingDefaults = true;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _deliveryCtrl.dispose();
    _offerCtrl.dispose();
    super.dispose();
  }

  double _toDouble(dynamic v, double fallback) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  Future<void> _loadDefaults() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _loadingDefaults = false);
        return;
      }
      final p = await _supabase
          .from('profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      if (p != null) {
        _carrierCutPct = _toDouble(p['carrier_cut_pct'], 25);
        _overheadPct = _toDouble(p['overhead_pct'], 15);
        _fscPct = _toDouble(p['fsc_rate'], 6);
        _fscPctReceived = _toDouble(p['fsc_pct_received'], 100);
        _insPct = _toDouble(p['carrier_insurance_pct'], 3);
        _fuelPrice = _toDouble(p['fuel_price_default'], 4.00);
        _hotelRate = _toDouble(p['hotel_rate'], 120);
        _emptyMpg = _toDouble(p['empty_mpg'], 8);
        _loadedMpg = _toDouble(p['loaded_mpg'], 6);
        _speedEmpty = _toDouble(p['speed_empty'], 60);
        _speedLoaded = _toDouble(p['speed_loaded'], 55);
        _hourlyRate = _toDouble(p['hourly_rate'], 50);
        _annualHours = _toDouble(p['annual_work_hours'], 2500);
      }
      final trucks = await _supabase
          .from('units')
          .select()
          .eq('user_id', user.id)
          .eq('unit_type', 'truck')
          .eq('is_active', true)
          .limit(1);
      if (trucks.isNotEmpty) {
        final t = trucks[0];
        _truck = UnitCost(
          mode: t['cost_mode'] == 'financed' ? CostMode.financed : CostMode.owned,
          purchasePrice: _toDouble(t['purchase_price'], 0),
          depreciationRate: _toDouble(t['depreciation_pct'], 20) / 100,
          monthlyPayment: _toDouble(t['monthly_payment'], 0),
        );
        _emptyMpg = _toDouble(t['empty_mpg'], _emptyMpg);
        _loadedMpg = _toDouble(t['loaded_mpg'], _loadedMpg);
        _speedEmpty = _toDouble(t['speed_empty'], _speedEmpty);
        _speedLoaded = _toDouble(t['speed_loaded'], _speedLoaded);
        _hasSleeper = t['has_sleeper_berth'] == true;
      }
      final trailers = await _supabase
          .from('units')
          .select()
          .eq('user_id', user.id)
          .eq('unit_type', 'trailer')
          .eq('is_active', true)
          .limit(1);
      if (trailers.isNotEmpty) {
        final t = trailers[0];
        _trailer = UnitCost(
          mode: t['cost_mode'] == 'financed' ? CostMode.financed : CostMode.owned,
          purchasePrice: _toDouble(t['purchase_price'], 0),
          depreciationRate: _toDouble(t['depreciation_pct'], 20) / 100,
          monthlyPayment: _toDouble(t['monthly_payment'], 0),
        );
      }
      try {
        await _fuelSvc.loadPrices();
        if (_fuelSvc.nationalAverage > 0) _fuelPrice = _fuelSvc.nationalAverage;
      } catch (_) {}
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingDefaults = false);
    }
  }

  Future<void> _getGps() async {
    setState(() {
      _gettingLocation = true;
      _error = null;
    });
    try {
      final latLng = await LocationService.getLatLngString();
      setState(() {
        _currentLocation = latLng;
        _gettingLocation = false;
      });
    } on LocationException catch (e) {
      setState(() {
        _error = e.message;
        _gettingLocation = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not get location: $e';
        _gettingLocation = false;
      });
    }
  }

  Future<void> _run() async {
    FocusScope.of(context).unfocus();
    final pickup = _pickupCtrl.text.trim();
    final delivery = _deliveryCtrl.text.trim();
    final offer = double.tryParse(_offerCtrl.text.trim());

    if (pickup.isEmpty || delivery.isEmpty) {
      setState(() => _error = 'Enter pickup and delivery.');
      return;
    }
    if (!_isQuote && (offer == null || offer <= 0)) {
      setState(() => _error = 'Enter the broker\'s offer.');
      return;
    }

    setState(() {
      _calculating = true;
      _error = null;
    });

    try {
      final useWaypoint = _currentLocation.isNotEmpty;
      final origin = useWaypoint ? _currentLocation : pickup;
      final url = useWaypoint
          ? Uri.parse('https://maps.googleapis.com/maps/api/directions/json'
              '?origin=${Uri.encodeComponent(origin)}'
              '&destination=${Uri.encodeComponent(delivery)}'
              '&waypoints=${Uri.encodeComponent(pickup)}'
              '&key=$googleMapsKey')
          : Uri.parse('https://maps.googleapis.com/maps/api/directions/json'
              '?origin=${Uri.encodeComponent(pickup)}'
              '&destination=${Uri.encodeComponent(delivery)}'
              '&key=$googleMapsKey');

      final resp = await http.get(url);
      final data = json.decode(resp.body);
      if (data['status'] != 'OK') {
        setState(() {
          _error = 'Google API error: ${data['status']}. Check the addresses.';
          _calculating = false;
        });
        return;
      }

      final legs = data['routes'][0]['legs'] as List;
      double deadhead = 0;
      double loaded;
      if (useWaypoint) {
        deadhead = (legs[0]['distance']['value'] as int) / 1609.34;
        loaded = (legs[1]['distance']['value'] as int) / 1609.34;
      } else {
        loaded = (legs[0]['distance']['value'] as int) / 1609.34;
      }

      setState(() {
        _deadheadMiles = deadhead;
        _loadedMiles = loaded;
        _offer = _isQuote ? 0 : (offer ?? 0);
        _previewMinimum = _isQuote; // quote opens on your number, not an offer
        _hasRun = true;
        _calculating = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Route error: $e';
        _calculating = false;
      });
    }
  }

  void _reset() {
    setState(() {
      _hasRun = false;
      _error = null;
      _previewMinimum = false;
      _mode = null; // back to the Quote / Evaluate picker
      _offerCtrl.clear();
    });
  }

  double get _detentionPay {
    final over = _loadUnloadHours - _freeHours;
    if (over <= 0 || _detentionPerHour <= 0) return 0;
    return over * _detentionPerHour;
  }

  double get _effectiveGross => _offer + _detentionPay;

  TripResult _compute({double? grossOverride}) {
    return TruCostEngine.compute(TruCostInputs(
      deadheadMiles: _deadheadMiles,
      loadedMiles: _loadedMiles,
      tollsOtherCost: 0,
      grossPay: grossOverride ?? _effectiveGross,
      emptySpeed: _speedEmpty,
      loadedSpeed: _speedLoaded,
      emptyMpg: _emptyMpg,
      loadedMpg: _loadedMpg,
      dieselPricePerGallon: _fuelPrice,
      hourlyRate: _hourlyRate,
      loadUnloadHours: _loadUnloadHours,
      hasSleeper: _hasSleeper,
      hotelRate: _hotelRate,
      truck: _truck,
      trailer: _trailer,
      carrierCutPercent: _carrierCutPct / 100,
      overheadPercent: _overheadPct / 100,
      fscPercent: _fscPct / 100,
      fscPercentReceived: _fscPctReceived / 100,
      insurancePercent: _insPct / 100,
      annualWorkingHours: _annualHours,
    ));
  }

  String _usd(double v) => '\$${v.toStringAsFixed(0)}';

  /// The gross needed to clear the operator's bar at the current settings.
  /// Always computed from the real offer, so it's stable even while previewing.
  double get _minimumGross =>
      _compute(grossOverride: _effectiveGross).minimumGrossNeeded;

  /// The gross we actually display/draw: the real offer (plus detention), or
  /// the minimum if the user tapped "show me at the minimum" preview.
  double get _displayedGross =>
      (_previewMinimum || _isQuote) ? _minimumGross : _effectiveGross;

  /// Save this load as a quote-stage trip, then open Book This Load for it.
  /// Books at whatever gross is currently DISPLAYED (the real offer, or the
  /// target rate if previewing the minimum) — that becomes the agreed gross,
  /// which the booking screen lets him fine-tune before booking.
  Future<void> _takeIt() async {
    setState(() => _booking = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      final bookGross = _displayedGross; // real offer, or preview target
      final r = _compute(grossOverride: bookGross);
      final now = DateTime.now();
      final datePfx =
          '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.year}';
      final pickup = _pickupCtrl.text.trim();
      final delivery = _deliveryCtrl.text.trim();
      final routeLabel = (pickup.isNotEmpty && delivery.isNotEmpty)
          ? '$pickup to $delivery'
          : '${(_loadedMiles + _deadheadMiles).round()} mi';
      final name = '$datePfx - $routeLabel - ${_usd(bookGross)}';

      final inserted = await _supabase
          .from('trips')
          .insert({
            'user_id': user.id,
            'trip_name': name,
            'origin': pickup.isNotEmpty ? pickup : null,
            'destination': delivery.isNotEmpty ? delivery : null,
            'trip_date': now.toIso8601String().substring(0, 10),
            'deadhead_miles': _deadheadMiles,
            'loaded_miles': _loadedMiles,
            'fuel_price_used': _fuelPrice,
            'carrier_cut_pct_at_time': _carrierCutPct,
            'lease_status_at_time':
                _carrierCutPct > 0 ? 'leased' : 'independent',
            'offer_gross': _offer,           // broker's original offer (history)
            'quoted_gross': _minimumGross,   // what we asked for (the floor)
            'agreed_gross': bookGross,       // the number we're booking at
            'gross_pay': bookGross,
            // Flat headline columns — the Loads list reads these directly,
            // no JSON parsing, and they never move once written.
            'estimated_fuel_cost': r.totalFuelCost,
            'estimated_net': r.netToOperator,
            'net_to_operator': r.netToOperator,
            'effective_hourly': r.effectiveHourlyRate,
            'carrier_cut': r.carrierCut,
            'stage': _isQuote ? 'quoted' : 'booked',
            'status': 'saved',
            'booked_at': now.toIso8601String(),
            // FROZEN SNAPSHOT — everything needed to redraw the exact breakdown
            // downstream without recomputing. Rates are captured as-of now, so a
            // later profile change can't retroactively move a booked load.
            'estimate_json': {
              'schemaVersion': 2,
              'source': 'ugly_truth',
              'mode': _isQuote ? 'quote' : 'evaluate',
              'frozenAt': now.toIso8601String(),
              'bookedGross': bookGross,
              'offer': _offer,
              'floorGross': r.minimumGrossNeeded,
              'wasPreview': _previewMinimum,
              // The full "Where your money goes" waterfall, penny for penny.
              'breakdown': {
                'gross': r.grossPay,
                'insuranceAmount': r.insuranceAmount,
                'carrierCut': r.carrierCut,
                'operatorRevenue': r.operatorGross,
                'fscKept': r.fscAmount,
                'totalFuelCost': r.totalFuelCost,
                'equipmentCost': r.equipmentCost,
                'overheadCost': r.overheadCost,
                'hotelCost': r.hotelCost,
                'hotelNights': r.hotelNights,
                'tollsCost': r.tollsCost,
                'totalCosts': r.totalCosts,
                'netToOperator': r.netToOperator,
                'effectiveHourlyRate': r.effectiveHourlyRate,
                'totalMiles': r.totalMiles,
                'totalHours': r.totalHours,
              },
              // The rates in effect at book time — so labels and any re-derivation
              // use these, not whatever the profile says later.
              'rates': {
                'carrierCutPct': _carrierCutPct,
                'insurancePct': _insPct,
                'fscPct': _fscPct,
                'fscPctReceived': _fscPctReceived,
                'overheadPct': _overheadPct,
                'hotelRate': _hotelRate,
                'hasSleeper': _hasSleeper,
                'fuelPrice': _fuelPrice,
              },
              // The lever positions the driver settled on.
              'levers': {
                'hourlyBar': _hourlyRate,
                'loadUnloadHours': _loadUnloadHours,
                'freeHours': _freeHours,
                'detentionPerHour': _detentionPerHour,
                'detentionPay': _detentionPay,
              },
            },
          })
          .select('id')
          .single();

      final newId = inserted['id'].toString();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LoadDetailsScreen(tripId: newId)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingDefaults) {
      return Scaffold(
        appBar: AppBar(title: const Text('The Ugly Truth')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('The Ugly Truth')),
      body: _mode == null
          ? _buildModePicker()
          : _hasRun
              ? _buildSliderPhase()
              : _buildInputPhase(),
    );
  }

  Widget _modeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 34, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: color)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildModePicker() {
    const green = Color(0xFF2E7D32);
    const amber = Color(0xFFB26A00);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        const Text('What are you doing?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Same math either way — this just sets how the answer reads.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 20),
        _modeCard(
          icon: Icons.request_quote_outlined,
          title: 'Quote a load',
          subtitle: 'No price yet — find your number and what to ask for.',
          color: green,
          onTap: () => setState(() => _mode = 'quote'),
        ),
        const SizedBox(height: 14),
        _modeCard(
          icon: Icons.gavel_outlined,
          title: 'Evaluate a load',
          subtitle: 'They gave you a price — take it or pass.',
          color: amber,
          onTap: () => setState(() => _mode = 'evaluate'),
        ),
      ],
    );
  }

  Widget _buildInputPhase() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_isQuote ? 'Where to & how far' : 'Where & how much',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _mode = null;
                  _error = null;
                }),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: Text(_isQuote ? 'Quote' : 'Evaluate'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              _isQuote
                  ? 'Enter the lane, then get your number. After that it\'s all sliders.'
                  : 'Enter the load, then Run. After that it\'s all sliders.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _currentLocation.isNotEmpty
                        ? 'From: GPS set'
                        : 'From: no GPS — deadhead 0',
                    style: TextStyle(
                      fontSize: 14,
                      color: _currentLocation.isNotEmpty
                          ? Colors.green[700]
                          : Colors.grey[600],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _gettingLocation ? null : _getGps,
                icon: _gettingLocation
                    ? const SizedBox(
                        height: 16, width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 18),
                label: const Text('GPS'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pickupCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Pickup',
              hintText: 'City, State or full address',
              prefixIcon: Icon(Icons.local_shipping),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _deliveryCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Delivery',
              hintText: 'City, State or full address',
              prefixIcon: Icon(Icons.flag),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (!_isQuote) ...[
            TextField(
              controller: _offerCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Broker offered (\$)',
                hintText: 'What are they paying?',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
          ] else
            const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _calculating ? null : _run,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
            ),
            child: _calculating
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isQuote ? 'Get My Number' : 'Run the Numbers',
                    style: const TextStyle(fontSize: 18)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14)),
          ],
        ],
      ),
    );
  }

  Widget _buildSliderPhase() {
    // Compute against the displayed gross (real offer, or minimum if previewing).
    final r = _compute(grossOverride: _displayedGross);
    // Clearing the bar exactly counts as a win. The target gross is derived by
    // dividing, so feeding it back can land a hair under (e.g. $49.9999997);
    // a half-cent/hr tolerance keeps "exactly your bar" from reading as under.
    final wins = r.effectiveHourlyRate >= _hourlyRate - 0.005;
    final barGap = r.effectiveHourlyRate - _hourlyRate;
    final green = const Color(0xFF2E7D32);
    final red = const Color(0xFFC62828);
    final verdictColor = wins ? green : red;

    return Column(
      children: [
        // PINNED — stays on screen while the levers scroll beneath it, so the
        // green glow is visible the moment a load slides into range.
        _buildVerdictStrip(r, wins, barGap, green, red, verdictColor),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${_isQuote ? 'Quote' : '${_usd(_offer)} offer'}  ·  ${_loadedMiles.round()} loaded'
                      '${_deadheadMiles > 0 ? ' + ${_deadheadMiles.round()} dh' : ''} mi',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('New load'),
                  ),
                ],
              ),

        // Preview banner — only in evaluate mode, when showing the minimum
        // instead of the real offer. In quote mode the whole screen is the target.
        if (_previewMinimum && !_isQuote) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade700),
            ),
            child: Row(
              children: [
                Icon(Icons.visibility, size: 16, color: Colors.amber.shade900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Target view: ${_usd(_minimumGross)} — what you\'d need, not the real ${_usd(_offer)} offer.',
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _previewMinimum = false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 0),
                  ),
                  child: const Text('Back to offer', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),
        _UglyTruthBars(
          offer: r.grossPay,
          offerLabel: _isQuote ? 'Your Number' : 'The Offer',
          fuel: r.totalFuelCost,
          equipment: r.equipmentCost,
          overhead: r.overheadCost,
          carrierCut: r.carrierCut,
          takeHome: r.netToOperator,
          hourly: r.effectiveHourlyRate,
          wins: wins,
          green: green,
          red: red,
        ),
        const SizedBox(height: 8),

        // GREEN → book it. Evaluate mode books the offer (or the talked-up
        // target); quote mode books at your number. In quote mode we also show
        // the "what to ask for" card, since that's the whole point of a quote.
        if (wins) ...[
          if (_isQuote) ...[
            const SizedBox(height: 16),
            _buildCounterOffer(r, green),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _booking ? null : _takeIt,
              icon: _booking
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline),
              label: Text(_booking
                  ? 'Saving…'
                  : (_isQuote
                      ? 'Book at ${_usd(_displayedGross)} — My Number'
                      : 'Take It at ${_usd(_displayedGross)} — Book This Load')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor:
                    (_previewMinimum || _isQuote) ? const Color(0xFF00A152) : green,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],

        // RED → counter-offer + the "show me at the minimum" preview button.
        if (!wins) ...[
          const SizedBox(height: 16),
          _buildCounterOffer(r, green),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _previewMinimum = true),
              icon: const Icon(Icons.trending_up, size: 18),
              label: Text('Show me this load at ${_usd(_minimumGross)}'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: green,
                side: BorderSide(color: green),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),
        const Text('The levers you can actually pull',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Fuel, the iron, and overhead barely move. Your time and the clock are the negotiation.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        _slider(
          label: 'Your hourly bar',
          value: _hourlyRate, min: 20, max: 120,
          display: '${_usd(_hourlyRate)}/hr',
          onChanged: (v) => setState(() { _hourlyRate = v; _previewMinimum = false; }),
        ),
        _slider(
          label: 'Load + unload time',
          value: _loadUnloadHours, min: 0, max: 12, divisions: 24,
          display: '${_loadUnloadHours.toStringAsFixed(1)} hrs',
          onChanged: (v) => setState(() { _loadUnloadHours = v; _previewMinimum = false; }),
        ),
        _slider(
          label: 'Free hours before detention',
          value: _freeHours, min: 0, max: 12, divisions: 24,
          display: '${_freeHours.toStringAsFixed(1)} hrs',
          onChanged: (v) => setState(() { _freeHours = v; _previewMinimum = false; }),
        ),
        _slider(
          label: 'Detention pay',
          value: _detentionPerHour, min: 0, max: 150, divisions: 30,
          display: _detentionPerHour <= 0 ? 'none' : '${_usd(_detentionPerHour)}/hr',
          onChanged: (v) => setState(() { _detentionPerHour = v; _previewMinimum = false; }),
        ),
        if (_detentionPay > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Detention adds ${_usd(_detentionPay)} to the offer '
            '(${(_loadUnloadHours - _freeHours).toStringAsFixed(1)} hrs x ${_usd(_detentionPerHour)}/hr).',
            style: TextStyle(fontSize: 12, color: Colors.green[800]),
          ),
        ],
        // Hotel rate is a real lever when there's no sleeper: knock it down to a
        // cheaper room to make a tight load work, instead of walking away.
        if (!_hasSleeper) ...[
          _slider(
            label: 'Hotel rate',
            value: _hotelRate.clamp(40, 250).toDouble(), min: 40, max: 250, divisions: 42,
            display: '${_usd(_hotelRate)}/night',
            onChanged: (v) => setState(() { _hotelRate = v; _previewMinimum = false; }),
          ),
          Text(
            'Cheaper room, tighter load. Set what you\'d actually pay on this lane.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text('Where your money goes',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[700])),
                ],
              ),
              const SizedBox(height: 8),
              _flowRow('Gross', _money2(r.grossPay)),
              if (r.insuranceAmount > 0)
                _flowRow('Carrier insurance (${_insPct.round()}%)',
                    '- ${_money2(r.insuranceAmount)}'),
              _flowRow('Carrier cut (${_carrierCutPct.round()}% of line haul)',
                  '- ${_money2(r.carrierCut)}'),
              if (r.grossPay - r.operatorGross - r.insuranceAmount - r.carrierCut > 0.005)
                _flowRow('FSC kept by carrier',
                    '- ${_money2(r.grossPay - r.operatorGross - r.insuranceAmount - r.carrierCut)}'),
              _flowRow('Your revenue', _money2(r.operatorGross),
                  bold: true, color: Colors.green[800]),
              if (r.fscAmount > 0)
                _flowRow('incl. FSC you keep (${_fscPct.round()}%)',
                    _money2(r.fscAmount)),
              const Divider(height: 16),
              _flowRow('Fuel (avg ${_usd(_fuelPrice)}/gal)',
                  '- ${_money2(r.totalFuelCost)}'),
              _flowRow('Truck + trailer', '- ${_money2(r.equipmentCost)}'),
              _flowRow('Overhead (${_overheadPct.round()}%)',
                  '- ${_money2(r.overheadCost)}'),
              if (r.hotelCost > 0)
                _flowRow('Hotels (${r.hotelNights.round()} nt)',
                    '- ${_money2(r.hotelCost)}'),
              if (r.tollsCost > 0)
                _flowRow('Tolls / other', '- ${_money2(r.tollsCost)}'),
              _flowRow('Your net', _money2(r.netToOperator),
                  bold: true,
                  color: r.netToOperator >= 0 ? Colors.green[800] : Colors.red[700]),
              const Divider(height: 16),
              _flowRow('Total miles', '${r.totalMiles.round()} mi'),
              _flowRow('Total hours', '${r.totalHours.toStringAsFixed(1)} hrs'),
            ],
          ),
        ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  // Compact verdict that stays pinned at the top of the result while the levers
  // scroll beneath it — glows green the instant the load is within range.
  Widget _buildVerdictStrip(TripResult r, bool wins, double barGap,
      Color green, Color red, Color verdictColor) {
    final headline = _isQuote
        ? 'ASK FOR ${_usd(_minimumGross)}'
        : (wins ? 'TAKE IT' : 'WALK AWAY');
    final detail = _isQuote
        ? 'clears your ${_usd(_hourlyRate)}/hr bar'
        : (wins
            ? 'clears by ${_usd(barGap < 0 ? 0.0 : barGap)}/hr'
            : '${_usd(barGap > 0 ? 0.0 : -barGap)}/hr under');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: verdictColor.withOpacity(0.12),
        border: Border(bottom: BorderSide(color: verdictColor, width: 1.5)),
        boxShadow: wins
            ? [BoxShadow(color: green.withOpacity(0.45), blurRadius: 18, spreadRadius: 1)]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(headline,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: verdictColor,
                      letterSpacing: 0.5)),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${_usd(r.effectiveHourlyRate)}/hr  ·  ${_usd(r.netToOperator)}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: verdictColor)),
              Text(detail, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCounterOffer(TripResult r, Color green) {
    final operatorShare = 1 - (_carrierCutPct / 100);
    final breakEvenGross =
        operatorShare > 0 ? r.totalCosts / operatorShare : r.totalCosts;
    final barGross = r.minimumGrossNeeded;
    final addToHitBar = barGross - _offer;
    final totalMi = _loadedMiles + _deadheadMiles;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.handshake, size: 18, color: Colors.amber.shade900),
              const SizedBox(width: 6),
              Text('What to ask for',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.amber.shade900)),
            ],
          ),
          const SizedBox(height: 10),
          _askLine('Break even (cover costs)', breakEvenGross,
              totalMi > 0 ? '${_usd(breakEvenGross / totalMi)}/mi' : ''),
          const SizedBox(height: 6),
          _askLine('Hit your ${_usd(_hourlyRate)}/hr bar', barGross,
              totalMi > 0 ? '${_usd(barGross / totalMi)}/mi' : ''),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _isQuote
                  ? 'Quote this lane at ${_usd(barGross)} to clear your ${_usd(_hourlyRate)}/hr bar. Below ${_usd(breakEvenGross)} you\'re paying to haul it.'
                  : (addToHitBar > 0
                      ? '"${_usd(_offer)} doesn\'t work. I need ${_usd(barGross)} to run this right — that\'s ${_usd(addToHitBar)} more. Or hold the rate and get me loaded fast with detention after ${_freeHours.toStringAsFixed(0)} hrs."'
                      : 'You\'re close — tighten the clock or add detention and this one works.'),
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _askLine(String label, double gross, String perMile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text('${_usd(gross)}${perMile.isNotEmpty ? '  ·  $perMile' : ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text(display, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min, max: max, divisions: divisions,
            activeColor: const Color(0xFF2E7D32),
            onChanged: onChanged,
            // Commit the release position too. On a fast drag to an edge the
            // final onChanged tick can be dropped between frames, leaving a
            // stale value that snaps back on rebuild; onChangeEnd pins it.
            onChangeEnd: onChanged,
          ),
        ],
      ),
    );
  }

  String _money2(double v) => '\$${v.toStringAsFixed(2)}';

  Widget _flowRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: color ?? Colors.grey[700],
                  fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }

  Widget _fixedLine(String label, double v, {bool isMiles = false, bool isHours = false}) {
    final right = isMiles
        ? '${v.round()} mi'
        : isHours
            ? '${v.toStringAsFixed(1)} hrs'
            : _usd(v);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          Text(right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Two side-by-side bars: OFFER vs WHERE IT GOES. Uses Expanded/flex inside a
/// fixed-height box so segments can never overflow the container.
class _UglyTruthBars extends StatelessWidget {
  final double offer;
  final String offerLabel;
  final double fuel;
  final double equipment;
  final double overhead;
  final double carrierCut;
  final double takeHome;
  final double hourly;
  final bool wins;
  final Color green;
  final Color red;

  const _UglyTruthBars({
    required this.offer,
    this.offerLabel = 'The Offer',
    required this.fuel,
    required this.equipment,
    required this.overhead,
    required this.carrierCut,
    required this.takeHome,
    required this.hourly,
    required this.wins,
    required this.green,
    required this.red,
  });

  // Bright cost-stack palette — each slice a distinct color so the breakdown
  // reads at a glance instead of a gray blob.
  static const Color _cCarrier = Color(0xFFE53935); // bright red — gone off the top
  static const Color _cFuel = Color(0xFF2E7D32);    // diesel-pump green
  static const Color _cTruck = Color(0xFFFB8C00);   // orange — the iron
  static const Color _cOverhead = Color(0xFFFDD835); // yellow — overhead
  static const Color _cTakeHome = Color(0xFF00E676); // neon green — your money

  String _usd(double v) => '\$${v.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final drawnTakeHome = takeHome < 0 ? 0.0 : takeHome;
    final stackTotal = carrierCut + fuel + equipment + overhead + drawnTakeHome;
    final maxVal = offer > stackTotal ? offer : stackTotal;
    final safeMax = maxVal <= 0 ? 1.0 : maxVal;
    const barHeight = 240.0;

    int flex(double v) => (v / safeMax * 1000).round().clamp(0, 1000);
    final emptyOfferFlex = flex(safeMax - offer);
    final emptyStackFlex = flex(safeMax - stackTotal);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          SizedBox(
            height: barHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _barColumn(
                  totalLabel: _usd(offer),
                  hourlyLabel: null,
                  label: offerLabel,
                  topColor: const Color(0xFF2E7D32),
                  children: [
                    if (emptyOfferFlex > 0) Spacer(flex: emptyOfferFlex),
                    Expanded(flex: flex(offer), child: Container(color: const Color(0xFF66BB6A))),
                  ],
                ),
                _barColumn(
                  totalLabel: '${takeHome < 0 ? '-' : ''}${_usd(takeHome.abs())} My Net Take Home',
                  hourlyLabel: '${_usd(hourly)}/hr',
                  label: 'Where It Goes',
                  topColor: wins ? const Color(0xFF00A152) : red,
                  children: [
                    if (emptyStackFlex > 0) Spacer(flex: emptyStackFlex),
                    Expanded(flex: flex(drawnTakeHome), child: Container(color: wins ? _cTakeHome : red)),
                    Expanded(flex: flex(overhead), child: Container(color: _cOverhead)),
                    Expanded(flex: flex(equipment), child: Container(color: _cTruck)),
                    Expanded(flex: flex(fuel), child: Container(color: _cFuel)),
                    Expanded(flex: flex(carrierCut), child: Container(color: _cCarrier)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              _legend(_cCarrier, 'Carrier cut'),
              _legend(_cFuel, 'Fuel'),
              _legend(_cTruck, 'Truck/trailer'),
              _legend(_cOverhead, 'Overhead'),
              _legend(wins ? _cTakeHome : red, 'Your take-home'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _barColumn({
    required String totalLabel,
    required String? hourlyLabel,
    required String label,
    required Color topColor,
    required List<Widget> children,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(totalLabel,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: topColor)),
        if (hourlyLabel != null) ...[
          const SizedBox(height: 2),
          Text(hourlyLabel,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: topColor, height: 1.0)),
        ],
        const SizedBox(height: 4),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 70,
              child: Column(children: children),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _legend(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: c),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
      ],
    );
  }
}
