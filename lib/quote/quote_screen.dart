// lib/quote/quote_screen.dart
//
// Quote a Load — the inverse of the calculator. The broker asks "what'll you
// do this load for?" and this hands back the number to give them: the gross
// (and $/mile) that clears the operator's OWN hourly bar after every real cost
// and the carrier cut. Same TruCost engine — we read minimumGrossNeeded and
// scale it for negotiation room.
//
// Miles auto-pull from Google Directions (same call as Route a Load). GPS is
// optional and only fills the deadhead leg. An OUT-OF-ROUTE percent bumps the
// LOADED miles (Google runs a little short of real truck miles); it defaults to
// 0 and is selectable per quote. Fuel and hours recompute on the bumped miles.
//
// Owner-operator default: deadhead included. The switch flips to loaded-only.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../engine/trucost_engine.dart';
import '../services/fuel_price_service.dart';
import '../help/help_content.dart';
import '../contacts/contacts_screen.dart';
import 'saved_quotes_screen.dart';

class QuoteScreen extends StatefulWidget {
  final double? initialDeadhead;
  final double? initialLoaded;
  final String? initialOrigin;
  final String? initialDestination;

  const QuoteScreen({
    super.key,
    this.initialDeadhead,
    this.initialLoaded,
    this.initialOrigin,
    this.initialDestination,
  });

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> {
  final _supabase = Supabase.instance.client;

  late final TextEditingController _originCtrl;
  late final TextEditingController _destCtrl;
  late final TextEditingController _deadheadCtrl;
  late final TextEditingController _loadedCtrl;
  late final TextEditingController _tollsCtrl;
  late final TextEditingController _loadUnloadCtrl;

  double _carrierCutPct = 25;
  double _overheadPct = 15;
  double _fuelPrice = 4.00;
  double _emptyMpg = 8;
  double _loadedMpg = 6;
  double _speedEmpty = 60;
  double _speedLoaded = 55;
  double _hourlyRate = 50;
  double _annualHours = 2500;

  UnitCost _truck = UnitCost.owned(value: 140000);
  UnitCost _trailer = UnitCost.owned(value: 40000);
  String _truckLabel = 'Truck';
  String _trailerLabel = 'Trailer';
  final FuelPriceService _fuelSvc = FuelPriceService();
  String? _truckUnitId;
  String? _trailerUnitId;
  Map<String, dynamic>? _selectedBroker;

  bool _includeDeadhead = true; // owner-operator default
  double _outOfRoutePct = 0; // bumps LOADED miles; selectable per quote
  double _marginPct = 0; // padding above the floor (negotiation room)

  // Distance lookup (ported from route_screen).
  String _currentLocation = '';
  bool _gettingLocation = false;
  bool _calculatingRoute = false;
  String? _routeError;

  bool _loading = true;
  bool _saving = false;
  TripResult? _result; // computed at the floor (grossPay irrelevant)

  @override
  void initState() {
    super.initState();
    _originCtrl = TextEditingController(text: widget.initialOrigin ?? '');
    _destCtrl = TextEditingController(text: widget.initialDestination ?? '');
    _deadheadCtrl = TextEditingController(
      text: widget.initialDeadhead != null
          ? widget.initialDeadhead!.round().toString()
          : '',
    );
    _loadedCtrl = TextEditingController(
      text: widget.initialLoaded != null
          ? widget.initialLoaded!.round().toString()
          : '',
    );
    _tollsCtrl = TextEditingController(text: '0');
    _loadUnloadCtrl = TextEditingController(text: '8');
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final p = await _supabase
          .from('profiles')
          .select()
          .eq('user_id', user.id)
          .single();

      _carrierCutPct = _toDouble(p['carrier_cut_pct'], 25);
      _overheadPct = _toDouble(p['overhead_pct'], 15);
      _fuelPrice = _toDouble(p['fuel_price_default'], 4.00);
      _emptyMpg = _toDouble(p['empty_mpg'], 8);
      _loadedMpg = _toDouble(p['loaded_mpg'], 6);
      _speedEmpty = _toDouble(p['speed_empty'], 60);
      _speedLoaded = _toDouble(p['speed_loaded'], 55);
      _hourlyRate = _toDouble(p['hourly_rate'], 50);
      _annualHours = _toDouble(p['annual_work_hours'], 2500);

      final trucks = await _supabase
          .from('units')
          .select()
          .eq('user_id', user.id)
          .eq('unit_type', 'truck')
          .eq('is_active', true)
          .limit(1);

      if (trucks.isNotEmpty) {
        final t = trucks[0];
        _truckUnitId = t['id']?.toString();
        final unitNumber = (t['unit_number'] ?? '').toString();
        _truckLabel = unitNumber.isNotEmpty ? 'Truck $unitNumber' : 'Truck';
        _truck = UnitCost(
          mode: t['cost_mode'] == 'financed' ? CostMode.financed : CostMode.owned,
          purchasePrice: _toDouble(t['purchase_price'], 0),
          depreciationRate: _toDouble(t['depreciation_pct'], 20) / 100,
          monthlyPayment: _toDouble(t['monthly_payment'], 0),
        );
        // MPG and speed live on the truck — let it drive the math, falling back
        // to the profile/defaults loaded above if the truck hasn't set them.
        _emptyMpg = _toDouble(t['empty_mpg'], _emptyMpg);
        _loadedMpg = _toDouble(t['loaded_mpg'], _loadedMpg);
        _speedEmpty = _toDouble(t['speed_empty'], _speedEmpty);
        _speedLoaded = _toDouble(t['speed_loaded'], _speedLoaded);
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
        _trailerUnitId = t['id']?.toString();
        final subtype = (t['trailer_subtype'] ?? '').toString();
        final unitNumber = (t['unit_number'] ?? '').toString();
        _trailerLabel = unitNumber.isNotEmpty
            ? 'Trailer $unitNumber'
            : subtype.isNotEmpty
                ? subtype
                : 'Trailer';
        _trailer = UnitCost(
          mode: t['cost_mode'] == 'financed' ? CostMode.financed : CostMode.owned,
          purchasePrice: _toDouble(t['purchase_price'], 0),
          depreciationRate: _toDouble(t['depreciation_pct'], 20) / 100,
          monthlyPayment: _toDouble(t['monthly_payment'], 0),
        );
      }

      await _fuelSvc.loadPrices();
      final origin = _originCtrl.text.trim();
      final dest = _destCtrl.text.trim();
      if (origin.isNotEmpty || dest.isNotEmpty) {
        final deadhead = double.tryParse(_deadheadCtrl.text) ?? 0;
        final loaded = double.tryParse(_loadedCtrl.text) ?? 0;
        _fuelPrice = _fuelSvc.averageForRoute(
          pickupAddress: origin,
          deliveryAddress: dest,
          deadheadMiles: deadhead,
          loadedMiles: loaded,
        );
      } else if (_fuelSvc.nationalAverage > 0) {
        _fuelPrice = _fuelSvc.nationalAverage;
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    }
  }

  double _toDouble(dynamic v, double fallback) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  // ── Distance (Google Directions; ported from route_screen) ──

  Future<void> _getGpsLocation() async {
    setState(() {
      _gettingLocation = true;
      _routeError = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _routeError = 'Location services are off. Turn them on in Settings.';
          _gettingLocation = false;
        });
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _routeError = 'Location permission denied.';
            _gettingLocation = false;
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _routeError = 'Location permission permanently denied. Enable in Settings.';
          _gettingLocation = false;
        });
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      setState(() {
        _currentLocation = '${position.latitude},${position.longitude}';
        _gettingLocation = false;
      });
    } catch (e) {
      setState(() {
        _routeError = 'Could not get location: $e';
        _gettingLocation = false;
      });
    }
  }

  Future<void> _getMiles() async {
    final pickup = _originCtrl.text.trim();
    final delivery = _destCtrl.text.trim();
    if (pickup.isEmpty || delivery.isEmpty) {
      setState(() => _routeError = 'Enter both From and To to pull miles.');
      return;
    }
    final origin = _currentLocation.isNotEmpty ? _currentLocation : pickup;
    final useWaypoint = _currentLocation.isNotEmpty;

    setState(() {
      _calculatingRoute = true;
      _routeError = null;
    });

    try {
      final Uri url = useWaypoint
          ? Uri.parse(
              'https://maps.googleapis.com/maps/api/directions/json'
              '?origin=${Uri.encodeComponent(origin)}'
              '&destination=${Uri.encodeComponent(delivery)}'
              '&waypoints=${Uri.encodeComponent(pickup)}'
              '&key=$googleMapsKey')
          : Uri.parse(
              'https://maps.googleapis.com/maps/api/directions/json'
              '?origin=${Uri.encodeComponent(pickup)}'
              '&destination=${Uri.encodeComponent(delivery)}'
              '&key=$googleMapsKey');

      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data['status'] != 'OK') {
        setState(() {
          _routeError = 'Google API error: ${data['status']}. Check your addresses.';
          _calculatingRoute = false;
        });
        return;
      }

      final legs = data['routes'][0]['legs'] as List;
      double deadheadMi = 0;
      double loadedMi;
      if (useWaypoint) {
        deadheadMi = (legs[0]['distance']['value'] as int) / 1609.34;
        loadedMi = (legs[1]['distance']['value'] as int) / 1609.34;
      } else {
        loadedMi = (legs[0]['distance']['value'] as int) / 1609.34;
      }

      // Route-accurate fuel for this lane.
      final routeFuel = _fuelSvc.averageForRoute(
        pickupAddress: pickup,
        deliveryAddress: delivery,
        deadheadMiles: deadheadMi,
        loadedMiles: loadedMi,
      );

      setState(() {
        _deadheadCtrl.text = deadheadMi.round().toString();
        _loadedCtrl.text = loadedMi.round().toString();
        if (routeFuel > 0) _fuelPrice = routeFuel;
        _calculatingRoute = false;
      });

      if (_result != null) _calculate();
    } catch (e) {
      setState(() {
        _routeError = 'Route error: $e';
        _calculatingRoute = false;
      });
    }
  }

  // ── Engine ──

  double get _baseLoaded => double.tryParse(_loadedCtrl.text) ?? 0;
  double get _effectiveLoaded => _baseLoaded * (1 + _outOfRoutePct / 100);

  /// Engine inputs. Loaded miles carry the out-of-route bump; deadhead is
  /// zeroed when quoting loaded-only. grossPay is the unknown we solve for —
  /// pass 0 for the floor, or a candidate quote to preview the take-home.
  TruCostInputs _inputs({required double grossPay}) {
    final deadhead =
        _includeDeadhead ? (double.tryParse(_deadheadCtrl.text) ?? 0) : 0.0;
    final tolls = double.tryParse(_tollsCtrl.text) ?? 0;
    final loadUnload = double.tryParse(_loadUnloadCtrl.text) ?? 8;
    return TruCostInputs(
      grossPay: grossPay,
      deadheadMiles: deadhead,
      loadedMiles: _effectiveLoaded,
      tollsOtherCost: tolls,
      emptySpeed: _speedEmpty,
      loadedSpeed: _speedLoaded,
      emptyMpg: _emptyMpg,
      loadedMpg: _loadedMpg,
      dieselPricePerGallon: _fuelPrice,
      hourlyRate: _hourlyRate,
      loadUnloadHours: loadUnload,
      truck: _truck,
      trailer: _trailer,
      carrierCutPercent: _carrierCutPct / 100,
      overheadPercent: _overheadPct / 100,
      annualWorkingHours: _annualHours,
    );
  }

  void _calculate() {
    if (_baseLoaded <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Get miles (or enter loaded miles) to get a quote.')),
      );
      return;
    }
    setState(() => _result = TruCostEngine.compute(_inputs(grossPay: 0)));
    FocusScope.of(context).unfocus();
  }

  // Derived quote numbers.
  double get _floorGross => _result?.minimumGrossNeeded ?? 0;
  double get _quotedGross => _floorGross * (1 + _marginPct / 100);
  double get _loadedMiles => _result?.loadedMiles ?? 0;
  double get _totalMiles => _result?.totalMiles ?? 0;
  double get _perLoadedMile =>
      _loadedMiles > 0 ? _quotedGross / _loadedMiles : 0;
  double get _perTotalMile => _totalMiles > 0 ? _quotedGross / _totalMiles : 0;

  Future<void> _saveQuote() async {
    final r = _result;
    if (r == null) return;

    final now = DateTime.now();
    final datePfx =
        '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.year}';
    final origin = _originCtrl.text.trim();
    final dest = _destCtrl.text.trim();
    final routeLabel = (origin.isNotEmpty && dest.isNotEmpty)
        ? '$origin to $dest'
        : '${_totalMiles.round()} mi';
    final defaultName = '$datePfx - $routeLabel - ${_usd(_quotedGross)}';

    final nameCtrl = TextEditingController(text: defaultName);
    final quoteName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Save This Quote'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            maxLines: 2,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'Quote Name',
              hintText: 'e.g. Atlanta to Dallas',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (quoteName == null || quoteName.isEmpty) return;

    setState(() => _saving = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      await _supabase.from('quotes').insert({
        'user_id': user.id,
        'quote_name': quoteName,
        'truck_unit_id': _truckUnitId,
        'trailer_unit_id': _trailerUnitId,
        'contact_id': _selectedBroker?['id'],
        'origin': origin.isNotEmpty ? origin : null,
        'destination': dest.isNotEmpty ? dest : null,
        'quote_date': now.toIso8601String().substring(0, 10),
        'include_deadhead': _includeDeadhead,
        'deadhead_miles': r.deadheadMiles,
        'loaded_miles': r.loadedMiles, // includes the out-of-route bump
        'total_miles': r.totalMiles,
        'fuel_price_used': _fuelPrice,
        'total_cost': r.totalCosts,
        'target_hourly': r.targetHourly,
        'carrier_cut_pct': _carrierCutPct,
        'overhead_pct': _overheadPct,
        'floor_gross': _floorGross,
        'margin_pct': _marginPct,
        'quoted_gross': _quotedGross,
        'quoted_per_loaded_mile': _perLoadedMile,
        'quoted_per_total_mile': _perTotalMile,
        'status': 'quoted',
        'estimate_json': {
          'baseLoadedMiles': _baseLoaded,
          'outOfRoutePct': _outOfRoutePct,
          'effectiveLoadedMiles': r.loadedMiles,
          'totalFuelCost': r.totalFuelCost,
          'truckCost': r.truckCost,
          'trailerCost': r.trailerCost,
          'equipmentCost': r.equipmentCost,
          'tollsCost': r.tollsCost,
          'overheadCost': r.overheadCost,
          'totalCosts': r.totalCosts,
          'totalMiles': r.totalMiles,
          'totalHours': r.totalHours,
          'costPerMile': r.costPerMile,
          'minimumGrossNeeded': r.minimumGrossNeeded,
          'minimumPerMile': r.minimumPerMile,
          'targetHourly': r.targetHourly,
          'marginPct': _marginPct,
          'quotedGross': _quotedGross,
        },
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quote saved: $quoteName'),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    _deadheadCtrl.dispose();
    _loadedCtrl.dispose();
    _tollsCtrl.dispose();
    _loadUnloadCtrl.dispose();
    super.dispose();
  }

  String _usd(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quote a Load')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final r = _result;
    final base = _baseLoaded;
    final eff = _effectiveLoaded;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quote a Load'),
        actions: [
          const HelpButton(HelpScreens.quote),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Saved Quotes',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SavedQuotesScreen()),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Optional GPS for the deadhead leg.
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _currentLocation.isNotEmpty
                          ? 'GPS set — deadhead will be measured'
                          : 'No GPS — deadhead stays as entered',
                      style: TextStyle(
                        fontSize: 12,
                        color: _currentLocation.isNotEmpty
                            ? Colors.green[700]
                            : Colors.grey[500],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _gettingLocation ? null : _getGpsLocation,
                  icon: _gettingLocation
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, size: 18),
                  label: const Text('GPS'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _originCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'From (pickup)',
                prefixIcon: Icon(Icons.local_shipping),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _destCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'To (delivery)',
                prefixIcon: Icon(Icons.flag),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _calculatingRoute ? null : _getMiles,
                icon: _calculatingRoute
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.map),
                label: Text(_calculatingRoute ? 'Getting miles...' : 'Get Miles'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.blueGrey[700],
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            if (_routeError != null) ...[
              const SizedBox(height: 8),
              Text(_routeError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _deadheadCtrl,
                    keyboardType: TextInputType.number,
                    enabled: _includeDeadhead,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Deadhead',
                      suffixText: 'mi',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _loadedCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Loaded (base)',
                      suffixText: 'mi',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Out-of-route bump on LOADED miles — default 0, set per quote.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Out-of-route  +${_outOfRoutePct.round()}%',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(
                        base > 0 ? '${base.round()} → ${eff.round()} mi loaded' : '—',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                  Slider(
                    value: _outOfRoutePct,
                    min: 0,
                    max: 30,
                    divisions: 30,
                    label: '+${_outOfRoutePct.round()}%',
                    onChanged: (v) {
                      setState(() => _outOfRoutePct = v);
                      if (_result != null) {
                        _result = TruCostEngine.compute(_inputs(grossPay: 0));
                      }
                    },
                  ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Include deadhead in quote', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                _includeDeadhead
                    ? 'Your empty miles are covered (owner-operator)'
                    : 'Loaded miles only (broker-style)',
                style: const TextStyle(fontSize: 12),
              ),
              value: _includeDeadhead,
              onChanged: (v) {
                setState(() => _includeDeadhead = v);
                if (_result != null) _calculate();
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tollsCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Tolls / Other',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _loadUnloadCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Load + Unload',
                      suffixText: 'hrs',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _chip('Cut', '${_carrierCutPct.round()}%'),
                  _chip('Overhead', '${_overheadPct.round()}%'),
                  _chip('Fuel', _usd(_fuelPrice)),
                  _chip('MPG', '${_emptyMpg.round()}/${_loadedMpg.round()}'),
                  _chip('Target', '\$${_hourlyRate.round()}/hr'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _calculate,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueGrey[700],
                foregroundColor: Colors.white,
              ),
              child: const Text('Get Quote', style: TextStyle(fontSize: 18)),
            ),
            if (r != null) ...[
              const SizedBox(height: 24),
              _buildQuote(r),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await Navigator.push<Map<String, dynamic>>(
                          context,
                          MaterialPageRoute(builder: (_) => const ContactsScreen(pickMode: true)),
                        );
                        if (picked != null) {
                          setState(() => _selectedBroker = picked);
                        }
                      },
                      icon: const Icon(Icons.person_add, size: 18),
                      label: Text(
                        _selectedBroker != null
                            ? '${_selectedBroker!['name']}${_selectedBroker!['company'] != null && _selectedBroker!['company'].toString().isNotEmpty ? ' - ${_selectedBroker!['company']}' : ''}'
                            : 'Broker (optional)',
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_selectedBroker != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _selectedBroker = null),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveQuote,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.bookmark_add),
                  label: Text(_saving ? 'Saving...' : 'Save Quote'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.blueGrey[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuote(TripResult r) {
    final preview = TruCostEngine.compute(_inputs(grossPay: _quotedGross));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.4), width: 2),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Column(
              children: [
                Text('QUOTE THIS LOAD AT',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green[800], letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(_usd(_quotedGross),
                    style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.green[800])),
                Text(
                  '${_usd(_perLoadedMile)}/loaded mi  ·  ${_usd(_perTotalMile)}/total mi',
                  style: TextStyle(fontSize: 14, color: Colors.green[800]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nets you ${_usd(preview.netToOperator)}  (~${_usd(preview.effectiveHourlyRate)}/hr)',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _section('Negotiation room'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _marginChip('At floor', 0),
                    _marginChip('+5%', 5),
                    _marginChip('+10%', 10),
                    _marginChip('+15%', 15),
                  ],
                ),
                const Divider(height: 24),
                _section('Behind the number'),
                _line('Loaded${_outOfRoutePct > 0 ? ' (+${_outOfRoutePct.round()}%)' : ''}',
                    '${r.loadedMiles.round()} mi'),
                _line('Deadhead', _includeDeadhead ? '${r.deadheadMiles.round()} mi' : 'excluded'),
                _line('Total', '${r.totalMiles.round()} mi / ${r.totalHours.toStringAsFixed(1)} hrs', bold: true),
                const Divider(height: 24),
                _section('Your costs'),
                _line('Fuel', _usd(r.totalFuelCost)),
                _line(_truckLabel, _usd(r.truckCost)),
                _line(_trailerLabel, _usd(r.trailerCost)),
                _line('Tolls / Other', _usd(r.tollsCost)),
                _line('Overhead (${_overheadPct.round()}%)', _usd(r.overheadCost)),
                _line('Total cost', _usd(r.totalCosts), bold: true),
                _line('Cost per mile', '${_usd(r.costPerMile)}/mi'),
                const Divider(height: 24),
                _section('The quote'),
                _line('Floor (hits \$${r.targetHourly.round()}/hr)', _usd(_floorGross)),
                _line('Margin', '+${_marginPct.round()}%'),
                _line('Quote', _usd(_quotedGross), bold: true, valueColor: Colors.green[800]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _marginChip(String label, double pct) {
    final selected = _marginPct == pct;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _marginPct = pct),
      selectedColor: Colors.green[100],
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        color: selected ? Colors.green[900] : Colors.grey[700],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _section(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
      ),
    );
  }

  Widget _line(String label, String value, {bool bold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                  color: bold ? Colors.black87 : Colors.grey[700],
                )),
          ),
          Text(value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: valueColor ?? (bold ? Colors.black87 : Colors.grey[700]),
              )),
        ],
      ),
    );
  }
}
