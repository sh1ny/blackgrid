import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fixture-repo tests for tool/changelog.dart and cliff.toml.
///
/// Requires git, dart and git-cliff on PATH (`mise run test` provides them).
void main() {
  final repoRoot = Directory.current.absolute.path;
  final changelogScript =
      '$repoRoot${Platform.pathSeparator}tool'
      '${Platform.pathSeparator}changelog.dart';
  final cliffConfig = File('$repoRoot${Platform.pathSeparator}cliff.toml');

  late Directory repo;
  var clock = DateTime.utc(2026, 1, 1);

  Future<ProcessResult> git(List<String> args) async {
    clock = clock.add(const Duration(minutes: 1));
    final stamp = clock.toIso8601String();
    final result = await Process.run(
      'git',
      [
        '-c',
        'user.name=Test',
        '-c',
        'user.email=test@example.com',
        '-c',
        'commit.gpgsign=false',
        '-c',
        'tag.gpgsign=false',
        ...args,
      ],
      workingDirectory: repo.path,
      environment: {'GIT_AUTHOR_DATE': stamp, 'GIT_COMMITTER_DATE': stamp},
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      fail('git ${args.join(' ')} failed: ${result.stderr}');
    }
    return result;
  }

  Future<void> commit(String message) =>
      git(['commit', '--allow-empty', '-m', message]);

  /// Branch with [branchCommits], merged the way GitHub does it.
  Future<void> mergePr(
    int number,
    String branch,
    String title,
    List<String> branchCommits,
  ) async {
    await git(['checkout', '-b', branch]);
    for (final message in branchCommits) {
      await commit(message);
    }
    await git(['checkout', 'main']);
    await git([
      'merge',
      '--no-ff',
      branch,
      '-m',
      'Merge pull request #$number from o/$branch\n\n$title',
    ]);
  }

  Future<void> tag(String name) => git(['tag', '-a', name, '-m', name]);

  Future<void> buildToV010() async {
    await commit('chore: initial');
    await tag('v0.1.0');
  }

  Future<void> buildToBeta() async {
    await mergePr(
      15,
      'release-versioning',
      'feat(release): add release versioning',
      [
        'feat(release): task 1.1 write ADR',
        'docs(release): amend specs',
        'fix(release): address review feedback',
      ],
    );
    await mergePr(16, 'readme', 'Tidy the readme', [
      'docs: task 2.1 readme pass',
    ]);
    await mergePr(17, 'unicode', 'fix(ui): zażółć gęślą jaźń 日本語', [
      'fix(ui): task 3.1 unicode',
    ]);
    await commit('fix: direct repair');
    await tag('v0.2.0-beta.1');
  }

  Future<void> buildReleaseMerge0() async {
    await mergePr(18, 'faster-scan', 'perf: faster scan', [
      'perf: task 4.1 scan',
    ]);
    await mergePr(19, 'release-0.2.0', 'chore(release): v0.2.0', [
      'chore(release): v0.2.0',
    ]);
  }

  Future<void> buildReleaseMerge() async {
    await buildReleaseMerge0();
    await tag('v0.2.0');
  }

  Future<void> buildLaterPr() =>
      mergePr(20, 'later', 'test: later thing', ['test: task 5.1 later']);

  Future<ProcessResult> run(List<String> args) => Process.run(
    'dart',
    ['run', changelogScript, ...args],
    workingDirectory: repo.path,
    // dart is a .bat shim on Windows.
    runInShell: Platform.isWindows,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  Future<String> ok(List<String> args) async {
    final result = await run(args);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result.stdout as String;
  }

  /// The text of the `## <heading>` section, or null when absent.
  String? section(String changelog, String heading) {
    final parts = changelog.split(RegExp(r'^## ', multiLine: true));
    for (final part in parts.skip(1)) {
      if (part.split('\n').first.startsWith(heading)) return part;
    }
    return null;
  }

  /// The entry lines of the `### <heading>` group, or empty when absent.
  List<String> entries(String changelog, String heading) {
    final parts = changelog.split(RegExp(r'^### ', multiLine: true));
    for (final part in parts.skip(1)) {
      final lines = part.split('\n').map((line) => line.trimRight());
      if (lines.first != heading) continue;
      return lines
          .skip(1)
          .takeWhile((line) => !line.startsWith('## '))
          .where((line) => line.startsWith('- '))
          .toList();
    }
    return const [];
  }

  setUpAll(() async {
    final cliff = await Process.run('git-cliff', [
      '--version',
    ]).catchError((_) => ProcessResult(0, 127, '', ''));
    if (cliff.exitCode != 0) {
      fail('git-cliff is not on PATH. Run the tests with `mise run test`.');
    }
  });

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('changelog_test_');
    clock = DateTime.utc(2026, 1, 1);
    await git(['init', '-b', 'main']);
    await cliffConfig.copy('${repo.path}${Platform.pathSeparator}cliff.toml');
  });

  tearDown(() async {
    await repo.delete(recursive: true);
  });

  test(
    'merged PR is one entry with title and number; branch commits absent',
    () async {
      await buildToV010();
      await buildToBeta();
      final out = await ok(['--strip', 'header', 'v0.1.0..HEAD']);
      expect(out, contains('### Features'));
      expect(out, contains('- *(release)* add release versioning (#15)'));
      expect(out, isNot(contains('task 1.1')));
      expect(out, isNot(contains('amend specs')));
      expect(out, isNot(contains('address review feedback')));
      expect(out, isNot(contains('Merge pull request')));
      expect(RegExp('add release versioning').allMatches(out), hasLength(1));
    },
  );

  test('non-ASCII PR titles survive the two-stage pipeline', () async {
    await buildToV010();
    await buildToBeta();
    final out = await ok(['--strip', 'header', 'v0.1.0..HEAD']);
    expect(out, contains('- *(ui)* zażółć gęślą jaźń 日本語 (#17)'));
  });

  test('non-conventional PR title lands under Other', () async {
    await buildToV010();
    await buildToBeta();
    final out = await ok(['--strip', 'header', 'v0.1.0..HEAD']);
    expect(out, contains('### Other\n\n- Tidy the readme (#16)'));
    expect(out, isNot(contains('task 2.1')));
  });

  test('direct fix commit on main is listed once under Fixes', () async {
    await buildToV010();
    await buildToBeta();
    final out = await ok(['--strip', 'header', 'v0.1.0..HEAD']);
    final fixes = entries(out, 'Fixes');
    expect(fixes.where((line) => line == '- direct repair'), hasLength(1));
    final entry = fixes.singleWhere((line) => line.contains('direct repair'));
    expect(entry, isNot(contains('(#')));
    expect(RegExp('direct repair').allMatches(out), hasLength(1));
  });

  test('squash-merged PR is one entry with title and number', () async {
    await buildToV010();
    await commit('fix(map): centre marker tiles (#59)');
    final out = await ok(['--strip', 'header', 'v0.1.0..HEAD']);
    expect(
      entries(
        out,
        'Fixes',
      ).where((line) => line == '- *(map)* centre marker tiles (#59)'),
      hasLength(1),
    );
    expect(RegExp('centre marker tiles').allMatches(out), hasLength(1));
  });

  test('direct commit that mentions merging is still listed', () async {
    await buildToV010();
    await commit('fix: merge duplicate pins');
    final out = await ok(['--strip', 'header', 'v0.1.0..HEAD']);
    expect(
      entries(out, 'Fixes').where((line) => line == '- merge duplicate pins'),
      hasLength(1),
    );
    expect(RegExp('merge duplicate pins').allMatches(out), hasLength(1));
  });

  test('final release folds prerelease sections', () async {
    await buildToV010();
    await buildToBeta();
    await buildReleaseMerge0();
    final out = await ok(['--strip', 'header', '--tag', 'v0.2.0']);
    final release = section(out, 'v0.2.0');
    expect(release, isNotNull, reason: out);
    expect(release, contains('add release versioning (#15)'));
    expect(release, contains('Tidy the readme (#16)'));
    expect(release, contains('(#17)'));
    expect(release, contains('direct repair'));
    expect(release, contains('faster scan (#18)'));
    expect(out, isNot(contains('v0.2.0-beta.1')));
  });

  test('release commit and its merge are not listed', () async {
    await buildToV010();
    await buildToBeta();
    await buildReleaseMerge();
    final out = await ok(['--strip', 'header']);
    expect(out, isNot(contains('chore(release)')));
    expect(out, isNot(contains('v0.2.0 (#19)')));
    expect(out, isNot(contains('(#19)')));
    expect(out, isNot(contains('Merge pull request')));
    expect(out, contains('faster scan (#18)'));
  });

  test(
    '--latest and --unreleased use final-tag ranges after a final release',
    () async {
      await buildToV010();
      await buildToBeta();
      await buildReleaseMerge();
      await buildLaterPr();

      final latest = await ok(['--strip', 'header', '--latest']);
      expect(latest, contains('## v0.2.0'));
      expect(latest, contains('add release versioning (#15)'));
      expect(latest, contains('Tidy the readme (#16)'));
      expect(latest, contains('faster scan (#18)'));
      expect(latest, isNot(contains('later thing')));
      expect(latest, isNot(contains('v0.2.0-beta.1')));

      final unreleased = await ok(['--strip', 'header', '--unreleased']);
      expect(unreleased, contains('## Unreleased'));
      expect(unreleased, contains('later thing (#20)'));
      expect(unreleased, isNot(contains('faster scan')));
      expect(unreleased, isNot(contains('release versioning')));
    },
  );

  test('--unreleased while a beta is latest lists everything since last final '
      'tag', () async {
    await buildToV010();
    await buildToBeta();
    await mergePr(18, 'faster-scan', 'perf: faster scan', ['perf: task 4.1']);
    final out = await ok(['--strip', 'header', '--unreleased']);
    expect(out, contains('add release versioning (#15)'));
    expect(out, contains('Tidy the readme (#16)'));
    expect(out, contains('direct repair'));
    expect(out, contains('faster scan (#18)'));
    expect(out, isNot(contains('v0.2.0-beta.1')));
  });

  test('--latest with no previous final tag renders from the root', () async {
    await buildToV010();
    await mergePr(15, 'feature', 'feat: first feature', ['feat: task 1.1']);
    await tag('v0.1.1');
    await buildLaterPr();
    final out = await ok(['--strip', 'header', '--latest']);
    expect(out, contains('## v0.1.1'));
    expect(out, contains('first feature (#15)'));
    expect(out, isNot(contains('later thing')));

    // No previous final tag: only one final tag exists.
    final single = await Directory.systemTemp.createTemp('changelog_single_');
    addTearDown(() => single.delete(recursive: true));
    final saved = repo;
    repo = single;
    await git(['init', '-b', 'main']);
    await cliffConfig.copy('${repo.path}${Platform.pathSeparator}cliff.toml');
    await commit('feat: root feature');
    await tag('v0.1.0');
    await commit('fix: after tag');
    final fromRoot = await ok(['--strip', 'header', '--latest']);
    repo = saved;
    expect(fromRoot, contains('## v0.1.0'));
    expect(fromRoot, contains('root feature'));
    expect(fromRoot, isNot(contains('after tag')));
  });

  test('--output writes the full changelog with the header', () async {
    await buildToV010();
    await buildToBeta();
    await ok(['--output', 'CHANGELOG.md']);
    final file = File('${repo.path}${Platform.pathSeparator}CHANGELOG.md');
    final text = utf8.decode(file.readAsBytesSync());
    expect(text, startsWith('# blackgrid Changelog'));
    expect(text, contains('(#17)'));
    expect(text, contains('日本語'));
  });

  test('unknown options exit 2', () async {
    await buildToV010();
    final result = await run(['--current']);
    expect(result.exitCode, 2);
  });

  test('unborn HEAD renders an empty changelog', () async {
    final out = await ok([]);
    expect(out, contains('# blackgrid Changelog'));
    expect(out, contains('## Unreleased'));
  });
}
