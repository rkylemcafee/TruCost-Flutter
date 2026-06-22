import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../help/help_content.dart';
import 'receipt_capture_screen.dart'; // for DocType + DocTypeInfo

/// Browse every saved document — receipts (from expenses) and load docs
/// (from trip_documents) — filtered by type and/or load, newest first.
///
/// Images only live in the cloud for the 3 most recent loads (the rolling
/// retention window). For older loads the row still shows all the data, but
/// the image has been purged from the cloud and lives on the phone, so the
/// viewer says so instead of showing a broken image.
///
/// Goes in: lib/expenses/document_viewer_screen.dart

class _Doc {
  final String id;
  final DocType type;
  final String? tripId;
  final DateTime? date;
  final String title;
  final String? subtitle;
  final String? storagePath; // null => image purged from cloud (on phone only)
  _Doc({
    required this.id,
    required this.type,
    required this.tripId,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.storagePath,
  });
}

class DocumentViewerScreen extends StatefulWidget {
  const DocumentViewerScreen({super.key});
  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<_Doc> _all = [];
  final Map<String, String> _tripNames = {};

  DocType? _typeFilter; // null => all types
  String? _loadFilter; // null => all loads, '__none__' => no load, else tripId

  @override
  void initState() {
    super.initState();
    _load();
  }

  DocType _typeFromDb(String s) {
    switch (s) {
      case 'ratecon':
        return DocType.ratecon;
      case 'bol':
        return DocType.bol;
      case 'pod':
        return DocType.pod;
      case 'permit':
        return DocType.permit;
      case 'receipt':
        return DocType.receipt;
      default:
        return DocType.other;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final uid = user.id;

      final exp = await _supabase
          .from('expenses')
          .select('id, vendor, category, amount, expense_date, trip_id, receipt_url, created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(300);

      final docs = await _supabase
          .from('trip_documents')
          .select('id, doc_type, reference, notes, trip_id, storage_path, created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(300);

      final List<_Doc> list = [];

      for (final e in (exp as List)) {
        final amt = e['amount'];
        final vendor = (e['vendor'] ?? '').toString().trim();
        final cat = (e['category'] ?? 'Receipt').toString();
        final path = (e['receipt_url'] ?? '').toString();
        list.add(_Doc(
          id: e['id'].toString(),
          type: DocType.receipt,
          tripId: e['trip_id']?.toString(),
          date: DateTime.tryParse((e['expense_date'] ?? e['created_at'] ?? '').toString()),
          title: vendor.isNotEmpty ? vendor : cat,
          subtitle: amt != null ? '\$${_money(amt)} \u00b7 $cat' : cat,
          storagePath: path.isEmpty ? null : path,
        ));
      }

      for (final d in (docs as List)) {
        final ref = (d['reference'] ?? '').toString().trim();
        final note = (d['notes'] ?? '').toString().trim();
        final type = _typeFromDb((d['doc_type'] ?? 'other').toString());
        final path = (d['storage_path'] ?? '').toString();
        final parts = <String>[];
        if (ref.isNotEmpty) parts.add('Ref $ref');
        if (note.isNotEmpty) parts.add(note);
        list.add(_Doc(
          id: d['id'].toString(),
          type: type,
          tripId: d['trip_id']?.toString(),
          date: DateTime.tryParse((d['created_at'] ?? '').toString()),
          title: type.label,
          subtitle: parts.isEmpty ? null : parts.join(' \u00b7 '),
          storagePath: path.isEmpty ? null : path,
        ));
      }

      list.sort((a, b) => (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));

      // Resolve load names for the trips present.
      final tripIds = list.map((x) => x.tripId).whereType<String>().toSet().toList();
      _tripNames.clear();
      if (tripIds.isNotEmpty) {
        final trips = await _supabase
            .from('trips')
            .select('id, trip_name, origin, destination')
            .inFilter('id', tripIds);
        for (final t in (trips as List)) {
          final name = (t['trip_name'] ?? '').toString().trim();
          final label = name.isNotEmpty
              ? name
              : '${t['origin'] ?? '?'} \u2192 ${t['destination'] ?? '?'}';
          _tripNames[t['id'].toString()] = label;
        }
      }

      if (mounted) {
        setState(() {
          _all = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load documents: $e')),
        );
      }
    }
  }

  String _money(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    return d.toStringAsFixed(2);
  }

  String _loadNameFor(String? tripId) {
    if (tripId == null) return 'General';
    return _tripNames[tripId] ?? 'Load';
  }

  String _dateStr(DateTime? d) {
    if (d == null) return 'no date';
    return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
  }

  IconData _iconFor(DocType t) {
    switch (t) {
      case DocType.receipt:
        return Icons.receipt_long;
      case DocType.ratecon:
        return Icons.request_quote;
      case DocType.bol:
        return Icons.local_shipping;
      case DocType.pod:
        return Icons.assignment_turned_in;
      case DocType.permit:
        return Icons.verified;
      case DocType.other:
        return Icons.description;
    }
  }

  List<_Doc> get _filtered {
    return _all.where((d) {
      if (_typeFilter != null && d.type != _typeFilter) return false;
      if (_loadFilter == null) return true;
      if (_loadFilter == '__none__') return d.tripId == null;
      return d.tripId == _loadFilter;
    }).toList();
  }

  Future<void> _open(_Doc d) async {
    if (d.storagePath == null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(d.title),
          content: Text(
            'The image for this ${d.type.label.toLowerCase()} has been cleared from '
            'the cloud to save space. Your copy is on this phone:\n\n'
            'Files \u2192 TruCost \u2192 ${_loadNameFor(d.tripId)}'
            '${d.subtitle != null ? '\n\n${d.subtitle}' : ''}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    try {
      final url = await _supabase.storage.from('receipts').createSignedUrl(d.storagePath!, 3600);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _ImageView(title: d.title, url: url)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          const HelpButton(HelpScreens.documents),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _typeChip(null, 'All'),
                ...DocType.values.map((d) => _typeChip(d, d.shortLabel)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: DropdownButtonFormField<String?>(
              value: _loadFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Load',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _loadItems(),
              onChanged: (v) => setState(() => _loadFilter = v),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? _emptyState()
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _row(items[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(DocType? t, String label) {
    final sel = _typeFilter == t;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      selectedColor: Colors.blueGrey[700],
      labelStyle: TextStyle(color: sel ? Colors.white : Colors.black87),
      onSelected: (_) => setState(() => _typeFilter = t),
    );
  }

  List<DropdownMenuItem<String?>> _loadItems() {
    final ids = _all.map((d) => d.tripId).whereType<String>().toSet().toList();
    ids.sort((a, b) => _loadNameFor(b).compareTo(_loadNameFor(a)));
    final hasNone = _all.any((d) => d.tripId == null);
    return [
      const DropdownMenuItem<String?>(value: null, child: Text('All loads')),
      if (hasNone)
        const DropdownMenuItem<String?>(value: '__none__', child: Text('No load (general)')),
      ...ids.map((id) => DropdownMenuItem<String?>(
            value: id,
            child: Text(_loadNameFor(id), overflow: TextOverflow.ellipsis),
          )),
    ];
  }

  Widget _row(_Doc d) {
    final onPhoneOnly = d.storagePath == null;
    final sub = <String>[_loadNameFor(d.tripId), _dateStr(d.date)];
    if (d.subtitle != null) sub.add(d.subtitle!);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blueGrey[50],
        child: Icon(_iconFor(d.type), color: Colors.blueGrey[700], size: 20),
      ),
      title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub.join(' \u00b7 '), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: onPhoneOnly
          ? Icon(Icons.phone_iphone, size: 18, color: Colors.grey[500])
          : const Icon(Icons.chevron_right),
      onTap: () => _open(d),
    );
  }

  Widget _emptyState() {
    final what = _typeFilter == null ? 'documents' : '${_typeFilter!.label.toLowerCase()}s';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No $what found.\nScan some from the home screen.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], fontSize: 15),
        ),
      ),
    );
  }
}

class _ImageView extends StatelessWidget {
  final String title;
  final String url;
  const _ImageView({required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.network(
            url,
            loadingBuilder: (c, w, progress) =>
                progress == null ? w : const CircularProgressIndicator(color: Colors.white),
            errorBuilder: (c, e, s) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Could not load image.', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    );
  }
}
