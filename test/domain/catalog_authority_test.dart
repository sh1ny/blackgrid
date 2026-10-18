import 'package:blackgrid/data/catalog_normalizer.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart';

void main() {
  const day = Duration(hours: 24);
  Map<String, DateTime?> times({DateTime? items}) => {
    for (final key in catalogDatasets) key: key == 'items' ? items : null,
  };

  group('catalog authority from download time', () {
    test('no source times: authoritative through 24 h, not at 24 h + 1 ms', () {
      final c = decisionCatalog(times: times());
      expect(c.authoritativeAt(fixtureNow), isTrue);
      expect(c.authoritativeAt(fixtureNow.add(day)), isTrue);
      expect(
        c.authoritativeAt(
          fixtureNow.add(day + const Duration(milliseconds: 1)),
        ),
        isFalse,
      );
    });

    test('items source time 30 days old does not revoke authority', () {
      final c = decisionCatalog(
        times: times(items: fixtureNow.subtract(const Duration(days: 30))),
      );
      expect(
        c.authoritativeAt(fixtureNow.add(const Duration(hours: 1))),
        isTrue,
      );
    });

    test('future observation is not authoritative', () {
      final c = decisionCatalog(
        observedAt: fixtureNow.add(const Duration(milliseconds: 1)),
      );
      expect(c.authoritativeAt(fixtureNow), isFalse);
    });

    test('unsupported source or unknown mode is not authoritative', () {
      final c = decisionCatalog();
      CatalogSnapshot copy({String? source, GameMode? mode}) => CatalogSnapshot(
        mode: mode ?? c.mode,
        source: source ?? c.source,
        revision: c.revision,
        observedAt: c.observedAt,
        items: c.items,
        traders: c.traders,
        requirements: c.requirements,
        sourceTimestamps: c.sourceTimestamps,
      );
      expect(copy().authoritativeAt(fixtureNow), isTrue);
      expect(
        copy(source: 'unsupported.example').authoritativeAt(fixtureNow),
        isFalse,
      );
      expect(copy(mode: GameMode.unknown).authoritativeAt(fixtureNow), isFalse);
    });
  });
}
