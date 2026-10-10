import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/scan_timing_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory sink whose operations can be held or failed by the test.
class _FakeSink implements ScanTimingFileSink {
  final List<String> written = <String>[];
  int size = 0;
  int rotations = 0;

  /// When non-null, the next [append] waits for this completer.
  Completer<void>? hold;

  /// Signalled each time an append starts.
  Completer<void> appendStarted = Completer<void>();

  /// When non-null, [append] throws this instead of writing.
  Object? failWith;

  @override
  Future<int> length() async => size;

  @override
  Future<void> append(List<int> bytes) async {
    if (!appendStarted.isCompleted) appendStarted.complete();
    final gate = hold;
    if (gate != null) await gate.future;
    final error = failWith;
    if (error != null) throw error;
    written.add(utf8.decode(bytes));
    size += bytes.length;
  }

  @override
  Future<void> rotate() async {
    rotations++;
    size = 0;
  }
}

Map<String, Object?> _decode(String line) =>
    jsonDecode(line) as Map<String, Object?>;

void main() {
  group('ScanTimingLog', () {
    test('defaults are 1 MiB and 32 queued lines', () {
      expect(ScanTimingLog.defaultMaxBytes, 1024 * 1024);
      expect(ScanTimingLog.defaultMaxQueued, 32);
    });

    test('writes lines in order, one JSON object per line', () async {
      final sink = _FakeSink();
      final log = ScanTimingLog(Directory.systemTemp, sink: sink);
      for (var i = 0; i < 5; i++) {
        log.append({'v': 1, 'n': i});
      }
      await log.close();

      expect(sink.written, everyElement(endsWith('\n')));
      expect(sink.written.map((l) => _decode(l)['n']), [0, 1, 2, 3, 4]);
      expect(log.status.value, isA<ScanTimingAvailable>());
    });

    test('rotates before passing maxBytes', () async {
      final sink = _FakeSink();
      final log = ScanTimingLog(
        Directory.systemTemp,
        maxBytes: 100,
        sink: sink,
      );
      log.append({'v': 1, 'pad': 'a' * 40});
      log.append({'v': 1, 'pad': 'b' * 40});
      await log.close();

      expect(sink.written, hasLength(2));
      expect(sink.rotations, 1);
      expect(sink.size, utf8.encode(sink.written.last).length);
    });

    test('does not rotate while the line still fits', () async {
      final sink = _FakeSink();
      final log = ScanTimingLog(
        Directory.systemTemp,
        maxBytes: 1000,
        sink: sink,
      );
      log.append({'v': 1});
      log.append({'v': 1});
      await log.close();

      expect(sink.rotations, 0);
    });

    test(
      'rotation on disk keeps the old file as scan-timings.1.jsonl',
      () async {
        final dir = await Directory.systemTemp.createTemp('scan_timing_log_');
        addTearDown(() => dir.delete(recursive: true));
        final current = File('${dir.path}/scan-timings.jsonl');
        final previous = File('${dir.path}/scan-timings.1.jsonl');
        await current.writeAsString('x' * 90);
        await previous.writeAsString('older');

        final log = ScanTimingLog(dir, maxBytes: 100);
        log.append({'v': 1, 'pad': 'c' * 30});
        await log.close();

        expect(await previous.readAsString(), 'x' * 90);
        final lines = await current.readAsLines();
        expect(lines, hasLength(1));
        expect(_decode(lines.single)['pad'], 'c' * 30);
      },
    );

    test('stalled write queues 32 and counts drops', () async {
      final sink = _FakeSink()..hold = Completer<void>();
      final log = ScanTimingLog(Directory.systemTemp, sink: sink);

      log.append({'v': 1, 'n': -1});
      await sink.appendStarted.future;
      for (var i = 0; i < 40; i++) {
        log.append({'v': 1, 'n': i});
      }

      sink.hold!.complete();
      sink.hold = null;
      await log.close();

      // The held line, then 32 queued; the 8 overflow lines are gone.
      final lines = sink.written.map(_decode).toList();
      expect(lines, hasLength(1 + 32));
      expect(
        lines.map((l) => l['n']).skip(1),
        List<int>.generate(32, (i) => i),
      );
      expect(lines.first.containsKey('droppedLines'), isFalse);
    });

    test(
      'next line written after the queue drains reports the drops',
      () async {
        final sink = _FakeSink()..hold = Completer<void>();
        final log = ScanTimingLog(Directory.systemTemp, sink: sink);

        log.append({'v': 1, 'n': -1});
        await sink.appendStarted.future;
        for (var i = 0; i < 40; i++) {
          log.append({'v': 1, 'n': i});
        }
        sink.hold!.complete();
        sink.hold = null;
        await log.close();

        // Drops were counted while the queue was full; the first line written
        // after that carries the count and the count then resets.
        final lines = sink.written.map(_decode).toList();
        final withDrops = lines.where((l) => l.containsKey('droppedLines'));
        expect(withDrops, hasLength(1));
        expect(withDrops.single['droppedLines'], 8);

        final more = _FakeSink();
        final log2 = ScanTimingLog(Directory.systemTemp, sink: more);
        log2.append({'v': 1});
        await log2.close();
        expect(
          _decode(more.written.single).containsKey('droppedLines'),
          isFalse,
        );
      },
    );

    test('a line larger than maxBytes is dropped and counted', () async {
      for (final existing in [0, 10]) {
        final sink = _FakeSink()..size = existing;
        final log = ScanTimingLog(
          Directory.systemTemp,
          maxBytes: 100,
          sink: sink,
        );

        log.append({'v': 1, 'pad': 'x' * 200});
        log.append({'v': 1, 'n': 2});
        await log.close();

        expect(sink.rotations, 0, reason: 'existing $existing: no rotation');
        expect(sink.written, hasLength(1), reason: 'existing $existing');
        final line = _decode(sink.written.single);
        expect(line['n'], 2);
        expect(line['droppedLines'], 1);
      }
    });

    test('a line JSON cannot encode is dropped and counted', () async {
      final sink = _FakeSink();
      final log = ScanTimingLog(Directory.systemTemp, sink: sink);

      log.append({'v': 1, 'score': double.nan});
      log.append({'v': 1, 'n': 2});
      await log.close();

      expect(sink.written, hasLength(1));
      final line = _decode(sink.written.single);
      expect(line['n'], 2);
      expect(line['droppedLines'], 1);
      expect(log.status.value, isA<ScanTimingAvailable>());
    });

    test('a logs path that is a file is unavailable, not thrown', () async {
      final data = Directory.systemTemp.createTempSync('blackgrid-log-');
      addTearDown(() => data.deleteSync(recursive: true));
      final logs = Directory('${data.path}${Platform.pathSeparator}logs');
      File(logs.path).writeAsStringSync('x');
      final log = ScanTimingLog(logs);

      log.append({'v': 1});
      await log.close();

      expect(log.status.value, isA<ScanTimingUnavailable>());
    });

    test('open failure sets unavailable and later appends retry', () async {
      final sink = _FakeSink()..failWith = const FileSystemException('denied');
      final log = ScanTimingLog(Directory.systemTemp, sink: sink);
      var notified = 0;
      log.status.addListener(() => notified++);

      log.append({'v': 1, 'n': 1});
      await _settle(log);
      expect(
        log.status.value,
        isA<ScanTimingUnavailable>().having(
          (s) => s.error,
          'error',
          isA<FileSystemException>(),
        ),
      );
      expect(notified, 1);

      sink.failWith = null;
      log.append({'v': 1, 'n': 2});
      await log.close();

      expect(log.status.value, isA<ScanTimingAvailable>());
      expect(sink.written.map((l) => _decode(l)['n']), [2]);
    });

    test('close flushes what is queued', () async {
      final sink = _FakeSink();
      final log = ScanTimingLog(Directory.systemTemp, sink: sink);
      log.append({'v': 1, 'n': 1});
      log.append({'v': 1, 'n': 2});
      await log.close();

      expect(sink.written, hasLength(2));
    });

    test(
      'close gives up on a stalled write and ignores later appends',
      () async {
        final sink = _FakeSink()..hold = Completer<void>();
        final log = ScanTimingLog(
          Directory.systemTemp,
          sink: sink,
          closeTimeout: const Duration(milliseconds: 1),
        );
        log.append({'v': 1, 'n': 1});
        await sink.appendStarted.future;
        log.append({'v': 1, 'n': 2});

        await log.close();
        log.append({'v': 1, 'n': 3});
        sink.hold!.complete();
        sink.hold = null;
        await log.idle;

        expect(sink.written.map((l) => _decode(l)['n']), [1]);
      },
    );
  });
}

/// Waits for the write loop to go idle without closing the log.
Future<void> _settle(ScanTimingLog log) => log.idle;
