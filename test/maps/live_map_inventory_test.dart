import 'dart:convert';
import 'dart:typed_data';

import 'package:blackgrid/maps/live_map_budget.dart';
import 'package:blackgrid/maps/live_map_inventory.dart';
import 'package:blackgrid/maps/live_map_normalizer.dart';
import 'package:test/test.dart';

import '../../tool/maps/calibration.dart' show calibrationFor;

const _positions = 12;
const _largeFact = 'Shared task source fact with a nested searchable value.';

LiveMapSourceBodies _sources() => LiveMapSourceBodies(
  maps: {
    'data': {
      'maps': {
        'customs': {
          'id': 'source-customs',
          'normalizedName': 'customs',
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
            category: <Object?>[],
          'bosses': <Object?>[],
        },
      },
      'mobs': <String, Object?>{},
    },
  },
  mapTranslations: const {
    'data': {'customs': 'Customs'},
  },
  tasks: {
    'data': {
      'tasks': {
        'task-1': {
          'id': 'task-1',
          'name': 'TASK_NAME',
          'wikiLink': 'https://example.invalid/task-1',
          'unknownFutureFact': {
            'nested': [
              {'label': _largeFact},
            ],
          },
          'objectives': [
            {
              'id': 'objective-1',
              'description': 'OBJECTIVE_DESCRIPTION',
              'zones': [
                for (var index = 0; index < _positions; index++)
                  {
                    'id': 'zone-$index',
                    'map': 'source-customs',
                    'position': {'x': index, 'y': index + 1, 'z': index + 2},
                  },
              ],
              'possibleLocations': <Object?>[],
            },
          ],
        },
      },
      'questItems': <String, Object?>{},
    },
  },
  taskTranslations: const {
    'data': {
      'TASK_NAME': 'Synthetic task',
      'OBJECTIVE_DESCRIPTION': 'Synthetic objective',
    },
  },
  traders: const {'data': <String, Object?>{}},
  traderTranslations: const {'data': <String, Object?>{}},
);

LiveMapInventory _inventory() => LiveMapInventory.fromSources(
  sources: _sources(),
  bindings: [
    LiveMapBinding(
      sourceKey: 'customs',
      mapId: 'customs',
      calibration: calibrationFor('customs'),
    ),
  ],
  mode: 'pve',
  budget: LiveMapBudget(),
);

Uint8List _wireBytes(Object? wire) =>
    Uint8List.fromList(utf8.encode(jsonEncode(wire)));

Map<String, dynamic> _decodedWire(LiveMapInventory inventory) =>
    jsonDecode(utf8.decode(inventory.encode(budget: LiveMapBudget())))
        as Map<String, dynamic>;

void main() {
  group('LiveMapInventory', () {
    test(
      'shares complete task facts while preserving each occurrence identity',
      () {
        final markers = _inventory().maps['customs']!;

        expect(markers, hasLength(_positions));
        final firstTask = markers.first.details['sourceTask'];
        expect(firstTask, isA<Map<String, dynamic>>());
        expect(
          markers.every(
            (marker) => identical(marker.details['sourceTask'], firstTask),
          ),
          isTrue,
        );
        expect((firstTask as Map<String, dynamic>)['unknownFutureFact'], {
          'nested': [
            {'label': _largeFact},
          ],
        });
        expect(
          markers.map((marker) => marker.source['originalIdentity']['zoneId']),
          [for (var index = 0; index < _positions; index++) 'zone-$index'],
        );
        expect(
          markers.map((marker) => marker.id).toSet(),
          hasLength(_positions),
        );
        expect(() => (firstTask)['new'] = true, throwsUnsupportedError);
      },
    );

    test('pooled generated input containers remain charged until disposal', () {
      const count = 64;
      final sources = _sources();
      final data = sources.tasks['data']! as Map<String, dynamic>;
      final task =
          (data['tasks']! as Map<String, dynamic>)['task-1']!
              as Map<String, dynamic>;
      final objective =
          (task['objectives']! as List<dynamic>).single as Map<String, dynamic>;
      // The long, distinct identities make the generated per-occurrence
      // source and identity maps substantial without duplicating the task.
      final suffix = List.filled(512, 'x').join();
      objective['zones'] = <dynamic>[
        for (var index = 0; index < count; index++)
          {
            'id': 'zone-$index-$suffix',
            'map': 'source-customs',
            'position': {'x': index, 'y': index + 1, 'z': index + 2},
          },
      ];

      LiveMapInventory build(LiveMapBudget budget) =>
          LiveMapInventory.fromSources(
            sources: sources,
            bindings: [
              LiveMapBinding(
                sourceKey: 'customs',
                mapId: 'customs',
                calibration: calibrationFor('customs'),
              ),
            ],
            mode: 'pve',
            budget: budget,
          );

      const preexistingBytes = 1024;
      final adequateBudget = LiveMapBudget()
        ..reserveMaterialized(preexistingBytes);
      final inventory = build(adequateBudget);
      final markers = inventory.maps['customs']!;
      expect(markers, hasLength(count));
      final sharedTask = markers.first.details['sourceTask'];
      expect(
        markers.every(
          (marker) => identical(marker.details['sourceTask'], sharedTask),
        ),
        isTrue,
      );
      expect((sharedTask as Map<String, dynamic>)['unknownFutureFact'], {
        'nested': [
          {'label': _largeFact},
        ],
      });
      expect(
        markers.map((marker) => marker.source['originalIdentity']['zoneId']),
        [for (var index = 0; index < count; index++) 'zone-$index-$suffix'],
      );
      expect(markers.map((marker) => marker.id).toSet(), hasLength(count));
      expect(
        adequateBudget.materializedBytes,
        greaterThanOrEqualTo(preexistingBytes),
      );
      expect(
        adequateBudget.materializedBytes,
        lessThanOrEqualTo(
          inventory.retainedMaterializedBytes + preexistingBytes,
        ),
      );

      // The output plus 50% leaves room for the pool's reference index and
      // one marker's transient work, but not all the input maps held as keys.
      final constrained = LiveMapBudget(
        maxMaterializedBytes:
            preexistingBytes + inventory.retainedMaterializedBytes * 3 ~/ 2,
      )..reserveMaterialized(preexistingBytes);
      expect(
        () => build(constrained),
        throwsA(isA<LiveMapResourceLimitException>()),
      );
      // A failed build may retain its partial output charges, but not the
      // pool's temporary input-key/index charges after the pool is disposed.
      expect(
        constrained.materializedBytes,
        greaterThanOrEqualTo(preexistingBytes),
      );
      expect(
        constrained.materializedBytes,
        lessThanOrEqualTo(
          inventory.retainedMaterializedBytes + preexistingBytes,
        ),
      );
    });

    test('freezes nested source facts against later input mutation', () {
      final sources = _sources();
      final inventory = LiveMapInventory.fromSources(
        sources: sources,
        bindings: [
          LiveMapBinding(
            sourceKey: 'customs',
            mapId: 'customs',
            calibration: calibrationFor('customs'),
          ),
        ],
        mode: 'pve',
        budget: LiveMapBudget(),
      );
      final task =
          ((sources.tasks['data']! as Map<String, dynamic>)['tasks']!
                  as Map<String, dynamic>)['task-1']!
              as Map<String, dynamic>;
      final nested = task['unknownFutureFact']! as Map<String, dynamic>;
      final nestedList = nested['nested']! as List<dynamic>;
      (nestedList.first as Map<String, dynamic>)['label'] = 'mutated';
      nestedList.add(<String, String>{'label': 'later'});
      final frozen =
          inventory.maps['customs']!.first.details['sourceTask']
              as Map<String, dynamic>;

      expect(frozen['unknownFutureFact'], {
        'nested': [
          {'label': _largeFact},
        ],
      });
      expect(
        () =>
            ((frozen['unknownFutureFact'] as Map<String, dynamic>)['nested']
                    as List<dynamic>)
                .add('forbidden'),
        throwsUnsupportedError,
      );
    });

    test('preserves ordinary source facts that resemble compact wire tags', () {
      final sources = _sources();
      final data = sources.tasks['data']! as Map<String, dynamic>;
      final task =
          (data['tasks']! as Map<String, dynamic>)['task-1']!
              as Map<String, dynamic>;
      task['unknownFutureFact'] = {
        'referenceShape': {'kind': 'map', 'entries': [], r'$ref': 99},
        'tagLikeList': [1, 999],
        'scannerText': 'comma, brackets ] }, quote " slash \\\\',
      };

      final inventory = LiveMapInventory.fromSources(
        sources: sources,
        bindings: [
          LiveMapBinding(
            sourceKey: 'customs',
            mapId: 'customs',
            calibration: calibrationFor('customs'),
          ),
        ],
        mode: 'pve',
        budget: LiveMapBudget(),
      );
      final restored = LiveMapInventory.decode(
        inventory.encode(budget: LiveMapBudget()),
        budget: LiveMapBudget(),
      );
      final marker = restored.maps['customs']!.first;
      final fact =
          (marker.details['sourceTask']
                  as Map<String, dynamic>)['unknownFutureFact']
              as Map<String, dynamic>;

      expect(fact['referenceShape'], {
        'kind': 'map',
        'entries': [],
        r'$ref': 99,
      });
      expect(fact['tagLikeList'], [1, 999]);
      expect(fact['scannerText'], 'comma, brackets ] }, quote " slash \\\\');
    });

    test(
      'decoded nested facts remain immutable and detached from payload bytes',
      () {
        final original = _inventory();
        final payload = original.encode(budget: LiveMapBudget());
        final restored = LiveMapInventory.decode(
          payload,
          budget: LiveMapBudget(),
        );
        final sourceTask =
            restored.maps['customs']!.first.details['sourceTask']
                as Map<String, dynamic>;
        final nested = sourceTask['unknownFutureFact'] as Map<String, dynamic>;
        final nestedList = nested['nested'] as List<dynamic>;
        expect(
          () => (nestedList.first as Map<String, dynamic>)['label'] = 'mutated',
          throwsUnsupportedError,
        );
        expect(() => nestedList.add('later'), throwsUnsupportedError);

        payload.fillRange(0, payload.length, 0);

        expect((nestedList.first as Map<String, dynamic>)['label'], _largeFact);
      },
    );

    test('fromMarkers reuses trusted immutable fact graphs', () {
      final original = _inventory();
      final budget = LiveMapBudget();
      original.reserveRetained(budget);
      final borrowed = LiveMapInventory.fromMarkers(
        maps: original.maps,
        budget: budget,
      );
      final originalMarker = original.maps['customs']!.first;
      final borrowedMarker = borrowed.maps['customs']!.first;

      expect(identical(borrowedMarker.details, originalMarker.details), isTrue);
      expect(identical(borrowedMarker.source, originalMarker.source), isTrue);
      expect(
        identical(
          borrowedMarker.details['sourceTask'],
          originalMarker.details['sourceTask'],
        ),
        isTrue,
      );
      expect(
        () =>
            (borrowedMarker.details['sourceTask']
                    as Map<String, dynamic>)['id'] =
                'mutated',
        throwsUnsupportedError,
      );
    });

    test('compact encoding reload preserves shared immutable facts', () {
      final original = _inventory();
      final payload = original.encode(budget: LiveMapBudget());
      final wire = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final facts = wire['facts']! as List<dynamic>;
      for (var index = 0; index < facts.length; index++) {
        final fact = facts[index] as Map<String, dynamic>;
        final values = fact['kind'] == 'map'
            ? (fact['entries']! as Map<String, dynamic>).values
            : fact['items']! as List<dynamic>;
        for (final value in values) {
          if (value is List) expect(value[1], lessThan(index));
        }
      }
      final restored = LiveMapInventory.decode(
        payload,
        budget: LiveMapBudget(),
      );
      final markers = restored.maps['customs']!;

      expect(markers, hasLength(_positions));
      expect(
        markers.map((marker) => marker.id),
        original.maps['customs']!.map((marker) => marker.id),
      );
      expect(
        markers.every(
          (marker) => identical(
            marker.details['sourceTask'],
            markers.first.details['sourceTask'],
          ),
        ),
        isTrue,
      );
      expect(
        (markers.first.details['sourceTask'] as Map<String, dynamic>)['id'],
        'task-1',
      );
    });

    test('deep shared fact references decode iteratively', () {
      const depth = 12000;
      final facts = <Object?>[
        {
          'kind': 'list',
          'items': ['deep-end'],
        },
        for (var index = 1; index <= depth; index++)
          {
            'kind': 'list',
            'items': [
              [1, index - 1],
            ],
          },
        {
          'kind': 'map',
          'entries': {
            'deep': [1, depth],
          },
        },
        {
          'kind': 'map',
          'entries': {
            'deep': [1, depth],
          },
        },
      ];
      final payload = _wireBytes({
        'version': 2,
        'facts': facts,
        'maps': {
          'customs': [
            {
              'id': 'deep-marker',
              'category': 'test',
              'filterKey': 'test',
              'name': 'Deep fact',
              'position': {'x': 1, 'z': 2},
              'floorId': null,
              'outline': [],
              'heightBand': null,
              'detailsRef': depth + 1,
              'sourceRef': depth + 2,
            },
          ],
        },
      });

      final inventory = LiveMapInventory.decode(
        payload,
        budget: LiveMapBudget(),
      );
      final marker = inventory.maps['customs']!.single;
      final restored = LiveMapInventory.decode(
        inventory.encode(budget: LiveMapBudget()),
        budget: LiveMapBudget(),
      );
      expect(
        identical(
          restored.maps['customs']!.single.details['deep'],
          restored.maps['customs']!.single.source['deep'],
        ),
        isTrue,
      );
      var value = marker.details['deep'];
      for (var index = 0; index < depth; index++) {
        value = (value as List<Object?>).single;
      }
      expect(value, ['deep-end']);
    });

    test('malformed compact fact references and tags are rejected', () {
      final encoded = _decodedWire(_inventory());
      final facts = encoded['facts']! as List<dynamic>;
      final maps = encoded['maps']! as Map<String, dynamic>;
      final rows = maps['customs']! as List<dynamic>;
      final invalidPayloads = <Map<String, dynamic>>[];

      final missingDetailsReference =
          jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
      ((missingDetailsReference['maps']! as Map<String, dynamic>)['customs']!
              as List<dynamic>)
          .first
          .remove('detailsRef');
      invalidPayloads.add(missingDetailsReference);

      final missingSourceReference =
          jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
      ((missingSourceReference['maps']! as Map<String, dynamic>)['customs']!
              as List<dynamic>)
          .first
          .remove('sourceRef');
      invalidPayloads.add(missingSourceReference);

      final missingTarget =
          jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
      ((missingTarget['maps']! as Map<String, dynamic>)['customs']!
                  as List<dynamic>)
              .first['detailsRef'] =
          facts.length + 10;
      invalidPayloads.add(missingTarget);

      final outOfRangeNested =
          jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
      final nestedFacts = outOfRangeNested['facts']! as List<dynamic>;
      final mapFact = nestedFacts.cast<Map<String, dynamic>>().firstWhere(
        (fact) => fact['kind'] == 'map',
      );
      final entries = mapFact['entries']! as Map<String, dynamic>;
      entries[entries.keys.first] = [1, nestedFacts.length + 10];
      invalidPayloads.add(outOfRangeNested);

      final cycle = jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
      final cycleFacts = cycle['facts']! as List<dynamic>;
      final cycleFact = cycleFacts.cast<Map<String, dynamic>>().firstWhere(
        (fact) => fact['kind'] == 'map',
      );
      final cycleEntries = cycleFact['entries']! as Map<String, dynamic>;
      cycleEntries[cycleEntries.keys.first] = [
        1,
        cycleFacts.indexOf(cycleFact),
      ];
      invalidPayloads.add(cycle);

      final malformedTag =
          jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
      final malformedFacts = malformedTag['facts']! as List<dynamic>;
      final malformedFact = malformedFacts
          .cast<Map<String, dynamic>>()
          .firstWhere((fact) => fact['kind'] == 'map');
      final malformedEntries =
          malformedFact['entries']! as Map<String, dynamic>;
      malformedEntries[malformedEntries.keys.first] = [7, null];
      invalidPayloads.add(malformedTag);

      invalidPayloads.add({
        'version': 2,
        'facts': [
          {
            'kind': 'map',
            'entries': {
              'forward': [1, 1],
            },
          },
          {'kind': 'map', 'entries': <String, Object?>{}},
        ],
        'maps': <String, Object?>{},
      });

      expect(rows, isNotEmpty);
      for (final payload in invalidPayloads) {
        expect(
          () => LiveMapInventory.decode(
            _wireBytes(payload),
            budget: LiveMapBudget(),
          ),
          throwsFormatException,
        );
      }
    });

    test('incremental scanner validates root punctuation', () {
      for (final json in [
        '{"version":2 "facts":[],"maps":{}}',
        '{"version":2,"facts":[],"maps":{},}',
      ]) {
        expect(
          () => LiveMapInventory.decode(
            Uint8List.fromList(utf8.encode(json)),
            budget: LiveMapBudget(),
          ),
          throwsFormatException,
        );
      }
    });

    test('duplicate marker identities in a map are rejected', () {
      final payload = _decodedWire(_inventory());
      final rows =
          (payload['maps']! as Map<String, dynamic>)['customs']!
              as List<dynamic>;
      rows[1]['id'] = rows.first['id'];

      expect(
        () => LiveMapInventory.decode(
          _wireBytes(payload),
          budget: LiveMapBudget(),
        ),
        throwsFormatException,
      );
    });

    test('quest item spread is admitted before the shallow copy', () {
      final item = <String, dynamic>{
        'id': 'item-1',
        'name': 'ITEM_NAME',
        for (var index = 0; index < 128; index++) 'fact-$index': index,
      };
      final expectedCopyBytes = 128 + item.length * 32;
      var copyAdmissionReached = false;
      var emitted = false;

      expect(
        () => prepareQuestMarkers(
          mapId: 'source-customs',
          tasks: {
            'task-1': {
              'id': 'task-1',
              'name': 'TASK_NAME',
              'wikiLink': 'https://example.invalid/task-1',
              'objectives': [
                {
                  'id': 'objective-1',
                  'questItem': 'item-1',
                  'zones': [
                    {
                      'id': 'zone-1',
                      'map': 'source-customs',
                      'position': {'x': 1, 'z': 2},
                    },
                  ],
                },
              ],
            },
          },
          translations: {'TASK_NAME': 'Task'},
          traders: const {},
          traderTranslations: const {},
          questItems: {'item-1': item},
          questItemTranslations: {'ITEM_NAME': 'Synthetic item'},
          reserveMaterialization: (bytes) {
            if (bytes == expectedCopyBytes) {
              copyAdmissionReached = true;
              throw const LiveMapResourceLimitException(
                'Rejected quest-item shallow copy.',
              );
            }
          },
          onMarker: (_) => emitted = true,
        ),
        throwsA(isA<LiveMapResourceLimitException>()),
      );
      expect(copyAdmissionReached, isTrue);
      expect(emitted, isFalse);
    });

    test('wire graph premeasurement respects the materialization budget', () {
      final inventory = _inventory();
      final budget = LiveMapBudget(maxMaterializedBytes: 1024);

      expect(
        () => inventory.encode(budget: budget),
        throwsA(isA<LiveMapResourceLimitException>()),
      );
      expect(budget.materializedBytes, 0);
      expect(budget.serializedBytes, 0);
    });

    test(
      'distinct fact overflow is rejected before an inventory is returned',
      () {
        final largeUniqueSources = _sources();
        final tasks = largeUniqueSources.tasks['data']! as Map<String, dynamic>;
        final task =
            (tasks['tasks']! as Map<String, dynamic>)['task-1']!
                as Map<String, dynamic>;
        task['unknownFutureFact'] = {
          for (var index = 0; index < 128; index++)
            'distinct-$index': List.filled(1024, 'unique-$index').join(),
        };

        expect(
          () => LiveMapInventory.fromSources(
            sources: largeUniqueSources,
            bindings: [
              LiveMapBinding(
                sourceKey: 'customs',
                mapId: 'customs',
                calibration: calibrationFor('customs'),
              ),
            ],
            mode: 'pve',
            budget: LiveMapBudget(maxMaterializedBytes: 64 * 1024),
          ),
          throwsA(isA<LiveMapResourceLimitException>()),
        );
      },
    );
  });
}
