import 'dart:async';
import 'dart:io';

import 'package:blackgrid/data/scan_frame_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

RecordedScan _scan(String id) => RecordedScan(
  id: id,
  clientWidth: 100,
  clientHeight: 50,
  kind: RecordedScanKind.fullClient,
  outcome: RecordedOutcome.rejected,
);

/// A writer whose answers the test delivers by hand.
class _FakeWriter implements ScanFrameWriter {
  _FakeWriter(this.folder, this.token, this.onAnswer);

  final String folder;
  final int token;
  final void Function(ScanFrameWriterAnswer) onAnswer;
  final List<RecordedScan> scans = [];
  int kills = 0;

  @override
  void write(RecordedScan scan) => scans.add(scan);

  @override
  void kill() => kills++;

  void ack(int index) => onAnswer(ScanFrameAck(token, scans[index].id));
}

void main() {
  late Directory temp;
  late String root;
  late DateTime now;
  late List<_FakeWriter> writers;
  Completer<void>? gate;
  late Completer<void> spawning;
  late ScanFrameRecorder recorder;

  ScanFrameRecorder build({String? at}) => ScanFrameRecorder(
    root: at ?? root,
    clock: () => now,
    writerFactory:
        ({required folder, required token, required onAnswer}) async {
          if (!spawning.isCompleted) spawning.complete();
          await gate?.future;
          final writer = _FakeWriter(folder, token, onAnswer);
          writers.add(writer);
          return writer;
        },
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('scan_frame_recorder_test');
    root = '${temp.path}/scan-frames';
    now = DateTime(2026, 10, 10, 14, 3, 7);
    writers = [];
    gate = null;
    spawning = Completer<void>();
    recorder = build();
  });

  tearDown(() async {
    await recorder.close(timeout: Duration.zero);
    temp.deleteSync(recursive: true);
  });

  int sessionFolders() =>
      Directory(root).existsSync() ? Directory(root).listSync().length : 0;

  test('start creates the session folder named by local start time', () async {
    expect(recorder.status.value.state, ScanRecordingState.off);

    expect(await recorder.start(), isTrue);

    final folder = '$root${Platform.pathSeparator}20261010-140307';
    expect(Directory(folder).existsSync(), isTrue);
    expect(recorder.status.value.state, ScanRecordingState.on);
    expect(recorder.status.value.folder, folder);
    expect(writers.single.folder, folder);
  });

  test('a second start in the same second uses the -2 suffix', () async {
    await recorder.start();
    recorder.stop();
    expect(recorder.status.value.state, ScanRecordingState.off);

    expect(await recorder.start(), isTrue);

    expect(
      recorder.status.value.folder,
      '$root${Platform.pathSeparator}20261010-140307-2',
    );
    expect(
      Directory('$root${Platform.pathSeparator}20261010-140307').existsSync(),
      isTrue,
    );
    expect(
      Directory('$root${Platform.pathSeparator}20261010-140307-2').existsSync(),
      isTrue,
    );
  });

  test(
    'two recorders starting in the same second get different folders',
    () async {
      final first = build();
      final second = build();
      addTearDown(() async {
        await first.close(timeout: Duration.zero);
        await second.close(timeout: Duration.zero);
      });

      final results = await Future.wait([first.start(), second.start()]);

      expect(results, [true, true]);
      expect(first.status.value.folder, isNot(second.status.value.folder));
      expect(sessionFolders(), 2);
    },
  );

  test('folder creation failure leaves recording off with the error', () async {
    File(root)
      ..createSync(recursive: true)
      ..writeAsStringSync('not a directory');

    expect(await recorder.start(), isFalse);

    final status = recorder.status.value;
    expect(status.state, ScanRecordingState.off);
    expect(status.stopReason, isA<ScanRecordingStartFailed>());
    expect(writers, isEmpty);
    expect(recorder.record(_scan('a')), ScanRecordResult.refused);
  });

  test('stop during starting ends off and kills the late writer', () async {
    gate = Completer<void>();
    final started = recorder.start();
    await spawning.future;
    expect(recorder.status.value.state, ScanRecordingState.starting);

    recorder.stop();
    expect(recorder.status.value.state, ScanRecordingState.off);
    gate!.complete();

    expect(await started, isFalse);
    expect(recorder.status.value.state, ScanRecordingState.off);
    expect(writers.single.kills, 1);
    expect(recorder.record(_scan('a')), ScanRecordResult.refused);
    expect(writers.single.scans, isEmpty);
  });

  test('answers from an invalidated session are ignored', () async {
    gate = Completer<void>();
    final first = recorder.start();
    await spawning.future;
    recorder.stop();
    gate!.complete();
    await first;
    gate = null;

    await recorder.start();
    recorder.record(_scan('a'));
    // The first session's writer answers late, under its own token.
    writers.first.onAnswer(ScanFrameAck(writers.first.token, 'a'));
    writers.first.onAnswer(const ScanFrameWriterExited(1, 'old'));

    final status = recorder.status.value;
    expect(status.state, ScanRecordingState.on);
    expect(status.written, 0);
    expect(status.dropped, 0);
  });

  test('start while stopping is refused and creates no folder', () async {
    await recorder.start();
    recorder.record(_scan('a'));
    recorder.stop();
    expect(recorder.status.value.state, ScanRecordingState.stopping);
    expect(sessionFolders(), 1);

    expect(await recorder.start(), isFalse);

    expect(sessionFolders(), 1);
    expect(recorder.status.value.state, ScanRecordingState.stopping);
    expect(recorder.record(_scan('b')), ScanRecordResult.refused);
    // The outstanding scan still drains.
    writers.single.ack(0);
    expect(recorder.status.value.state, ScanRecordingState.off);
    expect(recorder.status.value.written, 1);
    expect(writers.single.kills, 1);
  });

  test('a new session after a drain starts with zero counts', () async {
    await recorder.start();
    for (var i = 0; i < 12; i++) {
      recorder.record(_scan('s$i'));
      writers.single.ack(i);
    }
    recorder.stop();
    expect(recorder.status.value.written, 12);
    expect(recorder.status.value.state, ScanRecordingState.off);

    await recorder.start();

    final status = recorder.status.value;
    expect(status.state, ScanRecordingState.on);
    expect(status.written, 0);
    expect(status.dropped, 0);
    expect(status.stopReason, isNull);
  });

  test('a third outstanding scan is dropped and counted', () async {
    await recorder.start();

    expect(recorder.record(_scan('a')), ScanRecordResult.handedOver);
    expect(recorder.record(_scan('b')), ScanRecordResult.handedOver);
    expect(recorder.record(_scan('c')), ScanRecordResult.dropped);

    expect(writers.single.scans.map((s) => s.id), ['a', 'b']);
    expect(recorder.status.value.dropped, 1);

    writers.single.ack(0);
    expect(recorder.status.value.written, 1);
    expect(recorder.record(_scan('d')), ScanRecordResult.handedOver);
    expect(recorder.status.value.dropped, 1);
  });

  test('drop counts a lost scan only while on', () async {
    recorder.drop();
    expect(recorder.status.value.dropped, 0);

    await recorder.start();
    recorder.drop();
    expect(recorder.status.value.dropped, 1);
    expect(writers.single.scans, isEmpty);
  });

  test(
    'the 500th hand-off stops intake and its ack turns recording off',
    () async {
      await recorder.start();
      for (var i = 0; i < ScanFrameRecorder.maxHandOffs - 1; i++) {
        expect(recorder.record(_scan('s$i')), ScanRecordResult.handedOver);
        writers.single.ack(i);
      }
      expect(recorder.status.value.state, ScanRecordingState.on);

      expect(recorder.record(_scan('last')), ScanRecordResult.handedOver);

      expect(recorder.status.value.state, ScanRecordingState.stopping);
      expect(recorder.record(_scan('over')), ScanRecordResult.refused);
      expect(writers.single.scans, hasLength(500));

      writers.single.ack(499);

      final status = recorder.status.value;
      expect(status.state, ScanRecordingState.off);
      expect(status.written, 500);
      expect(status.dropped, 0);
      expect(status.stopReason, isA<ScanRecordingCapReached>());
      expect(writers.single.kills, 1);
    },
  );

  group('a writer failure', () {
    test('turns recording off with the error', () async {
      await recorder.start();
      recorder.record(_scan('a'));
      recorder.record(_scan('b'));

      writers.single.onAnswer(ScanFrameFailure(1, 'a', 'disk full'));

      final status = recorder.status.value;
      expect(status.state, ScanRecordingState.off);
      expect(status.written, 0);
      // The failed scan has no line and is reported by the error; the scan
      // queued behind it is never written.
      expect(status.dropped, 1);
      expect(
        status.stopReason,
        isA<ScanRecordingWriteFailed>().having(
          (r) => r.error,
          'error',
          'disk full',
        ),
      );
      expect(status.folder, '$root${Platform.pathSeparator}20261010-140307');
      expect(writers.single.kills, 1);
      expect(recorder.record(_scan('c')), ScanRecordResult.refused);
    });

    test('during a drain ends the drain off with the error', () async {
      await recorder.start();
      recorder.record(_scan('a'));
      recorder.stop();

      writers.single.onAnswer(ScanFrameFailure(1, 'a', 'bad png'));

      expect(recorder.status.value.state, ScanRecordingState.off);
      expect(recorder.status.value.stopReason, isA<ScanRecordingWriteFailed>());
    });

    test(
      'is also a writer exit, which counts the outstanding as dropped',
      () async {
        await recorder.start();
        recorder.record(_scan('a'));
        recorder.record(_scan('b'));

        writers.single.onAnswer(const ScanFrameWriterExited(1, 'isolate died'));

        final status = recorder.status.value;
        expect(status.state, ScanRecordingState.off);
        expect(status.dropped, 2);
        expect(status.written, 0);
        expect(
          status.stopReason,
          isA<ScanRecordingWriteFailed>().having(
            (r) => r.error,
            'error',
            'isolate died',
          ),
        );
        expect(writers.single.kills, 1);
      },
    );
  });

  group('close', () {
    test('waits up to the timeout and ignores late acks', () async {
      await recorder.start();
      recorder.record(_scan('a'));

      await recorder.close(timeout: const Duration(milliseconds: 20));

      var status = recorder.status.value;
      expect(status.state, ScanRecordingState.off);
      expect(writers.single.kills, 1);
      final written = status.written;
      final dropped = status.dropped;

      writers.single.ack(0);
      status = recorder.status.value;
      expect(status.written, written);
      expect(status.dropped, dropped);
      expect(status.state, ScanRecordingState.off);
      expect(await recorder.start(), isFalse);
    });

    test('returns as soon as the outstanding scans are written', () async {
      await recorder.start();
      recorder.record(_scan('a'));

      final closing = recorder.close(timeout: const Duration(minutes: 5));
      writers.single.ack(0);
      await closing;

      expect(recorder.status.value.written, 1);
      expect(recorder.status.value.state, ScanRecordingState.off);
      expect(writers.single.kills, 1);
    });

    test('during starting kills the late writer, and is idempotent', () async {
      gate = Completer<void>();
      final started = recorder.start();
      await spawning.future;

      await recorder.close();
      gate!.complete();
      await started;
      await recorder.close();

      expect(writers.single.kills, 1);
      expect(recorder.status.value.state, ScanRecordingState.off);
    });
  });
}
