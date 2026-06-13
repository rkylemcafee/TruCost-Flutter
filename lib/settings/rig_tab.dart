import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

/// Fleet manager (Rig tab). Up to 2 trucks and 3 trailers, each with its own
/// cost basis and — for trucks — its own MPG. Flag the active pair you're
/// running; the calculator does the math on that exact truck + trailer.
///
/// Goes in: lib/settings/rig_tab.dart

const int _maxTrucks = 2;
const int _maxTrailers = 3;

const List<List<String>> _trailerTypes = [
  ['flatbed', 'Flatbed'],
  ['step_deck', 'Step Deck'],
  ['double_drop', 'Double Drop'],
  ['dry_van', 'Dry Van'],
  ['reefer', 'Reefer'],
];

class RigTab extends StatefulWidget {
  const RigTab({super.key});
  @override
  State<RigTab> createState() => _RigTabState();
}

class _RigTabState extends State<RigTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _trucks = [];
  List<Map<String, dynamic>> _trailers = [];
  String? _activeTruckId;
  String? _activeTrailerId;
  bool _loading = true;

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

  String _numStr(dynamic v) {
    if (v == null) return '';
    final d = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (d == null) return v.toString();
    if (d == d.roundToDouble()) return d.toInt().toString();
    return d.toString();
  }

  String _trailerLabel(String key) {
    for (final t in _trailerTypes) {
      if (t[0] == key) return t[1];
    }
    return key.isEmpty ? 'Trailer' : key;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final prof = await _supabase
          .from('profiles')
          .select('active_truck_id, active_trailer_id')
          .eq('user_id', user.id)
          .maybeSingle();
      _activeTruckId = prof?['active_truck_id']?.toString();
      _activeTrailerId = prof?['active_trailer_id']?.toString();

      final units = await _supabase
          .from('units')
          .select()
          .eq('user_id', user.id)
          .filter('deleted_at', 'is', null);
      final list = List<Map<String, dynamic>>.from(units);
      _trucks = list.where((u) => u['unit_type'] == 'truck').toList();
      _trailers = list.where((u) => u['unit_type'] == 'trailer').toList();
    } catch (e) {
      _toast('Could not load your rig: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setActive(String unitId, String type) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      // keep is_active in sync (one active per type)
      await _supabase
          .from('units')
          .update({'is_active': false})
          .eq('user_id', user.id)
          .eq('unit_type', type);
      await _supabase.from('units').update({'is_active': true}).eq('id', unitId);
      // point the profile at it
      final key = type == 'truck' ? 'active_truck_id' : 'active_trailer_id';
      await _supabase.from('profiles').update({key: unitId}).eq('user_id', user.id);
      await _load();
    } catch (e) {
      _toast('Could not switch: $e');
    }
  }

  Future<void> _delete(Map<String, dynamic> unit) async {
    final type = unit['unit_type'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove this ${type == 'truck' ? 'truck' : 'trailer'}?'),
        content: const Text('This deletes it from your rig.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final user = _supabase.auth.currentUser;
      final wasActive = unit['id'].toString() ==
          (type == 'truck' ? _activeTruckId : _activeTrailerId);
      await _supabase.from('units').update({
        'deleted_at': DateTime.now().toIso8601String(),
        'is_active': false,
      }).eq('id', unit['id']);
      if (wasActive && user != null) {
        final key = type == 'truck' ? 'active_truck_id' : 'active_trailer_id';
        await _supabase.from('profiles').update({key: null}).eq('user_id', user.id);
      }
      await _load();
    } catch (e) {
      _toast('Could not delete: $e');
    }
  }

  Future<void> _addOrEdit({Map<String, dynamic>? existing, required String type}) async {
    final isTruck = type == 'truck';
    final numCtrl = TextEditingController(text: existing?['unit_number']?.toString() ?? '');
    final priceCtrl = TextEditingController(
        text: existing != null ? _numStr(existing['purchase_price']) : (isTruck ? '140000' : '40000'));
    final deprecCtrl = TextEditingController(
        text: existing != null ? _numStr(existing['depreciation_pct']) : '20');
    final paymentCtrl = TextEditingController(
        text: existing != null ? _numStr(existing['monthly_payment']) : '');
    final emptyMpgCtrl =
        TextEditingController(text: existing != null ? _numStr(existing['empty_mpg']) : '8');
    final loadedMpgCtrl =
        TextEditingController(text: existing != null ? _numStr(existing['loaded_mpg']) : '6');
    String costMode = (existing?['cost_mode'] ?? 'owned').toString();
    String trailerSubtype = (existing?['trailer_subtype'] ?? 'flatbed').toString();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing != null
              ? 'Edit ${isTruck ? 'Truck' : 'Trailer'}'
              : 'Add ${isTruck ? 'Truck' : 'Trailer'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isTruck) ...[
                  DropdownButtonFormField<String>(
                    value: trailerSubtype,
                    decoration: const InputDecoration(
                        labelText: 'Type', isDense: true, border: OutlineInputBorder()),
                    items: _trailerTypes
                        .map((t) => DropdownMenuItem(value: t[0], child: Text(t[1])))
                        .toList(),
                    onChanged: (v) => setD(() => trailerSubtype = v ?? 'flatbed'),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: numCtrl,
                  decoration: InputDecoration(
                      labelText: '${isTruck ? 'Truck' : 'Trailer'} number',
                      hintText: isTruck ? 'e.g. 1010' : 'e.g. 220',
                      isDense: true,
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'owned', label: Text('Owned')),
                    ButtonSegment(value: 'financed', label: Text('Financed')),
                  ],
                  selected: {costMode},
                  onSelectionChanged: (v) => setD(() => costMode = v.first),
                ),
                const SizedBox(height: 10),
                if (costMode == 'owned') ...[
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Purchase price',
                        prefixText: '\$ ',
                        isDense: true,
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: deprecCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Annual depreciation',
                        suffixText: '%',
                        isDense: true,
                        border: OutlineInputBorder()),
                  ),
                ] else ...[
                  TextField(
                    controller: paymentCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Monthly payment',
                        prefixText: '\$ ',
                        isDense: true,
                        border: OutlineInputBorder()),
                  ),
                ],
                if (isTruck) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: emptyMpgCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Empty MPG', isDense: true, border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: loadedMpgCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Loaded MPG', isDense: true, border: OutlineInputBorder()),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true) return;

    final data = <String, dynamic>{
      'unit_type': type,
      'unit_number': numCtrl.text.trim(),
      'cost_mode': costMode,
      'purchase_price': costMode == 'owned' ? double.tryParse(priceCtrl.text.trim()) : null,
      'depreciation_pct': costMode == 'owned' ? double.tryParse(deprecCtrl.text.trim()) : null,
      'monthly_payment': costMode == 'financed' ? double.tryParse(paymentCtrl.text.trim()) : null,
    };
    if (isTruck) {
      data['empty_mpg'] = double.tryParse(emptyMpgCtrl.text.trim());
      data['loaded_mpg'] = double.tryParse(loadedMpgCtrl.text.trim());
    } else {
      data['trailer_subtype'] = trailerSubtype;
    }

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      if (existing != null) {
        await _supabase.from('units').update(data).eq('id', existing['id']);
      } else {
        final isFirst = (isTruck ? _trucks : _trailers).isEmpty;
        final inserted = await _supabase
            .from('units')
            .insert({...data, 'user_id': user.id, 'is_active': isFirst})
            .select('id')
            .single();
        if (isFirst) {
          final key = isTruck ? 'active_truck_id' : 'active_trailer_id';
          await _supabase
              .from('profiles')
              .update({key: inserted['id']}).eq('user_id', user.id);
        }
      }
      await _load();
    } catch (e) {
      _toast('Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader('Trucks', _trucks.length, _maxTrucks),
        const SizedBox(height: 8),
        ..._trucks.map((t) => _unitCard(t, 'truck')),
        if (_trucks.length < _maxTrucks)
          _addButton('Add Truck', () => _addOrEdit(type: 'truck')),
        const SizedBox(height: 24),
        _sectionHeader('Trailers', _trailers.length, _maxTrailers),
        const SizedBox(height: 8),
        ..._trailers.map((t) => _unitCard(t, 'trailer')),
        if (_trailers.length < _maxTrailers)
          _addButton('Add Trailer', () => _addOrEdit(type: 'trailer')),
        const SizedBox(height: 16),
      ],
    );
  }

  void _showPhotoOptions(Map<String, dynamic> unit) {
    final hasPhoto = (unit['photo_url'] ?? '').toString().isNotEmpty;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickUnitPhoto(unit, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickUnitPhoto(unit, ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeUnitPhoto(unit);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickUnitPhoto(Map<String, dynamic> unit, ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final bytes = await picked.readAsBytes();
      final path = '${user.id}/${unit['unit_type']}_${unit['id']}.jpg';
      await _supabase.storage.from('rig-photos').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
          );
      final url =
          '${_supabase.storage.from('rig-photos').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      await _supabase.from('units').update({'photo_url': url}).eq('id', unit['id']);
      await _load();
    } catch (e) {
      _toast('Could not set photo: $e');
    }
  }

  Future<void> _removeUnitPhoto(Map<String, dynamic> unit) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      await _supabase.from('units').update({'photo_url': null}).eq('id', unit['id']);
      try {
        await _supabase.storage
            .from('rig-photos')
            .remove(['${user.id}/${unit['unit_type']}_${unit['id']}.jpg']);
      } catch (_) {}
      await _load();
    } catch (e) {
      _toast('Could not remove photo: $e');
    }
  }

  Widget _buildUnitLeading(Map<String, dynamic> u, bool isTruck, bool active, String photoUrl) {
    final fallback = Icon(isTruck ? Icons.local_shipping : Icons.rv_hookup,
        color: active ? Colors.green[700] : Colors.blueGrey);
    if (photoUrl.isNotEmpty) {
      final img = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          photoUrl,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => SizedBox(width: 44, height: 44, child: fallback),
        ),
      );
      return isTruck ? GestureDetector(onTap: () => _showPhotoOptions(u), child: img) : img;
    }
    if (isTruck) {
      return GestureDetector(
        onTap: () => _showPhotoOptions(u),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.add_a_photo_outlined, size: 20, color: Colors.blueGrey[300]),
        ),
      );
    }
    return SizedBox(width: 44, height: 44, child: fallback);
  }

  Widget _sectionHeader(String title, int count, int max) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        Text('$count / $max', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      ],
    );
  }

  Widget _unitCard(Map<String, dynamic> u, String type) {
    final isTruck = type == 'truck';
    final id = u['id'].toString();
    final active = id == (isTruck ? _activeTruckId : _activeTrailerId);
    final number = (u['unit_number'] ?? '').toString();
    final mode = (u['cost_mode'] ?? 'owned').toString();
    final title = isTruck
        ? (number.isNotEmpty ? 'Truck $number' : 'Truck')
        : ('${_trailerLabel((u['trailer_subtype'] ?? '').toString())}${number.isNotEmpty ? ' $number' : ''}');
    final cost = mode == 'owned'
        ? '\$${_numStr(u['purchase_price'])} owned'
        : '\$${_numStr(u['monthly_payment'])}/mo';
    final mpg = isTruck ? '${_numStr(u['empty_mpg'])}/${_numStr(u['loaded_mpg'])} mpg' : '';
    final photoUrl = (u['photo_url'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: active ? Colors.green : Colors.grey.shade300, width: active ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            _buildUnitLeading(u, isTruck, active, photoUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                        child: Text(title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis)),
                    if (active) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.green[600], borderRadius: BorderRadius.circular(20)),
                        child: const Text('IN USE',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text([cost, mpg].where((s) => s.isNotEmpty).join('  •  '),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  if (!active)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: GestureDetector(
                        onTap: () => _setActive(id, type),
                        child: Text('Use this ${isTruck ? 'truck' : 'trailer'}',
                            style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'photo') _showPhotoOptions(u);
                if (v == 'edit') _addOrEdit(existing: u, type: type);
                if (v == 'delete') _delete(u);
              },
              itemBuilder: (_) => [
                if (isTruck) const PopupMenuItem(value: 'photo', child: Text('Photo')),
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _addButton(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add),
        label: Text(label),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
      ),
    );
  }
}
