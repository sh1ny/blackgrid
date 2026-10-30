import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/ci/qualification.dart';
import '../../../tool/release/src/git.dart';

class _Call {
  _Call(this.executable, this.arguments, this.stream);

  final String executable;
  final List<String> arguments;
  final bool stream;
}

/// Records every command and stands in for `flutter test`: it writes
/// [reportLines] to the path given to `--file-reporter` and exits with
/// [testExit]. Nothing real is ever launched.
class _FakeRunner implements CommandRunner {
  _FakeRunner({this.testExit = 0, this.reportLines});

  final int testExit;
  final List<String>? reportLines;
  final List<_Call> calls = [];

  String? get reportPath {
    for (final argument in calls.last.arguments) {
      if (argument.startsWith('json:')) return argument.substring(5);
    }
    return null;
  }

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool stream = false,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    calls.add(_Call(executable, arguments, stream));
    final lines = reportLines;
    if (lines != null) {
      File(reportPath!).writeAsStringSync('${lines.join('\n')}\n');
    }
    return CommandResult(testExit, '', '');
  }
}

String _event(Map<String, Object?> event) => jsonEncode(event);

List<String> _cleanReport() => [
  _event({
    'type': 'suite',
    'suite': {'id': 1, 'path': 'test/qualification/a_test.dart'},
  }),
  _event({
    'type': 'testStart',
    'test': {
      'id': 2,
      'name': 'ran',
      'suiteID': 1,
      'metadata': {'skip': false, 'skipReason': null},
    },
  }),
  _event({
    'type': 'testDone',
    'testID': 2,
    'result': 'success',
    'skipped': false,
    'hidden': false,
  }),
  _event({'type': 'done', 'success': true}),
];

List<String> _reportWithUnlistedSkip() => [
  ..._cleanReport().take(3),
  _event({
    'type': 'testStart',
    'test': {
      'id': 3,
      'name': 'identity reports vision abi',
      'suiteID': 1,
      'metadata': {
        'skip': true,
        'skipReason': 'Requires BLACKGRID_RELEASE_BUNDLE.',
      },
    },
  }),
  _event({
    'type': 'testDone',
    'testID': 3,
    'result': 'success',
    'skipped': true,
    'hidden': false,
  }),
  _event({'type': 'done', 'success': true}),
];

void main() {
  late Directory bundle;
  late Directory repo;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    bundle = Directory.systemTemp.createTempSync('blackgrid-bundle-test-');
    repo = Directory.current;
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() => bundle.deleteSync(recursive: true));

  Future<int> run(_FakeRunner runner, {Map<String, String>? environment}) =>
      runQualification(
        runner: runner,
        environment: environment ?? {'BLACKGRID_RELEASE_BUNDLE': bundle.path},
        repoDir: repo,
        out: out,
        err: err,
      );

  test('a missing bundle directory exits 2 before flutter test runs', () async {
    final runner = _FakeRunner(reportLines: _cleanReport());

    final unset = await run(runner, environment: const {});
    final absent = await run(
      runner,
      environment: {'BLACKGRID_RELEASE_BUNDLE': '${bundle.path}/absent'},
    );
    final file = File('${bundle.path}/file')..writeAsStringSync('x');
    final notDirectory = await run(
      runner,
      environment: {'BLACKGRID_RELEASE_BUNDLE': file.path},
    );

    expect([unset, absent, notDirectory], [2, 2, 2]);
    expect(runner.calls, isEmpty);
    expect(err.toString(), contains('BLACKGRID_RELEASE_BUNDLE'));
  });

  test(
    'flutter test writes its JSON report to a fresh system-temp directory',
    () async {
      final runner = _FakeRunner(reportLines: _cleanReport());

      final exit = await run(runner);

      expect(exit, 0);
      final call = runner.calls.single;
      expect(call.executable, 'flutter');
      expect(call.arguments.take(3), ['test', '--tags', 'qualification']);
      expect(call.arguments, contains('--file-reporter'));
      expect(call.stream, isTrue);
      final path = runner.reportPath!;
      expect(path, endsWith('report.json'));
      expect(
        File(path).parent.absolute.path,
        startsWith(Directory.systemTemp.absolute.path),
      );
      expect(File(path).absolute.path, isNot(startsWith(repo.absolute.path)));
      expect(File(path).parent.existsSync(), isFalse, reason: 'cleaned up');
    },
  );

  test(
    'a failing flutter test exits non-zero even when the audit passes',
    () async {
      final runner = _FakeRunner(testExit: 1, reportLines: _cleanReport());

      final exit = await run(runner);

      expect(exit, isNonZero);
      expect(out.toString(), contains('Audit passed'));
    },
  );

  test('an audit finding exits non-zero with a zero test exit', () async {
    final runner = _FakeRunner(reportLines: _reportWithUnlistedSkip());

    final exit = await run(runner);

    expect(exit, isNonZero);
    expect(err.toString(), contains('Requires BLACKGRID_RELEASE_BUNDLE.'));
  });

  test('a missing report fails the run', () async {
    final runner = _FakeRunner();

    final exit = await run(runner);

    expect(exit, isNonZero);
    expect(err.toString(), contains('missing'));
  });

  test('both the test result and the audit result are printed', () async {
    final runner = _FakeRunner(
      testExit: 3,
      reportLines: _reportWithUnlistedSkip(),
    );

    final exit = await run(runner);

    expect(exit, 3);
    final printed = '$out$err';
    expect(printed, contains('flutter test exited with 3'));
    expect(printed, contains('Audit failed'));
  });
}
