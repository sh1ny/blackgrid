import 'package:blackgrid/domain/map_place_labels.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewport = PlaceLabelViewport(width: 800, height: 600);

PlaceLabelCandidate _label({
  required int packIndex,
  double x = 400,
  double y = 300,
  double width = 100,
  double height = 20,
  double rotation = 0,
  double size = 80,
  Set<String> floorIds = const {'base'},
}) => PlaceLabelCandidate(
  x: x,
  y: y,
  width: width,
  height: height,
  rotationDegrees: rotation,
  size: size,
  packIndex: packIndex,
  floorIds: floorIds,
);

void main() {
  group('placeLabelFontSize', () {
    test('font size follows relative size 65, 80, 100', () {
      expect(placeLabelFontSize(65), closeTo(10.5625, 1e-9));
      expect(placeLabelFontSize(80), 13);
      // 100 gives 16.25, which the clamp brings to 16.
      expect(placeLabelFontSize(100), 16);
    });

    test('font size is clamped to 10..16', () {
      expect(placeLabelFontSize(1), 10);
      expect(placeLabelFontSize(61), 10);
      expect(placeLabelFontSize(500), 16);
    });
  });

  group('placeLabels', () {
    test('larger overlapping label wins', () {
      final placed = placeLabels(
        [
          _label(packIndex: 0, size: 65),
          _label(packIndex: 1, size: 100, x: 430),
        ],
        _viewport,
        const {},
      );
      expect(placed, [1]);
    });

    test('separated labels are both placed', () {
      final placed = placeLabels(
        [
          _label(packIndex: 0, size: 65),
          _label(packIndex: 1, size: 100, x: 600),
        ],
        _viewport,
        const {},
      );
      expect(placed, unorderedEquals([0, 1]));
    });

    test('labels closer than the 2 px margin collide, at 2 px they do not', () {
      // Widths 100: centres 101 apart leave a 1 px gap, so they collide.
      expect(
        placeLabels(
          [_label(packIndex: 0), _label(packIndex: 1, x: 501)],
          _viewport,
          const {},
        ),
        [0],
      );
      // Centres 103 apart leave a 3 px gap, so both are placed.
      expect(
        placeLabels(
          [_label(packIndex: 0), _label(packIndex: 1, x: 503)],
          _viewport,
          const {},
        ),
        unorderedEquals([0, 1]),
      );
    });

    test('equal sizes: earlier pack index wins', () {
      final placed = placeLabels(
        [_label(packIndex: 5, x: 410), _label(packIndex: 2)],
        _viewport,
        const {},
      );
      expect(placed, [1]);
    });

    test('selected overlay label wins over a base label of equal size', () {
      final placed = placeLabels(
        [
          _label(packIndex: 0, floorIds: const {'base'}),
          _label(packIndex: 1, floorIds: const {'second'}),
        ],
        _viewport,
        const {'second'},
      );
      expect(placed, [1]);
    });

    test('label outside the viewport takes no room', () {
      final placed = placeLabels(
        [
          _label(packIndex: 0, x: -40, width: 200, size: 100),
          _label(packIndex: 1, x: 40, width: 100, size: 65),
        ],
        _viewport,
        const {},
      );
      // The large label spans x -140..60 and is visible; move it fully out.
      expect(placed, [0]);
      final offscreen = placeLabels(
        [
          _label(packIndex: 0, x: -300, width: 400, size: 100),
          _label(packIndex: 1, x: 40, width: 100, size: 65),
        ],
        _viewport,
        const {},
      );
      expect(offscreen, [1]);
    });

    test('rotated bounds decide the cull and the overlap', () {
      // A 200 x 10 label rotated 90 degrees is 10 wide and 200 tall.
      final rotated = _label(
        packIndex: 0,
        x: 400,
        y: 300,
        width: 200,
        height: 10,
        rotation: 90,
      );
      final beside = _label(packIndex: 1, x: 400, y: 405, width: 40);
      // Unrotated, the first label ends at y 305; rotated it reaches y 400.
      expect(placeLabels([rotated, beside], _viewport, const {}), [0]);
    });
  });
}
