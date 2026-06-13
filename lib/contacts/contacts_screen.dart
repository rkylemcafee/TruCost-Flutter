import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


const List<String> _contactTypes = ['Direct Customer', 'Broker', 'Agent', 'Escort'];

/// Lower-48 states, keyed by abbreviation (what we store), value is display name.
const Map<String, String> _usStates = {
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

class ContactsScreen extends StatefulWidget {
  final bool pickMode;
  const ContactsScreen({super.key, this.pickMode = false});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _searchCtrl.addListener(_applyFilter);
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final rows = await _supabase
          .from('contacts')
          .select()
          .eq('user_id', user.id)
          .order('star_rating', ascending: false)
          .order('name');
      setState(() {
        _contacts = List<Map<String, dynamic>>.from(rows);
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = _contacts;
      } else {
        _filtered = _contacts.where((c) {
          final name = (c['name'] ?? '').toString().toLowerCase();
          final company = (c['company'] ?? '').toString().toLowerCase();
          final state = (c['state'] ?? '').toString().toLowerCase();
          final city = (c['city'] ?? '').toString().toLowerCase();
          final type = (c['contact_type'] ?? '').toString().toLowerCase();
          return name.contains(q) || company.contains(q) || state.contains(q) || city.contains(q) || type.contains(q);
        }).toList();
      }
    });
  }

  Future<void> _addOrEditContact({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final companyCtrl = TextEditingController(text: existing?['company'] ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone'] ?? '');
    final emailCtrl = TextEditingController(text: existing?['email'] ?? '');
    final cityCtrl = TextEditingController(text: existing?['city'] ?? '');
    final stateCtrl = TextEditingController(text: existing?['state'] ?? '');
    final notesCtrl = TextEditingController(text: existing?['notes'] ?? '');
    String selectedType = existing?['contact_type'] ?? 'Broker';
    int selectedStars = existing?['star_rating'] ?? 0;
    List<String> selectedStates =
        (existing?['best_load_states'] as List?)?.cast<String>() ?? <String>[];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing != null ? 'Edit Contact' : 'Add Contact'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Contact type
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder(), isDense: true),
                  items: _contactTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 14)))).toList(),
                  onChanged: (v) => setDialogState(() => selectedType = v ?? 'Broker'),
                ),
                const SizedBox(height: 10),
                // Star rating
                Row(
                  children: [
                    Text('Rating: ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    ...List.generate(5, (i) => GestureDetector(
                      onTap: () => setDialogState(() => selectedStars = selectedStars == i + 1 ? 0 : i + 1),
                      child: Icon(
                        i < selectedStars ? Icons.star : Icons.star_border,
                        color: Colors.amber[700],
                        size: 28,
                      ),
                    )),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name *', isDense: true), textCapitalization: TextCapitalization.words),
                const SizedBox(height: 8),
                TextField(controller: companyCtrl, decoration: const InputDecoration(labelText: 'Company', isDense: true), textCapitalization: TextCapitalization.words),
                const SizedBox(height: 8),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone', isDense: true), keyboardType: TextInputType.phone),
                const SizedBox(height: 8),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email', isDense: true), keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'City', isDense: true), textCapitalization: TextCapitalization.words)),
                    const SizedBox(width: 8),
                    SizedBox(width: 60, child: TextField(controller: stateCtrl, decoration: const InputDecoration(labelText: 'State', isDense: true), textCapitalization: TextCapitalization.characters)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes', isDense: true), maxLines: 2),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    final result = await Navigator.push<List<String>>(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => _StatePickerScreen(initial: selectedStates),
                      ),
                    );
                    if (result != null) setDialogState(() => selectedStates = result);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Best Load States',
                      isDense: true,
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.map_outlined, size: 20),
                    ),
                    child: Text(
                      selectedStates.isEmpty
                          ? 'None set — tap to choose'
                          : (selectedStates.length >= _usStates.length
                              ? 'All 48 states'
                              : selectedStates.join(', ')),
                      style: TextStyle(
                        fontSize: 14,
                        color: selectedStates.isEmpty ? Colors.grey[500] : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Name is required')));
                  return;
                }
                Navigator.pop(ctx, {
                  'name': nameCtrl.text.trim(),
                  'company': companyCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'city': cityCtrl.text.trim(),
                  'state': stateCtrl.text.trim().toUpperCase(),
                  'notes': notesCtrl.text.trim(),
                  'contact_type': selectedType,
                  'star_rating': selectedStars,
                  'best_load_states': selectedStates,
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      if (existing != null) {
        await _supabase.from('contacts').update(result).eq('id', existing['id']);
      } else {
        await _supabase.from('contacts').insert({...result, 'user_id': user.id});
      }
      _loadContacts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteContact(Map<String, dynamic> contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact?'),
        content: Text('Remove ${contact['name']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _supabase.from('contacts').delete().eq('id', contact['id']);
      _loadContacts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'Direct Customer': return Colors.green;
      case 'Broker': return Colors.blue;
      case 'Agent': return Colors.purple;
      case 'Escort': return Colors.orange;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? 'Pick a Contact' : 'Contacts'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _addOrEditContact()),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search name, company, state, type...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${_filtered.length} contact${_filtered.length != 1 ? 's' : ''}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadContacts,
                    child: _filtered.isEmpty
                        ? const Center(child: Text('No contacts yet. Tap + to add.', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, i) => _buildContactTile(_filtered[i]),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildContactTile(Map<String, dynamic> c) {
    final name = c['name'] ?? '';
    final company = c['company'] ?? '';
    final phone = c['phone'] ?? '';
    final city = c['city'] ?? '';
    final state = c['state'] ?? '';
    final type = c['contact_type'] ?? 'Broker';
    final stars = c['star_rating'] ?? 0;
    final loadStates = (c['best_load_states'] as List?)?.cast<String>() ?? <String>[];
    final loadStatesLabel = loadStates.isEmpty
        ? ''
        : (loadStates.length >= 48 ? 'All 48' : loadStates.join(', '));
    final location = [city, state].where((s) => s.isNotEmpty).join(', ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _typeColor(type).withOpacity(0.15),
          child: Icon(
            type == 'Escort' ? Icons.local_shipping : Icons.person,
            color: _typeColor(type),
          ),
        ),
        title: Row(
          children: [
            Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _typeColor(type).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(type, style: TextStyle(fontSize: 10, color: _typeColor(type), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (company.isNotEmpty) Text(company, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            if (location.isNotEmpty) Text(location, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            if (phone.isNotEmpty) Text(phone, style: TextStyle(fontSize: 12, color: Colors.blue[700])),
            if (loadStatesLabel.isNotEmpty)
              Text('Loads: $loadStatesLabel',
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey[400], fontWeight: FontWeight.w500)),
            if (stars > 0)
              Row(
                children: List.generate(5, (i) => Icon(
                  i < stars ? Icons.star : Icons.star_border,
                  size: 14,
                  color: Colors.amber[700],
                )),
              ),
          ],
        ),
        trailing: widget.pickMode
            ? const Icon(Icons.chevron_right)
            : PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') _addOrEditContact(existing: c);
                  if (v == 'delete') _deleteContact(c);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                ],
              ),
        onTap: widget.pickMode
            ? () => Navigator.pop(context, c)
            : () => _addOrEditContact(existing: c),
      ),
    );
  }
}


class _StatePickerScreen extends StatefulWidget {
  final List<String> initial;
  const _StatePickerScreen({required this.initial});
  @override
  State<_StatePickerScreen> createState() => _StatePickerScreenState();
}

class _StatePickerScreenState extends State<_StatePickerScreen> {
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

  bool get _allSelected => _selected.length >= _usStates.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected = _usStates.keys.toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _usStates.entries.where((e) {
      if (_query.isEmpty) return true;
      return e.value.toLowerCase().contains(_query) || e.key.toLowerCase().contains(_query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Best Load States'),
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
