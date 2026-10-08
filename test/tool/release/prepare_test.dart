import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/release/src/git.dart';
import '../../../tool/release/src/release_steps.dart';

const _identity = {
  'GIT_AUTHOR_NAME': 'Test Author',
  'GIT_AUTHOR_EMAIL': 'author@example.invalid',
  'GIT_COMMITTER_NAME': 'Test Committer',
  'GIT_COMMITTER_EMAIL': 'committer@example.invalid',
  'GIT_CONFIG_GLOBAL': '',
  'GIT_CONFIG_NOSYSTEM': '1',
};

/// Records every non-git invocation. Git runs for real; `mise run <gate>` and
/// the changelog generator are stubbed.
class FakeRunner implements CommandRunner {
  FakeRunner(this.real);

  final CommandRunner real;
  final List<String> calls = [];
  final Map<String, int> gateCodes = {};
  int changelogCode = 0;

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool stream = false,
    Map<String, String>? environment,
  }) async {
    final line = [executable, ...arguments].join(' ');
    if (executable == 'git') {
      return real.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
    }
    calls.add(line);
    if (executable == 'mise' && arguments.first == 'run') {
      return CommandResult(gateCodes[arguments[1]] ?? 0, '', 'gate stderr');
    }
    if (executable == Platform.resolvedExecutable &&
        arguments.contains('tool/changelog.dart')) {
      if (changelogCode != 0) {
        return CommandResult(changelogCode, '', 'generator exploded');
      }
      final tag = arguments[arguments.indexOf('--tag') + 1];
      File('$workingDirectory/CHANGELOG.md')
          .writeAsStringSync('# Changelog\n\n## $tag\n\n- feat: something\n');
      return const CommandResult(0, '', '');
    }
    if (executable == 'git-cliff') {
      return const CommandResult(0, '0.2.0\n', '');
    }
    fail('unexpected command: $line');
  }

  List<String> get gates => [
    for (final c in calls)
      if (c.startsWith('mise run ')) c.substring('mise run '.length),
  ];
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

void main() {
  late Directory root;
  late Directory origin;
  late Directory work;
  late FakeRunner runner;
  late StringBuffer out;

  Future<void> prepareRelease(
    String version, {
    List<String> trailers = const [],
  }) {
    return prepare(
      version: version,
      repoDir: work,
      runner: runner,
      trailers: trailers,
      out: out,
    );
  }

  Future<ReleaseException> refusal(String version) async {
    try {
      await prepareRelease(version);
    } on ReleaseException catch (e) {
      return e;
    }
    fail('expected ReleaseException');
  }

  String snapshot() => [
    _git(work, ['branch', '--show-current']),
    _git(work, ['rev-parse', 'HEAD']),
    _git(work, ['status', '--porcelain', '--untracked-files=all']),
    _git(work, ['branch', '--list']),
    _git(work, ['tag', '--list']),
    File('${work.path}/pubspec.yaml').readAsStringSync(),
  ].join('\n--\n');

  setUp(() {
    root = Directory.systemTemp.createTempSync('blackgrid_prepare_');
    origin = Directory('${root.path}/origin.git')..createSync();
    work = Directory('${root.path}/work')..createSync();
    _git(origin, ['init', '--bare', '-b', 'main']);
    _git(work, ['init', '-b', 'main']);
    _git(work, ['remote', 'add', 'origin', origin.path]);
    File('${work.path}/pubspec.yaml').writeAsStringSync(
      'name: demo\r\nversion: 0.1.0+1\r\nenvironment:\r\n  sdk: any\r\n',
    );
    File('${work.path}/README.md').writeAsStringSync('hi\n');
    _git(work, ['add', '.']);
    _git(work, ['commit', '-m', 'feat: first']);
    _git(work, ['tag', 'v0.1.0']);
    _git(work, ['push', 'origin', 'main', '--tags']);
    runner = FakeRunner(ProcessCommandRunner(environment: _identity));
    out = StringBuffer();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('preconditions pass on clean main equal to origin/main', () async {
    await prepareRelease('0.2.0');
    expect(out.toString(), contains('git push -u origin release/v0.2.0'));
    expect(out.toString(), contains('gh pr create'));
  });

  test(
    'wrong branch, modified or untracked file refuses with no change',
    () async {
      _git(work, ['checkout', '-b', 'feat/x']);
      var before = snapshot();
      var e = await refusal('0.2.0');
      expect(e.message, contains('feat/x'));
      expect(snapshot(), before);

      _git(work, ['checkout', 'main']);
      File('${work.path}/README.md').writeAsStringSync('changed\n');
      before = snapshot();
      e = await refusal('0.2.0');
      expect(e.message, contains('README.md'));
      expect(snapshot(), before);

      _git(work, ['checkout', '--', 'README.md']);
      File('${work.path}/stray.txt').writeAsStringSync('x');
      before = snapshot();
      e = await refusal('0.2.0');
      expect(e.message, contains('stray.txt'));
      expect(snapshot(), before);
      expect(runner.calls, isEmpty);
    },
  );

  test(
    'local main differing from origin/main refuses naming both commits',
    () async {
      // Ahead.
      File('${work.path}/README.md').writeAsStringSync('ahead\n');
      _git(work, ['commit', '-am', 'feat: ahead']);
      final ahead = _git(work, ['rev-parse', 'HEAD']);
      final remote = _git(origin, ['rev-parse', 'main']);
      var before = snapshot();
      var e = await refusal('0.2.0');
      expect(e.message, contains(ahead));
      expect(e.message, contains(remote));
      expect(snapshot(), before);

      // Behind.
      _git(work, ['reset', '--hard', remote]);
      final other = Directory('${root.path}/other')..createSync();
      _git(other, ['clone', origin.path, '.']);
      File('${other.path}/README.md').writeAsStringSync('upstream\n');
      _git(other, ['commit', '-am', 'feat: upstream']);
      _git(other, ['push', 'origin', 'main']);
      final newRemote = _git(origin, ['rev-parse', 'main']);
      before = snapshot();
      e = await refusal('0.2.0');
      expect(e.message, contains(remote));
      expect(e.message, contains(newRemote));
      expect(snapshot(), before);
    },
  );

  test('fetch failure refuses with the fetch error and no change', () async {
    _git(work, ['remote', 'set-url', 'origin', '${root.path}/missing.git']);
    final before = snapshot();
    final e = await refusal('0.2.0');
    expect(e.message.toLowerCase(), contains('fetch'));
    expect(e.message, contains('missing.git'));
    expect(snapshot(), before);
    expect(runner.calls, isEmpty);
  });

  test('existing tag or release branch locally or on origin refuses', () async {
    // Tag locally and on origin.
    var e = await refusal('0.1.0');
    expect(e.message, contains('v0.1.0'));

    // Release branch only locally.
    _git(work, ['branch', 'release/v0.2.0']);
    e = await refusal('0.2.0');
    expect(e.message, contains('release/v0.2.0'));
    _git(work, ['branch', '-D', 'release/v0.2.0']);

    // Release branch only on origin.
    _git(work, ['push', 'origin', 'main:refs/heads/release/v0.3.0']);
    final before = snapshot();
    e = await refusal('0.3.0');
    expect(e.message, contains('release/v0.3.0'));
    expect(snapshot(), before);
    expect(runner.calls, isEmpty);
  });

  test('gates run in order analyze, format:check, test:all and preparation continues', () async {
    await prepareRelease('0.2.0');
    expect(runner.gates, ['analyze', 'format:check', 'test:all']);
    expect(_git(work, ['branch', '--show-current']), 'release/v0.2.0');
  });

  test('failing gate stops with its name and code; branch, tree and history unchanged', () async {
    runner.gateCodes['format:check'] = 3;
    final before = snapshot();
    final e = await refusal('0.2.0');
    expect(e.message, contains('format:check'));
    expect(e.message, contains('3'));
    expect(e.exitCode, 3);
    expect(runner.gates, ['analyze', 'format:check']);
    expect(snapshot(), before);
  });

  test(
    'release commit changes only pubspec version and CHANGELOG section',
    () async {
      await prepareRelease(
        '0.2.0',
        trailers: ['Co-authored-by: Bot <bot@example.invalid>'],
      );
      expect(_git(work, ['branch', '--show-current']), 'release/v0.2.0');
      expect(_git(work, ['rev-list', '--count', 'main..HEAD']), '1');
      expect(
        _git(work, ['log', '-1', '--format=%s']),
        'chore(release): v0.2.0',
      );
      expect(
        _git(work, [
          'show',
          '--name-only',
          '--format=',
          'HEAD',
        ]).split('\n').toSet(),
        {'CHANGELOG.md', 'pubspec.yaml'},
      );
      expect(
        File('${work.path}/pubspec.yaml').readAsStringSync(),
        'name: demo\r\nversion: 0.2.0\r\nenvironment:\r\n  sdk: any\r\n',
      );
      expect(
        File('${work.path}/CHANGELOG.md').readAsStringSync(),
        contains('## v0.2.0'),
      );
      expect(
        _git(work, ['log', '-1', '--format=%an <%ae>']),
        'Test Author <author@example.invalid>',
      );
      expect(
        _git(work, ['log', '-1', '--format=%B']),
        contains('Co-authored-by: Bot <bot@example.invalid>'),
      );
      expect(_git(work, ['status', '--porcelain']), isEmpty);
      expect(_git(origin, ['branch', '--list']), isNot(contains('release/')));
    },
  );

  test(
    'changelog failure makes no commit and names branch and files to discard',
    () async {
      runner.changelogCode = 7;
      final mainHead = _git(work, ['rev-parse', 'main']);
      final e = await refusal('0.2.0');
      expect(e.message, contains('generator exploded'));
      expect(e.message, contains('release/v0.2.0'));
      expect(e.message, contains('pubspec.yaml'));
      expect(e.message, contains('CHANGELOG.md'));
      expect(e.message, contains('git checkout main'));
      expect(_git(work, ['rev-parse', 'HEAD']), mainHead);
      expect(_git(work, ['rev-parse', 'release/v0.2.0']), mainHead);
    },
  );
}
