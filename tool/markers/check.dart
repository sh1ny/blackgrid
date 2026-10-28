/// Command line entry for the marker icon set check.
///
/// ```sh
/// mise exec -- dart run tool/markers/check.dart <manifest>
/// ```
///
/// Prints one failure per line (`rule: subject: value`), including the
/// expected hash for stale provenance records. Exits 1 when any rule fails,
/// 0 when the set is valid and 2 on a usage error. See `icon_set.dart` for
/// the rules.
library;

import 'dart:io';

import 'icon_set.dart';

const _usage = 'usage: dart run tool/markers/check.dart <manifest>';

/// Runs the check for [args] and returns the process exit code.
///
/// Writes failures to [out] (default stdout) and usage errors to [err]
/// (default stderr).
int runCli(List<String> args, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  if (args case [final manifest] when !manifest.startsWith('-')) {
    switch (checkIconSet(manifest)) {
      case IconSetValid(:final set):
        stdoutSink.writeln(
          'valid: ${set.name} (${set.scope.name}, ${set.icons.length} icons)',
        );
        return 0;
      case IconSetInvalid(:final failures):
        failures.map(formatFailure).forEach(stdoutSink.writeln);
        stdoutSink.writeln('invalid: ${failures.length} failure(s)');
        return 1;
    }
  }
  stderrSink.writeln(_usage);
  return 2;
}

void main(List<String> args) {
  exit(runCli(args));
}
