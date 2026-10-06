import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/catalog.dart';

import '../fixtures/m1/catalog/fixture.dart';

void main() {
  test(
    'alternative items index one shared requirement without multiplying count',
    () {
      final c = fixtureCatalog();
      final task = c.requirementIndex['item-a']!
          .where((r) => r.kind == RequirementKind.task)
          .single;
      expect(task.itemIds, ['item-a', 'item-b']);
      expect(task.count, 3);
      expect(task.progressIds, ['find-a', 'give-a']);
      expect(
        c.requirementIndex['item-b']!
            .where((r) => r.kind == RequirementKind.task)
            .single,
        same(task),
      );
    },
  );
  test('paired find/give index once irrespective of objective order', () {
    final a = fixtureCatalog();
    final j = wireFixture();
    final objectives =
        j['tasks']['data']['tasks']['task-a']['objectives'] as List;
    j['tasks']['data']['tasks']['task-a']['objectives'] = objectives.reversed
        .toList();
    final b = fixtureCatalog(wire: j);
    expect(
      b.requirements.map((r) => r.toJson()),
      a.requirements.map((r) => r.toJson()),
    );
  });
  test('different FIR/count acquisitions are not paired', () {
    final j = wireFixture();
    j['tasks']['data']['tasks']['task-a']['objectives'][1]['count'] = 4;
    expect(
      fixtureCatalog(wire: j).requirements
          .where((r) => r.kind == RequirementKind.task)
          .length,
      2,
    );
  });
  test('requirement index deterministic class/source/objective order and immutable', () {
    final c = fixtureCatalog();
    expect(
      c.requirementIndex['item-a']!.map((r) => r.kind),
      RequirementKind.values,
    );
    expect(() => c.requirementIndex.clear(), throwsUnsupportedError);
  });
  test('unrelated optional source extension is accepted', () {
    final j = wireFixture();
    j['tasks']['data']['tasks']['task-a']['newUpstreamExtension'] = {
      'unknown': true,
    };
    expect(fixtureCatalog(wire: j).items.length, 2);
  });
}
