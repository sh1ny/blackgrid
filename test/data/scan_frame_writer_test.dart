import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:blackgrid/data/scan_frame_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _width = 8;
const _height = 4;
const _stride = 40; // 8 * 4 pixel bytes + 8 padding bytes.

/// An 8x4 BGRX frame whose pixel (x, y) is r = x * 30, g = y * 60, b = x + y,
/// with a garbage X byte and garbage row padding.
RecordedFrame _frame({bool clipped = false}) {
  final bytes = Uint8List(_stride * _height)
    ..fillRange(0, _stride * _height, 0xEE);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final o = y * _stride + x * 4;
      bytes[o] = x + y; // B
      bytes[o + 1] = y * 60; // G
      bytes[o + 2] = x * 30; // R
      bytes[o + 3] = 0x07; // undefined X byte, must not become alpha.
    }
  }
  return RecordedFrame(
    width: _width,
    height: _height,
    stride: _stride,
    pixels: TransferableTypedData.fromList([bytes]),
    clipped: clipped,
    capturedAtUtc: DateTime.utc(2026, 1, 2, 3, 4, 5),
    captured: (left: 3, top: 5, width: _width, height: _height),
  );
}

RecordedScan _scan(
  String id, {
  RecordedFrame? full,
  RecordedFrame? strip,
  RecordedScanKind kind = RecordedScanKind.targeted,
}) => RecordedScan(
  id: id,
  clientWidth: 1920,
  clientHeight: 1080,
  kind: kind,
  cursorX: kind == RecordedScanKind.fullClient ? null : 100,
  cursorY: kind == RecordedScanKind.fullClient ? null : 200,
  outcome: RecordedOutcome.accepted,
  acceptedId: 'item-1',
  text: 'Salewa',
  targetedMarkerScore: 0.9,
  full: full,
  strip: strip,
);

/// Top-level so it can be sent to the writer isolate.
ScanFrameFileOps _failingPngOps() => _FailingPngOps();

final class _FailingPngOps implements ScanFrameFileOps {
  final ScanFrameFileOps _real = defaultScanFrameFileOps();

  @override
  Future<void> createDirectory(String path) => _real.createDirectory(path);

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    if (path.endsWith('.png.tmp')) throw const FileSystemException('disk full');
    await _real.writeBytes(path, bytes);
  }

  @override
  Future<void> rename(String from, String to) => _real.rename(from, to);

  @override
  Future<void> appendBytes(String path, List<int> bytes) =>
      _real.appendBytes(path, bytes);
}

/// Collects answers and lets a test await the next one without sleeping.
final class _Answers {
  final Queue<ScanFrameWriterAnswer> _queue = Queue();
  Completer<void>? _waiting;

  void add(ScanFrameWriterAnswer answer) {
    _queue.add(answer);
    _waiting?.complete();
    _waiting = null;
  }

  Future<ScanFrameWriterAnswer> next() async {
    while (_queue.isEmpty) {
      final waiting = _waiting = Completer<void>();
      await waiting.future.timeout(const Duration(seconds: 30));
    }
    return _queue.removeFirst();
  }
}

void main() {
  group('scan frame line', () {
    test('serialises the D7 fields and never an expected field', () {
      final line = encodeScanFrameLine(
        _scan('s1', full: _frame(clipped: true), strip: _frame()),
      );
      final json = jsonDecode(line) as Map<String, Object?>;
      expect(json, {
        'v': 1,
        'id': 's1',
        'image': 's1-full.png',
        'client': {'width': 1920, 'height': 1080},
        'kind': 'targeted',
        'cursor': {'x': 100, 'y': 200},
        'captured': {'left': 3, 'top': 5, 'width': 8, 'height': 4},
        'clipped': true,
        'strip': 's1-targeted.png',
        'outcome': 'accepted',
        'acceptedId': 'item-1',
        'rejectReason': null,
        'failure': null,
        'fullFailure': null,
        'text': 'Salewa',
        'targetedMarkerScore': 0.9,
        'fallbackMarkerScore': null,
        'stripCapturedAtUtc': '2026-01-02T03:04:05.000Z',
        'fullCapturedAtUtc': '2026-01-02T03:04:05.000Z',
      });
      expect(json.containsKey('expected'), isFalse);
      expect(line.contains('\n'), isFalse);
    });

    test('omits cursor for fullClient and nulls missing frames', () {
      final json = jsonDecode(
        encodeScanFrameLine(_scan('s2', kind: RecordedScanKind.fullClient)),
      ) as Map<String, Object?>;
      expect(json.containsKey('cursor'), isFalse);
      expect(json['kind'], 'fullClient');
      for (final key in [
        'image',
        'captured',
        'clipped',
        'strip',
        'stripCapturedAtUtc',
        'fullCapturedAtUtc',
      ]) {
        expect(json.containsKey(key), isTrue, reason: key);
        expect(json[key], isNull, reason: key);
      }
    });
  });

  group('writer isolate', () {
    late Directory dir;
    late _Answers answers;
    ScanFrameWriter? writer;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('scan_frame_writer_test');
      answers = _Answers();
    });

    tearDown(() {
      writer?.kill();
      writer = null;
      dir.deleteSync(recursive: true);
    });

    Future<ScanFrameWriter> spawn({
      ScanFrameFileOps Function() fileOps = defaultScanFrameFileOps,
      int token = 7,
    }) async {
      final spawned = await IsolateScanFrameWriter.spawn(
        folder: dir.path,
        token: token,
        onAnswer: answers.add,
        fileOps: fileOps,
      );
      writer = spawned;
      return spawned;
    }

    test('writes an opaque RGB PNG without the X byte or padding', () async {
      final w = await spawn();
      w.write(_scan('a1', full: _frame(), strip: _frame()));
      expect(await answers.next(), isA<ScanFrameAck>());

      for (final name in ['a1-full.png', 'a1-targeted.png']) {
        final decoded = img.decodePng(
          File('${dir.path}/$name').readAsBytesSync(),
        )!;
        expect(decoded.width, _width);
        expect(decoded.height, _height);
        if (decoded.numChannels == 4) {
          expect(decoded.getPixel(0, 0).a, 255);
        } else {
          expect(decoded.numChannels, 3);
        }
        for (var y = 0; y < _height; y++) {
          for (var x = 0; x < _width; x++) {
            final p = decoded.getPixel(x, y);
            expect(
              [p.r, p.g, p.b],
              [x * 30, y * 60, x + y],
              reason: '$name pixel $x,$y',
            );
          }
        }
      }
    });

    test('appends the line after both PNGs exist', () async {
      final w = await spawn();
      w.write(_scan('b1', full: _frame(), strip: _frame()));
      w.write(_scan('b2', kind: RecordedScanKind.fullClient));
      expect(await answers.next(), isA<ScanFrameAck>());
      // The ack means the line is on disk and both PNGs are final.
      expect(File('${dir.path}/b1-full.png').existsSync(), isTrue);
      expect(File('${dir.path}/b1-targeted.png').existsSync(), isTrue);
      expect(File('${dir.path}/b1-full.png.tmp').existsSync(), isFalse);
      expect(File('${dir.path}/b1-targeted.png.tmp').existsSync(), isFalse);

      expect(await answers.next(), isA<ScanFrameAck>());
      final all = File('${dir.path}/frames.jsonl').readAsStringSync();
      expect(all.endsWith('\n'), isTrue);
      expect(
        all
            .trimRight()
            .split('\n')
            .map((l) => (jsonDecode(l) as Map<String, Object?>)['id']),
        ['b1', 'b2'],
      );
    });

    test('a failed PNG write leaves no line and no final PNG', () async {
      final w = await spawn(fileOps: _failingPngOps);
      w.write(_scan('c1', full: _frame(), strip: _frame()));
      final answer = await answers.next();
      expect(answer, isA<ScanFrameFailure>());
      expect((answer as ScanFrameFailure).id, 'c1');
      expect(answer.error, contains('disk full'));
      expect(File('${dir.path}/c1-full.png').existsSync(), isFalse);
      expect(File('${dir.path}/c1-targeted.png').existsSync(), isFalse);
      final lines = File('${dir.path}/frames.jsonl');
      expect(!lines.existsSync() || lines.readAsStringSync().isEmpty, isTrue);
    });

    test('answers carry the session token', () async {
      final ok = await spawn(token: 42);
      ok.write(_scan('d1', full: _frame()));
      expect((await answers.next()).token, 42);
      ok.kill();

      final failing = await spawn(fileOps: _failingPngOps, token: 43);
      failing.write(_scan('d2', full: _frame()));
      final failure = await answers.next();
      expect(failure, isA<ScanFrameFailure>());
      expect(failure.token, 43);
    });
  });
}
