import 'package:blackgrid/domain/marker_categories.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('marker category labels', () {
    test('known keys have their player-facing labels', () {
      expect(
        [
          'PmcExtracts',
          'ScavExtracts',
          'BossSpawns',
          'BtrStops',
          'lootContainers',
          'lootLoose',
          'CustomPins',
        ].map(markerCategoryLabel),
        [
          'PMC extracts',
          'Scav extracts',
          'Bosses',
          'BTR stops',
          'Containers',
          'Loose loot',
          'Saved pins',
        ],
      );
    });

    test('every icon key has a unique non-empty label', () {
      final keys = markerPreferenceKeys(markerCategories);
      expect(keys, hasLength(19));
      final labels = keys.map(markerCategoryLabel).toList();
      expect(labels.every((label) => label.isNotEmpty), isTrue);
      expect(labels.toSet(), hasLength(labels.length));
      expect([
        for (final key in keys)
          if (markerCategoryLabel(key) == key) key,
      ], unorderedEquals(['Hazards', 'Transits', 'Switches']));
    });

    test('labelled keys equal markerCategories without Labels', () {
      expect(
        markerPreferenceKeys(markerCategories).toSet(),
        markerCategories.toSet().difference({'Labels'}),
      );
    });

    test('a key with no label reads as the key itself', () {
      expect(markerCategoryLabel('Ziplines'), 'Ziplines');
      expect(markerCategoryLabel('Labels'), 'Labels');
    });
  });

  group('marker preference keys', () {
    test('markerPreferenceKeys orders keys by group', () {
      expect(
        markerPreferenceKeys([
          'lootLoose',
          'PmcExtracts',
          'QuestItems',
          'BossSpawns',
          'locks',
          'CustomPins',
        ]).map(markerCategoryLabel),
        [
          'PMC extracts',
          'Quest items',
          'Bosses',
          'Loose loot',
          'Locks',
          'Saved pins',
        ],
      );
    });

    test('markerPreferenceKeys ignores input order and drops unknown keys', () {
      const expected = ['PmcExtracts', 'locks', 'CustomPins'];
      expect(
        markerPreferenceKeys([
          'locks',
          'Ziplines',
          'PmcExtracts',
          'CustomPins',
        ]),
        expected,
      );
      expect(
        markerPreferenceKeys([
          'CustomPins',
          'PmcExtracts',
          'Ziplines',
          'locks',
        ]),
        expected,
      );
    });
  });
}
