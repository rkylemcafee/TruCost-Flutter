// lib/survey/import/indot_survey.dart
//
// Port of the web app's src/lib/indotSurvey.ts.
//
// Reading an Indiana route survey (State Form 56411).
//
// INDOT issues these as a PDF whose text layer is unusable: the glyphs are
// Type3 drawing procedures with no ToUnicode map, so every page is its own
// substitution cipher and `pdftotext` returns mojibake. The document therefore
// arrives here as OCR or as a transcription, which means the parser has to be
// forgiving about whitespace and column alignment and strict about the few
// markers INDOT actually guarantees: the `==> ... <==` segment lines, the
// `**ALERT n: ...**` blocks, and the `[Split Trip n Origin]` rows.
//
// What makes the format worth parsing at all is that it carries its own
// checksum. Every turn has a running total and every segment has a stated
// length, so a route we build from the road names can be checked against the
// survey's own mileage instead of being taken on trust.
//
// What it does NOT carry is coordinates. Nothing here invents one.

// ───────────────────────────────────────────────────────────────────── shapes

/// One of INDOT's `**ALERT**` blocks.
///
/// The location is given as a stretch of road between two cross streets, in
/// words — "SR-69 BETWEEN OLD SR-69 AND E 200 S". That is not a position, and
/// turning it into one needs geocoding the carrier has not done yet, so the
/// words are kept verbatim and the caller decides what to do with them.
class IndotAlert {
  /// INDOT's own number, kept as text because it is an identifier, not a count.
  final String id;

  /// The highway the restriction sits on, normalised: "SR-69", "US-231".
  final String road;

  /// The two cross streets bounding the restriction, as written.
  final List<String>? between;

  /// The headline restriction, as written: "10 FT WIDTH", "NO PERMITS".
  final String restriction;

  /// Width limit in inches where the restriction states one.
  final int? widthIn;

  /// True for the blanket "NO PERMITS" stretches.
  final bool noPermits;

  /// The prose beneath the headline.
  String notes;

  IndotAlert({
    required this.id,
    required this.road,
    required this.between,
    required this.restriction,
    required this.widthIn,
    required this.noPermits,
    this.notes = '',
  });

  // Key order as the web writes it: { id, notes, ...parseAlertHead() }.
  Map<String, dynamic> toJson() => {
        'id': id,
        'notes': notes,
        'road': road,
        'between': between,
        'restriction': restriction,
        'widthIn': widthIn,
        'noPermits': noPermits,
      };
}

/// One row of the routing table.
class IndotStep {
  /// The length of this step.
  final double? miles;

  /// The road this step is driven on, as written: "SR-69 North".
  final String? route;

  /// INDOT's instruction, verbatim.
  final String instruction;

  /// The running total at the end of this step.
  final double? cumulative;

  const IndotStep({
    required this.miles,
    required this.route,
    required this.instruction,
    required this.cumulative,
  });

  Map<String, dynamic> toJson() => {
        'miles': jsNumber(miles),
        'route': route,
        'instruction': instruction,
        'cumulative': jsNumber(cumulative),
      };
}

/// A stretch of road INDOT actually approved.
///
/// The survey calls the first one the route and the rest "Split Trips", but
/// they are the same thing: an origin, a destination, and the roads between
/// them.
class IndotSegment {
  /// 0 for the opening route, then 1..n for each Split Trip.
  final int index;

  /// "Route" or "Split Trip 3".
  final String label;
  final String originText;
  final String destText;

  /// The road list from the `==>` line, as written: ["SR-69 North", ...].
  final List<String> roads;

  /// Those same roads reduced to designations: ["SR-69", "SR-62"].
  final List<String> roadIds;
  final List<IndotStep> steps;

  /// The total INDOT states for this segment — the checksum to route against.
  final double? miles;

  const IndotSegment({
    required this.index,
    required this.label,
    required this.originText,
    required this.destText,
    required this.roads,
    required this.roadIds,
    required this.steps,
    required this.miles,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'label': label,
        'originText': originText,
        'destText': destText,
        'roads': roads,
        'roadIds': roadIds,
        'steps': [for (final s in steps) s.toJson()],
        'miles': jsNumber(miles),
      };
}

class IndotSurvey {
  final String? routeNumber;
  final String? carrier;
  final int? lengthIn;
  final int? widthIn;
  final int? heightIn;
  final int? weightLb;
  final List<IndotSegment> segments;
  final List<IndotAlert> alerts;

  /// Whether a person has signed the physical survey.
  ///
  /// INDOT issues the routing with the certification lines blank; the carrier
  /// fills them in after driving it. An unsigned form is a proposal, not a
  /// cleared route, and that distinction is worth carrying because the
  /// document looks identical either way.
  final bool certified;

  const IndotSurvey({
    required this.routeNumber,
    required this.carrier,
    required this.lengthIn,
    required this.widthIn,
    required this.heightIn,
    required this.weightLb,
    required this.segments,
    required this.alerts,
    required this.certified,
  });

  /// The same survey with the width replaced — what the web does with
  /// `{ ...survey, widthIn }`.
  IndotSurvey withWidth(int? widthIn) => IndotSurvey(
        routeNumber: routeNumber,
        carrier: carrier,
        lengthIn: lengthIn,
        widthIn: widthIn,
        heightIn: heightIn,
        weightLb: weightLb,
        segments: segments,
        alerts: alerts,
        certified: certified,
      );

  /// The shape the web writes into route_surveys.dot_parsed (before it adds
  /// `trips`), key for key.
  Map<String, dynamic> toJson() => {
        'routeNumber': routeNumber,
        'carrier': carrier,
        'lengthIn': lengthIn,
        'widthIn': widthIn,
        'heightIn': heightIn,
        'weightLb': weightLb,
        'segments': [for (final s in segments) s.toJson()],
        'alerts': [for (final a in alerts) a.toJson()],
        'certified': certified,
      };
}

/// A number as JavaScript's JSON.stringify would write it.
///
/// JavaScript has one number type, so 5.9 + 0.0 is written `5.9` and 3.0 is
/// written `3`. Dart writes the double 3.0 as `3.0`; turning a whole double
/// back into an int keeps dot_parsed byte-for-byte what the web would store.
num? jsNumber(num? n) {
  if (n == null) return null;
  if (n is double && n.isFinite && n == n.truncateToDouble()) return n.toInt();
  return n;
}

// ──────────────────────────────────────────────── inches (from surveyImport.ts)

/// Inches from the ways a height or width gets written: 13'6", 13’6”, 13-6,
/// "13 ft 6 in", or a plain number of inches.
int? parseInches(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  // 13'6" / 13’6” / 13-6 / 13 ft 6 in
  final ftIn = RegExp(
    r'''^(\d+)\s*(?:'|’|ft\.?|feet|-)\s*(\d{1,2})?\s*(?:"|”|in\.?|inches)?$''',
    caseSensitive: false,
  ).firstMatch(s);
  if (ftIn != null) {
    return int.parse(ftIn.group(1)!) * 12 + int.parse(ftIn.group(2) ?? '0');
  }
  final plain = RegExp(r'''^(\d+(?:\.\d+)?)\s*(in\.?|inches|")?$''', caseSensitive: false)
      .firstMatch(s);
  if (plain != null) return _jsRound(double.parse(plain.group(1)!));
  return null;
}

/// Math.round: halves go up, toward positive infinity.
int _jsRound(double v) => (v + 0.5).floor();

// ───────────────────────────────────────────────────────────────── road names

/// Reduce "US-41 Ramp East" to "US-41".
///
/// Direction and ramp are properties of the step, not of the road, and a
/// restriction filed against US-41 applies whether the survey calls it
/// "US-41 North" or "US-41 Ramp North".
String normalizeRoad(String name) {
  final m = RegExp(r'^(I|SR|US|IN|CR)\s*-?\s*(\d+)').firstMatch(name.trim().toUpperCase());
  return m != null ? '${m.group(1)}-${m.group(2)}' : name.trim().toUpperCase();
}

// ─────────────────────────────────────────────────────────────────── alerts

// "**ALERT 496: SR-69 BETWEEN OLD SR-69 AND E 200 S, 10 FT WIDTH"
final _alertHead = RegExp(r'^\*\*\s*ALERT\s+(\d+)\s*:\s*(.+)$', caseSensitive: false);

/// Split an alert headline into road, stretch and restriction.
///
/// The restriction is whatever follows the last comma, because the
/// cross-street names themselves can contain commas-free but comma-adjacent
/// text and the restriction is always last.
IndotAlert _parseAlertHead(String id, String rest) {
  final lastComma = rest.lastIndexOf(',');
  final where = lastComma >= 0 ? rest.substring(0, lastComma).trim() : rest.trim();
  final restriction = lastComma >= 0 ? rest.substring(lastComma + 1).trim() : '';

  var road = where;
  List<String>? between;
  final btw = RegExp(r'^(.+?)\s+BETWEEN\s+(.+?)\s+AND\s+(.+)$', caseSensitive: false)
      .firstMatch(where);
  if (btw != null) {
    road = btw.group(1)!.trim();
    between = [btw.group(2)!.trim(), btw.group(3)!.trim()];
  }

  // "10 FT WIDTH" → 120 inches. A bare number with no FT is not a width.
  final w = RegExp(
    r'''(\d+(?:\.\d+)?)\s*(?:FT|FEET|')\s*(?:\d+\s*(?:IN|")?)?\s*WIDTH''',
    caseSensitive: false,
  ).firstMatch(restriction);
  final widthIn = w != null ? _jsRound(double.parse(w.group(1)!) * 12) : null;

  return IndotAlert(
    id: id,
    notes: '',
    road: normalizeRoad(road),
    between: between,
    restriction: restriction,
    widthIn: widthIn,
    noPermits: RegExp(r'NO\s+PERMITS', caseSensitive: false).hasMatch(restriction),
  );
}

// ───────────────────────────────────────────────────────────── table rows

// "3.20    SR-69 North   Turn right onto SR-62   3.20"
// Columns are separated by runs of whitespace, but an instruction contains
// single spaces, so the split has to be on two-or-more.
final _splitCol = RegExp(r'\s{2,}|\t+');

final _splitMark =
    RegExp(r'^\[\s*Split\s+Trip\s+(\d+)\s+(Origin|Destination)\s*\]$', caseSensitive: false);

double? _numberOrNull(String? s) {
  if (s == null || s.isEmpty) return null;
  final t = s.trim();
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) return null;
  return double.parse(t);
}

/// Read one routing-table row.
///
/// Returns null for anything that is not a step — headings, the column header,
/// the split markers, the certification paragraph.
IndotStep? _parseRow(String line) {
  final cols = line.split(_splitCol).map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
  if (cols.length < 2) return null;

  final miles = _numberOrNull(cols[0]);
  if (miles == null) return null; // not a step row

  // Three shapes occur: [miles, route, to, distance], [miles, to, distance]
  // (no road named, as on the Origin and Destination rows), and a trailing
  // distance that is sometimes absent.
  final last = cols[cols.length - 1];
  final cumulative = cols.length >= 3 ? _numberOrNull(last) : null;
  final body = cumulative == null ? cols.sublist(1) : cols.sublist(1, cols.length - 1);

  if (body.isEmpty) return null;
  if (body.length == 1) {
    return IndotStep(miles: miles, route: null, instruction: body[0], cumulative: cumulative);
  }
  return IndotStep(
    miles: miles,
    route: body[0],
    instruction: body.sublist(1).join(' '),
    cumulative: cumulative,
  );
}

// ───────────────────────────────────────────────────────────────── the parser

// "==> SR-69 3.0mi MOUNT VERNON <==SR-69 North, SR-62 East==> SR-62, MOUNT VERNON <=="
final _segmentLine = RegExp(r'==>\s*(.+?)\s*<==\s*(.*?)\s*==>\s*(.+?)\s*<==');

/// Put each `==> origin <== roads ==> destination <==` block back on one line.
///
/// The block is one logical line that the PDF wraps wherever the column runs
/// out, and where it wraps depends on how long the road list is:
///
///     ==> SR-69 1.1mi MOUNT VERNON <==SR-69 North, ... US-41
///     South==> US-41, PRINCETON <==
///
/// Read line by line, that is not a segment at all. On route survey 18144 two
/// of six wrapped, so four headers were found and then zipped against six
/// mileage buckets from the routing table — which silently shifted every
/// origin and destination onto the wrong trip. Nothing looked broken; the
/// numbers were all real, just attached to the wrong places.
///
/// Joined with a space, because the wrap falls between words ("US-41" +
/// "South", "US-231 North," + "SR-58 West").
List<String> _unwrapSegments(List<String> lines) {
  final out = <String>[];
  final closed = RegExp(r'<==\s*$');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    // An unfinished block: it opened with ==> but has not closed with <==.
    while (line.contains('==>') && !closed.hasMatch(line) && i + 1 < lines.length) {
      line = '${line.replaceFirst(RegExp(r'\s*$'), '')} ${lines[++i].trim()}';
    }
    out.add(line);
  }
  return out;
}

class _SegmentLine {
  final String originText;
  final List<String> roads;
  final String destText;
  _SegmentLine(this.originText, this.roads, this.destText);
}

IndotSurvey parseIndotSurvey(String text) {
  final lines = _unwrapSegments(text.split(RegExp(r'\r?\n')));

  String? routeNumber;
  String? carrier;
  int? lengthIn;
  int? widthIn;
  int? heightIn;
  int? weightLb;

  final alerts = <IndotAlert>[];
  final segmentLines = <_SegmentLine>[];

  // Steps are gathered into buckets as the split markers go past. Bucket 0 is
  // the opening route; a "[Split Trip n Origin]" opens bucket n.
  final buckets = <List<IndotStep>>[[]];
  var bucket = 0;

  IndotAlert? pendingAlert;
  final alertNotes = <String>[];

  void closeAlert() {
    final a = pendingAlert;
    if (a == null) return;
    a.notes = alertNotes.join(' ').replaceFirst(RegExp(r'\*+$'), '').trim();
    alerts.add(a);
    pendingAlert = null;
    alertNotes.clear();
  }

  final closesAlert = RegExp(r'\*\*\s*$');

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    // An alert body runs until the closing `**`, so it is collected first and
    // everything else on those lines is ignored.
    if (pendingAlert != null) {
      alertNotes.add(line);
      if (closesAlert.hasMatch(line)) closeAlert();
      continue;
    }

    final alert = _alertHead.firstMatch(line);
    if (alert != null) {
      pendingAlert = _parseAlertHead(alert.group(1)!, alert.group(2)!.replaceFirst(RegExp(r'\*+$'), ''));
      // A one-line alert closes on its own line.
      if (closesAlert.hasMatch(line)) closeAlert();
      continue;
    }

    final seg = _segmentLine.firstMatch(line);
    if (seg != null) {
      segmentLines.add(_SegmentLine(
        seg.group(1)!.trim(),
        seg.group(2)!.split(',').map((r) => r.trim()).where((r) => r.isNotEmpty).toList(),
        seg.group(3)!.trim(),
      ));
      continue;
    }

    final split = _splitMark.firstMatch(line);
    if (split != null) {
      if (RegExp('origin', caseSensitive: false).hasMatch(split.group(2)!)) {
        bucket = int.parse(split.group(1)!);
        while (buckets.length <= bucket) {
          buckets.add([]);
        }
      }
      continue;
    }

    if (routeNumber == null) {
      final n = RegExp(r'Route\s+Survey\s*:\s*(\S+)', caseSensitive: false).firstMatch(line);
      if (n != null) {
        routeNumber = n.group(1);
        continue;
      }
    }
    if (carrier == null) {
      final c = RegExp(r'Carrier\s+Name\s*:\s*(.+)$', caseSensitive: false).firstMatch(line);
      if (c != null) {
        carrier = c.group(1)!.trim();
        continue;
      }
    }

    // Dimensions share one line: Length: 185' 0"  Width: 18' 4"  Height: 21' 6"
    final dim = RegExp(
      r'Length\s*:\s*(.+?)\s{2,}Width\s*:\s*(.+?)\s{2,}Height\s*:\s*(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(line);
    if (dim != null) {
      lengthIn = parseInches(dim.group(1));
      widthIn = parseInches(dim.group(2));
      heightIn = parseInches(dim.group(3));
      continue;
    }

    final wt = RegExp(r'Total\s+Gross\s+Weight\s*:\s*([\d,]+)', caseSensitive: false).firstMatch(line);
    if (wt != null) {
      weightLb = int.parse(wt.group(1)!.replaceAll(',', ''));
      continue;
    }

    final row = _parseRow(line);
    if (row != null) buckets[bucket].add(row);
  }
  closeAlert();

  // The certification lines are issued blank and filled in by hand. A row of
  // underscores is still blank; so is a label with nothing after it. This has
  // to be judged line by line — anchoring to the end of the string instead of
  // the end of the line finds the rest of the document and calls it a
  // signature.
  final certLine = RegExp(r'Has been physically surveyed on\s*:(.*)$', caseSensitive: false);
  final certified = lines.any((l) {
    final m = certLine.firstMatch(l);
    if (m == null) return false;
    return m.group(1)!.replaceAll(RegExp(r'[_\s]'), '').isNotEmpty;
  });

  final segments = <IndotSegment>[];
  for (var i = 0; i < segmentLines.length; i++) {
    final s = segmentLines[i];
    final steps = i < buckets.length ? buckets[i] : <IndotStep>[];
    segments.add(IndotSegment(
      index: i,
      label: i == 0 ? 'Route' : 'Split Trip $i',
      originText: s.originText,
      destText: s.destText,
      roads: s.roads,
      roadIds: s.roads.map(normalizeRoad).toSet().toList(),
      steps: steps,
      miles: _segmentMiles(steps),
    ));
  }

  return IndotSurvey(
    routeNumber: routeNumber,
    carrier: carrier,
    lengthIn: lengthIn,
    widthIn: widthIn,
    heightIn: heightIn,
    weightLb: weightLb,
    segments: segments,
    alerts: alerts,
    certified: certified,
  );
}

/// The segment's stated length.
///
/// The running total on the "Arrive at destination." row is INDOT's own figure
/// and is preferred over summing the steps, because the sum compounds the
/// rounding in every row. Where no arrival row carries a total, the sum is the
/// best available answer.
double? _segmentMiles(List<IndotStep> steps) {
  final arrive = RegExp('arrive at destination', caseSensitive: false);
  for (var i = steps.length - 1; i >= 0; i--) {
    if (arrive.hasMatch(steps[i].instruction) && steps[i].cumulative != null) {
      return steps[i].cumulative;
    }
  }
  final given = [for (final s in steps) if (s.cumulative != null) s.cumulative!];
  if (given.isNotEmpty) return given.reduce((a, b) => a > b ? a : b);
  final sum = steps.fold<double>(0, (t, s) => t + (s.miles ?? 0));
  return sum > 0 ? sum : null;
}

// ─────────────────────────────────────────────────────────────────────── gaps

/// A stretch the survey does not cover.
///
/// INDOT approves state highways. Where two segments do not meet, the ground
/// between them is something else — a city street outside INDOT's
/// jurisdiction, or a stretch closed for construction that the planner expects
/// to reopen. The survey does not say which, and neither does this.
///
/// Filling a gap is the carrier's own work, so a filled stretch is never drawn
/// as part of the approved route: it is the carrier's proposal, shown in its
/// own colour, and it is what still has to be checked before the load moves.
class SurveyGap {
  /// Index of the segment the route arrives on.
  final int fromSegment;

  /// Index of the segment it has to resume on.
  final int toSegment;

  /// Where the survey leaves off, as INDOT words it.
  final String fromText;

  /// Where it picks up again.
  final String toText;

  /// Alerts on roads either side of the gap.
  ///
  /// These are candidates, not causes. A construction alert next to a gap is
  /// suggestive and worth a phone call; it is not proof, and calling it proof
  /// would put a reason on the page that nobody at INDOT ever gave.
  final List<IndotAlert> candidateAlerts;

  const SurveyGap({
    required this.fromSegment,
    required this.toSegment,
    required this.fromText,
    required this.toText,
    required this.candidateAlerts,
  });
}

List<SurveyGap> surveyGaps(IndotSurvey survey) {
  final gaps = <SurveyGap>[];

  for (var i = 0; i < survey.segments.length - 1; i++) {
    final from = survey.segments[i];
    final to = survey.segments[i + 1];

    // Same place in the same words: the segments already meet.
    if (_sameplace(from.destText, to.originText)) continue;

    final touched = <String>{
      if (from.roadIds.isNotEmpty) from.roadIds.last, // the road it arrives on
      if (to.roadIds.isNotEmpty) to.roadIds.first, // the road it leaves on
    };

    gaps.add(SurveyGap(
      fromSegment: from.index,
      toSegment: to.index,
      fromText: from.destText,
      toText: to.originText,
      candidateAlerts: survey.alerts.where((a) => touched.contains(a.road)).toList(),
    ));
  }

  return gaps;
}

/// INDOT writes the same spot the same way, give or take case and punctuation.
bool _sameplace(String a, String b) {
  String norm(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return norm(a) == norm(b);
}

// ────────────────────────────────────────────────────────────── width check

/// An alert whose width limit the load does not fit through.
///
/// This is the cheapest check in the document and the most expensive one to
/// miss: the load's width is on page 1, the limits are on page 2, and nothing
/// in the form puts them side by side.
class WidthConflict {
  final IndotAlert alert;

  /// Segments whose road list includes the restricted road.
  final List<int> segments;
  final int loadWidthIn;
  final int limitIn;

  const WidthConflict({
    required this.alert,
    required this.segments,
    required this.loadWidthIn,
    required this.limitIn,
  });
}

List<WidthConflict> widthConflicts(IndotSurvey survey) {
  final load = survey.widthIn;
  if (load == null) return [];

  final out = <WidthConflict>[];
  for (final alert in survey.alerts) {
    final limit = alert.widthIn;
    if (limit == null || load <= limit) continue;
    final segments = survey.segments
        .where((s) => s.roadIds.contains(alert.road))
        .map((s) => s.index)
        .toList();
    out.add(WidthConflict(alert: alert, segments: segments, loadWidthIn: load, limitIn: limit));
  }
  return out;
}

/// Alerts flagged against a road the segment is routed on.
///
/// INDOT routes a load onto a highway and separately lists restrictions on
/// that same highway, leaving the reader to work out whether the two overlap.
/// They usually do not — the restricted stretch is elsewhere on the road — but
/// "usually" is not a basis for moving 704,000 pounds, so every one of these
/// gets surfaced and resolved against the map rather than assumed away.
List<IndotAlert> alertsOnSegment(IndotSurvey survey, int index) {
  IndotSegment? seg;
  for (final s in survey.segments) {
    if (s.index == index) {
      seg = s;
      break;
    }
  }
  if (seg == null) return [];
  final ids = seg.roadIds;
  return survey.alerts.where((a) => ids.contains(a.road)).toList();
}

/// Inches as feet and inches, for anything a person reads.
String feetInches(int inches) => "${(inches / 12).floor()}' ${inches % 12}\"";
