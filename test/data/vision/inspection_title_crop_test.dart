import 'dart:typed_data';

import 'package:blackgrid/data/vision/inspection_title_crop.dart';
import 'package:blackgrid/data/vision/vision_image.dart';
import 'package:flutter_test/flutter_test.dart';

/// A white one-channel image with black pixels at [ink], each `(x, y)`.
///
/// Padding bytes past [width] in each row hold [padding].
VisionImage binary(
  int width,
  int height, {
  List<(int, int)> ink = const [],
  int? stride,
  int padding = 255,
}) {
  final rowBytes = stride ?? width;
  final bytes = Uint8List(rowBytes * height);
  for (var y = 0; y < height; y++) {
    bytes.fillRange(y * rowBytes, y * rowBytes + width, 255);
    bytes.fillRange(y * rowBytes + width, (y + 1) * rowBytes, padding);
  }
  for (final (x, y) in ink) {
    bytes[y * rowBytes + x] = 0;
  }
  return VisionImage(
    bytes,
    width: width,
    height: height,
    stride: rowBytes,
    channels: 1,
  );
}

/// The image of [crop], failing the test when it is blank.
VisionImage contentOf(BoundedTitle crop) => switch (crop) {
  TitleWithForeground(:final image) => image,
  BlankTitle() => fail('expected foreground, got a blank title'),
};

/// Logical pixel rows of [image], without row padding.
List<List<int>> rows(VisionImage image) => [
  for (var y = 0; y < image.height; y++)
    image.bytes.sublist(y * image.stride, y * image.stride + image.width),
];

void main() {
  group('boundTitleMargin', () {
    test('bounds the recorded 999-to-595 extent', () {
      final source = binary(999, 2, ink: [(3, 0), (586, 1)]);
      final image = contentOf(boundTitleMargin(source));
      expect(image.width, 595);
      expect(image.height, 2);
      expect(image.stride, 595);
      expect(image.channels, 1);
      expect(rows(image), [
        for (final row in rows(source)) row.sublist(0, 595),
      ]);
    });

    test('rightmost foreground at 19 yields width 28', () {
      final source = binary(50, 3, ink: [(19, 1)]);
      final image = contentOf(boundTitleMargin(source));
      expect(image.width, titleRightMargin + 20);
      expect(image.width, 28);
      expect(rows(image), [for (final row in rows(source)) row.sublist(0, 28)]);
    });

    test('rightmost foreground at 46 retains width 50', () {
      final source = binary(50, 3, ink: [(46, 2)]);
      final image = contentOf(boundTitleMargin(source));
      expect(image, same(source));
    });

    test('foreground at the last column retains full width', () {
      final source = binary(50, 2, ink: [(0, 0), (49, 1)]);
      expect(contentOf(boundTitleMargin(source)), same(source));
    });

    test('preserves internal spaces and detached final punctuation', () {
      // Two "words" separated by a wide gap, then a detached ")" whose only
      // pixels sit in a lower row than the rest of the text.
      final ink = [
        for (var x = 2; x < 8; x++) (x, 0),
        for (var x = 30; x < 36; x++) (x, 0),
        (60, 3),
      ];
      final source = binary(120, 4, ink: ink);
      final image = contentOf(boundTitleMargin(source));
      expect(image.width, 69);
      expect(rows(image), [for (final row in rows(source)) row.sublist(0, 69)]);
    });

    test('foreground in different rows uses the rightmost of all rows', () {
      final source = binary(80, 3, ink: [(40, 0), (10, 1), (25, 2)]);
      expect(contentOf(boundTitleMargin(source)).width, 49);
    });

    test('black row padding is not foreground and is not copied', () {
      final source = binary(
        40,
        2,
        ink: [(5, 0), (9, 1)],
        stride: 48,
        padding: 0,
      );
      final image = contentOf(boundTitleMargin(source));
      expect(image.width, 18);
      expect(image.stride, 18);
      expect(image.bytes.length, 36);
      expect(rows(image), [for (final row in rows(source)) row.sublist(0, 18)]);
    });

    test('padded image needing no narrowing is returned unchanged', () {
      final source = binary(20, 2, ink: [(15, 1)], stride: 24, padding: 0);
      expect(contentOf(boundTitleMargin(source)), same(source));
    });

    test('all-white input is blank', () {
      expect(boundTitleMargin(binary(50, 3)), isA<BlankTitle>());
    });

    test('all-white input with black padding is blank', () {
      final source = binary(10, 2, stride: 16, padding: 0);
      expect(boundTitleMargin(source), isA<BlankTitle>());
    });

    test('one white pixel is blank', () {
      expect(boundTitleMargin(binary(1, 1)), isA<BlankTitle>());
    });

    test('one black pixel is kept unchanged', () {
      final source = binary(1, 1, ink: [(0, 0)]);
      expect(contentOf(boundTitleMargin(source)), same(source));
    });

    test('narrowing leaves the source bytes untouched', () {
      final source = binary(60, 2, ink: [(4, 0), (7, 1)], stride: 64);
      final before = Uint8List.fromList(source.bytes);
      final image = contentOf(boundTitleMargin(source));
      expect(source.bytes, before);
      expect(image.bytes.buffer, isNot(same(source.bytes.buffer)));
      image.bytes[0] = 7;
      expect(source.bytes, before);
    });

    test('rejects a multi-channel image', () {
      final image = VisionImage(
        Uint8List(12),
        width: 2,
        height: 2,
        stride: 6,
        channels: 3,
      );
      expect(() => boundTitleMargin(image), throwsArgumentError);
    });

    test('rejects an invalid descriptor', () {
      final image = VisionImage(
        Uint8List(3),
        width: 2,
        height: 2,
        stride: 2,
        channels: 1,
      );
      expect(() => boundTitleMargin(image), throwsArgumentError);
    });
  });
}
