import 'dart:io';

import 'package:blackgrid/data/local_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cpp = File('windows/runner/local_data_channel.cpp');

  test('the Dart and native channel names match', () {
    final source = cpp.readAsStringSync();
    final match = RegExp(r'kLocalDataChannelName\[\]\s*=\s*"([^"]+)"')
        .firstMatch(source);

    expect(match, isNotNull, reason: 'native channel name constant');
    expect(match!.group(1), localDataChannelName);
  });

  test('the runner channel answers localDataPath and nothing else', () {
    final source = cpp.readAsStringSync();

    expect(source, contains('localDataPath'));
    for (final removed in ['protect', 'unprotect', 'atomicReplace']) {
      expect(source, isNot(contains('"$removed"')), reason: removed);
    }
    expect(source, isNot(contains('wincrypt')));
    expect(source.toLowerCase(), isNot(contains('credential')));
    expect(
      File('windows/runner/credential_protector.cpp').existsSync(),
      isFalse,
    );
  });

  test('the Windows build no longer links the crypto library', () {
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(cmake, contains('local_data_channel.cpp'));
    expect(cmake.toLowerCase(), isNot(contains('crypt32')));
    expect(cmake, isNot(contains('credential_protector')));
  });
}
