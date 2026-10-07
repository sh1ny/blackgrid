import 'dart:typed_data';

import 'package:blackgrid/data/vision/vision_image.dart';
import 'package:flutter_test/flutter_test.dart';

VisionImage image(
  int width,
  int height, {
  int channels = 1,
  int? stride,
  int? length,
}) {
  final rowBytes = stride ?? width * channels;
  return VisionImage(
    Uint8List(length ?? rowBytes * height),
    width: width,
    height: height,
    stride: rowBytes,
    channels: channels,
  );
}

void main() {
  test('well formed images validate', () {
    expect(image(4, 3).validate(), isNull);
    expect(image(4, 3, channels: 3, stride: 16).validate(), isNull);
    expect(image(4, 3, channels: 4).validate(), isNull);
    expect(image(8192, 1).validate(), isNull);
    expect(image(1, 8192).validate(), isNull);
  });

  test('short stride or buffer is invalidImage before native call', () {
    expect(image(4, 3, channels: 3, stride: 11).validate(), isNotNull);
    expect(image(4, 3, length: 11).validate(), isA<VisionInvalidImage>());
    expect(image(4, 3, length: 12).validate(), isNull);
  });

  test('template larger than image is invalidImage', () {
    final base = image(10, 10);
    expect(
      VisionImage.validateTemplate(base, image(11, 5)),
      isA<VisionInvalidImage>(),
    );
    expect(
      VisionImage.validateTemplate(base, image(5, 11)),
      isA<VisionInvalidImage>(),
    );
    expect(VisionImage.validateTemplate(base, image(10, 10)), isNull);
    expect(
      VisionImage.validateTemplate(base, image(5, 5, length: 3)),
      isA<VisionInvalidImage>(),
    );
  });

  test('each side is capped at 8192 and must be positive', () {
    expect(image(8193, 1).validate(), isA<VisionInvalidImage>());
    expect(image(1, 8193).validate(), isA<VisionInvalidImage>());
    expect(image(0, 1, length: 1).validate(), isA<VisionInvalidImage>());
    expect(image(1, 0, length: 1).validate(), isA<VisionInvalidImage>());
  });

  test('pixel count is capped at 24 MPix', () {
    expect(image(8192, 3072).validate(), isNull);
    expect(image(8192, 3073).validate(), isA<VisionInvalidImage>());
  });

  test('channels must be 1, 3 or 4', () {
    expect(image(2, 2, channels: 2, length: 16).validate(), isNotNull);
    expect(image(2, 2, channels: 5, length: 40).validate(), isNotNull);
    expect(image(2, 2, channels: 0, length: 16).validate(), isNotNull);
  });
}
