import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:test/test.dart';

import 'support/wire.dart';

void main() {
  test('station level keeps station, trader and skill requirements', () {
    final catalog = parseWire(
      stations: [
        stationWire('library', {
          'name': 'library-name',
          'normalizedName': 'library-normalized',
          'levels': [
            levelWire('library-2', 2, {'constructionTime': 3600}),
            levelWire('library-1', 1, {
              'constructionTime': 120,
              'stationLevelRequirements': [
                {'station': 'rest-space', 'level': 3},
              ],
              'traderRequirements': [
                {
                  'trader': 'trader-b',
                  'requirementType': 'level',
                  'compareMethod': '>=',
                  'value': 2,
                },
              ],
              'skillRequirements': [
                {'skill': 'HideoutManagement', 'level': 5},
              ],
            }),
          ],
        }),
        stationWire('rest-space'),
      ],
      hideoutDictionary: {'library-name': 'Library'},
    );
    final station = catalog.stationsById['library']!;
    expect(station.id, 'library');
    expect(station.name, 'Library');
    expect(station.normalizedName, 'library-normalized');
    expect(station.levels.map((level) => level.id), ['library-1', 'library-2']);
    expect(station.levels.map((level) => level.level), [1, 2]);
    expect(station.levels.map((level) => level.constructionTime), [120, 3600]);
    final level = station.levels.first;
    final requiredStation = level.stationRequirements!.single;
    expect(requiredStation.stationId, 'rest-space');
    expect(requiredStation.level, 3);
    final trader = level.traderRequirements!.single;
    expect(trader.traderId, 'trader-b');
    expect(trader.type, TraderRequirementType.level);
    expect(trader.comparison, Comparison.atLeast);
    expect(trader.rawComparison, '>=');
    expect(trader.value, 2);
    final skill = level.skillRequirements!.single;
    expect(skill.skillId, 'HideoutManagement');
    expect(skill.level, 5);
  });

  test('station names fall back to normalized name and ID', () {
    final catalog = parseWire(
      stations: [
        stationWire('translated', {
          'name': 'translated-key',
          'normalizedName': 'normalized',
        }),
        stationWire('normalized', {
          'name': 'missing-key',
          'normalizedName': 'fallback',
        }),
        stationWire('id-fallback', {
          'name': 'missing-key',
          'normalizedName': '',
        }),
        stationWire('bad-name', {'name': 42, 'normalizedName': 42}),
      ],
      hideoutDictionary: {'translated-key': 'Translated'},
    );
    expect(catalog.stationsById['translated']!.name, 'Translated');
    expect(catalog.stationsById['translated']!.normalizedName, 'normalized');
    expect(catalog.stationsById['normalized']!.name, 'fallback');
    expect(catalog.stationsById['id-fallback']!.name, 'id-fallback');
    expect(catalog.stationsById['bad-name']!.name, 'bad-name');
    expect(catalog.stationsById['bad-name']!.normalizedName, isNull);
    final withoutDictionary = parseWire(stations: [stationWire('station')]);
    expect(withoutDictionary.stations.single.name, 'normalized-station');
  });

  test('absent station level requirement lists differ from empty lists', () {
    final absent = levelWire('absent', 1)
      ..remove('stationLevelRequirements')
      ..remove('traderRequirements')
      ..remove('skillRequirements');
    final catalog = parseWire(
      stations: [
        stationWire('station', {
          'levels': [absent, levelWire('empty', 2)],
        }),
      ],
    );
    final levels = catalog.stations.single.levels;
    expect(levels[0].stationRequirements, isNull);
    expect(levels[0].traderRequirements, isNull);
    expect(levels[0].skillRequirements, isNull);
    expect(levels[1].stationRequirements, isEmpty);
    expect(levels[1].traderRequirements, isEmpty);
    expect(levels[1].skillRequirements, isEmpty);
  });

  test('wrong typed new level facts remain unknown', () {
    final catalog = parseWire(
      stations: [
        stationWire('station', {
          'levels': [
            levelWire('level', 1, {
              'constructionTime': 'sixty',
              'stationLevelRequirements': [
                {'station': 'required', 'level': 'three'},
              ],
              'traderRequirements': [
                {
                  'trader': 'trader-a',
                  'requirementType': 'new-type',
                  'compareMethod': '~',
                  'value': 'two',
                },
              ],
              'skillRequirements': [
                {'skill': 42, 'level': 'five'},
              ],
            }),
          ],
        }),
        stationWire('required'),
      ],
    );
    final level = catalog.stationsById['station']!.levels.single;
    expect(level.constructionTime, isNull);
    expect(level.stationRequirements!.single.stationId, 'required');
    expect(level.stationRequirements!.single.level, isNull);
    final trader = level.traderRequirements!.single;
    expect(trader.type, TraderRequirementType.unknown);
    expect(trader.rawType, 'new-type');
    expect(trader.comparison, Comparison.unknown);
    expect(trader.rawComparison, '~');
    expect(trader.value, isNull);
    final skill = level.skillRequirements!.single;
    expect(skill.skillId, isNull);
    expect(skill.level, isNull);
  });

  test('level number 0 or absent is an identity error', () {
    final missing = levelWire('level', 1)..remove('level');
    for (final level in [
      levelWire('level', 0),
      missing,
      levelWire('level', -1),
      levelWire('level', 1, {'level': 1.5}),
      levelWire('level', 1, {'level': '1'}),
    ]) {
      expect(
        () => parseWire(
          stations: [
            stationWire('station', {
              'levels': [level],
            }),
          ],
        ),
        throwsFormatException,
        reason: 'invalid level: $level',
      );
    }
  });

  test('station and level IDs are required strings', () {
    for (final invalidId in [null, '', '   ', 42]) {
      final level = levelWire('level', 1, {'id': invalidId});
      expect(
        () => parseWire(
          stations: [
            stationWire('station', {
              'levels': [level],
            }),
          ],
        ),
        throwsFormatException,
        reason: 'invalid level ID: $invalidId',
      );
      expect(
        () => parseProgressCatalog(
          {'tasks': <String, dynamic>{}},
          {
            'station': stationWire('station', {'id': invalidId}),
          },
          <String>{},
          null,
          null,
        ),
        throwsFormatException,
        reason: 'invalid station ID: $invalidId',
      );
    }
  });

  test('unresolved required station or trader is an identity error', () {
    for (final fields in <Map<String, dynamic>>[
      {
        'stationLevelRequirements': [
          {'station': 'missing', 'level': 1},
        ],
      },
      {
        'traderRequirements': [
          {
            'trader': 'missing',
            'requirementType': 'level',
            'compareMethod': '>=',
            'value': 1,
          },
        ],
      },
    ]) {
      expect(
        () => parseWire(
          stations: [
            stationWire('station', {
              'levels': [levelWire('level', 1, fields)],
            }),
          ],
        ),
        throwsFormatException,
      );
    }
  });
}
