import 'dart:io';

import 'git.dart';
import 'release_notes.dart';
import 'semver.dart';

const releaseGates = ['analyze', 'format:check', 'test:all'];

/// Runs the `prepare` flow (design D4 steps 1-11). Throws [ReleaseException]
/// on the first refusal or failure. Never pushes.
Future<void> prepare({
  required String version,
  required Directory repoDir,
  required CommandRunner runner,
  List<String> trailers = const [],
  String? summary,
  DateTime? now,
  StringSink? out,
}) async {
  final sink = out ?? stdout;
  final git = Git(runner, repoDir);
  final tag = 'v$version';
  final branch = 'release/$tag';

  // 0. The summary, before anything is read or run.
  final collapsed = summary == null ? '' : collapseSummary(summary);
  if (collapsed.isEmpty) {
    throw const ReleaseException(
      'A release summary is required: pass --summary <text> or '
      '--summary-file <path> (the summary is blank or missing).',
    );
  }
  if (collapsed.length > maxSummary) {
    throw ReleaseException(
      'The release summary is ${collapsed.length} characters after '
      'collapsing whitespace, over the $maxSummary limit.',
    );
  }
  // The summary is the section's first line, so a leading `## ` would end
  // the section there in verify-tag, after the tag is pushed.
  if (collapsed.startsWith('#')) {
    throw const ReleaseException(
      'The release summary starts with `#`; it must not, because as the '
      'first line of the CHANGELOG.md section a heading would end the section '
      'in verify-tag. Start it with plain text (write "PR #69", not "#69").',
    );
  }

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

  // 5b. Build and validate the section in memory.
  final range = await readReleaseRange(git);
  if (range.changes.isEmpty) {
    throw ReleaseException(
      'Nothing to release: no change was archived on main since '
      '${range.lastFinalTag ?? 'the first commit'}.',
    );
  }
  final rendered = renderReleaseNotes(collapsed, range.changes);

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
      'may be modified or staged, but nothing was committed. Discard with:\n'
      '  git restore --staged --worktree -- pubspec.yaml CHANGELOG.md\n'
      '  git checkout main && git branch -D $branch';

  try {
    // 8. Rewrite the version line.
    _setPubspecVersion(File('${repoDir.path}/pubspec.yaml'), version);

    // 9. Insert the section above the newest one.
    final changelogFile = File('${repoDir.path}/CHANGELOG.md');
    try {
      final existing = changelogFile.existsSync()
          ? changelogFile.readAsStringSync()
          : '';
      changelogFile.writeAsStringSync(
        insertChangelogSection(
          existing: existing,
          version: version,
          date: _isoDate(now ?? DateTime.now()),
          body: rendered.body,
        ),
      );
    } on FileSystemException catch (e) {
      throw ReleaseException(
        leftover('Writing CHANGELOG.md failed: ${e.message} (${e.path}).'),
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

  // 11. Warnings and next commands.
  for (final warning in rendered.warnings) {
    sink.writeln('Warning: $warning');
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

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

final RegExp _anySpace = RegExp(r'\s+');
final RegExp _versionHeading = RegExp(r'^## v(\S+)', multiLine: true);
final RegExp _anyHeading = RegExp(r'^## ', multiLine: true);

/// Collapses every whitespace run, newlines included, to one space and trims.
String collapseSummary(String text) => text.replaceAll(_anySpace, ' ').trim();

/// Returns [existing] with a `## v<version> - <date>` section holding [body]
/// directly above its newest `## v` section.
///
/// Every other byte of [existing] is kept, except that a final [version] drops
/// the sections of its own prereleases (`## v<version>-<pre> ...`, up to the
/// next `## ` heading). With no `## v` section the new one goes after the
/// existing text, and an empty [existing] gets the `# Blackgrid Changelog`
/// title first. The section uses the line ending [existing] uses, `\n` when
/// it has none.
String insertChangelogSection({
  required String existing,
  required String version,
  required String date,
  required String body,
}) {
  final eol = existing.contains('\r\n') ? '\r\n' : '\n';
  var text = existing.isEmpty ? '# Blackgrid Changelog$eol$eol' : existing;

  if (!version.contains('-')) {
    final headings = _anyHeading.allMatches(text).map((m) => m.start).toList();
    final removals = <(int, int)>[];
    for (final m in _versionHeading.allMatches(text)) {
      if (!m[1]!.startsWith('$version-')) continue;
      final next = headings.where((h) => h > m.start);
      removals.add((m.start, next.isEmpty ? text.length : next.first));
    }
    for (final (start, end) in removals.reversed) {
      text = text.replaceRange(start, end, '');
    }
  }

  final section =
      '## v$version - $date$eol$eol${body.replaceAll('\n', eol)}$eol$eol';
  final newest = _versionHeading.firstMatch(text);
  if (newest != null) {
    return text.replaceRange(newest.start, newest.start, section);
  }
  final kept = text.trimRight();
  return '$kept$eol$eol${section.trimRight()}$eol';
}
