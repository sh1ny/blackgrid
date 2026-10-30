import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/ci/src/audit.dart';
import '../../data/capture/support/native_guard.dart';

// Verbatim from the qualification tests that may skip on private inputs.
const _corpusReason =
    'Requires BLACKGRID_CORPUS_DIR (a corpus directory, see '
    'docs/qualification/m2/CORPUS.md).';
const _replayReason =
    'Requires BLACKGRID_RECORDING_DIRS (;-separated recording session '
    'folders, see docs/qualification/m2/REPLAY.md).';
const _ocrReason =
    'Requires the explicitly authorized Shoreline image and built OCR DLL.';

// The hosted windows-2025 runner is ANSI code page 1252.
const _codePageReason =
    'ANSI code page 1252 is not UTF-8; covered by the blackgrid.exe '
    'self-check under a Cyrillic path (m2_vision_self_check_test).';

// Verbatim from the app self-check test's launch guard.
const _selfCheckSkipReason =
    'Escape from Tarkov is running or its absence cannot be confirmed; '
    'app launch is not allowed (AGENTS.md). Unverified.';
const _selfCheckFile = 'test/qualification/m2_vision_self_check_test.dart';
const _selfCheckTest =
    'self-check from bundle copied under Cyrillic path exits 0';

const _corpusFile = 'test/qualification/inspection_corpus_test.dart';
const _replayFile = 'test/qualification/targeted_region_replay_test.dart';
const _ocrFile = 'test/qualification/m5_panel_ocr_test.dart';
const _bundleFile = 'test/qualification/m2_vision_runtime_test.dart';
const _captureFile = 'test/data/capture/capture_native_test.dart';

const _root = r'F:\Dev\Dart\blackgrid';

const _allowlist = [
  AllowedSkip(
    kind: SkipKind.privateInput,
    file: _corpusFile,
    reason: _corpusReason,
    why: 'private corpus',
  ),
  AllowedSkip(
    kind: SkipKind.privateInput,
    file: _replayFile,
    reason: _replayReason,
    why: 'recordings',
  ),
  AllowedSkip(
    kind: SkipKind.privateInput,
    file: _ocrFile,
    reason: _ocrReason,
    why: 'private image',
  ),
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
    test('the committed allowlist parses into three private inputs and one '
        'host-platform skip', () {
      final entries = _committed();

      expect(entries.map((e) => (e.kind, e.file, e.reason)), [
        (SkipKind.privateInput, _corpusFile, _corpusReason),
        (SkipKind.privateInput, _replayFile, _replayReason),
        (SkipKind.privateInput, _ocrFile, _ocrReason),
        (SkipKind.hostPlatform, _bundleFile, _codePageReason),
      ]);
      expect(entries.every((e) => e.why.isNotEmpty), isTrue);
    });

    test('an entry missing a field is rejected', () {
      expect(
        () => parseAllowlist(
          '- kind: private_input\n  file: a_test.dart\n  reason: r\n',
        ),
        throwsFormatException,
      );
    });

    test('the host-platform entry names a covering self-check test that has '
        'no platform skip', () {
      final hostEntries = _committed().where(
        (e) => e.kind == SkipKind.hostPlatform,
      );

      final entry = hostEntries.single;
      expect(entry.file, _bundleFile);
      expect(entry.reason, _codePageReason);
      final coveredBy = entry.coveredBy;
      expect(coveredBy, isNotNull);
      expect(coveredBy!.file, _selfCheckFile);
      expect(coveredBy.test, _selfCheckTest);
      final source = File(coveredBy.file).readAsStringSync();
      expect(source, isNot(contains('GetACP')));
      expect(source, isNot(contains('65001')));
    });

    test('every committed covered_by names an existing test and a '
        'host_platform entry without covered_by is rejected', () {
      final covered = _committed().where((e) => e.coveredBy != null);
      expect(covered, isNotEmpty);
      for (final entry in covered) {
        final coveredBy = entry.coveredBy!;
        final file = File(coveredBy.file);
        expect(file.existsSync(), isTrue, reason: coveredBy.file);
        final declaration = RegExp(
          "test\\(\\s*'${RegExp.escape(coveredBy.test)}'",
        );
        expect(
          declaration.hasMatch(file.readAsStringSync()),
          isTrue,
          reason: '${coveredBy.file} declares no test "${coveredBy.test}"',
        );
      }

      const fields = '  file: a_test.dart\n  reason: r\n  why: w\n';
      expect(
        () => parseAllowlist('- kind: host_platform\n$fields'),
        throwsFormatException,
      );
      expect(
        () => parseAllowlist(
          '- kind: private_input\n$fields'
          '  covered_by: {file: b_test.dart, test: t}\n',
        ),
        throwsFormatException,
      );
      expect(
        () => parseAllowlist('- file: a_test.dart\n  reason: r\n  why: w\n'),
        throwsFormatException,
      );
      expect(
        () => parseAllowlist('- kind: sometimes\n$fields'),
        throwsFormatException,
      );
      expect(
        parseAllowlist(
          '- kind: host_platform\n$fields'
          '  covered_by: {file: b_test.dart, test: t}\n',
        ).single.coveredBy?.test,
        't',
      );
    });

    test('the committed allowlist holds no capture-guard or missing-input '
        'reason', () {
      ProcessResult tasklist(int exitCode, String stdout) =>
          ProcessResult(0, exitCode, stdout, '');
      String? guard({
        bool isWindows = true,
        Map<String, String> environment = const {noGamesRunningVariable: '1'},
        required ProcessResult result,
      }) => nativeCaptureSkipReason(
        isWindows: isWindows,
        environment: environment,
        listProcesses: () => result,
      );

      final ok = tasklist(0, '"explorer.exe","1"\n');
      final forbidden = <String>{
        ?guard(isWindows: false, result: ok),
        ?guard(environment: const {}, result: ok),
        ?guard(result: tasklist(1, '')),
        for (final game in ['escapefromtarkov.exe', 'escapefromtarkov_be.exe'])
          ?guard(result: tasklist(0, '"$game","123","Console","1","1 K"\n')),
        _selfCheckSkipReason,
      };
      expect(forbidden, hasLength(6));

      for (final entry in _committed()) {
        expect(forbidden, isNot(contains(entry.reason)));
        for (final variable in [
          'BLACKGRID_RELEASE_BUNDLE',
          'BLACKGRID_PANEL_OCR_RUNTIME',
          'BLACKGRID_CMAKE',
          noGamesRunningVariable,
        ]) {
          expect(entry.reason, isNot(contains(variable)));
        }
      }
    });
  });
}

List<AllowedSkip> _committed() =>
    parseAllowlist(File('tool/ci/qualification_skips.yaml').readAsStringSync());
