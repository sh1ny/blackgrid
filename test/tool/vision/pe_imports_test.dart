import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/vision/pe.dart';
import '../../support/pe_builder.dart';

void main() {
  final allow = SystemAllowList.fromJson(
    jsonEncode({
      'format': 1,
      // A VC++ name listed here must still never be allowed.
      'dlls': ['KERNEL32.dll', 'msvcp140.dll'],
      'prefixes': ['api-ms-win-'],
    }),
  );
  const bundle = {'blackgrid.dll', 'flutter_windows.dll'};

  test('imports resolve to bundle or allow-list', () {
    final result = checkImports(
      files: {
        'app.exe': PeBuilder(
          imports: ['kernel32.DLL', 'API-MS-WIN-CRT-runtime-l1-1-0.dll'],
          delayImports: ['Flutter_Windows.dll'],
        ).build(),
        'blackgrid.dll': PeBuilder().build(),
      },
      bundleDllNames: bundle,
      allow: allow,
    );
    expect(result.passed, isTrue, reason: '${result.failures}');
    expect(result.failures, isEmpty);
  });

  test('unresolved vcruntime import fails naming dll and import', () {
    final result = checkImports(
      files: {
        'blackgrid.dll': PeBuilder(
          imports: ['KERNEL32.dll'],
          delayImports: ['VCRUNTIME140.dll'],
        ).build(),
        'other.dll': PeBuilder(imports: ['MSVCP140.dll']).build(),
      },
      bundleDllNames: bundle,
      allow: allow,
    );
    expect(result.passed, isFalse);
    expect(result.failures, hasLength(2));
    final f = result.failures.firstWhere((f) => f.file == 'blackgrid.dll');
    expect(f.kind, ImportFailureKind.unresolved);
    expect(f.dll, 'VCRUNTIME140.dll');
    expect(
      f.toString(),
      allOf(contains('blackgrid.dll'), contains('VCRUNTIME140.dll')),
    );
    expect(
      result.failures.any(
        (f) => f.file == 'other.dll' && f.dll == 'MSVCP140.dll',
      ),
      isTrue,
    );
  });

  test('non-PE dll is reported unreadable', () {
    final truncated = PeBuilder(imports: ['KERNEL32.dll'])
        .build()
        .sublist(0, 0x90);
    final result = checkImports(
      files: {
        'junk.dll': Uint8List.fromList(utf8.encode('not a pe file')),
        'cut.dll': truncated,
        'x86.dll': PeBuilder(machine: 0x14C).build(),
      },
      bundleDllNames: bundle,
      allow: allow,
    );
    expect(result.passed, isFalse);
    expect(result.failures.map((f) => f.file), [
      'junk.dll',
      'cut.dll',
      'x86.dll',
    ]);
    expect(
      result.failures.every((f) => f.kind == ImportFailureKind.unreadable),
      isTrue,
    );
    expect(result.failures.first.toString(), contains('junk.dll'));
  });

  test('allow list never permits Visual C++ runtime names', () {
    expect(allow.allows('msvcp140.dll'), isFalse);
    expect(allow.allows('Vcruntime140_1.dll'), isFalse);
    expect(allow.allows('KERNEL32.DLL'), isTrue);
    expect(allow.allows('api-ms-win-core-x.dll'), isTrue);
    expect(allow.allows('ext-ms-win-x.dll'), isFalse);
  });
}
