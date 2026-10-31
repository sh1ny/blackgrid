import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/release/src/git.dart';
import '../../../tool/release/src/verify_tag_step.dart';

const _identity = {
  'GIT_AUTHOR_NAME': 'Test Author',
  'GIT_AUTHOR_EMAIL': 'author@example.invalid',
  'GIT_COMMITTER_NAME': 'Test Committer',
  'GIT_COMMITTER_EMAIL': 'committer@example.invalid',
  'GIT_CONFIG_GLOBAL': '',
  'GIT_CONFIG_NOSYSTEM': '1',
};

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

const _notes = '- *(map)* first entry (#1)\n\n- *(map)* second entry (#2)\n';

String _changelog(String tag, {String body = _notes, String suffix = ''}) =>
    '# demo Changelog\n\n## $tag$suffix\n\n### Features\n\n$body\n'
    '## v0.0.1 - 2026-01-01\n\n- old entry\n';

void main() {
  late Directory root;
  late Directory work;
  late Directory out;

  void commitFiles(Map<String, String> files, String subject) {
    for (final e in files.entries) {
      File('${work.path}/${e.key}').writeAsStringSync(e.value);
    }
    _git(work, ['add', '.']);
    _git(work, ['commit', '-m', subject]);
  }

  /// Commits [pubspecVersion] and [changelog] on main and moves the
  /// remote-tracking ref `origin/main` to it.
  void releaseCommit({
    required String pubspecVersion,
    required String changelog,
  }) {
    commitFiles({
      'pubspec.yaml': 'name: demo\nversion: $pubspecVersion\n',
      'CHANGELOG.md': changelog,
    }, 'chore(release): v$pubspecVersion');
    _git(work, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
  }

  Future<void> verify(String tag) => verifyTag(
    tag: tag,
    outDir: out,
    repoDir: work,
    runner: const ProcessCommandRunner(environment: _identity),
  );

  Future<ReleaseException> refusal(String tag) async {
    try {
      await verify(tag);
    } on ReleaseException catch (e) {
      expect(out.existsSync() && out.listSync().isNotEmpty, isFalse);
      return e;
    }
    fail('expected ReleaseException');
  }

  Map<String, Object?> meta() =>
      jsonDecode(File('${out.path}/release.json').readAsStringSync())
          as Map<String, Object?>;

  String notes() => File('${out.path}/notes.md').readAsStringSync();

  setUp(() {
    root = Directory.systemTemp.createTempSync('blackgrid_verify_tag_');
    work = Directory('${root.path}/work')..createSync();
    out = Directory('${root.path}/out');
    _git(work, ['init', '-b', 'main']);
    commitFiles({
      'pubspec.yaml': 'name: demo\nversion: 0.0.1\n',
    }, 'feat: first');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('valid final tag writes notes and release metadata', () async {
    releaseCommit(
      pubspecVersion: '0.6.0',
      changelog: _changelog('v0.6.0', suffix: ' - 2026-11-10'),
    );
    _git(work, ['tag', '-a', 'v0.6.0', '-m', 'v0.6.0']);
    // Detached at the tag, as in CI.
    _git(work, ['checkout', '--detach', 'v0.6.0']);

    await verify('v0.6.0');

    expect(meta(), {
      'tag': 'v0.6.0',
      'version': '0.6.0',
      'prerelease': false,
      'latest': true,
    });
    expect(notes(), isNotEmpty);
    expect(out.listSync().map((e) => e.uri.pathSegments.last).toSet(), {
      'notes.md',
      'release.json',
    });
  });

  test('non-SemVer or build-metadata tag is refused', () async {
    releaseCommit(pubspecVersion: '0.6.0', changelog: _changelog('v0.6.0'));
    for (final bad in ['v0.6', 'v0.6.0+5', '0.6.0']) {
      final e = await refusal(bad);
      expect(e.message, contains(bad), reason: bad);
      expect(e.message, contains('not a strict SemVer release version'));
      expect(e.exitCode, 1);
    }
  });

  test('commit off main\'s first-parent line is refused', () async {
    releaseCommit(pubspecVersion: '0.0.1', changelog: _changelog('v0.0.1'));

    // A commit only on a feature branch.
    _git(work, ['checkout', '-b', 'feature']);
    commitFiles({
      'pubspec.yaml': 'name: demo\nversion: 0.6.0\n',
      'CHANGELOG.md': _changelog('v0.6.0'),
    }, 'feat: on a branch');
    _git(work, ['tag', 'v0.6.0']);
    var e = await refusal('v0.6.0');
    expect(e.message, contains("not on main's first-parent line"));

    // A commit that reached main only through a merged branch.
    _git(work, ['checkout', 'main']);
    _git(work, ['merge', '--no-ff', 'feature', '-m', 'Merge pull request #1']);
    _git(work, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
    e = await refusal('v0.6.0');
    expect(e.message, contains("not on main's first-parent line"));

    // The merge itself is on the line.
    commitFiles({
      'pubspec.yaml': 'name: demo\nversion: 0.6.1\n',
      'CHANGELOG.md': _changelog('v0.6.1'),
    }, 'chore(release): v0.6.1');
    _git(work, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
    _git(work, ['tag', 'v0.6.1']);
    await verify('v0.6.1');
    expect(meta()['tag'], 'v0.6.1');
  });

  test('pubspec mismatch is refused naming both versions', () async {
    releaseCommit(pubspecVersion: '0.5.0', changelog: _changelog('v0.6.0'));
    _git(work, ['tag', 'v0.6.0']);
    final e = await refusal('v0.6.0');
    expect(e.message, contains('0.5.0'));
    expect(e.message, contains('0.6.0'));
  });

  test('missing changelog section is refused', () async {
    // The beta heading must not satisfy the final tag.
    releaseCommit(
      pubspecVersion: '0.6.0',
      changelog: _changelog('v0.6.0-beta.1'),
    );
    _git(work, ['tag', 'v0.6.0']);
    final e = await refusal('v0.6.0');
    expect(e.message, contains('## v0.6.0'));
    expect(e.message.toLowerCase(), contains('missing'));
  });

  test(
    'notes are the lines between the tag heading and the next section',
    () async {
      releaseCommit(
        pubspecVersion: '0.6.0',
        changelog:
            '# demo Changelog\n\n## v0.6.0 - 2026-11-10\n\nintro\n\n'
            '### Fixes\n\n- fix one\n\n## v0.5.0\n\n- other\n',
      );
      _git(work, ['tag', 'v0.6.0']);
      await verify('v0.6.0');
      expect(notes(), '\nintro\n\n### Fixes\n\n- fix one\n\n');
    },
  );

  test('notes of the last section run to the end of the file', () async {
    releaseCommit(
      pubspecVersion: '0.6.0',
      changelog: '# demo Changelog\n\n## v0.6.0\n\n- last\n- entries\n',
    );
    _git(work, ['tag', 'v0.6.0']);
    await verify('v0.6.0');
    expect(notes(), '\n- last\n- entries\n');
  });

  test('empty changelog section is refused', () async {
    releaseCommit(
      pubspecVersion: '0.6.0',
      changelog: '# demo Changelog\n\n## v0.6.0\n\n  \n\n## v0.5.0\n\n- x\n',
    );
    _git(work, ['tag', 'v0.6.0']);
    final e = await refusal('v0.6.0');
    expect(e.message, contains('## v0.6.0'));
    expect(e.message.toLowerCase(), contains('empty'));
  });

  test('beta tag is a prerelease and never latest', () async {
    releaseCommit(
      pubspecVersion: '0.6.0-beta.1',
      changelog: _changelog('v0.6.0-beta.1'),
    );
    _git(work, ['tag', 'v0.6.0-beta.1']);
    await verify('v0.6.0-beta.1');
    expect(meta(), {
      'tag': 'v0.6.0-beta.1',
      'version': '0.6.0-beta.1',
      'prerelease': true,
      'latest': false,
    });
  });

  test('highest final tag is latest', () async {
    releaseCommit(pubspecVersion: '0.6.0', changelog: _changelog('v0.6.0'));
    // Lower finals and a higher prerelease do not outrank it.
    for (final t in ['v0.5.0', 'v0.6.0-rc.1', 'v0.7.0-beta.1', 'v0.6.0']) {
      _git(work, ['tag', t]);
    }
    await verify('v0.6.0');
    expect(meta()['latest'], isTrue);
  });

  test('lower final tag than an existing final is not latest', () async {
    releaseCommit(pubspecVersion: '0.6.0', changelog: _changelog('v0.6.0'));
    _git(work, ['tag', 'v0.6.0']);
    _git(work, ['tag', 'v0.6.1']);
    await verify('v0.6.0');
    expect(meta(), {
      'tag': 'v0.6.0',
      'version': '0.6.0',
      'prerelease': false,
      'latest': false,
    });
  });

  test(
    'the heading release:prepare renders for a beta is found by verify-tag',
    () async {
      final repoRoot = Directory.current.absolute.path;
      File('$repoRoot/cliff.toml').copySync('${work.path}/cliff.toml');
      commitFiles({}, 'feat(map): add a thing (#9)');
      final render = await Process.run(
        'dart',
        [
          'run',
          '$repoRoot/tool/changelog.dart',
          '--tag',
          'v0.6.0-beta.1',
          '--output',
          'CHANGELOG.md',
        ],
        workingDirectory: work.path,
        // dart is a .bat shim on Windows.
        runInShell: Platform.isWindows,
        environment: _identity,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(render.exitCode, 0, reason: '${render.stderr}');
      final changelog = File('${work.path}/CHANGELOG.md').readAsStringSync();
      expect(
        changelog,
        contains(RegExp(r'^## v0\.6\.0-beta\.1\b', multiLine: true)),
      );

      releaseCommit(pubspecVersion: '0.6.0-beta.1', changelog: changelog);
      _git(work, ['tag', 'v0.6.0-beta.1']);
      await verify('v0.6.0-beta.1');
      expect(notes(), contains('add a thing (#9)'));
    },
  );
}
