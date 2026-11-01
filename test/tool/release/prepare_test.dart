import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/release/release.dart';
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

/// Records every non-git invocation. Git runs for real; `mise run <gate>` is
/// stubbed.
class FakeRunner implements CommandRunner {
  FakeRunner(this.real);

  final CommandRunner real;
  final List<String> calls = [];
  final Map<String, int> gateCodes = {};
  int commitCode = 0;
  bool failRangeRead = false;

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool stream = false,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final line = [executable, ...arguments].join(' ');
    if (executable == 'git') {
      if (commitCode != 0 && arguments.first == 'commit') {
        return CommandResult(commitCode, '', 'hook refused');
      }
      if (failRangeRead && arguments.contains('--merged')) {
        return const CommandResult(128, '', 'fatal: range exploded');
      }
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

const _summary = 'Blackgrid now follows the whole raid.';

String _proposal(String added) =>
    '## Why\n\nBecause it matters.\n\n## Release Notes\n\nA summary.\n\n'
    '### Added\n\n- $added\n';

void main() {
  late Directory root;
  late Directory origin;
  late Directory work;
  late FakeRunner runner;
  late StringBuffer out;

  Future<void> prepareRelease(
    String version, {
    List<String> trailers = const [],
    String? summary = _summary,
  }) {
    return prepare(
      version: version,
      repoDir: work,
      runner: runner,
      trailers: trailers,
      summary: summary,
      now: DateTime(2026, 11, 2),
      out: out,
    );
  }

  Future<ReleaseException> refusal(
    String version, {
    String? summary = _summary,
  }) async {
    try {
      await prepareRelease(version, summary: summary);
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

  /// Commits an archived proposal, as a squash-merged PR [pr] would.
  void archive(String name, int pr, String proposal) {
    final dir = Directory(
      '${work.path}/openspec/changes/archive/2026-01-01-$name',
    )..createSync(recursive: true);
    File('${dir.path}/proposal.md').writeAsStringSync(proposal);
    _git(work, ['add', '.']);
    _git(work, ['commit', '-m', 'feat: $name (#$pr)']);
  }

  void commitChangelog(String text) {
    File('${work.path}/CHANGELOG.md').writeAsStringSync(text);
    _git(work, ['add', 'CHANGELOG.md']);
    _git(work, ['commit', '-m', 'docs: changelog']);
    _git(work, ['push', 'origin', 'main']);
  }

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
    archive('thing', 5, _proposal('Raid timers'));
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

  test('a failing CHANGELOG write stops with no commit and names the branch '
      'and files to discard', () async {
    Directory('${work.path}/CHANGELOG.md').createSync();
    File('${work.path}/CHANGELOG.md/keep.txt').writeAsStringSync('x');
    _git(work, ['add', '.']);
    _git(work, ['commit', '-m', 'docs: changelog is odd']);
    _git(work, ['push', 'origin', 'main']);
    final mainHead = _git(work, ['rev-parse', 'main']);
    final e = await refusal('0.2.0');
    expect(e.message, contains('CHANGELOG.md'));
    expect(e.message, contains('release/v0.2.0'));
    expect(e.message, contains('pubspec.yaml'));
    expect(e.message, contains('git checkout main'));
    expect(_git(work, ['rev-parse', 'HEAD']), mainHead);
    expect(_git(work, ['rev-parse', 'release/v0.2.0']), mainHead);
  });

  group('the changelog section', () {
    const dated = '## v0.6.0 - 2026-10-01\n\nold six\n\n';
    const older = '## v0.5.0 - 2026-09-01\n\nold five\n\n';
    const title = '# Blackgrid Changelog\n\n';
    const added = 'Added:\n- Raid timers (#5)\n\n';

    String changelog() => File('${work.path}/CHANGELOG.md').readAsStringSync();

    test('release commit inserts the new section above the newest and keeps '
        'every other section', () async {
      commitChangelog('$title$dated${older.trimRight()}\n');
      await prepareRelease('0.7.0');
      expect(_git(work, ['branch', '--show-current']), 'release/v0.7.0');
      expect(_git(work, ['rev-list', '--count', 'main..HEAD']), '1');
      expect(
        _git(work, ['log', '-1', '--format=%s']),
        'chore(release): v0.7.0',
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
        contains('version: 0.7.0\r\n'),
      );
      expect(
        changelog(),
        '$title## v0.7.0 - 2026-11-02\n\n$_summary\n\n$added'
        '$dated${older.trimRight()}\n',
      );
    });

    test(
      'a final release removes the sections of its own prereleases',
      () async {
        commitChangelog(
          '$title## v0.7.0-beta.2 - 2026-10-20\n\nbeta two\n\n'
          '## v0.7.0-beta.1 - 2026-10-10\n\nbeta one\n\n$dated',
        );
        await prepareRelease('0.7.0');
        expect(
          changelog(),
          '$title## v0.7.0 - 2026-11-02\n\n$_summary\n\n$added$dated',
        );
      },
    );

    test(
      'a prerelease keeps the earlier prerelease section below it',
      () async {
        const beta1 = '## v0.7.0-beta.1 - 2026-10-10\n\nbeta one\n\n';
        commitChangelog('$title$beta1$dated');
        await prepareRelease('0.7.0-beta.2');
        expect(
          changelog(),
          '$title## v0.7.0-beta.2 - 2026-11-02\n\n$_summary\n\n$added'
          '$beta1$dated',
        );
      },
    );

    test('a CRLF changelog keeps its line endings', () async {
      commitChangelog('$title$dated'.replaceAll('\n', '\r\n'));
      await prepareRelease('0.7.0');
      final text = changelog();
      expect(text, startsWith('# Blackgrid Changelog\r\n\r\n## v0.7.0 - '));
      expect(text.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect(text, endsWith('old six\r\n\r\n'));
    });

    test(
      'a changelog without a version section gets it after the title',
      () async {
        commitChangelog(title);
        await prepareRelease('0.2.0');
        expect(
          changelog(),
          '$title## v0.2.0 - 2026-11-02\n\n$_summary\n\n${added.trimRight()}\n',
        );
      },
    );

    test(
      'the summary opens the section followed by the grouped items',
      () async {
        await prepareRelease('0.2.0');
        expect(
          changelog(),
          contains('## v0.2.0 - 2026-11-02\n\n$_summary\n\nAdded:\n'),
        );
      },
    );

    test('a change without release notes is warned about and listed', () async {
      archive('plain', 6, '## Why\n\nJust because.\n');
      _git(work, ['push', 'origin', 'main']);
      await prepareRelease('0.2.0');
      expect(out.toString(), contains('plain: no release notes'));
      expect(changelog(), contains('Changes:\n- plain (#6): Just because.'));
    });

    test('no suggested next version is printed', () async {
      await prepareRelease('0.2.0');
      expect(out.toString(), isNot(contains('suggested next version')));
    });
  });

  test(
    'nothing archived since the last final tag is refused before any gate',
    () async {
      _git(work, ['tag', 'v0.2.0']);
      File('${work.path}/README.md').writeAsStringSync('direct\n');
      _git(work, ['commit', '-am', 'feat: direct commit']);
      _git(work, ['push', 'origin', 'main', '--tags']);
      final before = snapshot();
      final e = await refusal('0.3.0');
      expect(e.message.toLowerCase(), contains('nothing to release'));
      expect(runner.calls, isEmpty);
      expect(snapshot(), before);
    },
  );

  test(
    'a missing, blank or over-long summary is refused before any gate',
    () async {
      final before = snapshot();
      for (final bad in [null, '', ' \n\t ', 'a ' * 301]) {
        final e = await refusal('0.2.0', summary: bad);
        expect(e.message.toLowerCase(), contains('summary'), reason: '$bad');
        expect(runner.calls, isEmpty);
        expect(snapshot(), before);
      }
      // 600 characters after collapsing are accepted.
      await prepareRelease('0.2.0', summary: '${'a ' * 299}a');
    },
  );

  test(
    'a summary starting with a heading is refused before any gate',
    () async {
      final before = snapshot();
      for (final bad in [
        '## Highlights Raid timers arrive.',
        '\n  ## v0.9.0 is out',
        '# Title',
        '### Small',
      ]) {
        final e = await refusal('0.2.0', summary: bad);
        expect(e.message, contains('starts with `#`'), reason: bad);
        expect(runner.calls, isEmpty);
        expect(snapshot(), before);
      }
      // A `#` later in the summary is fine: it stays inside the one line.
      await prepareRelease('0.2.0', summary: 'Fixes #12 and ## more.');
    },
  );

  test('a git error reading the range is refused without leftover-branch '
      'instructions', () async {
    runner.failRangeRead = true;
    final before = snapshot();
    final e = await refusal('0.2.0');
    expect(e.message, contains('range exploded'));
    expect(e.message, isNot(contains('release/v0.2.0')));
    expect(e.message, isNot(contains('Discard')));
    expect(runner.calls, isEmpty);
    expect(snapshot(), before);
  });

  group('command line', () {
    Future<int> cli(List<String> args) =>
        runRelease(['prepare', ...args], runner: runner, repoDir: work);

    test('--summary and --summary-file are exclusive', () async {
      final before = snapshot();
      expect(
        await cli(['0.2.0', '--summary', 'x', '--summary-file', 'y.md']),
        2,
      );
      expect(snapshot(), before);
      expect(runner.calls, isEmpty);
    });

    test('a multi-line summary file becomes one line in the section', () async {
      final file = File('${root.path}/summary.md')
        ..writeAsStringSync('Raid timers arrive.\n## Not a heading\n');
      expect(await cli(['0.2.0', '--summary-file', file.path]), 0);
      expect(
        File('${work.path}/CHANGELOG.md').readAsStringSync(),
        contains('\n\nRaid timers arrive. ## Not a heading\n\nAdded:\n'),
      );
    });

    test('a missing summary is a refusal', () async {
      expect(await cli(['0.2.0']), 1);
      expect(runner.calls, isEmpty);
    });

    test('an unreadable summary file is a refusal', () async {
      expect(await cli(['0.2.0', '--summary-file', '${root.path}/nope.md']), 1);
      expect(runner.calls, isEmpty);
    });
  });

  test(
    'commit failure leaves a recovery that returns main to a clean tree',
    () async {
      File('${work.path}/CHANGELOG.md').writeAsStringSync('# Changelog\n');
      _git(work, ['add', 'CHANGELOG.md']);
      _git(work, ['commit', '-m', 'docs: changelog']);
      _git(work, ['push', 'origin', 'main']);
      final mainHead = _git(work, ['rev-parse', 'main']);
      runner.commitCode = 1;
      final e = await refusal('0.2.0');
      expect(e.message, contains('hook refused'));

      // Run the printed recovery commands exactly as the user would.
      final commands = [
        for (final line in e.message.split('\n'))
          if (line.startsWith('  git ')) line.trim().split('&&'),
      ].expand((c) => c).map((c) => c.trim().split(' ').skip(1).toList());
      expect(commands, isNotEmpty);
      for (final c in commands) {
        _git(work, c);
      }

      expect(_git(work, ['branch', '--show-current']), 'main');
      expect(_git(work, ['rev-parse', 'HEAD']), mainHead);
      expect(
        _git(work, ['status', '--porcelain', '--untracked-files=all']),
        isEmpty,
      );
      expect(_git(work, ['branch', '--list']), isNot(contains('release/')));
    },
  );
}
