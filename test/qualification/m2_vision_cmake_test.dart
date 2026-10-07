@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Path to a cmake.exe, e.g. the one bundled with Visual Studio.
  final cmake = Platform.environment['BLACKGRID_CMAKE'];
  final skip = cmake == null ? 'Requires BLACKGRID_CMAKE.' : false;
  final script = File('windows/vision/verify_inputs.cmake').absolute.path;

  late Directory temporary;
  late Directory cache;
  late File lock;
  final good = utf8.encode('pinned input bytes');
  final goodHash = sha256.convert(good).toString();

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('m2-vision-cmake-');
    cache = Directory('${temporary.path}/cache');
    lock = File('${temporary.path}/third_party.lock.json');
    await lock.writeAsString(
      jsonEncode({
        'format': 1,
        'inputs': [
          {
            'id': 'fixture-input',
            'name': 'fixture.bin',
            'version': '1.0.0',
            'urls': ['https://example.invalid/fixture.bin'],
            'sha256': goodHash,
            'size': good.length,
            'license': 'Apache-2.0',
            'noticeAnchor': 'fixture',
          },
        ],
      }),
    );
  });
  tearDown(() => temporary.delete(recursive: true));

  Future<ProcessResult> verify() => Process.run(cmake!, [
    '-DBGV_LOCK_FILE=${lock.path}',
    '-DBGV_INPUT_CACHE=${cache.path}',
    '-P',
    script,
  ]);

  Future<void> cacheInput(List<int> bytes) async {
    final file = File('${cache.path}/$goodHash/fixture.bin');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  test('verify_inputs.cmake passes on verified cached input', () async {
    await cacheInput(good);
    final result = await verify();
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }, skip: skip);

  test(
    'verify_inputs.cmake fails on altered cached input naming both hashes',
    () async {
      final altered = utf8.encode('altered input bytes');
      await cacheInput(altered);
      final result = await verify();
      final output = '${result.stdout}${result.stderr}';
      expect(result.exitCode, isNot(0));
      expect(output, contains('fixture-input'));
      expect(output, contains(goodHash));
      expect(output, contains(sha256.convert(altered).toString()));
    },
    skip: skip,
  );

  test(
    'verify_inputs.cmake fails on missing input naming mise run vision:fetch',
    () async {
      final result = await verify();
      final output = '${result.stdout}${result.stderr}';
      expect(result.exitCode, isNot(0));
      expect(output, contains('fixture-input'));
      expect(output, contains('mise run vision:fetch'));
    },
    skip: skip,
  );
}
