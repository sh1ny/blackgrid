import 'package:blackgrid/data/catalog_normalizer.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart';

void main() {
  test('present items source time reads as ISO-8601 UTC', () {
    expect(
      itemsSourceUpdateLabel(
        decisionCatalog(
          times: {
            for (final key in catalogDatasets)
              key: key == 'items' ? DateTime.utc(2026, 10, 5, 23) : null,
          },
        ),
      ),
      'Items source update: 2026-10-05T23:00:00.000Z',
    );
  });

  test('absent items source time reads unknown', () {
    expect(
      itemsSourceUpdateLabel(
        decisionCatalog(times: {for (final key in catalogDatasets) key: null}),
      ),
      'Items source update: unknown',
    );
  });
}
