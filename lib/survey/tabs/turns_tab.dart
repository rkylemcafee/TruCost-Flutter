// lib/survey/tabs/turns_tab.dart
//
// Turn by turn: every turn as a card with its own map, framed and with the
// trailer on it, exactly as the report will print it.
//
// The map is a picture, not a live map — sixty live maps in a scrolling list
// would stop a phone. Tap "Trailer" to work the corner on a live map; tap the
// card for photos, wording and the measured clearance.

import 'package:flutter/material.dart';
import '../map_image.dart';
import '../survey_data.dart';
import '../turn_map_editor.dart';
import '../turn_screen.dart';
import '../widgets/empty_note.dart';
import '../widgets/static_map.dart';

class TurnsTab extends StatelessWidget {
  const TurnsTab({super.key, required this.data, required this.onChanged});
  final SurveyData data;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d.points.isEmpty) {
      return RefreshIndicator(
        onRefresh: onChanged,
        child: const EmptyNote('No turns in this survey yet.\n\n'
            'Bring in the state\'s route survey from the list of surveys and every turn it names arrives here, in order.'),
      );
    }
    final unfiled = d.photos.where((p) => p['point_id'] == null).length;

    return RefreshIndicator(
      onRefresh: onChanged,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
        itemCount: d.points.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!d.haveDeck)
                _note(context, Colors.amber,
                    'No deck size yet, so no trailer is drawn. Enter the deck length and load width on Load & route.'),
              if (unfiled > 0)
                _note(context, Colors.amber,
                    '$unfiled photo(s) are not filed under any turn and will not be in the report. File them on trucost.app.'),
            ]);
          }
          final p = d.points[i - 1];
          return _TurnCard(data: d, point: p, onChanged: onChanged);
        },
      ),
    );
  }

  Widget _note(BuildContext context, MaterialColor c, String text) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.shade50,
          border: Border.all(color: c.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, color: c.shade900)),
      );
}

class _TurnCard extends StatelessWidget {
  const _TurnCard({required this.data, required this.point, required this.onChanged});
  final SurveyData data;
  final Map<String, dynamic> point;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final p = point;
    final pics = data.photosFor(p['id']).length;
    final clearance = (p['clearance_in'] as num?)?.toInt();
    final hasTrailer = TrailerPlacement.fromAnnotations(p['annotations']) != null;
    final instruction = (p['instruction'] ?? '').toString();

    Future<void> openTurn() async {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => TurnScreen(surveyId: data.id, point: p, total: data.points.length),
      ));
      await onChanged();
    }

    Future<void> openTrailer() async {
      final saved = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => TurnMapEditor(data: data, point: p),
      ));
      if (saved == true) await onChanged();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: openTurn,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 14, child: Text('${p['seq']}', style: const TextStyle(fontSize: 12))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(instruction.isEmpty ? '(no wording yet)' : instruction,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      p['kind'] ?? 'turn',
                      if (clearance != null) 'clearance ${ftIn(clearance)}',
                      if (pics > 0) '$pics photo(s)',
                    ].join('  ·  '),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            StaticMap(
              url: data.turnMapUrl(p),
              caption: 'Turn ${p['seq']}${instruction.isEmpty ? '' : ' — $instruction'}',
            ),
            const SizedBox(height: 6),
            Row(children: [
              TextButton.icon(
                onPressed: data.sealed ? null : openTrailer,
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: Text(hasTrailer ? 'Move trailer' : (data.haveDeck ? 'Place trailer' : 'Frame the map')),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: openTurn,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Photos & notes'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
