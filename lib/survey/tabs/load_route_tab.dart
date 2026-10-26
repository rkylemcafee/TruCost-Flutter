// lib/survey/tabs/load_route_tab.dart
//
// Load & route: what is being moved, where from and to, who drove it, and the
// state's own paperwork.
//
// Set once and read by every other tab — the height flags the overpasses, the
// deck length and width size the trailer on every turn, the weight goes
// against every bridge — so it comes first, as it does on the web.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../map_image.dart';
import '../survey_data.dart';
import '../survey_doc_source.dart';
import '../survey_repository.dart';
import '../widgets/static_map.dart';

const docKindLabel = {
  'state_survey': 'State route survey',
  'dot_map': 'DOT route map',
  'permit': 'Permit',
  'report': 'Route survey report',
  'other': 'Other',
};

class LoadRouteTab extends StatefulWidget {
  const LoadRouteTab({super.key, required this.data, required this.onChanged});
  final SurveyData data;
  final Future<void> Function() onChanged;

  @override
  State<LoadRouteTab> createState() => _LoadRouteTabState();
}

class _LoadRouteTabState extends State<LoadRouteTab> with AutomaticKeepAliveClientMixin {
  final _repo = SurveyRepository();
  final _c = <String, TextEditingController>{};
  bool _dirty = false;
  bool _busy = false;
  String? _verifiedOn;

  /// Text columns, edited as they are.
  static const _text = ['title', 'customer_name', 'origin_label', 'dest_label', 'verified_by'];

  /// Inch columns, edited as feet and inches because that is how a load is
  /// spoken about. Stored as inches, as the web stores them.
  static const _dims = {
    'load_height_in': 'Height',
    'load_width_in': 'Width',
    'load_length_in': 'Overall length',
    'trailer_length_in': 'Deck length',
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fill();
  }

  @override
  void didUpdateWidget(LoadRouteTab old) {
    super.didUpdateWidget(old);
    // A reload after somebody else's save; don't trample typing in progress.
    if (!_dirty) _fill();
  }

  void _fill() {
    final s = widget.data.survey;
    for (final k in _text) {
      (_c[k] ??= TextEditingController()).text = (s[k] ?? '').toString();
    }
    for (final k in _dims.keys) {
      final v = (s[k] as num?)?.toInt();
      (_c['${k}_ft'] ??= TextEditingController()).text = v == null ? '' : '${v ~/ 12}';
      (_c['${k}_in'] ??= TextEditingController()).text = v == null ? '' : '${v % 12}';
    }
    (_c['load_weight_lbs'] ??= TextEditingController()).text = (s['load_weight_lbs'] ?? '').toString();
    (_c['axle_count'] ??= TextEditingController()).text = (s['axle_count'] ?? '').toString();
    _verifiedOn = s['verified_on'] as String?;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  int? _inches(String k) {
    final f = _c['${k}_ft']!.text.trim(), i = _c['${k}_in']!.text.trim();
    if (f.isEmpty && i.isEmpty) return null;
    return (int.tryParse(f) ?? 0) * 12 + (int.tryParse(i) ?? 0);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _repo.updateSurvey(widget.data.id, {
        for (final k in _text) k: _c[k]!.text.trim(),
        for (final k in _dims.keys) k: _inches(k),
        'load_weight_lbs': int.tryParse(_c['load_weight_lbs']!.text.replaceAll(',', '').trim()),
        'axle_count': int.tryParse(_c['axle_count']!.text.trim()),
        'verified_on': _verifiedOn,
      });
      _dirty = false;
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _attach() async {
    final doc = await pickSurveyDoc(context);
    if (doc == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.uploadDocument(
        surveyId: widget.data.id,
        bytes: doc.bytes,
        fileName: doc.fileName,
        mimeType: doc.mimeType,
        kind: 'state_survey',
        caption: doc.isPaper ? 'Paper route survey, ${doc.imagePaths.length} page(s)' : '',
      );
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Filed with this survey — it is on the web too')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not store it: $e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickVerified() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDate: _verifiedOn == null ? now : DateTime.tryParse(_verifiedOn!) ?? now,
      helpText: 'The day the route was driven',
    );
    if (d == null) return;
    setState(() {
      _verifiedOn = d.toIso8601String().substring(0, 10);
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = widget.data;
    final locked = d.sealed;
    final segments = (d.survey['segments'] is List) ? d.survey['segments'] as List : const [];
    final stateDocs = d.documents.where((x) => x['kind'] != 'report').toList();

    return RefreshIndicator(
      onRefresh: widget.onChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          if (locked)
            _Banner(
              color: Colors.green,
              text: '${d.sealLine}. This survey is closed — nothing on it can change. '
                  'Open it for changes on trucost.app.',
            ),

          // ── Has anybody driven it? ───────────────────────────────────
          // The first thing the report says, and the thing that was missing
          // when a desk screening went out looking like a finished survey.
          _Banner(
            color: _verifiedOn == null ? Colors.amber : Colors.green,
            child: Row(children: [
              Icon(_verifiedOn == null ? Icons.warning_amber_rounded : Icons.verified_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _verifiedOn == null
                      ? 'Not driven yet. This is a desk screening until somebody drives it.'
                      : 'Driven $_verifiedOn${_c['verified_by']!.text.trim().isEmpty ? '' : ' by ${_c['verified_by']!.text.trim()}'}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (!locked)
                TextButton(
                  onPressed: _verifiedOn == null
                      ? _pickVerified
                      : () => setState(() {
                            _verifiedOn = null;
                            _dirty = true;
                          }),
                  child: Text(_verifiedOn == null ? 'I drove it' : 'Clear'),
                ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── The route ────────────────────────────────────────────────
          if (d.pieces.isNotEmpty) ...[
            StaticMap(url: overviewMapUrl(d.pieces), caption: '${d.title} — route'),
            const SizedBox(height: 6),
            Text(
              [
                if ((d.survey['origin_label'] ?? '').toString().isNotEmpty) d.survey['origin_label'],
                if ((d.survey['dest_label'] ?? '').toString().isNotEmpty) d.survey['dest_label'],
              ].join('  →  '),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            for (final s in segments.whereType<Map>())
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• ${s['label'] ?? s['kind']}', style: const TextStyle(fontSize: 12)),
              ),
          ] else
            const _Banner(
              color: Colors.grey,
              text: 'No route line yet. Bring in the state\'s survey from the list of surveys '
                  '(the + button) to have it drawn, or draw it on trucost.app.',
            ),
          const SizedBox(height: 20),

          // ── The state's paperwork ────────────────────────────────────
          Row(children: [
            const Expanded(child: _Heading('State route survey & paperwork')),
            if (!locked)
              TextButton.icon(
                onPressed: _busy ? null : _attach,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Add'),
              ),
          ]),
          if (stateDocs.isEmpty)
            const Text('Nothing filed. Add the PDF the state sent, or scan or photograph the paper copy.',
                style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            for (final doc in stateDocs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.description_outlined),
                title: Text((doc['caption'] ?? '').toString().isNotEmpty ? doc['caption'] : doc['file_name'] ?? ''),
                subtitle: Text(docKindLabel[doc['kind']] ?? 'Document'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => launchUrl(Uri.parse(_repo.publicUrl(doc['storage_path'])),
                    mode: LaunchMode.externalApplication),
              ),
          const SizedBox(height: 20),

          // ── The survey ───────────────────────────────────────────────
          const _Heading('The survey'),
          _field('title', 'Title', locked),
          _field('customer_name', 'Customer', locked),
          _field('origin_label', 'From', locked),
          _field('dest_label', 'To', locked),
          _field('verified_by', 'Driven by (as it should read on the report)', locked),
          const SizedBox(height: 20),

          // ── The load ─────────────────────────────────────────────────
          const _Heading('The load'),
          const Text(
            'Height flags every overpass too low. Deck length and width size the trailer on every turn — '
            'the deck, not the whole combination, because the tractor bends and the deck does not.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          for (final e in _dims.entries) _dim(e.key, e.value, locked),
          Row(children: [
            Expanded(child: _field('load_weight_lbs', 'Gross weight', locked, number: true, suffix: 'lb')),
            const SizedBox(width: 10),
            SizedBox(width: 110, child: _field('axle_count', 'Axles', locked, number: true)),
          ]),
        ],
      ),
    ).withSaveBar(
      show: _dirty && !locked,
      busy: _busy,
      onSave: _save,
    );
  }

  Widget _field(String k, String label, bool locked, {bool number = false, String? suffix}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c[k],
          readOnly: locked,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          onChanged: (_) => _touch(),
          decoration: InputDecoration(
            labelText: label,
            suffixText: suffix,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Widget _dim(String k, String label, bool locked) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: TextField(
              controller: _c['${k}_ft'],
              readOnly: locked,
              keyboardType: TextInputType.number,
              onChanged: (_) => _touch(),
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, suffixText: 'ft'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _c['${k}_in'],
              readOnly: locked,
              keyboardType: TextInputType.number,
              onChanged: (_) => _touch(),
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, suffixText: 'in'),
            ),
          ),
        ]),
      );
}

extension on Widget {
  /// The tab's content with a Save bar pinned under it while there is
  /// something to save.
  Widget withSaveBar({required bool show, required bool busy, required VoidCallback onSave}) => Column(children: [
        Expanded(child: this),
        if (show)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: busy ? null : onSave,
                icon: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('Save changes'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ),
          ),
      ]);
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, this.text, this.child});
  final MaterialColor color;
  final String? text;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.shade50,
          border: Border.all(color: color.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child ?? Text(text ?? '', style: TextStyle(fontSize: 12.5, color: color.shade900)),
      );
}
