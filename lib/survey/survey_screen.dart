// lib/survey/survey_screen.dart
//
// One survey, in tabs.
//
// The web app shows the whole thing at once because a desk has the room for it.
// A handset does not, so the work is split by the question being asked: where
// does it go, what do I have to look at, and what is overhead. Each tab is one
// job, and the detail for a single turn gets a screen of its own rather than a
// row in a list.

import 'package:flutter/material.dart';
import 'survey_repository.dart';
import 'turn_screen.dart';

class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key, required this.surveyId, required this.title});
  final String surveyId;
  final String title;

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  final _repo = SurveyRepository();
  Map<String, dynamic>? _survey;
  List<Map<String, dynamic>> _points = [];
  List<Map<String, dynamic>> _photos = [];
  List<Map<String, dynamic>> _structures = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final survey = await _repo.survey(widget.surveyId);
      final points = await _repo.points(widget.surveyId);
      final photos = await _repo.photos(widget.surveyId);
      // The structures table is newer than some surveys; a survey made before
      // it existed simply has none.
      List<Map<String, dynamic>> structures = [];
      try { structures = await _repo.structures(widget.surveyId); } catch (_) {}
      if (!mounted) return;
      setState(() {
        _survey = survey;
        _points = points;
        _photos = photos;
        _structures = structures;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load: $e')));
    }
  }

  int _photoCount(String pointId) =>
      _photos.where((p) => p['point_id'] == pointId).length;

  int? get _loadHeightIn => _survey?['load_height_in'] as int?;

  @override
  Widget build(BuildContext context) {
    final overhead = _structures.where((s) => s['kind'] != 'cross' && s['status'] != 'ignore').toList();
    final crossed = _structures.where((s) => s['kind'] == 'cross' && s['status'] != 'ignore').toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Turns (${_points.length})'),
              Tab(text: 'Overhead (${overhead.length})'),
              Tab(text: 'Bridges (${crossed.length})'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                _turns(),
                _overhead(overhead),
                _crossed(crossed),
              ]),
      ),
    );
  }

  // ── Turns ────────────────────────────────────────────────────────────────
  Widget _turns() {
    if (_points.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('No turns in this survey yet. Import a route on the web.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      ));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _points.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final p = _points[i];
          final pics = _photoCount(p['id']);
          final clearance = p['clearance_in'] as int?;
          return ListTile(
            leading: CircleAvatar(
              radius: 16,
              child: Text('${p['seq']}', style: const TextStyle(fontSize: 12)),
            ),
            title: Text(
              (p['instruction'] ?? '').toString().isEmpty
                  ? '(no wording yet)'
                  : p['instruction'],
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
            subtitle: Row(children: [
              Text(p['kind'] ?? 'turn', style: const TextStyle(fontSize: 12)),
              if (clearance != null) ...[
                const Text('  ·  ', style: TextStyle(fontSize: 12)),
                Text("${clearance ~/ 12}'${clearance % 12}\"",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
              if (pics > 0) ...[
                const Text('  ·  ', style: TextStyle(fontSize: 12)),
                const Icon(Icons.photo_camera, size: 13),
                Text(' $pics', style: const TextStyle(fontSize: 12)),
              ],
            ]),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => TurnScreen(
                  surveyId: widget.surveyId,
                  point: p,
                  total: _points.length,
                ),
              ));
              if (mounted) _load();
            },
          );
        },
      ),
    );
  }

  // ── Overhead ─────────────────────────────────────────────────────────────
  Widget _overhead(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('Nothing overhead on this route.\n\nRun the check on the web to populate this.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      ));
    }
    final h = _loadHeightIn;
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final s = rows[i];
        final c = s['clearance_in'] as int?;
        final tooLow = h != null && c != null && c < h;
        return ListTile(
          tileColor: tooLow ? Colors.red.withValues(alpha: 0.06) : null,
          leading: Text(
            c == null ? '—' : "${c ~/ 12}'${c % 12}\"",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: tooLow ? Colors.red.shade800 : null,
            ),
          ),
          title: Text(s['carries'] ?? 'structure', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text([
            if (s['miles_along'] != null) '${(s['miles_along'] as num).toStringAsFixed(1)} mi',
            if (s['crosses'] != null) 'over ${s['crosses']}',
            // tooLow is only true when both are present, so h! and c! are safe.
            if (tooLow) "${(h - c) ~/ 12}'${(h - c) % 12}\" too tall",
          ].join('  ·  '), style: const TextStyle(fontSize: 12)),
        );
      },
    );
  }

  // ── Bridges crossed ──────────────────────────────────────────────────────
  Widget _crossed(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('No crossings recorded.\n\nRun the check on the web to populate this.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      ));
    }
    final totalFt = rows.fold<double>(0, (n, s) => n + ((s['length_ft'] as num?)?.toDouble() ?? 0));
    final weight = _survey?['load_weight_lbs'] as int?;
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
          '${rows.length} structures carry this load'
          '${totalFt > 0 ? '  ·  ${totalFt.round()} ft of deck' : ''}'
          '${weight != null ? '  ·  $weight lb across each' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = rows[i];
            final len = (s['length_ft'] as num?)?.round();
            return ListTile(
              leading: Text(len == null ? '—' : '$len ft',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              title: Text(s['carries'] ?? 'structure', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text([
                if (s['miles_along'] != null) '${(s['miles_along'] as num).toStringAsFixed(1)} mi',
                if (s['crosses'] != null) 'over ${s['crosses']}',
                if ((s['action'] ?? '').toString().isNotEmpty) s['action'],
              ].join('  ·  '), style: const TextStyle(fontSize: 12)),
            );
          },
        ),
      ),
    ]);
  }
}
