import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../common/state_picker_screen.dart';

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

  final _emptyMpgCtrl = TextEditingController(text: '8');
  final _loadedMpgCtrl = TextEditingController(text: '6');
  final _speedEmptyCtrl = TextEditingController(text: '60');
  final _speedLoadedCtrl = TextEditingController(text: '55');
  final _hourlyRateCtrl = TextEditingController(text: '50');
  final _annualHoursCtrl = TextEditingController(text: '2500');
  final _overheadCtrl = TextEditingController(text: '15');
  final _cargoInsCtrl = TextEditingController(text: '100000');
  final _hotelRateCtrl = TextEditingController(text: '120');
  bool _teamOperation = false;

  // Optional device capture (feeds profiles.device_* and profiles.phone).
  bool _deviceIphone = false;
  bool _deviceAndroidPhone = false;
  bool _deviceIpad = false;
  bool _deviceAndroidTablet = false;
  final _phoneCtrl = TextEditingController();

  List<String> _runStates = kUsStates.keys.toList();

  bool _loading = false;

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('profiles').update({
        'empty_mpg': double.tryParse(_emptyMpgCtrl.text) ?? 8,
        'loaded_mpg': double.tryParse(_loadedMpgCtrl.text) ?? 6,
        'speed_empty': double.tryParse(_speedEmptyCtrl.text) ?? 60,
        'speed_loaded': double.tryParse(_speedLoadedCtrl.text) ?? 55,
        'hourly_rate': double.tryParse(_hourlyRateCtrl.text) ?? 50,
        'annual_work_hours': double.tryParse(_annualHoursCtrl.text) ?? 2500,
        'overhead_pct': double.tryParse(_overheadCtrl.text) ?? 15,
        'cargo_insurance': double.tryParse(_cargoInsCtrl.text) ?? 100000,
        'hotel_rate': double.tryParse(_hotelRateCtrl.text) ?? 120,
        'team_operation': _teamOperation,
        'run_states': _runStates,
        'device_iphone': _deviceIphone,
        'device_android_phone': _deviceAndroidPhone,
        'device_ipad': _deviceIpad,
        'device_android_tablet': _deviceAndroidTablet,
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
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
    _emptyMpgCtrl.dispose();
    _loadedMpgCtrl.dispose();
    _speedEmptyCtrl.dispose();
    _speedLoadedCtrl.dispose();
    _hourlyRateCtrl.dispose();
    _annualHoursCtrl.dispose();
    _overheadCtrl.dispose();
    _cargoInsCtrl.dispose();
    _hotelRateCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController ctrl, String label, {String? prefix, String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix,
          suffixText: suffix,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  String _runStatesLabel() {
    if (_runStates.isEmpty) return 'None set — tap to choose';
    if (_runStates.length >= kUsStates.length) return 'All 48 states';
    return _runStates.join(', ');
  }

  Future<void> _pickRunStates() async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => StatePickerScreen(initial: _runStates, title: 'Where You Run')),
    );
    if (result != null) setState(() => _runStates = result);
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

          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Coverage & how you run',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _field(_cargoInsCtrl, 'Cargo Insurance', prefix: '\$'),
          SwitchListTile(
            title: const Text('Team operation'),
            subtitle: const Text('You run with a co-driver'),
            value: _teamOperation,
            onChanged: (v) => setState(() => _teamOperation = v),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          _field(_hotelRateCtrl, 'Hotel Rate (overnight, no sleeper)', prefix: '\$', suffix: '/night'),
          InkWell(
            onTap: _pickRunStates,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Where you like to run',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.map_outlined, size: 20),
              ),
              child: Text(_runStatesLabel(),
                  style: TextStyle(fontSize: 14, color: _runStates.isEmpty ? Colors.grey[500] : Colors.black87)),
            ),
          ),

          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Your device (optional)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Check any you use — helps us test on the right hardware.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          CheckboxListTile(
            title: const Text('iPhone'),
            value: _deviceIphone,
            onChanged: (v) => setState(() => _deviceIphone = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
          CheckboxListTile(
            title: const Text('Android phone'),
            value: _deviceAndroidPhone,
            onChanged: (v) => setState(() => _deviceAndroidPhone = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
          CheckboxListTile(
            title: const Text('iPad'),
            value: _deviceIpad,
            onChanged: (v) => setState(() => _deviceIpad = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
          CheckboxListTile(
            title: const Text('Android tablet'),
            value: _deviceAndroidTablet,
            onChanged: (v) => setState(() => _deviceAndroidTablet = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone (optional)',
              helperText: 'So we can reach you about the beta.',
              border: OutlineInputBorder(),
            ),
          ),

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
