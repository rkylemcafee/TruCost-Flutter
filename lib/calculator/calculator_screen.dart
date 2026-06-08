import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../engine/trucost_engine.dart';
import '../services/fuel_price_service.dart';
import '../contacts/contacts_screen.dart';

class CalculatorScreen extends StatefulWidget {
  final double? initialDeadhead;
  final double? initialLoaded;
  final String? initialOrigin;
  final String? initialDestination;

  const CalculatorScreen({super.key, this.initialDeadhead, this.initialLoaded, this.initialOrigin, this.initialDestination});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _supabase = Supabase.instance.client;

  late final TextEditingController _grossPayCtrl;
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
  String _origin = '';
  String _destination = '';
  final FuelPriceService _fuelSvc = FuelPriceService();
  String? _truckUnitId;
  String? _trailerUnitId;
  Map<String, dynamic>? _selectedBroker;

  bool _loading = true;
  bool _saving = false;
  TripResult? _result;

  @override
  void initState() {
    super.initState();
    _grossPayCtrl = TextEditingController();
    _grossPayCtrl.addListener(() => setState(() {}));
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
    _origin = widget.initialOrigin ?? '';
    _destination = widget.initialDestination ?? '';
    _loadProfile();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _grossPayCtrl.clear();
    });
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
            : subtype.isNotEmpty ? subtype : 'Trailer';
        _trailer = UnitCost(
          mode: t['cost_mode'] == 'financed' ? CostMode.financed : CostMode.owned,
          purchasePrice: _toDouble(t['purchase_price'], 0),
          depreciationRate: _toDouble(t['depreciation_pct'], 20) / 100,
          monthlyPayment: _toDouble(t['monthly_payment'], 0),
        );
      }

      await _fuelSvc.loadPrices();
      if (_origin.isNotEmpty || _destination.isNotEmpty) {
        final deadhead = double.tryParse(_deadheadCtrl.text) ?? 0;
        final loaded = double.tryParse(_loadedCtrl.text) ?? 0;
        _fuelPrice = _fuelSvc.averageForRoute(
          pickupAddress: _origin,
          deliveryAddress: _destination,
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

  void _calculate() {
    final gross = double.tryParse(_grossPayCtrl.text) ?? 0;
    final deadhead = double.tryParse(_deadheadCtrl.text) ?? 0;
    final loaded = double.tryParse(_loadedCtrl.text) ?? 0;
    final tolls = double.tryParse(_tollsCtrl.text) ?? 0;
    final loadUnload = double.tryParse(_loadUnloadCtrl.text) ?? 8;

    if (gross <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a gross pay amount to calculate.')),
      );
      return;
    }
    if (loaded <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter loaded miles to calculate.')),
      );
      return;
    }

    final inputs = TruCostInputs(
      grossPay: gross,
      deadheadMiles: deadhead,
      loadedMiles: loaded,
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

    setState(() => _result = TruCostEngine.compute(inputs));
    FocusScope.of(context).unfocus();
  }

  Future<void> _saveTrip(TripResult r) async {
    final deadhead = double.tryParse(_deadheadCtrl.text) ?? 0;
    final loaded = double.tryParse(_loadedCtrl.text) ?? 0;
    final gross = double.tryParse(_grossPayCtrl.text) ?? 0;

    final now = DateTime.now();
    final datePfx = '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.year}';
    final defaultName = _origin.isNotEmpty && _destination.isNotEmpty
        ? '$datePfx - $_origin to $_destination - ${_usd(gross)}'
        : '$datePfx - ${(deadhead + loaded).round()} mi - ${_usd(gross)}';

    final nameCtrl = TextEditingController(text: defaultName);
    final tripName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Save This Trip'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            maxLines: 2,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'Trip Name',
              hintText: 'e.g. Cocoa to Miami',
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

    if (tripName == null || tripName.isEmpty) return;

    setState(() => _saving = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      await _supabase.from('trips').insert({
        'user_id': user.id,
        'trip_name': tripName,
        'truck_unit_id': _truckUnitId,
        'trailer_unit_id': _trailerUnitId,
        'contact_id': _selectedBroker?['id'],
        'origin': _origin.isNotEmpty ? _origin : null,
        'destination': _destination.isNotEmpty ? _destination : null,
        'trip_date': DateTime.now().toIso8601String().substring(0, 10),
        'deadhead_miles': deadhead,
        'loaded_miles': loaded,
        'total_miles': deadhead + loaded,
        'gross_pay': gross,
        'fuel_price_used': _fuelPrice,
        'estimated_fuel_cost': r.totalFuelCost,
        'lease_status_at_time': _carrierCutPct > 0 ? 'leased' : 'independent',
        'carrier_cut_pct_at_time': _carrierCutPct,
        'estimated_net': r.netToOperator,
        'status': 'saved',
        'estimate_json': {
          'grossPay': r.grossPay,
          'carrierCut': r.carrierCut,
          'operatorGross': r.operatorGross,
          'totalFuelCost': r.totalFuelCost,
          'driverCost': r.driverCost,
          'truckCost': r.truckCost,
          'trailerCost': r.trailerCost,
          'equipmentCost': r.equipmentCost,
          'tollsCost': r.tollsCost,
          'overheadCost': r.overheadCost,
          'totalCosts': r.totalCosts,
          'netToOperator': r.netToOperator,
          'effectiveHourlyRate': r.effectiveHourlyRate,
          'costPerMile': r.costPerMile,
          'totalMiles': r.totalMiles,
          'totalHours': r.totalHours,
          'offerPerMile': r.offerPerMile,
          'minimumGrossNeeded': r.minimumGrossNeeded,
          'minimumPerMile': r.minimumPerMile,
          'targetHourly': r.targetHourly,
          'isWinner': r.isWinner,
        },
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved: $tripName'),
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
    _grossPayCtrl.dispose();
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
        appBar: AppBar(title: const Text('Calculator')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final r = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Calculate a Load')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _grossPayCtrl,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Gross Pay',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _deadheadCtrl,
                    keyboardType: TextInputType.number,
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
                    decoration: const InputDecoration(
                      labelText: 'Loaded',
                      suffixText: 'mi',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
                  _chip('Rate', '\$${_hourlyRate.round()}/hr'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_grossPayCtrl.text.isNotEmpty && (double.tryParse(_grossPayCtrl.text) ?? 0) > 0)
                  ? _calculate
                  : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueGrey[700],
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
              ),
              child: const Text('Calculate', style: TextStyle(fontSize: 18)),
            ),
            if (r != null) ...[
              const SizedBox(height: 24),
              _buildResults(r),
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
                        if (picked != null) setState(() => _selectedBroker = picked);
                      },
                      icon: const Icon(Icons.person_add, size: 18),
                      label: Text(
                        _selectedBroker != null
                            ? '${_selectedBroker!['name']}${_selectedBroker!['company'] != null && _selectedBroker!['company'].toString().isNotEmpty ? ' - ${_selectedBroker!['company']}' : ''}'
                            : 'Pick Contact (optional)',
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
                  onPressed: _saving ? null : () => _saveTrip(r),
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.bookmark_add),
                  label: Text(_saving ? 'Saving...' : 'Save This Trip'),
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

  Widget _chip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildResults(TripResult r) {
    final isWinner = r.isWinner;
    final color = isWinner ? Colors.green : Colors.red;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: 2),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Column(
              children: [
                Icon(isWinner ? Icons.thumb_up : Icons.thumb_down, color: color, size: 32),
                const SizedBox(height: 8),
                Text(
                  isWinner ? 'TAKE IT' : 'PASS',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color),
                ),
                Text(
                  '${_usd(r.effectiveHourlyRate)}/hr effective',
                  style: TextStyle(fontSize: 16, color: color),
                ),
                if (!isWinner)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Need ${_usd(r.minimumGrossNeeded)} to hit \$${r.targetHourly.round()}/hr',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _section('Time'),
                _line('Deadhead', '${r.deadheadMiles.round()} mi / ${r.emptyDriveHours.toStringAsFixed(1)} hrs'),
                _line('Loaded', '${r.loadedMiles.round()} mi / ${r.loadedDriveHours.toStringAsFixed(1)} hrs'),
                _line('Load + Unload', '${r.loadUnloadHours.toStringAsFixed(1)} hrs'),
                _line('Total', '${r.totalMiles.round()} mi / ${r.totalHours.toStringAsFixed(1)} hrs', bold: true),
                const Divider(height: 24),
                _section('Costs'),
                _line('Fuel (empty)', _usd(r.emptyFuelCost)),
                _line('Fuel (loaded)', _usd(r.loadedFuelCost)),
                _line('Driver pay', _usd(r.driverCost)),
                _line(_truckLabel, _usd(r.truckCost)),
                _line(_trailerLabel, _usd(r.trailerCost)),
                _line('Tolls / Other', _usd(r.tollsCost)),
                _line('Overhead (${_overheadPct.round()}%)', _usd(r.overheadCost)),
                _line('Total Trip Cost', _usd(r.totalCosts), bold: true),
                const Divider(height: 24),
                _section('Revenue'),
                _line('Gross pay', _usd(r.grossPay)),
                _line('Carrier cut (${_carrierCutPct.round()}%)', '- ${_usd(r.carrierCut)}'),
                _line('Your gross', _usd(r.operatorGross), bold: true),
                _line('- Trip costs', '- ${_usd(r.totalCosts)}'),
                _line('Net to you', _usd(r.netToOperator),
                    bold: true, valueColor: r.netToOperator >= 0 ? Colors.green : Colors.red),
                const Divider(height: 24),
                _section('Key Numbers'),
                _line('Cost per mile', '${_usd(r.costPerMile)}/mi'),
                _line('Offer per mile', '${_usd(r.offerPerMile)}/mi'),
                _line('Effective hourly', '${_usd(r.effectiveHourlyRate)}/hr',
                    valueColor: isWinner ? Colors.green : Colors.red),
                _line('Min gross for \$${r.targetHourly.round()}/hr', _usd(r.minimumGrossNeeded)),
                _line('Min per mile', '${_usd(r.minimumPerMile)}/mi'),
              ],
            ),
          ),
        ],
      ),
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