// lib/survey/tabs/overpasses_tab.dart
//
// Overpasses: everything the load passes under, each with its own map zoomed
// in close enough to see which road is on top.
//
// The question here is one number against another — the clearance against
// the load — so the clearance is the biggest thing on each card and anything
// too low is red before you read a word.

import 'package:flutter/material.dart';
import '../map_image.dart';
import '../survey_data.dart';
import '../widgets/empty_note.dart';
import '../widgets/static_map.dart';
import '../widgets/structure_row.dart';
import 'bridges_tab.dart';

class OverpassesTab extends StatelessWidget {
  const OverpassesTab({super.key, required this.data, required this.onChanged});
  final SurveyData data;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d.structures.isEmpty) {
      return RefreshIndicator(
        onRefresh: onChanged,
        child: const EmptyNote('The route has not been checked for overpasses yet.\n\n'
            'Open this survey on trucost.app and press "Check the route". What it finds shows up here.'),
      );
    }
    final rows = d.overhead;
    final low = rows.where(d.tooLow).length;
    final h = d.loadHeightIn;

    return RefreshIndicator(
      onRefresh: onChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
        children: [
          Text(
            '${rows.length} structure(s) over this route'
            '${h == null ? '' : low > 0 ? ', $low too low for ${ftIn(h)}' : ', all clear at ${ftIn(h)}'}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: low > 0 ? Colors.red.shade800 : null,
            ),
          ),
          if (h == null)
            const Text('Enter the load height on Load & route and anything too low gets flagged.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          if (rows.isNotEmpty && d.pieces.isNotEmpty) ...[
            StaticMap(url: d.overpassesMapUrl(), caption: '${d.title} — overpasses'),
            const SizedBox(height: 4),
            const Text('Red: too low for the load. Orange: clears it, or no height on file.',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 12),
          ],
          for (final s in rows) StructureRow(data: d, s: s, onChanged: onChanged),
          if (d.ignored.any((s) => s['kind'] != 'cross')) IgnoredStructures(data: d, onChanged: onChanged),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Clearances are the state\'s filing. Resurfacing changes a clearance without changing the record — '
              'measure anything close.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
