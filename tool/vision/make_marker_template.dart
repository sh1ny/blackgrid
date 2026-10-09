// Generates the inspection marker template (change
// add-inspection-recognition-pipeline, design D4).
//
// Reads a user-supplied PNG of the game client area and the marker's top-left
// pixel, converts it to grayscale with the runtime's BGR luma weights, crops
// the square footprint of side trunc(16 * s) (s = min(W / 1920, H / 1080)) and
// resizes it to 28x28. It writes
//   <out>/inspection_marker.gray  raw 8-bit grayscale, row-major, no codec
//   <out>/inspection_marker.json  format, size, source size, scale, origin,
//                                 source screenshot SHA-256, recipe
//
// The tool never captures the screen. Output is deterministic: equal inputs
// give byte-identical files. Nothing is written when an input is rejected.
//
// Usage: dart run tool/vision/make_marker_template.dart <client-screenshot.png>
//          --origin x,y [--out assets/vision/marker]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/application/output_path_guard.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

/// Recipe identifier recorded in the metadata and in THIRD_PARTY_NOTICES.md.
const String markerRecipe = 'inspection-marker-v1';

/// Side of the stored template in pixels.
const int markerSide = 28;

/// Footprint side at 1080p, in pixels.
const int referenceFootprint = 16;

const String defaultOutDir = 'assets/vision/marker';

const String _usage =
    '''
Usage: dart run tool/vision/make_marker_template.dart <client-screenshot.png>
         --origin x,y [--out <dir>]
  --origin  top-left pixel of the marker footprint in the screenshot
  --out     output directory, default $defaultOutDir
''';

/// BGR to gray exactly as OpenCV's fixed-point `cvtColor(BGR2GRAY)`.
int lumaOf(int r, int g, int b) =>
    (r * 4899 + g * 9617 + b * 1868 + 8192) >> 14;

const int _scaleDenominator = 1920 * 1080;

/// s * 1920 * 1080 with s = min(W / 1920, H / 1080), in integers so no
/// floating-point boundary can move the footprint.
int _scaleNumerator(int width, int height) {
  final byWidth = width * 1080;
  final byHeight = height * 1920;
  return byWidth < byHeight ? byWidth : byHeight;
}

/// Footprint side for a client of [width] x [height]: trunc(16 * s).
int footprintFor(int width, int height) =>
    referenceFootprint * _scaleNumerator(width, height) ~/ _scaleDenominator;

/// Resizes a square [side] x [side] gray crop to 28x28 deterministically:
/// exact integer area averaging when shrinking, fixed-point cubic (OpenCV's
/// a = -0.75 kernel) when enlarging, identity at exactly 28.
Uint8List resizeToMarker(Uint8List src, int side) {
  if (side == markerSide) return Uint8List.fromList(src);
  return side > markerSide ? _area(src, side) : _cubic(src, side);
}

Uint8List _area(Uint8List src, int side) {
  // Units of 1/28 source pixel: source pixel i spans [i * 28, (i + 1) * 28),
  // destination pixel d spans [d * side, (d + 1) * side).
  final weights = <List<(int, int)>>[];
  for (var d = 0; d < markerSide; d++) {
    final lo = d * side;
    final hi = lo + side;
    final list = <(int, int)>[];
    for (var i = lo ~/ markerSide; i * markerSide < hi; i++) {
      final a = i * markerSide > lo ? i * markerSide : lo;
      final b = (i + 1) * markerSide < hi ? (i + 1) * markerSide : hi;
      if (b > a) list.add((i, b - a));
    }
    weights.add(list);
  }
  final total = side * side;
  final out = Uint8List(markerSide * markerSide);
  for (var dy = 0; dy < markerSide; dy++) {
    for (var dx = 0; dx < markerSide; dx++) {
      var sum = 0;
      for (final (sy, wy) in weights[dy]) {
        for (final (sx, wx) in weights[dx]) {
          sum += wy * wx * src[sy * side + sx];
        }
      }
      out[dy * markerSide + dx] = (sum + total ~/ 2) ~/ total;
    }
  }
  return out;
}

const int _weightBits = 11;
const int _weightOne = 1 << _weightBits;

/// Cubic taps for destination index [d]: (source index, fixed-point weight)
/// with weights summing to exactly [_weightOne] and source indices clamped.
List<(int, int)> _cubicTaps(int d, int side) {
  // Source coordinate (2d + 1) * side / 56 - 0.5 is num / 56 exactly.
  final num = (2 * d + 1) * side - markerSide;
  final base = num >= 0 ? num ~/ 56 : -((-num + 55) ~/ 56);
  final t = (num - base * 56) / 56;
  const a = -0.75;
  final raw = <double>[
    ((a * (t + 1) - 5 * a) * (t + 1) + 8 * a) * (t + 1) - 4 * a,
    ((a + 2) * t - (a + 3)) * t * t + 1,
    ((a + 2) * (1 - t) - (a + 3)) * (1 - t) * (1 - t) + 1,
    0,
  ];
  raw[3] = 1 - raw[0] - raw[1] - raw[2];
  final fixed = [for (final w in raw) (w * _weightOne).round()];
  fixed[1] += _weightOne - fixed.reduce((x, y) => x + y);
  return [
    for (var k = 0; k < 4; k++) ((base - 1 + k).clamp(0, side - 1), fixed[k]),
  ];
}

Uint8List _cubic(Uint8List src, int side) {
  final taps = [for (var d = 0; d < markerSide; d++) _cubicTaps(d, side)];
  // The horizontal pass keeps full precision; the vertical pass rounds once.
  final rows = List<Int32List>.generate(side, (y) {
    final row = Int32List(markerSide);
    for (var dx = 0; dx < markerSide; dx++) {
      var sum = 0;
      for (final (sx, w) in taps[dx]) {
        sum += w * src[y * side + sx];
      }
      row[dx] = sum;
    }
    return row;
  });
  const shift = 2 * _weightBits;
  final out = Uint8List(markerSide * markerSide);
  for (var dy = 0; dy < markerSide; dy++) {
    for (var dx = 0; dx < markerSide; dx++) {
      var sum = 0;
      for (final (sy, w) in taps[dy]) {
        sum += w * rows[sy][dx];
      }
      final v = (sum + (1 << (shift - 1))) >> shift;
      out[dy * markerSide + dx] = v < 0 ? 0 : (v > 255 ? 255 : v);
    }
  }
  return out;
}

/// Runs the tool. Returns 0 on success, 1 when the input is rejected and 2 on
/// a usage error. Files are written only on success.
int run(List<String> args, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  String? screenshot;
  String? originText;
  var outDir = defaultOutDir;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--help' || '-h':
        stdoutSink.writeln(_usage);
        return 0;
      case '--origin' || '--out':
        if (i + 1 >= args.length) {
          stderrSink.writeln('error: $a needs a value\n$_usage');
          return 2;
        }
        final value = args[++i];
        if (a == '--origin') {
          originText = value;
        } else {
          outDir = value;
        }
      default:
        if (a.startsWith('--') || screenshot != null) {
          stderrSink.writeln('error: unexpected argument $a\n$_usage');
          return 2;
        }
        screenshot = a;
    }
  }
  final parts = originText?.split(',');
  final ox = parts?.length == 2 ? int.tryParse(parts![0].trim()) : null;
  final oy = parts?.length == 2 ? int.tryParse(parts![1].trim()) : null;
  if (screenshot == null || ox == null || oy == null) {
    stderrSink.writeln(
      'error: a screenshot and --origin x,y are required\n$_usage',
    );
    return 2;
  }
  final file = File(screenshot);
  if (!file.existsSync()) {
    stderrSink.writeln('error: screenshot not found: $screenshot');
    return 2;
  }
  final bytes = file.readAsBytesSync();
  final decoded = img.decodePng(bytes);
  if (decoded == null) {
    stderrSink.writeln('error: $screenshot is not a decodable PNG');
    return 2;
  }
  final width = decoded.width;
  final height = decoded.height;

  final numerator = _scaleNumerator(width, height);
  if (numerator < _scaleDenominator) {
    final s = numerator / _scaleDenominator;
    stderrSink.writeln(
      'error: screenshot ${width}x$height has scale ${s.toStringAsFixed(3)} '
      '< 1.0; supply a screenshot at 1080p scale or larger',
    );
    return 1;
  }
  final side = footprintFor(width, height);
  if (ox < 0 || oy < 0 || ox + side > width || oy + side > height) {
    stderrSink.writeln(
      'error: footprint ${side}x$side at ($ox,$oy) extends past the '
      '${width}x$height screenshot',
    );
    return 1;
  }

  final rgb = decoded.convert(format: img.Format.uint8, numChannels: 3);
  final crop = Uint8List(side * side);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final p = rgb.getPixel(ox + x, oy + y);
      crop[y * side + x] = lumaOf(p.r.toInt(), p.g.toInt(), p.b.toInt());
    }
  }
  final gray = resizeToMarker(crop, side);

  final meta = <String, Object>{
    'format': 1,
    'width': markerSide,
    'height': markerSide,
    'stride': markerSide,
    'sourceWidth': width,
    'sourceHeight': height,
    'scale': numerator / _scaleDenominator,
    'footprint': side,
    'origin': <String, int>{'x': ox, 'y': oy},
    'sourceSha256': sha256.convert(bytes).toString(),
    'recipe': markerRecipe,
  };
  final json = const JsonEncoder.withIndent('  ').convert(meta);

  final grayPath = '$outDir/inspection_marker.gray';
  final jsonPath = '$outDir/inspection_marker.json';
  for (final path in [grayPath, jsonPath]) {
    final unsafe = unsafeOutputReason(path, protectedFiles: [screenshot]);
    if (unsafe != null) {
      stderrSink.writeln('error: $unsafe');
      return 1;
    }
  }
  final dir = Directory(outDir)..createSync(recursive: true);
  File(grayPath).writeAsBytesSync(gray);
  File(jsonPath).writeAsBytesSync(utf8.encode('$json\n'));
  stdoutSink.writeln(
    'wrote ${dir.path} ${markerSide}x$markerSide from ${side}x$side '
    'footprint at ($ox,$oy)',
  );
  return 0;
}

void main(List<String> args) {
  exit(run(args));
}
