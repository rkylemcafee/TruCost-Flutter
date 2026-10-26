// The trailer outline's whole job is answering "does it fit", so its size on
// the ground is checked here against the same haversine the app measures with.

import 'package:flutter_test/flutter_test.dart';
import 'package:trucost_flutter/survey/map_image.dart';

void main() {
  test('a 90 x 8.5 ft deck has 90 x 8.5 ft sides, at any bearing', () {
    for (final deg in [0.0, 37.0, 90.0, 213.5]) {
      final c = trailerCorners(TrailerPlacement(38.0, -87.5, deg), 90, 8.5);
      final front = haversineMiles(c[0], c[1]) * 5280;
      final side = haversineMiles(c[1], c[2]) * 5280;
      expect(front, closeTo(8.5, 0.01), reason: 'width at $deg°');
      expect(side, closeTo(90, 0.05), reason: 'length at $deg°');
    }
  });

  test('polyline encoding matches Google\'s documented example', () {
    expect(
      encodePolyline([
        [38.5, -120.2],
        [40.7, -120.95],
        [43.252, -126.453],
      ]),
      '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
    );
  });

  test('the trailer replaces only itself among a turn\'s marks', () {
    final before = [
      {'t': 'icon', 'kind': 'bridge', 'x': 0.2, 'y': 0.3},
      {'t': 'trailer', 'lat': 1.0, 'lng': 2.0, 'deg': 0},
    ];
    final after = TrailerPlacement.intoAnnotations(before, const TrailerPlacement(3, 4, 45));
    expect(after.length, 2);
    expect(after.first['t'], 'icon');
    expect(TrailerPlacement.fromAnnotations(after)!.deg, 45);
    expect(TrailerPlacement.intoAnnotations(after, null).length, 1);
  });
}
