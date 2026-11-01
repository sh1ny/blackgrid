import 'dart:io';

import 'package:test/test.dart';

/// Calls that would make log input able to spawn processes, load native code,
/// or change a game file.
const _banned = [
  'Process.run',
  'Process.start',
  'Process.killPid',
  'dart:ffi',
  'openWrite',
  'writeAsBytes',
  'writeAsString',
  'FileMode.write',
  'FileMode.append',
  '.rename(',
  '.delete(',
];

/// Returns `path:line: banned text` for every banned call in the Dart files
/// under [roots] (directories are scanned recursively, files directly).
/// Whole-line `//` comments are skipped.
List<String> findBannedCalls(Iterable<FileSystemEntity> roots) {
  final files = <File>[
    for (final root in roots)
      if (root is Directory)
        ...root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
      else if (root is File)
        root,
  ];
  final found = <String>[];
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; ++i) {
      if (lines[i].trimLeft().startsWith('//')) continue;
      for (final call in _banned) {
        if (lines[i].contains(call)) found.add('${file.path}:${i + 1}: $call');
      }
    }
  }
  return found;
}

void main() {
  test('log input source has no process or write calls', () {
    final roots = [
      Directory('lib/data/game_log'),
      File('lib/data/session_log_reader.dart'),
    ];
    for (final root in roots) {
      expect(
        root is Directory ? root.existsSync() : (root as File).existsSync(),
        isTrue,
        reason: '${root.path} must exist so the audit scans something',
      );
    }
    expect(findBannedCalls(roots), isEmpty);
  });

  test('audit scan flags every banned call in a scratch file', () {
    final scratch = Directory.systemTemp.createTempSync('blackgrid-audit-');
    addTearDown(() => scratch.deleteSync(recursive: true));
    File('${scratch.path}/clean.dart').writeAsStringSync(
      '// Process.run in a comment is fine.\nvoid f() => File("a").open();\n',
    );
    expect(findBannedCalls([scratch]), isEmpty);
    File(
      '${scratch.path}/bad.dart',
    ).writeAsStringSync(_banned.map((call) => 'final x = $call;').join('\n'));
    final found = findBannedCalls([scratch]);
    expect(found, hasLength(_banned.length));
    for (final call in _banned) {
      expect(found.any((entry) => entry.endsWith(': $call')), isTrue);
    }
  });
}
