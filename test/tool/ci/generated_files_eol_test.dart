import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Offline check that the files Flutter regenerates during `pub get` keep LF
/// endings in every checkout.
///
/// Flutter writes them with LF. A checkout with `core.autocrlf=true` (the
/// GitHub-hosted Windows runner) writes them with CRLF, so the rewrite leaves
/// them modified and `build:release` refuses the dirty tree.
void main() {
  const generated = [
    'windows/flutter/generated_plugin_registrant.cc',
    'windows/flutter/generated_plugin_registrant.h',
    'windows/flutter/generated_plugins.cmake',
  ];

  test('Flutter-generated files are checked out with LF endings', () {
    final result = Process.runSync('git', [
      'check-attr',
      'eol',
      '--',
      ...generated,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    for (final path in generated) {
      expect(
        '${result.stdout}',
        contains('$path: eol: lf'),
        reason: '.gitattributes must pin $path to eol=lf',
      );
    }
  });
}
