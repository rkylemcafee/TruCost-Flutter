// lib/survey/survey_data.dart
//
// Everything one survey screen shows, loaded together and handed to each tab.
//
// Rows stay as the maps Supabase returns, the way the rest of this module
// reads them; the getters here are the few questions every tab asks — where
// the route is, how big the deck is, which structures are still in play.

import 'map_image.dart';

class SurveyData {
  SurveyData({
    required this.survey,
    required this.points,
    required this.photos,
    required this.structures,
    required this.documents,
  });

  final Map<String, dynamic> survey;
  final List<Map<String, dynamic>> points;
  final List<Map<String, dynamic>> photos;
  final List<Map<String, dynamic>> structures;
  final List<Map<String, dynamic>> documents;

  String get id => survey['id'] as String;

  /// A closed survey: the desk sealed it, and nothing on it may change.
  Map<String, dynamic>? get seal {
    final p = survey['dot_parsed'];
    final s = p is Map ? p['sealed'] : null;
    return s is Map && s['at'] is String ? Map<String, dynamic>.from(s) : null;
  }

  bool get sealed => seal != null;

  String get sealLine {
    final s = seal;
    if (s == null) return '';
    final by = (s['by'] ?? '').toString();
    return 'Closed ${(s['at'] as String).substring(0, 10)}${by.isEmpty ? '' : ' by $by'}';
  }
  String get title => (survey['title'] ?? '').toString().isEmpty ? 'Route survey' : survey['title'];

  /// The route as drawn, piece by piece; gaps between pieces stay gaps.
  late final List<List<LL>> pieces = routePieces(survey);

  /// All of it end to end, for "the road near this spot".
  late final List<LL> route = pieces.expand((p) => p).toList();

  int? get loadHeightIn => (survey['load_height_in'] as num?)?.toInt();
  int? get loadWidthIn => (survey['load_width_in'] as num?)?.toInt();
  int? get loadWeightLbs => (survey['load_weight_lbs'] as num?)?.toInt();

  /// The rigid deck, which is what has to fit the corner. The whole
  /// combination articulates; drawing it would make every corner look
  /// impossible.
  double? get deckLengthFt => (survey['trailer_length_in'] as num?) == null
      ? null
      : (survey['trailer_length_in'] as num) / 12;
  double? get deckWidthFt => loadWidthIn == null ? null : loadWidthIn! / 12;
  bool get haveDeck => (deckLengthFt ?? 0) > 0 && (deckWidthFt ?? 0) > 0;

  List<Map<String, dynamic>> get live => structures.where((s) => s['status'] != 'ignore').toList();
  List<Map<String, dynamic>> get ignored => structures.where((s) => s['status'] == 'ignore').toList();

  /// What the load passes under.
  List<Map<String, dynamic>> get overhead => live.where((s) => s['kind'] != 'cross').toList();

  /// What carries the load.
  List<Map<String, dynamic>> get crossed => live.where((s) => s['kind'] == 'cross').toList();

  bool tooLow(Map<String, dynamic> s) {
    final c = (s['clearance_in'] as num?)?.toInt();
    return loadHeightIn != null && c != null && c > 0 && c < loadHeightIn!;
  }

  List<Map<String, dynamic>> photosFor(String pointId) =>
      photos.where((p) => p['point_id'] == pointId).toList();

  List<Map<String, dynamic>> docsOfKind(String kind) =>
      documents.where((d) => d['kind'] == kind).toList();

  // ── One turn's picture ───────────────────────────────────────────────────

  static LL pointLL(Map<String, dynamic> p) =>
      [(p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()];

  /// The view the escort framed, falling back to the turn itself.
  static LL frameOf(Map<String, dynamic> p) => [
        ((p['map_center_lat'] ?? p['lat']) as num).toDouble(),
        ((p['map_center_lng'] ?? p['lng']) as num).toDouble(),
      ];

  static int zoomOf(Map<String, dynamic> p) => (p['map_zoom'] as num?)?.toInt() ?? turnMapZoom;

  /// The turn as the report prints it: framed, zoomed, trailer on.
  String turnMapUrl(Map<String, dynamic> p, {int width = 640, int height = 420}) => spotMapUrl(
        route,
        pointLL(p),
        centre: frameOf(p),
        zoom: zoomOf(p),
        width: width,
        height: height,
        trailer: TrailerPlacement.fromAnnotations(p['annotations']),
        lengthFt: deckLengthFt,
        widthFt: deckWidthFt,
      );

  /// A structure, close enough to see which road is on top.
  String structureMapUrl(Map<String, dynamic> s, {int zoom = 18, int width = 640, int height = 360}) =>
      spotMapUrl(
        route,
        [(s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()],
        zoom: zoom,
        width: width,
        height: height,
        windowMiles: 0.4,
        markerColor: s['kind'] == 'cross' ? '0x16a34a' : (tooLow(s) ? '0xdc2626' : '0xea580c'),
      );

  /// The whole route with every bridge it crosses marked.
  String bridgesMapUrl({int width = 640, int height = 420}) => overviewMapUrl(
        pieces,
        width: width,
        height: height,
        markers: [
          for (final s in crossed.take(60))
            (at: [(s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()], color: '0x16a34a', label: null),
        ],
      );

  /// The whole route with every overpass marked; red where the load won't fit.
  String overpassesMapUrl({int width = 640, int height = 420}) => overviewMapUrl(
        pieces,
        width: width,
        height: height,
        markers: [
          for (final s in overhead.take(60))
            (
              at: [(s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()],
              color: tooLow(s) ? '0xdc2626' : '0xea580c',
              label: null,
            ),
        ],
      );
}

/// "12.4 mi", or nothing when the structure has no position along the route.
String milesLabel(Object? v) => v is num ? '${v.toStringAsFixed(1)} mi' : '';
