import 'dart:convert';
import 'dart:io';

import 'git.dart';
import 'push_identity.dart';
import 'semver.dart';

final _releaseSubject = RegExp(r'^chore\(release\): v(.+)$');
final _squashSubject = RegExp(r'^chore\(release\): v(.+) \(#(\d+)\)$');
final _githubUrl = RegExp(
  r'^https://github\.com/([^/@]+)/([^/@]+?)(?:\.git)?/?$',
  caseSensitive: false,
);

/// Runs the `tag` flow (design D5, D6). Throws [ReleaseException] on the
/// first refusal or failure. Pushes only `refs/tags/v<version>`.
///
/// `HEAD` is either a merge commit of a `chore(release): v<version>` commit
/// or a squash commit titled `chore(release): v<version> (#<pr>)` that GitHub
/// confirms is the merge of exactly that release commit.
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

  // HEAD must be the merge or the squash of a release commit.
  final headSubject = await git.output(['log', '-1', '--format=%s', 'HEAD']);
  final parents = (await git.output([
    'rev-list',
    '--parents',
    '-n',
    '1',
    'HEAD',
  ])).split(' ').skip(1).toList();
  final squash = parents.length == 1
      ? _squashSubject.firstMatch(headSubject)
      : null;
  final String version;
  if (squash != null) {
    version = _parseVersion(squash.group(1)!, 'HEAD "$headSubject"');
    await _checkSquash(
      git: git,
      identity: identity,
      repoDir: repoDir,
      head: head,
      mainBase: parents[0],
      version: version,
      pr: int.parse(squash.group(2)!),
    );
  } else {
    version = await _checkMerge(git, headSubject, parents);
  }
  final tagName = 'v$version';
  final tagRef = 'refs/tags/$tagName';

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
  final repo = _githubRepo(await _fetchUrl(git));
  sink.writeln(
    repo == null
        ? 'The release workflow publishes the release; watch it on the '
              'repository\'s Actions page.'
        : 'The release workflow publishes the release; watch it at '
              'https://github.com/$repo/actions/workflows/release.yml',
  );
}

String _parseVersion(String raw, String what) {
  try {
    return SemVer.parseRelease(raw).toString();
  } on FormatException catch (e) {
    throw ReleaseException('$what has an invalid version: ${e.message}');
  }
}

Future<String> _fetchUrl(Git git) => git.output([
  'remote',
  'get-url',
  'origin',
], failure: 'Could not read the URL of origin');

/// `<owner>/<repo>` of a github.com HTTPS [url], or `null`.
String? _githubRepo(String url) {
  final match = _githubUrl.firstMatch(url);
  return match == null ? null : '${match[1]}/${match[2]}';
}

/// Checks the ordinary merge shape (design D5) and returns the version.
Future<String> _checkMerge(
  Git git,
  String headSubject,
  List<String> parents,
) async {
  if (parents.length != 2) {
    throw ReleaseException(
      'HEAD is not a release merge: "$headSubject" has ${parents.length} '
      'parent(s), expected a merge with exactly two or a squash titled '
      '"chore(release): v<version> (#<pr>)".',
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
  final version = _parseVersion(
    match.group(1)!,
    'Release commit "$releaseSubject"',
  );

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
      'Delete release/v$version locally and on origin, then run '
      'release:prepare again for $version.',
    );
  }
  return version;
}

/// Confirms through the GitHub API that squash commit [head] is the merge of
/// PR [pr] and that the PR's single commit is the release commit (design D6).
Future<void> _checkSquash({
  required Git git,
  required PushIdentity identity,
  required Directory repoDir,
  required String head,
  required String mainBase,
  required String version,
  required int pr,
}) async {
  final repo = _githubRepo(await _fetchUrl(git));
  if (repo == null) {
    throw ReleaseException(
      'HEAD is a squash merge of PR #$pr, but origin is not an HTTPS '
      'github.com URL, so the PR cannot be verified.',
    );
  }
  final branch = 'release/v$version';

  Future<Object?> read(String endpoint) async {
    final r = await git.runner.run(
      'gh',
      ['api', '--hostname', 'github.com', endpoint],
      workingDirectory: repoDir.path,
      environment: identity.environment,
    );
    if (r.exitCode != 0) {
      throw ReleaseException(
        'Could not read PR #$pr ($endpoint): ${r.stderr.trim()}',
      );
    }
    try {
      return jsonDecode(r.stdout);
    } on FormatException catch (e) {
      throw ReleaseException(
        'Could not read PR #$pr ($endpoint): invalid JSON: ${e.message}',
      );
    }
  }

  ReleaseException refuse(String check) => ReleaseException(
    'HEAD is not the release squash: PR #$pr failed a check: $check.',
  );

  final prBody = await read('repos/$repo/pulls/$pr');
  if (prBody is! Map<String, Object?>) throw refuse('unexpected PR response');
  if (prBody['merged'] != true) throw refuse('the PR is not merged');
  if (prBody['merge_commit_sha'] != head) {
    throw refuse(
      'its merge commit is ${prBody['merge_commit_sha']}, not HEAD $head',
    );
  }
  final headRef = switch (prBody['head']) {
    {'ref': final String ref} => ref,
    _ => null,
  };
  if (headRef != branch) {
    throw refuse('it was merged from "$headRef", not $branch');
  }
  if (prBody['commits'] != 1) {
    throw refuse('it has ${prBody['commits']} commits, expected exactly 1');
  }

  final commits = await read('repos/$repo/pulls/$pr/commits');
  final entry = switch (commits) {
    [final Map<String, Object?> only] => only,
    _ => throw refuse('its commit list does not hold exactly 1 commit'),
  };
  final sha = entry['sha'];
  final message = switch (entry['commit']) {
    {'message': final String m} => m,
    _ => '',
  };
  final subject = message.split('\n').first;
  if (sha is! String || subject != 'chore(release): v$version') {
    throw refuse('its commit is "$subject", not "chore(release): v$version"');
  }
  final releaseBase = switch (entry['parents']) {
    [{'sha': final String parent}] => parent,
    _ => null,
  };
  if (releaseBase != mainBase) {
    // The old base is normally still local; naming the intervening commits
    // is best effort if it is not.
    final log = await git.run(['log', '--oneline', '$releaseBase..$mainBase']);
    final intervening = log.exitCode == 0
        ? log.stdout.trim()
        : '(unavailable locally)';
    throw ReleaseException(
      'Main moved after the release was prepared (PR #$pr); the release '
      'commit was built on $releaseBase but was squashed onto $mainBase. '
      'Intervening commits:\n$intervening\n'
      'Delete $branch locally and on origin, then run release:prepare '
      'again for $version.',
    );
  }

  final commitBody = await read('repos/$repo/git/commits/$sha');
  final apiTree = switch (commitBody) {
    {'tree': {'sha': final String tree}} => tree,
    _ => null,
  };
  final headTree = await git.output(['rev-parse', 'HEAD^{tree}']);
  if (apiTree != headTree) {
    throw refuse(
      'the release commit tree ($apiTree) differs from the tree of HEAD '
      '($headTree)',
    );
  }
}
