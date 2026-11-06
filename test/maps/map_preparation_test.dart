import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'package:blackgrid/domain/settings.dart' show supportedMaps;

import '../../tool/maps/pack.dart';

import 'package:blackgrid/maps/live_map_normalizer.dart'
    show canonicalJson, prepareMarkers;

import '../../tool/maps/svg.dart';
import '../../tool/maps/calibration.dart';
import '../support/map_preparation_fixtures.dart' show png;

Map<String, dynamic> _fixtureBoss({
  required String mob,
  required num spawnChance,
  required String location,
  required num x,
  required num? y,
  required num z,
  num locationChance = .5,
}) => {
  'mob': mob,
  'spawnChance': spawnChance,
  'spawnLocations': [
    {
      'name': location,
      'spawnChance': locationChance,
      'positions': [
        {'x': x, 'y': y, 'z': z},
      ],
    },
  ],
};

Map<String, dynamic> _bossSnapshot(String sourceKey, Object? bosses) => {
  'data': <String, dynamic>{
    'maps': <String, dynamic>{
      sourceKey: {
        'id': 'synthetic-$sourceKey',
        'normalizedName': sourceKey,
        'bosses': ?bosses,
      },
    },
    'mobs': <String, dynamic>{
      for (final mob in ['alpha', 'beta', 'control'])
        mob: <String, dynamic>{'name': 'BOSS_${mob.toUpperCase()}'},
    },
  },
};
String _bossDiagnosticFact(String description) => switch (description) {
  'missing bosses' ||
  'wrong bosses array' ||
  'boss record dictionary' => 'bosses',
  'missing spawnLocations' || 'wrong spawnLocations array' => 'spawnLocations',
  'location dictionary' ||
  'missing positions' ||
  'wrong positions array' => 'spawnLocations',
  'missing mob' || 'wrong mob type' || 'unknown mob' || 'empty mob' => 'mob',
  'missing boss chance' => 'spawnChance',
  _ when description.startsWith('invalid boss chance') => 'spawnChance',
  'missing location name' ||
  'empty location name' ||
  'invalid location name type' => 'name',
  'position dictionary' => 'positions',
  'missing x coordinate' => 'x',
  'missing z coordinate' => 'z',
  _ when description.startsWith('x ') => 'x',
  _ when description.startsWith('z ') => 'z',
  _ when description.startsWith('invalid height') => 'y',
  _ => throw StateError('No diagnostic field for $description'),
};

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('blackgrid-map-test-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test(
    'preparation source identities cover every unchanged selector exactly once',
    () {
      expect(supportedMapSources.keys, supportedMaps);
      expect(supportedMapSources.values.toSet(), hasLength(13));
      for (final entry in supportedMapSources.entries) {
        final local = calibrationFor(entry.value);
        expect(local['id'], entry.key);
        expect(local['sourceKey'], entry.value);
      }
      expect(supportedMapSources['thelab'], 'the-lab');
      expect(supportedMapSources['streetsoftarkov'], 'streets-of-tarkov');
      expect(supportedMapSources['groundzero'], 'ground-zero');
      expect(supportedMapSources['labyrinth'], 'the-labyrinth');
      for (final alias in [
        'lab',
        'labs',
        'thelab',
        'streetsoftarkov',
        'groundzero',
      ]) {
        expect(() => calibrationFor(alias), throwsFormatException);
      }
    },
  );

  for (final entry in <String, (List<String>, Set<String>, num)>{
    'customs': (
      [
        'Ground_Level',
        'Second_Floor',
        'Third_Floor',
        'Fourth_Floor',
        'Underground_Level',
      ],
      {'Fourth_Floor'},
      1062.4827,
    ),
    'reserve': (
      [
        'Ground_Level',
        'Second_Floor',
        'Third_Floor',
        'Fourth_Floor',
        'Fifth_Floor',
        'Bunkers',
      ],
      {'Second_Floor', 'Third_Floor', 'Fourth_Floor', 'Fifth_Floor'},
      827.28742,
    ),
  }.entries) {
    final (ids, tileOnly, width) = entry.value;
    test(
      '${entry.key} abstract SVG keeps every declared tile-only floor as an overlay',
      () {
        final local = calibrationFor(entry.key);
        final floors = (local['floors'] as List).cast<Map<String, Object?>>();
        expect(local['kind'], 'vector');
        expect(floors.map((floor) => floor['id']), ids);
        expect(
          floors.where((f) => f['sourceTileUrl'] != null).map((f) => f['id']),
          tileOnly,
        );
        expect((local['artworkFrame'] as Map)['width'], width);
        expect((local['geometry'] as Map)['projection'], 'bounds-normalized');
        expect((local['rasterOverlayFrame'] as Map)['nativeZoom'], 4);
        // The SVG frame is the original revision-0 pin basis again.
        expect((local['geometry'] as Map)['legacyPinBounds'], isNull);
        expect(
          (local['geometry'] as Map)['bounds'],
          entry.key == 'customs'
              ? [
                  [698, -307],
                  [-372, 237],
                ]
              : [
                  [289, -274],
                  [-303, 272],
                ],
        );
        final upstream = <String, dynamic>{
          'svgLayer': 'Ground_Level',
          'tilePath': 'https://example.invalid/main/{z}/{x}/{y}.png',
          'layers': [
            for (final floor in floors.skip(1))
              {
                'name': floor['id'],
                // Actual publisher has no svgLayer for the tile-only floors;
                // binding must not depend on inventing those groups.
                if (floor['sourceTileUrl'] != null)
                  'tilePath': floor['sourceTileUrl']
                else ...{
                  'svgLayer': floor['id'],
                  'tilePath': 'https://example.invalid/${floor['id']}.png',
                },
              },
          ],
        };
        expect(
          reconcileFloors(local, upstream).map((floor) => floor['id']),
          ids,
        );
        for (var index = 0; index < ids.length - 1; index++) {
          final changed = {
            ...upstream,
            'layers': [
              for (var i = 0; i < (upstream['layers'] as List).length; i++)
                if (i != index) (upstream['layers'] as List)[i],
            ],
          };
          expect(() => reconcileFloors(local, changed), throwsFormatException);
        }
        expect(
          () => reconcileFloors(local, {
            ...upstream,
            'layers': [
              ...(upstream['layers'] as List),
              {'tilePath': 'https://example.invalid/added/{z}/{x}/{y}.png'},
            ],
          }),
          throwsFormatException,
        );
      },
    );
  }

  test('SVG root floor closure and publisher attachments reject lost unowned or renamed groups', () {
    const source =
        '<svg viewBox="0 0 10 10">'
        '<g id="Ground_Level"/><g id="First_Floor" data-keep-with-group="Ground_Level"/>'
        '<g id="Second_Floor"/></svg>';
    final floors = <Map<String, Object?>>[
      {
        'id': 'Ground_Level',
        'attachedIds': ['First_Floor'],
      },
      {'id': 'Second_Floor', 'attachedIds': <String>[]},
    ];
    validateSvgFloorInventory(source, floors);
    expect(
      svgLayerOrder(source, {'Ground_Level', 'First_Floor', 'Second_Floor'}),
      ['Ground_Level', 'First_Floor', 'Second_Floor'],
    );
    for (final changed in [
      source.replaceFirst('<g id="Second_Floor"/>', ''),
      source.replaceFirst('</svg>', '<g id="Uncalibrated_Level"/></svg>'),
      source.replaceFirst('data-keep-with-group="Ground_Level"', ''),
      source.replaceFirst(
        'data-keep-with-group="Ground_Level"',
        'data-keep-with-group="Second_Floor"',
      ),
      source.replaceFirst('id="First_Floor"', 'id="Different_Floor"'),
      source.replaceFirst('<g id="Second_Floor"/>', '<g/>'),
      source.replaceFirst(
        '</svg>',
        '<defs><g data-keep-with-group="Ground_Level"/></defs></svg>',
      ),
      source.replaceFirst(
        '</svg>',
        '<defs><g id="First_Floor" data-keep-with-group="Ground_Level"/></defs></svg>',
      ),
    ]) {
      expect(
        () => validateSvgFloorInventory(changed, floors),
        throwsFormatException,
      );
    }
  });

  test(
    'Ground Zero requires exactly every metadata-declared raster alternative',
    () {
      final local = calibrationFor('ground-zero');
      final dependencies = (local['rasterDependencies'] as List).cast<Map>();
      final upstream = <String, dynamic>{
        'svgLayer': 'Ground_Level',
        'tilePath': dependencies.first['sourceTileUrl'],
        'layers': [
          for (final dependency in dependencies.skip(1))
            {
              'svgLayer': dependency['id'],
              'tilePath': dependency['sourceTileUrl'],
            },
        ],
      };
      final floors = reconcileFloors(local, upstream);
      expect(floors.map((floor) => floor['id']), [
        'Ground_Level',
        'Second_Floor',
        'Third_Floor',
        'Underground_Level',
      ]);
      expect(floors.first['attachedIds'], ['First_Floor']);
      for (final changed in [
        {...upstream, 'tilePath': null},
        {
          ...upstream,
          'layers': [
            ...(upstream['layers'] as List).skip(1),
            {'svgLayer': 'Second_Floor'},
          ],
        },
        {
          ...upstream,
          'layers': [
            ...(upstream['layers'] as List),
            {'tilePath': 'https://example.invalid/unknown/{z}/{x}/{y}.png'},
          ],
        },
      ]) {
        expect(() => reconcileFloors(local, changed), throwsFormatException);
      }
    },
  );

  test('decoded alpha, not HTTP length, identifies empty tiles', () {
    expect(inspectPng(png(2, 2, empty: true), expectedSize: 2).empty, isTrue);
    expect(inspectPng(png(2, 2), expectedSize: 2).empty, isFalse);
    expect(
      () => inspectPng(Uint8List.fromList([137, 80, 78, 71]), expectedSize: 2),
      throwsFormatException,
    );
    expect(() => inspectPng(png(3, 2), expectedSize: 2), throwsFormatException);
  });

  test('frozen source hash changes and missing files fail', () async {
    final root = Directory('${temporary.path}/raw');
    await root.create();
    final bytes = png(2, 2);
    final tile = File('${root.path}/tile.png');
    await tile.writeAsBytes(bytes);
    await File('${root.path}/sources.json').writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'sources': [
          {
            'path': 'tile.png',
            'url': 'https://example.invalid/tile.png',
            'sha256': sha256.convert(bytes).toString(),
          },
        ],
      }),
    );
    final frozen = await FrozenInputs.open(root);
    expect(await frozen.bytes('tile.png'), bytes);
    // An on-disk file is not a dependency unless the frozen index declares it.
    await File('${root.path}/unfrozen.png').writeAsBytes(bytes);
    await expectLater(frozen.bytes('unfrozen.png'), throwsFormatException);
    final indexFile = File('${root.path}/sources.json');
    final originalIndex =
        jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
    final entry =
        (originalIndex['sources'] as List).single as Map<String, dynamic>;
    await indexFile.writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'sources': [entry, Map<String, dynamic>.from(entry)],
      }),
    );
    await expectLater(
      FrozenInputs.open(root),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Duplicate frozen path tile.png',
        ),
      ),
    );
    await indexFile.writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'sources': [
          {...entry, 'url': 'http://example.invalid/tile.png'},
        ],
      }),
    );
    await expectLater(
      FrozenInputs.open(root),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Invalid frozen source URL: tile.png',
        ),
      ),
    );
    await indexFile.writeAsString(canonicalJson(originalIndex));
    await tile.writeAsBytes(png(2, 2, empty: true));
    await expectLater(FrozenInputs.open(root), throwsFormatException);
    await tile.delete();
    await expectLater(
      FrozenInputs.open(root),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('conditional floor override requires matching synthetic identity and full volume', () {
    final console = <String, dynamic>{
      'id': 'synthetic-console',
      'name': 'Synthetic console',
      'position': {'x': 4, 'y': 3, 'z': 2},
      'bottom': 2,
      'top': 4,
      'outline': [
        {'x': 3, 'y': 3, 'z': 1},
        {'x': 5, 'y': 3, 'z': 1},
        {'x': 5, 'y': 3, 'z': 3},
        {'x': 3, 'y': 3, 'z': 3},
      ],
    };
    final reviewedVolume = {
      'position': console['position'],
      'heightBand': [console['bottom'], console['top']],
      'outline': console['outline'],
    };
    final calibration = {
      ...calibrationFor('interchange'),
      'markerFloorAssignments': {
        'switches:synthetic-console:0': {
          'floorId': 'Synthetic_Floor',
          'sourceVolume': reviewedVolume,
        },
      },
    };
    Map<String, dynamic> snapshot(Map<String, dynamic> source) => {
      'data': {
        'maps': {
          'interchange': {
            'id': 'synthetic-interchange',
            'normalizedName': 'interchange',
            'switches': [source],
            'bosses': <Object>[],
          },
        },
      },
    };

    final matching = prepareMarkers(snapshot(console), {}, calibration).single;
    expect(matching['floorId'], 'Synthetic_Floor');
    expect(
      (matching['source'] as Map)['floorAssignment'],
      containsPair('floorId', 'Synthetic_Floor'),
    );

    for (final changed in [
      {...console, 'id': 'synthetic-unreviewed-same-name'},
      {...console, 'bottom': 1},
      {
        ...console,
        'position': {'x': 4.5, 'y': 3, 'z': 2},
      },
      {
        ...console,
        'position': {'x': 4, 'y': 3.5, 'z': 2},
      },
      {
        ...console,
        'outline': [
          ...(console['outline'] as List).cast<Map<String, dynamic>>().skip(1),
          {'x': 3, 'y': 3, 'z': 3},
        ],
      },
    ]) {
      final marker = prepareMarkers(snapshot(changed), {}, calibration).single;
      expect(marker.containsKey('floorId'), isFalse);
      expect((marker['source'] as Map).containsKey('floorAssignment'), isFalse);
    }
  });

  test(
    'unnamed transits take their translated description as the panel label',
    () {
      final snapshot = <String, dynamic>{
        'data': {
          'maps': {
            'factory': {
              'id': '5704e3c2d2720bac5b8b4567',
              'normalizedName': 'factory',
              'transits': [
                {
                  'id': '12',
                  'description': 'FAC_TRANSIT_12_DESC',
                  'position': {'x': 24.36, 'y': 2.24, 'z': 60.22},
                },
                {
                  'id': '13',
                  'description': 'UNTRANSLATED_DESC',
                  'position': {'x': 1, 'y': 0, 'z': 1},
                },
              ],
              'bosses': <Object>[],
            },
          },
        },
      };
      final markers = prepareMarkers(snapshot, {
        'FAC_TRANSIT_12_DESC': 'Transit to Woods',
      }, calibrationFor('factory'));
      expect(markers.map((marker) => marker['name']), [
        'Transit to Woods',
        'UNTRANSLATED_DESC',
      ]);
    },
  );

  test('boss positions preserve independently specified source facts', () {
    final customs = prepareMarkers(
      _bossSnapshot('customs', [
        _fixtureBoss(
          mob: 'alpha',
          spawnChance: .37,
          location: 'Customs stronghold',
          locationChance: .81,
          x: 11.25,
          y: null,
          z: -4.5,
        ),
      ]),
      {'BOSS_ALPHA': 'Translated Alpha'},
      calibrationFor('customs'),
    );
    final reserve = prepareMarkers(
      _bossSnapshot('reserve', [
        _fixtureBoss(
          mob: 'beta',
          spawnChance: .62,
          location: 'Reserve bunker',
          locationChance: .19,
          x: -8.5,
          y: 2.25,
          z: 17.75,
        ),
      ]),
      {'BOSS_BETA': 'Translated Beta'},
      calibrationFor('reserve'),
    );

    expect(customs.single['category'], 'bosses');
    expect(customs.single['name'], 'Translated Alpha');
    expect(customs.single['position'], {'x': 11.25, 'z': -4.5, 'height': null});
    expect(customs.single['details'], {
      'position': {'x': 11.25, 'y': null, 'z': -4.5},
      'mob': 'alpha',
      'spawnChance': .37,
      'location': 'Customs stronghold',
    });
    expect(reserve.single['name'], 'Translated Beta');
    expect(reserve.single['position'], {'x': -8.5, 'z': 17.75, 'height': 2.25});
    expect((reserve.single['details'] as Map)['spawnChance'], .62);
    expect((reserve.single['details'] as Map)['location'], 'Reserve bunker');
  });

  test('boss repeated positions preserve occurrence facts', () {
    final markers = prepareMarkers(
      _bossSnapshot('customs', [
        _fixtureBoss(
          mob: 'alpha',
          spawnChance: .22,
          location: 'Repeated location',
          locationChance: .41,
          x: 5,
          y: null,
          z: 7,
        ),
        _fixtureBoss(
          mob: 'alpha',
          spawnChance: .76,
          location: 'Repeated location',
          locationChance: .93,
          x: 5,
          y: null,
          z: 7,
        ),
      ]),
      {'BOSS_ALPHA': 'Translated Alpha'},
      calibrationFor('customs'),
    );
    expect(markers, hasLength(2));
    expect(markers.map((marker) => (marker['details'] as Map)['spawnChance']), [
      .22,
      .76,
    ]);
    expect(
      markers.map((marker) => (marker['details'] as Map)['position']),
      everyElement({'x': 5, 'y': null, 'z': 7}),
    );
    expect(markers.map((marker) => marker['id']).toSet(), hasLength(2));
  });

  test(
    'explicit empty boss location and position arrays have empty coverage',
    () {
      final emptyLocations = <String, Object?>{
        'mob': 'alpha',
        'spawnChance': .4,
        'spawnLocations': <Object>[],
      };
      final emptyPositions = <String, Object?>{
        'mob': 'beta',
        'spawnChance': .5,
        'spawnLocations': [
          {'name': 'No positions', 'spawnChance': .6, 'positions': <Object>[]},
        ],
      };
      final markers = prepareMarkers(
        _bossSnapshot('customs', [
          emptyLocations,
          emptyPositions,
          _fixtureBoss(
            mob: 'control',
            spawnChance: .7,
            location: 'Nonempty control',
            x: 1,
            y: 2,
            z: 3,
          ),
        ]),
        {},
        calibrationFor('customs'),
      );
      expect(markers, hasLength(1));
      expect((markers.single['details'] as Map)['mob'], 'control');
      expect(
        (markers.single['details'] as Map)['location'],
        'Nonempty control',
      );
    },
  );

  test('boss source rejects malformed required arrays and facts', () {
    final valid = _fixtureBoss(
      mob: 'alpha',
      spawnChance: .4,
      location: 'Valid location',
      x: 1,
      y: null,
      z: 2,
    );
    final invalidBosses = <(String, Object?)>[
      ('missing bosses', null),
      ('wrong bosses array', {'not': 'an array'}),
      ('boss record dictionary', ['not a dictionary']),
      (
        'missing spawnLocations',
        [
          {'mob': 'alpha', 'spawnChance': .4},
        ],
      ),
      (
        'wrong spawnLocations array',
        [
          {'mob': 'alpha', 'spawnChance': .4, 'spawnLocations': {}},
        ],
      ),
      (
        'location dictionary',
        [
          {
            'mob': 'alpha',
            'spawnChance': .4,
            'spawnLocations': ['not a dictionary'],
          },
        ],
      ),
      (
        'missing positions',
        [
          {
            'mob': 'alpha',
            'spawnChance': .4,
            'spawnLocations': [
              {'name': 'Here'},
            ],
          },
        ],
      ),
      (
        'wrong positions array',
        [
          {
            'mob': 'alpha',
            'spawnChance': .4,
            'spawnLocations': [
              {'name': 'Here', 'positions': {}},
            ],
          },
        ],
      ),
      (
        'missing mob',
        [
          {'spawnChance': .4, 'spawnLocations': valid['spawnLocations']},
        ],
      ),
      (
        'wrong mob type',
        [
          {
            'mob': {},
            'spawnChance': .4,
            'spawnLocations': valid['spawnLocations'],
          },
        ],
      ),
      (
        'empty mob',
        [
          {
            'mob': '',
            'spawnChance': .4,
            'spawnLocations': valid['spawnLocations'],
          },
        ],
      ),
      (
        'unknown mob',
        [
          {
            'mob': 'unknown',
            'spawnChance': .4,
            'spawnLocations': valid['spawnLocations'],
          },
        ],
      ),
      (
        'missing boss chance',
        [
          {'mob': 'alpha', 'spawnLocations': valid['spawnLocations']},
        ],
      ),
      (
        'missing location name',
        [
          {
            'mob': 'alpha',
            'spawnChance': .4,
            'spawnLocations': [
              {'positions': valid['spawnLocations']![0]['positions']},
            ],
          },
        ],
      ),
      (
        'empty location name',
        [
          {
            'mob': 'alpha',
            'spawnChance': .4,
            'spawnLocations': [
              {
                'name': '',
                'positions': valid['spawnLocations']![0]['positions'],
              },
            ],
          },
        ],
      ),
      (
        'invalid location name type',
        [
          {
            'mob': 'alpha',
            'spawnChance': .4,
            'spawnLocations': [
              {
                'name': 5,
                'positions': valid['spawnLocations']![0]['positions'],
              },
            ],
          },
        ],
      ),
      (
        'position dictionary',
        [
          {
            'mob': 'alpha',
            'spawnChance': .4,
            'spawnLocations': [
              {
                'name': 'Here',
                'positions': ['not a dictionary'],
              },
            ],
          },
        ],
      ),
      (
        'missing x coordinate',
        [
          {
            ...valid,
            'spawnLocations': [
              {
                'name': 'Missing x',
                'positions': [
                  {'y': null, 'z': 2},
                ],
              },
            ],
          },
        ],
      ),
      (
        'missing z coordinate',
        [
          {
            ...valid,
            'spawnLocations': [
              {
                'name': 'Missing z',
                'positions': [
                  {'x': 1, 'y': null},
                ],
              },
            ],
          },
        ],
      ),
      for (final axis in ['x', 'z'])
        for (final value in ['bad', double.nan, double.infinity])
          (
            '$axis invalid $value',
            [
              _fixtureBoss(
                  mob: 'alpha',
                  spawnChance: .4,
                  location: 'Invalid position',
                  x: axis == 'x' && value is num ? value : 1,
                  y: null,
                  z: axis == 'z' && value is num ? value : 2,
                )
                ..['spawnLocations'] = [
                  {
                    'name': 'Invalid position',
                    'positions': [
                      {
                        'x': axis == 'x' ? value : 1,
                        'y': null,
                        'z': axis == 'z' ? value : 2,
                      },
                    ],
                  },
                ],
            ],
          ),
      for (final value in ['bad', double.nan, double.infinity])
        (
          'invalid height $value',
          [
            _fixtureBoss(
                mob: 'alpha',
                spawnChance: .4,
                location: 'Invalid height',
                x: 1,
                y: value is num ? value : null,
                z: 2,
              )
              ..['spawnLocations'] = [
                {
                  'name': 'Invalid height',
                  'positions': [
                    {'x': 1, 'y': value, 'z': 2},
                  ],
                },
              ],
          ],
        ),
      for (final chance in ['bad', double.nan, double.infinity, -.01, 1.01])
        (
          'invalid boss chance $chance',
          [
            {...valid, 'spawnChance': chance},
          ],
        ),
    ];
    void expectMalformed(
      String description,
      Map<String, dynamic> snapshot,
      String fact,
    ) {
      expect(
        () => prepareMarkers(snapshot, {}, calibrationFor('customs')),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('markers/maps.json'),
              contains('customs'),
              contains(fact),
            ),
          ),
        ),
        reason: description,
      );
    }

    for (final (description, bosses) in invalidBosses) {
      expectMalformed(
        description,
        _bossSnapshot('customs', bosses),
        _bossDiagnosticFact(description),
      );
    }

    final badDictionaryCases = <(String, Map<String, dynamic>, String)>[];
    for (final (description, mutate, fact)
        in <(String, void Function(Map<String, dynamic>), String)>[
          ('missing mob dictionary', (data) => data.remove('mobs'), 'mobs'),
          ('wrong mob dictionary type', (data) => data['mobs'] = [], 'mobs'),
          (
            'missing mob dictionary entry',
            (data) => (data['mobs'] as Map).remove('alpha'),
            'alpha',
          ),
          (
            'wrong mob dictionary entry type',
            (data) => (data['mobs'] as Map)['alpha'] = 'not a dictionary',
            'alpha',
          ),
          (
            'missing resolved mob name',
            (data) => (data['mobs'] as Map)['alpha'] = {},
            'name',
          ),
          (
            'wrong resolved mob name type',
            (data) => (data['mobs'] as Map)['alpha'] = {'name': 5},
            'name',
          ),
        ]) {
      final snapshot = _bossSnapshot('customs', [valid]);
      mutate((snapshot['data'] as Map<String, dynamic>));
      badDictionaryCases.add((description, snapshot, fact));
    }
    for (final (description, snapshot, fact) in badDictionaryCases) {
      expectMalformed(description, snapshot, fact);
    }
  });

  test('absent metadata map is empty and duplicate identity is rejected', () {
    for (final entry in supportedMapSources.entries) {
      final missing = _bossSnapshot(entry.value, []);
      ((missing['data'] as Map)['maps'] as Map).remove(entry.value);
      expect(
        prepareMarkers(missing, {}, calibrationFor(entry.value)),
        isEmpty,
        reason: 'missing ${entry.value} yields an empty inventory',
      );

      final duplicate = _bossSnapshot(entry.value, []);
      ((duplicate['data'] as Map)['maps'] as Map)['duplicate'] = {
        'id': 'duplicate-${entry.key}',
        'normalizedName': entry.value,
        'bosses': <Object>[],
      };
      expect(
        () => prepareMarkers(duplicate, {}, calibrationFor(entry.value)),
        throwsA(isA<FormatException>()),
        reason: 'duplicate ${entry.value}',
      );
    }
  });

  test('canonical manifest bytes do not depend on insertion order', () {
    expect(
      canonicalJson({
        'b': 1,
        'a': {'z': 2, 'y': 3},
      }),
      canonicalJson({
        'a': {'y': 3, 'z': 2},
        'b': 1,
      }),
    );
  });

  test('local floor identities and bands survive changed upstream labels', () {
    final local = calibrationFor('the-lab');
    final upstream = {
      'tilePath': labsTiles.first,
      'layers': [
        {'name': 'Renamed technical', 'tilePath': labsTiles[2]},
        {'name': 'Renamed upper', 'tilePath': labsTiles[1]},
      ],
    };
    final floors = reconcileFloors(local, upstream);
    expect(floors.map((f) => f['id']), [
      'First_Level',
      'Second_Level',
      'Technical_Level',
    ]);
    expect(floors[1]['heightBand'], [3, 1000]);
    expect(
      () => reconcileFloors(local, {'tilePath': labsTiles.first, 'layers': []}),
      throwsFormatException,
    );
    final interchange = calibrationFor('interchange');
    final refreshedVector = reconcileFloors(interchange, {
      'svgLayer': 'Ground_Level',
      'tilePath': 'https://example.invalid/unselected-raster/{z}/{x}/{y}.png',
      'layers': [
        {'name': 'Renamed upper', 'svgLayer': 'Second_Floor'},
        {'name': 'Renamed middle', 'svgLayer': 'First_Floor'},
      ],
    });
    expect(refreshedVector.map((f) => f['id']), [
      'Ground_Level',
      'First_Floor',
      'Second_Floor',
    ]);
    expect(refreshedVector[1]['label'], '2nd Floor');
    expect(refreshedVector[1]['heightBand'], [25, 34]);
    expect(refreshedVector[2]['heightBand'], [34, 1000]);
    expect(calibrationFor('icebreaker')['floors'], hasLength(16));
    final ice = calibrationFor('icebreaker');
    final iceFloors = (ice['floors'] as List).cast<Map<String, Object?>>();
    final refreshedIce = reconcileFloors(ice, {
      'tilePath': iceFloors.singleWhere(
        (f) => f['base'] == true,
      )['sourceTileUrl'],
      'layers': [
        for (final f in iceFloors.reversed)
          {'name': 'Changed display label', 'tilePath': f['sourceTileUrl']},
      ],
    });
    expect(refreshedIce.map((f) => f['id']), icebreakerSources.keys);
    expect(refreshedIce.every((f) => f['exclusive'] == true), isTrue);
    expect(
      refreshedIce.singleWhere(
        (f) => f['id'] == 'Storage_Security',
      )['heightBand'],
      [15, 18.92],
    );
    expect(
      refreshedIce
          .singleWhere((f) => f['id'] == 'Infirmary')
          .containsKey('heightBand'),
      isFalse,
    );
    expect(
      () => reconcileFloors(local, {
        ...upstream,
        'layers': [
          ...(upstream['layers'] as List),
          {'tilePath': 'https://example.invalid/unknown/{z}/{x}/{y}.png'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('exact source drop-shadow transfers to explicit native vector effect', () {
    const source =
        '<svg width="10" height="10" viewBox="0 0 10 10"><style>.shadow {filter:drop-shadow(0 0 2px #000)}</style><g id="First_Floor" class="shadow"><path d="M0 0L1 1"/></g></svg>';
    final normalized = normalizeSvgFloor(
      source,
      {'First_Floor'},
      {'First_Floor'},
    );
    final compiled = compilerSvg(normalized, 'First_Floor');
    expect(compiled.effects, [
      {
        'type': 'drop-shadow',
        'dx': 0,
        'dy': 0,
        'sigma': 2,
        'color': '#000000',
        'sourceDeclaration': 'drop-shadow(0 0 2px #000)',
      },
    ]);
    expect(
      () => normalizeSvgFloor(
        source.replaceAll('2px', '3px'),
        {'First_Floor'},
        {'First_Floor'},
      ),
      throwsFormatException,
    );
  });

  test('attached content retains dependency targets without painting another floor', () {
    const source =
        '<svg viewBox="0 0 10 10"><g id="Ground_Level" fill="#123456"><use href="#Other"/></g><g id="Attached"><path d="M0 0L1 1"/></g><g id="Other"><g id="OtherPart"><path id="shared" d="M1 1L2 2"/></g></g></svg>';
    final document = XmlDocument.parse(
      normalizeSvgFloor(
        source,
        {'Ground_Level', 'Attached'},
        {'Ground_Level', 'Attached', 'Other', 'OtherPart'},
      ),
    );
    final elements = document.descendantElements.toList();
    expect(
      elements
          .singleWhere((e) => e.getAttribute('id') == 'shared')
          .ancestors
          .whereType<XmlElement>()
          .any((e) => e.name.local == 'defs'),
      isTrue,
    );
    final dependency = elements.singleWhere(
      (e) => e.getAttribute('id') == 'Other',
    );
    expect(dependency.childElements.single.getAttribute('id'), 'OtherPart');
    expect(
      dependency.descendantElements
          .singleWhere((e) => e.name.local == 'path')
          .getAttribute('d'),
      'M1 1L2 2',
    );
    expect(
      elements
          .singleWhere((e) => e.getAttribute('id') == 'Attached')
          .ancestors
          .whereType<XmlElement>()
          .any((e) => e.name.local == 'defs'),
      isFalse,
    );
    expect(svgLayerOrder(source, {'Ground_Level', 'Attached', 'Other'}), [
      'Ground_Level',
      'Attached',
      'Other',
    ]);
  });

  test('use with a missing local target renders nothing, like a browser', () {
    const source =
        '<svg viewBox="0 0 10 10"><defs><path id="kept" d="M0 0L1 1"/></defs><g id="Ground_Level"><use xlink:href="#kept" xmlns:xlink="http://www.w3.org/1999/xlink"/><use xlink:href="#stairs-86" xmlns:xlink="http://www.w3.org/1999/xlink"/></g></svg>';
    final uses = XmlDocument.parse(
      normalizeSvgFloor(source, {'Ground_Level'}, {'Ground_Level'}),
    ).findAllElements('use').toList();
    expect(uses.map((e) => e.getAttribute('href', namespace: '*')), ['#kept']);
    expect(
      () => normalizeSvgFloor(
        source.replaceAll('#stairs-86', '#stairs-1'),
        {'Ground_Level'},
        {'Ground_Level'},
      ),
      throwsFormatException,
      reason: 'only the known deleted Streets stair symbols are dropped',
    );
  });

  test(
    'unsafe href, missing paint target and excluded content fail closure',
    () {
      for (final source in [
        '<svg><g id="Ground_Level"><use href="https://bad.invalid/x.svg#x"/></g></svg>',
        '<svg><g id="Ground_Level"><path fill="url(#missing)"/></g></svg>',
        '<svg><g id="Second_Floor"/></svg>',
        '<svg><g id="Ground_Level"><image href="data:image/png;base64,AA=="/></g></svg>',
        '<svg><style>.floor {fill:url(https://bad.invalid/paint)}</style><g id="Ground_Level" class="floor"/></svg>',
      ]) {
        expect(
          () => normalizeSvgFloor(
            source,
            {'Ground_Level'},
            {'Ground_Level', 'Second_Floor'},
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('invalid candidate preserves active pointer and prior pack', () async {
    final packs = Directory('${temporary.path}/packs');
    await packs.create();
    final active = File('${packs.path}/active.json');
    await active.writeAsString('{"version":"A"}');
    final bad = Directory('${temporary.path}/bad');
    await bad.create();
    await File('${bad.path}/manifest.json').writeAsString(
      canonicalJson({'schemaVersion': 1, 'maps': [], 'outputs': []}),
    );
    await expectLater(promoteCandidate(bad, packs), throwsFormatException);
    expect(jsonDecode(await active.readAsString()), {'version': 'A'});
  });
}
