import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qualification/contracts.dart';
import 'm0_contracts_test.dart' as source_examples;

void main() {
  test('failed lock replacement preserves bytes and permits retry', () async {
    final temporary = await Directory.systemTemp.createTemp('m0-lock-rewrite-');
    final target = File('${temporary.path}/lock with spaces.json');
    final release = File('${temporary.path}/release');
    final record = source_examples.lock()..remove('local_locators');
    final original = '${const JsonEncoder.withIndent('  ').convert(record)}\n';
    await target.writeAsString(original);
    final holder = await Process.start(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        r'$handle=[IO.File]::Open($env:M0_TEST_LOCK,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite); try { [Console]::WriteLine("ready"); [Console]::Out.Flush(); $clock=[Diagnostics.Stopwatch]::StartNew(); while (-not [IO.File]::Exists($env:M0_TEST_RELEASE) -and $clock.Elapsed.TotalSeconds -lt 15) { Start-Sleep -Milliseconds 25 } } finally { $handle.Dispose() }',
      ],
      environment: {
        'M0_TEST_LOCK': target.path,
        'M0_TEST_RELEASE': release.path,
      },
    );
    final ready = Completer<String>();
    final holderOutput = utf8.decoder
        .bind(holder.stdout)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (!ready.isCompleted) ready.complete(line);
          },
          onDone: () {
            if (!ready.isCompleted) {
              ready.completeError(
                StateError('Lock holder exited without acquiring the file.'),
              );
            }
          },
        );
    final holderErrors = utf8.decoder.bind(holder.stderr).join();
    try {
      expect(await ready.future, 'ready');
      Future<ProcessResult> rewrite() => Process.run(
        'mise',
        [
          'exec',
          '--',
          'dart',
          'tool/qualification/m0.dart',
          'hash-lock',
          target.path,
          '--write',
        ],
        workingDirectory: Directory.current.path,
        environment: {
          'DART_DATA_HOME': '${Directory.current.path}/.dart_tool/dart-data',
        },
      );
      final failed = await rewrite();
      expect(
        failed.exitCode,
        isNot(0),
        reason: '${failed.stdout}\n${failed.stderr}',
      );
      expect(
        failed.stderr,
        contains('Cannot read or write qualification record'),
      );
      expect(await target.readAsString(), original);
      await release.writeAsString('release');
      expect(await holder.exitCode, 0, reason: await holderErrors);
      final retried = await rewrite();
      expect(
        retried.exitCode,
        0,
        reason: '${retried.stdout}\n${retried.stderr}',
      );
      final rewritten =
          jsonDecode(await target.readAsString()) as Map<String, dynamic>;
      validateRecord(rewritten);
      expect(rewritten['freeze_id'], sourceFreezeId(record));
      expect(rewritten, record);
      await release.delete();
      expect(await temporary.list().map((entry) => entry.uri).toList(), [
        target.uri,
      ]);
    } finally {
      await release.writeAsString('release');
      await holder.exitCode;
      await holderErrors;
      await holderOutput.cancel();
      await holder.stdin.close();
      await temporary.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);
}
