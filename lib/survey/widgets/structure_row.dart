// lib/survey/widgets/structure_row.dart
//
// One bridge or overpass, with what was decided about it.
//
// The sorting into "passes under" and "carries the load" is the software's
// guess from the bridge inventory, and the guess is wrong often enough at an
// interchange that the escort must be able to overrule it from the truck.
// That is the same ruling the web records — status and kind on the survey's
// own copy of the structure — so either screen can make it.

import 'package:flutter/material.dart';
import '../map_image.dart';
import '../survey_data.dart';
import '../survey_repository.dart';
import 'static_map.dart';

const statusLabel = {'review': 'To look at', 'include': 'In the report', 'ignore': 'Not an issue'};

/// "120 ft · 3 spans, longest 50 ft · rated 36 tons operating (72,000 lb) · built 1968"
///
/// Facts, never a verdict: whether a bridge carries a load is an engineer's
/// call, and the inventory's rating is where that conversation starts.
String bridgeFacts(Map<String, dynamic> s, int? loadLbs) {
  String? ft(num? n) => n == null ? null : '${_thousands(n.round())} ft';
  final spans = (s['main_spans'] as num?)?.toInt();
  final maxSpan = s['max_span_ft'] as num?;
  String? spanText;
  if (spans != null || maxSpan != null) {
    if (spans == 1) {
      spanText = 'a single span${maxSpan != null ? ' of ${ft(maxSpan)}' : ''}';
    } else {
      final count = spans != null ? '$spans spans' : 'several spans';
      spanText = maxSpan == null ? count : '$count, longest ${ft(maxSpan)}';
    }
  }
  final tons = s['operating_tons'] as num?;
  String? rating;
  if (tons != null && tons > 0) {
    rating = 'rated $tons tons operating (${_thousands((tons * 2000).round())} lb)';
    if (loadLbs != null) rating += '; this load is ${_thousands(loadLbs)} lb';
  }
  return [
    ft(s['length_ft'] as num?) ?? 'length not on file',
    spanText,
    rating,
    if (s['year_built'] != null) 'built ${s['year_built']}',
  ].whereType<String>().join(' · ');
}

String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

class StructureRow extends StatelessWidget {
  const StructureRow({
    super.key,
    required this.data,
    required this.s,
    required this.onChanged,
    this.showMap = true,
    this.onLocate,
  });

  final SurveyData data;
  final Map<String, dynamic> s;
  final Future<void> Function() onChanged;
  final bool showMap;

  /// Bridges tab: show this one on the overview map.
  final VoidCallback? onLocate;

  bool get _over => s['kind'] == 'cross';

  Future<void> _patch(BuildContext context, Map<String, dynamic> patch) async {
    try {
      await SurveyRepository().updateStructure(s['id'], patch);
      await onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _notes(BuildContext context) async {
    final c = TextEditingController(text: (s['notes'] ?? '').toString());
    final a = TextEditingController(text: (s['action'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s['carries'] ?? 'Structure'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: a,
            decoration: const InputDecoration(labelText: 'What we do here', hintText: 'Lift wires, use the left lane…'),
          ),
          const SizedBox(height: 10),
          TextField(controller: c, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Notes')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _patch(context, {'notes': c.text.trim(), 'action': a.text.trim()});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = (s['clearance_in'] as num?)?.toInt();
    final low = data.tooLow(s);
    final h = data.loadHeightIn;
    final locked = data.sealed;
    final status = (s['status'] ?? 'review') as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: low ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 64,
              child: Text(
                _over
                    ? ((s['length_ft'] as num?) == null ? '—' : '${(s['length_ft'] as num).round()} ft')
                    : ftIn(c),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: low ? Colors.red.shade800 : null,
                ),
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['carries'] ?? 'structure', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  [
                    milesLabel(s['miles_along']),
                    if (s['crosses'] != null) 'over ${s['crosses']}',
                  ].where((x) => x.isNotEmpty).join('  ·  '),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (low && h != null && c != null)
                  Text("${ftIn(h - c)} too low for a ${ftIn(h)} load",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.red.shade800)),
                if (_over)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(bridgeFacts(s, data.loadWeightLbs), style: const TextStyle(fontSize: 12)),
                  ),
                if ((s['action'] ?? '').toString().isNotEmpty)
                  Text('Do: ${s['action']}', style: const TextStyle(fontSize: 12)),
                if ((s['notes'] ?? '').toString().isNotEmpty)
                  Text(s['notes'], style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
              ]),
            ),
            if (onLocate != null)
              IconButton(onPressed: onLocate, icon: const Icon(Icons.my_location, size: 20), tooltip: 'Show on map'),
          ]),
          if (showMap) ...[
            const SizedBox(height: 8),
            StaticMap(
              url: data.structureMapUrl(s),
              aspect: 640 / 360,
              caption: '${_over ? 'Bridge' : 'Overpass'} — ${s['carries'] ?? ''}',
            ),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final e in statusLabel.entries)
              ChoiceChip(
                label: Text(e.value, style: const TextStyle(fontSize: 12)),
                selected: status == e.key,
                visualDensity: VisualDensity.compact,
                onSelected: locked ? null : (_) => _patch(context, {'status': e.key}),
              ),
            TextButton(
              onPressed: locked
                  ? null
                  : () => _patch(context, {'kind': _over ? 'under' : 'cross', 'kind_locked': true}),
              child: Text(_over ? 'We pass under it' : 'We go over it', style: const TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: locked ? null : () => _notes(context),
              child: const Text('Notes', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ]),
      ),
    );
  }
}
