/// Pure geometry for inspection recognition: processing scale, scaled marker
/// template size, title region and correlation-peak suppression.
///
/// Nothing here touches native memory; the recognition job feeds it integers
/// and lists and decides what to do with the answers.
library;

import 'dart:math' as math;

/// Reference client width the processing scale is measured against.
const int _referenceWidth = 1920;

/// Reference client height the processing scale is measured against.
const int _referenceHeight = 1080;

/// Side of the stored marker template, in pixels.
const int _templateSide = 28;

/// Side of the marker footprint at the reference 1080p client, in pixels.
const int _referenceMarkerSide = 16;

/// Lower colour bound of the close-button pixel, in BGRX channel order.
const List<int> closeButtonBgrxLo = [10, 10, 50, 0];

/// Upper colour bound of the close-button pixel, in BGRX channel order.
const List<int> closeButtonBgrxHi = [15, 15, 80, 255];

/// The processing scale for a client of [clientWidth] x [clientHeight]:
/// `min(width / 1920, height / 1080)`, independent of display scaling.
double processingScale(int clientWidth, int clientHeight) =>
    math.min(clientWidth / _referenceWidth, clientHeight / _referenceHeight);

/// The side, in pixels, of the marker template scaled for [scale].
///
/// The 28 px template is scaled by `(16 / 28) * scale` and truncated, which
/// gives 16 at 1080p and 32 at 4K.
int scaledTemplateSize(double scale) =>
    (_templateSide * (_referenceMarkerSide / _templateSide) * scale).truncate();

/// An integer rectangle in frame pixels.
final class TitleRegion {
  /// Creates a region at ([x], [y]) of [width] x [height].
  const TitleRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Left edge.
  final int x;

  /// Top edge.
  final int y;

  /// Width in pixels; zero or less means empty.
  final int width;

  /// Height in pixels; zero or less means empty.
  final int height;

  /// Whether the region holds no pixels, so no probe or OCR should run.
  bool get isEmpty => width <= 0 || height <= 0;

  @override
  bool operator ==(Object other) =>
      other is TitleRegion &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'TitleRegion($x, $y, ${width}x$height)';
}

/// The title region before the close-button probe, plus where to probe.
final class TitleRegionPlan {
  /// Creates a plan; see [planTitleRegion].
  const TitleRegionPlan({
    required this.unprobed,
    required this.probeRow,
    required this.probeStartX,
    required this.scale,
  });

  /// The region clamped to the frame, before any close-button narrowing.
  final TitleRegion unprobed;

  /// The frame row to scan for the close-button pixel.
  final int probeRow;

  /// The x to start scanning from, rightwards.
  final int probeStartX;

  /// The processing scale used to derive the region.
  final double scale;

  /// Whether the caller should probe. False when [unprobed] is empty, in
  /// which case the caller must skip both probe and OCR.
  bool get needsProbe => !unprobed.isEmpty;

  /// The final region once the probe has run.
  ///
  /// [closeButtonX] is the x of the close-button pixel found, or null when
  /// none was found. The width then ends `trunc(64 * scale)` before it, and
  /// never exceeds the unprobed width: the probe only narrows.
  TitleRegion narrow(int? closeButtonX) {
    if (unprobed.isEmpty || closeButtonX == null) {
      return unprobed;
    }
    final end = closeButtonX - (64 * scale).truncate();
    return TitleRegion(
      x: unprobed.x,
      y: unprobed.y,
      width: math.min(end - unprobed.x, unprobed.width),
      height: unprobed.height,
    );
  }
}

/// Derives the unprobed title region and the probe position for a marker.
///
/// The region starts at `markerX + trunc(scaledWidth * 1.2)` and [markerY],
/// is `trunc(17 * scale)` high and `trunc(500 * scale)` wide, and is clamped
/// to the frame. It is never padded. A start at or beyond the right edge, or
/// a non-positive clamped size, gives an empty region.
TitleRegionPlan planTitleRegion({
  required int markerX,
  required int markerY,
  required int scaledWidth,
  required int scaledHeight,
  required double scale,
  required int frameWidth,
  required int frameHeight,
}) {
  final startX = markerX + (scaledWidth * 1.2).truncate();
  final width = math.min((500 * scale).truncate(), frameWidth - startX);
  final height = math.min((17 * scale).truncate(), frameHeight - markerY);
  final empty = startX >= frameWidth || width <= 0 || height <= 0;
  return TitleRegionPlan(
    unprobed: empty
        ? TitleRegion(x: startX, y: markerY, width: 0, height: 0)
        : TitleRegion(x: startX, y: markerY, width: width, height: height),
    probeRow: markerY + scaledHeight ~/ 2,
    probeStartX: startX,
    scale: scale,
  );
}

/// A correlation location at or above the threshold.
final class PeakCandidate {
  /// Creates a candidate at top-left ([x], [y]) with [score].
  const PeakCandidate({required this.x, required this.y, required this.score});

  /// Top-left x.
  final int x;

  /// Top-left y.
  final int y;

  /// Normalised correlation score.
  final double score;

  @override
  String toString() => 'PeakCandidate($x, $y, $score)';
}

/// Reduces raw correlation locations to distinct inspection markers.
///
/// [candidates] is every location at or above the threshold, so a plateau's
/// neighbours are present. The steps are:
/// 1. A candidate loses its plateau when an 8-neighbour with an equal score
///    comes earlier in raster order (y, then x).
/// 2. Survivors are visited by score descending, then y, then x ascending.
/// 3. Each accepted peak suppresses any later peak with `|dx| < templateWidth`
///    and `|dy| < templateHeight`.
///
/// At most [maxPeaks] are kept, in visit order.
List<PeakCandidate> suppressPeaks(
  List<PeakCandidate> candidates,
  int templateWidth,
  int templateHeight, {
  int maxPeaks = 8,
}) {
  final scoreAt = <(int, int), double>{
    for (final c in candidates) (c.x, c.y): c.score,
  };
  bool losesPlateau(PeakCandidate c) {
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        // Earlier in raster order: a previous row, or the left of this row.
        if (dy > 0 || (dy == 0 && dx > 0)) continue;
        if (scoreAt[(c.x + dx, c.y + dy)] == c.score) return true;
      }
    }
    return false;
  }

  final survivors = [
    for (final c in candidates)
      if (!losesPlateau(c)) c,
  ]..sort(_visitOrder);

  final kept = <PeakCandidate>[];
  for (final c in survivors) {
    if (kept.length >= maxPeaks) break;
    final suppressed = kept.any(
      (k) =>
          (c.x - k.x).abs() < templateWidth &&
          (c.y - k.y).abs() < templateHeight,
    );
    if (!suppressed) kept.add(c);
  }
  return kept;
}

int _visitOrder(PeakCandidate a, PeakCandidate b) {
  final byScore = b.score.compareTo(a.score);
  if (byScore != 0) return byScore;
  final byY = a.y.compareTo(b.y);
  return byY != 0 ? byY : a.x.compareTo(b.x);
}
