import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Step 0: Name your co-pilot. Presets or a custom name → profiles.copilot_name.
///
/// Goes in: lib/onboarding/copilot_name_step.dart

class CopilotNameStep extends StatefulWidget {
  final VoidCallback onNext;
  const CopilotNameStep({super.key, required this.onNext});

  @override
  State<CopilotNameStep> createState() => _CopilotNameStepState();
}

class _CopilotNameStepState extends State<CopilotNameStep> {
  final _supabase = Supabase.instance.client;

  // [stored name, label, flavor]
  static const List<List<String>> _presets = [
    ['TruCost Co-Pilot', 'TruCost Co-Pilot', 'Keeps it all business'],
    ['Dave', 'Dave', 'The Dispatcher'],
    ['Charlie', 'Charlie', 'The Co-Pilot'],
  ];

  static const String _customKey = '__custom__';

  String _choice = 'TruCost Co-Pilot';
  final _customCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  String get _resolvedName {
    if (_choice == _customKey) {
      final t = _customCtrl.text.trim();
      return t.isEmpty ? 'TruCost Co-Pilot' : t;
    }
    return _choice;
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      await _supabase.from('profiles').update({
        'copilot_name': _resolvedName,
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
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.smart_toy, size: 64, color: Colors.blueGrey),
          const SizedBox(height: 16),
          const Text(
            'Meet Your Co-Pilot',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            "What do you want to call your voice assistant? Call him by name and he'll answer.",
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ..._presets.map((p) => _presetTile(p[0], p[1], p[2])),
          _customTile(),
          const SizedBox(height: 24),
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

  Widget _presetTile(String value, String label, String flavor) {
    final selected = _choice == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? Colors.blueGrey[50] : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.blueGrey : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: RadioListTile<String>(
          value: value,
          groupValue: _choice,
          onChanged: (v) => setState(() => _choice = v!),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(flavor),
          activeColor: Colors.blueGrey[700],
        ),
      ),
    );
  }

  Widget _customTile() {
    final selected = _choice == _customKey;
    return Container(
      decoration: BoxDecoration(
        color: selected ? Colors.blueGrey[50] : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? Colors.blueGrey : Colors.grey.shade300,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          RadioListTile<String>(
            value: _customKey,
            groupValue: _choice,
            onChanged: (v) => setState(() => _choice = v!),
            title: const Text('Something else', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Pick your own name'),
            activeColor: Colors.blueGrey[700],
          ),
          if (selected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextField(
                controller: _customCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Co-Pilot name',
                  hintText: 'e.g. Smokey, Dispatch, Rubber Duck',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
