import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/map_geometry.dart';
import 'package:blackgrid/domain/screenshot_filename.dart';

void main() {
  test('supplied filename structure supports synthetic signed XYZ and rounded XYZW', () {
    final sample = parseScreenshotFilename(
      '2026-01-01[00-52]_123.45, -67.89, 10.11_0, -0.38268, 0, 0.92388_12.13 (0).png',
    )!;
    expect(sample.position.x, 123.45);
    expect(sample.position.z, 10.11);
    expect(sample.position.height, -67.89);
    expect(sample.forwardX, lessThan(0));
    expect(sample.forwardZ, greaterThan(0));
    expect(sample.savedAt, DateTime(2026, 1, 1, 0, 52));
  });
  test('Unity positive Z rotates to positive X for a quarter turn', () {
    final sample = parseScreenshotFilename(
      '2026-10-07[00-52]_-1, 0, +2_0, 0.70710678, 0, 0.70710678_0.png',
    )!;
    expect(sample.position.height, 0);
    expect(sample.forwardX, closeTo(1, 1e-8));
    expect(sample.forwardZ, closeTo(0, 1e-8));
    expect(sample.bearingDegrees, closeTo(90, 1e-6));
    final geometry = MapGeometry.boundsOnly(
      bounds: GameBounds(minX: -10, maxX: 10, minZ: -10, maxZ: 10),
    );
    final from = geometry.gameToArtwork(sample.position);
    final to = geometry.gameToArtwork(
      GamePoint(
        sample.position.x + sample.forwardX,
        sample.position.z + sample.forwardZ,
      ),
    );
    expect(to.x, closeTo(from.x + 0.05, 1e-8));
    expect(to.y, closeTo(from.y, 1e-8));
    // Authored convention fixture: map X/Z rotation +90 maps +X into
    // game +Z, and projection's vertical inversion makes it screen-up.
    final rotated = MapGeometry.affine(
      bounds: GameBounds(minX: -10, maxX: 10, minZ: -10, maxZ: 10),
      a: 1,
      b: 0,
      c: 1,
      d: 0,
      rotationDegrees: 90,
    );
    final rotatedFrom = rotated.gameToArtwork(sample.position);
    final rotatedTo = rotated.gameToArtwork(
      GamePoint(
        sample.position.x + sample.forwardX,
        sample.position.z + sample.forwardZ,
      ),
    );
    expect(rotatedTo.x, closeTo(rotatedFrom.x, 1e-8));
    expect(rotatedTo.y, closeTo(rotatedFrom.y - 0.05, 1e-8));
  });
  test('metadata never invents unknown height as zero', () {
    expect(GamePoint(1, 2).height, isNull);
    expect(
      parseScreenshotFilename('2026-10-07[00-52]_1, 2_0, 0, 0, 1_0.png'),
      isNull,
    );
  });
  test('malformed nonfinite and invalid rotations reject samples', () {
    for (final tuple in ['0, 0, 0, 0', '0, 0, 0, 2', 'NaN, 0, 0, 1']) {
      expect(
        parseScreenshotFilename('2026-10-07[00-52]_1, 2, 3_${tuple}_0.png'),
        isNull,
      );
    }
    expect(
      parseScreenshotFilename(
        '2026-10-07[00-52]_Infinity, 2, 3_0, 0, 0, 1_0.png',
      ),
      isNull,
    );
    expect(parseScreenshotFilename('unrelated.png'), isNull);
    expect(
      parseScreenshotFilename(
        '2026-10-07[00-52]_${'9' * 400}, 2, 3_0, 0, 0, 1_0.png',
      ),
      isNull,
    );
    expect(
      parseScreenshotFilename('2026-13-07[00-52]_1, 2, 3_0, 0, 0, 1_0.png'),
      isNull,
    );
  });
}
