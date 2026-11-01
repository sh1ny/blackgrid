import 'dart:convert';
import 'dart:io';

import 'release/src/git.dart';
import 'release/src/release_notes.dart';

/// Previews the next release's notes, or checks one proposal's section.
///
/// Usage: dart run tool/changelog.dart [--check <proposal.md>]
///
/// Without options it prints, changing no file, the notes the next release
/// would hold from the proposals archived since the last final tag, the
/// warnings, and the direct commits that no archived proposal covers.
Future<void> main(List<String> arguments) async {
  exitCode = await runChangelog(
    arguments,
    git: Git(const ProcessCommandRunner(), Directory.current),
    out: stdout,
    err: stderr,
  );
}

const String _usage =
    'Usage: dart run tool/changelog.dart [--check <proposal.md>]\n'
    '  (no option)         preview the next release notes\n'
    '  --check <file>      validate the release notes of one proposal';

const String _placeholderSummary =
    '<release summary: pass --summary or --summary-file to release:prepare>';

/// Runs the CLI for [arguments] in the repository of [git].
///
/// Normal output goes to [out], problems and usage to [err]. Returns the exit
/// code: 0 on success, 1 when a check finds a problem or git fails, 2 for a
/// usage error or a missing file.
Future<int> runChangelog(
  List<String> arguments, {
  required Git git,
  required StringSink out,
  required StringSink err,
}) async {
  switch (arguments) {
    case []:
      try {
        return await _preview(git, out);
      } on ReleaseException catch (error) {
        err.writeln('changelog: $error');
        return error.exitCode;
      }
    case ['--check', final path]:
      return _check(git.directory, path, out, err);
    default:
      err.writeln(
        'changelog: unsupported arguments: ${arguments.join(' ')}\n$_usage',
      );
      return 2;
  }
}

int _check(Directory base, String path, StringSink out, StringSink err) {
  final file = File(path);
  final resolved = file.isAbsolute ? file : File('${base.path}/$path');
  if (!resolved.existsSync()) {
    err.writeln('changelog: cannot read $path: no such file');
    return 2;
  }
  if (resolved.lengthSync() > maxProposalBytes) {
    err.writeln(
      '$path: proposal is over the ${maxProposalBytes ~/ 1024} KB limit',
    );
    return 1;
  }
  final text = utf8.decode(resolved.readAsBytesSync(), allowMalformed: true);
  switch (parseReleaseNotes(text)) {
    case ReleaseNotes(:final summary, :final items):
      out.writeln(summary);
      final counts = [
        for (final h in noteHeadings)
          if (items[h] case final list?) '$h: ${list.length}',
      ];
      out.writeln('Items - ${counts.join(', ')}');
      return 0;
    case ReleaseNotesInvalid(:final errors):
      for (final error in errors) {
        err.writeln('$path: $error');
      }
      return 1;
    case final NoReleaseNotes none:
      err.writeln('$path: ${none.message}');
      return 1;
  }
}

Future<int> _preview(Git git, StringSink out) async {
  final range = await readReleaseRange(git);
  final since = range.lastFinalTag ?? 'the start of history';
  final log = await git.output([
    'log',
    '--first-parent',
    '--no-merges',
    '--format=%h\x01%H\x01%s',
    ?(range.lastFinalTag == null ? null : '${range.lastFinalTag}..HEAD'),
  ]);
  final covered = range.proposalShas;
  final uncovered = <String>[];
  for (final line in log.split('\n')) {
    if (line.trim().isEmpty) continue;
    final [short, sha, subject] = line.split('\x01');
    if (covered.contains(sha) || subject.startsWith('chore(release): v')) {
      continue;
    }
    uncovered.add('$short $subject');
  }

  if (range.changes.isEmpty && uncovered.isEmpty) {
    out.writeln('Nothing to release since $since.');
    return 0;
  }
  if (range.changes.isEmpty) {
    out.writeln(
      'No change was archived since $since, so release:prepare would '
      'refuse to release.',
    );
  } else {
    final rendered = renderReleaseNotes(_placeholderSummary, range.changes);
    out.writeln(rendered.body);
    if (rendered.warnings.isNotEmpty) {
      out.writeln('\nWarnings:');
      for (final warning in rendered.warnings) {
        out.writeln('- $warning');
      }
    }
  }
  if (uncovered.isNotEmpty) {
    out.writeln('\nNot covered by a change:');
    for (final commit in uncovered) {
      out.writeln('- $commit');
    }
  }
  return 0;
}
