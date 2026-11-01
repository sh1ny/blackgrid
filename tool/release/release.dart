import 'dart:io';

import 'src/build_step.dart';
import 'src/git.dart';
import 'src/package_step.dart';
import 'src/release_steps.dart';
import 'src/tag_step.dart';
import 'src/verify_tag_step.dart';

const _usage = '''
Usage: dart run tool/release/release.dart <command> [arguments]

Commands:
  prepare <version> (--summary <text> | --summary-file <path>) [--trailer <line>]...
      Create release/v<version> with the version bump and changelog commit.
      The summary (whitespace collapsed to one line, at most 600 characters)
      opens the new changelog section; the file must be outside the checkout.
  tag
      Tag the merged release commit on main and push the tag to origin.
  build
      Build the Windows Release bundle with the pubspec version and commit-count
      build number, then run the offline bundle integrity check.
  package
      Package the stamped Release bundle of the clean HEAD into build/release:
      the zip, the per-user installer and SHA256SUMS.txt.
  verify-tag <tag> --out <dir>
      In the tag's checkout, refuse unless the tag is a valid release tag on
      main's first-parent line whose pubspec version and non-empty changelog
      section match; then write <dir>/notes.md and <dir>/release.json.
''';

Future<void> main(List<String> arguments) async {
  exitCode = await runRelease(arguments);
}

/// Dispatches subcommands and returns the process exit code
/// (2 for usage errors, otherwise the failure's code).
Future<int> runRelease(
  List<String> arguments, {
  CommandRunner runner = const ProcessCommandRunner(),
  Directory? repoDir,
}) async {
  if (arguments.isEmpty) return _usageError('Missing command.');
  final command = arguments.first;
  final rest = arguments.sublist(1);
  switch (command) {
    case 'prepare':
      return _prepare(rest, runner, repoDir ?? Directory.current);
    case 'tag':
      if (rest.isNotEmpty) return _usageError('tag takes no arguments.');
      return _tag(runner, repoDir ?? Directory.current);
    case 'build':
      if (rest.isNotEmpty) return _usageError('build takes no arguments.');
      return _build(runner, repoDir ?? Directory.current);
    case 'package':
      if (rest.isNotEmpty) return _usageError('package takes no arguments.');
      return _package(runner, repoDir ?? Directory.current);
    case 'verify-tag':
      return _verifyTag(rest, runner, repoDir ?? Directory.current);
    default:
      return _usageError('Unknown command "$command".');
  }
}

Future<int> _prepare(
  List<String> arguments,
  CommandRunner runner,
  Directory repoDir,
) async {
  String? version;
  String? summary;
  String? summaryFile;
  final trailers = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--summary') {
      if (i + 1 >= arguments.length) {
        return _usageError('--summary needs a value.');
      }
      summary = arguments[++i];
    } else if (arg == '--summary-file') {
      if (i + 1 >= arguments.length) {
        return _usageError('--summary-file needs a value.');
      }
      summaryFile = arguments[++i];
    } else if (arg == '--trailer') {
      if (i + 1 >= arguments.length) {
        return _usageError('--trailer needs a value.');
      }
      trailers.add(arguments[++i]);
    } else if (arg.startsWith('-')) {
      return _usageError('Unknown option "$arg".');
    } else if (version == null) {
      version = arg;
    } else {
      return _usageError('Unexpected argument "$arg".');
    }
  }
  if (version == null) return _usageError('prepare needs a <version>.');
  if (summary != null && summaryFile != null) {
    return _usageError('--summary and --summary-file are exclusive.');
  }
  try {
    if (summaryFile != null) {
      try {
        summary = File(summaryFile).readAsStringSync();
      } on FileSystemException catch (e) {
        throw ReleaseException(
          'Cannot read the summary file $summaryFile: ${e.message}',
        );
      }
    }
    await prepare(
      version: version,
      repoDir: repoDir,
      runner: runner,
      trailers: trailers,
      summary: summary,
    );
    return 0;
  } on ReleaseException catch (e) {
    stderr.writeln(e.message);
    return e.exitCode;
  }
}

Future<int> _tag(CommandRunner runner, Directory repoDir) async {
  try {
    await tag(repoDir: repoDir, runner: runner);
    return 0;
  } on ReleaseException catch (e) {
    stderr.writeln(e.message);
    return e.exitCode;
  }
}

Future<int> _build(CommandRunner runner, Directory repoDir) async {
  try {
    await build(repoDir: repoDir, runner: runner);
    return 0;
  } on ReleaseException catch (e) {
    stderr.writeln(e.message);
    return e.exitCode;
  }
}

Future<int> _package(CommandRunner runner, Directory repoDir) async {
  try {
    await package(repoDir: repoDir, runner: runner);
    return 0;
  } on ReleaseException catch (e) {
    stderr.writeln(e.message);
    return e.exitCode;
  }
}

Future<int> _verifyTag(
  List<String> arguments,
  CommandRunner runner,
  Directory repoDir,
) async {
  String? tagName;
  String? outDir;
  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--out') {
      if (i + 1 >= arguments.length) return _usageError('--out needs a value.');
      outDir = arguments[++i];
    } else if (arg.startsWith('-')) {
      return _usageError('Unknown option "$arg".');
    } else if (tagName == null) {
      tagName = arg;
    } else {
      return _usageError('Unexpected argument "$arg".');
    }
  }
  if (tagName == null) return _usageError('verify-tag needs a <tag>.');
  if (outDir == null) return _usageError('verify-tag needs --out <dir>.');
  try {
    await verifyTag(
      tag: tagName,
      outDir: Directory(outDir),
      repoDir: repoDir,
      runner: runner,
    );
    return 0;
  } on ReleaseException catch (e) {
    stderr.writeln(e.message);
    return e.exitCode;
  }
}

int _usageError(String message) {
  stderr.writeln(message);
  stderr.write(_usage);
  return 2;
}
