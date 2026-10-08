import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:blackgrid/data/vision/vision_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/clock_capture_platform.dart';
import 'support/holdable_vision_native.dart';

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

/// One service over a fresh fake runtime directory and control block.
final class Rig {
  Rig({
    List<VisionTemplate> templates = const [],
    Duration deadline = const Duration(milliseconds: 1500),
  }) : control = VisionControlBlock(),
       directory = createFakeRuntimeDirectory() {
    service = VisionService<int, Probe>(
      runtimeDirectory: directory.path,
      jobFactory: probeJob,
      templates: templates,
      opener: holdableVisionOpener(control.address),
      platformFactory: clockPlatformFactory(control.address),
      qpcNow: control.clock.now,
      deadline: deadline,
    );
  }

  final VisionControlBlock control;
  final Directory directory;
  late final VisionService<int, Probe> service;

  File get model =>
      File('${directory.path}/data/vision/tessdata/eng.traineddata');

  Future<void> dispose() async {
    await service.close();
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
  });
}
