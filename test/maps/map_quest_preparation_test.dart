import 'dart:convert';

import 'package:blackgrid/domain/map_marker_query.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:test/test.dart';

import '../../tool/maps/quest_markers.dart';

const _map = '56f40101d2720b2a4d8b45d6';
const _otherMap = '5714dbc024597771384a510d';
const _task = '5936da9e86f7742d65037edf';
const _trader = '54cb50c76803fa8b248b4571';
const _item = '5937fd0086f7742bf33fc198';

void main() {
  late _Inputs inputs;
  setUp(() => inputs = _Inputs());

  test(
    'prepares only exact-map zones and each actual item position in order',
    () {
      final markers = inputs.prepare();
      expect(markers.map((marker) => marker['category']), [
        'questObjectives',
        'questItems',
        'questItems',
      ]);
      expect(markers.map((marker) => marker['filterKey']), [
        'QuestObjectives',
        'QuestItems',
        'QuestItems',
      ]);
      expect(markers.map((marker) => marker['position']), [
        {'x': 1.0, 'z': -2.0, 'height': 3.0},
        {'x': 102.2964, 'z': -5.9064, 'height': 2.9634},
        {'x': 110.0, 'z': -8.0, 'height': null},
      ]);
      expect(markers.first['outline'], [
        {'x': 0.0, 'z': -3.0, 'height': 3.0},
        {'x': 2.0, 'z': -3.0, 'height': null},
        {'x': 2.0, 'z': -1.0, 'height': 3.0},
      ]);
      expect(markers.first['heightBand'], [2.0, 4.0]);
      expect(inputs.prepare(mapId: 'customs'), isEmpty);
      final other = inputs.prepare(mapId: _otherMap);
      expect(other.map((marker) => marker['position']), [
        {'x': 70.0, 'z': 80.0, 'height': 90.0},
        {'x': 500.0, 'z': 600.0, 'height': 700.0},
      ]);
    },
  );

  test(
    'translated metadata retains task trader objective item and conditions',
    () {
      final markers = inputs.prepare();
      expect(markers.first['name'], 'Inspect the vehicle');
      expect(markers[1]['name'], 'Bronze pocket watch on a chain');
      final details = markers[1]['details'] as Map;
      expect(details['quest'], {
        'id': _task,
        'name': 'Background Check',
        'trader': {'id': _trader, 'name': 'Prapor'},
        'wikiLink': 'https://escapefromtarkov.fandom.com/wiki/Background_Check',
      });
      expect(details['sourceTask'], inputs.tasks[_task]);
      expect(details['sourceTrader'], inputs.traders[_trader]);
      expect(details['objective'], inputs.itemObjective);
      expect(details['item'], inputs.items[_item]);
      expect(
        (details['questItem'] as Map)['name'],
        'Bronze pocket watch on a chain',
      );
      expect(details['description'], 'Find the bronze pocket watch');
      expect((details['objective'] as Map)['requiredKeys'], [
        ['truck-key'],
      ]);
      expect((details['sourceTask'] as Map)['otherRequirements'], [
        {'type': 'globalVariable', 'variableId': 'condition', 'value': 3},
      ]);
      final decoded = PreparedMarker.fromJson(
        jsonDecode(jsonEncode(markers[1])) as Map<String, dynamic>,
      );
      final metadata = MapMarkerMetadata(
        name: decoded.name,
        type: decoded.filterKey,
        category: decoded.category,
        details: decoded.details,
        source: decoded.source,
      );
      expect(metadata.questNames, ['Background Check']);
      expect(metadata.traders, ['Prapor']);
      expect(metadata.questLinks, [
        'https://escapefromtarkov.fandom.com/wiki/Background_Check',
      ]);
      expect(
        metadata.matchesQuest(name: 'background', trader: 'Prapor'),
        isTrue,
      );
      expect(
        metadata.matchesQuest(name: 'background', trader: 'Therapist'),
        isFalse,
      );
    },
  );

  test('source paths and original identities address precise occurrences', () {
    final markers = inputs.prepare();
    final zoneSource = markers.first['source'] as Map;
    expect(zoneSource['url'], 'https://json.tarkov.dev/regular/tasks');
    expect(zoneSource['mapId'], _map);
    expect(zoneSource['path'], 'tasks/$_task/objectives/0/zones/0');
    expect(zoneSource['originalIdentity'], {
      'taskId': _task,
      'objectiveId': 'visit-objective',
      'objectiveIndex': 0,
      'zoneId': 'truck-zone',
      'zoneIndex': 0,
    });
    final itemSource = markers[2]['source'] as Map;
    expect(
      itemSource['path'],
      'tasks/$_task/objectives/1/possibleLocations/0/positions/1',
    );
    expect(itemSource['originalIdentity'], {
      'taskId': _task,
      'objectiveId': 'find-objective',
      'objectiveIndex': 1,
      'questItemId': _item,
      'locationIndex': 0,
      'positionIndex': 1,
    });
  });

  test(
    'identities are unique for repeated source IDs and repeated coordinates',
    () {
      final zones = inputs.visitObjective['zones'] as List;
      zones.insert(1, jsonDecode(jsonEncode(zones.first)));
      final positions =
          ((inputs.itemObjective['possibleLocations'] as List).first
                  as Map)['positions']
              as List;
      positions.add(jsonDecode(jsonEncode(positions.first)));
      (inputs.tasks[_task]['objectives'] as List).add(
        jsonDecode(jsonEncode(inputs.itemObjective)),
      );
      final markers = inputs.prepare();
      final ids = markers.map((marker) => marker['id']).toList();
      expect(markers, hasLength(8));
      expect(ids.toSet(), hasLength(markers.length));
      expect(inputs.prepare().map((marker) => marker['id']), ids);
      inputs.translations['$_task name'] = 'Localized quest';
      expect(inputs.prepare().map((marker) => marker['id']), ids);
      expect(
        inputs
            .prepare(mapId: _otherMap)
            .map((marker) => marker['id'])
            .toSet()
            .intersection(ids.toSet()),
        isEmpty,
      );
    },
  );

  test(
    'item-bearing objective zones retain and validate their item dependency',
    () {
      inputs.visitObjective['questItem'] = _item;
      inputs.visitObjective['type'] = 'plantQuestItem';
      final marker = inputs.prepare().first;
      expect(marker['category'], 'questObjectives');
      expect(marker['name'], 'Inspect the vehicle');
      expect(
        ((marker['details'] as Map)['questItem'] as Map)['name'],
        'Bronze pocket watch on a chain',
      );
      expect(
        ((marker['source'] as Map)['originalIdentity'] as Map)['questItemId'],
        _item,
      );
      inputs.visitObjective['questItem'] = 'foreign';
      expect(inputs.prepare, throwsFormatException);
    },
  );

  test(
    'present but empty translated labels reject instead of leaking keys',
    () {
      inputs.translations['visit-objective'] = '   ';
      expect(inputs.prepare, throwsFormatException);
    },
  );

  test(
    'non-geometric objectives produce no invented markers or dependencies',
    () {
      inputs.tasks[_task]['objectives'] = [
        {
          'id': 'give-objective',
          'type': 'giveQuestItem',
          'questItem': 'unknown',
        },
        {
          'id': 'empty-objective',
          'type': 'findQuestItem',
          'possibleLocations': [
            {'map': _map, 'positions': <Object>[]},
          ],
        },
      ];
      inputs.translations.clear();
      inputs.traders.clear();
      inputs.items.clear();
      expect(inputs.prepare(), isEmpty);
    },
  );

  for (final missing in ['task', 'objective', 'trader', 'item']) {
    test('missing $missing translation explicitly rejects labels', () {
      switch (missing) {
        case 'task':
          inputs.translations.remove('$_task name');
        case 'objective':
          inputs.translations.remove('visit-objective');
        case 'trader':
          inputs.traderTranslations.remove('$_trader Nickname');
        case 'item':
          inputs.itemTranslations.remove('$_item Name');
      }
      expect(inputs.prepare, throwsFormatException);
    });
  }
  for (final missing in ['trader', 'item']) {
    test('foreign $missing dependency is rejected', () {
      if (missing == 'trader') inputs.tasks[_task]['trader'] = 'foreign';
      if (missing == 'item') inputs.itemObjective['questItem'] = 'foreign';
      expect(inputs.prepare, throwsFormatException);
    });
    test('mismatched $missing identity is rejected', () {
      if (missing == 'trader') inputs.traders[_trader]['id'] = 'foreign';
      if (missing == 'item') inputs.items[_item]['id'] = 'foreign';
      expect(inputs.prepare, throwsFormatException);
    });
  }

  test('task dictionary identity mismatch is rejected', () {
    inputs.tasks[_task]['id'] = 'foreign';
    expect(inputs.prepare, throwsFormatException);
  });

  for (final bad in [null, '1', double.nan, double.infinity]) {
    test(
      'missing or nonfinite zone X rejects rather than inventing position ($bad)',
      () {
        final zone = (inputs.visitObjective['zones'] as List).first as Map;
        (zone['position'] as Map)['x'] = bad;
        expect(inputs.prepare, throwsFormatException);
      },
    );
    test('missing or nonfinite item Z rejects ($bad)', () {
      final location =
          (inputs.itemObjective['possibleLocations'] as List).first as Map;
      ((location['positions'] as List).first as Map)['z'] = bad;
      expect(inputs.prepare, throwsFormatException);
    });
  }

  test('missing matching zone position rejects despite a valid outline', () {
    ((inputs.visitObjective['zones'] as List).first as Map).remove('position');
    expect(inputs.prepare, throwsFormatException);
  });
  test('missing matching item positions rejects', () {
    ((inputs.itemObjective['possibleLocations'] as List).first as Map).remove(
      'positions',
    );
    expect(inputs.prepare, throwsFormatException);
  });
  test(
    'optional height remains unknown but invalid provided height rejects',
    () {
      final zone = (inputs.visitObjective['zones'] as List).first as Map;
      (zone['position'] as Map).remove('y');
      expect((inputs.prepare().first['position'] as Map)['height'], isNull);
      (zone['position'] as Map)['y'] = double.infinity;
      expect(inputs.prepare, throwsFormatException);
    },
  );
  test('corrupted outline and invalid height bands reject', () {
    final zone = (inputs.visitObjective['zones'] as List).first as Map;
    final point = (zone['outline'] as List).first as Map;
    point['z'] = double.nan;
    expect(inputs.prepare, throwsFormatException);
    point['z'] = -3;
    zone['bottom'] = 5;
    expect(inputs.prepare, throwsFormatException);
    zone['bottom'] = 2;
    zone['top'] = null;
    expect(inputs.prepare, throwsFormatException);
  });
}

class _Inputs {
  // Production sources are decoded JSON, not covariant typed Dart literals.
  // Preserve that shape so malformed/duplicate mutations reach preparation.
  final tasks = jsonDecode(
    jsonEncode(<String, dynamic>{
      _task: {
        'id': _task,
        'name': '$_task name',
        'trader': _trader,
        'wikiLink': 'https://escapefromtarkov.fandom.com/wiki/Background_Check',
        'minPlayerLevel': 0,
        'taskRequirements': <Object>[],
        'otherRequirements': [
          {'type': 'globalVariable', 'variableId': 'condition', 'value': 3},
        ],
        'objectives': [
          {
            'id': 'visit-objective',
            'description': 'visit-objective',
            'type': 'visit',
            'optional': false,
            'zones': [
              {
                'id': 'truck-zone',
                'map': _map,
                'position': {'x': 1, 'y': 3, 'z': -2},
                'bottom': 2,
                'top': 4,
                'outline': [
                  {'x': 0, 'y': 3, 'z': -3},
                  {'x': 2, 'z': -3},
                  {'x': 2, 'y': 3, 'z': -1},
                ],
              },
              {
                'id': 'truck-zone',
                'map': _otherMap,
                'position': {'x': 70, 'y': 90, 'z': 80},
              },
            ],
          },
          {
            'id': 'find-objective',
            'description': 'find-objective',
            'type': 'findQuestItem',
            'count': 1,
            'optional': false,
            'questItem': _item,
            'requiredKeys': [
              ['truck-key'],
            ],
            'possibleLocations': [
              {
                'map': _map,
                'positions': [
                  {'x': 102.2964, 'y': 2.9634, 'z': -5.9064},
                  {'x': 110, 'y': null, 'z': -8},
                ],
              },
              {
                'map': _otherMap,
                'positions': [
                  {'x': 500, 'y': 700, 'z': 600},
                ],
              },
            ],
          },
          {
            'id': 'give-objective',
            'description': 'give-objective',
            'type': 'giveQuestItem',
            'questItem': _item,
          },
        ],
      },
    }),
  ) as Map<String, dynamic>;
  final translations = <String, dynamic>{
    '$_task name': 'Background Check',
    'visit-objective': 'Inspect the vehicle',
    'find-objective': 'Find the bronze pocket watch',
  };
  final traders = <String, dynamic>{
    _trader: {
      'id': _trader,
      'name': '$_trader Nickname',
      'normalizedName': 'prapor',
    },
  };
  final traderTranslations = <String, dynamic>{'$_trader Nickname': 'Prapor'};
  final items = <String, dynamic>{
    _item: {
      'id': _item,
      'name': '$_item Name',
      'width': 1,
      'height': 1,
      'normalizedName': 'bronze-pocket-watch-on-a-chain',
      'iconLink': 'https://assets.tarkov.dev/$_item-icon.webp',
    },
  };
  final itemTranslations = <String, dynamic>{
    '$_item Name': 'Bronze pocket watch on a chain',
  };

  Map<String, dynamic> get visitObjective =>
      tasks[_task]['objectives'][0] as Map<String, dynamic>;
  Map<String, dynamic> get itemObjective =>
      tasks[_task]['objectives'][1] as Map<String, dynamic>;

  List<Map<String, Object?>> prepare({String mapId = _map}) =>
      prepareQuestMarkers(
        mapId: mapId,
        tasks: tasks,
        translations: translations,
        traders: traders,
        traderTranslations: traderTranslations,
        questItems: items,
        questItemTranslations: itemTranslations,
      );
}
