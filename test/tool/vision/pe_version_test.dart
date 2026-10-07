import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/vision/pe.dart';
import '../../support/pe_builder.dart';

void main() {
  test('runtime version step passes and reports versions', () {
    final result = checkRuntimeVersions(
      files: {
        'msvcp140.dll': PeBuilder(version: [14, 44, 35211, 0]).build(),
        'vcruntime140.dll': PeBuilder(version: [14, 100, 1, 0]).build(),
      },
      minimumVersions: {
        'msvcp140.dll': '14.40.0.0',
        'vcruntime140.dll': '14.40',
      },
    );
    expect(result.passed, isTrue, reason: '${result.failures}');
    expect(result.versions, {
      'msvcp140.dll': '14.44.35211.0',
      'vcruntime140.dll': '14.100.1.0',
    });
  });

  test('runtime below minimum fails with actual and minimum', () {
    final result = checkRuntimeVersions(
      files: {
        'msvcp140.dll': PeBuilder(version: [14, 9, 65535, 0]).build(),
      },
      minimumVersions: {'msvcp140.dll': '14.40.0.0'},
    );
    expect(result.passed, isFalse);
    final f = result.failures.single;
    expect(f.kind, VersionFailureKind.belowMinimum);
    expect(f.file, 'msvcp140.dll');
    expect(f.actual, '14.9.65535.0');
    expect(f.minimum, '14.40.0.0');
    expect(
      f.toString(),
      allOf(
        contains('msvcp140.dll'),
        contains('14.9.65535.0'),
        contains('14.40.0.0'),
      ),
    );
  });

  test('missing version resource fails as unreadable version', () {
    final result = checkRuntimeVersions(
      files: {
        'msvcp140.dll': PeBuilder().build(),
        'junk.dll': Uint8List.fromList([1, 2, 3]),
      },
      minimumVersions: {'msvcp140.dll': '14.40.0.0', 'junk.dll': '1.0.0.0'},
    );
    expect(result.passed, isFalse);
    expect(result.failures, hasLength(2));
    expect(
      result.failures.every((f) => f.kind == VersionFailureKind.unreadable),
      isTrue,
    );
    expect(result.failures.map((f) => f.file), ['msvcp140.dll', 'junk.dll']);
  });
}
