// lib/survey/survey_export.dart
//
// The survey, out to the tools escorts already use.
//
// None of them has an API. My Maps and Google Earth import a file, inRoute and
// GPS units read GPX or a URL scheme, Google Maps takes stops in a link, and a
// spreadsheet takes CSV. So the job is to write the right file — the KML and
// inRoute link exactly as trucost.app writes them (src/lib/surveyExport.ts),
// so a file from the phone and a file from the desk are the same file.

import 'dart:convert';
import 'package:archive/archive.dart';
import 'map_image.dart';
import 'survey_data.dart';

const inRouteMaxStops = 150;
const googleMaxStops = 100;

String _esc(Object? s) => (s ?? '')
    .toString()
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _ftIn2(num? inches) {
  if (inches == null || inches <= 0) return '—';
  return "${inches ~/ 12}'${(inches % 12).round().toString().padLeft(2, '0')}\"";
}

String _placemark(String name, double lat, double lng, String style, [String? description]) => '''
    <Placemark>
      <name>${_esc(name)}</name>
      <styleUrl>#$style</styleUrl>${description == null || description.isEmpty ? '' : '\n      <description><![CDATA[$description]]></description>'}
      <Point><coordinates>${lng.toStringAsFixed(6)},${lat.toStringAsFixed(6)},0</coordinates></Point>
    </Placemark>''';

double _d(Object? v) => (v as num).toDouble();

/// One file for My Maps and Google Earth. Every section is its own folder, so
/// each becomes its own switchable layer.
String surveyToKml(SurveyData d) {
  final h = d.loadHeightIn;
  final lines = d.pieces.indexed.map((e) => '''
    <Placemark>
      <name>${_esc(d.pieces.length > 1 ? '${d.title} — part ${e.$1 + 1}' : d.title)}</name>
      <styleUrl>#routeLine</styleUrl>
      <LineString>
        <tessellate>1</tessellate>
        <coordinates>${e.$2.map((p) => '${p[1].toStringAsFixed(6)},${p[0].toStringAsFixed(6)},0').join(' ')}</coordinates>
      </LineString>
    </Placemark>''').join('\n');

  final folders = <String>[
    if (d.pieces.isNotEmpty) '  <Folder>\n    <name>Route</name>\n$lines\n  </Folder>',
    if (d.points.isNotEmpty)
      '  <Folder>\n    <name>Turns</name>\n${d.points.map((p) {
        final ins = (p['instruction'] ?? '').toString();
        final name = '${p['seq']}. ${ins.isEmpty ? 'Turn' : ins}';
        return _placemark(
          name.length > 120 ? name.substring(0, 120) : name,
          _d(p['lat']),
          _d(p['lng']),
          'turn',
          [ins, if (p['clearance_in'] != null) 'Clearance ${_ftIn2(p['clearance_in'] as num)}']
              .where((x) => x.isNotEmpty)
              .join('<br>'),
        );
      }).join('\n')}\n  </Folder>',
    if (d.overhead.isNotEmpty)
      '  <Folder>\n    <name>Overpasses</name>\n${d.overhead.map((s) {
        final low = h != null && d.tooLow(s);
        return _placemark(
          '${_ftIn2(s['clearance_in'] as num?)} — ${s['carries'] ?? 'structure'}',
          _d(s['lat']),
          _d(s['lng']),
          low ? 'tooLow' : 'overhead',
          [
            '${_esc(s['carries'])} over ${_esc(s['crosses'])}',
            if (low) '<b>LOAD DOES NOT FIT</b>',
            s['action'],
            s['notes'],
          ].where((x) => x != null && x.toString().isNotEmpty).join('<br>'),
        );
      }).join('\n')}\n  </Folder>',
    if (d.crossed.isNotEmpty)
      '  <Folder>\n    <name>Bridges crossed</name>\n${d.crossed.map((s) => _placemark(
            '${s['length_ft'] != null ? '${(s['length_ft'] as num).round()} ft' : 'Bridge'} — ${s['carries'] ?? ''}'.trim(),
            _d(s['lat']),
            _d(s['lng']),
            'bridge',
            ['${_esc(s['carries'])} over ${_esc(s['crosses'])}', s['action'], s['notes']]
                .where((x) => x != null && x.toString().isNotEmpty)
                .join('<br>'),
          )).join('\n')}\n  </Folder>',
  ];

  const icon = 'https://maps.google.com/mapfiles/kml/';
  String style(String id, String colour, String href) => '''
  <Style id="$id">
    <IconStyle>
      <color>$colour</color>
      <scale>1.1</scale>
      <Icon><href>$href</href></Icon>
    </IconStyle>
  </Style>''';

  return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
  <name>${_esc(d.title)}</name>
  <Style id="routeLine">
    <LineStyle><color>ffdb561a</color><width>5</width></LineStyle>
  </Style>
${style('turn', 'ffeb6325', '${icon}paddle/blu-circle.png')}
${style('overhead', 'ff0b82ea', '${icon}shapes/road_shield3.png')}
${style('tooLow', 'ff2222dc', '${icon}shapes/caution.png')}
${style('bridge', 'ff32a154', '${icon}shapes/truck.png')}
${folders.join('\n')}
</Document>
</kml>
''';
}

/// The KML zipped, which is what Google Earth opens by default.
List<int> surveyToKmz(SurveyData d) {
  final kml = utf8.encode(surveyToKml(d));
  final archive = Archive()..addFile(ArchiveFile('doc.kml', kml.length, kml));
  return ZipEncoder().encode(archive);
}

/// GPX: the route as a track, every turn as a waypoint in order, and the
/// turns again as a route — some GPS apps only read one of the three.
String surveyToGpx(SurveyData d) {
  String wpt(String tag, Map<String, dynamic> p) {
    final ins = (p['instruction'] ?? '').toString();
    return '  <$tag lat="${_d(p['lat']).toStringAsFixed(6)}" lon="${_d(p['lng']).toStringAsFixed(6)}">'
        '<name>${_esc('${p['seq']}. ${ins.isEmpty ? 'Turn' : ins}')}</name>'
        '${ins.isEmpty ? '' : '<desc>${_esc(ins)}</desc>'}</$tag>';
  }

  final trk = d.pieces.isEmpty
      ? ''
      : '  <trk>\n    <name>${_esc(d.title)}</name>\n'
          '${d.pieces.map((piece) => '    <trkseg>\n${piece.map((v) => '      <trkpt lat="${v[0].toStringAsFixed(6)}" lon="${v[1].toStringAsFixed(6)}"/>').join('\n')}\n    </trkseg>').join('\n')}\n  </trk>\n';
  return '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TruCost" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>${_esc(d.title)}</name></metadata>
${d.points.map((p) => wpt('wpt', p)).join('\n')}
  <rte>
    <name>${_esc(d.title)}</name>
${d.points.map((p) => '  ${wpt('rtept', p)}').join('\n')}
  </rte>
$trk</gpx>
''';
}

/// GeoJSON, for anybody putting the survey into GIS.
String surveyToGeoJson(SurveyData d) {
  Map<String, dynamic> pt(double lat, double lng, Map<String, dynamic> props) => {
        'type': 'Feature',
        'geometry': {'type': 'Point', 'coordinates': [lng, lat]},
        'properties': props,
      };
  return const JsonEncoder.withIndent(' ').convert({
    'type': 'FeatureCollection',
    'name': d.title,
    'features': [
      if (d.pieces.isNotEmpty)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'MultiLineString',
            'coordinates': [for (final piece in d.pieces) [for (final v in piece) [v[1], v[0]]]],
          },
          'properties': {'layer': 'route', 'name': d.title},
        },
      for (final p in d.points)
        pt(_d(p['lat']), _d(p['lng']), {
          'layer': 'turn',
          'seq': p['seq'],
          'kind': p['kind'],
          'instruction': p['instruction'],
          'clearance_in': p['clearance_in'],
        }),
      for (final s in d.live)
        pt(_d(s['lat']), _d(s['lng']), {
          'layer': s['kind'] == 'cross' ? 'bridge' : 'overpass',
          'carries': s['carries'],
          'crosses': s['crosses'],
          'clearance_in': s['clearance_in'],
          'length_ft': s['length_ft'],
          'miles_along': s['miles_along'],
          'too_low': d.tooLow(s),
          'action': s['action'],
          'notes': s['notes'],
        }),
    ],
  });
}

String _csvCell(Object? v) {
  final s = (v ?? '').toString();
  return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// The turn list as a spreadsheet, with the structures after it.
String surveyToCsv(SurveyData d) {
  final rows = <List<Object?>>[
    ['Type', '#', 'Instruction / carries', 'Over', 'Clearance', 'Length ft', 'Miles along', 'Too low', 'Lat', 'Lng'],
    for (final p in d.points)
      ['Turn', p['seq'], p['instruction'], '', _ftIn2(p['clearance_in'] as num?), '', '', '', p['lat'], p['lng']],
    for (final s in d.overhead)
      ['Overpass', '', s['carries'], s['crosses'], _ftIn2(s['clearance_in'] as num?), '', s['miles_along'],
       d.tooLow(s) ? 'YES' : '', s['lat'], s['lng']],
    for (final s in d.crossed)
      ['Bridge', '', s['carries'], s['crosses'], '', s['length_ft'], s['miles_along'], '', s['lat'], s['lng']],
  ];
  return '${rows.map((r) => r.map(_csvCell).join(',')).join('\r\n')}\r\n';
}

/// Opens the survey as stops in inRoute, in driving order. Never asked to
/// optimise — that would reorder the route, and the order is the survey.
String surveyToInRouteUrl(SurveyData d) {
  final parts = <String>[];
  for (final p in d.points.take(inRouteMaxStops)) {
    final ins = (p['instruction'] ?? '').toString().trim();
    final label = ins.isEmpty
        ? 'Turn ${p['seq']}'
        : '${p['seq']}. ${ins.length > 48 ? '${ins.substring(0, 47)}…' : ins}';
    parts.add('loc=${Uri.encodeComponent(label.replaceAll(',', ' '))},'
        '${_d(p['lat']).toStringAsFixed(6)},${_d(p['lng']).toStringAsFixed(6)}');
  }
  return 'inroute://coordinates?${parts.join('&')}';
}

int inRouteOverflow(SurveyData d) => (d.points.length - inRouteMaxStops).clamp(0, 1 << 30);

/// Every surveyed point as a stop, so Google has to follow the route that was
/// driven. Too many for one link becomes several legs, each starting where the
/// last finished.
List<String> googleMapsLinks(SurveyData d) {
  String coord(double n) => n.toStringAsFixed(5).replaceFirst(RegExp(r'\.?0+$'), '');
  final clean = <LL>[];
  for (final p in d.points) {
    final v = [_d(p['lat']), _d(p['lng'])];
    if (clean.isNotEmpty && (clean.last[0] - v[0]).abs() < 1e-5 && (clean.last[1] - v[1]).abs() < 1e-5) continue;
    clean.add(v);
  }
  if (clean.length < 2) return const [];
  final links = <String>[];
  for (var start = 0; start < clean.length - 1; start += googleMaxStops - 1) {
    final chunk = clean.sublist(start, (start + googleMaxStops).clamp(0, clean.length));
    if (chunk.length < 2) break;
    links.add('https://www.google.com/maps/dir/${chunk.map((s) => '${coord(s[0])},${coord(s[1])}').join('/')}/');
  }
  return links;
}

/// A file name from the survey's title: "IN_18144_-_Mt_Vernon_to_Evansville".
String fileStem(SurveyData d) => d.title.replaceAll(RegExp(r'[^\w-]+'), '_');
