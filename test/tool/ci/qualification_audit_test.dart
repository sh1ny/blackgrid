import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/ci/src/audit.dart';

// Verbatim from the qualification tests that may skip on private inputs.
const _corpusReason =
    'Requires BLACKGRID_CORPUS_DIR (a corpus directory, see '
    'docs/qualification/m2/CORPUS.md).';
const _replayReason =
    'Requires BLACKGRID_RECORDING_DIRS (;-separated recording session '
    'folders, see docs/qualification/m2/REPLAY.md).';
const _ocrReason =
    'Requires the explicitly authorized Shoreline image and built OCR DLL.';

const _corpusFile = 'test/qualification/inspection_corpus_test.dart';
const _replayFile = 'test/qualification/targeted_region_replay_test.dart';
const _ocrFile = 'test/qualification/m5_panel_ocr_test.dart';
const _bundleFile = 'test/qualification/m2_vision_runtime_test.dart';
const _captureFile = 'test/data/capture/capture_native_test.dart';

const _root = r'F:\Dev\Dart\blackgrid';

const _allowlist = [
  AllowedSkip(file: _corpusFile, reason: _corpusReason, why: 'private corpus'),
  AllowedSkip(file: _replayFile, reason: _replayReason, why: 'recordings'),
  AllowedSkip(file: _ocrFile, reason: _ocrReason, why: 'private image'),
];

String _line(Map<String, Object?> event) => jsonEncode(event);

String _suite(int id, String path) => _line({
  'type': 'suite',
  'suite': {'id': id, 'platform': 'vm', 'path': path},
});

/// A hidden loading test, as the reporter emits before each suite.
List<String> _loading(int id, int suiteId, String path) => [
  _line({
    'type': 'testStart',
    'test': {
      'id': id,
      'name': 'loading $path',
      'suiteID': suiteId,
      'metadata': {'skip': false, 'skipReason': null},
    },
  }),
  _line({
    'type': 'testDone',
    'testID': id,
    'result': 'success',
    'skipped': false,
    'hidden': true,
  }),
];

List<String> _test(
  int id,
  int suiteId,
  String name, {
  String? skipReason,
  bool skipped = false,
  bool hidden = false,
  String result = 'success',
}) {
  final skip = skipReason != null || skipped;
  return [
    _line({
      'type': 'testStart',
      'test': {
        'id': id,
        'name': name,
        'suiteID': suiteId,
        'metadata': {'skip': skip, 'skipReason': skipReason},
      },
    }),
    _line({
      'type': 'testDone',
      'testID': id,
      'result': result,
      'skipped': skip,
      'hidden': hidden,
    }),
  ];
}

String get _done => _line({'type': 'done', 'success': true});

AuditResult _audit(List<String>? lines) =>
    auditReport(lines, _allowlist, repoRoot: _root);

void main() {
  test('allowlisted private-input skips pass and are listed', () {
    final result = _audit([
      _suite(1, '$_root\\$_corpusFile'.replaceAll('/', r'\')),
      ..._loading(1, 1, _corpusFile),
      ..._test(2, 1, 'corpus', skipReason: _corpusReason),
      _suite(2, '$_root\\${_replayFile.replaceAll('/', r'\')}'),
      ..._test(3, 2, 'replay', skipReason: _replayReason),
      _suite(3, _ocrFile),
      ..._test(4, 3, 'ocr', skipReason: _ocrReason),
      _suite(4, 'test/qualification/m2_bundle_integrity_test.dart'),
      ..._test(5, 4, 'bundle integrity'),
      _done,
    ]);

    expect(result.passed, isTrue);
    expect(result.findings, isEmpty);
    expect(result.accepted.map((s) => s.file), [
      _corpusFile,
      _replayFile,
      _ocrFile,
    ]);
    expect(result.accepted.map((s) => s.testName), ['corpus', 'replay', 'ocr']);
  });

  test('an unlisted skip fails naming the file and reason', () {
    const reason = 'Requires BLACKGRID_CMAKE.';
    final result = _audit([
      _suite(1, 'test/qualification/m2_vision_cmake_test.dart'),
      ..._test(2, 1, 'cmake check', skipReason: reason),
      _suite(2, 'test/qualification/other_test.dart'),
      ..._test(3, 2, 'ran'),
      _done,
    ]);

    expect(result.passed, isFalse);
    final finding = result.findings.single;
    expect(finding, isA<UnlistedSkip>());
    finding as UnlistedSkip;
    expect(finding.file, 'test/qualification/m2_vision_cmake_test.dart');
    expect(finding.reason, reason);
    expect(finding.toString(), contains('m2_vision_cmake_test.dart'));
    expect(finding.toString(), contains(reason));
  });

  test('a skipped bundle-based test fails the audit', () {
    final result = _audit([
      _suite(1, '$_root\\test\\qualification\\m2_vision_runtime_test.dart'),
      ..._test(
        2,
        1,
        'identity reports vision abi',
        skipReason:
            'Requires BLACKGRID_RELEASE_BUNDLE (a built Release bundle).',
      ),
      _suite(2, 'test/qualification/other_test.dart'),
      ..._test(3, 2, 'ran'),
      _done,
    ]);

    expect(result.passed, isFalse);
    expect(
      result.findings.single,
      isA<UnlistedSkip>().having((f) => f.file, 'file', _bundleFile),
    );
  });

  test('an allowlisted file skipping for another reason fails', () {
    final result = _audit([
      _suite(1, _ocrFile),
      ..._test(
        2,
        1,
        'ocr',
        skipReason: 'Requires the built app-local OCR DLL.',
      ),
      _suite(2, 'test/qualification/other_test.dart'),
      ..._test(3, 2, 'ran'),
      _done,
    ]);

    expect(result.findings.single, isA<UnlistedSkip>());
  });

  test('an allowlisted reason in another file fails', () {
    final result = _audit([
      _suite(1, _bundleFile),
      ..._test(2, 1, 'x', skipReason: _ocrReason),
      _suite(2, 'test/qualification/other_test.dart'),
      ..._test(3, 2, 'ran'),
      _done,
    ]);

    expect(result.findings.single, isA<UnlistedSkip>());
  });

  test(
    'the capture guard\'s refused and unconfirmed reasons are not allowlisted',
    () {
      final result = _audit([
        _suite(1, _captureFile),
        ..._test(
          2,
          1,
          'refused',
          skipReason: 'refused: escapefromtarkov.exe is running (AGENTS.md)',
        ),
        ..._test(
          3,
          1,
          'unconfirmed',
          skipReason:
              'set BLACKGRID_NO_GAMES_RUNNING=1 after confirming no game is '
              'running',
        ),
        _suite(2, 'test/qualification/other_test.dart'),
        ..._test(4, 2, 'ran'),
        _done,
      ]);

      expect(result.passed, isFalse);
      expect(result.findings, hasLength(2));
      expect(result.findings, everyElement(isA<UnlistedSkip>()));
      expect(
        result.findings.map((f) => (f as UnlistedSkip).reason),
        contains(startsWith('refused:')),
      );
    },
  );

  group('report problems', () {
    test('a missing report fails the audit', () {
      final result = _audit(null);

      expect(result.passed, isFalse);
      expect(result.findings.single, isA<MissingReport>());
      expect(result.accepted, isEmpty);
    });

    test('a malformed line fails the audit', () {
      final result = _audit([
        _suite(1, 'test/a_test.dart'),
        '{"type": "testStart", ',
        ..._test(2, 1, 'ran'),
        _done,
      ]);

      expect(result.passed, isFalse);
      expect(
        result.findings.single,
        isA<MalformedLine>().having((f) => f.lineNumber, 'lineNumber', 2),
      );
    });

    test('a non-object line is malformed', () {
      final result = _audit([
        _suite(1, 'test/a_test.dart'),
        ..._test(2, 1, 'ran'),
        '[1, 2]',
        _done,
      ]);

      expect(result.findings.single, isA<MalformedLine>());
    });

    test('a report without a done event fails the audit', () {
      final result = _audit([
        _suite(1, 'test/a_test.dart'),
        ..._test(2, 1, 'ran'),
      ]);

      expect(result.passed, isFalse);
      expect(result.findings.single, isA<MissingDone>());
    });

    test('a report where nothing ran unskipped fails the audit', () {
      final result = _audit([
        _suite(1, _corpusFile),
        ..._loading(1, 1, _corpusFile),
        ..._test(2, 1, 'corpus', skipReason: _corpusReason),
        _done,
      ]);

      expect(result.passed, isFalse);
      expect(result.findings.single, isA<NoTestRan>());
      expect(result.accepted, hasLength(1));
    });

    test('an empty report fails as unfinished with nothing run', () {
      final result = _audit(const []);

      expect(result.findings, [isA<MissingDone>(), isA<NoTestRan>()]);
    });
  });

  group('hidden tests', () {
    test('hidden loading tests are not counted as having run', () {
      final result = _audit([
        _suite(1, _corpusFile),
        ..._loading(1, 1, _corpusFile),
        _done,
      ]);

      expect(result.findings.single, isA<NoTestRan>());
    });

    test('hidden setUpAll entries are not counted as having run', () {
      final result = _audit([
        _suite(1, _corpusFile),
        ..._test(2, 1, '(setUpAll)', hidden: true),
        ..._test(3, 1, 'corpus', skipReason: _corpusReason),
        ..._test(4, 1, '(tearDownAll)', hidden: true),
        _done,
      ]);

      expect(result.findings.single, isA<NoTestRan>());
    });

    test('hidden skipped entries are excluded from the skip audit', () {
      final result = _audit([
        _suite(1, 'test/a_test.dart'),
        ..._test(2, 1, '(setUpAll)', skipReason: 'whatever', hidden: true),
        ..._test(3, 1, 'ran'),
        _done,
      ]);

      expect(result.passed, isTrue);
      expect(result.accepted, isEmpty);
    });
  });

  group('suite path', () {
    test('matches an absolute path with backslashes under the repo root', () {
      final result = _audit([
        _suite(1, '$_root\\test\\qualification\\m5_panel_ocr_test.dart'),
        ..._test(2, 1, 'ocr', skipReason: _ocrReason),
        _suite(2, 'test/a_test.dart'),
        ..._test(3, 2, 'ran'),
        _done,
      ]);

      expect(result.passed, isTrue);
    });

    test('matches the suite path, not the test url', () {
      final result = _audit([
        _suite(1, 'test/other_test.dart'),
        _line({
          'type': 'testStart',
          'test': {
            'id': 2,
            'name': 'ocr',
            'suiteID': 1,
            'url': 'file:///$_ocrFile',
            'metadata': {'skip': true, 'skipReason': _ocrReason},
          },
        }),
        _line({
          'type': 'testDone',
          'testID': 2,
          'result': 'success',
          'skipped': true,
          'hidden': false,
        }),
        ..._test(3, 1, 'ran'),
        _done,
      ]);

      expect(result.findings.single, isA<UnlistedSkip>());
    });
  });

  group('allowlist file', () {
    test('the committed allowlist parses into the three private inputs', () {
      final entries = parseAllowlist(
        File('tool/ci/qualification_skips.yaml').readAsStringSync(),
      );

      expect(entries.map((e) => (e.file, e.reason)), [
        (_corpusFile, _corpusReason),
        (_replayFile, _replayReason),
        (_ocrFile, _ocrReason),
      ]);
      expect(entries.every((e) => e.why.isNotEmpty), isTrue);
    });

    test('an entry missing a field is rejected', () {
      expect(
        () => parseAllowlist('- file: a_test.dart\n  reason: r\n'),
        throwsFormatException,
      );
    });
  });
}
