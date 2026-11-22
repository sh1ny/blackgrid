import 'dart:io';

import 'package:test/test.dart';

const _paths = [
  'lib/data/screenshot_directory_watcher.dart',
  'lib/data/screenshot_folder_lister.dart',
  'lib/domain/screenshot_cleanup.dart',
  'lib/application/screenshot_cleanup_controller.dart',
];

const _banned = [
  '.delete(',
  '.rename(',
  'openWrite',
  'writeAsBytes',
  'writeAsString',
  'FileMode.write',
  'FileMode.append',
  'Process.',
  'dart:ffi',
];

List<String> _findBannedCalls(Iterable<File> files) {
  final found = <String>[];
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('//')) continue;
      for (final banned in _banned) {
        if (lines[i].contains(banned)) {
          found.add('${file.path}:${i + 1}: $banned');
        }
      }
    }
  }
  return found;
}

void main() {
  test('screenshot Dart sources have no process or write calls', () {
    expect(_findBannedCalls(_paths.map(File.new)), isEmpty);
  });

  test('screenshot audit detects every banned call', () {
    final dir = Directory.systemTemp.createTempSync('screenshot_audit_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/source.dart');
    file.writeAsStringSync(_banned.join('\n'));
    final found = _findBannedCalls([file]);
    for (final banned in _banned) {
      expect(
        found.any((line) => line.endsWith(banned)),
        isTrue,
        reason: banned,
      );
    }
  });

  test('screenshot audit does not silently skip a missing source', () {
    final dir = Directory.systemTemp.createTempSync(
      'screenshot_audit_missing_',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(
      () => _findBannedCalls([File('${dir.path}/missing.dart')]),
      throwsA(isA<FileSystemException>()),
    );
  });
}
