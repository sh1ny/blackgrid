@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_native.dart';
import 'package:blackgrid/data/vision/inspection_geometry.dart';
import 'package:blackgrid/data/vision/inspection_recognition.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/data/vision/vision_primitives.dart'
    show visionInterCubic;
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:blackgrid/data/vision/vision_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// How long one stage may take before the test reports where it stuck.
const _stageLimit = Duration(seconds: 30);

/// A 4K client: processing scale 2, a 32 px marker, a 34 px title region that
/// needs no resize (2 / scale = 1).
const _clientWidth = 3840;
const _clientHeight = 2160;

/// Where the marker's top-left sits in the synthetic frame.
const _markerX = 40;
const _markerY = 12;

const _frameWidth = 440;
const _frameHeight = 70;

/// The self-check sample's ink spans rows 14..33 and columns 10..326 of its
/// 336x48 image. The paste puts the ink 7 rows below the marker's y (inside the
/// 34 px title region) and 6 columns right of the region start.
const _inkTop = 14;
const _inkLeft = 10;
const _inkRowInRegion = 7;
const _inkColumnInRegion = 6;

/// Dark background and light text, as in the game's inspection panel.
const _background = 20;

/// The bundle's capture DLL. The factories are top-level so they are always
/// sendable: a closure in the test body would share a context with the
/// service itself.
String _bundleCaptureDll() =>
    '${Directory(Platform.environment['BLACKGRID_RELEASE_BUNDLE']!).resolveSymbolicLinksSync()}'
    '${Platform.pathSeparator}$captureLibraryName';

CapturePlatform _bundleCapture() =>
    NativeCapturePlatform.open(_bundleCaptureDll());

FrameRegistry _bundleFrames() => _bundleCapture().frames;

/// Resizes the marker in a worker isolate with the runtime's own `bgv_resize`,
/// exactly as the job scales it, so the pasted copy matches the job's template
/// pixel for pixel.
Future<Uint8List> _scaledMarker(String bundle, VisionImage marker, int side) =>
    Isolate.run(() {
      final runtime = VisionRuntime.open(runtimeDirectory: bundle);
      try {
        return switch (runtime.resize(
          marker,
          side,
          side,
          interp: visionInterCubic,
        )) {
          VisionOk(:final value) => value.bytes,
          VisionFailed(:final failure) => throw StateError(failure.message),
        };
      } finally {
        runtime.dispose();
      }
    });

/// A BGRX frame holding [marker] (a [side] px gray square) at the known
/// position and the self-check title, light on dark, in the title region.
VisionImage _syntheticFrame({
  required Uint8List marker,
  required int side,
  required VisionImage title,
}) {
  final pixels = Uint8List(_frameWidth * _frameHeight * 4);
  void put(int x, int y, int gray) {
    final at = (y * _frameWidth + x) * 4;
    pixels[at] = gray;
    pixels[at + 1] = gray;
    pixels[at + 2] = gray;
    pixels[at + 3] = 255;
  }

  for (var y = 0; y < _frameHeight; y++) {
    for (var x = 0; x < _frameWidth; x++) {
      put(x, y, _background);
    }
  }
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      put(_markerX + x, _markerY + y, marker[y * side + x]);
    }
  }
  final regionX = _markerX + (side * 1.2).truncate();
  final originX = regionX + _inkColumnInRegion - _inkLeft;
  final originY = _markerY + _inkRowInRegion - _inkTop;
  for (var y = 0; y < title.height; y++) {
    for (var x = 0; x < title.width; x++) {
      // The sample is dark text on a light page; the game is the reverse.
      put(originX + x, originY + y, 255 - title.bytes[y * title.stride + x]);
    }
  }
  return VisionImage(
    pixels,
    width: _frameWidth,
    height: _frameHeight,
    stride: _frameWidth * 4,
    channels: 4,
  );
}

/// Runs the real job in a warm worker over the real bundle and returns the
/// targeted result for the synthetic frame.
Future<InspectionRecognition> _recognise(String bundle) async {
  final loaded = loadMarkerTemplate(bundle);
  if (loaded is! MarkerTemplateLoaded) fail('marker template: $loaded');
  final template = loaded.template;
  final scale = processingScale(_clientWidth, _clientHeight);
  final side = scaledTemplateSize(scale);

  final sample = jsonDecode(
    File('$bundle\\data\\vision\\self_check\\title.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final title = VisionImage(
    File('$bundle\\data\\vision\\self_check\\title.gray').readAsBytesSync(),
    width: sample['width']! as int,
    height: sample['height']! as int,
    stride: sample['stride']! as int,
    channels: 1,
  );
  final frame = _syntheticFrame(
    marker: await _scaledMarker(bundle, template.image, side),
    side: side,
    title: title,
  );

  final service = VisionService<InspectionRequest, InspectionRecognition>(
    runtimeDirectory: bundle,
    jobFactory: inspectionRecognitionJobFactory,
    templates: [template],
    platformFactory: _bundleCapture,
    registryFactory: _bundleFrames,
  );
  try {
    final failure = await service.start().timeout(
      _stageLimit,
      onTimeout: () => fail('start did not answer; state ${service.state}'),
    );
    expect(failure, isNull, reason: failure?.message);
    final answer = await service
        .submit(
          frame,
          const InspectionRequest(
            kind: InspectionFrameKind.targeted,
            clientWidth: _clientWidth,
            clientHeight: _clientHeight,
          ),
        )
        .timeout(
          _stageLimit,
          onTimeout: () => fail('job did not answer; state ${service.state}'),
        );
    if (answer is! VisionDelivered<InspectionRecognition>) {
      fail('job answered $answer');
    }
    return answer.result;
  } finally {
    await service.close();
  }
}

/// Real NCC, threshold and OCR over a synthetic frame, through the real
/// worker and the Release bundle's runtime. Nothing here touches the game.
void main() {
  // e.g. build/windows/x64/runner/Release
  final bundleEnv = Platform.environment['BLACKGRID_RELEASE_BUNDLE'];
  final skip = bundleEnv == null
      ? 'Requires BLACKGRID_RELEASE_BUNDLE (a built Release bundle).'
      : false;
  final bundle = bundleEnv == null
      ? ''
      : Directory(bundleEnv).resolveSymbolicLinksSync();

  test('real runtime finds a synthetic marker at its position with score at '
      'least 0.99', () async {
    final result = await _recognise(bundle);

    expect(result, isA<InspectionRecognised>());
    final recognised = result as InspectionRecognised;
    expect(recognised.bestMarkerScore, greaterThanOrEqualTo(0.99));
    expect(recognised.evidence, hasLength(1));
    final evidence = recognised.evidence.single;
    expect((evidence.markerX, evidence.markerY), (_markerX, _markerY));
    expect(evidence.markerScore, greaterThanOrEqualTo(0.99));
  }, skip: skip);

  test(
    'real runtime reads the rendered SALEWA title through the pipeline',
    () async {
      final result = await _recognise(bundle);

      final evidence = (result as InspectionRecognised).evidence.single;
      expect(evidence.titleStatus, InspectionTitleStatus.read);
      expect(evidence.text, 'SALEWA FIRST AID KIT');
      expect(evidence.crop, isNotEmpty);
      expect(evidence.qpcMarker, lessThanOrEqualTo(evidence.qpcOcr));
    },
    skip: skip,
  );
}
