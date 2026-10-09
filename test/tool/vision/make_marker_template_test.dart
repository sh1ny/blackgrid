import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../../tool/vision/make_marker_template.dart';

/// Writes a sparse PNG: all zero except a textured patch at (4, 6).
File writeScreenshot(Directory dir, String name, int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < 24; y++) {
    for (var x = 0; x < 24; x++) {
      image.setPixelRgb(
        4 + x,
        6 + y,
        (x * 11 + y * 3) & 0xff,
        (x * 5 + y * 13) & 0xff,
        (x * 17 + y * 7) & 0xff,
      );
    }
  }
  return File('${dir.path}/$name')
    ..writeAsBytesSync(img.encodePng(image, level: 9));
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('bg_marker_tool'));
  tearDown(() => temp.deleteSync(recursive: true));

  ({int code, String err}) runTool(
    File screenshot,
    String origin,
    Directory out,
  ) {
    final err = StringBuffer();
    final code = run(
      [screenshot.path, '--origin', origin, '--out', out.path],
      out: StringBuffer(),
      err: err,
    );
    return (code: code, err: err.toString());
  }

  test(
    '1440p screenshot crops a 21px footprint to identical 28x28 output twice',
    () {
      final shot = writeScreenshot(temp, 'shot.png', 2560, 1440);
      final outA = Directory('${temp.path}/a');
      final outB = Directory('${temp.path}/b');

      final first = runTool(shot, '4,6', outA);
      final second = runTool(shot, '4,6', outB);
      expect(first.code, 0, reason: first.err);
      expect(second.code, 0, reason: second.err);

      List<int> bytes(Directory d, String n) =>
          File('${d.path}/$n').readAsBytesSync();
      final gray = bytes(outA, 'inspection_marker.gray');
      expect(gray, hasLength(28 * 28));
      expect(gray.toSet().length, greaterThan(1));
      expect(gray, bytes(outB, 'inspection_marker.gray'));
      expect(
        bytes(outA, 'inspection_marker.json'),
        bytes(outB, 'inspection_marker.json'),
      );

      final meta = jsonDecode(
        utf8.decode(bytes(outA, 'inspection_marker.json')),
      ) as Map<String, Object?>;
      expect(meta['width'], 28);
      expect(meta['height'], 28);
      expect(meta['stride'], 28);
      expect(meta['footprint'], 21);
      expect(meta['scale'], closeTo(4 / 3, 1e-9));
      expect(meta['sourceWidth'], 2560);
      expect(meta['sourceHeight'], 1440);
      expect(meta['origin'], {'x': 4, 'y': 6});
      expect(
        meta['sourceSha256'],
        sha256.convert(shot.readAsBytesSync()).toString(),
      );
      expect(meta['recipe'], markerRecipe);
    },
  );

  test(
    'footprint past the screenshot edge exits non-zero and writes nothing',
    () {
      final shot = writeScreenshot(temp, 'shot.png', 2560, 1440);
      final out = Directory('${temp.path}/out');
      final result = runTool(shot, '2545,100', out);
      expect(result.code, isNot(0));
      expect(result.err, contains('21x21'));
      expect(result.err, contains('2560x1440'));
      expect(out.existsSync() && out.listSync().isNotEmpty, isFalse);
    },
  );

  test('screenshot below 1080p scale exits non-zero and writes nothing', () {
    final shot = writeScreenshot(temp, 'small.png', 1280, 720);
    final out = Directory('${temp.path}/out');
    final result = runTool(shot, '4,6', out);
    expect(result.code, isNot(0));
    expect(result.err, contains('1080p'));
    expect(out.existsSync() && out.listSync().isNotEmpty, isFalse);
  });
}
