// lib/survey/map_image.dart
//
// Google Static Maps pictures of a route survey, and the trailer drawn to
// scale on them.
//
// The same arithmetic as trucost.app (src/lib/surveyMapImage.ts and
// src/lib/trailerGeometry.ts), so a turn framed on the phone prints the same
// picture on the desk. Every small map on the phone is one of these images
// rather than a live map: a 60-turn survey is sixty pictures in a list, and
// sixty live maps would bring a handset to its knees. The trailer outline is
// sent to Google as a filled path, so Google draws it at the right size for
// the zoom — there is no pixel arithmetic here to get wrong.

import 'dart:math' as math;
import '../config/maps_config.dart';

typedef LL = List<double>; // [lat, lng], as route_shape stores it

const _base = 'https://maps.googleapis.com/maps/api/staticmap';

/// Default zoom for a turn's map. 19 is about 490 ft across, which puts a
/// 90 ft trailer at a fifth of the picture — the scale the outline is for.
const turnMapZoom = 19;

/// survey_points.map_zoom is checked to this range in the database.
const minTurnZoom = 14;
const maxTurnZoom = 21;

/// Route line colour. Matches the blue My Maps draws by default.
const _pathStyle = 'color:0x1a56dbff|weight:5';
const _trailerStyle = 'color:0xfacc15ff|weight:2|fillcolor:0xfacc1566';

// ── Geometry ────────────────────────────────────────────────────────────────

const _earthRadiusMiles = 3958.8;
final _ftPerDegLat = (2 * math.pi * _earthRadiusMiles * 5280) / 360;

double haversineMiles(LL a, LL b) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b[0] - a[0]);
  final dLng = rad(b[1] - a[1]);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a[0])) * math.cos(rad(b[0])) * math.pow(math.sin(dLng / 2), 2);
  return _earthRadiusMiles * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

/// Ground metres per logical map pixel at this latitude and zoom.
double metersPerPixel(double lat, num zoom) =>
    (156543.03392 * math.cos(lat * math.pi / 180)) / math.pow(2, zoom);

/// The trailer as stored on a turn: a point on the earth and a bearing.
///
/// Only the centre and the bearing are kept. The size comes from the survey's
/// deck length and load width every time it is drawn, so it is right at any
/// zoom and after anybody changes the load.
class TrailerPlacement {
  const TrailerPlacement(this.lat, this.lng, this.deg);
  final double lat;
  final double lng;

  /// Bearing of the LENGTH, clockwise from north. 0 points up the map.
  final double deg;

  static TrailerPlacement? fromAnnotations(Object? annotations) {
    if (annotations is! List) return null;
    for (final a in annotations) {
      if (a is Map && a['t'] == 'trailer') {
        return TrailerPlacement(
          (a['lat'] as num).toDouble(),
          (a['lng'] as num).toDouble(),
          (a['deg'] as num?)?.toDouble() ?? 0,
        );
      }
    }
    return null;
  }

  /// The point's annotations with this trailer in place of any other.
  /// The other marks — drawn on the desk — are kept as they are.
  static List<dynamic> intoAnnotations(Object? annotations, TrailerPlacement? t) {
    final others = annotations is List
        ? annotations.where((a) => !(a is Map && a['t'] == 'trailer')).toList()
        : <dynamic>[];
    if (t != null) others.add({'t': 'trailer', 'lat': t.lat, 'lng': t.lng, 'deg': t.deg});
    return others;
  }
}

/// The four corners of the deck, clockwise from the front-left. Flat-earth
/// offsets, which over ninety feet are good to fractions of an inch.
List<LL> trailerCorners(TrailerPlacement t, double lengthFt, double widthFt) {
  final rad = t.deg * math.pi / 180;
  final fN = math.cos(rad), fE = math.sin(rad); // along the length
  final sN = -math.sin(rad), sE = math.cos(rad); // across the width
  final halfL = lengthFt / 2, halfW = widthFt / 2;
  final ftPerDegLng = _ftPerDegLat * math.cos(t.lat * math.pi / 180);

  LL corner(int f, int s) {
    final north = fN * f * halfL + sN * s * halfW;
    final east = fE * f * halfL + sE * s * halfW;
    return [t.lat + north / _ftPerDegLat, t.lng + east / ftPerDegLng];
  }

  return [corner(1, -1), corner(1, 1), corner(-1, 1), corner(-1, -1)];
}

/// The middle of the leading edge, for the nose marker.
LL trailerNose(TrailerPlacement t, double lengthFt) {
  final rad = t.deg * math.pi / 180;
  final ftPerDegLng = _ftPerDegLat * math.cos(t.lat * math.pi / 180);
  return [
    t.lat + (math.cos(rad) * lengthFt / 2) / _ftPerDegLat,
    t.lng + (math.sin(rad) * lengthFt / 2) / ftPerDegLng,
  ];
}

// ── Paths ───────────────────────────────────────────────────────────────────

/// Google's encoded polyline, which keeps a long route inside the URL limit.
String encodePolyline(List<LL> points) {
  var lastLat = 0, lastLng = 0;
  final out = StringBuffer();
  void enc(int n) {
    var s = n << 1;
    if (n < 0) s = ~s;
    while (s >= 0x20) {
      out.writeCharCode((0x20 | (s & 0x1f)) + 63);
      s >>= 5;
    }
    out.writeCharCode(s + 63);
  }

  for (final p in points) {
    final la = (p[0] * 1e5).round(), ln = (p[1] * 1e5).round();
    enc(la - lastLat);
    enc(ln - lastLng);
    lastLat = la;
    lastLng = ln;
  }
  return out.toString();
}

/// Douglas–Peucker, tolerance in miles.
List<LL> simplifyPath(List<LL> pts, [double tol = 0.002]) {
  if (pts.length <= 2) return List.of(pts);
  var maxD = 0.0;
  var index = 0;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = _perpMiles(pts[i], pts.first, pts.last);
    if (d > maxD) {
      maxD = d;
      index = i;
    }
  }
  if (maxD <= tol) return [pts.first, pts.last];
  final left = simplifyPath(pts.sublist(0, index + 1), tol);
  final right = simplifyPath(pts.sublist(index), tol);
  return [...left.sublist(0, left.length - 1), ...right];
}

double _perpMiles(LL p, LL a, LL b) {
  final k = math.cos(a[0] * math.pi / 180);
  final ax = a[1] * k, ay = a[0], bx = b[1] * k, by = b[0];
  final px = p[1] * k, py = p[0];
  final dx = bx - ax, dy = by - ay;
  final lenSq = dx * dx + dy * dy;
  var t = lenSq == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / lenSq;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)) * 69.05;
}

/// Simplify until the encoded path fits the budget. A map read at a few
/// inches wide loses nothing to a few yards of smoothing.
List<LL> fitToBudget(List<LL> pts, [int maxChars = 6000]) {
  if (pts.length < 2) return pts;
  var tol = 0.002;
  var out = simplifyPath(pts, tol);
  for (var i = 0; i < 8 && encodePolyline(out).length > maxChars; i++) {
    tol *= 3;
    out = simplifyPath(pts, tol);
  }
  return out;
}

/// The stretch of route within [miles] of a point, in route order.
List<LL> routeWindow(List<LL> route, LL at, double miles) =>
    route.where((v) => haversineMiles(at, v) <= miles).toList();

/// [[lat,lng], ...] out of whatever JSON route_shape came back as.
List<LL> shapeOf(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<List>()
      .where((p) => p.length >= 2)
      .map<LL>((p) => [(p[0] as num).toDouble(), (p[1] as num).toDouble()])
      .toList();
}

/// The route as it is actually drawn, piece by piece.
///
/// A survey imported from a state's form keeps each trip's line in dot_parsed,
/// because the gaps between trips are real: joined into one line they become
/// straight lines across country. Anything else is the one flat route.
List<List<LL>> routePieces(Map<String, dynamic>? survey) {
  final trips = (survey?['dot_parsed'] is Map) ? survey!['dot_parsed']['trips'] : null;
  if (trips is List) {
    final pieces = trips
        .whereType<Map>()
        .where((t) => t['dropped'] != true)
        .map((t) => shapeOf(t['shape']))
        .where((s) => s.length >= 2)
        .toList();
    if (pieces.isNotEmpty) return pieces;
  }
  final flat = shapeOf(survey?['route_shape']);
  return flat.length >= 2 ? [flat] : const [];
}

// ── URLs ────────────────────────────────────────────────────────────────────

String _qs(List<MapEntry<String, String>> params) =>
    params.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');

/// The whole route on one picture. No centre or zoom: Google frames the
/// paths itself, which is more reliable than computing a zoom.
String overviewMapUrl(
  List<List<LL>> pieces, {
  int width = 640,
  int height = 420,
  List<({LL at, String color, String? label})> markers = const [],
}) {
  final all = pieces.expand((p) => p).toList();
  final budget = (6000 / math.max(1, pieces.length)).floor();
  final p = <MapEntry<String, String>>[
    MapEntry('size', '${width}x$height'),
    const MapEntry('scale', '2'),
    const MapEntry('maptype', 'hybrid'),
    const MapEntry('format', 'jpg'),
    for (final piece in pieces)
      MapEntry('path', '$_pathStyle|enc:${encodePolyline(fitToBudget(piece, budget))}'),
    if (all.isNotEmpty) MapEntry('markers', 'color:0x16a34a|label:A|${all.first[0]},${all.first[1]}'),
    if (all.isNotEmpty) MapEntry('markers', 'color:0xdc2626|label:B|${all.last[0]},${all.last[1]}'),
    for (final m in markers)
      MapEntry('markers',
          'size:${m.label == null ? 'small' : 'mid'}|color:${m.color}${m.label == null ? '' : '|label:${m.label}'}|${m.at[0]},${m.at[1]}'),
    const MapEntry('key', googleMapsKey),
  ];
  return '$_base?${_qs(p)}';
}

/// One spot, close up, with the route drawn through it.
///
/// [centre] is where the escort framed the picture; the red marker stays on
/// [point] regardless. With [trailer] and the deck's size, the outline is
/// drawn as a filled path at its true size on the ground.
String spotMapUrl(
  List<LL> route,
  LL point, {
  LL? centre,
  int zoom = turnMapZoom,
  int width = 640,
  int height = 420,
  double windowMiles = 0.6,
  String markerColor = '0xdc2626',
  TrailerPlacement? trailer,
  double? lengthFt,
  double? widthFt,
}) {
  final near = routeWindow(route, point, windowMiles);
  final c = centre ?? point;
  final p = <MapEntry<String, String>>[
    MapEntry('center', '${c[0]},${c[1]}'),
    MapEntry('zoom', '$zoom'),
    MapEntry('size', '${width}x$height'),
    const MapEntry('scale', '2'),
    const MapEntry('maptype', 'hybrid'),
    const MapEntry('format', 'jpg'),
    if (near.length >= 2) MapEntry('path', '$_pathStyle|enc:${encodePolyline(fitToBudget(near))}'),
    MapEntry('markers', 'color:$markerColor|${point[0]},${point[1]}'),
  ];
  if (trailer != null && lengthFt != null && widthFt != null && lengthFt > 0 && widthFt > 0) {
    final corners = trailerCorners(trailer, lengthFt, widthFt);
    final ring = [...corners, corners.first]
        .map((c) => '${c[0].toStringAsFixed(7)},${c[1].toStringAsFixed(7)}')
        .join('|');
    p.add(MapEntry('path', '$_trailerStyle|$ring'));
    final nose = trailerNose(trailer, lengthFt);
    p.add(MapEntry('markers', 'size:tiny|color:0xfacc15|${nose[0]},${nose[1]}'));
  }
  p.add(const MapEntry('key', googleMapsKey));
  return '$_base?${_qs(p)}';
}

// ── Labels ──────────────────────────────────────────────────────────────────

/// 220 -> 18'4". Inches are how the survey stores every dimension.
String ftIn(num? inches) {
  if (inches == null || inches <= 0) return '—';
  final ft = inches ~/ 12;
  final i = (inches % 12).round();
  return i == 0 ? "$ft'" : "$ft'$i\"";
}
