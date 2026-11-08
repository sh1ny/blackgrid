import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/colour_literal_check.dart';

void main() {
  test('lib/ui has no colour literals outside lib/ui/ember', () {
    final hits = [
      for (final file in _uiFiles())
        ...findColourLiteralHits(file.path, file.readAsStringSync()),
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'Take colours from Theme.of(context) (EmberColors, BlackgridColors '
          'or the ColorScheme):\n${hits.join('\n')}',
    );
  });

  test('reports file and line of a colour literal', () {
    const source = '''
// final ignored = Color(0xff000000);
/// Colors.red in a doc comment.
final text = 'Color(0xff000000) in a string';
final ok = Colors.transparent;
final theme = Theme.of(context).colorScheme.surface;
final a = const Color(0xff112233);
final b = Color.fromARGB(255, 1, 2, 3);
final c = Color.fromRGBO(1, 2, 3, 1);
final d = Colors.white;
/* block
   Colors.blue */
final e = Colors.amber.shade200;
final f = Color.from(alpha: 1, red: 0, green: 0, blue: 0);
''';
    final hits = findColourLiteralHits('lib/ui/sample.dart', source);
    expect([for (final hit in hits) hit.line], [6, 7, 8, 9, 12, 13]);
    expect(hits.first.path, 'lib/ui/sample.dart');
    expect(
      hits.first.toString(),
      'lib/ui/sample.dart:6: final a = const Color(0xff112233);',
    );
  });
}

List<File> _uiFiles() =>
    Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.replaceAll(r'\', '/').contains('lib/ui/ember/'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
