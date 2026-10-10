import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_service.dart'
    show FrameRegistryFactory;
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:blackgrid/data/vision/vision_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../capture/support/fake_capture_platform.dart';
import 'support/clock_capture_platform.dart';
import 'support/holdable_vision_native.dart';
import 'support/shared_frame_registry.dart';

/// What the probe job reports: the isolate it ran in, the recognised text and
/// the template bytes it saw. All plain sendable data.
typedef Probe = ({
  String isolate,
  String text,
  Map<String, List<int>> templates,
});

final class _ProbeJob implements VisionJob<int, Probe> {
  const _ProbeJob();

  @override
  Probe run(VisionJobContext context, VisionJobInput input, int params) {
    final text = input.withImage(
      (image) => switch (context.recognise(image)) {
        VisionOk(:final value) => value.text,
        VisionFailed(:final failure) => failure.message,
      },
    );
    return (
      isolate: Isolate.current.debugName ?? '',
      text: text,
      templates: {
        for (final entry in context.templates.entries)
          entry.key: entry.value.image.bytes.toList(),
      },
    );
  }
}

/// Top-level so it can be sent to the worker at spawn.
VisionJob<int, Probe> probeJob() => const _ProbeJob();

/// Modes of [_ScriptedJob], chosen by the request parameter.
const scriptOk = 1;
const scriptThrow = 2;
const scriptAbortOnFailure = 3;

/// Runs the native call (held by the control block), then ends the worker
/// isolate without releasing the frame or replying.
const scriptHoldThenDie = 4;

/// A job that behaves as scripted by its parameter: [scriptOk] recognises,
/// [scriptThrow] throws, [scriptAbortOnFailure] recognises and aborts with the
/// typed failure when the native operation fails (the contract the real jobs
/// follow).
final class _ScriptedJob implements VisionJob<int, Probe> {
  const _ScriptedJob();

  @override
  Probe run(VisionJobContext context, VisionJobInput input, int params) {
    if (params == scriptThrow) throw StateError('boom');
    final text = input.withImage(
      (image) => switch (context.recognise(image)) {
        VisionOk() when params == scriptHoldThenDie => Isolate.exit(),
        VisionOk(:final value) => value.text,
        VisionFailed(:final failure) when params == scriptAbortOnFailure =>
          throw VisionJobAbort(failure),
        VisionFailed(:final failure) => failure.message,
      },
    );
    return (isolate: '', text: text, templates: const {});
  }
}

/// Top-level so it can be sent to the worker at spawn.
VisionJob<int, Probe> scriptedJob() => const _ScriptedJob();

/// Returns a value that cannot cross the isolate boundary.
final class _UnsendableJob implements VisionJob<int, Object?> {
  const _UnsendableJob();

  @override
  Object? run(VisionJobContext context, VisionJobInput input, int params) {
    if (params != scriptOk) return 'sendable';
    final port = RawReceivePort();
    port.close();
    return port;
  }
}

VisionJob<int, Object?> unsendableJob() => const _UnsendableJob();

/// Answers `'ran'` for any parameters it is given.
final class _EchoJob implements VisionJob<Object?, Object?> {
  const _EchoJob();

  @override
  Object? run(VisionJobContext context, VisionJobInput input, Object? params) =>
      'ran';
}

VisionJob<Object?, Object?> echoJob() => const _EchoJob();

/// A job factory that fails in the worker, after the runtime opened.
VisionJob<int, Probe> throwingJobFactory() => throw StateError('no job');

/// The shared registry at [address], except inside the worker isolate, where
/// it throws: the worker then dies of an uncaught error while adopting its
/// first frame, before it can release it.
FrameRegistryFactory workerFailingRegistryFactory(int address) => () {
  if (Isolate.current.debugName == 'bgv_worker') {
    throw StateError('no registry in the worker');
  }
  return FakeFrameRegistry.fromAddress(address);
};

VisionImage sample() =>
    VisionImage(Uint8List(16), width: 4, height: 4, stride: 4, channels: 1);

VisionTemplate template(String name, {int seed = 1}) => VisionTemplate(
  name,
  VisionImage(
    Uint8List.fromList([for (var i = 0; i < 16; i++) i * 10 + seed]),
    width: 4,
    height: 4,
    stride: 4,
    channels: 1,
  ),
);

CaptureFrameMetadata frameMetadata() => CaptureFrameMetadata(
  width: 4,
  height: 4,
  stride: 16,
  desktopLeft: 0,
  desktopTop: 0,
  requested: CaptureRect(0, 0, 4, 4),
  captured: CaptureRect(0, 0, 4, 4),
  clipped: false,
  clientWidth: 1920,
  clientHeight: 1080,
  dpi: 96,
  hwnd: 1,
  pid: 2,
  tid: 3,
  exeName: 'EscapeFromTarkov.exe',
  qpcBefore: 10,
  qpcAfter: 20,
  capturedAtUtc: DateTime.utc(2026, 10, 9),
  requestId: 1,
);

/// Submits [frame] to a service that is dropped on return. Separate from the
/// test body so no local keeps the service reachable.
void submitAndDrop(Rig rig, FrameRegistry registry) {
  final frame = CaptureFrame(
    rig.frames.createFrame(4, 4),
    frameMetadata(),
    registry,
  );
  unawaited(rig.newService().submitFrame(frame, 1));
}

/// Starts a new service on [rig], leaves a held job running in its worker and
/// drops the service. Separate from the test body so no local keeps the
/// service reachable; the weak reference tells the test when it is collected.
Future<WeakReference<Object>> startSubmitAndDrop(Rig rig) async {
  final service = rig.newService();
  expect(await service.start(), isNull);
  rig.control.held = true;
  unawaited(service.submit(sample(), 1));
  await eventually(() => rig.control.concurrent == 1);
  return WeakReference(service);
}

/// One service over a fresh fake runtime directory and control block.
final class Rig {
  Rig({
    this._templates = const [],
    this._deadline = const Duration(milliseconds: 1500),
    this._closeDrain = const Duration(seconds: 5),
    this._jobFactory = probeJob,
  }) : control = VisionControlBlock(),
       directory = createFakeRuntimeDirectory(),
       frames = FakeFrameRegistry.create() {
    // Built now: the service copies its templates at construction.
    service = newService();
  }

  final List<VisionTemplate> _templates;
  final Duration _deadline;
  final Duration _closeDrain;
  final VisionJobFactory<int, Probe> _jobFactory;
  final VisionControlBlock control;
  final Directory directory;

  /// The frame slots shared with the worker isolate.
  final FakeFrameRegistry frames;
  late final VisionService<int, Probe> service;

  VisionService<int, Probe> newService() => VisionService<int, Probe>(
    runtimeDirectory: directory.path,
    jobFactory: _jobFactory,
    templates: _templates,
    opener: holdableVisionOpener(control.address),
    platformFactory: clockPlatformFactory(control.address),
    registryFactory: sharedFrameRegistryFactory(frames.address),
    qpcNow: control.clock.now,
    deadline: _deadline,
    closeDrain: _closeDrain,
  );

  /// A live frame owned by the caller, 4x4 BGRX.
  CaptureFrame newFrame() =>
      CaptureFrame(frames.createFrame(4, 4), frameMetadata(), frames);

  File get model =>
      File('${directory.path}/data/vision/tessdata/eng.traineddata');

  Future<void> dispose() async {
    await service.close();
    // Every frame this rig made is released on every outcome.
    expect(frames.liveCount, 0, reason: 'live frames at teardown');
    control.free();
    directory.deleteSync(recursive: true);
  }
}

void main() {
  test(
    'warm start opens the runtime once in the worker and reuses one engine',
    () async {
      final rig = Rig(templates: [template('a'), template('b', seed: 2)]);
      addTearDown(rig.dispose);

      expect(rig.service.state, VisionServiceState.idle);
      expect(await rig.service.start(), isNull);
      expect(rig.service.state, VisionServiceState.ready);
      expect(rig.control.openCount, 1);
      expect(rig.control.engineDisposeCount, 0);

      for (var i = 0; i < 3; i++) {
        final answer = await rig.service.submit(sample(), i);
        expect(answer, isA<VisionDelivered<Probe>>());
        final delivered = answer as VisionDelivered<Probe>;
        expect(delivered.result.isolate, 'bgv_worker');
        expect(delivered.result.text, 'hello');
        expect(delivered.result.templates.keys, unorderedEquals(['a', 'b']));
        expect(delivered.submittedQpc, lessThan(delivered.startedQpc));
        expect(delivered.startedQpc, lessThan(delivered.finishedQpc));
      }

      expect(rig.control.operationCount, 3);
      expect(rig.control.openCount, 1);
      expect(rig.control.engineDisposeCount, 0);
      expect(rig.service.state, VisionServiceState.ready);
      expect(Isolate.current.debugName, isNot('bgv_worker'));
    },
  );

  test('runtime failure at start makes the service unavailable without '
      'respawn', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    rig.model.deleteSync();

    final failure = await rig.service.start();
    expect(
      failure,
      isA<VisionRuntimeStartFailure>().having(
        (f) => f.failure,
        'failure',
        isA<VisionMissingFile>().having(
          (m) => m.path,
          'path',
          endsWith('eng.traineddata'),
        ),
      ),
    );
    expect(rig.service.state, VisionServiceState.unavailable);

    final answer = await rig.service.submit(sample(), 0);
    expect(
      answer,
      isA<VisionUnavailableAnswer<Probe>>().having(
        (a) => a.failure,
        'failure',
        isA<VisionMissingFile>(),
      ),
    );
    expect(rig.control.operationCount, 0);

    // Repair the bundle: a respawn would now succeed and open the runtime.
    rig.model.writeAsStringSync(
      'content of data/vision/tessdata/eng.traineddata',
    );
    await rig.service.workerExit;
    expect(rig.service.workerRunning, isFalse);
    expect(
      await rig.service.submit(sample(), 1),
      isA<VisionUnavailableAnswer>(),
    );
    expect(rig.service.state, VisionServiceState.unavailable);
    expect(rig.control.openCount, 0);
    expect(rig.control.operationCount, 0);
  });

  test('a throwing job factory fails start and disposes the runtime', () async {
    final rig = Rig(jobFactory: throwingJobFactory);
    addTearDown(rig.dispose);

    final failure = await rig.service.start();

    expect(
      failure,
      isA<VisionWorkerStartFailure>().having(
        (f) => f.message,
        'message',
        contains('job factory failed'),
      ),
    );
    expect(rig.service.state, VisionServiceState.unavailable);
    await rig.service.workerExit;
    expect(rig.control.engineDisposeCount, 1);
    expect(rig.control.nativeCloseCount, 1);
  });

  test('invalid or zero-variance template fails start with invalidTemplate and '
      'disposes the runtime', () async {
    final flat = VisionTemplate(
      'flat',
      VisionImage(
        Uint8List.fromList(List.filled(16, 7)),
        width: 4,
        height: 4,
        stride: 4,
        channels: 1,
      ),
    );
    final short = VisionTemplate(
      'short',
      VisionImage(Uint8List(8), width: 4, height: 4, stride: 4, channels: 1),
    );
    final colour = VisionTemplate(
      'colour',
      VisionImage(
        Uint8List.fromList([for (var i = 0; i < 48; i++) i]),
        width: 4,
        height: 4,
        stride: 12,
        channels: 3,
      ),
    );

    for (final bad in [flat, short, colour]) {
      final rig = Rig(templates: [template('good'), bad]);
      addTearDown(rig.dispose);

      final failure = await rig.service.start();
      expect(
        failure,
        isA<VisionInvalidTemplateStart>().having(
          (f) => f.name,
          'name',
          bad.name,
        ),
        reason: bad.name,
      );
      expect(rig.service.state, VisionServiceState.unavailable);
      await rig.service.workerExit;
      expect(rig.control.openCount, 1, reason: bad.name);
      expect(rig.control.engineDisposeCount, 1, reason: bad.name);
      expect(rig.control.nativeCloseCount, 1, reason: bad.name);

      final answer = await rig.service.submit(sample(), 0);
      expect(answer, isA<VisionUnavailableAnswer<Probe>>(), reason: bad.name);
      expect(rig.control.operationCount, 0, reason: bad.name);
    }
  });

  test('templates are copied at construction', () async {
    final original = template('a');
    final bytes = original.image.bytes;
    final expected = bytes.toList();
    final rig = Rig(templates: [original]);
    addTearDown(rig.dispose);

    bytes.fillRange(0, bytes.length, 0xff);

    expect(await rig.service.start(), isNull);
    bytes.fillRange(0, bytes.length, 0);
    final answer = await rig.service.submit(sample(), 0);

    expect(answer, isA<VisionDelivered<Probe>>());
    expect((answer as VisionDelivered<Probe>).result.templates['a'], expected);
  });

  group('admission', () {
    late Rig rig;

    setUp(() async {
      rig = Rig(deadline: const Duration(milliseconds: 150));
      addTearDown(rig.dispose);
      expect(await rig.service.start(), isNull);
    });

    // Released first, so a failing test never leaves the worker spinning when
    // dispose waits for it.
    tearDown(() => rig.control.held = false);

    test(
      'second job does not start while the first native call is held',
      () async {
        rig.control.held = true;
        final first = rig.service.submit(sample(), 1);
        await eventually(() => rig.control.concurrent == 1);
        final second = rig.service.submit(sample(), 2);

        expect(rig.control.operationCount, 1);
        expect(rig.control.concurrent, 1);

        rig.control.held = false;
        final a = await first as VisionDelivered<Probe>;
        final b = await second as VisionDelivered<Probe>;

        expect(rig.control.operationCount, 2);
        expect(rig.control.maxConcurrent, 1);
        expect(b.startedQpc, greaterThanOrEqualTo(a.finishedQpc));
      },
    );

    test('pending request runs after the active one', () async {
      rig.control.held = true;
      final order = <int>[];
      final first = rig.service.submit(sample(), 1)..then((_) => order.add(1));
      await eventually(() => rig.control.concurrent == 1);
      final second = rig.service.submit(sample(), 2)..then((_) => order.add(2));
      expect(rig.service.state, VisionServiceState.active);

      rig.control.held = false;
      expect(await first, isA<VisionDelivered<Probe>>());
      expect(await second, isA<VisionDelivered<Probe>>());

      expect(order, [1, 2]);
      expect(rig.control.operationCount, 2);
      expect(rig.control.maxConcurrent, 1);
    });

    test('newer request supersedes the pending one at once', () async {
      rig.control.held = true;
      final first = rig.service.submit(sample(), 1);
      await eventually(() => rig.control.concurrent == 1);
      final second = rig.service.submit(sample(), 2);
      final third = rig.service.submit(sample(), 3);

      // Answered while the first native call is still held.
      expect(await second, isA<VisionSuperseded<Probe>>());
      expect(rig.control.concurrent, 1);

      rig.control.held = false;
      expect(await first, isA<VisionDelivered<Probe>>());
      expect(await third, isA<VisionDelivered<Probe>>());
      expect(rig.control.operationCount, 2);
      expect(rig.control.maxConcurrent, 1);
    });

    test('deadline never starts a second native call', () async {
      rig.control.held = true;
      final first = rig.service.submit(sample(), 1);
      await eventually(() => rig.control.concurrent == 1);

      // The deadline passes while the native call is still held.
      expect(await first, isA<VisionDeadlineExceeded<Probe>>());
      expect(rig.service.state, VisionServiceState.overrun);
      expect(rig.control.concurrent, 1);

      // A pending request that expires never runs.
      expect(
        await rig.service.submit(sample(), 2),
        isA<VisionDeadlineExceeded<Probe>>(),
      );
      expect(rig.control.operationCount, 1);

      // A fresh request waits for the held call, then runs alone.
      final third = rig.service.submit(sample(), 3);
      rig.control.held = false;
      expect(await third, isA<VisionDelivered<Probe>>());
      expect(rig.control.operationCount, 2);
      expect(rig.control.maxConcurrent, 1);
    });
  });

  group('generations and deadlines', () {
    late Rig rig;

    setUp(() async {
      rig = Rig(deadline: const Duration(milliseconds: 150));
      addTearDown(rig.dispose);
      expect(await rig.service.start(), isNull);
    });

    tearDown(() => rig.control.held = false);

    test('current-generation result is delivered', () async {
      // A generation advanced before submission is the current one.
      rig.service.invalidate();
      rig.control.held = true;
      final request = rig.service.submit(sample(), 1);
      await eventually(() => rig.control.concurrent == 1);
      rig.control.held = false;

      expect(await request, isA<VisionDelivered<Probe>>());
      expect(rig.service.state, VisionServiceState.ready);
    });

    test('invalidate answers the active request at once and discards its '
        'late result', () async {
      rig.control.held = true;
      final answers = <VisionAnswer<Probe>>[];
      final first = rig.service.submit(sample(), 1)..then(answers.add);
      await eventually(() => rig.control.concurrent == 1);

      rig.service.invalidate();
      // Answered while the native call is still held.
      expect(await first, isA<VisionInvalidated<Probe>>());
      expect(rig.control.concurrent, 1);

      // A request submitted now outlives the first one's deadline, so by the
      // time it expires the first one's overrun timer has fired.
      final expired = await rig.service.submit(sample(), 2);
      expect(expired, isA<VisionDeadlineExceeded<Probe>>());
      expect(rig.service.state, VisionServiceState.overrun);
      expect(answers, hasLength(1), reason: 'no second answer for the first');
      expect(rig.control.operationCount, 1);

      // The call returns: the late result is discarded and the service
      // recovers to run the next request alone.
      final third = rig.service.submit(sample(), 3);
      rig.control.held = false;
      expect(await third, isA<VisionDelivered<Probe>>());
      expect(answers, hasLength(1));
      expect(rig.control.operationCount, 2);
      expect(rig.control.maxConcurrent, 1);
      expect(rig.service.state, VisionServiceState.ready);
    });

    test('invalidate answers the pending request without running it', () async {
      rig.control.held = true;
      final first = rig.service.submit(sample(), 1);
      await eventually(() => rig.control.concurrent == 1);
      final second = rig.service.submit(sample(), 2);

      rig.service.invalidate();
      expect(await second, isA<VisionInvalidated<Probe>>());
      expect(await first, isA<VisionInvalidated<Probe>>());
      expect(rig.control.operationCount, 1);

      final third = rig.service.submit(sample(), 3);
      rig.control.held = false;
      expect(await third, isA<VisionDelivered<Probe>>());
      // Only the first and third ever ran.
      expect(rig.control.operationCount, 2);
    });

    test('request within its deadline is delivered and the service is not '
        'overrun', () async {
      final fast = Rig();
      addTearDown(fast.dispose);
      expect(await fast.service.start(), isNull);

      final answer = await fast.service.submit(sample(), 1);

      expect(answer, isA<VisionDelivered<Probe>>());
      expect(fast.service.state, VisionServiceState.ready);
    });

    test('active request past its deadline answers visionTimeout and overruns '
        'until the call returns', () async {
      rig.control.held = true;
      final answers = <VisionAnswer<Probe>>[];
      final first = rig.service.submit(sample(), 1)..then(answers.add);
      await eventually(() => rig.control.concurrent == 1);

      expect(await first, isA<VisionDeadlineExceeded<Probe>>());
      expect(rig.service.state, VisionServiceState.overrun);
      expect(rig.control.concurrent, 1);

      final second = rig.service.submit(sample(), 2);
      rig.control.held = false;
      expect(await second, isA<VisionDelivered<Probe>>());
      expect(answers, hasLength(1), reason: 'late result is discarded');
      expect(rig.service.state, VisionServiceState.ready);
      expect(rig.control.operationCount, 2);
    });

    test('pending request that expires is answered visionTimeout and never '
        'runs', () async {
      rig.control.held = true;
      final first = rig.service.submit(sample(), 1);
      await eventually(() => rig.control.concurrent == 1);
      final second = rig.service.submit(sample(), 2);

      expect(await second, isA<VisionDeadlineExceeded<Probe>>());
      expect(await first, isA<VisionDeadlineExceeded<Probe>>());
      expect(rig.control.operationCount, 1);

      final third = rig.service.submit(sample(), 3);
      rig.control.held = false;
      expect(await third, isA<VisionDelivered<Probe>>());
      expect(rig.control.operationCount, 2);
    });
  });

  group('submission during warm start', () {
    test('requests submitted during warm start wait in the slots and their '
        'deadlines run from submission', () async {
      // Slots and supersession: the first request is held unsent, the second
      // pending, and a third replaces the second at once.
      final held = Rig();
      addTearDown(held.dispose);
      addTearDown(() => held.control.openHeld = false);
      held.control.openHeld = true;
      final first = held.service.submit(sample(), 1);
      final second = held.service.submit(sample(), 2);
      final third = held.service.submit(sample(), 3);

      expect(held.service.state, VisionServiceState.starting);
      expect(await second, isA<VisionSuperseded<Probe>>());
      expect(held.service.state, VisionServiceState.starting);

      held.control.openHeld = false;
      expect(await first, isA<VisionDelivered<Probe>>());
      expect(await third, isA<VisionDelivered<Probe>>());
      expect(held.control.operationCount, 2);

      // Deadlines: a slow start times the request out instead of hiding the
      // delay, and the expired request never runs.
      final slow = Rig(deadline: const Duration(milliseconds: 150));
      addTearDown(slow.dispose);
      addTearDown(() => slow.control.openHeld = false);
      slow.control.openHeld = true;
      final late = slow.service.submit(sample(), 1);

      expect(await late, isA<VisionDeadlineExceeded<Probe>>());
      expect(slow.service.state, VisionServiceState.starting);

      slow.control.openHeld = false;
      expect(await slow.service.start(), isNull);
      expect(slow.control.operationCount, 0);
    });

    test('pending request runs when the unsent one expired during warm '
        'start', () async {
      // The deadline runs from submission, so the two requests must be
      // submitted apart: the second still has half its deadline left when
      // the first expires.
      const deadline = Duration(milliseconds: 600);
      final rig = Rig(deadline: deadline);
      addTearDown(rig.dispose);
      addTearDown(() => rig.control.openHeld = false);
      rig.control.openHeld = true;
      final first = rig.service.submit(sample(), 1);
      final gap = Completer<void>();
      Timer(deadline ~/ 2, gap.complete);
      await gap.future;
      final second = rig.service.submit(sample(), 2);

      expect(await first, isA<VisionDeadlineExceeded<Probe>>());
      rig.control.openHeld = false;

      expect(await second, isA<VisionDelivered<Probe>>());
      expect(
        rig.control.operationCount,
        1,
        reason: 'the expired one never ran',
      );
      expect(rig.service.state, VisionServiceState.ready);
    });

    test('the survivor of an expired unsent request runs before a newer '
        'one', () async {
      const deadline = Duration(milliseconds: 600);
      final rig = Rig(deadline: deadline);
      addTearDown(rig.dispose);
      addTearDown(() => rig.control.openHeld = false);
      rig.control.openHeld = true;
      final first = rig.service.submit(sample(), 1);
      final gap = Completer<void>();
      Timer(deadline ~/ 2, gap.complete);
      await gap.future;
      final second = rig.service.submit(sample(), 2);
      expect(await first, isA<VisionDeadlineExceeded<Probe>>());

      // The survivor moved up into the unsent slot, so the newer request
      // waits behind it instead of running ahead of it.
      final third = rig.service.submit(sample(), 3);
      final order = <int>[];
      unawaited(second.then((_) => order.add(2)));
      unawaited(third.then((_) => order.add(3)));
      rig.control.openHeld = false;

      expect(await second, isA<VisionDelivered<Probe>>());
      expect(await third, isA<VisionDelivered<Probe>>());
      expect(order, [2, 3]);
      expect(rig.control.operationCount, 2);
      expect(rig.service.state, VisionServiceState.ready);
    });
  });

  group('input ownership', () {
    late Rig rig;

    setUp(() async {
      rig = Rig();
      addTearDown(rig.dispose);
      expect(await rig.service.start(), isNull);
    });

    tearDown(() => rig.control.held = false);

    test('frame input is released exactly once after success', () async {
      final frame = rig.newFrame();
      expect(rig.frames.liveCount, 1);

      final answer = await rig.service.submitFrame(frame, 1);

      expect(answer, isA<VisionDelivered<Probe>>());
      expect((answer as VisionDelivered<Probe>).result.text, 'hello');
      expect(rig.frames.effectiveReleases, 1);
      expect(rig.frames.liveCount, 0);
      expect(frame.isReleased, isTrue, reason: 'the submitter lost the frame');
    });

    test('superseded pending frame is released before the newer request is '
        'acknowledged', () async {
      rig.control.held = true;
      final first = rig.service.submit(sample(), 1);
      await eventually(() => rig.control.concurrent == 1);
      final older = rig.service.submitFrame(rig.newFrame(), 2);
      expect(rig.frames.liveCount, 1);

      final newer = rig.service.submitFrame(rig.newFrame(), 3);

      // Released by the time submit returns, while the native call is held.
      expect(rig.frames.effectiveReleases, 1);
      expect(rig.frames.liveCount, 1, reason: 'only the newer frame is held');
      expect(await older, isA<VisionSuperseded<Probe>>());
      expect(rig.control.concurrent, 1);

      rig.control.held = false;
      expect(await first, isA<VisionDelivered<Probe>>());
      expect(await newer, isA<VisionDelivered<Probe>>());
      expect(rig.frames.effectiveReleases, 2);
      expect(rig.frames.liveCount, 0);
    });

    test('malformed owned image is rejected at submit and keeps the pending '
        'request', () async {
      rig.control.held = true;
      final first = rig.service.submit(sample(), 1);
      await eventually(() => rig.control.concurrent == 1);
      final pendingFrame = rig.newFrame();
      final pending = rig.service.submitFrame(pendingFrame, 2);

      final malformed = VisionImage(
        Uint8List(16),
        width: 4,
        height: 4,
        stride: 2,
        channels: 1,
      );
      final answer = await rig.service.submit(malformed, 3);

      expect(answer, isA<VisionInvalidInput<Probe>>());
      expect(pendingFrame.isReleased, isFalse);
      expect(rig.frames.liveCount, 1, reason: 'the pending frame is kept');
      expect(rig.control.operationCount, 1, reason: 'no job ran');

      rig.control.held = false;
      expect(await first, isA<VisionDelivered<Probe>>());
      expect(await pending, isA<VisionDelivered<Probe>>());
      expect(rig.control.operationCount, 2);
      expect(rig.frames.liveCount, 0);
    });
  });

  group('input ownership on failure', () {
    late Rig rig;

    setUp(() {
      rig = Rig();
      addTearDown(rig.dispose);
    });

    test('worker error before the frame is released still releases it on '
        'exit', () async {
      final service = VisionService<int, Probe>(
        runtimeDirectory: rig.directory.path,
        jobFactory: probeJob,
        opener: holdableVisionOpener(rig.control.address),
        platformFactory: clockPlatformFactory(rig.control.address),
        registryFactory: workerFailingRegistryFactory(rig.frames.address),
        qpcNow: rig.control.clock.now,
      );
      addTearDown(service.close);
      expect(await service.start(), isNull);

      // The error reaches the service before the exit and answers the
      // request; the exit must still find the ticket to release.
      final answer = await service.submitFrame(rig.newFrame(), 1);
      expect(answer, isA<VisionUnavailableAnswer<Probe>>());
      await service.workerExit;
      expect(rig.frames.liveCount, 0, reason: 'sent frame released on exit');
      expect(rig.frames.effectiveReleases, 1);
      expect(service.state, VisionServiceState.unavailable);
      expect(rig.control.engineDisposeCount, 1, reason: 'runtime disposed');
      expect(rig.control.nativeCloseCount, 1);
    });

    test('unsendable parameters are answered invalidInput, the frame is '
        'released and the next request runs', () async {
      final service = VisionService<Object?, Object?>(
        runtimeDirectory: rig.directory.path,
        jobFactory: echoJob,
        opener: holdableVisionOpener(rig.control.address),
        platformFactory: clockPlatformFactory(rig.control.address),
        registryFactory: sharedFrameRegistryFactory(rig.frames.address),
        qpcNow: rig.control.clock.now,
      );
      addTearDown(service.close);
      final unsendable = RawReceivePort()..close();

      // Both wait through warm start: the unsendable one in the unsent slot,
      // the next one pending, so the failed send must start the pending one.
      final bad = service.submitFrame(rig.newFrame(), unsendable);
      final next = service.submitFrame(rig.newFrame(), 1);

      expect(
        await bad,
        isA<VisionInvalidInput<Object?>>().having(
          (a) => a.detail,
          'detail',
          contains('not sendable'),
        ),
      );
      final delivered = await next;
      expect(delivered, isA<VisionDelivered<Object?>>());
      expect((delivered as VisionDelivered<Object?>).result, 'ran');
      expect(rig.frames.liveCount, 0);
      expect(rig.frames.effectiveReleases, 2);
      expect(service.state, VisionServiceState.ready);
      expect(
        rig.control.operationCount,
        0,
        reason: 'the echo job is native-free',
      );
    });
  });

  group('job failures and timestamps', () {
    late Rig rig;

    setUp(() async {
      rig = Rig(jobFactory: scriptedJob);
      addTearDown(rig.dispose);
      expect(await rig.service.start(), isNull);
    });

    tearDown(() => rig.control.held = false);

    test('throwing job answers jobFailed and the worker stays ready', () async {
      final frame = rig.newFrame();
      final failed = await rig.service.submitFrame(frame, scriptThrow);

      expect(
        failed,
        isA<VisionJobFailed<Probe>>().having(
          (a) => a.description,
          'description',
          contains('boom'),
        ),
      );
      final timed = failed as VisionJobFailed<Probe>;
      expect(timed.submittedQpc, lessThanOrEqualTo(timed.startedQpc));
      expect(timed.startedQpc, lessThanOrEqualTo(timed.finishedQpc));
      expect(frame.isReleased, isTrue);
      expect(rig.frames.liveCount, 0, reason: 'input released');
      expect(rig.service.state, VisionServiceState.ready);

      // The next request runs on the same warm engine.
      final next = await rig.service.submit(sample(), scriptOk);
      expect(next, isA<VisionDelivered<Probe>>());
      expect((next as VisionDelivered<Probe>).result.text, 'hello');
      expect(rig.control.openCount, 1);
      expect(rig.control.engineDisposeCount, 0);
      expect(rig.control.nativeCloseCount, 0);
      expect(rig.service.state, VisionServiceState.ready);
    });

    test('native failure inside a job reaches the caller typed', () async {
      rig.control.nativeStatus = -3;
      final frame = rig.newFrame();
      final answer = await rig.service.submitFrame(frame, scriptAbortOnFailure);

      expect(answer, isNot(isA<VisionDelivered<Probe>>()));
      expect(
        answer,
        isA<VisionFailureAnswer<Probe>>().having(
          (a) => a.failure,
          'failure',
          isA<VisionNativeFailure>().having((f) => f.status, 'status', -3),
        ),
      );
      final typed = answer as VisionFailureAnswer<Probe>;
      expect(typed.submittedQpc, lessThanOrEqualTo(typed.startedQpc));
      expect(typed.startedQpc, lessThanOrEqualTo(typed.finishedQpc));
      expect(frame.isReleased, isTrue);
      expect(rig.frames.liveCount, 0);
      expect(rig.service.state, VisionServiceState.ready);

      // Once the native side recovers, the same worker succeeds.
      rig.control.nativeStatus = 0;
      expect(
        await rig.service.submit(sample(), scriptOk),
        isA<VisionDelivered<Probe>>(),
      );
      expect(rig.control.openCount, 1);
    });

    test(
      'completed answer reports ordered submit, start and end timestamps',
      () async {
        rig.control.held = true;
        final first = rig.service.submit(sample(), scriptOk);
        await eventually(() => rig.control.concurrent == 1);
        // Submitted while the first job runs, so it waits behind it.
        final second = rig.service.submit(sample(), scriptOk);
        rig.control.held = false;

        final a = await first as VisionDelivered<Probe>;
        final b = await second as VisionDelivered<Probe>;

        expect(a.submittedQpc, lessThanOrEqualTo(a.startedQpc));
        expect(a.startedQpc, lessThanOrEqualTo(a.finishedQpc));
        expect(b.submittedQpc, lessThanOrEqualTo(b.startedQpc));
        expect(b.startedQpc, lessThanOrEqualTo(b.finishedQpc));
        expect(b.submittedQpc, greaterThan(a.startedQpc));
        expect(b.startedQpc, greaterThanOrEqualTo(a.finishedQpc));
      },
    );

    test('superseded answer reports submission only', () async {
      rig.control.held = true;
      final first = rig.service.submit(sample(), scriptOk);
      await eventually(() => rig.control.concurrent == 1);

      // The worker is held inside a native call and does not read the clock,
      // so the submission time of the second request is exactly this value.
      rig.control.clock
        ..set(5000)
        ..setStep(0);
      final second = rig.service.submit(sample(), scriptOk);
      final third = rig.service.submit(sample(), scriptOk);

      final answer = await second;
      expect(answer, isA<VisionSuperseded<Probe>>());
      expect(answer, isA<VisionNotDelivered<Probe>>());
      expect(answer.submittedQpc, 5000);
      // The family carries no job start or end.
      expect(() => (answer as dynamic).startedQpc, throwsNoSuchMethodError);
      expect(() => (answer as dynamic).finishedQpc, throwsNoSuchMethodError);

      rig.control.held = false;
      expect(await first, isA<VisionDelivered<Probe>>());
      expect(await third, isA<VisionDelivered<Probe>>());
      expect(rig.control.operationCount, 2, reason: 'second never ran');
    });

    test('job returning a non-sendable result is answered jobFailed', () async {
      final service = VisionService<int, Object?>(
        runtimeDirectory: rig.directory.path,
        jobFactory: unsendableJob,
        opener: holdableVisionOpener(rig.control.address),
        platformFactory: clockPlatformFactory(rig.control.address),
        registryFactory: sharedFrameRegistryFactory(rig.frames.address),
        qpcNow: rig.control.clock.now,
      );
      addTearDown(service.close);
      expect(await service.start(), isNull);

      final frame = rig.newFrame();
      final answer = await service.submitFrame(frame, scriptOk);
      expect(
        answer,
        isA<VisionJobFailed<Object?>>().having(
          (a) => a.description,
          'description',
          contains('not sendable'),
        ),
      );
      expect(frame.isReleased, isTrue);
      expect(rig.frames.liveCount, 0);
      expect(service.state, VisionServiceState.ready);

      final next = await service.submit(sample(), scriptThrow);
      expect(next, isA<VisionDelivered<Object?>>());
      expect((next as VisionDelivered<Object?>).result, 'sendable');
    });
  });

  group('shutdown', () {
    late Rig rig;

    tearDown(() {
      rig.control.held = false;
      rig.control.openHeld = false;
    });

    test('close while idle disposes once and exits', () async {
      rig = Rig();
      addTearDown(rig.dispose);
      expect(await rig.service.start(), isNull);

      expect(await rig.service.close(), VisionCloseResult.closed);

      expect(rig.service.state, VisionServiceState.closed);
      expect(rig.service.workerRunning, isFalse);
      expect(rig.control.engineDisposeCount, 1);
      expect(rig.control.nativeCloseCount, 1);
      expect(await rig.service.submit(sample(), 1), isA<VisionClosed<Probe>>());
      final frame = rig.newFrame();
      expect(
        await rig.service.submitFrame(frame, 1),
        isA<VisionClosed<Probe>>(),
      );
      expect(frame.isReleased, isTrue);
      expect(await rig.service.close(), VisionCloseResult.closed);
      expect(rig.control.engineDisposeCount, 1);
    });

    test('close during warm start disposes the late-opened runtime and '
        'exits', () async {
      rig = Rig();
      addTearDown(rig.dispose);
      rig.control.openHeld = true;
      final frame = rig.newFrame();
      final request = rig.service.submitFrame(frame, 1);
      await eventually(() => rig.control.openCount == 1);
      expect(rig.service.state, VisionServiceState.starting);

      final closing = rig.service.close();
      expect(await request, isA<VisionClosed<Probe>>());
      expect(frame.isReleased, isTrue);
      expect(rig.frames.liveCount, 0);
      expect(rig.service.state, VisionServiceState.closing);
      expect(rig.control.engineDisposeCount, 0);

      rig.control.openHeld = false;
      expect(await closing, VisionCloseResult.closed);

      expect(rig.service.state, VisionServiceState.closed);
      expect(rig.service.workerRunning, isFalse);
      expect(rig.control.openCount, 1);
      expect(rig.control.engineDisposeCount, 1);
      expect(rig.control.nativeCloseCount, 1);
      expect(rig.control.operationCount, 0, reason: 'no job ran');
    });

    test('late OpenFailed during closing is ignored', () async {
      // A flat template makes the open fail after the held opener returns.
      final flat = VisionTemplate(
        'flat',
        VisionImage(
          Uint8List.fromList(List.filled(16, 7)),
          width: 4,
          height: 4,
          stride: 4,
          channels: 1,
        ),
      );
      rig = Rig(templates: [flat]);
      addTearDown(rig.dispose);
      rig.control.openHeld = true;
      final request = rig.service.submit(sample(), 1);
      await eventually(() => rig.control.openCount == 1);

      final closing = rig.service.close();
      expect(await request, isA<VisionClosed<Probe>>());
      rig.control.openHeld = false;

      expect(await closing, VisionCloseResult.closed);
      expect(rig.service.state, VisionServiceState.closed);
      expect(rig.service.unavailableReason, isNull);
      expect(rig.control.engineDisposeCount, 1, reason: 'worker disposed');
      expect(await rig.service.submit(sample(), 2), isA<VisionClosed<Probe>>());
    });

    test('close drains a call that returns within 2 s', () async {
      rig = Rig();
      addTearDown(rig.dispose);
      expect(await rig.service.start(), isNull);
      rig.control.held = true;
      final answers = <VisionAnswer<Probe>>[];
      final activeFrame = rig.newFrame();
      final active = rig.service.submitFrame(activeFrame, 1)..then(answers.add);
      await eventually(() => rig.control.concurrent == 1);
      final pendingFrame = rig.newFrame();
      final pending = rig.service.submitFrame(pendingFrame, 2)
        ..then(answers.add);

      final closing = rig.service.close();

      // Answered while the native call is still held.
      expect(await active, isA<VisionClosed<Probe>>());
      expect(await pending, isA<VisionClosed<Probe>>());
      expect(pendingFrame.isReleased, isTrue);
      expect(rig.service.state, VisionServiceState.closing);
      expect(rig.control.engineDisposeCount, 0, reason: 'call still running');

      rig.control.held = false;
      expect(await closing, VisionCloseResult.closed);

      expect(answers, hasLength(2), reason: 'late result not delivered');
      expect(rig.control.operationCount, 1, reason: 'pending never ran');
      expect(rig.control.engineDisposeCount, 1);
      expect(rig.control.nativeCloseCount, 1);
      expect(rig.service.workerRunning, isFalse);
      expect(rig.frames.liveCount, 0);
    });

    test('close reports shutdownIncomplete without disposing under a held '
        'call', () async {
      rig = Rig(closeDrain: const Duration(milliseconds: 100));
      addTearDown(rig.dispose);
      expect(await rig.service.start(), isNull);
      rig.control.held = true;
      final answers = <VisionAnswer<Probe>>[];
      final frame = rig.newFrame();
      final request = rig.service.submitFrame(frame, 1)..then(answers.add);
      await eventually(() => rig.control.concurrent == 1);

      expect(await rig.service.close(), VisionCloseResult.shutdownIncomplete);

      expect(await request, isA<VisionClosed<Probe>>());
      expect(rig.control.engineDisposeCount, 0);
      expect(rig.control.nativeCloseCount, 0);
      expect(rig.service.workerRunning, isTrue);
      expect(rig.control.concurrent, 1);
      expect(
        await rig.service.close(),
        VisionCloseResult.shutdownIncomplete,
        reason: 'repeated calls share one result',
      );

      // The call returns: the input is released, nothing is delivered, and the
      // worker then disposes and exits on its own.
      rig.control.held = false;
      await rig.service.workerExit;
      expect(answers, hasLength(1));
      expect(rig.frames.liveCount, 0);
      expect(rig.control.engineDisposeCount, 1);
      expect(rig.control.nativeCloseCount, 1);
    });

    test('worker exit answers outstanding requests unavailable and releases '
        'their frames', () async {
      rig = Rig(jobFactory: scriptedJob);
      addTearDown(rig.dispose);
      expect(await rig.service.start(), isNull);
      rig.control.held = true;
      final activeFrame = rig.newFrame();
      final active = rig.service.submitFrame(activeFrame, scriptHoldThenDie);
      await eventually(() => rig.control.concurrent == 1);
      final pendingFrame = rig.newFrame();
      final pending = rig.service.submitFrame(pendingFrame, scriptOk);
      expect(rig.frames.liveCount, 2);

      rig.control.held = false;

      expect(await active, isA<VisionUnavailableAnswer<Probe>>());
      expect(await pending, isA<VisionUnavailableAnswer<Probe>>());
      expect(rig.frames.liveCount, 0, reason: 'both frames released');
      expect(pendingFrame.isReleased, isTrue);
      expect(rig.service.state, VisionServiceState.unavailable);
      expect(rig.service.workerRunning, isFalse);

      final late = rig.newFrame();
      expect(
        await rig.service.submitFrame(late, scriptOk),
        isA<VisionUnavailableAnswer<Probe>>(),
      );
      expect(late.isReleased, isTrue);
      expect(rig.control.openCount, 1, reason: 'no respawn');
      expect(rig.frames.liveCount, 0);
    });
  });

  test('a service dropped while its job runs stops the worker on the '
      'reply', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    addTearDown(() => rig.control.held = false);

    final dropped = await startSubmitAndDrop(rig);
    await collectGarbageUntil(() => dropped.target == null);
    expect(dropped.target, isNull, reason: 'the service was collected');

    rig.control.held = false;
    await eventually(() => rig.control.nativeCloseCount == 1);
    expect(rig.control.engineDisposeCount, 1);
  });

  test('pending frame keeps its finalizer until it is sent', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    // The worker stays in the opener, so the frame stays unsent.
    rig.control.openHeld = true;
    addTearDown(() => rig.control.openHeld = false);
    final registry = FinalizingFrameRegistry(rig.frames);
    expect(rig.frames.liveCount, 0);

    submitAndDrop(rig, registry);
    expect(rig.frames.liveCount, 1);

    await collectGarbageUntil(() => rig.frames.liveCount == 0);

    expect(rig.frames.liveCount, 0);
    expect(rig.frames.effectiveReleases, 1);

    // The orphaned worker closes itself when it becomes ready.
    rig.control.openHeld = false;
    await eventually(() => rig.control.nativeCloseCount == 1);
  });
}
