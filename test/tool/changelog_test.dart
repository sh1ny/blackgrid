import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/changelog.dart';
import '../../tool/release/src/git.dart';

/// Tests for the release notes CLI in tool/changelog.dart, over temporary
/// git repositories. Requires git on PATH.
void main() {
  late Directory repo;
  late Git git;
  late StringBuffer out;
  late StringBuffer err;
  var clock = DateTime.utc(2026, 1, 1);

  Future<void> run(List<String> args) async {
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
    );
    if (result.exitCode != 0) {
      fail('git ${args.join(' ')} failed: ${result.stderr}');
    }
  }

  String proposal(String item) =>
      '# Change\n\n## Why\n\nBecause.\n\n## Release Notes\n\n'
      'Summary of the change.\n\n### Added\n\n- $item\n';

  /// Commits an archived proposal the way an archive commit does.
  Future<void> archive(String name, String item, int pr) async {
    final dir = Directory(
      '${repo.path}/openspec/changes/archive/2026-01-02-$name',
    )..createSync(recursive: true);
    File('${dir.path}/proposal.md').writeAsStringSync(proposal(item));
    await run(['add', '-A']);
    await run(['commit', '-m', 'feat($name): archive (#$pr)']);
  }

  Future<void> commit(String message) =>
      run(['commit', '--allow-empty', '-m', message]);

  Future<int> cli(List<String> args) =>
      runChangelog(args, git: git, out: out, err: err);

  Future<String> status() async {
    final result = await Process.run('git', [
      'status',
      '--porcelain',
    ], workingDirectory: repo.path);
    return result.stdout as String;
  }

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('changelog_test_');
    git = Git(const ProcessCommandRunner(), repo);
    out = StringBuffer();
    err = StringBuffer();
    clock = DateTime.utc(2026, 1, 1);
    await run(['init', '-b', 'main']);
  });

  tearDown(() async {
    await repo.delete(recursive: true);
  });

  test('preview prints grouped items and uncovered direct commits and changes '
      'no file', () async {
    await commit('chore: initial');
    await run(['tag', '-a', 'v0.6.0', '-m', 'v0.6.0']);
    await archive('first-thing', 'Adds the first thing.', 11);
    await commit('docs(readme): fix typo');
    await archive('second-thing', 'Adds the second thing.', 12);

    final before = await status();
    final code = await cli([]);

    expect(code, 0, reason: '$err');
    final text = out.toString();
    expect(text, contains('Added:'));
    expect(text, contains('- Adds the first thing. (#11)'));
    expect(text, contains('- Adds the second thing. (#12)'));
    expect(text, contains('Not covered by a change:'));
    expect(text, contains('docs(readme): fix typo'));
    expect(text, isNot(contains('feat(first-thing): archive')));
    expect(await status(), before);
  });

  test(
    'preview with nothing since the last final tag says so and exits 0',
    () async {
      await commit('chore: initial');
      await run(['tag', '-a', 'v0.6.0', '-m', 'v0.6.0']);

      final code = await cli([]);

      expect(code, 0, reason: '$err');
      expect(out.toString(), contains('Nothing to release since v0.6.0'));
    },
  );

  test('check accepts a valid proposal and prints its summary', () async {
    final file = File('${repo.path}/proposal.md')
      ..writeAsStringSync(proposal('Adds a thing.'));

    final code = await cli(['--check', file.path]);

    expect(code, 0, reason: '$err');
    expect(out.toString(), contains('Summary of the change.'));
  });

  test('check reports each error with its line and exits 1', () async {
    final file = File('${repo.path}/proposal.md')
      ..writeAsStringSync(
        '# Change\n\n## Release Notes\n\nSummary.\n\n### Bogus\n\n- x\n\n'
        '### Added\n\nnot an item\n',
      );

    final code = await cli(['--check', file.path]);

    expect(code, 1);
    final text = err.toString();
    expect(text, contains("line 7: unknown heading 'Bogus'"));
    expect(text, contains('line 13: line is neither a list item'));
  });

  test('check of a proposal without a section exits 1', () async {
    final file = File('${repo.path}/proposal.md')
      ..writeAsStringSync('# Change\n\n## Why\n\nBecause.\n');

    final code = await cli(['--check', file.path]);

    expect(code, 1);
    expect(err.toString(), contains('no release notes'));
  });

  test('check of a missing file exits 2', () async {
    final code = await cli(['--check', '${repo.path}/missing.md']);

    expect(code, 2);
    expect(err.toString(), contains('missing.md'));
  });

  test('unknown options and extra arguments exit 2 with usage', () async {
    expect(await cli(['--current']), 2);
    expect(err.toString(), contains('Usage'));
    expect(await cli(['--check']), 2);
    expect(await cli(['stray']), 2);
  });
}
