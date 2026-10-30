import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/release/src/build_step.dart';
import '../../../tool/release/src/git.dart';
import '../../../tool/release/src/stamp.dart';

const _identity = {
  'GIT_AUTHOR_NAME': 'Test Author',
  'GIT_AUTHOR_EMAIL': 'author@example.invalid',
  'GIT_COMMITTER_NAME': 'Test Committer',
  'GIT_COMMITTER_EMAIL': 'committer@example.invalid',
  'GIT_CONFIG_GLOBAL': '',
  'GIT_CONFIG_NOSYSTEM': '1',
};

class Call {
  Call(this.executable, this.arguments, this.stream);

  final String executable;
  final List<String> arguments;
  final bool stream;

  String get line => [executable, ...arguments].join(' ');
}

/// Git runs for real against the fixture (except an optional injected commit
/// count); Flutter and the mise tasks are stubbed and recorded.
class FakeRunner implements CommandRunner {
  FakeRunner(this.real);

  final CommandRunner real;
  final List<Call> calls = [];
  String? countOverride;
  int bundleCheckExit = 0;

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool stream = false,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    calls.add(Call(executable, arguments, stream));
    if (executable == 'git') {
      if (countOverride != null &&
          arguments.join(' ') == 'rev-list --count HEAD') {
        return CommandResult(0, '$countOverride\n', '');
      }
      return real.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    }
    if (executable == 'flutter') return const CommandResult(0, '', '');
    if (executable == 'mise') {
      if (arguments.join(' ').startsWith('run bundle:check')) {
        return CommandResult(bundleCheckExit, '', '');
      }
      return const CommandResult(0, '', '');
    }
    fail('unexpected command: $executable ${arguments.join(' ')}');
  }
}

String _git(Directory dir, List<String> args) {
  final r = Process.runSync(
    'git',
    ['-c', 'commit.gpgsign=false', ...args],
    workingDirectory: dir.path,
    environment: _identity,
  );
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
  return (r.stdout as String).trim();
}

void main() {
  late Directory root;
  late Directory work;
  late FakeRunner runner;

  void commitFile(String path, String content, String subject) {
    File('${work.path}/$path').writeAsStringSync(content);
    _git(work, ['add', '.']);
    _git(work, ['commit', '-m', subject]);
  }

  Future<void> runBuild() =>
      build(repoDir: work, runner: runner, out: StringBuffer());

  Future<ReleaseException> refusal() async {
    try {
      await runBuild();
    } on ReleaseException catch (e) {
      return e;
    }
    fail('expected ReleaseException');
  }

  List<Call> external() => [
    for (final c in runner.calls)
      if (c.executable != 'git') c,
  ];

  setUp(() {
    root = Directory.systemTemp.createTempSync('blackgrid_build_');
    work = Directory('${root.path}/work')..createSync();
    _git(work, ['init', '-b', 'main']);
    File('${work.path}/.gitignore').writeAsStringSync('/build/\n');
    commitFile('pubspec.yaml', 'name: demo\nversion: 0.2.0\n', 'feat: first');
    commitFile('a.txt', 'a\n', 'feat: second');
    commitFile('b.txt', 'b\n', 'feat: third');
    runner = FakeRunner(ProcessCommandRunner(environment: _identity));
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('build passes build-name, commit-count build-number and version define, then bundle:check', () async {
    final count = _git(work, ['rev-list', '--count', 'HEAD']);
    expect(count, '3');
    await runBuild();

    final calls = external();
    expect(calls.map((c) => c.line).toList(), [
      'mise run vision:fetch',
      'flutter build windows --release --build-name 0.2.0 '
          '--build-number $count --dart-define=BLACKGRID_VERSION=0.2.0+$count',
      'mise run bundle:check -- build/windows/x64/runner/Release',
    ]);
    expect(calls.every((c) => c.stream), isTrue);
  });

  test('dirty tree refuses before building naming files', () async {
    File('${work.path}/a.txt').writeAsStringSync('changed\n');
    final e = await refusal();
    expect(e.message, contains('a.txt'));
    expect(external(), isEmpty);
  });

  test('count above 65535 refuses naming count and limit', () async {
    runner.countOverride = '65536';
    final e = await refusal();
    expect(e.message, contains('65536'));
    expect(e.message, contains('65535'));
    expect(external(), isEmpty);
  });

  test('bundle:check failure fails the build with its output', () async {
    runner.bundleCheckExit = 3;
    final e = await refusal();
    expect(e.message, contains('bundle:check'));
    expect(e.message, contains('3'));
    expect(e.exitCode, 3);
    expect(external().last.line, startsWith('mise run bundle:check'));
  });

  test(
    'a passing build writes a stamp with version, build number and HEAD commit',
    () async {
      final head = _git(work, ['rev-parse', 'HEAD']);
      await runBuild();

      final stamp = File('${work.path}/$stampPath');
      expect(stamp.existsSync(), isTrue);
      expect(jsonDecode(stamp.readAsStringSync()), {
        'format': 1,
        'version': '0.2.0',
        'buildNumber': 3,
        'commit': head,
      });
      expect(head, matches(RegExp(r'^[0-9a-f]{40}$')));
    },
  );

  test(
    'a failing bundle check deletes an earlier stamp and writes none',
    () async {
      final stamp = File('${work.path}/$stampPath')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"format":1}');
      runner.bundleCheckExit = 4;

      final e = await refusal();

      expect(e.exitCode, 4);
      expect(stamp.existsSync(), isFalse);
    },
  );
}
