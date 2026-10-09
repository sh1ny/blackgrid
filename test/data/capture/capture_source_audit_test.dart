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

final _rawPrefix = RegExp(r'(?:^|[^A-Za-z0-9_])(?:u8|[LuU])?R$');
final _numberStart = RegExp(r'(?:^|[^A-Za-z0-9_.])[0-9][A-Za-z0-9_.]*$');

/// Removes C/C++ comments so prose such as "never calls OpenProcess" does not
/// count as a call. It lexes string, character and raw string literals, so a
/// comment marker inside a literal cannot hide the code after it, and keeps
/// their contents, so `GetProcAddress("OpenProcess")` is still caught.
String stripComments(String source) {
  final out = StringBuffer();
  final n = source.length;
  var i = 0;
  while (i < n) {
    final c = source[i];
    final next = i + 1 < n ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < n && source[i] != '\n') {
        i++;
      }
      out.write(' ');
    } else if (c == '/' && next == '*') {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? n : end + 2;
      out.write(' ');
    } else if (c == '"' && _rawPrefix.hasMatch(source.substring(0, i))) {
      // R"delim( ... )delim"
      final open = source.indexOf('(', i + 1);
      final delim = open < 0 ? '' : source.substring(i + 1, open);
      final close = open < 0 ? -1 : source.indexOf(')$delim"', open + 1);
      final end = close < 0 ? n : close + delim.length + 2;
      out.write(source.substring(i, end));
      i = end;
    } else if (c == '"' ||
        (c == "'" && !_numberStart.hasMatch(source.substring(0, i)))) {
      // An ordinary string or character literal, up to its unescaped closing
      // quote. A C++14 digit separator such as 1'000 opens no literal.
      var j = i + 1;
      while (j < n && source[j] != c && source[j] != '\n') {
        j += source[j] == r'\' ? 2 : 1;
      }
      final end = j < n ? j + 1 : n;
      out.write(source.substring(i, end));
      i = end;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

final _bannedPattern = RegExp(r'\b(' + _banned.join('|') + r')[AW]?\b');

/// The banned identifiers (and A/W variants) in [source], outside comments.
List<String> bannedIdentifiers(String source) => [
  for (final m in _bannedPattern.allMatches(stripComments(source))) m.group(0)!,
];

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
  final findings = <String>[];
  for (final file in files) {
    for (final name in bannedIdentifiers(file.readAsStringSync())) {
      findings.add('${file.uri.pathSegments.last}: $name');
    }
  }
  return findings;
}

/// The one Dart file under `lib/application`, `lib/ui` and `lib/main.dart` that
/// may import `data/capture/` or name the trigger source (ADR-0013).
const allowedCaptureImporter = 'lib/application/scan_coordinator.dart';

final _captureImport = RegExp(r'''(import|export)\s+['"][^'"]*data/capture/''');

/// Whether [source] imports `data/capture/` or names the trigger source.
bool reachesCaptureLayer(String source) =>
    _captureImport.hasMatch(source) ||
    source.contains('MouseReleaseTriggerSource');

/// Whether the file at [path] (any separator) is the allowed importer.
bool mayReachCaptureLayer(String path) =>
    path.replaceAll('\\', '/') == allowedCaptureImporter;

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

    test('comment markers inside literals do not hide a banned call', () {
      // Each line hides OpenProcess from a regex comment stripper.
      const sources = <String>[
        r'const char* s = "//"; OpenProcess(0, 0, 0);',
        r'const char* s = "/*"; OpenProcess(0, 0, 0); // */',
        r'''char q = '"'; const char* s = "//"; OpenProcess(0, 0, 0);''',
        r'auto s = R"x(" // )x"; OpenProcess(0, 0, 0);',
        r'auto s = u8R"(/*)"; OpenProcess(0, 0, 0); /* x */',
        r'const char* s = "a\"//"; OpenProcess(0, 0, 0);',
      ];
      for (final source in sources) {
        expect(bannedIdentifiers(source), ['OpenProcess'], reason: source);
      }
    });

    test('real comments are still ignored and literals still scanned', () {
      expect(
        bannedIdentifiers('/* OpenProcess */ int x; // SendInput'),
        isEmpty,
      );
      expect(bannedIdentifiers('GetProcAddress(m, "OpenProcess");'), [
        'OpenProcess',
      ]);
    });

    test('only the scan coordinator imports capture or the trigger source', () {
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
        if (!mayReachCaptureLayer(file.path) && reachesCaptureLayer(text)) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty);
      expect(
        reachesCaptureLayer(File(allowedCaptureImporter).readAsStringSync()),
        isTrue,
        reason: 'the allowance would be vacuous',
      );
    });

    test(
      'any other file is still flagged and only the coordinator is allowed',
      () {
        const sources = <String>[
          "import '../data/capture/capture_service.dart';",
          "import 'package:blackgrid/data/capture/capture_native.dart';",
          'final s = MouseReleaseTriggerSource(platform);',
        ];
        for (final path in const [
          'lib/ui/scanner_screen.dart',
          'lib/application/other.dart',
          'lib/main.dart',
        ]) {
          expect(mayReachCaptureLayer(path), isFalse, reason: path);
          for (final source in sources) {
            expect(reachesCaptureLayer(source), isTrue, reason: source);
          }
        }
        expect(mayReachCaptureLayer(allowedCaptureImporter), isTrue);
        expect(
          mayReachCaptureLayer('lib\\application\\scan_coordinator.dart'),
          isTrue,
        );
        expect(reachesCaptureLayer("import 'dart:io';"), isFalse);
      },
    );
  });
}
