import 'dart:io';

import 'git.dart';
import 'push_identity.dart';
import 'semver.dart';

final _releaseSubject = RegExp(r'^chore\(release\): v(.+)$');

/// Runs the `tag` flow (design D5). Throws [ReleaseException] on the first
/// refusal or failure. Pushes only `refs/tags/v<version>`.
Future<void> tag({
  required Directory repoDir,
  required CommandRunner runner,
  StringSink? out,
}) async {
  final sink = out ?? stdout;
  final git = Git(runner, repoDir);

  // Clean main (local checks first, nothing touches the network yet).
  final current = await git.output(['branch', '--show-current']);
  if (current != 'main') {
    throw ReleaseException(
      'Tagging must run on main, but the current branch is '
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

  // Identity is confirmed before the first network call and before any tag.
  final identity = await PushIdentity.confirm(repoDir: repoDir, runner: runner);

  final fetch = await identity.git(git, ['fetch', 'origin', 'main', '--tags']);
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

  // HEAD must be the merge of a release commit.
  final headSubject = await git.output(['log', '-1', '--format=%s', 'HEAD']);
  final parents = (await git.output([
    'rev-list',
    '--parents',
    '-n',
    '1',
    'HEAD',
  ])).split(' ').skip(1).toList();
  if (parents.length != 2) {
    throw ReleaseException(
      'HEAD is not a release merge: "$headSubject" has ${parents.length} '
      'parent(s), expected a merge with exactly two.',
    );
  }
  final releaseCommit = parents[1];
  final releaseSubject = await git.output([
    'log',
    '-1',
    '--format=%s',
    releaseCommit,
  ]);
  final match = _releaseSubject.firstMatch(releaseSubject);
  if (match == null) {
    throw ReleaseException(
      'HEAD is not a release merge: "$headSubject" merges '
      '"$releaseSubject", not a "chore(release): v<version>" commit.',
    );
  }
  final String version;
  try {
    version = SemVer.parseRelease(match.group(1)!).toString();
  } on FormatException catch (e) {
    throw ReleaseException(
      'Release commit "$releaseSubject" has an invalid version: ${e.message}',
    );
  }
  final tagName = 'v$version';
  final tagRef = 'refs/tags/$tagName';

  // Main must not have moved between prepare and the release merge.
  final releaseBase = await git.output(['rev-parse', '$releaseCommit^1']);
  final mainBase = parents[0];
  if (releaseBase != mainBase) {
    final intervening = await git.output([
      'log',
      '--oneline',
      '$releaseBase..$mainBase',
    ]);
    throw ReleaseException(
      'Main moved after the release was prepared; the release commit was '
      'built on $releaseBase but was merged onto $mainBase. Intervening '
      'commits:\n$intervening\n'
      'Delete release/$tagName locally and on origin, then run '
      'release:prepare again for $version.',
    );
  }

  // Pubspec must carry the release version.
  final pubspec = File('${repoDir.path}/pubspec.yaml').readAsStringSync();
  final pubspecVersion = RegExp(
    r'^version:[ \t]*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec)?.group(1);
  if (pubspecVersion != version) {
    throw ReleaseException(
      'The release commit says $version but pubspec.yaml says '
      '${pubspecVersion ?? '(no version)'}.',
    );
  }

  // Tag must not exist locally or on origin.
  final local = await git.run(['rev-parse', '--verify', '--quiet', tagRef]);
  if (local.exitCode == 0) {
    throw ReleaseException('$tagRef already exists locally.');
  }
  final remoteRefs = await identity.gitOutput(git, [
    'ls-remote',
    'origin',
    tagRef,
  ], failure: 'git ls-remote origin $tagRef failed');
  if (remoteRefs.isNotEmpty) {
    throw ReleaseException('$tagRef already exists on origin.');
  }

  // Tag HEAD, push only that tag, roll back the local tag on failure.
  await git.output(['tag', '-a', tagName, '-m', tagName, 'HEAD']);
  final push = await identity.git(git, ['push', 'origin', tagRef]);
  if (push.exitCode != 0) {
    await git.run(['tag', '-d', tagName]);
    throw ReleaseException(
      'git push origin $tagRef failed; the local tag was deleted: '
      '${push.stderr.trim()}',
    );
  }
  sink.writeln('Tagged $tagName at $head and pushed it to origin.');
}
