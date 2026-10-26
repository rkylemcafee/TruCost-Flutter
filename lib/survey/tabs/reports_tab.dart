// lib/survey/tabs/reports_tab.dart
//
// Reports: everything this survey has produced, under its name.
//
// Every PDF report ever made for it, newest first — kept, because the route
// changes by the hour while the work is being done and "which one did the
// state get?" has a real answer. And every map the survey makes: the whole
// route, the bridges, the overpasses, and each turn framed with the trailer
// on it, each one a tap from full screen and a share.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../map_image.dart';
import '../survey_data.dart';
import '../survey_export.dart';
import '../survey_pdf.dart';
import '../survey_repository.dart';
import '../widgets/static_map.dart';
import 'load_route_tab.dart' show docKindLabel;

/// Make the report, keep it on the survey, and offer to send it.
///
/// Kept first and shared second: a report that was sent but not kept is the
/// one nobody can find when the permit office calls.
Future<void> makeAndKeepReport(BuildContext context, SurveyData d, Future<void> Function() onChanged) async {
  final step = ValueNotifier<String>('Starting');
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 16),
        Expanded(child: ValueListenableBuilder(valueListenable: step, builder: (_, s, _) => Text(s))),
      ]),
    ),
  );
  File? file;
  String? problem;
  try {
    final bytes = await buildSurveyPdf(d, onStep: (s) => step.value = s);
    final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(RegExp(r'[:T]'), '-');
    final name = '${fileStem(d)}_$stamp.pdf';
    final dir = await getTemporaryDirectory();
    file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);

    step.value = 'Filing it with the survey';
    try {
      await SurveyRepository().uploadDocument(
        surveyId: d.id,
        bytes: bytes,
        fileName: name,
        mimeType: 'application/pdf',
        kind: 'report',
        caption: '${d.points.length} turn(s) · ${d.overhead.length} overpass(es) · '
            '${d.crossed.length} bridge(s) · made on iPhone',
      );
    } catch (e) {
      problem = 'The report was made, but could not be kept on the survey ($e). Share it now so it is not lost.';
    }
  } catch (e) {
    problem = 'The report could not be made: $e';
  }
  step.dispose();
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  await onChanged();
  if (!context.mounted) return;
  if (problem != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem), duration: const Duration(seconds: 8)));
  }
  if (file != null) {
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], subject: d.title));
  }
}

class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key, required this.data, required this.onChanged});
  final SurveyData data;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final repo = SurveyRepository();
    final reports = d.docsOfKind('report');
    final paperwork = d.documents.where((x) => x['kind'] != 'report').toList();

    final maps = <({String url, String caption})>[
      if (d.pieces.isNotEmpty) (url: overviewMapUrl(d.pieces), caption: 'The route'),
      if (d.pieces.isNotEmpty && d.crossed.isNotEmpty) (url: d.bridgesMapUrl(), caption: 'Bridges crossed'),
      if (d.pieces.isNotEmpty && d.overhead.isNotEmpty) (url: d.overpassesMapUrl(), caption: 'Overpasses'),
      if (d.route.length >= 2)
        for (final p in d.points) (url: d.turnMapUrl(p), caption: 'Turn ${p['seq']}'),
      for (final s in d.overhead)
        (url: d.structureMapUrl(s), caption: 'Overpass ${ftIn(s['clearance_in'] as num?)} — ${s['carries'] ?? ''}'),
      for (final s in d.crossed) (url: d.structureMapUrl(s), caption: 'Bridge — ${s['carries'] ?? ''}'),
    ];

    String when(Object? iso) {
      final t = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
      if (t == null) return '';
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      return '${t.month}/${t.day}/${t.year} $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    }

    return RefreshIndicator(
      onRefresh: onChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Text(d.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('${d.points.length} turn(s) · ${d.crossed.length} bridge(s) · ${d.overhead.length} overpass(es)'
              '${d.overhead.where(d.tooLow).isNotEmpty ? ' · ${d.overhead.where(d.tooLow).length} too low' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: d.points.isEmpty ? null : () => makeAndKeepReport(context, d, onChanged),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Make a report (PDF)'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
          const SizedBox(height: 16),

          // ── Every report made, newest first ─────────────────────────
          const _Heading('Reports'),
          if (reports.isEmpty)
            const Text('None yet. Each one you make is kept here, and on trucost.app.',
                style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            for (final r in reports)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: Text(when(r['created_at'])),
                subtitle: Text(
                  [
                    if ((r['caption'] ?? '').toString().isNotEmpty) r['caption'],
                    if (r['byte_size'] != null) '${((r['byte_size'] as num) / 1e6).toStringAsFixed(1)} MB',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => launchUrl(Uri.parse(repo.publicUrl(r['storage_path'])),
                    mode: LaunchMode.externalApplication),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    final url = repo.publicUrl(r['storage_path']);
                    if (v == 'share') {
                      await SharePlus.instance.share(ShareParams(uri: Uri.parse(url), subject: d.title));
                    } else if (v == 'delete') {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete this report?'),
                          content: Text('The one made ${when(r['created_at'])}. Copies already sent are not affected.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await repo.deleteDocument(r);
                        await onChanged();
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'share', child: Text('Share link')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
          const SizedBox(height: 16),

          // ── Every map the survey makes ──────────────────────────────
          _Heading('Maps (${maps.length})'),
          if (maps.isEmpty)
            const Text('No route line yet, so no maps.', style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.98,
              children: [
                for (final m in maps)
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    StaticMap(url: m.url, caption: '${d.title} — ${m.caption}'),
                    const SizedBox(height: 4),
                    Text(m.caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  ]),
              ],
            ),
          const SizedBox(height: 16),

          // ── The paperwork it came from ──────────────────────────────
          if (paperwork.isNotEmpty) ...[
            const _Heading('Paperwork'),
            for (final doc in paperwork)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text((doc['caption'] ?? '').toString().isNotEmpty ? doc['caption'] : doc['file_name'] ?? ''),
                subtitle: Text(docKindLabel[doc['kind']] ?? 'Document'),
                onTap: () => launchUrl(Uri.parse(repo.publicUrl(doc['storage_path'])),
                    mode: LaunchMode.externalApplication),
              ),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );
}
