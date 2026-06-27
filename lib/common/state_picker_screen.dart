import 'package:flutter/material.dart';

/// Shared US-states multi-select. Returns the chosen 2-letter codes (sorted)
/// via Navigator.pop, or null if dismissed.
///
/// Goes in: lib/common/state_picker_screen.dart

const Map<String, String> kUsStates = {
  'AL': 'Alabama', 'AZ': 'Arizona', 'AR': 'Arkansas', 'CA': 'California',
  'CO': 'Colorado', 'CT': 'Connecticut', 'DE': 'Delaware', 'FL': 'Florida',
  'GA': 'Georgia', 'ID': 'Idaho', 'IL': 'Illinois', 'IN': 'Indiana',
  'IA': 'Iowa', 'KS': 'Kansas', 'KY': 'Kentucky', 'LA': 'Louisiana',
  'ME': 'Maine', 'MD': 'Maryland', 'MA': 'Massachusetts', 'MI': 'Michigan',
  'MN': 'Minnesota', 'MS': 'Mississippi', 'MO': 'Missouri', 'MT': 'Montana',
  'NE': 'Nebraska', 'NV': 'Nevada', 'NH': 'New Hampshire', 'NJ': 'New Jersey',
  'NM': 'New Mexico', 'NY': 'New York', 'NC': 'North Carolina', 'ND': 'North Dakota',
  'OH': 'Ohio', 'OK': 'Oklahoma', 'OR': 'Oregon', 'PA': 'Pennsylvania',
  'RI': 'Rhode Island', 'SC': 'South Carolina', 'SD': 'South Dakota', 'TN': 'Tennessee',
  'TX': 'Texas', 'UT': 'Utah', 'VT': 'Vermont', 'VA': 'Virginia',
  'WA': 'Washington', 'WV': 'West Virginia', 'WI': 'Wisconsin', 'WY': 'Wyoming',
};

class StatePickerScreen extends StatefulWidget {
  final List<String> initial;
  final String title;
  const StatePickerScreen({super.key, required this.initial, this.title = 'Select States'});

  @override
  State<StatePickerScreen> createState() => _StatePickerScreenState();
}

class _StatePickerScreenState extends State<StatePickerScreen> {
  late Set<String> _selected;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initial};
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _allSelected => _selected.length >= kUsStates.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected = kUsStates.keys.toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = kUsStates.entries.where((e) {
      if (_query.isEmpty) return true;
      return e.value.toLowerCase().contains(_query) || e.key.toLowerCase().contains(_query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _selected.toList()..sort()),
            child: const Text('Done',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search states...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),
          ),
          CheckboxListTile(
            value: _allSelected,
            onChanged: (_) => _toggleAll(),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: Colors.blueGrey[700],
            title: const Text('All 48 States', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${_selected.length} selected'),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: entries.map((e) {
                final sel = _selected.contains(e.key);
                return CheckboxListTile(
                  value: sel,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(e.key);
                    } else {
                      _selected.remove(e.key);
                    }
                  }),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.blueGrey[700],
                  dense: true,
                  title: Text(e.value),
                  secondary: Text(e.key,
                      style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w600)),
                );
              }).toList(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _selected.toList()..sort()),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueGrey[700],
                foregroundColor: Colors.white,
              ),
              child: Text(
                _selected.isEmpty
                    ? 'Save'
                    : 'Save  (${_selected.length} state${_selected.length == 1 ? '' : 's'})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
