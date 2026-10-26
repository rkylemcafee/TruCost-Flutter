// lib/survey/widgets/empty_note.dart
//
// A short grey line saying why a tab is empty, and what fills it.

import 'package:flutter/material.dart';

class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ),
      ]);
}
