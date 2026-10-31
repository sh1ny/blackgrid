import 'dart:convert';
import 'dart:io';

import 'git.dart';
import 'semver.dart';

/// Runs the `verify-tag` flow (design D3) inside the tag's checkout.
///
/// Refuses, naming the failed check, unless [tag] is `v` plus a strict SemVer
/// release version, its commit is on the first-parent line of `origin/main`,
/// that commit's `pubspec.yaml` carries the tag's version, and its
/// `CHANGELOG.md` has a non-empty `## <tag>` section. On success writes
/// `notes.md` (the section body, verbatim) and `release.json` to [outDir]
/// through a temporary file and a rename.
///
/// Whether the tag is annotated is a preflight concern, not checked here.
/// Throws [ReleaseException] on the first refusal.
Future<void> verifyTag({
  required String tag,
  required Directory outDir,
  required Directory repoDir,
  required CommandRunner runner,
  StringSink? out,
}) async {
  final sink = out ?? stdout;
  final git = Git(runner, repoDir);

  // 1. The name.
  final SemVer version;
  try {
    if (!tag.startsWith('v')) {
      throw FormatException('"$tag" has no "v" prefix');
    }
    version = SemVer.parseRelease(tag.substring(1));
  } on FormatException catch (e) {
    throw ReleaseException(
      'Tag "$tag" is not a strict SemVer release version (v + '
      'MAJOR.MINOR.PATCH[-prerelease], no build metadata): ${e.message}',
    );
  }
  final versionText = version.toString();

  // 2. The commit is on main's first-parent line.
  final commit = await git.output([
    'rev-parse',
    '--verify',
    '$tag^{commit}',
  ], failure: 'Tag "$tag" does not name a commit');
  final firstParent = (await git.output([
    'rev-list',
    '--first-parent',
    'origin/main',
  ], failure: 'Cannot list the first-parent line of origin/main')).split('\n');
  if (!firstParent.contains(commit)) {
    throw ReleaseException(
      'Tag "$tag" ($commit) is not on main\'s first-parent line of '
      'origin/main; a commit on a branch, or one that reached main only '
      'through a merged branch, cannot be released.',
    );
  }

  // 3. The pubspec version equals the tag's version.
  final pubspec = await git.output([
    'show',
    '$commit:pubspec.yaml',
  ], failure: 'Cannot read pubspec.yaml at $tag');
  final pubspecVersion = RegExp(
    r'^version:[ \t]*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec)?.group(1);
  if (pubspecVersion != versionText) {
    throw ReleaseException(
      'Tag "$tag" says $versionText but pubspec.yaml says '
      '${pubspecVersion ?? '(no version)'}.',
    );
  }

  // 4. The changelog section is present and non-empty.
  final changelog = await git.output([
    'show',
    '$commit:CHANGELOG.md',
  ], failure: 'Cannot read CHANGELOG.md at $tag');
  final body = _section(changelog, tag);
  if (body == null) {
    throw ReleaseException(
      'CHANGELOG.md has no "## $tag" section (missing section).',
    );
  }
  if (body.every((line) => line.trim().isEmpty)) {
    throw ReleaseException('The "## $tag" section of CHANGELOG.md is empty.');
  }

  // Prerelease versions are never latest; a final version is latest only when
  // no final release tag outranks it.
  final tags = (await git.output([
    'tag',
    '--list',
    'v*',
  ], failure: 'Cannot list tags')).split('\n');
  final latest = version.preRelease.isEmpty && !_outranked(version, tags);

  outDir.createSync(recursive: true);
  _writeAtomically(
    File('${outDir.path}/notes.md'),
    body.map((l) => '$l\n').join(),
  );
  _writeAtomically(
    File('${outDir.path}/release.json'),
    '${jsonEncode({'tag': tag, 'version': versionText, 'prerelease': version.preRelease.isNotEmpty, 'latest': latest})}\n',
  );
  sink.writeln(
    'Verified $tag (${latest ? 'latest' : 'not latest'}); notes and '
    'metadata are in ${outDir.path}.',
  );
}

/// The lines between the `## <tag>` heading and the next `## ` heading (or the
/// end of the file), or null when the heading is absent. The heading may carry
/// a suffix after a space, such as ` - 2026-11-10`, but `## v0.6.0-beta.1` is
/// not the heading of `v0.6.0`.
List<String>? _section(String changelog, String tag) {
  final lines = changelog.split(RegExp(r'\r?\n'));
  // A trailing newline yields one phantom empty element.
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  final heading = RegExp('^## ${RegExp.escape(tag)}(?:[ \\t].*)?\$');
  final start = lines.indexWhere(heading.hasMatch);
  if (start < 0) return null;
  final end = lines.indexWhere((l) => l.startsWith('## '), start + 1);
  return lines.sublist(start + 1, end < 0 ? lines.length : end);
}

/// Whether a final `v*` tag in [tags] has higher precedence than [version].
bool _outranked(SemVer version, Iterable<String> tags) {
  for (final t in tags) {
    if (!releaseTagPattern.hasMatch(t)) continue;
    final other = SemVer.tryParse(t.substring(1))!;
    if (other.build.isNotEmpty || other.preRelease.isNotEmpty) continue;
    if (other.compareTo(version) > 0) return true;
  }
  return false;
}

void _writeAtomically(File target, String content) {
  final temp = File('${target.path}.tmp')..writeAsStringSync(content);
  temp.renameSync(target.path);
}
