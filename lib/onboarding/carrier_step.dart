import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Step 2 (leased only): Carrier cut, fuel tax toggle, fuel surcharge.
///
/// Goes in: lib/onboarding/carrier_step.dart

class CarrierStep extends StatefulWidget {
  final VoidCallback onNext;
  const CarrierStep({super.key, required this.onNext});

  @override
  State<CarrierStep> createState() => _CarrierStepState();
}

class _CarrierStepState extends State<CarrierStep> {
  final _supabase = Supabase.instance.client;

  double _keepPct = 75;
  bool _carrierChargesFuelTax = false;
  bool _carrierFuelCard = false;
  // FSC as a % of gross (default 6%) and the % of it the operator keeps (100%).
  final _fscRateCtrl = TextEditingController(text: '6');
  final _fscReceivedCtrl = TextEditingController(text: '100');
  final _insRateCtrl = TextEditingController(text: '3');
  bool _loading = false;

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final carrierCut = 100 - _keepPct;

      await _supabase.from('profiles').update({
        'carrier_cut_pct': carrierCut,
        'carrier_charges_fuel_tax': _carrierChargesFuelTax,
        'carrier_fuel_card': _carrierFuelCard,
        'fsc_rate': double.tryParse(_fscRateCtrl.text) ?? 6,
        'fsc_pct_received': double.tryParse(_fscReceivedCtrl.text) ?? 100,
        'carrier_insurance_pct': double.tryParse(_insRateCtrl.text) ?? 3,
      }).eq('user_id', user.id);

      widget.onNext();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _fscRateCtrl.dispose();
    _fscReceivedCtrl.dispose();
    _insRateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Your Carrier Deal',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // ── Keep percentage ──
          Text('What percentage do you keep?',
              style: TextStyle(fontSize: 16, color: Colors.grey[700])),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _keepPct,
                  min: 50,
                  max: 100,
                  divisions: 50,
                  label: '${_keepPct.round()}%',
                  onChanged: (v) => setState(() => _keepPct = v),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${_keepPct.round()}%',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          Text('Carrier takes ${(100 - _keepPct).round()}%',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 24),

          // ── Fuel tax toggle ──
          SwitchListTile(
            title: const Text('Carrier deducts fuel tax from settlement?'),
            value: _carrierChargesFuelTax,
            onChanged: (v) => setState(() => _carrierChargesFuelTax = v),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Do you run a carrier fuel card or advance?'),
            subtitle: const Text('If yes, fuel is deducted from your settlement'),
            value: _carrierFuelCard,
            onChanged: (v) => setState(() => _carrierFuelCard = v),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 20),

          // ── Fuel surcharge ──
          Text('Fuel surcharge',
              style: TextStyle(fontSize: 16, color: Colors.grey[700])),
          const SizedBox(height: 4),
          Text(
            'FSC is passed through — your carrier doesn\'t take a cut of it, and it '
            'counts as income toward your hourly. Most carriers run about 6%.',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fscRateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'FSC (% of gross)',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _fscReceivedCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'You keep',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Carrier insurance ──
          Text('Carrier insurance',
              style: TextStyle(fontSize: 16, color: Colors.grey[700])),
          const SizedBox(height: 4),
          Text(
            'Some carriers take a slice of your gross for insurance — off the top, '
            'and you keep none of it. Often 3–4%. Leave 0 if yours doesn\'t.',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _insRateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Carrier insurance (% of gross)',
              suffixText: '%',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _loading ? null : _save,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _loading
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Next', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
