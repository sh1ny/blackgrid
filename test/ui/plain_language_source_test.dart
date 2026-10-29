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

    test('check B ignores banned words outside literals', () {
      expect(
        findBannedTermHits('lib/ui/sample.dart', 'final canonical = 1;'),
        isEmpty,
      );
    });
  });
}
