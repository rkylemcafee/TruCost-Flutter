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
  final _searchCtrl = TextEditingController();

  // 0 = Personal, 1 = Agents, 2 = Brokers
  int _tab = 0;

  // Personal
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  bool _loadingContacts = true;

  // Agents
  List<Map<String, dynamic>> _allAgents = [];
  List<Map<String, dynamic>> _agents = [];
  List<Map<String, dynamic>> _filteredAgents = [];
  Set<String> _dismissedIds = {};
  Set<String> _addedIds = {};
  bool _loadingAgents = false;
  bool _agentsLoaded = false;

  // Brokers
  List<Map<String, dynamic>> _brokers = [];
  List<Map<String, dynamic>> _filteredBrokers = [];
  bool _loadingBrokers = false;
  bool _brokersLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _switchTab(int i) {
    setState(() => _tab = i);
    if (i == 1 && !_agentsLoaded) _loadAgents();
    if (i == 2 && !_brokersLoaded) _loadBrokers();
    _applyFilter();
  }

  // ---------------------------------------------------------------- loading

  Future<void> _loadContacts() async {
    setState(() => _loadingContacts = true);
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
        _loadingContacts = false;
        _applyFilter();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingContacts = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _loadAgents() async {
    setState(() => _loadingAgents = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final agentRows = await _supabase
          .from('agent_directory')
          .select()
          .eq('is_active', true)
          .order('name');
      final statusRows = await _supabase
          .from('user_agent_status')
          .select('agent_id, status')
          .eq('user_id', user.id);

      final dismissed = <String>{};
      final added = <String>{};
      for (final s in (statusRows as List)) {
        final id = s['agent_id'].toString();
        if (s['status'] == 'dismissed') dismissed.add(id);
        if (s['status'] == 'added') added.add(id);
      }
      final all = List<Map<String, dynamic>>.from(agentRows);
      setState(() {
        _dismissedIds = dismissed;
        _addedIds = added;
        _allAgents = all;
        _agents = all.where((a) => !dismissed.contains(a['id'].toString())).toList();
        _agentsLoaded = true;
        _loadingAgents = false;
        _applyFilter();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAgents = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading agents: $e')));
      }
    }
  }

  Future<void> _loadBrokers() async {
    setState(() => _loadingBrokers = true);
    try {
      final rows = await _supabase
          .from('broker_directory')
          .select()
          .eq('is_active', true)
          .order('company');
      setState(() {
        _brokers = List<Map<String, dynamic>>.from(rows);
        _brokersLoaded = true;
        _loadingBrokers = false;
        _applyFilter();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingBrokers = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading directory: $e')));
      }
    }
  }

  // ---------------------------------------------------------------- filter

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      if (_tab == 0) {
        _filteredContacts = q.isEmpty
            ? _contacts
            : _contacts.where((c) {
                final name = (c['name'] ?? '').toString().toLowerCase();
                final company = (c['company'] ?? '').toString().toLowerCase();
                final state = (c['state'] ?? '').toString().toLowerCase();
                final city = (c['city'] ?? '').toString().toLowerCase();
                final type = (c['contact_type'] ?? '').toString().toLowerCase();
                return name.contains(q) || company.contains(q) || state.contains(q) || city.contains(q) || type.contains(q);
              }).toList();
      } else if (_tab == 1) {
        _filteredAgents = q.isEmpty
            ? _agents
            : _agents.where((a) {
                final name = (a['name'] ?? '').toString().toLowerCase();
                final company = (a['company'] ?? '').toString().toLowerCase();
                final freight = ((a['freight_types'] as List?)?.join(' ') ?? '').toLowerCase();
                final states = ((a['origin_states'] as List?)?.join(' ') ?? '').toLowerCase();
                return name.contains(q) || company.contains(q) || freight.contains(q) || states.contains(q);
              }).toList();
      } else {
        _filteredBrokers = q.isEmpty
            ? _brokers
            : _brokers.where((b) {
                final c = (b['company'] ?? '').toString().toLowerCase();
                final f = (b['freight_types'] ?? '').toString().toLowerCase();
                final s = (b['hq_state'] ?? '').toString().toLowerCase();
                final n = (b['notes'] ?? '').toString().toLowerCase();
                return c.contains(q) || f.contains(q) || s.contains(q) || n.contains(q);
              }).toList();
      }
    });
  }

  // ------------------------------------------------------------- personal CRUD

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
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder(), isDense: true),
                  items: _contactTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 14)))).toList(),
                  onChanged: (v) => setDialogState(() => selectedType = v ?? 'Broker'),
                ),
                const SizedBox(height: 10),
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

  // ------------------------------------------------------------- broker import

  Future<void> _importBroker(Map<String, dynamic> b) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final company = (b['company'] ?? '').toString().trim();
      if (company.isEmpty) return;

      final existing = await _supabase
          .from('contacts')
          .select()
          .eq('user_id', user.id)
          .eq('name', company)
          .limit(1);

      Map<String, dynamic> contact;
      if ((existing as List).isNotEmpty) {
        contact = Map<String, dynamic>.from(existing.first);
      } else {
        final phone = (b['dispatch_phone'] ?? '').toString().trim();
        final emailRaw = (b['email'] ?? '').toString().trim();
        final realEmail = emailRaw.contains('@') ? emailRaw : '';
        final setupNote = (!emailRaw.contains('@') && emailRaw.isNotEmpty)
            ? 'Carrier setup: $emailRaw. '
            : '';
        final freight = (b['freight_types'] ?? '').toString().trim();
        final dirNotes = (b['notes'] ?? '').toString().trim();
        final notes =
            ('$setupNote$freight${dirNotes.isNotEmpty ? ' — $dirNotes' : ''}').trim();

        final inserted = await _supabase.from('contacts').insert({
          'user_id': user.id,
          'name': company,
          'company': '',
          'phone': phone,
          'email': realEmail,
          'city': '',
          'state': (b['hq_state'] ?? '').toString().trim().toUpperCase(),
          'notes': notes,
          'contact_type': 'Broker',
          'star_rating': 0,
          'best_load_states': <String>[],
        }).select().single();
        contact = Map<String, dynamic>.from(inserted);
      }

      if (!mounted) return;
      if (widget.pickMode) {
        Navigator.pop(context, contact);
      } else {
        _loadContacts();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $company to your contacts'),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  // ------------------------------------------------------------- agent actions

  Future<void> _addAgentToContacts(Map<String, dynamic> a) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final agentId = a['id'].toString();

      final existing = await _supabase
          .from('contacts')
          .select('id')
          .eq('user_id', user.id)
          .eq('source_agent_id', agentId)
          .limit(1);

      if ((existing as List).isEmpty) {
        final origin = (a['origin_states'] as List?)?.cast<String>() ?? <String>[];
        await _supabase.from('contacts').insert({
          'user_id': user.id,
          'name': a['name'],
          'company': a['company'] ?? '',
          'phone': a['phone'] ?? '',
          'email': a['email'] ?? '',
          'city': '',
          'state': '',
          'notes': '',
          'contact_type': 'Agent',
          'star_rating': 0,
          'best_load_states': origin,
          'source_agent_id': agentId,
        });
      }

      await _supabase.from('user_agent_status').upsert(
        {'user_id': user.id, 'agent_id': agentId, 'status': 'added'},
        onConflict: 'user_id,agent_id',
      );

      if (!mounted) return;
      setState(() => _addedIds.add(agentId));
      _loadContacts();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${a['name']} to your contacts'),
          backgroundColor: Colors.green[700],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _dismissAgent(Map<String, dynamic> a) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final agentId = a['id'].toString();
      await _supabase.from('user_agent_status').upsert(
        {'user_id': user.id, 'agent_id': agentId, 'status': 'dismissed'},
        onConflict: 'user_id,agent_id',
      );
      setState(() {
        _dismissedIds.add(agentId);
        _addedIds.remove(agentId);
        _agents = _allAgents.where((x) => !_dismissedIds.contains(x['id'].toString())).toList();
        _applyFilter();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Hid ${a['name']}'),
        action: SnackBarAction(label: 'Undo', onPressed: () => _restoreAgent(agentId)),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _restoreAgent(String agentId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      await _supabase
          .from('user_agent_status')
          .delete()
          .eq('user_id', user.id)
          .eq('agent_id', agentId)
          .eq('status', 'dismissed');
      setState(() {
        _dismissedIds.remove(agentId);
        _agents = _allAgents.where((x) => !_dismissedIds.contains(x['id'].toString())).toList();
        _applyFilter();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _restoreAllAgents() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      await _supabase
          .from('user_agent_status')
          .delete()
          .eq('user_id', user.id)
          .eq('status', 'dismissed');
      setState(() {
        _dismissedIds = {};
        _agents = List<Map<String, dynamic>>.from(_allAgents);
        _applyFilter();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showHiddenSheet() {
    final hidden = _allAgents.where((a) => _dismissedIds.contains(a['id'].toString())).toList();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text('Hidden agents (${hidden.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: hidden.isEmpty
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _restoreAllAgents();
                          },
                    child: const Text('Restore all'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: hidden.isEmpty
                  ? const Padding(padding: EdgeInsets.all(24), child: Text('Nothing hidden.', style: TextStyle(color: Colors.grey)))
                  : ListView(
                      shrinkWrap: true,
                      children: hidden.map((a) {
                        return ListTile(
                          title: Text((a['name'] ?? '').toString()),
                          subtitle: Text((a['company'] ?? '').toString(), style: const TextStyle(fontSize: 12)),
                          trailing: TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _restoreAgent(a['id'].toString());
                            },
                            child: const Text('Restore'),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- helpers

  Color _typeColor(String type) {
    switch (type) {
      case 'Direct Customer': return Colors.green;
      case 'Broker': return Colors.blue;
      case 'Agent': return Colors.purple;
      case 'Escort': return Colors.orange;
      default: return Colors.grey;
    }
  }

  String _fmtIns(dynamic v) {
    if (v == null) return '';
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    if (n <= 0) return '';
    if (n >= 1000000) {
      final m = n / 1000000;
      return '\$${m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1)}M cargo';
    }
    if (n >= 1000) return '\$${(n / 1000).round()}K cargo';
    return '\$${n.toStringAsFixed(0)} cargo';
  }

  bool _isNew(dynamic createdAt) {
    if (createdAt == null) return false;
    final dt = DateTime.tryParse(createdAt.toString());
    if (dt == null) return false;
    return DateTime.now().difference(dt).inDays < 7;
  }

  Widget _badge(String text, MaterialColor color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10.5, color: color[800], fontWeight: FontWeight.w700)),
      );

  Widget _chip(String text, MaterialColor color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 11, color: color[800])),
      );

  Widget _countLine(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const Spacer(),
            if (trailing != null) trailing,
          ],
        ),
      );

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? 'Pick a Contact' : 'Contacts'),
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: 'Add contact', onPressed: () => _addOrEditContact()),
        ],
      ),
      body: Column(
        children: [
          _segmentedControl(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: _tab == 0
                    ? 'Search name, company, state, type...'
                    : _tab == 1
                        ? 'Search agents...'
                        : 'Search broker, freight, state...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _tabBody()),
        ],
      ),
    );
  }

  Widget _segmentedControl() {
    final accent = Theme.of(context).colorScheme.primary;
    Widget seg(String label, int i) {
      final active = _tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switchTab(i),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: active ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active ? accent : Colors.grey.shade400),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? Colors.white : Colors.grey[700],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(children: [seg('Personal', 0), seg('Agents', 1), seg('Brokers', 2)]),
    );
  }

  Widget _tabBody() {
    if (_tab == 0) return _personalBody();
    if (_tab == 1) return _agentsBody();
    return _brokersBody();
  }

  Widget _personalBody() {
    if (_loadingContacts) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        _countLine('${_filteredContacts.length} contact${_filteredContacts.length != 1 ? 's' : ''}'),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadContacts,
            child: _filteredContacts.isEmpty
                ? ListView(children: const [SizedBox(height: 80), Center(child: Text('No contacts yet. Tap + to add.', style: TextStyle(color: Colors.grey)))])
                : ListView.builder(itemCount: _filteredContacts.length, itemBuilder: (ctx, i) => _buildContactTile(_filteredContacts[i])),
          ),
        ),
      ],
    );
  }

  Widget _agentsBody() {
    if (_loadingAgents) return const Center(child: CircularProgressIndicator());
    final hiddenCount = _dismissedIds.length;
    return Column(
      children: [
        _countLine(
          '${_filteredAgents.length} agent${_filteredAgents.length != 1 ? 's' : ''}',
          trailing: hiddenCount > 0
              ? GestureDetector(
                  onTap: _showHiddenSheet,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_off_outlined, size: 14, color: Colors.grey[500]),
                      Text(' $hiddenCount hidden', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                )
              : null,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAgents,
            child: _filteredAgents.isEmpty
                ? ListView(children: const [SizedBox(height: 80), Center(child: Text('No agents to show.', style: TextStyle(color: Colors.grey)))])
                : ListView.builder(itemCount: _filteredAgents.length, itemBuilder: (ctx, i) => _buildAgentTile(_filteredAgents[i])),
          ),
        ),
      ],
    );
  }

  Widget _brokersBody() {
    if (_loadingBrokers) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        _countLine('${_filteredBrokers.length} broker${_filteredBrokers.length != 1 ? 's' : ''} · tap to add to contacts'),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadBrokers,
            child: _filteredBrokers.isEmpty
                ? ListView(children: const [SizedBox(height: 80), Center(child: Text('No brokers found.', style: TextStyle(color: Colors.grey)))])
                : ListView.builder(itemCount: _filteredBrokers.length, itemBuilder: (ctx, i) => _buildBrokerTile(_filteredBrokers[i])),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- tiles

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

  Widget _buildAgentTile(Map<String, dynamic> a) {
    final name = (a['name'] ?? '').toString();
    final company = (a['company'] ?? '').toString();
    final freight = (a['freight_types'] as List?)?.cast<String>() ?? <String>[];
    final origin = (a['origin_states'] as List?)?.cast<String>() ?? <String>[];
    final team = a['typically_team'] == true;
    final ins = _fmtIns(a['min_cargo_insurance']);
    final agentId = a['id'].toString();
    final added = _addedIds.contains(agentId);
    final isNew = _isNew(a['created_at']);

    final subtitleParts = <String>[
      if (company.isNotEmpty) company,
      if (origin.isNotEmpty) 'out of ${origin.join(', ')}',
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                _badge('Agent', Colors.purple),
                const Spacer(),
                if (isNew && !added) _badge('NEW', Colors.green),
                if (added)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 15, color: Colors.teal[700]),
                      Text(' In contacts', style: TextStyle(fontSize: 11, color: Colors.teal[700], fontWeight: FontWeight.w600)),
                    ],
                  ),
              ],
            ),
            if (subtitleParts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(subtitleParts.join(' · '), style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...freight.map((f) => _chip(f, Colors.grey)),
                if (team) _chip('team', Colors.amber),
                if (ins.isNotEmpty) _chip(ins, Colors.grey),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: added
                      ? OutlinedButton.icon(
                          onPressed: () => _dismissAgent(a),
                          icon: const Icon(Icons.visibility_off_outlined, size: 18),
                          label: const Text('Hide from list'),
                        )
                      : ElevatedButton.icon(
                          onPressed: () => _addAgentToContacts(a),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add to contacts'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                ),
                if (!added) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _dismissAgent(a),
                    icon: const Icon(Icons.visibility_off_outlined),
                    tooltip: 'Hide',
                    color: Colors.brown[300],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrokerTile(Map<String, dynamic> b) {
    final company = (b['company'] ?? '').toString();
    final phone = (b['dispatch_phone'] ?? '').toString();
    final email = (b['email'] ?? '').toString();
    final state = (b['hq_state'] ?? '').toString();
    final freight = (b['freight_types'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.15),
          child: Icon(Icons.local_shipping, color: Colors.blue[700]),
        ),
        title: Text(company, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (freight.isNotEmpty)
              Text(freight, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            Row(
              children: [
                if (state.isNotEmpty) ...[
                  Icon(Icons.place, size: 12, color: Colors.grey[400]),
                  Text(' $state', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  const SizedBox(width: 8),
                ],
                if (phone.isNotEmpty)
                  Flexible(
                    child: Text(phone,
                        style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
            if (email.contains('@'))
              Text(email, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
        trailing: const Icon(Icons.add_circle_outline),
        onTap: () => _importBroker(b),
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
