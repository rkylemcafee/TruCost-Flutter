import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../common/state_picker_screen.dart';

/// Admin-only screen for curating the SHARED agent directory.
/// Anything saved here appears in every driver's Agents tab.
///
/// Gated two ways:
///   • UI: this screen checks profiles.role and locks out non-admins.
///   • DB: agent_directory write RLS only allows admin / assistant_admin
///     (see 05_admin_roles_and_agent_rls.sql) — the real enforcement.
///
/// Goes in: lib/admin/agent_admin_screen.dart

const Color _kGreen = Color(0xFF2E6E3A);

const List<String> kFreightTypes = [
  'van', 'reefer', 'flatbed', 'stepdeck', 'oversize', 'heavy',
  'project', 'hotshot', 'power_only', 'partial', 'tanker', 'intermodal',
];

const List<String> kTrailerTypes = [
  'van', 'reefer', 'flatbed', 'stepdeck', 'double_drop', 'rgn',
  'lowboy', 'conestoga', 'hotshot', 'power_only',
];

const List<List<dynamic>> kInsurancePresets = [
  ['100K', 100000],
  ['250K', 250000],
  ['500K', 500000],
  ['1M', 1000000],
];

String prettyTag(String s) {
  const upper = {'rgn': 'RGN', 'ltl': 'LTL', 'tl': 'TL'};
  if (upper.containsKey(s)) return upper[s]!;
  return s
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String fmtMoney(num? v) {
  if (v == null || v == 0) return '—';
  if (v >= 1000000) return '\$${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M';
  if (v >= 1000) return '\$${(v / 1000).round()}K';
  return '\$$v';
}

class AgentAdminScreen extends StatefulWidget {
  const AgentAdminScreen({super.key});

  @override
  State<AgentAdminScreen> createState() => _AgentAdminScreenState();
}

class _AgentAdminScreenState extends State<AgentAdminScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isAdmin = false;
  String? _role;
  List<Map<String, dynamic>> _agents = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _load() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }
      final p = await _supabase
          .from('profiles')
          .select('role')
          .eq('user_id', user.id)
          .maybeSingle();
      _role = p?['role']?.toString();
      _isAdmin = _role == 'admin' || _role == 'assistant_admin';

      if (_isAdmin) {
        final rows = await _supabase
            .from('agent_directory')
            .select()
            .order('name');
        _agents = (rows as List).cast<Map<String, dynamic>>();
      }
    } catch (e) {
      _toast('Could not load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _AgentFormScreen(existing: existing)),
    );
    if (saved == true) {
      setState(() => _loading = true);
      await _load();
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> a) async {
    final next = !(a['is_active'] == true);
    try {
      await _supabase
          .from('agent_directory')
          .update({'is_active': next}).eq('id', a['id']);
      _toast(next ? 'Agent activated' : 'Agent hidden from everyone');
      await _load();
    } catch (e) {
      _toast('Update failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        title: const Text('Manage Agents'),
      ),
      floatingActionButton: (_isAdmin && !_loading)
          ? FloatingActionButton.extended(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('New Agent'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_isAdmin
              ? _locked()
              : _list(),
    );
  }

  Widget _locked() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('Admin access only',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'This area is for managing the shared agent directory. '
              'Ask an admin to grant you access.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    if (_agents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.badge_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text('No agents yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Tap “New Agent” to add the first one.',
                  style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }

    final active = _agents.where((a) => a['is_active'] == true).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: _agents.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                '${_agents.length} agent${_agents.length == 1 ? '' : 's'} · $active live on every device',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            );
          }
          return _agentCard(_agents[i - 1]);
        },
      ),
    );
  }

  Widget _agentCard(Map<String, dynamic> a) {
    final active = a['is_active'] == true;
    final name = (a['name'] ?? '').toString();
    final company = (a['company'] ?? '').toString();
    final states = ((a['origin_states'] as List?) ?? const []).cast<String>();
    final freight = ((a['freight_types'] as List?) ?? const []).cast<String>();
    final team = a['typically_team'] == true;
    final ins = a['min_cargo_insurance'] as num?;

    return Card(
      elevation: 0,
      color: active ? const Color(0xFFF1F5EE) : Colors.grey[200],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openForm(existing: a),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name.isEmpty ? '(no name)' : name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: active ? Colors.black87 : Colors.grey[600],
                      ),
                    ),
                  ),
                  if (!active)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Hidden',
                          style: TextStyle(fontSize: 11, color: Colors.white)),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _openForm(existing: a);
                      if (v == 'toggle') _toggleActive(a);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(active ? 'Hide from everyone' : 'Make visible'),
                      ),
                    ],
                  ),
                ],
              ),
              if (company.isNotEmpty || states.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    [
                      if (company.isNotEmpty) company,
                      if (states.isNotEmpty) 'out of ${states.join(', ')}',
                    ].join(' · '),
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                ),
              if (freight.isNotEmpty || team || ins != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...freight.take(4).map((f) => _miniChip(prettyTag(f))),
                    if (team) _miniChip('Team', amber: true),
                    if (ins != null) _miniChip('${fmtMoney(ins)} cargo'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniChip(String label, {bool amber = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: amber ? const Color(0xFFFDF1D6) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 12,
            color: amber ? const Color(0xFF9A6B00) : Colors.black87,
          )),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  Add / Edit form
// ════════════════════════════════════════════════════════════

class _AgentFormScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _AgentFormScreen({this.existing});

  @override
  State<_AgentFormScreen> createState() => _AgentFormScreenState();
}

class _AgentFormScreenState extends State<_AgentFormScreen> {
  final _supabase = Supabase.instance.client;

  final _nameCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _insCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final Set<String> _freight = {};
  final Set<String> _trailer = {};
  List<String> _states = [];
  bool _team = false;
  bool _active = true;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = (e['name'] ?? '').toString();
      _companyCtrl.text = (e['company'] ?? '').toString();
      _phoneCtrl.text = (e['phone'] ?? '').toString();
      _emailCtrl.text = (e['email'] ?? '').toString();
      final ins = e['min_cargo_insurance'];
      _insCtrl.text = ins == null ? '' : (ins as num).toInt().toString();
      _notesCtrl.text = (e['notes'] ?? '').toString();
      _freight.addAll(((e['freight_types'] as List?) ?? const []).cast<String>());
      _trailer.addAll(((e['trailer_types'] as List?) ?? const []).cast<String>());
      _states = ((e['origin_states'] as List?) ?? const []).cast<String>();
      _team = e['typically_team'] == true;
      _active = e['is_active'] != false;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _companyCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _insCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pickStates() async {
    final res = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => StatePickerScreen(initial: _states, title: 'Coverage States'),
      ),
    );
    if (res != null) setState(() => _states = res);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('Name is required');
      return;
    }
    setState(() => _saving = true);

    String? t(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    final data = <String, dynamic>{
      'name': name,
      'company': t(_companyCtrl),
      'phone': t(_phoneCtrl),
      'email': t(_emailCtrl),
      'freight_types': _freight.toList(),
      'trailer_types': _trailer.toList(),
      'origin_states': _states,
      'min_cargo_insurance': double.tryParse(_insCtrl.text.trim()),
      'typically_team': _team,
      'is_active': _active,
      'notes': t(_notesCtrl),
    };

    try {
      if (_isEdit) {
        await _supabase
            .from('agent_directory')
            .update(data)
            .eq('id', widget.existing!['id']);
      } else {
        await _supabase.from('agent_directory').insert(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      _toast('Save failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        title: Text(_isEdit ? 'Edit Agent' : 'New Agent'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _text(_nameCtrl, 'Name *', cap: TextCapitalization.words),
          _text(_companyCtrl, 'Company', cap: TextCapitalization.words),
          Row(
            children: [
              Expanded(child: _text(_phoneCtrl, 'Phone', kb: TextInputType.phone)),
              const SizedBox(width: 12),
              Expanded(child: _text(_emailCtrl, 'Email', kb: TextInputType.emailAddress)),
            ],
          ),

          const SizedBox(height: 8),
          _label('Freight types'),
          _chips(kFreightTypes, _freight),

          const SizedBox(height: 12),
          _label('Trailer types'),
          _chips(kTrailerTypes, _trailer),

          const SizedBox(height: 16),
          _label('Coverage states'),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _pickStates,
            icon: const Icon(Icons.map_outlined, size: 20),
            label: Text(
              _states.isEmpty
                  ? 'Choose states'
                  : (_states.length >= kUsStates.length
                      ? 'All 48 states'
                      : _states.join(', ')),
            ),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              minimumSize: const Size.fromHeight(0),
            ),
          ),

          const SizedBox(height: 16),
          _text(_insCtrl, 'Minimum cargo insurance',
              kb: TextInputType.number, prefix: '\$'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: kInsurancePresets
                .map((p) => ActionChip(
                      label: Text('\$${p[0]}'),
                      onPressed: () =>
                          setState(() => _insCtrl.text = (p[1] as int).toString()),
                    ))
                .toList(),
          ),

          const SizedBox(height: 4),
          SwitchListTile(
            title: const Text('Typically runs team'),
            value: _team,
            activeColor: _kGreen,
            onChanged: (v) => setState(() => _team = v),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Visible to all drivers'),
            subtitle: const Text('Off = saved but hidden from everyone'),
            value: _active,
            activeColor: _kGreen,
            onChanged: (v) => setState(() => _active = v),
            contentPadding: EdgeInsets.zero,
          ),

          const SizedBox(height: 8),
          _text(_notesCtrl, 'Notes', maxLines: 3),

          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Save changes' : 'Add agent',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _label(String s) => Text(s,
      style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700]));

  Widget _text(TextEditingController c, String label,
      {TextInputType? kb,
      TextCapitalization cap = TextCapitalization.none,
      String? prefix,
      int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: kb,
        textCapitalization: cap,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _chips(List<String> all, Set<String> selected) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: all.map((tag) {
        final on = selected.contains(tag);
        return FilterChip(
          label: Text(prettyTag(tag)),
          selected: on,
          selectedColor: _kGreen.withOpacity(0.18),
          checkmarkColor: _kGreen,
          onSelected: (v) => setState(() {
            if (v) {
              selected.add(tag);
            } else {
              selected.remove(tag);
            }
          }),
        );
      }).toList(),
    );
  }
}
