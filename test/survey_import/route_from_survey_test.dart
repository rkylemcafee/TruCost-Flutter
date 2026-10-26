// A port of the web's src/lib/routeFromSurvey.test.ts, plus the one-way and
// single-road cases drawTrip handles.
//
// A crossroads with nothing on it but two straight roads, which is enough to
// catch the mistake that mileage alone cannot see: a road runs both ways from
// a junction, so the stated distance fits a point on either side of it.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trucost_flutter/survey/import/route_from_survey.dart';

/// Degrees of latitude per mile, near enough for a test fixture.
const mi = 1 / 69;
const cross = <double>[38.0, -87.5];

/// Longitude shrinks with latitude; at 38 degrees a mile is about 1/54.4 deg.
final miLng = 1 / (69 * math.cos(38 * math.pi / 180));

List<LL> _ns() => [
      for (var m = -10.0; m <= 10; m += 0.25) [cross[0] + m * mi, cross[1]],
    ];
List<LL> _ew() => [
      for (var m = -10.0; m <= 10; m += 0.25) [cross[0], cross[1] + m * miLng],
    ];

/// A north-south road and an east-west one, crossing at CROSS.
RoadNet crossroads({Dir nsDir = 0}) {
  final net = RoadNet();
  net.add(Way(ref: 'SR-69', geom: _ns(), dir: nsDir));
  net.add(Way(ref: 'SR-62', geom: _ew()));
  return net;
}

bool south(LL p) => p[0] < cross[0];
bool east(LL p) => p[1] > cross[1];

void main() {
  // "3.20 SR-69 North, turn right onto SR-62" means the load came UP to the
  // junction, so the origin is three miles SOUTH of it. Three miles north
  // fits the distance exactly as well, and for 18144 that is where it landed:
  // the survey opened 4.74 miles from the real start with both step mileages
  // correct to the inch, because nothing checked the direction word.
  test('the origin sits on the side you drove FROM', () {
    final g = tripGeometry(crossroads(), ['SR-69', 'SR-62'], [3.2, 2.7], 5.9, ['North', 'East']);
    expect(g.shape, isNotEmpty, reason: g.why);
    final o = g.shape.first;
    expect(south(o), isTrue, reason: 'driving north, the origin is south of the junction');
    expect(((o[0] - cross[0]).abs() / mi - 3.2).abs(), lessThan(0.3));
    expect(east(g.shape.last), isTrue, reason: 'the far end is east, as the second step says');
    expect((g.miles - 5.9).abs(), lessThan(0.3));
    expect(g.statedMiles, 5.9);
    expect(g.steps.map((s) => s.road), ['SR-69', 'SR-62']);
    expect(g.steps.first.endsAt, isNotNull);
    expect(miles(g.steps.first.endsAt!, cross), lessThan(0.01),
        reason: 'the first step ends at the turn');
  });

  test('and reverses cleanly when the survey does', () {
    final g = tripGeometry(crossroads(), ['SR-69', 'SR-62'], [3.2, 2.7], 5.9, ['South', 'West']);
    expect(south(g.shape.first), isFalse, reason: 'driving south, the origin is north');
    expect(east(g.shape.last), isFalse, reason: 'and the far end is west');

    // The property that cannot pass by luck: on a symmetric crossroads the two
    // directions must land on opposite sides. Ignore the direction word and
    // both reduce to the same distance search, so both get the same answer.
    final north =
        tripGeometry(crossroads(), ['SR-69', 'SR-62'], [3.2, 2.7], 5.9, ['North', 'East']);
    expect(south(north.shape.first) != south(g.shape.first), isTrue);
    expect(east(north.shape.last) != east(g.shape.last), isTrue);
  });

  // Older surveys and hand-typed trips carry no direction. The reconstruction
  // must still produce something rather than refuse.
  test('with no direction word, mileage still decides', () {
    final g = tripGeometry(crossroads(), ['SR-69', 'SR-62'], [3.2, 2.7], 5.9);
    expect(g.shape, isNotEmpty, reason: g.why);
    expect((g.miles - 5.9).abs(), lessThan(0.3));
  });

  test('repeated roads merge into one run, not a turn onto themselves', () {
    final g = tripGeometry(
        crossroads(), ['SR-69', 'SR-69', 'SR-62'], [2.0, 1.2, 2.7], 5.9, ['North', 'North', 'East']);
    expect(g.steps.length, 2);
    expect(g.steps.first.statedMiles, closeTo(3.2, 1e-9));
    expect(south(g.shape.first), isTrue);
  });

  test('roads missing from the map say so', () {
    final g = tripGeometry(crossroads(), ['SR-69', 'US-41'], [3.2, 2.7], 5.9);
    expect(g.shape, isEmpty);
    expect(g.why, 'US-41 is not in the map data');
    expect(tripGeometry(crossroads(), [], [], 0).why, 'the trip lists no roads');
  });

  // A one-way road listed south to north may only be driven north. The
  // direction word on a turn list is a penalty, not a veto, so a two-road trip
  // still draws obeying the arrows; a one-road trip asked to run south has
  // nowhere to go, and drawTrip draws it anyway and says so rather than
  // leaving the trip blank.
  test('drawTrip obeys one-way roads, and flags the line when it cannot', () {
    final ok = drawTrip(crossroads(nsDir: 1), ['SR-69', 'SR-62'], [3.2, 2.7], ['North', 'East'], 5.9, null);
    expect(ok.shape, isNotEmpty, reason: ok.why);
    expect(ok.wrongWay, isFalse);
    expect(south(ok.shape.first), isTrue);

    final north = drawTrip(crossroads(nsDir: 1), ['SR-69'], [0.8], ['North'], 0.8, cross);
    expect(north.shape, isNotEmpty, reason: north.why);
    expect(north.wrongWay, isFalse);

    final against = drawTrip(crossroads(nsDir: 1), ['SR-69'], [0.8], ['South'], 0.8, cross);
    expect(against.shape, isNotEmpty, reason: against.why);
    expect(against.wrongWay, isTrue);
    expect(south(against.shape.last), isTrue);
  });

  // Splits 4 and 5 of 18144 are each 0.80 miles of I-70 with no turn: they
  // hang off where the last trip ended and run the way the survey names.
  test('a single-road trip runs from its anchor in the named direction', () {
    final net = crossroads();
    final g = drawTrip(net, ['SR-62'], [0.8], ['East'], 0.8, cross);
    expect(g.shape, isNotEmpty, reason: g.why);
    expect(east(g.shape.last), isTrue);
    expect((g.miles - 0.8).abs(), lessThan(0.3));

    final w = drawTrip(net, ['SR-62'], [0.8], ['West'], 0.8, cross);
    expect(east(w.shape.last), isFalse);

    final lost = drawTrip(net, ['SR-62'], [0.8], ['East'], 0.8, null);
    expect(lost.shape, isEmpty);
    expect(lost.why, 'SR-62 has no turn and nothing to anchor it to');
  });

  // Grade-separated roads share no vertex; a ramp joins them. Filed under the
  // ramp's own name it gets the walk across, and the turn is where it lands.
  test('roads that share no vertex meet across a ramp', () {
    final net = RoadNet();
    net.add(Way(ref: 'SR-69', geom: _ns()));
    // East-west road shifted a tenth of a mile north: it never touches SR-69.
    final off = 0.1 * mi;
    net.add(Way(ref: 'SR-62', geom: [for (final p in _ew()) [p[0] + off, p[1]]]));
    net.add(Way(ref: rampRef('SR-62'), geom: [
      [cross[0], cross[1]],
      [cross[0] + off / 2, cross[1] + 0.05 * miLng],
      [cross[0] + off, cross[1] + 0.25 * miLng],
    ]));
    final j = net.junctions('SR-69', 'SR-62');
    expect(j, isNotEmpty);
    expect(j.first.$1 != j.first.$2, isTrue, reason: 'the two ends of the ramp');
    final g = tripGeometry(net, ['SR-69', 'SR-62'], [3.2, 2.7], 5.9, ['North', 'East']);
    expect(g.shape, isNotEmpty, reason: g.why);
    expect(south(g.shape.first), isTrue);
  });

  // A survey splits without saying why. Closing that by merging the pieces
  // drew a continuous line over a question nobody had answered: the load
  // still has to get across, and the road it crosses on was not part of what
  // the state approved. Now the gap is reported and somebody has to go and
  // ask.
  group('the places the survey does not join up', () {
    test('a real gap is reported', () {
      final a = <LL>[[38.0, -87.5], [38.1, -87.5]];
      final b = <LL>[[38.3, -87.5], [38.4, -87.5]];
      final gaps = routeGaps([a, b]);
      expect(gaps.length, 1);
      expect(gaps[0].after, 0);
      expect((gaps[0].miles - 13.8).abs(), lessThan(1));
      expect(gaps[0].from[0], 38.1);
      expect(gaps[0].to[0], 38.3);
    });

    test('pieces that meet are not a gap', () {
      // Even when the road graph stopped on a slightly different vertex.
      final a = <LL>[[38.0, -87.5], [38.1, -87.5]];
      final b = <LL>[[38.1002, -87.5], [38.2, -87.5]];
      expect(routeGaps([a, b]), isEmpty);
    });

    test('an undrawn piece is skipped, not counted as a gap', () {
      final a = <LL>[[38.0, -87.5], [38.1, -87.5]];
      final c = <LL>[[38.3, -87.5], [38.4, -87.5]];
      final gaps = routeGaps([a, [], c]);
      expect(gaps.length, 1);
      expect(gaps[0].after, 0, reason: 'numbered against the piece that IS drawn');
    });

    test('one piece, or none, has no gaps', () {
      expect(routeGaps([
        [[38.0, -87.5], [38.1, -87.5]],
      ]), isEmpty);
      expect(routeGaps([]), isEmpty);
      expect(joinedMiles, 0.05);
    });
  });
}
