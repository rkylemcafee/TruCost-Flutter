// lib/survey/import/roads_index.dart
//
// Port of the web app's src/lib/roadsIndex.ts `loadRoads`.
//
// Fetch the road geometry a route survey needs, and nothing else.
//
// scripts/export_state_roads.ts cuts one state's numbered routes out of
// highways.tsv — 148 MB that lives beside the router and will never be on
// Vercel — into one file per route number. Indiana is 6.9 MB across 251
// routes, and a survey names a dozen of them, so this fetches about 300 KB
// rather than the lot.
//
// The web fetches them from its own origin (/roads/...). The phone has no
// origin of its own, so it fetches the same files from the deployed site.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'route_from_survey.dart';

/// Where public/roads in the web repo is served.
///
/// www, because https://trucost.app answers every path with a 307 to
/// https://www.trucost.app. package:http would follow it, but going straight
/// there saves a round trip per road.
const String roadsBaseUrl = 'https://www.trucost.app/roads';

class LoadedRoads {
  final RoadNet net;

  /// Roads the survey names that have no geometry file, or failed to load.
  final List<String> missing;
  const LoadedRoads(this.net, this.missing);
}

/// The URL of one road's geometry, e.g. .../roads/IN/I-64.json.
Uri roadUrl(String state, String ref) =>
    Uri.parse('$roadsBaseUrl/$state/${Uri.encodeComponent(ref)}.json');

/// Build a graph of just these routes, in this state.
///
/// [client] is for tests; left out, a client is made and closed here.
Future<LoadedRoads> loadRoads(
  String state,
  List<String> refs, [
  void Function(int done, int total)? onProgress,
  http.Client? client,
]) async {
  final net = RoadNet();
  final missing = <String>[];
  final list = refs.toSet().toList();
  final http.Client c = client ?? http.Client();

  var done = 0;
  try {
    // Sequential on purpose. A dozen small files from the same origin is not
    // worth a parallel storm, and it lets the dialog count up honestly.
    for (final ref in list) {
      try {
        final r = await c.get(roadUrl(state, ref));
        if (r.statusCode < 200 || r.statusCode >= 300) {
          // As on the web, a road with no file is not counted in the
          // progress: the `continue` skips it there too.
          missing.add(ref);
          continue;
        }
        final body = jsonDecode(utf8.decode(r.bodyBytes));
        // Older exports are a bare list of ways; newer ones separate the
        // ramps that merely touch the road from the road itself. Both are
        // read, so a state exported before the split still loads.
        final isList = body is List;
        final ways = isList ? body : ((body as Map)['ways'] as List? ?? const []);
        final ramps = isList ? const [] : (body as Map)['ramps'] as List? ?? const [];
        // Which way traffic runs on each, in step with the lists above. An
        // export made before divided highways were understood has neither,
        // and every road in it reads as two-way — which is what it used to be.
        final dirs = isList ? const [] : (body as Map)['dirs'] as List? ?? const [];
        final rampDirs = isList ? const [] : (body as Map)['rampDirs'] as List? ?? const [];
        for (var i = 0; i < ways.length; i++) {
          net.add(Way(ref: ref, geom: _geom(ways[i]), dir: _dir(dirs, i)));
        }
        // Under their own name: a ramp is how you LEAVE this road, not part
        // of it, and filing it as the road let a walk along I-70 wander onto
        // US 40.
        for (var i = 0; i < ramps.length; i++) {
          net.add(Way(ref: rampRef(ref), geom: _geom(ramps[i]), dir: _dir(rampDirs, i)));
        }
      } catch (_) {
        missing.add(ref);
      }
      onProgress?.call(++done, list.length);
    }
  } finally {
    if (client == null) c.close();
  }
  return LoadedRoads(net, missing);
}

/// [[lat, lng], ...] from JSON, where a whole-number coordinate arrives as an
/// int.
List<LL> _geom(Object? raw) => [
      for (final p in raw as List)
        [((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()],
    ];

Dir _dir(List dirs, int i) => i < dirs.length && dirs[i] is num ? (dirs[i] as num).toInt() : 0;
