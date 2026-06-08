import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Step 2 (leased only): Carrier cut, fuel tax toggle, fuel surcharge setup.
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
  String _fscMethod = 'included';
  final _fscRateCtrl = TextEditingController();
  double _fscPctReceived = 100;
  bool _loading = false;

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final carrierCut = 100 - _keepPct;
      double? fscRate;
      if (_fscMethod == 'pct_of_linehaul' || _fscMethod == 'per_mile') {
        fscRate = double.tryParse(_fscRateCtrl.text);
      }

      await _supabase.from('profiles').update({
        'carrier_cut_pct': carrierCut,
        'carrier_charges_fuel_tax': _carrierChargesFuelTax,
        'fsc_method': _fscMethod,
        'fsc_rate': fscRate,
        'fsc_pct_received': _fscPctReceived,
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
          const SizedBox(height: 16),

          // ── FSC method ──
          Text('How is fuel surcharge handled?',
              style: TextStyle(fontSize: 16, color: Colors.grey[700])),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _fscMethod,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'included', child: Text('Included in gross pay')),
              DropdownMenuItem(value: 'pct_of_linehaul', child: Text('% of linehaul')),
              DropdownMenuItem(value: 'per_mile', child: Text('Per mile amount')),
              DropdownMenuItem(value: 'none', child: Text('Carrier keeps all FSC')),
            ],
            onChanged: (v) => setState(() => _fscMethod = v ?? 'included'),
          ),

          // ── FSC rate (conditional) ──
          if (_fscMethod == 'pct_of_linehaul' || _fscMethod == 'per_mile') ...[
            const SizedBox(height: 16),
            TextField(
              controller: _fscRateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _fscMethod == 'pct_of_linehaul'
                    ? 'FSC Rate (%)'
                    : 'FSC Rate (\$/mile)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('What % of fuel surcharge do you receive?',
                style: TextStyle(fontSize: 16, color: Colors.grey[700])),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _fscPctReceived,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '${_fscPctReceived.round()}%',
                    onChanged: (v) => setState(() => _fscPctReceived = v),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text('${_fscPctReceived.round()}%',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                ),
              ],
            ),
          ],

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
