@Tags(['qualification'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/data/vision/vision_primitives.dart';
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic noise so the template correlates only with its own copies.
Uint8List _noise(int length, int seed) {
  var state = seed;
  return Uint8List.fromList([
    for (var i = 0; i < length; i++)
      (state = (state * 1103515245 + 12345) & 0x7fffffff) >> 23,
  ]);
}

VisionImage _gray(Uint8List bytes, int width, int height) => VisionImage(
  bytes,
  width: width,
  height: height,
  stride: width,
  channels: 1,
);

/// Loads the real Release bundle's vision runtime in the test process and
/// lists template peaks through `bgv_match_template_peaks`; no app is launched.
void main() {
  // e.g. build/windows/x64/runner/Release
  final bundleEnv = Platform.environment['BLACKGRID_RELEASE_BUNDLE'];
  final skip = bundleEnv == null
      ? 'Requires BLACKGRID_RELEASE_BUNDLE (a built Release bundle).'
      : false;

  const side = 12;
  const imageWidth = 100;
  const imageHeight = 50;
  final template = _gray(_noise(side * side, 7), side, side);

  T withRuntime<T>(T Function(VisionRuntime runtime) body) {
    final runtime = VisionRuntime.open(
      runtimeDirectory: Directory(bundleEnv!).resolveSymbolicLinksSync(),
    );
    try {
      final status = runtime.status;
      if (status is VisionUnavailable) {
        fail('runtime unavailable: ${status.failure.message}');
      }
      return body(runtime);
    } finally {
      runtime.dispose();
    }
  }

  List<TemplatePeak> ok(VisionResult<List<TemplatePeak>> result) =>
      switch (result) {
        VisionOk(:final value) => value,
        VisionFailed(:final failure) => fail(failure.message),
      };

  test('real DLL lists two exact copies in raster order', () {
    final bytes = Uint8List(imageWidth * imageHeight);
    // The later copy is pasted first, so raster order is the DLL's doing.
    for (final (x, y) in [(60, 30), (10, 5)]) {
      for (var row = 0; row < side; row++) {
        bytes.setRange(
          (y + row) * imageWidth + x,
          (y + row) * imageWidth + x + side,
          template.bytes,
          row * side,
        );
      }
    }
    withRuntime((runtime) {
      final peaks = ok(
        runtime.matchTemplatePeaks(
          _gray(bytes, imageWidth, imageHeight),
          template,
          0.99,
          16,
        ),
      );
      expect([for (final peak in peaks) (peak.x, peak.y)], [(10, 5), (60, 30)]);
      for (final peak in peaks) {
        expect(peak.score, greaterThanOrEqualTo(0.99));
      }
    });
  }, skip: skip);

  test('real DLL returns an empty list below threshold', () {
    final image = _gray(
      _noise(imageWidth * imageHeight, 99),
      imageWidth,
      imageHeight,
    );
    withRuntime((runtime) {
      expect(
        ok(runtime.matchTemplatePeaks(image, template, 0.99, 16)),
        isEmpty,
      );
    });
  }, skip: skip);
}
