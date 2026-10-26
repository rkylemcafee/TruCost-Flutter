// lib/survey/import/state_survey_import.dart
//
// Port of two pieces of the web app's state-survey import:
//
//   drawTrips()          — src/components/survey/ImportStateSurvey.tsx
//   saveImportedSurvey() — importSurvey in src/pages/survey/index.tsx, with
//                          saveSurvey / savePoint (src/lib/db/surveyDb.ts) and
//                          uploadSurveyDoc (src/lib/db/surveyDocsDb.ts) inlined
//                          so the rows written are column for column the same.
//
// The document is read and drawn, then shown back to a person before anything
// is created. That review step is not ceremony. On 2026-10-22 the parser read
// route survey 18144 as six trips with entirely real mileage and every origin
// and destination attached to the wrong trip — nothing errored, and on a list
// page it would have looked perfect. A person who has seen the PDF spots that
// in a second; no amount of validation would have. So the screen that calls
// drawTrips must show the result, and only then call saveImportedSurvey.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'indot_survey.dart';
import 'roads_index.dart';
import 'route_from_survey.dart';

class DrawnTrip {
  final String label;
  final TripGeom geom;

  /// Struck out in the review: imported and kept, but not driven.
  ///
  /// A state survey can contain trips this load does not drive. 18144 ends
  /// with two 0.8 mile runs on I-70 that nobody gets on. Struck out they are
  /// still imported and still kept — the survey is evidence of what the state
  /// said — but they arrive already set aside, so nothing is drawn, measured
  /// or checked against a leg nobody drives.
  final bool dropped;

  const DrawnTrip({required this.label, required this.geom, this.dropped = false});

  DrawnTrip withDropped(bool dropped) => DrawnTrip(label: label, geom: geom, dropped: dropped);
}

class DrawnTrips {
  final List<DrawnTrip> drawn;

  /// Roads named by the survey that have no geometry to draw them with.
  final List<String> missing;
  const DrawnTrips(this.drawn, this.missing);
}

/// Turn the parsed trips into lines on the map.
///
/// The survey is a turn list, and consecutive roads meet at the turn, so the
/// route is the chain of junctions — chosen and then checked by the mileage
/// INDOT prints beside each step. See route_from_survey.dart.
Future<DrawnTrips> drawTrips(
  IndotSurvey survey,
  String state, [
  void Function(int done, int total)? onProgress,
]) async {
  List<IndotStep> travel(List<IndotStep> steps) =>
      steps.where((s) => (s.route ?? '').isNotEmpty).toList();

  final refs = <String>[];
  for (final g in survey.segments) {
    for (final s in travel(g.steps)) {
      final n = normalizeRoad(s.route ?? '');
      if (n.isNotEmpty) refs.add(n);
    }
  }

  final loaded = await loadRoads(state, refs, onProgress);
  final net = loaded.net;

  // The direction named on each step matters as much as the distance: a road
  // runs both ways from a junction, so mileage alone cannot tell a route from
  // its reflection.
  //
  // The direction is the last word of the route column, as the web takes it.
  // Note that a route written with no direction ("SR-46") gives its own name
  // as the "direction", which reads as South; that is the web's behaviour and
  // is kept so the two draw the same line.
  final raw = survey.segments.map((g) {
    final rows = travel(g.steps);
    return (
      roads: rows.map((x) => normalizeRoad(x.route ?? '')).where((r) => r.isNotEmpty).toList(),
      dists: rows.map((x) => x.miles ?? 0.0).toList(),
      dirs: rows.map((x) => (x.route ?? '').split(RegExp(r'\s+')).last).toList(),
    );
  }).toList();

  // One piece per split trip, exactly as the survey writes them.
  //
  // This used to do more: trips that ended where the next began were merged,
  // and the few tenths of a mile the state writes to reach a point and come
  // back were dropped as an artifact. Both were inferences, and inferring is
  // the one thing this must not do. Kyle: "it is only producing what the
  // route survey gives it, not inferring anything."
  //
  // Merging made the line continuous where the survey is not, which hides the
  // question the escort has to answer. A survey splits without saying why, but
  // the load still has to get across the gap, and the road it crosses on was
  // not part of what the state approved. A continuous line says that was
  // handled. It was not.
  //
  // Drawing the artifact literally has a second benefit. At Princeton the
  // survey as written ramps onto US-41 under a bridge with 16'4" beneath it,
  // and a 17'9" load does not fit. Dropping those tenths of a mile hid that;
  // drawing them puts the bridge on the clearance list, where an escort can
  // see what the survey actually asks for.
  final drawn = <DrawnTrip>[];
  LL? lastEnd;

  for (var gi = 0; gi < raw.length; gi++) {
    final piece = raw[gi];
    final label = survey.segments[gi].label;
    final stated = piece.dists.fold<double>(0, (t, d) => t + d);
    // One road and no turn: nothing for the mileage to anchor to, so it hangs
    // off where the last trip ended and runs out in the direction named.
    final geom = piece.roads.isNotEmpty
        ? drawTrip(net, piece.roads, piece.dists, piece.dirs, stated, lastEnd)
        : TripGeom.none(stated, 'no road named');
    drawn.add(DrawnTrip(label: label, geom: geom));
    if (geom.shape.isNotEmpty) lastEnd = geom.shape.last;
  }
  return DrawnTrips(drawn, loaded.missing);
}

/// The survey was created, but its PDF could not be stored.
///
/// The PDF is the authority for everything in the survey. If storing it fails
/// the survey still exists and is still correct, so this says so rather than
/// throwing away a good import: [surveyId] is the survey to open, and the file
/// can be attached from there. The web shows the same as an alert.
class SurveyPdfNotStored implements Exception {
  final String surveyId;
  final String message;
  const SurveyPdfNotStored(this.surveyId, this.message);

  @override
  String toString() =>
      'The survey was created, but the PDF could not be stored: $message\n\n'
      'Attach it from the survey page.';
}

const _bucket = 'tenant-assets';

/// Turn a parsed state survey into one of ours, and keep the PDF with it.
///
/// One survey, not one per trip. The splits are places the route has to be
/// joined up — a point and a note, the same gesture as going under an
/// overpass the router will not allow — not separate moves. Indiana issues
/// one number and one permit covers it.
///
/// The whole reading is stored in dot_parsed, so the survey page can show
/// what the document said without going back to the PDF, and so a later
/// parser fix can be compared against what we understood at the time.
///
/// Returns the new survey's id. Throws [SurveyPdfNotStored] (carrying the id)
/// when everything but the file was saved.
Future<String> saveImportedSurvey({
  required IndotSurvey parsed,
  required List<DrawnTrip> drawn,
  required Uint8List fileBytes,
  required String fileName,
  required String mimeType,
}) async {
  final db = Supabase.instance.client;

  // The tenant, found the way the web's useAuth finds it and the way RLS
  // checks it: the app_users row whose id is the signed-in user's.
  final user = db.auth.currentUser;
  if (user == null) throw StateError('Not signed in.');
  final me = await db
      .from('app_users')
      .select('tenant_id, is_active')
      .eq('id', user.id)
      .maybeSingle();
  final tenantId = me?['tenant_id'] as String?;
  if (me == null || tenantId == null || me['is_active'] == false) {
    throw StateError('This account has no active company to save the survey to.');
  }

  // The web works from the survey list it already has on screen — every
  // survey for the tenant, most recently updated first. The same, minus the
  // columns nothing here reads.
  final rows = List<Map<String, dynamic>>.from(await db
      .from('route_surveys')
      .select('dot_state, dot_survey_number, trailer_length_in')
      .eq('tenant_id', tenantId)
      .order('updated_at', ascending: false));

  // Importing the same document again is a normal thing to do — it is how
  // you check a parser you have just changed — so the copy is labelled
  // rather than refused. The number stays the same on every revision
  // because it is how everybody refers to the move; only the title says
  // which attempt this is.
  final already = parsed.routeNumber != null
      ? rows
          .where((r) => r['dot_state'] == 'IN' && r['dot_survey_number'] == parsed.routeNumber)
          .length
      : 0;
  final rev = already > 0 ? ' (rev ${already + 1})' : '';
  final first = parsed.segments.isNotEmpty ? parsed.segments.first : null;
  final last = parsed.segments.isNotEmpty ? parsed.segments.last : null;

  // The trips joined end to end, which is what the map draws. The gaps
  // between them are real — three of them on 18144 — and are left as gaps
  // rather than bridged with a straight line somebody might mistake for
  // road. Connecting them is a decision with a permission attached.
  // A leg struck out in the review is in the record and in nothing else:
  // not the line, not the turn list, not the segment summary.
  final driven = drawn.where((d) => !d.dropped).toList();
  final shape = <LL>[for (final d in driven) ...d.geom.shape];
  final addedAt = _isoNow();
  final pieces = [
    for (final d in driven)
      if (d.geom.shape.isNotEmpty)
        {
          'kind': 'text',
          'ref': fileName,
          'label': '${d.label} — ${d.geom.miles.toStringAsFixed(1)} mi',
          'points': 0,
          'shapeCount': d.geom.shape.length,
          'miles': jsNumber(d.geom.miles),
          'startLat': d.geom.shape.first[0],
          'startLng': d.geom.shape.first[1],
          'endLat': d.geom.shape.last[0],
          'endLng': d.geom.shape.last[1],
          'addedAt': addedAt,
        },
  ];

  // The parse, plus the line each trip drew. The shapes live here rather
  // than only in route_shape because the gaps between trips matter: drawn
  // as one line they become straight lines across country.
  final dotParsed = {
    ...parsed.toJson(),
    'trips': [
      for (final d in drawn)
        {
          'label': d.label,
          'miles': jsNumber(d.geom.miles),
          'statedMiles': jsNumber(d.geom.statedMiles),
          'why': d.geom.why,
          'shape': d.geom.shape,
          // Struck out in the review. Kept, drawn by nothing.
          if (d.dropped) 'dropped': true,
        },
    ],
  };

  final title = 'IN ${parsed.routeNumber ?? 'route survey'}$rev'
      '${first != null ? ' — ${first.originText} to ${last!.destText}' : ''}';

  // Column for column what saveSurvey writes on an insert.
  final row = <String, dynamic>{
    'tenant_id': tenantId,
    'proposal_id': null,
    'title': title,
    'customer_name': null,
    'origin_label': first?.originText ?? '',
    'origin_lat': shape.isNotEmpty ? shape.first[0] : null,
    'origin_lng': shape.isNotEmpty ? shape.first[1] : null,
    'dest_label': last?.destText ?? '',
    'dest_lat': shape.isNotEmpty ? shape.last[0] : null,
    'dest_lng': shape.isNotEmpty ? shape.last[1] : null,
    'leg_state': 'IN',
    'trip_id': null,
    'leg_seq': null,
    'route_shape': shape.isNotEmpty ? shape : null,
    'segments': pieces,
    'source_kind': 'text',
    'source_ref': fileName,
    'dot_state': 'IN',
    'dot_survey_number': parsed.routeNumber,
    'carrier_name': parsed.carrier,
    'dot_parsed': dotParsed,
    'load_height_in': parsed.heightIn,
    'load_width_in': parsed.widthIn,
    'load_length_in': parsed.lengthIn,
    // Carried forward from the most recent survey, as the web does: a company
    // runs the same decks for years.
    'trailer_length_in': rows.isNotEmpty ? rows.first['trailer_length_in'] : null,
    'load_weight_lbs': parsed.weightLb,
    'axle_count': null,
    'outcome': null,
    'outcome_notes': null,
    'status': 'draft',
    'surveyed_on': null,
    'verified_on': null,
    'verified_by': null,
    'updated_at': _isoNow(),
  };
  final inserted = await db.from('route_surveys').insert(row).select('id').single();
  final id = inserted['id'] as String;

  // A turn point for every turn the survey names.
  //
  // Not decoration: the structure check works out which road the load is on
  // from the turn instructions, and with none it cannot tell "you drive
  // across this bridge" from "this bridge is near the road you are on".
  // Mulberry Street over the CSX sits 44 ft from SR-62 through Mount Vernon
  // and was reported as a bridge the load crosses.
  //
  // The instruction is INDOT's own words, so the turn list reads the way the
  // paperwork does. The last step of each trip ends at a destination rather
  // than a turn, and gets said so.
  var seq = 0;
  LL? prevEnd;
  for (final d in driven) {
    final steps = d.geom.steps;
    // Where a leg STARTS, when it does not carry on from the one before it.
    //
    // Every leg's end is a point — "Route ends here — SR-62" — and no leg's
    // beginning was, because the survey names turns and a leg does not begin
    // with a turn. So the far side of a gap, the one place a join has to
    // reach, was the one place nothing could be picked: the nearest thing on
    // the list was the first TURN of the next leg, twelve miles further on,
    // and a join made to it drew eleven miles of yellow over road the state
    // had already approved.
    final start = d.geom.shape.isNotEmpty ? d.geom.shape.first : null;
    if (start != null && prevEnd != null && _haversineMiles(prevEnd, start) > joinedMiles) {
      final n = ++seq;
      try {
        await _savePoint(db, id, n, start,
            '${d.label} starts here — ${steps.isNotEmpty ? steps.first.road : ''}'.trim());
      } catch (_) {/* see below: one point is not worth the import */}
    }
    if (d.geom.shape.isNotEmpty) prevEnd = d.geom.shape.last;
    for (var i = 0; i < steps.length; i++) {
      final st = steps[i];
      final at = st.endsAt;
      if (at == null) continue;
      final lastOfTrip = i == steps.length - 1;
      final n = ++seq;
      try {
        await _savePoint(
          db,
          id,
          n,
          at,
          lastOfTrip
              ? '${d.label} ends here — ${st.road}'
              : '${st.road} — ${i + 1 < steps.length ? steps[i + 1].road : ''}'.trim(),
        );
      } catch (_) {
        // One point failing is not worth losing the import over; the route
        // and its mileage are already stored.
      }
    }
  }

  // The PDF is the authority for everything above. If storing it fails the
  // survey still exists and is still correct, so say so rather than
  // throwing away a good import.
  try {
    await _uploadSurveyDoc(
      db,
      surveyId: id,
      bytes: fileBytes,
      fileName: fileName,
      mimeType: mimeType,
      kind: 'state_survey',
      caption: 'Indiana route survey ${parsed.routeNumber ?? ''}'.trim(),
    );
  } catch (e) {
    throw SurveyPdfNotStored(
      id,
      e is PostgrestException
          ? e.message
          : e is StorageException
              ? e.message
              : e.toString(),
    );
  }
  return id;
}

/// savePoint's insert, for a new turn.
Future<void> _savePoint(SupabaseClient db, String surveyId, int seq, LL at, String instruction) async {
  await db.from('survey_points').insert({
    'survey_id': surveyId,
    'lat': at[0],
    'lng': at[1],
    'kind': 'turn',
    'instruction': instruction,
    'clearance_in': null,
    'width_in': null,
    'map_image_path': null,
    'map_zoom': null,
    'map_center_lat': null,
    'map_center_lng': null,
    'is_waypoint': false,
    'annotations': <dynamic>[],
    'seq': seq,
  }).select('id').single();
}

/// Store a file and record it against the survey — uploadSurveyDoc.
///
/// The stored name keeps the original inside a folder named for the survey, so
/// somebody looking in the bucket can tell what they are looking at. A clash
/// is resolved by the timestamp rather than by overwriting: two people
/// uploading "map.png" on the same job should end up with two maps, not one.
Future<void> _uploadSurveyDoc(
  SupabaseClient db, {
  required String surveyId,
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required String kind,
  String caption = '',
}) async {
  final safe = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final storagePath =
      'surveys/$surveyId/$kind/${DateTime.now().millisecondsSinceEpoch}-$safe';

  try {
    await db.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: false,
            contentType: mimeType.isNotEmpty ? mimeType : null,
          ),
        );
  } on StorageException catch (e) {
    throw _UploadFailed('Could not upload $fileName: ${e.message}');
  }

  try {
    await db.from('survey_documents').insert({
      'survey_id': surveyId,
      'kind': kind,
      'storage_path': storagePath,
      'file_name': fileName,
      'mime_type': mimeType.isNotEmpty ? mimeType : null,
      'byte_size': bytes.length,
      'caption': caption.isNotEmpty ? caption : null,
    }).select().single();
  } catch (_) {
    // The row is what makes the file findable. Without it the upload is
    // litter in a bucket nobody will ever look in, so take it back out.
    try {
      await db.storage.from(_bucket).remove([storagePath]);
    } catch (_) {}
    rethrow;
  }
}

class _UploadFailed implements Exception {
  final String message;
  const _UploadFailed(this.message);
  @override
  String toString() => message;
}

/// new Date().toISOString(): UTC, milliseconds, a Z.
String _isoNow() =>
    DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch, isUtc: true)
        .toIso8601String();

/// The web's haversineMiles (src/lib/geo.ts), which the gap check uses rather
/// than route_from_survey's own — a slightly different earth radius, kept so a
/// "starts here" point appears in exactly the same places.
double _haversineMiles(LL a, LL b) {
  const r = 3958.7613, p = math.pi / 180;
  final dLa = (b[0] - a[0]) * p, dLo = (b[1] - a[1]) * p;
  final sLa = math.sin(dLa / 2), sLo = math.sin(dLo / 2);
  final h = sLa * sLa + math.cos(a[0] * p) * math.cos(b[0] * p) * (sLo * sLo);
  return 2 * r * math.asin(math.sqrt(h));
}
