import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../../tool/vision/make_fir_template.dart' as fir;

void main() {
  late Directory temp;
  late File screenshot;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bg_fir_tool');
    // Full dimensions are necessary to exercise the reviewed crop coordinates.
    final image = img.Image(width: 3440, height: 1440, numChannels: 3);
    for (var y = 0; y < 28; y++) {
      for (var x = 0; x < 28; x++) {
        image.setPixelRgb(1199 + x, 732 + y, x * 7, y * 8, (x + y) * 4);
      }
    }
    screenshot = File('${temp.path}/source.png')
      ..writeAsBytesSync(img.encodePng(image));
  });
  tearDown(() => temp.deleteSync(recursive: true));

  ({int exitCode, String stderr}) generate(
    Directory out, {
    String crop = '1199,732,28,28',
    String client = '3440,1440',
  }) {
    final errors = StringBuffer();
    final code = fir.run(
      [screenshot.path, '--crop', crop, '--client', client, '--out', out.path],
      out: StringBuffer(),
      err: errors,
    );
    return (exitCode: code, stderr: errors.toString());
  }

  test('small crop uses exact fixed-point luma without resampling', () {
    final image = img.Image(width: 32, height: 32, numChannels: 3);
    image.setPixelRgb(2, 3, 200, 100, 50);
    image.setPixelRgb(29, 30, 10, 20, 30);
    final pixels = fir.cropFirTemplate(
      image,
      clientWidth: 32,
      clientHeight: 32,
      x: 2,
      y: 3,
      width: 28,
      height: 28,
    );
    expect(pixels.first, (200 * 4899 + 100 * 9617 + 50 * 1868 + 8192) >> 14);
    expect(pixels.last, (10 * 4899 + 20 * 9617 + 30 * 1868 + 8192) >> 14);
    expect(pixels.skip(1).take(782), everyElement(0));
  });

  test('refuses an output that would overwrite the source image', () {
    screenshot = File('${temp.path}/inspection_fir.json')
      ..writeAsBytesSync(screenshot.readAsBytesSync());
    final before = screenshot.readAsBytesSync();
    final result = generate(temp);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('inspection_fir.json'));
    expect(screenshot.readAsBytesSync(), before);
    expect(File('${temp.path}/inspection_fir.gray').existsSync(), isFalse);
  });

  test('same screenshot recipe reproduces bytes', () {
    final a = Directory('${temp.path}/a');
    final b = Directory('${temp.path}/b');
    final first = generate(a);
    final second = generate(b);
    expect(first.exitCode, 0, reason: first.stderr);
    expect(second.exitCode, 0, reason: second.stderr);
    final gray = File('${a.path}/inspection_fir.gray').readAsBytesSync();
    expect(gray, File('${b.path}/inspection_fir.gray').readAsBytesSync());
    expect(gray, hasLength(28 * 28));
    for (var y = 0; y < 28; y++) {
      for (var x = 0; x < 28; x++) {
        final expected =
            (x * 7 * 4899 + y * 8 * 9617 + (x + y) * 4 * 1868 + 8192) >> 14;
        expect(gray[y * 28 + x], expected, reason: 'pixel $x,$y');
      }
    }
    final metadataBytes = File('${a.path}/inspection_fir.json')
        .readAsBytesSync();
    expect(
      metadataBytes,
      File('${b.path}/inspection_fir.json').readAsBytesSync(),
    );
    final metadata =
        jsonDecode(utf8.decode(metadataBytes)) as Map<String, dynamic>;
    expect(metadata['recipe'], 'inspection-fir-v1');
    expect(
      metadata['sourceSha256'],
      sha256.convert(screenshot.readAsBytesSync()).toString(),
    );
    expect((metadata['sourceWidth'], metadata['sourceHeight']), (3440, 1440));
    expect(metadata['client'], {'width': 3440, 'height': 1440});
    expect(metadata['crop'], {'x': 1199, 'y': 732, 'width': 28, 'height': 28});
    expect(metadata['grayscale'], 'opencv-bgr2gray-fixed-point');
    expect(
      (metadata['width'], metadata['height'], metadata['stride']),
      (28, 28, 28),
    );
  });

  test('incorrect crop or client geometry is rejected without outputs', () {
    for (final invalid in [
      (crop: '3430,732,28,28', client: '3440,1440'),
      (crop: '1199,732,28,28', client: '1920,1080'),
    ]) {
      final out = Directory('${temp.path}/invalid');
      final result = generate(out, crop: invalid.crop, client: invalid.client);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, anyOf(contains('crop'), contains('client')));
      expect(out.existsSync() && out.listSync().isNotEmpty, isFalse);
    }
  });
}
