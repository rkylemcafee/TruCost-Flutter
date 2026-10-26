// The column-preserving layout the INDOT parser depends on, and the verdict on
// whether a document has a text layer worth parsing.

import 'package:flutter_test/flutter_test.dart';
import 'package:trucost_flutter/survey/import/indot_survey.dart';
import 'package:trucost_flutter/survey/import/pdf_text.dart';

/// A fragment of `s` at column `col` on row `row`, in a 6-unit-wide font.
TextFrag frag(int row, int col, String s) =>
    TextFrag(x: 36 + col * 6.0, y: 700 - row * 12.0, w: s.length * 6.0, s: s);

void main() {
  test('fragments land in their columns, top of the page first', () {
    final page = [
      // Arrive out of order, as a PDF's content stream often does.
      frag(1, 0, '3.20'),
      frag(1, 16, 'SR-69 North'),
      frag(1, 35, 'Turn right onto SR-62'),
      frag(1, 59, '3.20'),
      frag(0, 0, 'Miles'),
      frag(0, 16, 'Route'),
      frag(0, 35, 'To'),
      frag(0, 59, 'Distance'),
    ];
    final lines = layoutPage(page).split('\n');
    expect(lines.length, 2);
    expect(lines[0].indexOf('Route'), 16);
    expect(lines[1].indexOf('SR-69 North'), 16);
    expect(lines[1].indexOf('3.20', 5), 59);
  });

  // pdf.js emits a single " " for any gap; a column break must still come out
  // as a run of spaces wide enough for the parser to split on.
  test('the parser reads a laid-out row as a step', () {
    final page = [
      frag(0, 0, '3.20'),
      frag(0, 4, ' '),
      frag(0, 16, 'SR-69 North'),
      frag(0, 35, 'Turn right onto SR-62'),
      frag(0, 59, '3.20'),
    ];
    final text = '==> A <==SR-69 North==> B <==\n${layoutPage(page)}';
    final s = parseIndotSurvey(text);
    final step = s.segments.single.steps.single;
    expect(step.miles, 3.2);
    expect(step.route, 'SR-69 North');
    expect(step.instruction, 'Turn right onto SR-62');
    expect(step.cumulative, 3.2);
  });

  test('fragments within a couple of units share a line; overlapping words do not overwrite', () {
    final a = TextFrag(x: 36, y: 700, w: 30, s: 'Hello');
    final b = TextFrag(x: 37, y: 701.5, w: 30, s: 'World');
    expect(layoutPage([a, b]), 'Hello World');
  });

  test('an empty page is empty', () {
    expect(layoutPage([]), '');
    expect(layoutPage([TextFrag(x: 0, y: 0, w: 5, s: '   ')]), '');
  });

  test('a page with too little text is unusable, in plain words', () {
    final r = readFragments([
      [frag(0, 0, 'SURVEY')],
    ]);
    expect(r.usable, isFalse);
    expect(r.text, '');
    expect(r.pages, 1);
    expect(r.why, startsWith('This PDF has no readable text layer'));
  });

  test('enough text per page is usable', () {
    final words = 'x' * 160;
    final r = readFragments([
      [frag(0, 0, words)],
      [frag(0, 0, words)],
    ]);
    expect(r.usable, isTrue);
    expect(r.pages, 2);
    expect(r.text, '$words\n$words');
    // 150 characters a page, across all pages: two pages need 300.
    expect(readFragments([[frag(0, 0, words)], []]).usable, isFalse);
    expect(readFragments([[frag(0, 0, 'x' * 100)], [frag(0, 0, 'x' * 100)]]).usable, isFalse);
  });
}
