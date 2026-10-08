import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _banned = <String>[
  'OpenProcess',
  'ReadProcessMemory',
  'WriteProcessMemory',
  'CreateRemoteThread',
  'SendInput',
  'PostMessage',
  'SendMessage',
  'PrintWindow',
];

/// Removes C/C++ comments so prose such as "never calls OpenProcess" does not
/// count as a call. String literals are kept, so a name smuggled through
/// `GetProcAddress("OpenProcess")` is still caught.
String stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
    .replaceAll(RegExp(r'//[^\n]*'), ' ');

/// Returns `file: identifier` findings for the banned APIs (and their A/W
/// variants) in the C++ sources of [dir]. `null` means no source was found.
List<String>? auditSources(Directory dir) {
  if (!dir.existsSync()) return null;
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.h') || f.path.endsWith('.cpp'))
      .toList();
  if (!files.any((f) => f.path.endsWith('.cpp'))) return null;
  final pattern = RegExp(r'\b(' + _banned.join('|') + r')[AW]?\b');
  final findings = <String>[];
  for (final file in files) {
    final text = stripComments(file.readAsStringSync());
    for (final match in pattern.allMatches(text)) {
      findings.add('${file.uri.pathSegments.last}: ${match.group(0)}');
    }
  }
  return findings;
}

void main() {
  group('capture source audit', () {
    test('capture sources call no process-access or input APIs', () {
      final findings = auditSources(Directory('windows/capture'));
      expect(
        findings,
        isNotNull,
        reason: 'no .cpp source under windows/capture: audit would be vacuous',
      );
      expect(findings, isEmpty);
    });

    test('the audit is not vacuous and detects a banned call', () {
      final tmp = Directory.systemTemp.createTempSync('bgc_audit_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      expect(auditSources(tmp), isNull);
      File('${tmp.path}/a.cpp').writeAsStringSync(
        '// OpenProcess in a comment is fine\nvoid f(){ SendMessageW(0,0,0,0); }',
      );
      expect(auditSources(tmp), ['a.cpp: SendMessageW']);
      File('${tmp.path}/a.cpp')
          .writeAsStringSync('void f(){ PostThreadMessageW(0,0,0,0); }');
      expect(auditSources(tmp), isEmpty);
    });

    test('no startup path imports or starts the trigger source', () {
      final offenders = <String>[];
      final roots = <FileSystemEntity>[
        Directory('lib/application'),
        Directory('lib/ui'),
        File('lib/main.dart'),
      ];
      final files = <File>[];
      for (final root in roots) {
        if (root is File && root.existsSync()) files.add(root);
        if (root is Directory && root.existsSync()) {
          files.addAll(
            root
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart')),
          );
        }
      }
      expect(files, isNotEmpty);
      for (final file in files) {
        final text = file.readAsStringSync();
        if (RegExp(r'''(import|export)\s+['"][^'"]*data/capture/''')
                .hasMatch(text) ||
            text.contains('MouseReleaseTriggerSource')) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
