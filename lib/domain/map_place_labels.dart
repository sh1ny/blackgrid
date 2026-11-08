/// Size and placement rules for the native map's place labels.
///
/// Pure geometry: the painter measures each label's text and passes the
/// measured size in, so no text layout or painting happens here.
library;

import 'dart:math' as math;

/// Returns the font size, in logical pixels, of a label with relative [size].
///
/// Size 80 gives 13 pixels and other sizes scale in proportion, clamped to
/// 10-16 pixels so labels keep a fixed, readable screen size at any zoom.
double placeLabelFontSize(num size) =>
    (13 * size / 80).clamp(10, 16).toDouble();

/// The screen area labels are placed in, from the origin to its far corner.
class PlaceLabelViewport {
  /// Creates a viewport of [width] by [height] logical pixels.
  const PlaceLabelViewport({required this.width, required this.height});

  /// Viewport width in logical pixels.
  final double width;

  /// Viewport height in logical pixels.
  final double height;
}

/// A measured place label ready for placement.
class PlaceLabelCandidate {
  /// Creates a candidate centred on ([x], [y]).
  const PlaceLabelCandidate({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.size,
    required this.packIndex,
    required this.floorIds,
  });

  /// Anchor x in viewport pixels; the text is centred here.
  final double x;

  /// Anchor y in viewport pixels; the text is centred here.
  final double y;

  /// Measured text width in logical pixels, before rotation.
  final double width;

  /// Measured text height in logical pixels, before rotation.
  final double height;

  /// Clockwise rotation about the anchor, in screen degrees.
  final double rotationDegrees;

  /// Relative size from the pack; larger labels win overlaps.
  final num size;

  /// Position in the pack's label list; earlier labels win ties.
  final int packIndex;

  /// Floors the pack assigns the label to.
  final Set<String> floorIds;

  /// Axis-aligned bounds of the rotated text, as left, top, right, bottom.
  (double, double, double, double) get bounds {
    final radians = rotationDegrees * math.pi / 180;
    final cos = math.cos(radians).abs();
    final sin = math.sin(radians).abs();
    final halfWidth = (width * cos + height * sin) / 2;
    final halfHeight = (width * sin + height * cos) / 2;
    return (x - halfWidth, y - halfHeight, x + halfWidth, y + halfHeight);
  }
}

/// The gap kept between placed labels, in logical pixels.
const double placeLabelMargin = 2;

/// Chooses which [candidates] to draw and returns their list indices in
/// placement order.
///
/// Labels on a floor in [selectedOverlayFloorIds] go first, then the rest;
/// within each group larger relative size first, then pack order. A label
/// whose rotated bounds miss [viewport] is dropped and takes no room. A label
/// whose bounds, grown by [placeLabelMargin], overlap a placed label are
/// skipped. The result depends only on the arguments.
List<int> placeLabels(
  List<PlaceLabelCandidate> candidates,
  PlaceLabelViewport viewport,
  Set<String> selectedOverlayFloorIds,
) {
  bool onOverlay(PlaceLabelCandidate c) =>
      c.floorIds.any(selectedOverlayFloorIds.contains);

  final order = [
    for (var i = 0; i < candidates.length; i++)
      if (_intersectsViewport(candidates[i].bounds, viewport)) i,
  ];
  order.sort((a, b) {
    final left = candidates[a];
    final right = candidates[b];
    final overlay = (onOverlay(right) ? 1 : 0) - (onOverlay(left) ? 1 : 0);
    if (overlay != 0) return overlay;
    final bySize = right.size.compareTo(left.size);
    if (bySize != 0) return bySize;
    return left.packIndex.compareTo(right.packIndex);
  });

  final placed = <int>[];
  final placedBounds = <(double, double, double, double)>[];
  for (final index in order) {
    final (left, top, right, bottom) = candidates[index].bounds;
    final collides = placedBounds.any(
      (p) =>
          left - placeLabelMargin < p.$3 &&
          right + placeLabelMargin > p.$1 &&
          top - placeLabelMargin < p.$4 &&
          bottom + placeLabelMargin > p.$2,
    );
    if (collides) continue;
    placed.add(index);
    placedBounds.add((left, top, right, bottom));
  }
  return placed;
}

bool _intersectsViewport(
  (double, double, double, double) bounds,
  PlaceLabelViewport viewport,
) {
  final (left, top, right, bottom) = bounds;
  return right > 0 &&
      bottom > 0 &&
      left < viewport.width &&
      top < viewport.height;
}
