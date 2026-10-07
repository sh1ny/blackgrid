@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/vision/check_bundle.dart';

/// Runs the offline integrity check over the real Release bundle with the
/// committed inventory, lock, notices and allow-list. No network, no launch.
void main() {
  // e.g. build/windows/x64/runner/Release
  final bundle = Platform.environment['BLACKGRID_RELEASE_BUNDLE'];

  test('real Release bundle passes every integrity step', () async {
    final temporary = await Directory.systemTemp.createTemp('m2-bundle-');
    try {
      final reportPath =
          '${temporary.path}${Platform.pathSeparator}report.json';
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        [bundle!, '--report', reportPath],
        out: out,
        err: err,
      );
      expect(code, 0, reason: '$out$err');
      final report = jsonDecode(
        File(reportPath).readAsStringSync(),
      ) as Map<String, Object?>;
      expect(report['result'], 'pass');
      final steps = [
        for (final step in report['steps']! as List<Object?>)
          step! as Map<String, Object?>,
      ];
      expect(
        [for (final step in steps) step['name']],
        [
          'inventory',
          'bindings',
          'pins',
          'imports',
          'runtimeVersions',
          'notices',
        ],
      );
      for (final step in steps) {
        expect(
          step['ok'],
          isTrue,
          reason: '${step['name']}: ${step['failures']}',
        );
      }
    } finally {
      await temporary.delete(recursive: true);
    }
  }, skip: bundle == null ? 'Requires BLACKGRID_RELEASE_BUNDLE.' : false);
}
