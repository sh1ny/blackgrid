import 'dart:io';

import 'git.dart';
import 'semver.dart';

const releaseGates = ['analyze', 'format:check', 'test:all'];

/// Runs the `prepare` flow (design D4 steps 1-11). Throws [ReleaseException]
/// on the first refusal or failure. Never pushes.
Future<void> prepare({
  required String version,
  required Directory repoDir,
  required CommandRunner runner,
  List<String> trailers = const [],
  StringSink? out,
}) async {
  final sink = out ?? stdout;
  final git = Git(runner, repoDir);
  final tag = 'v$version';
  final branch = 'release/$tag';

  // 1. Validate the version.
  final SemVer requested;
  try {
    requested = SemVer.parseRelease(version);
  } on FormatException catch (e) {
    throw ReleaseException(e.message);
  }

  // 2. On main with a clean tree.
  final current = await git.output(['branch', '--show-current']);
  if (current != 'main') {
    throw ReleaseException(
      'Release preparation must start from main, but the current branch is '
      '"${current.isEmpty ? '(detached HEAD)' : current}".',
    );
  }
  final dirty = await git.output([
    'status',
    '--porcelain',
    '--untracked-files=all',
  ]);
  if (dirty.isNotEmpty) {
    throw ReleaseException(
      'The working tree is not clean; commit, stash or remove:\n$dirty',
    );
  }

  // 3. Fetch and compare with origin/main.
  final fetch = await git.run(['fetch', 'origin', 'main', '--tags']);
  if (fetch.exitCode != 0) {
    throw ReleaseException(
      'git fetch origin main --tags failed: ${fetch.stderr.trim()}',
    );
  }
  final head = await git.output(['rev-parse', 'HEAD']);
  final remote = await git.output(['rev-parse', 'refs/remotes/origin/main']);
  if (head != remote) {
    throw ReleaseException(
      'Local main ($head) differs from origin/main ($remote). '
      'Update main first.',
    );
  }

  // 4. Strictly increasing version.
  final tags = (await git.output(['tag', '--list']))
      .split('\n')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty);
  final latest = latestReleaseTag(tags);
  final refusal = increaseRefusal(requested, latest);
  if (refusal != null) throw ReleaseException(refusal);

  // 5. Tag and branch absent locally and on origin.
  for (final ref in ['refs/tags/$tag', 'refs/heads/$branch']) {
    final local = await git.run(['rev-parse', '--verify', '--quiet', ref]);
    if (local.exitCode == 0) {
      throw ReleaseException('$ref already exists locally.');
    }
    final remoteRefs = await git.output([
      'ls-remote',
      'origin',
      ref,
    ], failure: 'git ls-remote origin $ref failed');
    if (remoteRefs.isNotEmpty) {
      throw ReleaseException('$ref already exists on origin.');
    }
  }

  // 6. Offline gates; nothing has been changed so far.
  for (final gate in releaseGates) {
    sink.writeln('Running gate: mise run $gate');
    final r = await runner.run(
      'mise',
      ['run', gate],
      workingDirectory: repoDir.path,
      stream: true,
    );
    if (r.exitCode != 0) {
      throw ReleaseException(
        'Gate "$gate" failed with exit code ${r.exitCode}; nothing changed.',
        exitCode: r.exitCode,
      );
    }
  }

  // 7. From here on, failures leave the branch behind.
  await git.output(['checkout', '-b', branch]);
  String leftover(String problem) =>
      '$problem\nBranch $branch was created and pubspec.yaml / CHANGELOG.md '
      'may be modified, but nothing was committed. Discard with:\n'
      '  git checkout -- pubspec.yaml CHANGELOG.md\n'
      '  git checkout main && git branch -D $branch';

  try {
    // 8. Rewrite the version line.
    _setPubspecVersion(File('${repoDir.path}/pubspec.yaml'), version);

    // 9. Regenerate the changelog. Run the Dart executable running this tool:
    // on Windows the `dart` on PATH is a .bat shim that needs a shell.
    final changelog = await runner.run(Platform.resolvedExecutable, [
      'run',
      'tool/changelog.dart',
      '--tag',
      tag,
      '--output',
      'CHANGELOG.md',
    ], workingDirectory: repoDir.path);
    if (changelog.exitCode != 0) {
      throw ReleaseException(
        leftover(
          'Changelog generation failed (exit code ${changelog.exitCode}): '
          '${changelog.stderr.trim()}',
        ),
      );
    }

    // 10. Commit.
    await git.output(['add', 'pubspec.yaml', 'CHANGELOG.md']);
    await git.output([
      'commit',
      '-m',
      'chore(release): $tag',
      for (final t in trailers) ...['--trailer', t],
    ]);
  } on ReleaseException catch (e) {
    if (e.message.contains('Branch $branch was created')) rethrow;
    throw ReleaseException(leftover(e.message), exitCode: e.exitCode);
  }

  // 11. Information and next commands.
  try {
    final bumped = await runner.run('git-cliff', [
      '--offline',
      '--config',
      'cliff.toml',
      '--bumped-version',
    ], workingDirectory: repoDir.path);
    if (bumped.exitCode == 0 && bumped.stdout.trim().isNotEmpty) {
      sink.writeln('git-cliff suggested next version: ${bumped.stdout.trim()}');
    }
  } on Object {
    // Informational only.
  }
  sink.writeln('Release commit created on $branch. Next:');
  sink.writeln('  git push -u origin $branch');
  sink.writeln(
    '  gh pr create --base main --head $branch '
    '--title "chore(release): $tag"',
  );
}

void _setPubspecVersion(File pubspec, String version) {
  final text = pubspec.readAsStringSync();
  final pattern = RegExp(r'^version:[^\r\n]*', multiLine: true);
  final matches = pattern.allMatches(text).length;
  if (matches != 1) {
    throw ReleaseException(
      'Expected exactly one "version:" line in pubspec.yaml, found $matches.',
    );
  }
  // Replacement leaves the existing line terminators untouched.
  pubspec.writeAsStringSync(text.replaceFirst(pattern, 'version: $version'));
}
