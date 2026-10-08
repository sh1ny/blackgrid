import 'dart:async';
import 'dart:ffi';

import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_native.dart';
import 'package:blackgrid/data/capture/capture_service.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_capture_platform.dart';
import 'support/holdable_capture_platform.dart';

const _ms = Duration(milliseconds: 1);

Duration ms(int n) => _ms * n;

void main() {
  late FakeFrameRegistry registry;
  late Pointer<Int64> control;
  late CaptureService service;
  final services = <CaptureService>[];

  CaptureService makeService({CapturePlatformFactory? factory}) {
    final s = CaptureService(
      platformFactory:
          factory ?? holdableFactory(registry.address, control.address),
      registryFactory: () => FakeFrameRegistry.fromAddress(registry.address),
    );
    services.add(s);
    return s;
  }

  setUp(() {
    registry = FakeFrameRegistry.create();
    control = allocateControl();
    service = makeService();
  });

  tearDown(() async {
    // Never leave a worker blocked or alive across tests.
    control[holdSlot] = 0;
    for (final s in services) {
      await s.close();
      if (s.workerRunning) {
        await s.workerExit.timeout(const Duration(seconds: 5));
      }
    }
    services.clear();
  });

  Future<CaptureResult> request() =>
      service.capture(holdableTrigger, CaptureMode.targeted);

  void hold() => control[holdSlot] = 1;

  /// Releases the hold [after] from now.
  void releaseAfter(Duration after) {
    final mine = control;
    Timer(after, () => mine[holdSlot] = 0);
  }

  Future<void> eventually(bool Function() condition, {int seconds = 5}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!condition()) {
      if (DateTime.now().isAfter(end)) fail('condition not met in ${seconds}s');
      await Future<void>.delayed(ms(10));
    }
  }

  CaptureFailure failureOf(CaptureResult result) {
    expect(result, isA<CaptureRejected>(), reason: '$result');
    return (result as CaptureRejected).failure;
  }

  test('second request while active is captureBusy', () async {
    hold();
    releaseAfter(ms(300));
    final first = request();
    await Future<void>.delayed(ms(50));
    expect(failureOf(await request()), isA<CaptureBusy>());
    final result = await first;
    expect(result, isA<CaptureSuccess>());
    expect(registry.liveCount, 1);
    (result as CaptureSuccess).frame.release();
    expect(registry.liveCount, 0);
  });

  test('caller isolate keeps ticking during a 3 s native hold', () async {
    hold();
    releaseAfter(const Duration(seconds: 3));
    var ticks = 0;
    final timer = Timer.periodic(ms(10), (_) => ticks++);
    final result = await request();
    expect(failureOf(result), isA<CaptureTimeout>());
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    timer.cancel();
    // 10 ms ticks over about 3 s: far more than a blocked isolate would see.
    expect(ticks, greaterThan(150));
    await eventually(() => registry.effectiveReleases == 1);
    expect(registry.liveCount, 0);
  });

  test('overrun times out stays busy and releases late frame', () async {
    hold();
    releaseAfter(const Duration(seconds: 2));
    final clock = Stopwatch()..start();
    final result = await request();
    final timedOut = clock.elapsedMilliseconds;
    expect(failureOf(result), isA<CaptureTimeout>());
    expect(timedOut, inInclusiveRange(400, 1500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(failureOf(await request()), isA<CaptureBusy>());
    await eventually(() => registry.effectiveReleases == 1);
    expect(registry.liveCount, 0);
  });

  test('request admitted after late reply', () async {
    hold();
    releaseAfter(const Duration(seconds: 1));
    expect(failureOf(await request()), isA<CaptureTimeout>());
    await eventually(() => registry.effectiveReleases == 1);
    expect(registry.liveCount, 0);
    final next = await request();
    expect(next, isA<CaptureSuccess>());
    (next as CaptureSuccess).frame.release();
    expect(registry.liveCount, 0);
  });

  test('close while idle exits worker and refuses later captures', () async {
    final first = await request();
    (first as CaptureSuccess).frame.release();
    expect(service.workerRunning, isTrue);
    expect(await service.close(), isNull);
    await service.workerExit.timeout(const Duration(seconds: 5));
    expect(service.workerRunning, isFalse);
    expect(failureOf(await request()), isA<CaptureClosed>());
    expect(registry.liveCount, 0);
  });

  test('close during capture returns captureClosed and releases', () async {
    hold();
    releaseAfter(ms(300));
    final active = request();
    await Future<void>.delayed(ms(50));
    final closing = service.close();
    expect(failureOf(await active), isA<CaptureClosed>());
    expect(await closing, isNull);
    await eventually(() => registry.effectiveReleases == 1);
    expect(registry.liveCount, 0);
    expect(failureOf(await request()), isA<CaptureClosed>());
  });

  test('close reports shutdownIncomplete after 2 s without killing', () async {
    hold();
    expect(failureOf(await request()), isA<CaptureTimeout>());
    final clock = Stopwatch()..start();
    final outcome = await service.close();
    expect(outcome, isA<ShutdownIncomplete>());
    expect(clock.elapsedMilliseconds, inInclusiveRange(1800, 3500));
    expect(service.workerRunning, isTrue);
    expect(failureOf(await request()), isA<CaptureClosed>());
    // Let the call finish so the worker can exit (tearDown also releases).
    control[holdSlot] = 0;
    await service.workerExit.timeout(const Duration(seconds: 5));
  });

  test('frame after shutdownIncomplete is released', () async {
    final before = registry.liveCount;
    hold();
    expect(failureOf(await request()), isA<CaptureTimeout>());
    expect(await service.close(), isA<ShutdownIncomplete>());
    control[holdSlot] = 0;
    await service.workerExit.timeout(const Duration(seconds: 5));
    expect(registry.liveCount, before);
    expect(registry.effectiveReleases, 1);
  });

  test('ticket reply in unavailable state is released', () async {
    hold();
    releaseAfter(ms(600));
    final active = request();
    await Future<void>.delayed(ms(100));
    service.debugReportWorkerError('crafted worker error');
    final result = failureOf(await active);
    expect(result, isA<CaptureUnavailable>());
    expect((result as CaptureUnavailable).reason, contains('crafted'));
    // The worker still finishes the call and replies with a ticket.
    await eventually(() => registry.effectiveReleases == 1);
    expect(registry.liveCount, 0);
    expect(failureOf(await request()), isA<CaptureUnavailable>());
  });

  test(
    'worker that cannot open the platform makes the service unavailable',
    () async {
      final broken = makeService(factory: failingFactory);
      final result = failureOf(
        await broken.capture(holdableTrigger, CaptureMode.targeted),
      );
      expect(result, isA<CaptureUnavailable>());
      expect((result as CaptureUnavailable).reason, contains('cannot open'));
      expect(
        failureOf(await broken.capture(holdableTrigger, CaptureMode.targeted)),
        isA<CaptureUnavailable>(),
      );
      expect(await broken.close(), isNull);
    },
  );

  test(
    'caller registry that cannot open refuses before any frame exists',
    () async {
      final broken = CaptureService(
        platformFactory: holdableFactory(registry.address, control.address),
        registryFactory: () => throw StateError('binding changed'),
      );
      services.add(broken);
      final result = failureOf(
        await broken.capture(holdableTrigger, CaptureMode.targeted),
      );
      expect(result, isA<CaptureUnavailable>());
      expect(
        (result as CaptureUnavailable).reason,
        contains('binding changed'),
      );
      // No worker was spawned, so no frame could be produced and leaked.
      expect(broken.workerRunning, isFalse);
      expect(registry.liveCount, 0);
      expect(
        failureOf(await broken.capture(holdableTrigger, CaptureMode.targeted)),
        isA<CaptureUnavailable>(),
      );
    },
  );
}
