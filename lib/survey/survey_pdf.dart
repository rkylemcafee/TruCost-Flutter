// lib/survey/survey_pdf.dart
//
// The route survey report, made on the phone.
//
// The same sections, in the same order, as the report trucost.app prints
// (src/lib/surveyPdf.ts): what was surveyed and whether anybody drove it, the
// load, the whole route on one map, what is overhead and what carries the
// load, then every turn with its framed map, the trailer drawn on it, and the
// photographs filed under it. Made here it is filed against the survey like a
// desk report, so "which one did they get?" has one answer wherever it was
// made.

import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'map_image.dart';
import 'survey_data.dart';
import 'survey_repository.dart';

const _blue = PdfColor.fromInt(0xFF1A56DB);
const _red = PdfColor.fromInt(0xFFB91C1C);
const _grey = PdfColor.fromInt(0xFF6B7280);

/// Fetch a picture for the page. One missing map costs that picture, not the
/// report — a bad signal on the shoulder of a road should not lose the lot.
Future<pw.MemoryImage?> _image(String url) async {
  try {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
    return pw.MemoryImage(r.bodyBytes);
  } catch (_) {
    return null;
  }
}

Future<Uint8List> buildSurveyPdf(SurveyData d, {void Function(String step)? onStep}) async {
  final repo = SurveyRepository();
  final s = d.survey;

  onStep?.call('Fetching the route map');
  final overview = d.pieces.isEmpty ? null : await _image(overviewMapUrl(d.pieces, width: 640, height: 400));

  // Maps one turn at a time: Google throttles a burst of sixty, and a
  // progress line that counts up is worth more than a few seconds saved.
  final turnMaps = <String, pw.MemoryImage?>{};
  final turnPhotos = <String, List<pw.MemoryImage>>{};
  for (final (i, p) in d.points.indexed) {
    onStep?.call('Turn ${i + 1} of ${d.points.length}');
    turnMaps[p['id']] = d.route.length >= 2 ? await _image(d.turnMapUrl(p, width: 640, height: 400)) : null;
    final pics = <pw.MemoryImage>[];
    for (final ph in d.photosFor(p['id']).take(2)) {
      final img = await _image(repo.publicUrl(ph['storage_path']));
      if (img != null) pics.add(img);
    }
    turnPhotos[p['id']] = pics;
  }

  onStep?.call('Laying out the pages');
  final doc = pw.Document(title: d.title, author: 'TruCost');
  final verified = s['verified_on'] as String?;
  final h = d.loadHeightIn;

  pw.Widget heading(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _blue)),
      );

  pw.Widget kv(String k, String v) => pw.Row(children: [
        pw.SizedBox(width: 110, child: pw.Text(k, style: const pw.TextStyle(fontSize: 9, color: _grey))),
        pw.Text(v, style: const pw.TextStyle(fontSize: 10)),
      ]);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.letter,
    margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text(d.title, style: const pw.TextStyle(fontSize: 8, color: _grey)),
      pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _grey)),
    ]),
    build: (ctx) => [
      // ── Title block ──────────────────────────────────────────────────
      pw.Text('ROUTE SURVEY', style: pw.TextStyle(fontSize: 9, letterSpacing: 2, color: _grey)),
      pw.Text(d.title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      if ((s['origin_label'] ?? '').toString().isNotEmpty || (s['dest_label'] ?? '').toString().isNotEmpty)
        pw.Text('${s['origin_label'] ?? 'Origin'}  to  ${s['dest_label'] ?? 'Destination'}',
            style: const pw.TextStyle(fontSize: 11)),
      if ((s['customer_name'] ?? '').toString().isNotEmpty)
        pw.Text('For ${s['customer_name']}', style: const pw.TextStyle(fontSize: 10, color: _grey)),
      pw.SizedBox(height: 10),

      // ── Has anybody actually driven this? ───────────────────────────
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: verified == null ? PdfColors.amber700 : PdfColors.green700),
          color: verified == null ? PdfColors.amber50 : PdfColors.green50,
        ),
        child: pw.Text(
          verified == null
              ? 'NOT DRIVEN. This is a desk screening from maps and records. Nobody has driven this route for this load yet.'
              : 'Driven $verified${(s['verified_by'] ?? '').toString().isEmpty ? '' : ' by ${s['verified_by']}'}.',
          style: const pw.TextStyle(fontSize: 10),
        ),
      ),

      // ── Load ─────────────────────────────────────────────────────────
      heading('THE LOAD'),
      kv('Height', ftIn(h)),
      kv('Width', ftIn(d.loadWidthIn)),
      kv('Overall length', ftIn(s['load_length_in'] as num?)),
      kv('Deck length', ftIn(s['trailer_length_in'] as num?)),
      kv('Gross weight', d.loadWeightLbs == null ? '—' : '${d.loadWeightLbs} lb'),
      if (s['axle_count'] != null) kv('Axles', '${s['axle_count']}'),

      // ── Overview map ─────────────────────────────────────────────────
      if (overview != null) ...[
        heading('THE ROUTE'),
        pw.Image(overview, height: 300, fit: pw.BoxFit.contain),
      ],

      // ── Structures ───────────────────────────────────────────────────
      if (d.overhead.isNotEmpty) ...[
        heading('OVERHEAD — ${d.overhead.length} STRUCTURE(S)'
            '${h == null ? '' : ', ${d.overhead.where(d.tooLow).length} TOO LOW FOR ${ftIn(h)}'}'),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headers: ['Mile', 'Clearance', 'Carries', 'Over', 'Notes'],
          data: [
            for (final x in d.overhead)
              [
                milesLabel(x['miles_along']),
                '${ftIn(x['clearance_in'] as num?)}${d.tooLow(x) ? '  TOO LOW' : ''}',
                x['carries'] ?? '',
                x['crosses'] ?? '',
                [x['action'], x['notes']].where((v) => (v ?? '').toString().isNotEmpty).join(' — '),
              ],
          ],
          cellDecoration: (index, data, row) => row > 0 && d.tooLow(d.overhead[row - 1])
              ? const pw.BoxDecoration(color: PdfColors.red50)
              : const pw.BoxDecoration(),
        ),
      ],
      if (d.crossed.isNotEmpty) ...[
        heading('BRIDGES CROSSED — ${d.crossed.length}'
            '${d.loadWeightLbs == null ? '' : ', ${d.loadWeightLbs} LB ACROSS EACH'}'),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headers: ['Mile', 'Length', 'Carries', 'Over', 'Rating', 'Notes'],
          data: [
            for (final x in d.crossed)
              [
                milesLabel(x['miles_along']),
                x['length_ft'] == null ? '—' : '${(x['length_ft'] as num).round()} ft',
                x['carries'] ?? '',
                x['crosses'] ?? '',
                x['operating_tons'] == null ? '' : '${x['operating_tons']} t',
                [x['action'], x['notes']].where((v) => (v ?? '').toString().isNotEmpty).join(' — '),
              ],
          ],
        ),
      ],

      // ── The turns ────────────────────────────────────────────────────
      if (d.points.isNotEmpty) heading('TURN BY TURN'),
      for (final p in d.points)
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Container(
                width: 20,
                height: 20,
                alignment: pw.Alignment.center,
                decoration: const pw.BoxDecoration(color: _blue, shape: pw.BoxShape.circle),
                child: pw.Text('${p['seq']}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.white)),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text((p['instruction'] ?? '').toString().isEmpty ? '(no wording)' : p['instruction'],
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    [
                      p['kind'] ?? 'turn',
                      if (p['clearance_in'] != null) 'measured clearance ${ftIn(p['clearance_in'] as num)}',
                      '${(p['lat'] as num).toStringAsFixed(5)}, ${(p['lng'] as num).toStringAsFixed(5)}',
                    ].join('  ·  '),
                    style: const pw.TextStyle(fontSize: 8, color: _grey),
                  ),
                ]),
              ),
            ]),
            pw.SizedBox(height: 4),
            if (turnMaps[p['id']] != null) pw.Image(turnMaps[p['id']]!, height: 250, fit: pw.BoxFit.contain),
            if ((turnPhotos[p['id']] ?? []).isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Row(children: [
                  for (final img in turnPhotos[p['id']]!)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 6),
                      child: pw.Image(img, height: 120, fit: pw.BoxFit.contain),
                    ),
                ]),
              ),
          ]),
        ),

      if (d.haveDeck && d.points.isNotEmpty)
        pw.Text(
          'The yellow outline on each turn is the ${ftIn(s['trailer_length_in'] as num?)} × ${ftIn(d.loadWidthIn)} deck, '
          'drawn to scale where the escort placed it.',
          style: const pw.TextStyle(fontSize: 8, color: _grey),
        ),
      pw.SizedBox(height: 8),
      pw.Text(
        'Clearances and bridge records are from the states\' filings and the FHWA National Bridge Inventory: '
        'places to look, never permission. Made ${DateTime.now().toString().substring(0, 16)} on the TruCost iPhone app.',
        style: const pw.TextStyle(fontSize: 7, color: _red),
      ),
    ],
  ));

  return doc.save();
}
