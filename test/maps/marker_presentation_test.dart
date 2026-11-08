import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/maps/marker_presentation.dart';
import 'package:blackgrid/maps/prepared_map.dart';

import '../fixtures/m1/catalog/fixture.dart';

void main() {
  group('marker presentation', () {
    test(
      'quest description remains a fact when it matches the prepared title',
      () {
        const description =
            'Travel to the north ridge and search every marked area for the '
            'hidden objective.';
        final marker = _marker(
          id: 'quest-objective-3ef16a317852',
          category: 'questObjectives',
          filterKey: 'QuestObjectives',
          name: description,
          details: const {'description': description},
        );

        final presentation = presentMarker(marker);

        expect(presentation.title, description);
        expect(presentation.facts, contains(description));
      },
    );

    test('spawn zone-name fallbacks use the player-facing category label', () {
      for (final zoneName in ['ZoneHotel_2', 'BotZoneKorr_t2']) {
        final presentation = presentMarker(
          _marker(
            id: 'spawn-$zoneName',
            category: 'spawns',
            filterKey: 'ScavSpawns',
            name: zoneName,
            details: {'zoneName': zoneName},
          ),
        );

        expect(presentation.title, 'Scav spawns');
        expect(presentation.text, isNot(contains(zoneName)));
      }
    });

    test('translated spawn names remain display titles', () {
      const zoneName = 'ZoneHotel_2';
      final presentation = presentMarker(
        _marker(
          id: 'translated-spawn',
          category: 'spawns',
          filterKey: 'ScavSpawns',
          name: 'Old Gas Station',
          details: const {'zoneName': zoneName},
        ),
      );

      expect(presentation.title, 'Old Gas Station');
      expect(presentation.text, isNot(contains(zoneName)));
    });

    test(
      'catalog ID fallback is unavailable for lock and extract summaries',
      () {
        final wire = wireFixture();
        final item = wire['items']['data']['items']['item-a'] as Map;
        item['normalizedName'] = 'item-a';
        (wire['items_en']['data'] as Map).remove('item-a Name');
        final snapshot = fixtureCatalog(wire: wire);
        expect(snapshot.items['item-a']!.name, 'item-a');

        final lock = _marker(
          id: 'lock-id',
          category: 'locks',
          filterKey: 'locks',
          name: 'Gate lock',
          details: const {'key': 'item-a'},
        );
        final extract = _marker(
          id: 'extract-id',
          category: 'extracts',
          filterKey: 'PmcExtracts',
          name: 'West exit',
          details: const {
            'transferItem': {'item': 'item-a'},
          },
        );

        final lockText = presentMarker(
          lock,
          activeMode: GameMode.pvp,
          catalogSnapshot: snapshot,
        ).text;
        final extractText = presentMarker(
          extract,
          activeMode: GameMode.pvp,
          catalogSnapshot: snapshot,
        ).text;

        expect(lockText, contains('Key: unavailable'));
        expect(lockText, isNot(contains('item-a')));
        expect(extractText, contains('Item: unavailable'));
        expect(extractText, isNot(contains('item-a')));
      },
    );

    test('quest objective and container show prepared names', () {
      final objective = _marker(
        id: 'objective-id',
        category: 'questObjectives',
        filterKey: 'QuestObjectives',
        name: 'Find the hidden cache',
        details: {
          'description': 'Search the marked area',
          'quest': {
            'id': 'quest-secret-id',
            'name': 'A translated quest',
            'trader': {'id': 'trader-id', 'name': 'A translated trader'},
            'wikiLink': 'https://example.test/quest',
          },
        },
      );
      final container = _marker(
        id: 'container-id',
        category: 'lootContainers',
        filterKey: 'lootContainers',
        name: 'Translated supply crate',
        details: const {},
      );
      final transit = _marker(
        id: 'transit-id',
        category: 'transits',
        filterKey: 'Transits',
        name: 'Transit to Woods',
        details: const {'description': 'FAC_TRANSIT_12_DESC'},
      );

      final questPresentation = presentMarker(objective);
      final containerPresentation = presentMarker(container);
      final transitPresentation = presentMarker(transit);

      expect(questPresentation.text, contains('Find the hidden cache'));
      expect(questPresentation.text, contains('Search the marked area'));
      expect(questPresentation.text, contains('A translated quest'));
      expect(questPresentation.text, contains('A translated trader'));
      expect(questPresentation.text, isNot(contains('quest-secret-id')));
      expect(containerPresentation.text, contains('Translated supply crate'));
      expect(transitPresentation.text, contains('Transit to Woods'));
      expect(transitPresentation.text, isNot(contains('FAC_TRANSIT_12_DESC')));
    });

    test('linked extract item count switch and lock key facts', () {
      final extract = _marker(
        id: 'extract-id',
        category: 'extracts',
        filterKey: 'PmcExtracts',
        name: 'North exit',
        details: {
          'transferItem': {'count': 2, 'item': 'item-id'},
          'switches': 'switch-id',
        },
      );
      final switchMarker = _marker(
        id: 'switch-id',
        category: 'switches',
        filterKey: 'Switches',
        name: 'Power control',
        details: const {},
      );
      final reverseLinked = _marker(
        id: 'other-switch',
        category: 'switches',
        filterKey: 'Switches',
        name: 'Reverse power control',
        details: const {
          'activates': ['extract-id'],
        },
      );
      final scalarAliasExtract = _marker(
        id: 'alias-extract',
        category: 'extracts',
        filterKey: 'PmcExtracts',
        name: 'West exit',
        details: const {'switch': 'switch-id'},
      );
      final otherMapSwitch = _marker(
        id: 'foreign-switch',
        category: 'switches',
        filterKey: 'Switches',
        name: 'Foreign map switch',
        details: const {
          'activates': ['extract-id'],
        },
        source: const {'mapId': 'map-b'},
      );
      final unlinkedSwitch = _marker(
        id: 'unlinked-switch',
        category: 'switches',
        filterKey: 'Switches',
        name: 'Unlinked switch',
        details: const {},
      );
      final lock = _marker(
        id: 'lock-id',
        category: 'locks',
        filterKey: 'locks',
        name: 'Gate lock',
        details: const {
          'key': 'key-id',
          'lockType': 'door',
          'needsPower': true,
        },
      );
      final snapshot = _catalog(
        mode: GameMode.pvp,
        items: {
          'item-id': _item('item-id', 'Translated transfer item'),
          'key-id': _item('key-id', 'Translated keycard'),
        },
      );

      final extractText = presentMarker(
        extract,
        mapMarkers: [
          extract,
          switchMarker,
          reverseLinked,
          otherMapSwitch,
          unlinkedSwitch,
        ],
        activeMode: GameMode.pvp,
        catalogSnapshot: snapshot,
      ).text;
      final scalarAliasText = presentMarker(
        scalarAliasExtract,
        mapMarkers: [scalarAliasExtract, switchMarker],
      ).text;
      final lockText = presentMarker(
        lock,
        activeMode: GameMode.pvp,
        catalogSnapshot: snapshot,
      ).text;

      expect(extractText, contains('2'));
      expect(extractText, contains('Translated transfer item'));
      expect(extractText, contains('Power control'));
      expect(extractText, contains('Reverse power control'));
      expect(extractText, isNot(contains('Foreign map switch')));
      expect(extractText, isNot(contains('Unlinked switch')));
      expect(extractText, isNot(contains('item-id')));
      expect(extractText, isNot(contains('switch-id')));
      expect(scalarAliasText, contains('Power control'));
      expect(lockText, contains('door'));
      expect(lockText, contains('Translated keycard'));
      expect(lockText, contains('power'));
      expect(lockText, isNot(contains('key-id')));
    });

    test('missing malformed and misleading facts are not invented', () {
      final marker = _marker(
        id: 'marker-id',
        category: 'locks',
        filterKey: 'locks',
        name: 'locks',
        details: const {
          'key': 123,
          'lockType': ['not-a-type'],
          'needsPower': 'yes',
          'switches': ['unlinked-switch'],
        },
      );
      final presentation = presentMarker(marker);

      expect(presentation.text, contains('Locks'));
      expect(presentation.text, isNot(contains('123')));
      expect(presentation.text, isNot(contains('not-a-type')));
      expect(presentation.text, isNot(contains('unlinked-switch')));
      expect(presentation.text, isNot(contains('yes')));
      expect(presentation.text, isNot(contains('marker-id')));
      final transit = _marker(
        id: 'transit-id',
        category: 'transits',
        filterKey: 'Transits',
        name: 'Transit to Woods',
        details: const {'description': 'FAC_TRANSIT_12_DESC'},
      );
      expect(presentMarker(transit).text, contains('Transit to Woods'));
      expect(
        presentMarker(transit).text,
        isNot(contains('FAC_TRANSIT_12_DESC')),
      );
    });

    test('boss wide chance is a percentage not a location chance', () {
      final marker = _marker(
        id: 'boss-id',
        category: 'bosses',
        filterKey: 'BossSpawns',
        name: 'The Boss',
        details: const {'spawnChance': 0.35, 'location': 'Warehouse'},
      );
      final valid = presentMarker(marker).text;
      final invalid = presentMarker(
        _marker(
          id: 'invalid-boss',
          category: 'bosses',
          filterKey: 'BossSpawns',
          name: 'The Boss',
          details: const {'spawnChance': 1.2},
        ),
      ).text;
      final nonfinite = presentMarker(
        _marker(
          id: 'nonfinite-boss',
          category: 'bosses',
          filterKey: 'BossSpawns',
          name: 'The Boss',
          details: const {'spawnChance': double.infinity},
        ),
      ).text;

      expect(valid, contains('35%'));
      expect(valid, isNot(contains('Warehouse')));
      expect(invalid, isNot(contains('%')));
      expect(nonfinite, isNot(contains('%')));
    });

    test('map-marker-popups: Fractional boss chance', () {
      final text = presentMarker(_bossWithChance(0.125)).text;

      expect(text, contains('Spawn chance: 13%'));
      expect(text, isNot(contains('12.5')));
    });

    test('map-marker-popups: Chance near the ends', () {
      const expected = <(num, String)>[
        (0.004, '1%'),
        (0.997, '99%'),
        (0, '0%'),
        (1, '100%'),
      ];

      for (final (chance, shown) in expected) {
        expect(
          presentMarker(_bossWithChance(chance)).text,
          contains('Spawn chance: $shown'),
          reason: 'chance $chance',
        );
      }
    });

    test(
      'absent mismatched missing and failed catalog names are unavailable',
      () {
        final marker = _marker(
          id: 'extract-id',
          category: 'extracts',
          filterKey: 'PmcExtracts',
          name: 'North exit',
          details: const {
            'transferItem': {'count': 1, 'item': 'known-id'},
          },
        );
        const unavailable = 'unavailable';

        expect(
          presentMarker(marker, activeMode: GameMode.pvp).text,
          contains(unavailable),
        );
        expect(
          presentMarker(
            marker,
            activeMode: GameMode.pve,
            catalogSnapshot: _catalog(
              mode: GameMode.pvp,
              items: {'known-id': _item('known-id', 'Wrong mode name')},
            ),
          ).text,
          contains(unavailable),
        );
        expect(
          presentMarker(
            marker,
            activeMode: GameMode.pvp,
            catalogSnapshot: _catalog(mode: GameMode.pvp, items: const {}),
          ).text,
          contains(unavailable),
        );
        expect(
          presentMarker(marker, activeMode: GameMode.unknown).text,
          contains(unavailable),
        );
        final missingId = presentMarker(
          _marker(
            id: 'missing-item',
            category: 'extracts',
            filterKey: 'PmcExtracts',
            name: 'North exit',
            details: const {
              'transferItem': {'count': 1},
            },
          ),
          activeMode: GameMode.pvp,
          catalogSnapshot: _catalog(mode: GameMode.pvp, items: const {}),
        ).text;
        expect(missingId, isNot(contains(unavailable)));
        expect(missingId, isNot(contains('known-id')));
        expect(missingId, isNot(contains('missing-item')));
      },
    );
  });
}

PreparedMarker _bossWithChance(num chance) => _marker(
  id: 'boss-id',
  category: 'bosses',
  filterKey: 'BossSpawns',
  name: 'The Boss',
  details: {'spawnChance': chance},
);

PreparedMarker _marker({
  required String id,
  required String category,
  required String filterKey,
  required String name,
  required Map<String, dynamic> details,
  Map<String, dynamic> source = const {'mapId': 'map-a'},
}) => PreparedMarker(
  id: id,
  category: category,
  filterKey: filterKey,
  name: name,
  position: GamePoint(1, 2),
  details: details,
  source: source,
  outline: const [],
);

CatalogSnapshot _catalog({
  required GameMode mode,
  required Map<String, CatalogItem> items,
}) => CatalogSnapshot(
  mode: mode,
  revision: 'test-revision',
  observedAt: DateTime.utc(2025),
  items: items,
  traders: const {},
  requirements: const [],
);

CatalogItem _item(String id, String name) =>
    CatalogItem(id: id, name: name, normalizedName: name.toLowerCase());
