import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Step 4: Default values that pre-fill the calculator.
///
/// Goes in: lib/onboarding/defaults_step.dart

class DefaultsStep extends StatefulWidget {
  final VoidCallback onNext;
  const DefaultsStep({super.key, required this.onNext});

  @override
  State<DefaultsStep> createState() => _DefaultsStepState();
}

class _DefaultsStepState extends State<DefaultsStep> {
  final _supabase = Supabase.instance.client;

  final _fuelPriceCtrl = TextEditingController(text: '4.00');
  final _emptyMpgCtrl = TextEditingController(text: '8');
  final _loadedMpgCtrl = TextEditingController(text: '6');
  final _speedEmptyCtrl = TextEditingController(text: '60');
  final _speedLoadedCtrl = TextEditingController(text: '55');
  final _hourlyRateCtrl = TextEditingController(text: '50');
  final _annualHoursCtrl = TextEditingController(text: '2500');
  final _overheadCtrl = TextEditingController(text: '15');

  bool _loading = false;

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('profiles').update({
        'fuel_price_default': double.tryParse(_fuelPriceCtrl.text) ?? 4.00,
        'empty_mpg': double.tryParse(_emptyMpgCtrl.text) ?? 8,
        'loaded_mpg': double.tryParse(_loadedMpgCtrl.text) ?? 6,
        'speed_empty': double.tryParse(_speedEmptyCtrl.text) ?? 60,
        'speed_loaded': double.tryParse(_speedLoadedCtrl.text) ?? 55,
        'hourly_rate': double.tryParse(_hourlyRateCtrl.text) ?? 50,
        'annual_work_hours': double.tryParse(_annualHoursCtrl.text) ?? 2500,
        'overhead_pct': double.tryParse(_overheadCtrl.text) ?? 15,
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
    _fuelPriceCtrl.dispose();
    _emptyMpgCtrl.dispose();
    _loadedMpgCtrl.dispose();
    _speedEmptyCtrl.dispose();
    _speedLoadedCtrl.dispose();
    _hourlyRateCtrl.dispose();
    _annualHoursCtrl.dispose();
    _overheadCtrl.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController ctrl, String label, {String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Your Defaults',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'These pre-fill your calculator. Change them anytime.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          _field(_fuelPriceCtrl, 'Fuel Price', suffix: '\$/gal'),
          Row(
            children: [
              Expanded(child: _field(_emptyMpgCtrl, 'Empty MPG')),
              const SizedBox(width: 12),
              Expanded(child: _field(_loadedMpgCtrl, 'Loaded MPG')),
            ],
          ),
          Row(
            children: [
              Expanded(
                  child: _field(_speedEmptyCtrl, 'Empty Speed', suffix: 'mph')),
              const SizedBox(width: 12),
              Expanded(
                  child:
                      _field(_speedLoadedCtrl, 'Loaded Speed', suffix: 'mph')),
            ],
          ),
          _field(_hourlyRateCtrl, 'Hourly Rate', suffix: '\$/hr'),
          _field(_annualHoursCtrl, 'Annual Working Hours', suffix: 'hrs/yr'),
          _field(_overheadCtrl, 'Overhead', suffix: '%'),
          const SizedBox(height: 20),
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
