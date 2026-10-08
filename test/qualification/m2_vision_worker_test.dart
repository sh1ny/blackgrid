@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_native.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:blackgrid/data/vision/vision_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// How long one stage may take before the test reports where it stuck.
const _stageLimit = Duration(seconds: 30);

/// What [_SelfCheckJob] found in one image.
typedef _SelfCheckResult = ({double score, int x, int y, String text});

/// Matches the `title` template and reads the line, as the self-check does.
final class _SelfCheckJob implements VisionJob<void, _SelfCheckResult> {
  @override
  _SelfCheckResult run(
    VisionJobContext context,
    VisionJobInput input,
    void params,
  ) => input.withImage((image) {
    final match = _ok(
      context.matchTemplate(image, context.templates['title']!.image),
    );
    final text = _ok(context.recognise(image));
    return (score: match.score, x: match.x, y: match.y, text: text.text.trim());
  });
}

VisionJob<void, _SelfCheckResult> _selfCheckJob() => _SelfCheckJob();

T _ok<T>(VisionResult<T> result) => switch (result) {
  VisionOk<T>(:final value) => value,
  VisionFailed<T>(:final failure) => throw VisionJobAbort(failure),
};

/// The bundle's capture DLL. The factories are top-level so they are always
/// sendable: a closure in the test body would share a context with the
/// service itself.
String _bundleCaptureDll() =>
    '${Directory(Platform.environment['BLACKGRID_RELEASE_BUNDLE']!).resolveSymbolicLinksSync()}'
    '${Platform.pathSeparator}$captureLibraryName';

CapturePlatform _bundleCapture() =>
    NativeCapturePlatform.open(_bundleCaptureDll());

FrameRegistry _bundleFrames() => _bundleCapture().frames;

/// Starts the warm vision worker against the real Release bundle in the test
/// process; no app is launched. The capture DLL comes from the bundle too,
/// because the test runner is not the bundle's executable.
void main() {
  // e.g. build/windows/x64/runner/Release
  final bundleEnv = Platform.environment['BLACKGRID_RELEASE_BUNDLE'];
  final skip = bundleEnv == null
      ? 'Requires BLACKGRID_RELEASE_BUNDLE (a built Release bundle).'
      : false;
  final bundle = bundleEnv == null
      ? ''
      : Directory(bundleEnv).resolveSymbolicLinksSync();
  final captureDll = '$bundle\\$captureLibraryName';

  // Each stage fails on its own instead of at the 2-minute tag timeout.
  test('capture platform opens in a worker isolate', () async {
    final qpc = await Isolate.run(
      () => NativeCapturePlatform.open(captureDll).qpcNow(),
    ).timeout(_stageLimit);
    expect(qpc, greaterThan(0));
  }, skip: skip);

  test('vision runtime opens in a worker isolate', () async {
    final status = await Isolate.run(() {
      final runtime = VisionRuntime.open(runtimeDirectory: bundle);
      try {
        return switch (runtime.status) {
          VisionReady() => 'ready',
          VisionUnavailable(:final failure) => failure.message,
          VisionDisposed() => 'disposed',
        };
      } finally {
        runtime.dispose();
      }
    }).timeout(_stageLimit);
    expect(status, 'ready');
  }, skip: skip);

  test('warm worker runs the self-check job twice and closes', () async {
    final sample = jsonDecode(
      File('$bundle\\data\\vision\\self_check\\title.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final bytes = File('$bundle\\data\\vision\\self_check\\title.gray')
        .readAsBytesSync();
    final image = VisionImage(
      bytes,
      width: sample['width']! as int,
      height: sample['height']! as int,
      stride: sample['stride']! as int,
      channels: 1,
    );
    final rect = sample['template']! as Map<String, Object?>;
    final x = rect['x']! as int;
    final y = rect['y']! as int;
    final w = rect['width']! as int;
    final h = rect['height']! as int;
    final crop = Uint8List(w * h);
    for (var row = 0; row < h; row++) {
      final start = (y + row) * image.stride + x;
      crop.setRange(row * w, (row + 1) * w, image.bytes, start);
    }

    final service = VisionService<void, _SelfCheckResult>(
      runtimeDirectory: bundle,
      jobFactory: _selfCheckJob,
      templates: [
        VisionTemplate(
          'title',
          VisionImage(crop, width: w, height: h, stride: w, channels: 1),
        ),
      ],
      platformFactory: _bundleCapture,
      registryFactory: _bundleFrames,
    );
    var closed = false;
    try {
      final failure = await service.start().timeout(
        _stageLimit,
        onTimeout: () => fail('start did not answer; state ${service.state}'),
      );
      expect(failure, isNull, reason: failure?.message);
      expect(service.state, VisionServiceState.ready);

      // The second run reuses the worker's warm engine and scratch buffers.
      for (var run = 0; run < 2; run++) {
        final answer = await service
            .submit(image, null)
            .timeout(
              _stageLimit,
              onTimeout: () =>
                  fail('run $run did not answer; state ${service.state}'),
            );
        if (answer is! VisionDelivered<_SelfCheckResult>) {
          fail('run $run answered $answer');
        }
        final result = answer.result;
        expect(result.score, greaterThanOrEqualTo(0.99));
        expect((result.x, result.y), (x, y));
        expect(result.text, sample['text']);
        expect(answer.submittedQpc, lessThanOrEqualTo(answer.startedQpc));
        expect(answer.startedQpc, lessThanOrEqualTo(answer.finishedQpc));
        expect(service.state, VisionServiceState.ready);
      }
      expect(await service.close(), VisionCloseResult.closed);
      closed = true;
      expect(service.state, VisionServiceState.closed);
    } finally {
      // Bounded by the close drain; never masks the failure above.
      if (!closed) await service.close();
    }
  }, skip: skip);
}
