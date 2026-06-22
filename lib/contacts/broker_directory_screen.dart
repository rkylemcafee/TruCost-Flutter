// lib/contacts/broker_directory_screen.dart
//
// Read-only browse of the shared `broker_directory` table. Tapping a broker
// returns its row (Map) to the caller via Navigator.pop — the caller (Contacts)
// decides what to do with it (copy into the user's contacts).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BrokerDirectoryScreen extends StatefulWidget {
  const BrokerDirectoryScreen({super.key});

  @override
  State<BrokerDirectoryScreen> createState() => _BrokerDirectoryScreenState();
}

class _BrokerDirectoryScreenState extends State<BrokerDirectoryScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _brokers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _supabase
          .from('broker_directory')
          .select()
          .eq('is_active', true)
          .order('company');
      setState(() {
        _brokers = List<Map<String, dynamic>>.from(rows);
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading directory: $e')),
        );
      }
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = _brokers;
      } else {
        _filtered = _brokers.where((b) {
          final c = (b['company'] ?? '').toString().toLowerCase();
          final f = (b['freight_types'] ?? '').toString().toLowerCase();
          final s = (b['hq_state'] ?? '').toString().toLowerCase();
          final n = (b['notes'] ?? '').toString().toLowerCase();
          return c.contains(q) || f.contains(q) || s.contains(q) || n.contains(q);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Broker Directory')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search broker, freight type, state...',
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
                    child: Text(
                      '${_filtered.length} broker${_filtered.length != 1 ? 's' : ''} · tap to add to your contacts',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(child: Text('No brokers found.', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _tile(_filtered[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _tile(Map<String, dynamic> b) {
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
        onTap: () => Navigator.pop(context, b),
      ),
    );
  }
}
