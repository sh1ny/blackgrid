import 'dart:io';

import '../release/src/git.dart';
import 'src/audit.dart';

const _bundleVariable = 'BLACKGRID_RELEASE_BUNDLE';
const _allowlistPath = 'tool/ci/qualification_skips.yaml';

/// CI-only qualification gate (`mise run ci:qualification`).
///
/// Runs the qualification tests against the CI-built bundle and audits the
/// skips. It has no local mode: qualification tests touch the capture
/// library, so a local run needs the user's own no-game confirmation.
Future<void> main() async {
  exitCode = await runQualification(
    runner: const ProcessCommandRunner(),
    environment: Platform.environment,
    repoDir: Directory.current,
  );
}

/// Runs the qualification gate and returns the process exit code.
///
/// Returns 2 without running anything when `BLACKGRID_RELEASE_BUNDLE` does
/// not name an existing directory. Otherwise runs
/// `flutter test --tags qualification` through [runner], with a JSON report
/// written to a fresh system-temp directory (removed afterwards), then audits
/// that report against the allowlist in [repoDir]. The result is the test
/// run's own non-zero exit code, else 1 for a failed audit, else 0. Both
/// results are written to [out] and [err].
Future<int> runQualification({
  required CommandRunner runner,
  required Map<String, String> environment,
  required Directory repoDir,
  StringSink? out,
  StringSink? err,
}) async {
  final sink = out ?? stdout;
  final errSink = err ?? stderr;

  final bundle = environment[_bundleVariable];
  if (bundle == null || !Directory(bundle).existsSync()) {
    errSink.writeln(
      '$_bundleVariable must name the built Release bundle directory; '
      '${bundle == null ? 'it is not set' : 'not a directory: $bundle'}.',
    );
    return 2;
  }

  final allowlist = parseAllowlist(
    File('${repoDir.path}/$_allowlistPath').readAsStringSync(),
  );

  final temp = Directory.systemTemp.createTempSync('blackgrid-qualification-');
  try {
    final report = File('${temp.path}/report.json');
    final result = await runner.run(
      'flutter',
      [
        'test',
        '--tags',
        'qualification',
        '--file-reporter',
        'json:${report.path}',
      ],
      workingDirectory: repoDir.path,
      stream: true,
    );

    List<String>? lines;
    try {
      lines = report.readAsLinesSync();
    } on FileSystemException {
      lines = null;
    }
    final audit = auditReport(lines, allowlist, repoRoot: repoDir.path);

    if (result.exitCode == 0) {
      sink.writeln('flutter test passed.');
    } else {
      errSink.writeln('flutter test exited with ${result.exitCode}.');
    }
    for (final skip in audit.accepted) {
      sink.writeln('Accepted skip: $skip');
    }
    if (audit.passed) {
      sink.writeln('Audit passed.');
    } else {
      errSink.writeln('Audit failed:');
      for (final finding in audit.findings) {
        errSink.writeln('  $finding');
      }
    }

    if (result.exitCode != 0) return result.exitCode;
    return audit.passed ? 0 : 1;
  } finally {
    temp.deleteSync(recursive: true);
  }
}
