import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/release/src/git.dart';

/// Whether a process whose command line contains [marker] is still running.
///
/// The marker reaches the query through the environment, so this query's
/// own command line never matches it.
bool _isRunning(String marker) {
  final r = Process.runSync(
    'pwsh',
    [
      '-NoProfile',
      '-Command',
      r'@(Get-CimInstance Win32_Process | '
          r'Where-Object { $_.CommandLine -like "*$env:BLACKGRID_MARKER*" })'
          r'.Count',
    ],
    environment: {'BLACKGRID_MARKER': marker},
  );
  if (r.exitCode != 0) throw StateError('process query failed: ${r.stderr}');
  return int.parse((r.stdout as String).trim()) > 0;
}

void main() {
  test(
    'a timed-out child is killed with its process tree and reported',
    () async {
      final marker =
          'blackgrid-timeout-${DateTime.now().microsecondsSinceEpoch}';
      const runner = ProcessCommandRunner();

      final result = await runner.run(
        'pwsh',
        ['-NoProfile', '-Command', 'Start-Sleep 30; # $marker'],
        workingDirectory: Directory.systemTemp.path,
        timeout: const Duration(seconds: 1),
      );

      expect(result.timedOut, isTrue);
      expect(result.exitCode, -1);
      expect(_isRunning(marker), isFalse);
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('a child that finishes in time is not marked timed out', () async {
    const runner = ProcessCommandRunner();

    final result = await runner.run(
      'pwsh',
      ['-NoProfile', '-Command', 'Write-Output ok; exit 3'],
      workingDirectory: Directory.systemTemp.path,
      timeout: const Duration(seconds: 20),
    );

    expect(result.timedOut, isFalse);
    expect(result.exitCode, 3);
    expect(result.stdout.trim(), 'ok');
  }, testOn: 'windows');
}
