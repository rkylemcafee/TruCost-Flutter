// lib/survey/import/pdf_text.dart
//
// Port of the web app's src/lib/pdfText.ts: rebuild a page's text fragments
// into lines, keeping the columns.
//
// A route survey is a table. INDOT's routing instructions line up Miles,
// Route, To and Distance in columns, and indot_survey.dart splits those rows
// on runs of spaces — so an extraction that returns the right words in the
// right order but loses the gaps between them produces a document the parser
// reads as nonsense.
//
// PDF has no notion of a line. It has glyphs at coordinates. So this groups
// fragments into rows by their vertical position, orders each row left to
// right, and puts back a number of spaces proportional to the horizontal gap
// — which is what `pdftotext -layout` does, and what the parser was written
// against.
//
// It is deliberately willing to say it failed. Route survey 18093 arrived as
// Type 3 fonts with no ToUnicode table, which means the glyphs carry no
// information about which characters they are: the document is readable to a
// human and genuinely unreadable to software. Returning half a survey from
// one of those would be worse than returning nothing, because a half-read
// route looks exactly like a real one.
//
// On the phone the fragments come from the native side (PDFKit for a PDF,
// Vision OCR for a photograph of a paper survey); this file only lays them
// out and judges them.

/// One run of text at a position on the page.
///
/// [x] and [y] are page units with y increasing UPWARD — the PDF convention,
/// the same as pdf.js `transform[4]` / `transform[5]`. [w] is the run's width
/// in the same units, 0 when unknown.
class TextFrag {
  double x;
  double y;
  double w;
  String s;

  TextFrag({required this.x, required this.y, required this.w, required this.s});
}

class PdfText {
  /// Reconstructed text, columns preserved. Empty when unusable.
  final String text;
  final int pages;

  /// False when there is no text layer worth parsing.
  final bool usable;

  /// Plain-language reason, when not usable.
  final String why;

  const PdfText({
    required this.text,
    required this.pages,
    required this.usable,
    required this.why,
  });

  /// The web's answer when pdf.js could not open the file at all, for the
  /// native side to return in the same words.
  factory PdfText.couldNotOpen(String message) => PdfText(
        text: '',
        pages: 0,
        usable: false,
        why: 'This file could not be opened as a PDF ($message).',
      );
}

/// Fewer printable characters than this per page means there is no text layer
/// — a scan, or fonts with no character mapping. A real route survey page
/// carries well over a thousand.
const int _minCharsPerPage = 150;

/// A fragment within this many PDF units of another shares its line.
const double _lineTolerance = 2.5;

/// Rebuild one page's fragments into lines, on a character grid.
///
/// Not by measuring the gap between fragments, which cannot work: pdfjs emits
/// a synthetic space item for any gap at all, so a word break and a hundred
/// units of column break both arrive as a single " ". Measured that way, every
/// column in route survey 18144 collapsed to one space and the routing table
/// stopped being a table — the words were all correct and all the mileage read
/// zero.
///
/// So each fragment is placed at the column its x coordinate falls in, padding
/// with spaces to get there, which is how `pdftotext -layout` does it and what
/// indot_survey.dart was written against. The grid's cell is the median
/// character width on the page, which adapts to whatever font the state used
/// without anybody configuring it.
String layoutPage(List<TextFrag> frags) {
  final real = frags.where((f) => f.s.trim() != '').toList();
  if (real.isEmpty) return '';

  final widths = real
      .where((f) => f.s.length > 1 && f.w > 0)
      .map((f) => f.w / f.s.length)
      .toList()
    ..sort();
  final charW = widths.isNotEmpty ? widths[widths.length ~/ 2] : 5.0;
  final left = real.map((f) => f.x).reduce((a, b) => a < b ? a : b);

  // Top of the page first, then left to right. Stable, as Array.sort is, so
  // two fragments at the same spot keep the order they arrived in.
  final ordered = _stableSorted(real, (a, b) {
    final dy = b.y.compareTo(a.y);
    return dy != 0 ? dy : a.x.compareTo(b.x);
  });

  final rows = <List<TextFrag>>[];
  for (final f in ordered) {
    final row = rows.isEmpty ? null : rows.last;
    if (row != null && (row[0].y - f.y).abs() <= _lineTolerance) {
      row.add(f);
    } else {
      rows.add([f]);
    }
  }

  return rows.map((r) {
    final row = _stableSorted(r, (a, b) => a.x.compareTo(b.x));
    var line = '';
    for (final f in row) {
      final c = ((f.x - left) / charW).round();
      final col = c < 0 ? 0 : c;
      // Never go backwards: two fragments can round into the same cell, and
      // a word must not be allowed to overwrite the one before it.
      if (col > line.length) {
        line += ' ' * (col - line.length);
      } else if (line.isNotEmpty && !line.endsWith(' ')) {
        line += ' ';
      }
      line += f.s;
    }
    return line.replaceFirst(RegExp(r'\s+$'), '');
  }).join('\n');
}

/// Text from a document's pages, columns intact, with the verdict on whether
/// it is worth parsing — the same rule and the same words as the web.
PdfText readFragments(List<List<TextFrag>> pages) {
  final text = pages.map(layoutPage).join('\n');
  final printable = text.replaceAll(RegExp(r'\s'), '').length;
  if (printable < _minCharsPerPage * pages.length) {
    return PdfText(
      text: '',
      pages: pages.length,
      usable: false,
      why: 'This PDF has no readable text layer — it is probably a scan, or it uses '
          'fonts with no character mapping, which is how Indiana sent route survey '
          '18093. The pages look fine to you and carry nothing a computer can read.',
    );
  }
  return PdfText(text: text, pages: pages.length, usable: true, why: '');
}

/// A sorted copy that keeps equal elements in their original order. Dart's
/// List.sort promises no stability; JavaScript's does, and the web relies on it.
List<T> _stableSorted<T>(List<T> list, int Function(T a, T b) cmp) {
  final indexed = List.generate(list.length, (i) => i);
  indexed.sort((i, j) {
    final c = cmp(list[i], list[j]);
    return c != 0 ? c : i.compareTo(j);
  });
  return [for (final i in indexed) list[i]];
}
