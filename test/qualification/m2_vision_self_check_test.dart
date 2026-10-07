@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Starts the real `blackgrid.exe --vision-self-check <report>` and waits for
/// it. Self-check mode shows no window and opens no database. Per AGENTS.md
/// the app is never launched unless Escape from Tarkov is confirmed not
/// running; an unconfirmed state skips, which is recorded as unverified.
void main() {
  // e.g. build/windows/x64/runner/Release
  final bundleEnv = Platform.environment['BLACKGRID_RELEASE_BUNDLE'];
  final skip = bundleEnv == null
      ? 'Requires BLACKGRID_RELEASE_BUNDLE (a built Release bundle).'
      : _gameNotRunningConfirmed()
      ? false
      : 'Escape from Tarkov is running or its absence cannot be confirmed; '
            'app launch is not allowed (AGENTS.md). Unverified.';
  final bundle = bundleEnv == null
      ? ''
      : Directory(bundleEnv).resolveSymbolicLinksSync();

  Future<({int code, Map<String, Object?>? report})> selfCheck(
    String bundleDir,
    String reportPath,
  ) async {
    final process = await Process.start('$bundleDir\\blackgrid.exe', [
      '--vision-self-check',
      reportPath,
    ], workingDirectory: bundleDir);
    final code = await process.exitCode.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    final file = File(reportPath);
    return (
      code: code,
      report: file.existsSync()
          ? jsonDecode(file.readAsStringSync()) as Map<String, Object?>
          : null,
    );
  }

  Future<String> copyBundle(String target) async {
    for (final entity in Directory(bundle).listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(bundle.length + 1);
      final destination = File('$target\\$relative');
      destination.parent.createSync(recursive: true);
      entity.copySync(destination.path);
    }
    return target;
  }

  void expectPass(({int code, Map<String, Object?>? report}) result) {
    expect(result.code, 0, reason: jsonEncode(result.report));
    expect(result.report, isNotNull);
    expect(result.report!['result'], 'pass');
    for (final step in result.report!['steps']! as List<Object?>) {
      expect((step! as Map<String, Object?>)['ok'], isTrue);
    }
  }

  test(
    'blackgrid.exe self-check on Release bundle exits 0 with pass report',
    () async {
      final temporary = await Directory.systemTemp.createTemp('m2-self-');
      try {
        expectPass(await selfCheck(bundle, '${temporary.path}\\vision.json'));
      } finally {
        await temporary.delete(recursive: true);
      }
    },
    skip: skip,
  );

  test(
    'self-check on bundle copy without model exits 1 naming model',
    () async {
      final temporary = await Directory.systemTemp.createTemp('m2-self-');
      try {
        final copy = await copyBundle('${temporary.path}\\bundle');
        File('$copy\\data\\vision\\tessdata\\eng.traineddata').deleteSync();
        final result = await selfCheck(copy, '${temporary.path}\\vision.json');
        expect(result.code, 1);
        expect(result.report!['result'], 'fail');
        final failed = [
          for (final step in result.report!['steps']! as List<Object?>)
            if ((step! as Map<String, Object?>)['ok'] == false) step,
        ];
        expect(failed, isNotEmpty);
        expect(jsonEncode(failed.first), contains('eng.traineddata'));
      } finally {
        await temporary.delete(recursive: true);
      }
    },
    skip: skip,
  );

  // Covers 'bundle copied under Cyrillic path opens ready' through the exe,
  // whose manifest sets the UTF-8 active code page (task 3.6).
  test('self-check from bundle copied under Cyrillic path exits 0', () async {
    final temporary = await Directory.systemTemp.createTemp('m2-self-');
    try {
      final copy = await copyBundle('${temporary.path}\\Блэкгрид тест');
      expectPass(await selfCheck(copy, '$copy\\отчёт.json'));
    } finally {
      await temporary.delete(recursive: true);
    }
  }, skip: skip);
}

/// True only when tasklist runs and lists no EscapeFromTarkov.exe.
bool _gameNotRunningConfirmed() {
  try {
    final result = Process.runSync('tasklist', [
      '/FI',
      'IMAGENAME eq EscapeFromTarkov.exe',
      '/NH',
      '/FO',
      'CSV',
    ]);
    if (result.exitCode != 0) return false;
    return !(result.stdout as String).toLowerCase().contains(
      'escapefromtarkov.exe',
    );
  } on ProcessException {
    return false;
  }
}
