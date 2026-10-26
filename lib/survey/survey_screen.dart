// lib/survey/survey_screen.dart
//
// One survey, in the same tabs as trucost.app.
//
// The web page settled on tabs because the work comes in phases — set the
// load up once, work the turns, rule on what is overhead and what carries the
// load, export, keep the reports — and almost nothing on one tab is looked at
// with anything on another. A handset has even less room for everything at
// once, so the phases are the same and in the same order. Counts sit in the
// tab labels because the first question about each is "how many".

import 'package:flutter/material.dart';
import 'survey_data.dart';
import 'survey_repository.dart';
import 'tabs/load_route_tab.dart';
import 'tabs/turns_tab.dart';
import 'tabs/bridges_tab.dart';
import 'tabs/overpasses_tab.dart';
import 'tabs/export_tab.dart';
import 'tabs/reports_tab.dart';

class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key, required this.surveyId, required this.title});
  final String surveyId;
  final String title;

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  final _repo = SurveyRepository();
  SurveyData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_data == null) setState(() => _loading = true);
    try {
      final survey = await _repo.survey(widget.surveyId);
      if (survey == null) throw 'This survey is no longer there.';
      final points = await _repo.points(widget.surveyId);
      final photos = await _repo.photos(widget.surveyId);
      // Newer tables than some surveys; a survey made before them has none.
      List<Map<String, dynamic>> structures = [];
      List<Map<String, dynamic>> documents = [];
      try { structures = await _repo.structures(widget.surveyId); } catch (_) {}
      try { documents = await _repo.documents(widget.surveyId); } catch (_) {}
      if (!mounted) return;
      setState(() {
        _data = SurveyData(
          survey: survey,
          points: points,
          photos: photos,
          structures: structures,
          documents: documents,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load: $e')));
    }
  }

  String _count(String label, int n) => n > 0 ? '$label  $n' : label;

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(d?.title ?? widget.title, overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Load & route'),
              Tab(text: _count('Turn by turn', d?.points.length ?? 0)),
              Tab(text: _count('Bridges', d?.crossed.length ?? 0)),
              Tab(text: _count('Overpasses', d?.overhead.length ?? 0)),
              const Tab(text: 'Export'),
              Tab(text: _count('Reports', d?.docsOfKind('report').length ?? 0)),
            ],
          ),
        ),
        body: _loading || d == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                // Sideways swipes belong to the maps on these tabs.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  LoadRouteTab(data: d, onChanged: _load),
                  TurnsTab(data: d, onChanged: _load),
                  BridgesTab(data: d, onChanged: _load),
                  OverpassesTab(data: d, onChanged: _load),
                  ExportTab(data: d, onChanged: _load),
                  ReportsTab(data: d, onChanged: _load),
                ],
              ),
      ),
    );
  }
}
