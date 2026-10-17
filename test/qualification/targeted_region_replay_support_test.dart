import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/targeted_region_replay.dart';

/// Offline tests of the targeted-region replay's pure parts. No bundle, no
/// recording and no catalog are needed: every input is a synthetic line.

String _line({
  String id = 's-0001',
  Object? image = 's-0001-full.png',
  Object? client = const {'width': 1920, 'height': 1080},
  String kind = 'targeted',
  Object? cursor = const {'x': 500, 'y': 300},
  bool withCursor = true,
  Object? clipped = false,
  Object? v = 1,
  Map<String, Object?> extra = const {},
}) => jsonEncode({
  'v': v,
  'id': id,
  'image': image,
  'client': client,
  'kind': kind,
  if (withCursor) 'cursor': cursor,
  'captured': null,
  'clipped': clipped,
  'outcome': 'accepted',
  'acceptedId': 'hint-not-truth',
  ...extra,
});

ReplayFrameResult _result({
  String id = 'f',
  String? targeted,
  String? full,
  bool? inBand,
  int targetedMs = 10,
  int fullMs = 100,
}) => ReplayFrameResult(
  frameId: id,
  session: 'sess',
  band: const CaptureRect(520, 0, 1140, 600),
  targetedAccepted: targeted,
  fullClientAccepted: full,
  targetedRejectReason: targeted == null ? 'belowSimilarity' : null,
  fullClientRejectReason: full == null ? 'belowSimilarity' : null,
  targetedMs: targetedMs,
  fullClientMs: fullMs,
  fullWinnerInBand: inBand,
);

void main() {
  group('parseFramesJsonl', () {
    test('keeps a targeted line with an image and no clipping', () {
      final session = parseFramesJsonl('${_line()}\n');
      expect(session.frames, hasLength(1));
      final f = session.frames.single;
      expect(f.id, 's-0001');
      expect(f.image, 's-0001-full.png');
      expect((f.clientWidth, f.clientHeight), (1920, 1080));
      expect((f.cursorX, f.cursorY), (500, 300));
      expect(session.skipped.values.every((n) => n == 0), isTrue);
      expect(session.partialFinalLine, isFalse);
    });

    test(
      'skips and counts lines without an image, clipped and full-client',
      () {
        final source = [
          _line(id: 'a', image: null, client: null, clipped: null),
          _line(id: 'b', clipped: true),
          _line(id: 'c', kind: 'fullClient', withCursor: false),
          _line(id: 'd', image: null, kind: 'fullClient', withCursor: false),
          _line(id: 'e'),
        ].join('\n');
        final session = parseFramesJsonl(source);
        expect(session.frames.map((f) => f.id), ['e']);
        expect(session.skipped, {
          ReplaySkip.noImage: 2,
          ReplaySkip.clipped: 1,
          ReplaySkip.fullClient: 1,
        });
      },
    );

    test('tolerates an unparseable final line', () {
      final source = '${_line(id: 'a')}\n{"v":1,"id":"b","ima';
      final session = parseFramesJsonl(source);
      expect(session.frames.map((f) => f.id), ['a']);
      expect(session.partialFinalLine, isTrue);
    });

    test('accepts CRLF line ends and an empty file', () {
      expect(parseFramesJsonl('').frames, isEmpty);
      final session = parseFramesJsonl(
        '${_line(id: 'a')}\r\n${_line(id: 'b')}\r\n',
      );
      expect(session.frames.map((f) => f.id), ['a', 'b']);
      expect(session.partialFinalLine, isFalse);
    });

    void expectBadLine(String source, int line) => expect(
      () => parseFramesJsonl(source),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('line $line'),
        ),
      ),
    );

    test('rejects an unparseable line that is not the last, naming it', () {
      expectBadLine('${_line(id: 'a')}\n{oops\n${_line(id: 'c')}', 2);
    });

    test('rejects a schema problem on any line, naming it', () {
      final good = _line(id: 'a');
      expectBadLine('$good\n[1, 2]', 2);
      expectBadLine('$good\n${_line(id: 'b', v: 2)}', 2);
      expectBadLine('$good\n${_line(id: 'b', kind: 'side')}', 2);
      expectBadLine('$good\n${_line(id: 'b', withCursor: false)}', 2);
      expectBadLine(
        '$good\n${_line(id: 'b', cursor: const {'x': 1920, 'y': 5})}',
        2,
      );
      expectBadLine('$good\n${_line(id: 'b', client: null)}', 2);
      expectBadLine('$good\n${_line(id: 'b', clipped: null)}', 2);
      expectBadLine('$good\n${_line(id: 'b', image: r'..\x.png')}', 2);
      expectBadLine('$good\n${_line(id: 'a')}', 2);
      // A blank line in the middle is not a partial final append.
      expectBadLine('$good\n\n${_line(id: 'c')}', 2);
      // The final line is tolerated only when it is not JSON at all.
      expectBadLine('$good\n${_line(id: 'b', kind: 'side')}\n', 2);
    });

    test('rejects a session with more lines than the recorder writes', () {
      final source = [
        for (var i = 0; i <= replayMaxFramesPerSession; i++)
          _line(id: 's-$i', image: null),
      ].join('\n');
      expect(() => parseFramesJsonl(source), throwsA(isA<FormatException>()));
    });
  });

  group('replayBand', () {
    test('is the centred band from planTargeted at 1080p', () {
      final band = replayBand(
        clientWidth: 1920,
        clientHeight: 1080,
        cursorX: 10,
        cursorY: 1000,
      )!;
      expect(
        (band.left, band.top, band.width, band.height),
        (520, 0, 1140, 600),
      );
    });

    test('is null for a cursor outside the client', () {
      expect(
        replayBand(
          clientWidth: 1920,
          clientHeight: 1080,
          cursorX: -1,
          cursorY: 0,
        ),
        isNull,
      );
    });

    test('contains a marker by its top-left point', () {
      const band = CaptureRect(520, 0, 1140, 600);
      expect(markerInsideBand(band, 520, 0), isTrue);
      expect(markerInsideBand(band, 1659, 599), isTrue);
      expect(markerInsideBand(band, 1660, 10), isFalse);
      expect(markerInsideBand(band, 519, 10), isFalse);
      expect(markerInsideBand(band, 700, 600), isFalse);
    });
  });

  group('classification', () {
    test('agreement, both rejected, conflict and miss', () {
      expect(
        _result(targeted: 'x', full: 'x').verdict,
        ReplayVerdict.agreement,
      );
      expect(_result().verdict, ReplayVerdict.bothRejected);
      expect(_result(targeted: 'x').verdict, ReplayVerdict.conflict);
      expect(
        _result(targeted: 'x', full: 'y', inBand: true).verdict,
        ReplayVerdict.conflict,
      );
      expect(_result(full: 'y', inBand: true).verdict, ReplayVerdict.miss);
    });

    test('a miss names its cause', () {
      expect(
        _result(full: 'y', inBand: false).missCause,
        ReplayMissCause.winnerOutsideBand,
      );
      expect(
        _result(full: 'y', inBand: true).missCause,
        ReplayMissCause.insideBandRejected,
      );
      expect(_result(targeted: 'x', full: 'x', inBand: true).missCause, isNull);
    });

    test('the JSON form carries the outcomes, times and verdict', () {
      final json = _result(id: 'q', full: 'y', inBand: false).toJson();
      expect(json['id'], 'q');
      expect(json['session'], 'sess');
      expect(json['band'], {
        'left': 520,
        'top': 0,
        'width': 1140,
        'height': 600,
      });
      expect(json['targetedAccepted'], isNull);
      expect(json['fullClientAccepted'], 'y');
      expect(json['targetedMs'], 10);
      expect(json['fullClientMs'], 100);
      expect(json['fullWinnerInBand'], isFalse);
      expect(json['verdict'], 'miss');
      expect(json['missCause'], 'winnerOutsideBand');
    });
  });

  group('jobTimeDistribution', () {
    test('reports nearest-rank percentiles', () {
      final d = jobTimeDistribution([for (var i = 10; i >= 1; i--) i * 10]);
      expect(d, {
        'count': 10,
        'p50': 50,
        'p90': 90,
        'p95': 100,
        'p99': 100,
        'max': 100,
      });
    });

    test('is empty with no samples', () {
      expect(jobTimeDistribution(const []), {
        'count': 0,
        'p50': null,
        'p90': null,
        'p95': null,
        'p99': null,
        'max': null,
      });
    });
  });

  group('summariseReplay', () {
    test('counts shares, conflicts, misses and job times', () {
      final summary = summariseReplay([
        _result(id: 'a', targeted: 'x', full: 'x', targetedMs: 5, fullMs: 50),
        _result(id: 'b', full: 'y', inBand: false, targetedMs: 6, fullMs: 60),
        _result(id: 'c', full: 'z', inBand: true, targetedMs: 7, fullMs: 70),
        _result(id: 'd', targeted: 'w', targetedMs: 8, fullMs: 80),
        _result(id: 'e', targetedMs: 9, fullMs: 90),
      ]);
      expect(summary.frames, 5);
      expect(summary.fullClientAccepts, 3);
      expect(summary.alsoAcceptedByTargeted, 1);
      expect(summary.share, closeTo(1 / 3, 1e-9));
      expect(summary.conflicts, ['d']);
      expect(summary.misses, {
        ReplayMissCause.winnerOutsideBand: ['b'],
        ReplayMissCause.insideBandRejected: ['c'],
      });
      final json = summary.toJson();
      expect(json['bothRejected'], 1);
      expect(json['agreements'], 1);
      expect((json['targetedMs'] as Map)['max'], 9);
      expect((json['fullClientMs'] as Map)['p50'], 70);
    });

    test('has no share without a full-client accept', () {
      final summary = summariseReplay([_result()]);
      expect(summary.share, isNull);
      expect(summary.conflicts, isEmpty);
    });
  });

  group('buildReplayReport', () {
    test('holds the summary, sessions with skips, and frames', () {
      final session = parseFramesJsonl(
        [_line(id: 'a'), _line(id: 'b', clipped: true)].join('\n'),
      );
      final report = buildReplayReport(
        sessions: [(directory: r'D:\rec\s1', session: session)],
        results: [_result(id: 'a', targeted: 'x', full: 'x')],
      );
      expect(report['version'], 1);
      expect((report['summary'] as Map)['frames'], 1);
      expect(report['sessions'], [
        {
          'directory': r'D:\rec\s1',
          'frames': 1,
          'skipped': {'noImage': 0, 'clipped': 1, 'fullClient': 0},
          'partialFinalLine': false,
        },
      ]);
      expect((report['frames'] as List).single, containsPair('id', 'a'));
      // The report round-trips through JSON.
      expect(jsonDecode(jsonEncode(report)), isA<Map<String, Object?>>());
    });
  });

  group('replayOutputRefusal', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('replay_guard'));
    tearDown(() => root.deleteSync(recursive: true));

    String p(String relative) =>
        '${root.path}${Platform.pathSeparator}$relative';

    test('refuses a report inside an input folder', () {
      Directory(p('rec')).createSync();
      expect(
        replayOutputRefusal(
          replayReportPath(p('rec')),
          inputDirectories: [p('rec')],
          inputFiles: [p('catalog.json')],
        ),
        isNotNull,
      );
    });

    test('allows a report in a separate run folder', () {
      Directory(p('rec')).createSync();
      Directory(p('run')).createSync();
      final path = replayReportPath(p('run'));
      expect(path, endsWith('out${Platform.pathSeparator}replay.json'));
      expect(
        replayOutputRefusal(
          path,
          inputDirectories: [p('rec')],
          inputFiles: [p('catalog.json')],
        ),
        isNull,
      );
    });
  });
}
