// lib/survey/survey_list_screen.dart
//
// The surveys this tenant has. The office builds them on the web; this is how
// they get into the truck.

import 'package:flutter/material.dart';
import 'survey_repository.dart';
import 'survey_screen.dart';

class SurveyListScreen extends StatefulWidget {
  const SurveyListScreen({super.key});
  @override
  State<SurveyListScreen> createState() => _SurveyListScreenState();
}

class _SurveyListScreenState extends State<SurveyListScreen> {
  final _repo = SurveyRepository();
  List<Map<String, dynamic>> _surveys = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await _repo.surveys();
      if (!mounted) return;
      setState(() { _surveys = rows; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  String _subtitle(Map<String, dynamic> s) {
    final bits = <String>[];
    if ((s['customer_name'] ?? '').toString().isNotEmpty) bits.add(s['customer_name']);
    final h = s['load_height_in'] as int?;
    if (h != null) bits.add("${h ~/ 12}'${h % 12}\" tall");
    if ((s['surveyed_on'] ?? '').toString().isNotEmpty) bits.add(s['surveyed_on']);
    return bits.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Route Surveys')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text('Could not load surveys.\n$_error',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Try again')),
                      ]),
                    ),
                  ])
                : _surveys.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No surveys yet.', style: TextStyle(color: Colors.grey))),
                        SizedBox(height: 8),
                        Center(child: Text('Build one on the web and it appears here.',
                            style: TextStyle(color: Colors.grey, fontSize: 12))),
                      ])
                    : ListView.separated(
                        itemCount: _surveys.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final s = _surveys[i];
                          return ListTile(
                            leading: const Icon(Icons.signpost_outlined),
                            title: Text(s['title'] ?? 'Untitled survey'),
                            subtitle: Text(_subtitle(s)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => SurveyScreen(surveyId: s['id'], title: s['title'] ?? 'Survey'),
                              ));
                              if (mounted) _load();
                            },
                          );
                        },
                      ),
      ),
    );
  }
}
