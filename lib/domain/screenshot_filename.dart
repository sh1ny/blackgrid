import 'dart:math' as math;

import 'map_coordinates.dart';

/// Saved filename metadata. It deliberately conveys no map or raid identity.
class ScreenshotFilenameSample {
  const ScreenshotFilenameSample({
    required this.position,
    required this.forwardX,
    required this.forwardZ,
    required this.savedAt,
  });
  final GamePoint position;
  final double forwardX;
  final double forwardZ;
  final DateTime savedAt;

  /// Clockwise game-world bearing from +Z; map projection owns screen bearing.
  double get bearingDegrees =>
      (math.atan2(forwardX, forwardZ) * 180 / math.pi + 360) % 360;
}

/// Unity screenshot tuples are XYZ followed by quaternion XYZW. Unity's
/// documented Transform.forward is local +Z, rotated here into game X/Z.
ScreenshotFilenameSample? parseScreenshotFilename(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  final match = _filename.firstMatch(name);
  if (match == null) return null;
  final date = DateTime.tryParse('${match[1]}T${match[2]}:${match[3]}:00');
  if (date == null ||
      date.year != int.parse(match[1]!.substring(0, 4)) ||
      date.month != int.parse(match[1]!.substring(5, 7)) ||
      date.day != int.parse(match[1]!.substring(8, 10)) ||
      date.hour != int.parse(match[2]!) ||
      date.minute != int.parse(match[3]!)) {
    return null;
  }
  if ([
        ...match[4]!.split(','),
        ...match[5]!.split(','),
      ].any((v) => !_number.hasMatch(v.trim())) ||
      double.tryParse(match[6]!)?.isFinite != true) {
    return null;
  }
  final xyz = match[4]!
      .split(',')
      .map((v) => double.tryParse(v.trim()))
      .toList();
  final quaternion = match[5]!
      .split(',')
      .map((v) => double.tryParse(v.trim()))
      .toList();
  if (xyz.length != 3 ||
      quaternion.length != 4 ||
      [...xyz, ...quaternion].any((v) => v == null || !v.isFinite)) {
    return null;
  }
  final x = quaternion[0]!;
  final y = quaternion[1]!;
  final z = quaternion[2]!;
  final w = quaternion[3]!;
  final norm = x * x + y * y + z * z + w * w;
  // Five-decimal screenshot rounding is allowed, arbitrary non-unit rotations
  // are not. Normalize only the supported rounding error.
  if (!norm.isFinite || (norm - 1).abs() > 0.0001) return null;
  final forwardX = 2 * (x * z + w * y) / norm;
  final forwardZ = 1 - 2 * (x * x + y * y) / norm;
  return ScreenshotFilenameSample(
    position: GamePoint(xyz[0]!, xyz[2]!, height: xyz[1]),
    forwardX: forwardX,
    forwardZ: forwardZ,
    savedAt: date,
  );
}

final _number = RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$');

final _filename = RegExp(
  r'^(\d{4}-\d{2}-\d{2})\[(\d{2})-(\d{2})\]_(.+)_(.+)_([+-]?(?:\d+(?:\.\d*)?|\.\d+))(?: \(\d+\))?\.(?:png|jpg|jpeg)$',
  caseSensitive: false,
);
