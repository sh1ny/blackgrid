import 'package:blackgrid/domain/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogItem _item(String id, String name) => CatalogItem(
  id: id,
  name: name,
  normalizedName: name.toLowerCase().replaceAll(RegExp(r'\s+'), '-'),
);

CatalogSnapshot _snapshot(List<CatalogItem> items) => CatalogSnapshot(
  mode: GameMode.pvp,
  revision: 'r1',
  observedAt: DateTime.utc(2026, 1, 1),
  items: {for (final i in items) i.id: i},
  traders: const {},
  requirements: const [],
);

void main() {
  group('CatalogSnapshot.searchWords', () {
    final plate = _item('b2', 'ANA Tactical M1 plate carrier (OD Green)');
    final other = _item('a1', 'Salewa first aid kit');
    final catalog = _snapshot([plate, other]);

    test('every word must appear, in any order', () {
      expect(catalog.searchWords('ANA M1 OD GREEN'), [plate]);
      expect(catalog.searchWords('green od m1 ana'), [plate]);
      expect(catalog.searchWords('ANA M1 OD GREEN MISSING'), isEmpty);
    });

    test('blank text gives no results', () {
      expect(catalog.searchWords(''), isEmpty);
      expect(catalog.searchWords('   \t\n'), isEmpty);
    });

    test('results are capped at the limit and come in ID order', () {
      final many = _snapshot([
        for (var i = 12; i >= 1; i--)
          _item('id${i.toString().padLeft(2, '0')}', 'Widget $i'),
      ]);
      final results = many.searchWords('widget', limit: 8);
      expect(results.map((i) => i.id), [
        for (var i = 1; i <= 8; i++) 'id${i.toString().padLeft(2, '0')}',
      ]);
    });
  });
}
