import 'package:test/test.dart';

import '../../tool/maps/calibration.dart';

import 'package:blackgrid/maps/live_map_normalizer.dart'
    show
        LiveMapBinding,
        LiveMapSourceBodies,
        normalizeLiveMapData,
        prepareMarkers,
        prepareQuestMarkers;

const _sourceKeys = [
  'factory',
  'customs',
  'woods',
  'shoreline',
  'interchange',
  'the-lab',
  'reserve',
  'lighthouse',
  'streets-of-tarkov',
  'ground-zero',
  'terminal',
  'icebreaker',
  'the-labyrinth',
];

Map<String, dynamic> _mapSource({
  Map<String, dynamic>? customs,
  Map<String, dynamic>? interchange,
  Map<String, dynamic>? icebreaker,
  Map<String, dynamic>? extra,
}) => {
  'data': <String, dynamic>{
    'maps': <String, dynamic>{
      for (final key in _sourceKeys)
        key: <String, dynamic>{
          'id': 'source-$key',
          'normalizedName': key,
          for (final category in [
            'extracts',
            'transits',
            'spawns',
            'locks',
            'hazards',
            'lootContainers',
            'lootLoose',
            'switches',
            'stationaryWeapons',
            'btrStops',
          ])
            category: <dynamic>[],
          'bosses': <dynamic>[],
        },
      'customs': ?customs,
      'interchange': ?interchange,
      'icebreaker': ?icebreaker,
      'new-upstream-map': ?extra,
    },
    'mobs': <String, dynamic>{
      'boss-alpha': {'name': 'Alpha'},
    },
  },
};

Map<String, dynamic> _mapRecord(
  String key, {
  String? id,
  List<dynamic>? switches,
  List<dynamic>? extracts,
  List<dynamic>? locks,
  List<dynamic>? bosses,
}) => {
  'id': id ?? 'source-$key',
  'normalizedName': key,
  'extracts': extracts ?? <dynamic>[],
  'transits': <dynamic>[],
  'spawns': <dynamic>[],
  'locks': locks ?? <dynamic>[],
  'hazards': <dynamic>[],
  'lootContainers': <dynamic>[],
  'lootLoose': <dynamic>[],
  'switches': switches ?? <dynamic>[],
  'stationaryWeapons': <dynamic>[],
  'btrStops': <dynamic>[],
  'bosses': bosses ?? <dynamic>[],
};

Map<String, dynamic> _boss({
  num x = 1,
  num y = 2,
  num z = 3,
  num chance = .25,
}) => {
  'mob': 'boss-alpha',
  'spawnChance': chance,
  'spawnLocations': [
    {
      'name': 'North',
      'spawnChance': .9,
      'positions': [
        {'x': x, 'y': y, 'z': z},
      ],
    },
  ],
};
Map<String, dynamic> _interchangeConsole({
  String id = '6b9023f26446d73433823e872e6d69688083beaf',
  num x = -46.555,
  num y = 37.347,
  num z = -55.202,
  num bottom = 37.187,
  num top = 37.507,
  List<dynamic>? outline,
}) => {
  'id': id,
  'name': 'Alarm switch',
  'position': {'x': x, 'y': y, 'z': z},
  'bottom': bottom,
  'top': top,
  'outline':
      outline ??
      [
        {'x': -46.81, 'y': 37.347, 'z': -55.517},
        {'x': -46.3, 'y': 37.347, 'z': -55.517},
        {'x': -46.3, 'y': 37.347, 'z': -54.887},
        {'x': -46.81, 'y': 37.347, 'z': -54.887},
      ],
};

Map<String, dynamic> _icebreakerHelicopter({
  String id = '9bf65c4c24d0153f1542a90ddabadb37198ab9ff',
  num x = .28,
  num y = 22.56,
  num z = -66.03,
}) => {
  'id': id,
  'name': 'Helicopter',
  'position': {'x': x, 'y': y, 'z': z},
};

Map<String, dynamic> _icebreakerC1({
  String id = 'f680d37a9e9c4f7b4673a2cd1bedd4a8ed73e104',
  String key = '69bb3f278af9f360ee010a7a',
  num x = -5.25,
  num y = 35.64,
  num z = 28.39,
}) => {
  'id': id,
  'name': 'Compartment C-1',
  'key': key,
  'position': {'x': x, 'y': y, 'z': z},
};

List<Map<String, Object?>> _prepareInterchangeConsole(
  Map<String, dynamic>? console,
) => prepareMarkers(
  _mapSource(
    interchange: console == null
        ? null
        : _mapRecord('interchange', switches: [console]),
  ),
  {},
  calibrationFor('interchange'),
);

List<Map<String, Object?>> _prepareIcebreaker({
  Map<String, dynamic>? helicopter,
  Map<String, dynamic>? c1,
}) => prepareMarkers(
  _mapSource(
    icebreaker: _mapRecord(
      'icebreaker',
      extracts: helicopter == null ? [] : [helicopter],
      locks: c1 == null ? [] : [c1],
    ),
  ),
  {},
  calibrationFor('icebreaker'),
);

Map<String, dynamic> _taskSource({
  bool includeTask = true,
  bool includeQuestItem = true,
  List<dynamic>? objectives,
}) => {
  'data': <String, dynamic>{
    'tasks': <String, dynamic>{
      if (includeTask)
        'task-1': <String, dynamic>{
          'id': 'task-1',
          'name': 'TASK_NAME',
          'trader': 'trader-1',
          'wikiLink': 'https://example.invalid/task-1',
          'objectives':
              objectives ??
              [
                {
                  'id': 'objective-1',
                  'description': 'OBJECTIVE_DESCRIPTION',
                  'zones': [
                    {
                      'id': 'zone-1',
                      'map': 'source-customs',
                      'position': {'x': 4, 'y': 5, 'z': 6},
                    },
                  ],
                  'possibleLocations': <dynamic>[],
                },
              ],
        },
    },
    'questItems': <String, dynamic>{
      if (includeQuestItem)
        'item-1': <String, dynamic>{'id': 'item-1', 'name': 'ITEM_NAME'},
    },
  },
};

Map<String, dynamic> _taskTranslations({bool omitName = false}) => {
  'data': <String, dynamic>{
    if (!omitName) 'TASK_NAME': 'A synthetic task',
    'OBJECTIVE_DESCRIPTION': 'Inspect the synthetic location',
    'ITEM_NAME': 'Synthetic item',
  },
};

Map<String, dynamic> _traderSource() => {
  'data': <String, dynamic>{
    'trader-1': <String, dynamic>{'id': 'trader-1', 'name': 'TRADER_NAME'},
  },
};

Map<String, dynamic> _traderTranslations() => {
  'data': <String, dynamic>{'TRADER_NAME': 'Synthetic trader'},
};

/// Joins the existing source-specific normalizers without hiding their outputs.
({List<Map<String, Object?>> map, List<Map<String, Object?>> quests})
_normalizeForMap({
  required String sourceKey,
  required Map<String, dynamic> maps,
  required Map<String, dynamic> mapTranslations,
  required Map<String, dynamic> tasks,
  required Map<String, dynamic> taskTranslations,
  required Map<String, dynamic> traders,
  required Map<String, dynamic> traderTranslations,
}) {
  final calibration = calibrationFor(sourceKey);
  final mapMarkers = prepareMarkers(maps, mapTranslations, calibration);
  final taskData = tasks['data'] as Map<String, dynamic>;
  final translatedTasks = taskTranslations['data'] as Map<String, dynamic>;
  final translatedTraders = traderTranslations['data'] as Map<String, dynamic>;
  final questMarkers = prepareQuestMarkers(
    mapId: 'source-$sourceKey',
    tasks: taskData['tasks'] as Map<String, dynamic>,
    questItems: taskData['questItems'] as Map<String, dynamic>,
    translations: translatedTasks,
    questItemTranslations: translatedTasks,
    traders: traders['data'] as Map<String, dynamic>,
    traderTranslations: translatedTraders,
  );
  return (map: mapMarkers, quests: questMarkers);
}

void main() {
  test('streaming callback failure releases normalization scratch', () {
    final maps = _mapSource(
      customs: _mapRecord(
        'customs',
        switches: [
          {
            'id': 'one',
            'name': 'One',
            'position': {'x': 1, 'z': 2},
          },
          {
            'id': 'two',
            'name': 'Two',
            'position': {'x': 3, 'z': 4},
          },
        ],
      ),
    );
    final failure = StateError('marker delivery failed');
    var reserved = 73;
    var emitted = 0;

    expect(
      () => normalizeLiveMapData(
        sources: LiveMapSourceBodies(
          maps: maps,
          mapTranslations: {'data': <String, dynamic>{}},
          tasks: _taskSource(includeTask: false),
          taskTranslations: _taskTranslations(),
          traders: _traderSource(),
          traderTranslations: _traderTranslations(),
        ),
        bindings: [
          LiveMapBinding(
            sourceKey: 'customs',
            mapId: 'customs',
            calibration: calibrationFor('customs'),
          ),
        ],
        mode: 'regular',
        reserveMaterialization: (bytes) => reserved += bytes,
        releaseMaterialization: (bytes) => reserved -= bytes,
        onMarker: (_, _) {
          if (++emitted == 2) throw failure;
        },
      ),
      throwsA(same(failure)),
    );
    expect(emitted, 2);
    expect(reserved, 73);
  });

  test('streaming quest validation failure releases temporary reservation', () {
    final data =
        _taskSource(
              objectives: [
                {
                  'id': 'objective-1',
                  'description': 'OBJECTIVE_DESCRIPTION',
                  'zones': [
                    {
                      'id': 'zone-1',
                      'map': 'source-customs',
                      'position': {'x': 'bad', 'y': 5, 'z': 6},
                    },
                  ],
                },
              ],
            )['data']
            as Map<String, dynamic>;
    var reserved = 73;
    var emitted = 0;
    expect(
      () => prepareQuestMarkers(
        mapId: 'source-customs',
        tasks: data['tasks'] as Map<String, dynamic>,
        questItems: data['questItems'] as Map<String, dynamic>,
        translations: _taskTranslations()['data'] as Map<String, dynamic>,
        questItemTranslations:
            _taskTranslations()['data'] as Map<String, dynamic>,
        traders: _traderSource()['data'] as Map<String, dynamic>,
        traderTranslations:
            _traderTranslations()['data'] as Map<String, dynamic>,
        reserveMaterialization: (bytes) => reserved += bytes,
        releaseMaterialization: (bytes) => reserved -= bytes,
        onMarker: (_) => emitted++,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(emitted, 0);
    expect(reserved, 73);
  });

  test('idless escape-heavy marker reserves fallback identity peak', () {
    final marker = <String, dynamic>{
      'name': 'Large detail',
      'position': {'x': 1, 'y': 2, 'z': 3},
      'detail': List.filled(1024, '\u0000').join(),
    };
    var reserved = 0;
    const budget = 12 * 1024;

    expect(
      () => prepareMarkers(
        _mapSource(customs: _mapRecord('customs', switches: [marker])),
        {},
        calibrationFor('customs'),
        reserveMaterialization: (bytes) {
          reserved += bytes;
          if (reserved > budget) {
            throw StateError('materialization budget exceeded');
          }
        },
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('six sources normalize a complete mode snapshot', () {
    final maps = _mapSource(
      customs: _mapRecord(
        'customs',
        bosses: [_boss(), _boss(x: 7, chance: .4)],
      ),
    );
    final result = _normalizeForMap(
      sourceKey: 'customs',
      maps: maps,
      mapTranslations: {'Alpha': 'Translated Alpha'},
      tasks: _taskSource(),
      taskTranslations: _taskTranslations(),
      traders: _traderSource(),
      traderTranslations: _traderTranslations(),
    );

    expect(result.map, hasLength(2));
    expect(
      result.map.map((marker) => marker['category']),
      everyElement('bosses'),
    );
    expect(
      result.map.map((marker) => marker['name']),
      everyElement('Translated Alpha'),
    );
    expect(result.map.map((marker) => marker['position']), [
      {'x': 1, 'z': 3, 'height': 2},
      {'x': 7, 'z': 3, 'height': 2},
    ]);
    expect(result.map.map((marker) => marker['details']), [
      {
        'position': {'x': 1, 'y': 2, 'z': 3},
        'mob': 'boss-alpha',
        'spawnChance': .25,
        'location': 'North',
      },
      {
        'position': {'x': 7, 'y': 2, 'z': 3},
        'mob': 'boss-alpha',
        'spawnChance': .4,
        'location': 'North',
      },
    ]);
    expect(result.quests, hasLength(1));
    expect(result.quests.single['category'], 'questObjectives');
    expect(result.quests.single['name'], 'Inspect the synthetic location');
    expect((result.quests.single['details'] as Map)['quest'], {
      'id': 'task-1',
      'name': 'A synthetic task',
      'trader': {'id': 'trader-1', 'name': 'Synthetic trader'},
      'wikiLink': 'https://example.invalid/task-1',
    });
  });

  test('malformed consumed records fail with their source', () {
    final malformedBoss = _mapSource(
      customs: _mapRecord('customs', bosses: [_boss(x: double.infinity)]),
    );
    expect(
      () => prepareMarkers(malformedBoss, {}, calibrationFor('customs')),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('customs/bosses/0/spawnLocations/0/positions/0'),
        ),
      ),
    );

    final malformedTask = _taskSource(
      objectives: [
        {
          'id': 'objective-1',
          'description': 'OBJECTIVE_DESCRIPTION',
          'zones': [
            {
              'id': 'zone-1',
              'map': 'source-customs',
              'position': {'x': 'bad', 'y': 5, 'z': 6},
            },
          ],
        },
      ],
    );
    expect(
      () => _normalizeForMap(
        sourceKey: 'customs',
        maps: _mapSource(),
        mapTranslations: {},
        tasks: malformedTask,
        taskTranslations: _taskTranslations(),
        traders: _traderSource(),
        traderTranslations: _traderTranslations(),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('tasks/task-1'),
        ),
      ),
    );
  });

  test('upstream additions removals and changes follow artwork inventory', () {
    final initial = _normalizeForMap(
      sourceKey: 'customs',
      maps: _mapSource(customs: _mapRecord('customs', bosses: [_boss()])),
      mapTranslations: {},
      tasks: _taskSource(),
      taskTranslations: _taskTranslations(),
      traders: _traderSource(),
      traderTranslations: _traderTranslations(),
    );
    final changedMaps = _mapSource(
      customs: _mapRecord('customs', bosses: [_boss(x: 11, chance: .8)]),
      extra: _mapRecord('new-upstream-map', bosses: [_boss(x: 90)]),
    )..['data']['maps'].remove('woods');
    final changed = _normalizeForMap(
      sourceKey: 'customs',
      maps: changedMaps,
      mapTranslations: {},
      tasks: _taskSource(includeTask: false),
      taskTranslations: _taskTranslations(),
      traders: _traderSource(),
      traderTranslations: _traderTranslations(),
    );

    expect(initial.map.single['position'], {'x': 1, 'z': 3, 'height': 2});
    expect(changed.map.single['position'], {'x': 11, 'z': 3, 'height': 2});
    expect((changed.map.single['details'] as Map)['spawnChance'], .8);
    expect(changed.quests, isEmpty);
    expect(prepareMarkers(changedMaps, {}, calibrationFor('woods')), isEmpty);
    expect(changed.map, hasLength(1));
    expect(
      changed.map.single['position'],
      isNot({'x': 90, 'z': 3, 'height': 2}),
    );
  });

  test('empty collections produce no invented markers', () {
    final result = _normalizeForMap(
      sourceKey: 'customs',
      maps: _mapSource(customs: _mapRecord('customs')),
      mapTranslations: {},
      tasks: _taskSource(includeTask: false, includeQuestItem: false),
      taskTranslations: {'data': <String, dynamic>{}},
      traders: {'data': <String, dynamic>{}},
      traderTranslations: {'data': <String, dynamic>{}},
    );

    expect(result.map, isEmpty);
    expect(result.quests, isEmpty);
  });

  test('missing references and translations omit unavailable facts', () {
    final result = _normalizeForMap(
      sourceKey: 'customs',
      maps: _mapSource(),
      mapTranslations: {},
      tasks: _taskSource(),
      taskTranslations: _taskTranslations(omitName: true),
      traders: {'data': <String, dynamic>{}},
      traderTranslations: {'data': <String, dynamic>{}},
    );

    expect(result.quests, hasLength(1));
    expect(result.quests.single['name'], 'Inspect the synthetic location');
    final details = result.quests.single['details'] as Map;
    expect(details['quest'], isA<Map>());
    expect(details['quest'], isNot(contains('name')));
    expect(details['quest'], isNot(contains('trader')));
  });

  test('reviewed floor overrides apply only to matching markers', () {
    final console = _interchangeConsole();
    final interchange = _prepareInterchangeConsole(console).single;
    expect(interchange['floorId'], 'Second_Floor');
    expect((interchange['source'] as Map)['floorAssignment'], isNotNull);
    expect(interchange['details'], console);

    final icebreaker = _prepareIcebreaker(
      helicopter: _icebreakerHelicopter(),
      c1: _icebreakerC1(),
    );
    expect(icebreaker.map((marker) => marker['floorId']), [
      'Helipad',
      'Officers_Deck',
    ]);
    expect(icebreaker.map((marker) => marker['position']), [
      {'x': .28, 'z': -66.03, 'height': 22.56},
      {'x': -5.25, 'z': 28.39, 'height': 35.64},
    ]);
    expect(
      icebreaker.map((marker) => (marker['source'] as Map)['floorAssignment']),
      everyElement(isNotNull),
    );
  });

  group('stale floor overrides neither reject nor resurrect markers', () {
    final staleExpectation = isNull;

    test('Interchange console is not overridden when removed', () {
      expect(_prepareInterchangeConsole(null), isEmpty);
    });

    test('Interchange console is not overridden after identity changes', () {
      final markers = _prepareInterchangeConsole(
        _interchangeConsole(id: 'changed-console-id'),
      );
      expect(markers, hasLength(1));
      expect(markers.single['floorId'], staleExpectation);
    });

    test('Interchange console is not overridden after horizontal movement', () {
      final markers = _prepareInterchangeConsole(
        _interchangeConsole(x: 1, z: 2),
      );
      expect(markers, hasLength(1));
      expect(markers.single['floorId'], staleExpectation);
      expect(markers.single['position'], {'x': 1, 'z': 2, 'height': 37.347});
    });

    test('Interchange console is not overridden after height changes', () {
      final markers = _prepareInterchangeConsole(_interchangeConsole(y: 38));
      expect(markers, hasLength(1));
      expect(markers.single['floorId'], staleExpectation);
    });

    test('Interchange console is not overridden after outline changes', () {
      final markers = _prepareInterchangeConsole(
        _interchangeConsole(
          outline: [
            {'x': 100, 'y': 37.347, 'z': 100},
          ],
        ),
      );
      expect(markers, hasLength(1));
      expect(markers.single['floorId'], staleExpectation);
    });

    test(
      'Interchange console is not overridden after volume bounds change',
      () {
        final markers = _prepareInterchangeConsole(
          _interchangeConsole(bottom: 37.1, top: 37.6),
        );
        expect(markers, hasLength(1));
        expect(markers.single['floorId'], staleExpectation);
      },
    );

    test('Icebreaker Helicopter is not overridden when removed', () {
      expect(_prepareIcebreaker(), isEmpty);
    });

    test('Icebreaker Helicopter is not overridden after identity changes', () {
      final markers = _prepareIcebreaker(
        helicopter: _icebreakerHelicopter(id: 'changed-helicopter-id'),
      );
      expect(markers, hasLength(1));
      expect(markers.single['floorId'], staleExpectation);
    });

    test(
      'Icebreaker Helicopter is not overridden after horizontal movement',
      () {
        final markers = _prepareIcebreaker(
          helicopter: _icebreakerHelicopter(x: 1, z: 2),
        );
        expect(markers, hasLength(1));
        expect(markers.single['floorId'], staleExpectation);
        expect(markers.single['position'], {'x': 1, 'z': 2, 'height': 22.56});
      },
    );

    test('Icebreaker Helicopter is not overridden after height changes', () {
      final markers = _prepareIcebreaker(
        helicopter: _icebreakerHelicopter(y: 23),
      );
      expect(markers, hasLength(1));
      expect(markers.single['floorId'], staleExpectation);
    });

    test('C-1 is not overridden when removed', () {
      expect(_prepareIcebreaker(c1: null), isEmpty);
    });

    test('C-1 is not overridden after identity changes', () {
      final markers = _prepareIcebreaker(
        c1: _icebreakerC1(id: 'changed-c1-id'),
      );
      expect(markers, hasLength(1));
      expect(markers.single['floorId'], staleExpectation);
    });

    test('C-1 is not overridden after horizontal movement', () {
      final markers = _prepareIcebreaker(c1: _icebreakerC1(x: 1, z: 2));
      expect(markers, hasLength(1));
      expect(markers.single['floorId'], staleExpectation);
      expect(markers.single['position'], {'x': 1, 'z': 2, 'height': 35.64});
    });

    test('C-1 is not overridden after height changes', () {
      final markers = _prepareIcebreaker(c1: _icebreakerC1(y: 36));
      expect(markers, hasLength(1));
      expect(markers.single['floorId'], staleExpectation);
    });

    test('C-1 is not overridden after key changes', () {
      final markers = _prepareIcebreaker(c1: _icebreakerC1(key: 'changed-key'));
      expect(markers, hasLength(1));
      expect(markers.single['floorId'], staleExpectation);
    });
  });
}
