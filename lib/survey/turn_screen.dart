// lib/survey/turn_screen.dart
//
// One turn, with the whole screen to itself.
//
// This is the field screen. An escort is standing at the spot, so the job is
// photograph it, say what the driver needs to know, and record the clearance —
// in that order, with the fewest taps that will do.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'survey_repository.dart';

const _kinds = <String, String>{
  'turn': 'Turn',
  'overpass': 'Overhead clearance',
  'narrow': 'Narrow',
  'rr_crossing': 'Railroad crossing',
  'utility': 'Utility line',
  'bridge': 'Bridge',
  'hazard': 'Hazard',
  'note': 'Note',
};

class TurnScreen extends StatefulWidget {
  const TurnScreen({super.key, required this.surveyId, required this.point, required this.total});
  final String surveyId;
  final Map<String, dynamic> point;
  final int total;

  @override
  State<TurnScreen> createState() => _TurnScreenState();
}

class _TurnScreenState extends State<TurnScreen> {
  final _repo = SurveyRepository();
  late final TextEditingController _instruction;
  late String _kind;
  late final TextEditingController _feet;
  late final TextEditingController _inches;

  List<Map<String, dynamic>> _photos = [];
  bool _busy = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _instruction = TextEditingController(text: widget.point['instruction'] ?? '');
    _kind = widget.point['kind'] ?? 'turn';
    final c = widget.point['clearance_in'] as int?;
    _feet = TextEditingController(text: c == null ? '' : '${c ~/ 12}');
    _inches = TextEditingController(text: c == null ? '' : '${c % 12}');
    _loadPhotos();
  }

  @override
  void dispose() {
    _instruction.dispose();
    _feet.dispose();
    _inches.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    final all = await _repo.photos(widget.surveyId);
    if (!mounted) return;
    setState(() => _photos = all.where((p) => p['point_id'] == widget.point['id']).toList());
  }

  int? get _clearanceIn {
    final f = int.tryParse(_feet.text.trim());
    final i = int.tryParse(_inches.text.trim()) ?? 0;
    if (f == null && _inches.text.trim().isEmpty) return null;
    return (f ?? 0) * 12 + i;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _repo.updatePoint(widget.point['id'], {
        'instruction': _instruction.text.trim(),
        'kind': _kind,
        'clearance_in': _clearanceIn,
      });
      if (!mounted) return;
      setState(() { _dirty = false; _busy = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  /// Where the phone is. Asked at the moment the shutter goes, because that is
  /// when the answer is true.
  Future<Position?> _position() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 12)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _takePhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2400,
    );
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      // Taken here, now — so the handset's position is the picture's position.
      final pos = source == ImageSource.camera ? await _position() : null;
      await _repo.addPhoto(
        surveyId: widget.surveyId,
        pointId: widget.point['id'],
        file: File(picked.path),
        lat: pos?.latitude,
        lng: pos?.longitude,
      );
      await _loadPhotos();
      if (!mounted) return;
      setState(() => _busy = false);
      final where = pos == null ? '' : ' at ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo added$where')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.point;
    final lat = (p['lat'] as num).toDouble();
    final lng = (p['lng'] as num).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text('Turn ${p['seq']} of ${widget.total}'),
        actions: [
          if (_dirty)
            TextButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          // ── Where it is ────────────────────────────────────────────────
          Row(children: [
            const Icon(Icons.place_outlined, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Text('${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          const SizedBox(height: 16),

          // ── What the driver needs to know ──────────────────────────────
          const Text('What the driver needs to know',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _instruction,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() => _dirty = true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Be in the left lane to swing right onto University Pkwy',
            ),
          ),
          const SizedBox(height: 20),

          // ── What kind of point ─────────────────────────────────────────
          const Text('What is it', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: _kinds.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() { _kind = v ?? 'turn'; _dirty = true; }),
          ),
          const SizedBox(height: 20),

          // ── Measured clearance ─────────────────────────────────────────
          const Text('Clearance, if you measured it',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(
              controller: _feet,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _dirty = true),
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, suffixText: 'ft'),
            )),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: _inches,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _dirty = true),
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, suffixText: 'in'),
            )),
          ]),
          const SizedBox(height: 24),

          // ── Photographs ────────────────────────────────────────────────
          Row(children: [
            const Text('Photos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${_photos.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          const SizedBox(height: 8),
          if (_photos.isEmpty)
            Container(
              height: 90,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Nothing yet', style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: _photos.map((ph) {
                final plat = (ph['exif_lat'] as num?)?.toDouble();
                final plng = (ph['exif_lng'] as num?)?.toDouble();
                final away = (plat != null && plng != null) ? milesApart(plat, plng, lat, lng) : null;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(_repo.publicUrl(ph['storage_path']),
                          fit: BoxFit.cover, width: double.infinity),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    away == null
                        ? 'No position'
                        : away > 0.5
                            ? '${away.toStringAsFixed(1)} mi from this turn'
                            : 'At this turn',
                    style: TextStyle(
                      fontSize: 10,
                      color: away != null && away > 0.5 ? Colors.red.shade800 : Colors.grey,
                    ),
                  ),
                ]);
              }).toList(),
            ),
        ],
      ),

      // The two things you came here to do.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _takePhoto(ImageSource.camera),
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_camera),
                label: const Text('Take photo'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _busy ? null : () => _takePhoto(ImageSource.gallery),
              style: OutlinedButton.styleFrom(minimumSize: const Size(56, 52)),
              child: const Icon(Icons.photo_library_outlined),
            ),
          ]),
        ),
      ),
    );
  }
}
