// lib/survey/tabs/export_tab.dart
//
// Export: the survey and its maps, out in whatever form the next person needs.
//
// Each file goes to the iPhone's share sheet, which is where "save to Files",
// AirDrop, Mail, Messages and "open in Google Earth" all live — so one button
// per format covers every destination without this screen having to know
// them. The links (inRoute, Google Maps) open on this phone or get copied to
// send to another.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../map_image.dart';
import '../survey_data.dart';
import '../survey_export.dart';
import '../widgets/static_map.dart';
import 'reports_tab.dart' show makeAndKeepReport;

class ExportTab extends StatefulWidget {
  const ExportTab({super.key, required this.data, required this.onChanged});
  final SurveyData data;
  final Future<void> Function() onChanged;

  @override
  State<ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<ExportTab> {
  String? _busy;

  SurveyData get d => widget.data;

  Future<void> _shareFile(String ext, List<int> bytes, String mime) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${fileStem(d)}.$ext');
    await f.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], subject: d.title));
  }

  /// Every map as a JPG: the route, the bridges, the overpasses, each turn.
  Future<void> _shareMaps() async {
    final list = <({String url, String name})>[
      if (d.pieces.isNotEmpty) (url: overviewMapUrl(d.pieces), name: '00_route'),
      if (d.pieces.isNotEmpty && d.crossed.isNotEmpty) (url: d.bridgesMapUrl(), name: '01_bridges'),
      if (d.pieces.isNotEmpty && d.overhead.isNotEmpty) (url: d.overpassesMapUrl(), name: '02_overpasses'),
      if (d.route.length >= 2)
        for (final p in d.points)
          (url: d.turnMapUrl(p), name: 'turn_${(p['seq'] as num).toInt().toString().padLeft(3, '0')}'),
      for (final (i, s) in d.overhead.indexed)
        (url: d.structureMapUrl(s), name: 'overpass_${(i + 1).toString().padLeft(2, '0')}'),
    ];
    if (list.isEmpty) return _say('No route line yet, so there are no maps to export.');
    final files = <XFile>[];
    for (final (i, m) in list.indexed) {
      setState(() => _busy = 'Map ${i + 1} of ${list.length}');
      final f = await downloadMap(m.url, '${fileStem(d)}_${m.name}');
      if (f != null) files.add(XFile(f.path, mimeType: 'image/jpeg'));
    }
    setState(() => _busy = null);
    if (files.isEmpty) return _say('The maps did not download — check the signal.');
    await SharePlus.instance.share(ShareParams(files: files, subject: '${d.title} — maps'));
  }

  Future<void> _run(String label, Future<void> Function() job) async {
    setState(() => _busy = label);
    try {
      await job();
    } catch (e) {
      _say('$label failed: $e');
    }
    if (mounted) setState(() => _busy = null);
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _say('$what copied');
  }

  @override
  Widget build(BuildContext context) {
    final nothing = d.pieces.isEmpty && d.points.isEmpty;
    final links = googleMapsLinks(d);
    final over = inRouteOverflow(d);
    final busy = _busy != null;

    Widget format(IconData icon, String title, String sub, VoidCallback onTap) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.ios_share, size: 20),
          enabled: !busy && !nothing,
          onTap: onTap,
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        if (busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text(_busy!, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        const _Heading('Maps'),
        format(Icons.map_outlined, 'Every map, as pictures',
            'The route, bridges, overpasses and every turn with the trailer on it — JPG', _shareMaps),
        format(Icons.picture_as_pdf_outlined, 'The report, as a PDF',
            'Also kept on the Reports tab', () => makeAndKeepReport(context, d, widget.onChanged)),
        const SizedBox(height: 12),

        const _Heading('Map files'),
        format(Icons.layers_outlined, 'KML — Google My Maps',
            'Route, turns, overpasses and bridges as separate layers. In My Maps: Create a new map → Import.',
            () => _run('KML', () => _shareFile('kml', utf8.encode(surveyToKml(d)), 'application/vnd.google-earth.kml+xml'))),
        format(Icons.public, 'KMZ — Google Earth', 'The same file zipped, which Earth opens by default',
            () => _run('KMZ', () => _shareFile('kmz', surveyToKmz(d), 'application/vnd.google-earth.kmz'))),
        format(Icons.route_outlined, 'GPX — inRoute and GPS units', 'The route as a track and every turn as a waypoint',
            () => _run('GPX', () => _shareFile('gpx', utf8.encode(surveyToGpx(d)), 'application/gpx+xml'))),
        format(Icons.data_object, 'GeoJSON — GIS', 'Route, turns and structures with their details',
            () => _run('GeoJSON', () => _shareFile('geojson', utf8.encode(surveyToGeoJson(d)), 'application/geo+json'))),
        format(Icons.table_chart_outlined, 'CSV — spreadsheet', 'Turns, then overpasses, then bridges',
            () => _run('CSV', () => _shareFile('csv', utf8.encode(surveyToCsv(d)), 'text/csv'))),
        const SizedBox(height: 12),

        // ── inRoute ──────────────────────────────────────────────────────
        const _Heading('inRoute'),
        const Text(
          'Opens the survey as stops in inRoute, in driving order. It is never asked to optimise — '
          'that would reorder the route, and the order is the survey.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Row(children: [
          TextButton.icon(
            onPressed: d.points.isEmpty
                ? null
                : () async {
                    final ok = await launchUrl(Uri.parse(surveyToInRouteUrl(d)));
                    if (!ok) _say('inRoute is not on this phone. Copy the link and send it to the one that has it.');
                  },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open in inRoute'),
          ),
          TextButton.icon(
            onPressed: d.points.isEmpty ? null : () => _copy(surveyToInRouteUrl(d), 'inRoute link'),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy link'),
          ),
        ]),
        if (over > 0)
          Text(
            '$over stop(s) will not fit. inRoute takes $inRouteMaxStops; this survey has ${d.points.length}. '
            'The link carries the first $inRouteMaxStops — split the route rather than setting off with the rest missing.',
            style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
          ),
        const SizedBox(height: 12),

        // ── Google Maps ──────────────────────────────────────────────────
        if (links.isNotEmpty) ...[
          const _Heading('Google Maps'),
          Text(
            'All ${d.points.length} point(s) go in as stops, so Google has to follow the route that was driven.'
            '${links.length > 1 ? ' Too long for one link, so it comes in ${links.length} legs — each starts where the last finished.' : ''}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          for (final (i, url) in links.indexed)
            Row(children: [
              SizedBox(
                width: 90,
                child: Text(links.length > 1 ? 'Leg ${i + 1} of ${links.length}' : 'Whole route',
                    style: const TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                child: const Text('Open'),
              ),
              TextButton(onPressed: () => _copy(url, 'Link'), child: const Text('Copy')),
            ]),
          if (links.length > 1)
            TextButton.icon(
              onPressed: () => _copy(links.join('\n'), 'All ${links.length} links'),
              icon: const Icon(Icons.copy_all, size: 18),
              label: Text('Copy all ${links.length}'),
            ),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );
}
