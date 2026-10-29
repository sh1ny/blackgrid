import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/plain_language_check.dart';

List<int> _linesA(String source) => [
  for (final hit in findEnumNameHits('lib/ui/sample.dart', source)) hit.line,
];

List<int> _linesB(String source) => [
  for (final hit in findBannedTermHits('lib/ui/sample.dart', source)) hit.line,
];

void main() {
  group('check A', () {
    test('check A flags a status name chain', () {
      final hits = findEnumNameHits(
        'lib/ui/sample.dart',
        "Text('Catalog: \${catalog.status.name}');\n",
      );
      expect(hits, hasLength(1));
      expect(hits.single.path, 'lib/ui/sample.dart');
      expect(hits.single.line, 1);
      expect(hits.single.toString(), startsWith('lib/ui/sample.dart:1'));
    });

    test('check A flags a destructured reason name', () {
      expect(_linesA("final a = 1;\nText('Reason: \${reason.name}');\n"), [2]);
    });

    test('check A flags each suffix and a nullable access', () {
      expect(_linesA('a(state.name);'), [1]);
      expect(_linesA('a(failure.code.name);'), [1]);
      expect(_linesA('a(pass.name);'), [1]);
      expect(_linesA('a(fir.name);'), [1]);
      expect(_linesA('a(activity.source?.name);'), [1]);
    });

    test('check A ignores names inside keys and item names', () {
      const source = '''
// Text('x \${catalog.status.name}');
/// Shows \${reason.name}.
final a = ValueKey('results-\${mode.name}');
final b = Text(item.name);
final c = const PageStorageKey('p-\${panel.state.name}');
final d = Key('k-\${scan.status.name}');
''';
      expect(findEnumNameHits('lib/ui/sample.dart', source), isEmpty);
    });

    test('check A still flags a name after a key on the same line', () {
      expect(_linesA("Row(key: ValueKey('a'), child: Text(status.name));"), [
        1,
      ]);
    });
  });

  group('check B', () {
    test('check B flags canonical, identities and Normalized', () {
      const source = '''
final a = Text('Canonical item');
final b = Text("Two identities found");
final c = Text('Normalized title');
''';
      expect(_linesB(source), [1, 2, 3]);
    });

    test('check B flags the other banned stems', () {
      expect(_linesB("a('identity');"), [1]);
      expect(_linesB("a('durable store');"), [1]);
      expect(_linesB("a('Stored with DPAPI');"), [1]);
      expect(_linesB("a('authority');"), [1]);
      expect(_linesB("a('Authorized');"), [1]);
      expect(_linesB("a('normalised');"), [1]);
      expect(_linesB("a('Gross RUB total');"), [1]);
      expect(_linesB("a('session-only');"), [1]);
    });

    test('check B ignores literals inside keys and debug labels', () {
      const source = '''
final a = Key('canonical-row');
final b = ValueKey('identities-\${x}');
final c = PageStorageKey("normalized");
final d = Foo(debugLabel: 'canonical');
// Text('canonical');
''';
      expect(findBannedTermHits('lib/ui/sample.dart', source), isEmpty);
    });

    test('check B matches M1 as a whole word only', () {
      expect(_linesB("a('M1 • x');"), [1]);
      expect(_linesB("a('Phase M1');"), [1]);
      expect(_linesB("a('M12');"), isEmpty);
      expect(_linesB("a('am1');"), isEmpty);
      expect(_linesB("a('m1');"), isEmpty);
    });

    test('check B joins adjacent literals on a line', () {
      expect(_linesB("a('Canon' 'ical');"), [1]);
    });

    test('check B matches literals nested inside an interpolation', () {
      expect(_linesB(r"a('${a ? 'canonical item' : ''}');"), [1]);
      expect(_linesB(r"""a('${a ? "identity" : b}');"""), [1]);
    });

    test('check B drops interpolation code before matching', () {
      expect(_linesB(r"a('${p?.authorityVersion}:');"), isEmpty);
      expect(_linesB(r"a('$canonicalName done');"), isEmpty);
      expect(_linesB(r"a('${f({'k': 1}).identity} ok');"), isEmpty);
      expect(_linesB(r"a('${f('x')} canonical');"), [1]);
    });

    test(
      'check B treats a raw string dollar and an escaped dollar as text',
      () {
        expect(_linesB(r"a(r'cost $canonical');"), [1]);
        expect(_linesB(r"a('cost \$canonical');"), [1]);
        expect(_linesB(r"a(r'${authority}');"), [1]);
      },
    );

    test('check B reads triple-quoted strings from their first line', () {
      const source = """
final a = 1;
final b = '''
first line
the canonical item
''';
""";
      expect(_linesB(source), [2]);
    });

    test('check B ignores apostrophes in trailing comments', () {
      expect(_linesB("a(); // don't say 'canonical'"), isEmpty);
      expect(_linesB("a(\"it's\", 'canonical');"), [1]);
    });

    test('check B ignores banned words outside literals', () {
      expect(
        findBannedTermHits('lib/ui/sample.dart', 'final canonical = 1;'),
        isEmpty,
      );
    });

    test('legacy import scoping keeps only the text the dialog shows', () {
      const source = '''
final x = row['normalizedX'];
final id = json['CanonicalItemId'];
final why = 'Entry wins';
ImportAccounting(kind: 'pin', reason: 'a canonical pin');
throw const FormatException('Bad identity');
final sourceReason = a
    ? 'one authority'
    : 'two';
final after = 'normalized';
''';
      final hits = findBannedTermHits(
        'lib/data/legacy_import.dart',
        scopeLegacyImportSource(source),
      );
      expect([for (final h in hits) h.line], [4, 5, 7]);
    });
  });

  group('whole tree', () {
    test('lib/ui has no raw enum name in text', () {
      final hits = [
        for (final file in _dartFiles('lib/ui'))
          ...findEnumNameHits(file.path, file.readAsStringSync()),
      ];
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('no scanned literal contains a banned term', () {
      final hits = [
        for (final file in [
          ..._dartFiles('lib/ui'),
          for (final name in _controllers)
            File('lib/application/${name}_controller.dart'),
          File('lib/domain/decision_engine.dart'),
        ])
          ...findBannedTermHits(file.path, file.readAsStringSync()),
        ...findBannedTermHits(
          'lib/data/legacy_import.dart',
          scopeLegacyImportSource(
            File('lib/data/legacy_import.dart').readAsStringSync(),
          ),
        ),
      ];
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  });
}

const _controllers = [
  'selection',
  'settings',
  'progress',
  'catalog',
  'map',
  'history',
];

List<File> _dartFiles(String directory) =>
    Directory(directory)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
