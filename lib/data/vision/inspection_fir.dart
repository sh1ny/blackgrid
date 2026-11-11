/// Per-inspection found-in-raid evidence and the bounded corner policy.
///
/// Geometry and colour admission operate on the frame's actual pixels. The
/// caller supplies the existing native correlation operation; no pixels or
/// native resources are retained in the returned reading.
library;

import 'dart:math' as math;

import '../../domain/inspection_context.dart';
import 'inspection_geometry.dart';
import 'vision_runtime.dart';

/// The observation underlying a found-in-raid value.
enum InspectionFirReason {
  /// The check template met the positive gate.
  iconFound,

  /// A readable corner met the negative admission rules.
  iconAbsent,

  /// Some required corner pixels were outside the frame.
  cornerCutOff,

  /// The corner, match or scale could not be interpreted reliably.
  cornerUnreadable,
}

/// Small, sendable found-in-raid evidence for one inspection.
final class InspectionFirReading {
  /// Creates evidence with a value derived from [reason].
  const InspectionFirReading({
    required this.reason,
    this.searchedRegion,
    this.score,
  });

  /// Why the detection yielded its value.
  final InspectionFirReason reason;

  /// The planned half-open search rectangle in frame coordinates, when known.
  final TitleRegion? searchedRegion;

  /// The finite best correlation score, when one was obtained.
  final double? score;

  /// The found-in-raid value implied by [reason].
  FirState get value => switch (reason) {
    InspectionFirReason.iconFound => FirState.yes,
    InspectionFirReason.iconAbsent => FirState.no,
    InspectionFirReason.cornerCutOff ||
    InspectionFirReason.cornerUnreadable => FirState.unknown,
  };
}

/// Plans the unclamped half-open search rectangle in frame coordinates.
///
/// Each reference offset is independently multiplied by [scale] and floored,
/// including the negative left offset. Throws [ArgumentError] unless [scale] and
/// its scaled offsets are finite and [scale] is positive.
TitleRegion planInspectionFirRegion({
  required int markerX,
  required int markerY,
  required double scale,
}) {
  // 330 is the largest reference-offset magnitude.
  final scaledBottom = 330 * scale;
  if (!scale.isFinite || scale <= 0 || !scaledBottom.isFinite) {
    throw ArgumentError.value(
      scale,
      'scale',
      'must be positive with finite scaled offsets',
    );
  }
  final left = markerX + (-8 * scale).floor();
  final top = markerY + (275 * scale).floor();
  final right = markerX + (80 * scale).floor();
  final bottom = markerY + scaledBottom.floor();
  return TitleRegion(
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
}

/// Reads one corner using BGR colour guards and the supplied NCC operation.
///
/// [frame] is the original colour image and [gray] is its grayscale image at
/// the same size. [match] receives the complete frame-space search rectangle
/// and the scaled check-template side; its result is relative to that rectangle.
/// It is not called for incomplete, unreadable, or uniformly dark corners.
/// It may return `null` when the resized template is unusable.
/// Native failures from [match] propagate to the caller unchanged.
///
/// Non-finite scale arithmetic returns unreadable evidence.
InspectionFirReading readInspectionFir({
  required VisionImage frame,
  required VisionImage gray,
  required int markerX,
  required int markerY,
  required double scale,
  required TemplateMatch? Function(TitleRegion region, int templateSide) match,
}) {
  const unreadable = InspectionFirReason.cornerUnreadable;
  if (!scale.isFinite || scale <= 0) {
    return const InspectionFirReading(reason: unreadable);
  }
  final scaledWitness = 2 * scale * scale;
  if (!scaledWitness.isFinite) {
    return const InspectionFirReading(reason: unreadable);
  }
  final region = planInspectionFirRegion(
    markerX: markerX,
    markerY: markerY,
    scale: scale,
  );
  InspectionFirReading unknown([double? score]) => InspectionFirReading(
    reason: unreadable,
    searchedRegion: region,
    score: score,
  );
  final side = (21 * scale).truncate();
  if (side < 2 ||
      side > region.width ||
      side > region.height ||
      frame.validate() != null ||
      gray.validate() != null ||
      frame.channels < 3 ||
      gray.channels != 1 ||
      frame.width != gray.width ||
      frame.height != gray.height) {
    return unknown();
  }
  if (region.x < 0 ||
      region.y < 0 ||
      region.x + region.width > frame.width ||
      region.y + region.height > frame.height) {
    return InspectionFirReading(
      reason: InspectionFirReason.cornerCutOff,
      searchedRegion: region,
    );
  }

  int px(int referenceX) => markerX + (referenceX * scale).floor();
  int py(int referenceY) => markerY + (referenceY * scale).floor();
  bool cue(int x, int y, int lo, int hi) {
    if (x < 0 || x >= frame.width || y < 0 || y >= frame.height) return false;
    final index = y * frame.stride + x * frame.channels;
    for (var channel = 0; channel < 3; channel++) {
      final value = frame.bytes[index + channel];
      if (value < lo || value > hi) return false;
    }
    return true;
  }

  for (final x in const [60, 65, 70, 75]) {
    for (final y in const [318, 319, 320]) {
      if (!cue(px(x), py(y), 0, 12)) return unknown();
    }
    for (final y in const [323, 324, 325]) {
      if (!cue(px(x), py(y), 18, 45)) return unknown();
    }
  }

  bool gold(int x, int y) {
    final index = y * frame.stride + x * frame.channels;
    final b = frame.bytes[index];
    final g = frame.bytes[index + 1];
    final r = frame.bytes[index + 2];
    return r > 110 && g > 90 && b < 0.8 * g && r > 1.4 * b;
  }

  final witnessThreshold = math.max(1, scaledWitness.floor());
  var witness = 0;
  for (var y = py(280); y < py(318) && witness < witnessThreshold; y++) {
    for (var x = px(-4); x < px(0) && witness < witnessThreshold; x++) {
      if (gold(x, y)) witness++;
    }
  }
  bool hasResidualGold() {
    final left = witness >= witnessThreshold ? px(32) : px(-4);
    for (var y = py(280); y < py(318); y++) {
      for (var x = left; x < px(75); x++) {
        if (gold(x, y)) return true;
      }
    }
    return false;
  }

  final first = gray.bytes[region.y * gray.stride + region.x];
  var uniformlyDark = first <= 12;
  for (var y = 0; y < region.height && uniformlyDark; y++) {
    final start = (region.y + y) * gray.stride + region.x;
    for (var x = 0; x < region.width; x++) {
      if (gray.bytes[start + x] != first) {
        uniformlyDark = false;
        break;
      }
    }
  }
  if (uniformlyDark) {
    if (hasResidualGold()) return unknown();
    return InspectionFirReading(
      reason: InspectionFirReason.iconAbsent,
      searchedRegion: region,
      score: 0,
    );
  }

  final result = match(region, side);
  if (result == null) return unknown();
  final score = result.score;
  if (!score.isFinite) return unknown();
  if (result.x < 0 ||
      result.y < 0 ||
      result.x + side > region.width ||
      result.y + side > region.height) {
    return unknown(score);
  }
  if (score >= 0.82) {
    return InspectionFirReading(
      reason: InspectionFirReason.iconFound,
      searchedRegion: region,
      score: score,
    );
  }
  if (score > 0.60 || hasResidualGold()) return unknown(score);
  return InspectionFirReading(
    reason: InspectionFirReason.iconAbsent,
    searchedRegion: region,
    score: score,
  );
}
