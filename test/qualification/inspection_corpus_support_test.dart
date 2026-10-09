import 'dart:convert';
import 'dart:typed_data';

import 'package:blackgrid/application/recognition_matcher.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/data/vision/inspection_geometry.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/inspection_corpus.dart';

/// Offline tests of the corpus runner's pure parts. No bundle is needed.

CatalogItem _item(String id, String name) => CatalogItem(
  id: id,
  name: name,
  normalizedName: name.toLowerCase().replaceAll(RegExp(r'\s+'), '-'),
);

CatalogSnapshot _snapshot() => CatalogSnapshot(
  mode: GameMode.pvp,
  revision: 'r1',
  observedAt: DateTime.utc(2026, 1, 1),
  items: {
    for (final i in [
      _item('kit', 'Salewa First Aid Kit'),
      _item('bolts', 'Steel Hex Bolts'),
    ])
      i.id: i,
  },
  traders: const {},
  requirements: const [],
);

InspectionEvidence _evidence(String text, {double score = 0.9}) =>
    InspectionEvidence(
      markerScore: score,
      markerX: 1,
      markerY: 2,
      titleRect: const TitleRegion(x: 0, y: 0, width: 4, height: 2),
      titleStatus: InspectionTitleStatus.read,
      text: text,
      crop: Uint8List.fromList([0, 255, 0, 255, 255, 0, 255, 0]),
      cropWidth: 4,
      cropHeight: 2,
      cropDownscaled: false,
      qpcMarker: 0,
      qpcTitle: 0,
      qpcPreprocess: 0,
      qpcOcr: 0,
    );

InspectionRecognised _read(
  InspectionFrameKind kind,
  String text, {
  double best = 0.9,
}) => InspectionRecognised(
  kind: kind,
  scale: 1,
  bestMarkerScore: best,
  evidence: [_evidence(text, score: best)],
);

String _corpusJson({List<Map<String, Object?>>? cases}) => jsonEncode({
  'cases':
      cases ??
      [
        {
          'id': 'a',
          'image': 'a.png',
          'client': {'width': 1920, 'height': 1080},
          'kind': 'targeted',
          'cursor': {'x': 500, 'y': 300},
          'expected': 'kit',
        },
        {
          'id': 'b',
          'image': 'b.png',
          'client': {'width': 2560, 'height': 1440},
          'kind': 'fullClient',
          'expected': 'reject',
        },
      ],
});

CaseReport _report(String id, String expected, String outcome) => CaseReport(
  caseId: id,
  family: '1920x1080',
  kind: InspectionFrameKind.targeted,
  expected: expected,
  outcome: outcome,
  usedFallback: false,
);

void main() {
  group('parseCorpus', () {
    test('reads targeted and full-client cases', () {
      final cases = parseCorpus(_corpusJson());
      expect(cases, hasLength(2));
      expect(cases[0].kind, InspectionFrameKind.targeted);
      expect((cases[0].cursorX, cases[0].cursorY), (500, 300));
      expect(cases[0].family, '1920x1080');
      expect(cases[1].kind, InspectionFrameKind.fullClient);
      expect(cases[1].cursorX, isNull);
      expect(cases[1].expected, rejectOutcome);
    });

    test('rejects malformed corpora', () {
      Map<String, Object?> base() => {
        'id': 'a',
        'image': 'a.png',
        'client': {'width': 1920, 'height': 1080},
        'kind': 'targeted',
        'cursor': {'x': 5, 'y': 5},
        'expected': 'kit',
      };
      final bad = <String, List<Map<String, Object?>>>{
        'duplicate id': [base(), base()],
        'unknown kind': [base()..['kind'] = 'wide'],
        'missing cursor': [base()..remove('cursor')],
        'cursor outside': [
          base()..['cursor'] = {'x': 1920, 'y': 5},
        ],
        'empty client': [
          base()..['client'] = {'width': 0, 'height': 1080},
        ],
        'no expected': [base()..remove('expected')],
      };
      for (final MapEntry(:key, :value) in bad.entries) {
        expect(
          () => parseCorpus(_corpusJson(cases: value)),
          throwsFormatException,
          reason: key,
        );
      }
      expect(() => parseCorpus('[]'), throwsFormatException);
      expect(() => parseCorpus('{}'), throwsFormatException);
    });
  });

  group('targetedRegion', () {
    test('is (x - m/2, y - m/2, m + r, m) at 1080p', () {
      expect(
        targetedRegion(
          clientWidth: 1920,
          clientHeight: 1080,
          cursorX: 500,
          cursorY: 300,
        ),
        const CaptureRect(475, 275, 650, 50),
      );
    });

    test('scales with the smaller axis and clips to the client', () {
      expect(
        targetedRegion(
          clientWidth: 3840,
          clientHeight: 2160,
          cursorX: 10,
          cursorY: 10,
        ),
        const CaptureRect(0, 0, 1260, 60),
      );
    });
  });

  group('image helpers', () {
    test('crop copies the rows of a BGRX sub-rectangle', () {
      final bytes = Uint8List.fromList([for (var i = 0; i < 3 * 2 * 4; i++) i]);
      final cropped = BgrxImage(
        bytes,
        3,
        2,
      ).crop(const CaptureRect(1, 1, 2, 1));
      expect(cropped.width, 2);
      expect(cropped.height, 1);
      expect(cropped.bytes, bytes.sublist(16, 24));
    });

    test('cropToPng produces a grayscale PNG that decodes to BGRX', () {
      final png = cropToPng(Uint8List.fromList([0, 255, 10, 200]), 2, 2);
      final back = decodePngBgrx(png);
      expect((back.width, back.height), (2, 2));
      expect(back.bytes.sublist(0, 8), [0, 0, 0, 255, 255, 255, 255, 255]);
      expect(back.bytes.sublist(8, 12), [10, 10, 10, 255]);
    });

    test('decodePngBgrx rejects bytes that are not a PNG', () {
      expect(
        () => decodePngBgrx(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  group('baseline', () {
    test('parses and rejects a malformed baseline', () {
      final baseline = parseBaseline('{"cases": {"a": "kit", "b": "reject"}}');
      expect(baseline.outcomes, {'a': 'kit', 'b': 'reject'});
      expect(() => parseBaseline('{"cases": {"a": 1}}'), throwsFormatException);
      expect(() => parseBaseline('{}'), throwsFormatException);
    });

    test('tally counts coverage and false positives', () {
      final tally = tallyOutcomes(
        {'a': 'kit', 'b': 'bolts', 'c': rejectOutcome, 'd': rejectOutcome},
        {'a': 'kit', 'b': 'kit', 'c': 'bolts', 'd': rejectOutcome},
      );
      expect(tally.expectedItemCases, 2);
      expect(tally.correct, 1);
      expect(tally.coverage, 0.5);
      expect(tally.falsePositives, 2);
    });

    test('lower coverage fails and names the regression', () {
      final comparison = compareWithBaseline([
        _report('a', 'kit', rejectOutcome),
        _report('b', 'bolts', 'bolts'),
      ], const Baseline({'a': 'kit', 'b': 'bolts'}));
      expect(comparison.passed, isFalse);
      expect(comparison.regressions, ['a']);
    });

    test('more false positives fails and names the case', () {
      final comparison = compareWithBaseline([
        _report('a', 'kit', 'kit'),
        _report('b', rejectOutcome, 'bolts'),
      ], const Baseline({'a': 'kit', 'b': rejectOutcome}));
      expect(comparison.passed, isFalse);
      expect(comparison.newFalsePositives, ['b']);
    });

    test('equal results pass, improvements are listed and unknown cases '
        'are ignored', () {
      final comparison = compareWithBaseline([
        _report('a', 'kit', 'kit'),
        _report('b', 'bolts', 'bolts'),
        _report('extra', 'kit', rejectOutcome),
      ], const Baseline({'a': 'kit', 'b': rejectOutcome}));
      expect(comparison.passed, isTrue);
      expect(comparison.improvements, ['b']);
      expect(comparison.current.expectedItemCases, 2);
    });
  });

  group('two-case synthetic corpus', () {
    test('a fake recogniser produces a complete report', () async {
      final cases = parseCorpus(
        _corpusJson(
          cases: [
            {
              'id': 'hit',
              'image': 'hit.png',
              'client': {'width': 1920, 'height': 1080},
              'kind': 'targeted',
              'cursor': {'x': 500, 'y': 300},
              'expected': 'kit',
            },
            {
              'id': 'miss',
              'image': 'miss.png',
              'client': {'width': 1920, 'height': 1080},
              'kind': 'targeted',
              'cursor': {'x': 700, 'y': 400},
              'expected': rejectOutcome,
            },
          ],
        ),
      );
      final index = await buildTitleMatchIndexOffUi(_snapshot());
      final calls = <String>[];
      final written = <String>[];

      Future<TimedRecognition> recognise(
        CorpusCase c,
        InspectionFrameKind kind,
      ) async {
        calls.add('${c.id}:${kind.name}');
        final text = c.id == 'hit' ? 'Salewa First Aid Kit' : 'zzzz qqqq';
        return (
          result: _read(kind, text, best: 0.93),
          elapsed: const Duration(milliseconds: 420),
        );
      }

      final reports = [
        for (final c in cases)
          await evaluateCase(
            c,
            recognise: recognise,
            match: ({required targeted, fullClient}) => matchRecognitionOffUi(
              index,
              targeted: targeted,
              fullClient: fullClient,
              mode: GameMode.pvp,
            ),
            writeCrop: (id, evidence) async {
              written.add(id);
              return 'crops/$id.png';
            },
          ),
      ];

      expect(calls, ['hit:targeted', 'miss:targeted', 'miss:fullClient']);
      expect(written, ['hit', 'miss']);
      final hit = reports[0];
      expect(hit.outcome, 'kit');
      expect(hit.correct, isTrue);
      expect(hit.usedFallback, isFalse);
      expect(hit.text, 'Salewa First Aid Kit');
      expect(hit.cropPath, 'crops/hit.png');
      expect(hit.targetedMarkerScore, 0.93);
      expect(hit.fullClientMs, isNull);
      final miss = reports[1];
      expect(miss.outcome, rejectOutcome);
      expect(miss.rejectReason, isNotNull);
      expect(miss.usedFallback, isTrue);
      expect(miss.fallbackMarkerScore, 0.93);
      expect(miss.fullClientMs, 420);
      expect(miss.falsePositive, isFalse);

      final report = buildReport(
        reports,
        baseline: const Baseline({'hit': 'kit', 'miss': rejectOutcome}),
      );
      final summary = report['summary']! as Map<String, Object?>;
      expect(summary['coverage'], 1.0);
      expect(summary['falsePositives'], 0);
      final families = report['families']! as List;
      expect(families.single, {
        'client': '1920x1080',
        'fullClientRuns': 1,
        'fullClientMs': [420],
        'maxMs': 420,
        'deadlineMs': fullClientDeadlineMs,
        'withinDeadline': true,
      });
      expect((report['cases']! as List), hasLength(2));
      expect((report['baseline']! as Map)['passed'], isTrue);
      expect(() => jsonEncode(report), returnsNormally);
    });
  });

  group('inputInsideOutput', () {
    test('inputs outside out/ are accepted', () {
      expect(
        inputInsideOutput(['corpus.json', 'frames/a.png', 'output/b.png']),
        isNull,
      );
    });

    test('an input inside out/ is named, whatever the separator or case', () {
      expect(inputInsideOutput(['a.png', 'out/b.png']), 'out/b.png');
      expect(inputInsideOutput([r'OUT\crops\c.png']), r'OUT\crops\c.png');
      expect(inputInsideOutput(['./out/d.png']), './out/d.png');
      expect(inputInsideOutput(['frames/../out/e.png']), 'frames/../out/e.png');
    });

    test('out itself counts as inside', () {
      expect(inputInsideOutput(['out']), 'out');
    });
  });
}
