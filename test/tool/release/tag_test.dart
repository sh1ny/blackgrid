import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/release/src/git.dart';
import '../../../tool/release/src/tag_step.dart';

const _identity = {
  'GIT_AUTHOR_NAME': 'Test Author',
  'GIT_AUTHOR_EMAIL': 'author@example.invalid',
  'GIT_COMMITTER_NAME': 'Test Committer',
  'GIT_COMMITTER_EMAIL': 'committer@example.invalid',
  'GIT_CONFIG_GLOBAL': '',
  'GIT_CONFIG_NOSYSTEM': '1',
};

const _token = 'stub-token-9f8e7d6c5b4a';
const _login = 'KintsugiBot';

class Call {
  Call(this.executable, this.arguments, this.environment);

  final String executable;
  final List<String> arguments;
  final Map<String, String>? environment;

  String get line => [executable, ...arguments].join(' ');
  bool get isGit => executable == 'git';
  bool isGitCommand(String name) => isGit && arguments.contains(name);
}

/// Git runs for real against the fixture; `gh` is stubbed. Every invocation
/// is recorded with the per-call environment it was given.
class FakeRunner implements CommandRunner {
  FakeRunner(this.real);

  final CommandRunner real;
  final List<Call> calls = [];
  bool hasCredential = true;
  String apiLogin = _login;
  bool failPush = false;

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool stream = false,
    Map<String, String>? environment,
  }) async {
    calls.add(Call(executable, arguments, environment));
    if (executable == 'git') {
      if (failPush && arguments.contains('push')) {
        return const CommandResult(1, '', 'remote rejected the push');
      }
      return real.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    }
    if (executable == 'gh') {
      if (arguments.take(2).join(' ') == 'auth token') {
        return hasCredential
            ? const CommandResult(0, '$_token\n', '')
            : const CommandResult(1, '', 'no token found for user');
      }
      if (arguments.first == 'api') {
        if (environment?['GH_TOKEN'] != _token) {
          return const CommandResult(1, '', 'not logged in');
        }
        return CommandResult(0, '$apiLogin\n', '');
      }
    }
    fail('unexpected command: $executable ${arguments.join(' ')}');
  }
}

String _git(Directory dir, List<String> args) {
  final r = Process.runSync(
    'git',
    ['-c', 'commit.gpgsign=false', '-c', 'tag.gpgsign=false', ...args],
    workingDirectory: dir.path,
    environment: _identity,
  );
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
  return (r.stdout as String).trim();
}

String _kind(Call c) => c.arguments.contains('fetch')
    ? 'fetch'
    : c.arguments.contains('ls-remote')
    ? 'ls-remote'
    : 'push';

void main() {
  late Directory root;
  late Directory origin;
  late Directory work;
  late FakeRunner runner;
  late StringBuffer out;

  void commitFile(String path, String content, String subject) {
    File('${work.path}/$path').writeAsStringSync(content);
    _git(work, ['add', '.']);
    _git(work, ['commit', '-m', subject]);
  }

  /// Builds main ending in a merge of a release branch whose commit has
  /// [releaseSubject] and pubspec version [releaseVersion].
  void buildMerge({
    String releaseSubject = 'chore(release): v0.2.0',
    String releaseVersion = '0.2.0',
    bool mainMovesFirst = false,
    bool merge = true,
  }) {
    _git(work, ['checkout', '-b', 'release/v0.2.0']);
    commitFile(
      'pubspec.yaml',
      'name: demo\nversion: $releaseVersion\n',
      releaseSubject,
    );
    _git(work, ['checkout', 'main']);
    if (mainMovesFirst) commitFile('late.txt', 'late\n', 'feat: late arrival');
    if (merge) {
      _git(work, [
        'merge',
        '--no-ff',
        'release/v0.2.0',
        '-m',
        'Merge pull request #7 from x/release/v0.2.0',
      ]);
    } else {
      commitFile('plain.txt', 'plain\n', 'docs: plain head');
    }
    _git(work, ['push', 'origin', 'main']);
  }

  Future<void> runTag() => tag(repoDir: work, runner: runner, out: out);

  Future<ReleaseException> refusal() async {
    try {
      await runTag();
    } on ReleaseException catch (e) {
      return e;
    }
    fail('expected ReleaseException');
  }

  List<Call> networkGit() => [
    for (final c in runner.calls)
      if (c.isGit &&
          (c.isGitCommand('fetch') ||
              c.isGitCommand('ls-remote') ||
              c.isGitCommand('push')))
        c,
  ];

  setUp(() {
    root = Directory.systemTemp.createTempSync('blackgrid_tag_');
    origin = Directory('${root.path}/origin.git')..createSync();
    work = Directory('${root.path}/work')..createSync();
    _git(origin, ['init', '--bare', '-b', 'main']);
    _git(work, ['init', '-b', 'main']);
    _git(work, ['remote', 'add', 'origin', origin.path]);
    Directory('${work.path}/openspec').createSync();
    File('${work.path}/openspec/specwright.yaml')
        .writeAsStringSync('finish: pr\ngithub:\n  login: $_login\n');
    commitFile('pubspec.yaml', 'name: demo\nversion: 0.1.0\n', 'feat: first');
    _git(work, ['tag', 'v0.1.0']);
    _git(work, ['push', 'origin', 'main', '--tags']);
    runner = FakeRunner(ProcessCommandRunner(environment: _identity));
    out = StringBuffer();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('release merge gets annotated tag pushed to origin', () async {
    buildMerge();
    final head = _git(work, ['rev-parse', 'HEAD']);
    await runTag();
    expect(_git(work, ['cat-file', '-t', 'refs/tags/v0.2.0']), 'tag');
    expect(_git(work, ['rev-parse', 'v0.2.0^{commit}']), head);
    expect(_git(origin, ['cat-file', '-t', 'refs/tags/v0.2.0']), 'tag');
    expect(_git(origin, ['rev-parse', 'v0.2.0^{commit}']), head);
    expect(
      _git(work, [
        'for-each-ref',
        '--format=%(contents:subject)',
        'refs/tags/v0.2.0',
      ]),
      'v0.2.0',
    );
    expect(
      _git(work, [
        'for-each-ref',
        '--format=%(taggername)',
        'refs/tags/v0.2.0',
      ]),
      'Test Committer',
    );
    final push = runner.calls.singleWhere((c) => c.isGitCommand('push'));
    expect(push.arguments.last, 'refs/tags/v0.2.0');
    expect(push.arguments, isNot(contains('--tags')));
  });

  test('first-parent mismatch refuses naming intervening commits', () async {
    buildMerge(mainMovesFirst: true);
    final e = await refusal();
    expect(e.message, contains('feat: late arrival'));
    expect(e.message, contains('release/v0.2.0'));
    expect(e.message, contains('release:prepare'));
    expect(_git(work, ['tag', '--list']), 'v0.1.0');
    expect(_git(origin, ['tag', '--list']), 'v0.1.0');
  });

  test('ordinary merge or non-merge HEAD refuses naming its subject', () async {
    buildMerge(releaseSubject: 'feat: not a release');
    var e = await refusal();
    expect(e.message, contains('Merge pull request #7'));
    expect(_git(work, ['tag', '--list']), 'v0.1.0');

    _git(work, ['reset', '--hard', 'HEAD~1']);
    _git(work, ['push', '--force', 'origin', 'main']);
    commitFile('plain.txt', 'plain\n', 'docs: plain head');
    _git(work, ['push', 'origin', 'main']);
    e = await refusal();
    expect(e.message, contains('docs: plain head'));
    expect(_git(work, ['tag', '--list']), 'v0.1.0');
    expect(_git(origin, ['tag', '--list']), 'v0.1.0');
  });

  test('pubspec version mismatch refuses naming both versions', () async {
    buildMerge(releaseVersion: '0.2.0-beta.1');
    final e = await refusal();
    expect(e.message, contains('0.2.0-beta.1'));
    expect(e.message, contains('0.2.0'));
    expect(_git(work, ['tag', '--list']), 'v0.1.0');
    expect(_git(origin, ['tag', '--list']), 'v0.1.0');
  });

  test(
    'missing credential or other login refuses before any tag exists',
    () async {
      buildMerge();
      runner.hasCredential = false;
      var e = await refusal();
      expect(e.message, contains(_login));
      expect(_git(work, ['tag', '--list']), 'v0.1.0');
      expect(runner.calls.where((c) => c.isGitCommand('tag')), isEmpty);
      expect(runner.calls.where((c) => c.isGitCommand('push')), isEmpty);

      runner = FakeRunner(ProcessCommandRunner(environment: _identity))
        ..apiLogin = 'someone-else';
      e = await refusal();
      expect(e.message, contains(_login));
      expect(e.message, contains('someone-else'));
      expect(_git(work, ['tag', '--list']), 'v0.1.0');
      expect(_git(origin, ['tag', '--list']), 'v0.1.0');
      expect(runner.calls.where((c) => c.isGitCommand('push')), isEmpty);
    },
  );

  test('network git calls carry the credential-helper override and never the token', () async {
    buildMerge();
    await runTag();

    final net = networkGit();
    expect(net.map(_kind).toSet(), {'fetch', 'ls-remote', 'push'});
    for (final c in net) {
      expect(c.arguments.take(4).toList(), [
        '-c',
        'credential.helper=',
        '-c',
        'credential.helper=!gh auth git-credential',
      ], reason: c.line);
      expect(c.environment?['GH_TOKEN'], _token, reason: c.line);
    }
    for (final c in runner.calls) {
      expect(c.line, isNot(contains(_token)));
      expect(c.arguments.any((a) => a.contains(_token)), isFalse);
      expect(c.environment?.containsKey('GITHUB_TOKEN') ?? false, isFalse);
    }
    final authToken = runner.calls.singleWhere(
      (c) => c.arguments.take(2).join(' ') == 'auth token',
    );
    expect(authToken.environment?.containsKey('GH_TOKEN') ?? false, isFalse);
    expect(
      authToken.arguments,
      containsAllInOrder(['--hostname', 'github.com', '--user', _login]),
    );
    expect(out.toString(), isNot(contains(_token)));
  });

  test(
    'token appears in no output or exception message on failure paths',
    () async {
      buildMerge();
      runner.failPush = true;
      var e = await refusal();
      expect(e.message, isNot(contains(_token)));
      expect(out.toString(), isNot(contains(_token)));

      runner = FakeRunner(ProcessCommandRunner(environment: _identity))
        ..apiLogin = 'someone-else';
      e = await refusal();
      expect(e.message, isNot(contains(_token)));
      for (final c in runner.calls) {
        expect(c.line, isNot(contains(_token)));
      }
    },
  );

  test('failed push deletes the local tag', () async {
    buildMerge();
    runner.failPush = true;
    final e = await refusal();
    expect(e.message, contains('remote rejected the push'));
    expect(_git(work, ['tag', '--list']), 'v0.1.0');
    expect(_git(origin, ['tag', '--list']), 'v0.1.0');

    runner.failPush = false;
    await runTag();
    expect(_git(origin, ['tag', '--list']), contains('v0.2.0'));
  });
}
