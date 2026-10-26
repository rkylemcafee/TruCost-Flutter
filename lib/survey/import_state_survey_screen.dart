// lib/survey/import_state_survey_screen.dart
//
// Bring in a state's route survey and turn it into a survey here.
//
// The phone's version of the web's ImportStateSurvey dialog, and like it, the
// document is read and shown back before anything is created. That review is
// not ceremony: on 2026-10-22 the web read survey 18144 as six trips with real
// mileage and every origin attached to the wrong trip, and nothing errored. A
// person who has the paper in their hand spots that in a second.
//
// The reading is Indiana's form (State Form 56411). Paper is read by the
// phone's own text recognition, which is good but not perfect — so the review
// matters more for a photograph than for a PDF, and says so.

import 'package:flutter/material.dart';
import 'import/indot_survey.dart';
import 'import/pdf_text.dart';
import 'import/state_survey_import.dart';
import 'survey_doc_source.dart';
import 'survey_screen.dart';

class ImportStateSurveyScreen extends StatefulWidget {
  const ImportStateSurveyScreen({super.key, required this.doc});
  final SurveyDocFile doc;

  @override
  State<ImportStateSurveyScreen> createState() => _ImportStateSurveyScreenState();
}

class _ImportStateSurveyScreenState extends State<ImportStateSurveyScreen> {
  String _step = 'Reading the document';
  String? _problem;
  IndotSurvey? _survey;
  List<DrawnTrip> _drawn = [];
  List<String> _missing = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final pages = await widget.doc.fragments();
      final text = readFragments([
        for (final page in pages)
          [
            for (final f in page)
              TextFrag(
                x: (f['x'] as num).toDouble(),
                y: (f['y'] as num).toDouble(),
                w: (f['w'] as num).toDouble(),
                s: f['s'] as String,
              ),
          ],
      ]);
      if (!text.usable) {
        return setState(() => _problem = widget.doc.isPaper
            ? 'Not enough words could be read off the picture. Try the scanner in good light, flat on a table.'
            : text.why);
      }
      final s = parseIndotSurvey(text.text);
      if (s.segments.isEmpty) {
        return setState(() => _problem =
            'This does not read as an Indiana route survey (State Form 56411) — no trips were found in it. '
            'It can still be kept: open the survey it belongs to and add it on Load & route.');
      }
      setState(() {
        _survey = s;
        _step = 'Drawing the route from the roads it names';
      });
      final drawn = await drawTrips(s, 'IN', (done, total) {
        if (mounted) setState(() => _step = 'Fetching road $done of $total');
      });
      if (!mounted) return;
      setState(() {
        _drawn = drawn.drawn;
        _missing = drawn.missing;
        _step = '';
      });
    } catch (e) {
      if (mounted) setState(() => _problem = 'Could not read it: $e');
    }
  }

  Future<void> _create() async {
    final s = _survey!;
    setState(() => _saving = true);
    String? id;
    try {
      id = await saveImportedSurvey(
        parsed: s,
        drawn: _drawn,
        fileBytes: widget.doc.bytes,
        fileName: widget.doc.fileName,
        mimeType: widget.doc.mimeType,
      );
    } on SurveyPdfNotStored catch (e) {
      // The survey exists and is right; only the copy of the paper is missing.
      id = e.surveyId;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('The survey was made, but the document could not be stored (${e.message}). '
              'Add it again on Load & route.'),
          duration: const Duration(seconds: 8),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create it: $e')));
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => SurveyScreen(surveyId: id!, title: 'IN ${s.routeNumber ?? 'route survey'}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = _survey;
    return Scaffold(
      appBar: AppBar(title: const Text('State route survey')),
      body: _problem != null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Icon(Icons.error_outline, size: 40, color: Colors.grey),
                const SizedBox(height: 12),
                Text(_problem!, textAlign: TextAlign.center),
              ]),
            )
          : s == null || _step.isNotEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_step),
                  ]),
                )
              : _review(s),
      bottomNavigationBar: s != null && _step.isEmpty && _problem == null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _saving || _drawn.every((d) => d.dropped) ? null : _create,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('This matches the paper — create the survey'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _review(IndotSurvey s) {
    final drawnMiles = _drawn.where((d) => !d.dropped).fold<double>(0, (n, d) => n + d.geom.miles);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('Indiana route survey ${s.routeNumber ?? ''}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        if (s.carrier != null) Text(s.carrier!, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 6),
        Text(
          [
            if (s.heightIn != null) '${feetInches(s.heightIn!)} tall',
            if (s.widthIn != null) '${feetInches(s.widthIn!)} wide',
            if (s.lengthIn != null) '${feetInches(s.lengthIn!)} long',
            if (s.weightLb != null) '${s.weightLb} lb',
          ].join('  ·  '),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            border: Border.all(color: Colors.amber.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Check every trip below against the ${widget.doc.isPaper ? 'paper' : 'PDF'} before creating it: '
            'where each one starts and ends, and its miles. Untick a trip the load does not drive — '
            'it is kept with the survey but nothing is drawn for it.'
            '${widget.doc.isPaper ? ' This was read off a picture, so a misread road name is possible.' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
          ),
        ),
        const SizedBox(height: 8),
        if (_missing.isNotEmpty)
          Text('No road data for: ${_missing.join(', ')}. Those stretches cannot be drawn.',
              style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
        for (final (i, d) in _drawn.indexed)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: !d.dropped,
            onChanged: (v) => setState(() => _drawn[i] = d.withDropped(v != true)),
            title: Text(d.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              [
                if (i < s.segments.length) '${s.segments[i].originText} → ${s.segments[i].destText}',
                'drawn ${d.geom.miles.toStringAsFixed(1)} mi of ${d.geom.statedMiles.toStringAsFixed(1)} stated',
                if (d.geom.why.isNotEmpty) d.geom.why,
              ].join('\n'),
              style: TextStyle(
                fontSize: 12,
                color: d.geom.shape.isEmpty || d.geom.why.isNotEmpty ? Colors.red.shade800 : null,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text('${drawnMiles.toStringAsFixed(1)} mi drawn  ·  ${s.alerts.length} alert(s) on the form',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
