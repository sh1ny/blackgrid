import 'dart:isolate';
import 'dart:typed_data';

import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'holdable_vision_native.dart';

VisionImage tiny() =>
    VisionImage(Uint8List(4), width: 2, height: 2, stride: 2, channels: 1);

/// Top-level so only the control address crosses into the isolate.
int grayOnWorker(int address) {
  final native = holdableVisionOpener(address)('l', 't', 'v');
  return native.primitives.toGray(tiny(), rgbOrder: false).length;
}

void main() {
  late VisionControlBlock control;
  setUp(() => control = VisionControlBlock());
  tearDown(() => control.free());

  test('a held call in another isolate is observed then released', () async {
    final address = control.address;
    control.held = true;
    final done = Isolate.run(() => grayOnWorker(address));

    await eventually(() => control.concurrent == 1);
    expect(control.maxConcurrent, 1);

    control.held = false;
    expect(await done, 4);
    expect(control.concurrent, 0);
    expect(control.maxConcurrent, 1);
    expect(control.operationCount, 1);
  });

  test('scripted native status surfaces as a native failure', () async {
    control.nativeStatus = -3;
    final dir = createFakeRuntimeDirectory();
    addTearDown(() => dir.deleteSync(recursive: true));
    final runtime = VisionRuntime.open(
      runtimeDirectory: dir.path,
      opener: holdableVisionOpener(control.address),
    );
    expect(runtime.status, isA<VisionReady>());
    final result = runtime.toGray(tiny());
    expect(
      result,
      isA<VisionFailed<VisionImage>>().having(
        (r) => r.failure,
        'failure',
        isA<VisionNativeFailure>().having((f) => f.status, 'status', -3),
      ),
    );
    runtime.dispose();
    expect(control.engineDisposeCount, 1);
    expect(control.nativeCloseCount, 1);
    expect(control.openCount, 1);
  });

  test('open hold blocks the opener in another isolate', () async {
    final address = control.address;
    control.openHeld = true;
    final done = Isolate.run(() {
      holdableVisionOpener(address)('l', 't', 'v');
      return 1;
    });
    await eventually(() => control.openCount == 1);
    control.openHeld = false;
    expect(await done, 1);
  });

  test('fake clock is shared and advances by the step', () {
    final a = control.clock;
    final b = FakeVisionClock.fromAddress(control.address);
    expect(a.now(), 1000);
    expect(b.now(), 1010);
    a.setStep(0);
    expect(b.now(), 1020);
    expect(a.now(), 1020);
  });
}
