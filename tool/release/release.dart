import 'dart:io';

import 'src/build_step.dart';
import 'src/git.dart';
import 'src/package_step.dart';
import 'src/release_steps.dart';
import 'src/tag_step.dart';

const _usage = '''
Usage: dart run tool/release/release.dart <command> [arguments]

Commands:
  prepare <version> [--trailer <line>]...
      Create release/v<version> with the version bump and changelog commit.
  tag
      Tag the merged release commit on main and push the tag to origin.
  build
      Build the Windows Release bundle with the pubspec version and commit-count
      build number, then run the offline bundle integrity check.
  package
      Package the stamped Release bundle of the clean HEAD into build/release:
      the zip, the per-user installer and SHA256SUMS.txt.
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
  final trailers = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--trailer') {
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
  try {
    await prepare(
      version: version,
      repoDir: repoDir,
      runner: runner,
      trailers: trailers,
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

int _usageError(String message) {
  stderr.writeln(message);
  stderr.write(_usage);
  return 2;
}
