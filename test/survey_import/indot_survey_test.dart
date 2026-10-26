// Tests for the Indiana route survey reader — a port of the web's
// src/lib/indotSurvey.test.ts.
//
// These run against a real document — survey 18093, Wolfe House Movers, a
// 185' x 18'4" x 21'6" load at 704,000 lb from Mount Vernon to Terre Haute —
// because the shapes that break this parser are the ones INDOT actually
// produces, not the ones a fixture author imagines: six segments that mostly
// do not join, a road that appears in both the routing and the restriction
// list, and an arrival row whose running total disagrees with the sum of the
// steps above it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trucost_flutter/survey/import/indot_survey.dart';

void main() {
  final text = File('test/survey_import/fixtures/indot-18093.txt').readAsStringSync();
  final survey = parseIndotSurvey(text);

  test('the header', () {
    expect(survey.routeNumber, '18093');
    expect(survey.carrier, 'WOLFE HOUSE MOVERS LLC');
    expect(survey.lengthIn, 185 * 12);
    expect(survey.widthIn, 18 * 12 + 4);
    expect(survey.heightIn, 21 * 12 + 6);
    expect(survey.weightLb, 704000);
  });

  test('an unsigned form is a proposal, not a cleared route', () {
    expect(survey.certified, isFalse);
  });

  test('segments', () {
    expect(survey.segments.length, 6);
    expect(survey.segments[0].label, 'Route');
    expect(survey.segments[3].label, 'Split Trip 3');
    expect(survey.segments[0].originText, 'SR-69 3.0mi MOUNT VERNON');
    expect(survey.segments[1].originText, 'SR-69 1.1mi MOUNT VERNON',
        reason: 'segment 1 starts at a different point on the same road');
    expect(survey.segments[2].destText, 'SR-46, TERRE HAUTE');
  });

  test("the road list keeps INDOT's words and also reduces them", () {
    expect(survey.segments[1].roads[4], 'US-41 Ramp East');
    expect(survey.segments[1].roadIds, contains('US-41'),
        reason: 'a ramp is still the road it ramps onto');
    expect(survey.segments[1].roadIds, isNot(contains('US-41 RAMP EAST')));
  });

  test('mileage, the checksum we route against', () {
    expect(survey.segments.map((s) => s.miles).toList(), [5.9, 59.6, 156.5, 5.4, 1.2, 1.1]);
  });

  test('the arrival total beats summing the steps', () {
    // On this document the two agree: segment 2's steps sum to exactly 156.50.
    // That is worth asserting, because it is evidence the step column was read
    // correctly — a misread row would break the agreement.
    final summed = survey.segments[2].steps.fold<double>(0, (t, s) => t + (s.miles ?? 0));
    expect((summed - 156.5).abs(), lessThan(0.005));
    expect(survey.segments[2].miles, 156.5);
    // They will not always agree. Rounding in a long survey compounds, and
    // when it does, INDOT's own figure is the one the permit was written
    // against.
    final drift = parseIndotSurvey('==> A <==SR-1 North==> B <==\n'
        '1.11   SR-1 North   Turn right onto SR-2   1.11\n'
        '1.11   SR-2 East   Turn left onto SR-3   2.22\n'
        '1.11   SR-3 North   Arrive at destination.   3.30\n');
    expect(drift.segments[0].miles, 3.3);
  });

  test('steps', () {
    final s2 = survey.segments[2].steps;
    expect(s2[0].route, 'US-41 North');
    expect(s2[0].instruction, 'Merge onto US-41 Ramp');
    expect(s2[0].cumulative, 0.3);
    final rndabt = s2.where((s) => RegExp('roundabout', caseSensitive: false).hasMatch(s.instruction));
    expect(rndabt, isNotEmpty, reason: 'the roundabout row survives');
    expect(rndabt.first.miles, 0, reason: 'a zero-length step is a real step, not a blank row');
  });

  test('alerts', () {
    expect(survey.alerts.length, 6);
    final a496 = survey.alerts.firstWhere((a) => a.id == '496');
    expect(a496.road, 'SR-69');
    expect(a496.widthIn, 120);
    expect(a496.noPermits, isFalse);
    expect(a496.between, ['OLD SR-69', 'E 200 S']);
    expect(a496.notes, matches(RegExp('alternating lane closures', caseSensitive: false)));

    final a564 = survey.alerts.firstWhere((a) => a.id == '564');
    expect(a564.noPermits, isTrue);
    expect(a564.widthIn, isNull);

    final a2155 = survey.alerts.firstWhere((a) => a.id == '2155');
    expect(a2155.widthIn, 132);
    expect(a2155.road, 'SR-46');
  });

  test('width conflicts: the check the form never does for you', () {
    final conflicts = widthConflicts(survey);
    expect(conflicts.length, 2);
    final byId = {for (final c in conflicts) c.alert.id: c};
    expect(byId.keys, containsAll(['496', '2155']));
    expect(byId['496']!.loadWidthIn, 220);
    expect(byId['496']!.limitIn, 120);
    expect(byId['496']!.segments, containsAll([0, 1]));
    expect(byId['2155']!.segments, contains(2));
  });

  test('a load that fits raises nothing', () {
    expect(widthConflicts(survey.withWidth(96)), isEmpty);
  });

  test('alerts against the segment they sit on', () {
    final onSeg2 = alertsOnSegment(survey, 2);
    expect(onSeg2.any((a) => a.id == '2796') && onSeg2.any((a) => a.id == '265'), isTrue,
        reason: 'both US-231 closures land on segment 2');
    expect(onSeg2.every((a) => a.id != '564'), isTrue,
        reason: 'the SR-65 ban does not, because segment 2 never touches SR-65');
  });

  test('gaps: what the survey does not cover', () {
    final gaps = surveyGaps(survey);
    // Three, not five. Two of the six pairs already meet: segment 1 ends at
    // "US-41, PRINCETON" and segment 2 begins there, and segments 4 and 5 are
    // the same mile of I-70 driven east and then west.
    expect(gaps.length, 3);
    expect(gaps.any((g) => g.fromSegment == 1), isFalse);
    expect(gaps[0].fromText, 'SR-62, MOUNT VERNON');
    expect(gaps[0].toText, 'SR-69 1.1mi MOUNT VERNON');
    expect(gaps[0].candidateAlerts.any((a) => a.id == '496'), isTrue);
    expect(gaps[2].fromText, 'SR-63, TERRE HAUTE');
    expect(gaps[2].toText, 'I-70, TERRE HAUTE');
  });

  test('segments that already meet are not a gap', () {
    final joined = parseIndotSurvey('==> A <==SR-1 North==> B <==\n==> B <==SR-2 North==> C <==\n');
    expect(surveyGaps(joined), isEmpty);
    final nearly = parseIndotSurvey(
        '==> A <==SR-1 North==> b, town <==\n==> B TOWN <==SR-2 North==> C <==\n');
    expect(surveyGaps(nearly), isEmpty, reason: 'case and punctuation do not make a gap');
  });

  test('road normalisation', () {
    expect(normalizeRoad('SR-69 North'), 'SR-69');
    expect(normalizeRoad('US-41 Ramp East'), 'US-41');
    expect(normalizeRoad('I-70 West'), 'I-70');
    expect(normalizeRoad('SR 46'), 'SR-46');
    expect(normalizeRoad('S CO RD 200 W'), 'S CO RD 200 W');
  });

  test('reading inches back out', () {
    expect(feetInches(220), "18' 4\"");
    expect(feetInches(258), "21' 6\"");
  });

  test('parseInches reads the ways a size gets written', () {
    expect(parseInches("13'6\""), 162);
    expect(parseInches('13’6”'), 162);
    expect(parseInches('13-6'), 162);
    expect(parseInches('13 ft 6 in'), 162);
    expect(parseInches("185' 0\""), 2220);
    expect(parseInches('162.5'), 163);
    expect(parseInches(''), isNull);
    expect(parseInches('tall'), isNull);
  });

  test('a blank document does not throw', () {
    final empty = parseIndotSurvey('');
    expect(empty.segments, isEmpty);
    expect(empty.alerts, isEmpty);
    expect(surveyGaps(empty), isEmpty);
    expect(widthConflicts(empty), isEmpty);
  });

  // Route survey 18144 wraps two of its six `==>` blocks, because where the
  // PDF breaks the line depends on how long the road list is. Read line by
  // line those two are invisible, so four headers were found and zipped
  // against six mileage buckets from the routing table — every origin and
  // destination landed on the wrong trip, with no error and entirely
  // plausible numbers.
  test('wrapped segment lines', () {
    final wrapped = [
      'Route Survey: 18144',
      'Carrier Name: WOLFE HOUSE MOVERS LLC',
      "Length: 155' 0\"                 Width: 18' 6\"            Height: 17' 9\"",
      'Total Gross Weight: 296500 pounds',
      '==> SR-69 3.0mi MOUNT VERNON <==SR-69 North, SR-62 East==> SR-62, MOUNT VERNON <==',
      // the wrap falls mid-road-name: "US-41" / "South"
      '==> SR-69 1.1mi MOUNT VERNON <==SR-69 North, SR-66 East, US-41',
      'South==> US-41, PRINCETON <==',
      // and here between two roads: "US-231 North," / "SR-58 West"
      '==> US-41, PRINCETON <==US-41 North, US-231 North,',
      'SR-58 West, SR-46 North==> SR-46, TERRE HAUTE <==',
    ].join('\n');

    final w = parseIndotSurvey(wrapped);
    expect(w.segments.length, 3);
    expect(w.segments[1].originText, 'SR-69 1.1mi MOUNT VERNON');
    expect(w.segments[1].destText, 'US-41, PRINCETON');
    expect(w.segments[1].roads, contains('US-41 South'));
    expect(w.segments[2].roads, containsAll(['US-231 North', 'SR-58 West']));
    expect(w.segments[2].originText, 'US-41, PRINCETON');
    expect(w.lengthIn, 155 * 12);
    expect(w.weightLb, 296500);
  });

  test('a block that never closes does not eat the rest of the document', () {
    final u = parseIndotSurvey(['Carrier Name: TEST', '==> SOMEWHERE <==SR-1 North'].join('\n'));
    expect(u.carrier, 'TEST');
  });

  // Kyle spotted this by looking at the map: our Split Trip 2 ran east to
  // Bloomington where the survey said Terre Haute, 64 miles the wrong way.
  // The survey says which way on every step — "SR-46 North" — and that is the
  // only thing in the document that can tell a route from its mirror image.
  // The parser must keep it, while still reducing the road itself to SR-46.
  test('a route and its reflection: the direction word is kept', () {
    final d = parseIndotSurvey([
      'Carrier Name: TEST',
      '==> A <==SR-46 North, SR-46 West==> B <==',
      'Miles           Route              To                     Distance',
      '0.00                               Origin: A              0.00',
      '32.70           SR-46 North        Turn right onto SR-46  32.70',
      '0.10            SR-46 West         Arrive at destination. 32.80',
    ].join('\n'));

    expect(d.segments.length, 1);
    final travelled = d.segments[0].steps.where((x) => x.route != null).toList();
    expect(travelled.length, 2);
    expect(travelled[0].route, 'SR-46 North');
    expect(travelled[1].route, 'SR-46 West');
    expect(d.segments[0].roadIds[0], 'SR-46');
  });

  // Not in the web's tests: the JSON written to dot_parsed must be the web's,
  // so a survey imported on the phone reads the same on the desk. The
  // reference file is the web parser's own JSON.stringify of this fixture.
  test('toJson matches what the web writes to dot_parsed', () {
    final web = File('test/survey_import/fixtures/indot-18093.web.json').readAsStringSync();
    expect(jsonEncode(survey.toJson()), web);
  });
}
