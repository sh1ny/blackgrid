import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart'
    as compiler;

import 'package:blackgrid/application/map_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/maps/live_map_budget.dart';
import 'package:blackgrid/maps/live_map_inventory.dart';
import 'package:blackgrid/maps/live_map_normalizer.dart';
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:blackgrid/maps/native_map_scene.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';

import '../support/prepared_pack_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'OR search dims hazards and keeps their outline hits; category hides both',
    () async {
      final controller = _controller(
        markers: [
          _marker('door', 'extracts', 8, 24, name: 'North Door'),
          _marker('tunnel', 'transits', 24, 24, name: 'Tunnel'),
          _marker(
            'hazard',
            'hazards',
            16,
            8,
            name: 'Minefield',
            outline: [
              {'x': 12, 'z': 4, 'height': null},
              {'x': 20, 'z': 4, 'height': null},
              {'x': 20, 'z': 12, 'height': null},
              {'x': 12, 'z': 12, 'height': null},
            ],
          ),
        ],
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      controller.setSearch(' DOOR, tunnel ');
      final visible = controller.visibleMarkers();
      expect(visible.where((m) => !m.dimmed).map((m) => m.marker.id), [
        'door',
        'tunnel',
      ]);
      final hazard = visible.singleWhere((m) => m.marker.id == 'hazard');
      expect(hazard.dimmed, isTrue);
      final inside = controller.transform.sceneToViewport(ScenePoint(13, 25));
      expect(controller.hitTestMarker(inside, radius: 1)!.marker.id, 'hazard');
      controller.setCategoryVisibility({'HazardZones': false});
      expect(controller.visibleMarkers().map((m) => m.marker.id), [
        'door',
        'tunnel',
      ]);
      expect(controller.hitTestMarker(inside, radius: 1), isNull);
      expect(controller.search, ' DOOR, tunnel ');
    },
  );

  test(
    'scav, PMC, boss, and cultist spawn toggles hide only their own markers',
    () async {
      final controller = _controller(
        markers: [
          _marker(
            'scav',
            'spawns',
            8,
            8,
            details: {
              'sides': ['scav'],
            },
          ),
          _marker(
            'pmc',
            'spawns',
            12,
            8,
            details: {
              'sides': ['pmc'],
            },
          ),
          _marker('boss', 'bosses', 16, 8, details: {'mob': 'bossTagilla'}),
          _marker(
            'cultist',
            'bosses',
            20,
            8,
            details: {'mob': 'sectantPriest'},
          ),
        ],
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      List<String> visible() => [
        for (final m in controller.visibleMarkers()) m.marker.id,
      ];
      expect(visible(), ['scav', 'pmc', 'boss', 'cultist']);
      for (final (key, hidden) in [
        ('ScavSpawns', 'scav'),
        ('PmcSpawns', 'pmc'),
        ('BossSpawns', 'boss'),
        ('CultistSpawns', 'cultist'),
      ]) {
        controller.setCategoryVisibility({key: false});
        expect(visible(), [
          for (final id in ['scav', 'pmc', 'boss', 'cultist'])
            if (id != hidden) id,
        ], reason: key);
      }
    },
  );

  test(
    'quest filters AND exact trader are independent of category toggles',
    () async {
      final controller = _controller(
        markers: [
          _marker(
            'letter',
            'questItems',
            8,
            24,
            filterKey: 'QuestItems',
            details: {
              'quest': {
                'name': 'Delivery from the Past',
                'trader': {'name': 'Prapor'},
              },
            },
          ),
          _marker(
            'zone',
            'questObjectives',
            24,
            24,
            filterKey: 'QuestObjectives',
            details: {
              'quest': {
                'name': 'Delivery from the Past',
                'trader': {'name': 'Therapist'},
              },
            },
          ),
          _marker('exit', 'extracts', 16, 8),
        ],
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final questPoint = controller.visibleMarkers().first.viewportPoint;
      controller.setQuestFilters(name: 'FROM THE', trader: 'PRAPOR');
      expect(controller.visibleMarkers().map((m) => m.marker.id), [
        'letter',
        'exit',
      ]);
      controller.setCategoryVisibility({'QuestItems': false});
      expect(controller.visibleMarkers().map((m) => m.marker.id), ['exit']);
      expect(controller.hitTestMarker(questPoint), isNull);
      controller.setCategoryVisibility({});
      controller.setQuestFilters(trader: 'Prap');
      expect(controller.visibleMarkers().map((m) => m.marker.id), ['exit']);
      controller.setQuestFilters(trader: ' all ');
      expect(controller.visibleMarkers().map((m) => m.marker.id), [
        'letter',
        'zone',
        'exit',
      ]);
      controller.setQuestFilters(name: 'missing');
      expect(controller.visibleMarkers().map((m) => m.marker.id), ['exit']);
    },
  );

  test(
    'selection links only source switches and never moves the view',
    () async {
      final controller = _controller(
        markers: [
          _marker(
            'exit',
            'extracts',
            8,
            24,
            details: {
              'id': 'source-exit',
              'switches': ['source-switch'],
            },
          ),
          _marker(
            'linked',
            'switches',
            24,
            24,
            details: {'id': 'source-switch'},
          ),
          _marker(
            'reverse',
            'switches',
            24,
            8,
            details: {
              'id': 'other',
              'activates': [
                {'id': 'source-exit'},
              ],
            },
          ),
          _marker(
            'unlinked',
            'switches',
            8,
            8,
            name: 'Same exit name',
            details: {'id': 'different'},
          ),
        ],
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final before = controller.transform;
      controller.setSelectedMarker('exit');
      expect(identical(controller.transform, before), isTrue);
      expect(
        controller
            .visibleMarkers()
            .where((m) => m.linkedHighlighted)
            .map((m) => m.marker.id),
        ['linked', 'reverse'],
      );
      controller.setCategoryVisibility({'extracts': false});
      expect(
        controller.visibleMarkers().any((m) => m.linkedHighlighted),
        isFalse,
      );
      controller.setRaidHighlights({'unlinked', 'other-map-id'});
      expect(
        controller
            .visibleMarkers()
            .where((m) => m.raidHighlighted)
            .map((m) => m.marker.id),
        ['unlinked'],
      );
    },
  );
  test('selected marker projection survives an offscreen anchor and follows view transforms', () async {
    final controller = _controller(
      markers: [
        _marker(
          'exit',
          'extracts',
          8,
          24,
          outline: [
            {'x': 8, 'z': 20, 'height': null},
            {'x': 24, 'z': 20, 'height': null},
            {'x': 24, 'z': 28, 'height': null},
            {'x': 8, 'z': 28, 'height': null},
          ],
        ),
      ],
    );
    addTearDown(controller.dispose);
    controller.updateViewport(const Size(320, 320));
    await controller.initialize(selectedMapId: 'interchange');

    controller.setSelectedMarker('exit');
    final selected = controller.selectedMarkerProjection!;
    expect(selected.marker.id, 'exit');
    expect(
      selected.viewportPoint.x,
      closeTo(
        controller.transform.sceneToViewport(selected.scenePoint).x,
        1e-9,
      ),
    );
    expect(
      selected.viewportPoint.y,
      closeTo(
        controller.transform.sceneToViewport(selected.scenePoint).y,
        1e-9,
      ),
    );

    controller.panBy(-150, 0);
    final offscreen = controller.selectedMarkerProjection!;
    expect(offscreen.viewportPoint.x, lessThan(0));
    expect(
      controller.visibleMarkers(margin: 0).single.marker.id,
      'exit',
      reason:
          'The outline remains visible although the badge anchor is offscreen.',
    );
    expect(
      offscreen.viewportPoint.x,
      closeTo(
        controller.transform.sceneToViewport(offscreen.scenePoint).x,
        1e-9,
      ),
    );
    expect(
      offscreen.viewportPoint.y,
      closeTo(
        controller.transform.sceneToViewport(offscreen.scenePoint).y,
        1e-9,
      ),
    );

    controller.updateViewport(const Size(400, 300));
    await _settled(controller);
    final resized = controller.selectedMarkerProjection!;
    expect(resized.marker.id, 'exit');
    expect(
      resized.viewportPoint.x,
      closeTo(controller.transform.sceneToViewport(resized.scenePoint).x, 1e-9),
    );
    expect(
      resized.viewportPoint.y,
      closeTo(controller.transform.sceneToViewport(resized.scenePoint).y, 1e-9),
    );
    controller.setSearch('not this marker');
    final dimmed = controller.selectedMarkerProjection!;
    expect(dimmed.marker.id, 'exit');
    expect(dimmed.dimmed, isTrue);
  });

  test('ineligible or replaced selected markers clear with linked highlights immediately', () async {
    Future<MapController> selectedController() async {
      final controller = _controller(
        markers: [
          _marker(
            'quest-exit',
            'extracts',
            8,
            24,
            filterKey: 'QuestItems',
            details: {
              'id': 'source-exit',
              'switches': ['source-switch'],
              'quest': {
                'name': 'Delivery',
                'trader': {'name': 'Prapor'},
              },
            },
          )..['floorId'] = 'Upper',
          _marker(
            'linked-switch',
            'switches',
            24,
            24,
            details: {'id': 'source-switch'},
          ),
        ],
      );
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      controller.toggleFloor('Upper');
      controller.setSelectedMarker('quest-exit');
      expect(controller.selectedMarkerProjection, isNotNull);
      expect(
        controller.visibleMarkers().where((m) => m.linkedHighlighted),
        isNotEmpty,
      );
      return controller;
    }

    Future<void> expectSynchronousClear(
      void Function(MapController) invalidate,
      void Function(MapController) reverse,
    ) async {
      final controller = await selectedController();
      addTearDown(controller.dispose);
      var notifications = 0;
      var inconsistentNotification = false;
      controller.addListener(() {
        notifications++;
        if (controller.selectedMarkerProjection != null ||
            controller.visibleMarkers().any((m) => m.linkedHighlighted)) {
          inconsistentNotification = true;
        }
      });
      invalidate(controller);
      expect(controller.selectedMarkerProjection, isNull);
      expect(
        controller.visibleMarkers().any((m) => m.linkedHighlighted),
        isFalse,
      );
      expect(notifications, greaterThan(0));
      expect(inconsistentNotification, isFalse);
      reverse(controller);
      expect(controller.selectedMarkerProjection, isNull);
      expect(
        controller.visibleMarkers().any((m) => m.linkedHighlighted),
        isFalse,
      );
    }

    await expectSynchronousClear(
      (controller) => controller.setCategoryVisibility({'QuestItems': false}),
      (controller) => controller.setCategoryVisibility({}),
    );
    await expectSynchronousClear(
      (controller) => controller.setQuestFilters(name: 'missing'),
      (controller) => controller.setQuestFilters(name: ''),
    );
    await expectSynchronousClear(
      (controller) => controller.toggleFloor('Upper'),
      (controller) => controller.toggleFloor('Upper'),
    );

    final controller = await selectedController();
    addTearDown(controller.dispose);
    await controller.selectPersistedMap('icebreaker');
    expect(controller.selectedMarkerProjection, isNull);
    await controller.selectPersistedMap('interchange');
    expect(controller.selectedMarkerProjection, isNull);

    controller.setSelectedMarker('quest-exit');
    expect(controller.selectedMarkerProjection, isNotNull);
    await controller.initialize(selectedMapId: 'interchange');
    expect(controller.selectedMarkerProjection, isNull);
  });

  test(
    'marker inventory replacement is structural, coherent, and view preserving',
    () async {
      var artworkLoads = 0;
      final controller = _controller(
        artwork: (path) async {
          artworkLoads++;
          return _picture();
        },
        markers: [_marker('old', 'extracts', 8, 24, name: 'Old exit')],
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      controller.zoomAt(ViewportPoint(100, 100), 1.5);
      controller.panBy(13, -7);
      controller.toggleFloor('Upper');
      controller.setCategoryVisibility({'old-filter': false});
      controller.setSelectedMarker('old');
      final beforeTransform = controller.transform;
      final beforeFloor = controller.floorSelection;
      final beforeScene = controller.scene;
      final beforeArtworkLoads = artworkLoads;
      final generation = controller.contentGeneration;
      final snapshot = _snapshot(controller, {
        'interchange': [
          _snapshotMarker(
            id: 'new',
            category: 'switches',
            filterKey: 'new-filter',
            name: 'New switch',
            x: 12,
            z: 20,
            details: {'id': 'new'},
          ),
        ],
        'icebreaker': const [],
      });

      final originalInventory = controller.activeMarkers;
      final activate = controller.prepareMarkerInventory(
        snapshot,
        budget: LiveMapBudget(),
      );
      expect(controller.activeMarkers, same(originalInventory));
      expect(controller.contentGeneration, generation);
      expect(activate(), isTrue);
      expect(controller.contentGeneration, generation + 1);
      expect(controller.selectedMarkerProjection, isNull);
      expect(controller.visibleMarkers().map((marker) => marker.marker.id), [
        'new',
      ]);
      expect(controller.applicableCategories, contains('new-filter'));
      expect(controller.applicableCategories, isNot(contains('old-filter')));
      expect(controller.transform.scale, beforeTransform.scale);
      expect(controller.transform.translationX, beforeTransform.translationX);
      expect(controller.transform.translationY, beforeTransform.translationY);
      expect(controller.floorSelection, same(beforeFloor));
      expect(controller.scene, same(beforeScene));
      expect(artworkLoads, beforeArtworkLoads);
      final newPoint = controller.visibleMarkers().single.viewportPoint;
      expect(controller.hitTestMarker(newPoint)?.marker.id, 'new');

      controller.setSelectedMarker('new');
      expect(
        controller.prepareMarkerInventory(
          _snapshot(controller, {
            'interchange': [
              _snapshotMarker(
                id: 'new',
                category: 'switches',
                filterKey: 'new-filter',
                name: 'New switch',
                x: 12,
                z: 20,
                details: {'id': 'new'},
              ),
            ],
            'icebreaker': const [],
          }),
          budget: LiveMapBudget(),
        )(),
        isFalse,
      );
      expect(controller.selectedMarkerProjection?.marker.id, 'new');
      expect(controller.contentGeneration, generation + 1);
      expect(artworkLoads, beforeArtworkLoads);
    },
  );

  test(
    'inventory initialization invalidates a prepared marker activation',
    () async {
      final controller = _controller(
        markers: [_marker('prepared', 'extracts', 8, 24)],
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final preparedPack = controller.pack!;
      final staleSnapshot = _snapshot(controller, {
        'interchange': [
          _snapshotMarker(
            id: 'stale',
            category: 'switches',
            filterKey: 'Switches',
            name: 'Stale switch',
            x: 12,
            z: 20,
            details: {'fact': 'must not be installed'},
          ),
        ],
        'icebreaker': const [],
      });
      final activate = controller.prepareMarkerInventory(
        staleSnapshot,
        budget: LiveMapBudget(),
      );
      final generationBeforeInitialize = controller.contentGeneration;

      final initialization = controller.initialize(
        selectedMapId: 'interchange',
      );
      expect(controller.pack, same(preparedPack));
      expect(controller.contentGeneration, generationBeforeInitialize + 1);
      expect(activate(), isFalse);
      await initialization;

      expect(controller.pack, same(preparedPack));
      expect(controller.activeMarkers.map((marker) => marker.id), ['prepared']);
      expect(controller.contentGeneration, generationBeforeInitialize + 1);
    },
  );

  test(
    'refreshed identical inventory keeps selection but charges retained memory',
    () async {
      final controller = _controller(
        markers: [_marker('prepared', 'extracts', 8, 24)],
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final snapshot = _snapshot(controller, {
        'interchange': [
          {
            ..._snapshotMarker(
              id: 'selected',
              category: 'extracts',
              filterKey: 'Extracts',
              name: 'Selected exit',
              x: 12,
              z: 20,
              details: {
                'retainedFact': {'value': List.filled(32, 'retained').join()},
              },
            ),
            'outline': _square(10, 14),
          },
        ],
        'icebreaker': const [],
      });
      expect(
        controller.prepareMarkerInventory(snapshot, budget: LiveMapBudget())(),
        isTrue,
      );
      controller.setSelectedMarker('selected');
      final selectedProjection = controller.selectedMarkerProjection!;
      final selectedInventory = controller.activeMarkers.single;
      final contentGeneration = controller.contentGeneration;
      final refreshedSnapshot = LiveMapSnapshot(
        mode: snapshot.mode,
        checkedAt: snapshot.checkedAt.add(const Duration(minutes: 1)),
        normalizedPayload: Uint8List.fromList(snapshot.normalizedPayload),
        sources: snapshot.sources,
        formatVersion: snapshot.formatVersion,
        normalizerVersion: snapshot.normalizerVersion,
        compatibility: snapshot.compatibility,
      );

      expect(
        refreshedSnapshot.normalizedPayload,
        orderedEquals(snapshot.normalizedPayload),
      );
      expect(
        refreshedSnapshot.compatibility.fingerprint,
        snapshot.compatibility.fingerprint,
      );
      expect(
        controller.prepareMarkerInventory(
          refreshedSnapshot,
          budget: LiveMapBudget(),
        )(),
        isFalse,
      );
      expect(controller.activeMarkers.single, same(selectedInventory));
      expect(controller.selectedMarkerProjection, same(selectedProjection));
      expect(controller.contentGeneration, contentGeneration);

      final baselineBudget = _PeakTrackingLiveMapBudget();
      controller.prepareMarkerInventory(
        refreshedSnapshot,
        budget: baselineBudget,
      )();
      final baselinePeak = baselineBudget.peakMaterializedBytes;
      controller.setSearch(
        List.generate(256, (index) => 'retained-query-$index').join(' '),
      );
      controller.visibleMarkers();
      final selectedAfterQuery = controller.selectedMarkerProjection;
      expect(selectedAfterQuery, isNotNull);

      expect(
        () => controller.prepareMarkerInventory(
          refreshedSnapshot,
          budget: LiveMapBudget(maxMaterializedBytes: baselinePeak),
        ),
        throwsA(isA<LiveMapResourceLimitException>()),
      );
      expect(controller.activeMarkers.single, same(selectedInventory));
      expect(controller.selectedMarkerProjection, same(selectedAfterQuery));
      expect(controller.contentGeneration, contentGeneration);
    },
  );

  test(
    'malformed compact wire preserves the active marker authority',
    () async {
      final controller = _controller(
        markers: [_marker('retained', 'extracts', 8, 24)],
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      controller.setSelectedMarker('retained');
      final retained = controller.activeMarkers.single;
      final generation = controller.contentGeneration;
      final valid = _snapshot(controller, {
        'interchange': [
          _snapshotMarker(
            id: 'invalid-reference-candidate',
            category: 'switches',
            filterKey: 'Switches',
            name: 'Invalid reference candidate',
            x: 12,
            z: 20,
          ),
        ],
        'icebreaker': const [],
      });
      final wire = jsonDecode(
        utf8.decode(valid.normalizedPayload),
      ) as Map<String, dynamic>;
      final maps = wire['maps'] as Map<String, dynamic>;
      final row = (maps['interchange'] as List).single as Map<String, dynamic>;
      row['detailsRef'] = (wire['facts'] as List).length;
      final malformed = LiveMapSnapshot(
        mode: valid.mode,
        checkedAt: valid.checkedAt,
        normalizedPayload: Uint8List.fromList(utf8.encode(jsonEncode(wire))),
        sources: valid.sources,
        formatVersion: valid.formatVersion,
        normalizerVersion: valid.normalizerVersion,
        compatibility: valid.compatibility,
      );

      expect(
        () => controller.prepareMarkerInventory(
          malformed,
          budget: LiveMapBudget(),
        ),
        throwsFormatException,
      );
      expect(controller.activeMarkers.single, same(retained));
      expect(controller.visibleMarkers().single.marker, same(retained));
      expect(controller.selectedMarkerProjection?.marker.id, 'retained');
      expect(controller.contentGeneration, generation);
    },
  );

  test(
    'search after activation does not consume a retired refresh budget',
    () async {
      final controller = _controller(
        markers: [_marker('retained', 'extracts', 8, 24)],
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final candidate = _snapshot(controller, {
        'interchange': [
          _snapshotMarker(
            id: 'searchable',
            category: 'switches',
            filterKey: 'Switches',
            name: 'Searchable switch',
            x: 12,
            z: 20,
            details: {'unknownSearchFact': 'Beacon of Truth'},
          ),
        ],
        'icebreaker': const [],
      });
      final refreshBudget = LiveMapBudget();
      controller.prepareMarkerInventory(candidate, budget: refreshBudget)();
      refreshBudget.reserveMaterialized(
        refreshBudget.maxMaterializedBytes - refreshBudget.materializedBytes,
      );

      controller.setSearch('beacon of truth');
      expect(
        controller
            .visibleMarkers()
            .where((marker) => !marker.dimmed)
            .map((marker) => marker.marker.id),
        ['searchable'],
      );
      controller.setSearch('absent phrase');
      expect(
        controller.visibleMarkers().where((marker) => !marker.dimmed),
        isEmpty,
      );
    },
  );

  test(
    'derived searchable-state overflow preserves active marker authority',
    () async {
      final controller = _controller(
        markers: [_marker('retained', 'extracts', 8, 24)],
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final retained = controller.activeMarkers.single;
      final generation = controller.contentGeneration;
      final distinctLeaves = [
        for (var index = 0; index < 64; index++)
          'MiXeD-search-fact-$index-${'q' * 256}',
      ];
      final compact = _snapshot(controller, {
        'interchange': [
          _snapshotMarker(
            id: 'search-heavy',
            category: 'switches',
            filterKey: 'Switches',
            name: 'Search-heavy switch',
            x: 12,
            z: 20,
            details: {'unknownSearchFacts': distinctLeaves},
          ),
        ],
        'icebreaker': const [],
      });

      final noSearchBudget = _PeakTrackingLiveMapBudget();
      controller.prepareMarkerInventory(compact, budget: noSearchBudget);
      expect(noSearchBudget.peakMaterializedBytes, greaterThan(0));

      controller.setSearch('absent-query-not-in-any-leaf');
      controller.setSelectedMarker('retained');
      final constrainedBudget = LiveMapBudget(
        maxMaterializedBytes: noSearchBudget.peakMaterializedBytes,
      );
      expect(
        () => controller.prepareMarkerInventory(
          compact,
          budget: constrainedBudget,
        ),
        throwsA(isA<LiveMapResourceLimitException>()),
      );
      expect(controller.activeMarkers.single, same(retained));
      expect(controller.selectedMarkerProjection?.marker.id, 'retained');
      expect(controller.contentGeneration, generation);
    },
  );

  test(
    'oversized nested marker inventory rejects before replacing active markers',
    () async {
      final controller = _controller(
        markers: [_marker('retained', 'extracts', 8, 24)],
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final retained = controller.activeMarkers.single;
      final generation = controller.contentGeneration;
      final oversized = _snapshot(controller, {
        'interchange': [
          _snapshotMarker(
            id: 'expanded',
            category: 'extracts',
            filterKey: 'SharedExtracts',
            name: 'Expanded exit',
            x: 12,
            z: 20,
            details: {
              'nested': [
                for (var index = 0; index < 80; index++)
                  {
                    'labels': ['shared nested content $index'],
                    'facts': {'enabled': true, 'count': index},
                  },
              ],
            },
          ),
        ],
        'icebreaker': const [],
      });

      expect(
        () => controller.prepareMarkerInventory(
          oversized,
          budget: LiveMapBudget(maxMaterializedBytes: 1024),
        ),
        throwsA(isA<LiveMapResourceLimitException>()),
      );
      expect(controller.activeMarkers.single, same(retained));
      expect(controller.visibleMarkers().single.marker, same(retained));
      expect(controller.contentGeneration, generation);
    },
  );

  test(
    'player center preserves scale and world heading uses existing geometry',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final generation = controller.contentGeneration;
      controller.zoomAt(ViewportPoint(100, 100), 2);
      controller.panBy(20, 40);
      controller.setPlayerSample(GamePoint(8, 24), forwardX: 1, forwardZ: 1);
      expect(controller.playerSceneDirection!.x, closeTo(1, 1e-9));
      expect(controller.playerSceneDirection!.y, closeTo(-1, 1e-9));
      final scale = controller.transform.scale;
      controller.centerOnPlayer();
      expect(controller.transform.scale, scale);
      expect(controller.playerViewportPoint!.x, closeTo(160, 1e-9));
      expect(controller.playerViewportPoint!.y, closeTo(160, 1e-9));
      controller.toggleFloor('Upper');
      controller.setSearch('test');
      controller.setCategoryVisibility({'Switches': false});
      controller.updateViewport(const Size(400, 300));
      expect(controller.contentGeneration, generation);
      await _settled(controller);
      var changes = 0;
      controller.addListener(() => changes++);
      controller.setPlayerSample(GamePoint(8, 24), forwardX: 1, forwardZ: 1);
      controller.setRaidHighlights({});
      expect(changes, 0);
      await controller.selectPersistedMap('icebreaker');
      expect(controller.contentGeneration, generation + 1);
      expect(controller.playerPosition, isNull);
    },
  );

  test(
    'quarter-turn map projects game forward X upward without glyph offsets',
    () async {
      final controller = _controller(rotation: 90);
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      controller.setPlayerSample(GamePoint(16, 16), forwardX: 1, forwardZ: 0);
      expect(controller.playerSceneDirection!.x, closeTo(0, 1e-9));
      expect(controller.playerSceneDirection!.y, closeTo(-1, 1e-9));
    },
  );

  test(
    'manual floors disable follow until explicit reenable; unknown is not zero',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'icebreaker');
      controller.setPlayerSample(GamePoint(8, 24, height: 3));
      expect(controller.floorSelection!.selectedOverlayIds, {'Upper'});
      controller.toggleFloor('Upper');
      expect(controller.automaticFloorFollowing, isFalse);
      controller.setPlayerSample(GamePoint(9, 24, height: 4));
      expect(controller.floorSelection!.selectedOverlayIds, isEmpty);
      controller.setAutomaticFloorFollowing(true);
      expect(controller.floorSelection!.selectedOverlayIds, {'Upper'});
      controller.setPlayerSample(GamePoint(10, 24));
      expect(controller.floorSelection!.selectedOverlayIds, {'Upper'});
      controller.setPlayerSample(GamePoint(10, 24, height: 0));
      expect(controller.floorSelection!.selectedOverlayIds, isEmpty);
      await controller.selectPersistedMap('interchange');
      expect(controller.automaticFloorSupported, isFalse);
    },
  );

  test('new pin intents reject artwork padding without altering old pin projection', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.updateViewport(const Size(320, 320));
    await controller.initialize(selectedMapId: 'interchange');
    expect(controller.pinCreationAt(ViewportPoint(0, 0)), isNull);
    final pin = controller.pinCreationAt(ViewportPoint(160, 160))!;
    expect(pin.mapId, 'interchange');
    expect(pin.point.x, closeTo(.5, 1e-9));
    expect(pin.point.y, closeTo(.5, 1e-9));
    expect(pin.frame.revision, 0);
    expect(controller.pinAt(ViewportPoint(0, 0)), isNotNull);
  });

  test('viewport framing: untouched maps refit after resize', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.updateViewport(const Size(320, 320));
    await controller.initialize(selectedMapId: 'interchange');
    controller.updateViewport(const Size(640, 480));
    await _settled(controller);
    final topLeft = controller.transform.sceneToViewport(ScenePoint(0, 0));
    final bottomRight = controller.transform.sceneToViewport(
      ScenePoint(32, 32),
    );
    expect(topLeft.x, closeTo(104, 1e-9));
    expect(topLeft.y, closeTo(24, 1e-9));
    expect(bottomRight.x, closeTo(536, 1e-9));
    expect(bottomRight.y, closeTo(456, 1e-9));
    final marker = controller.visibleMarkers().single;
    expect(marker.viewportPoint.x, closeTo(212, 1e-9));
    expect(marker.viewportPoint.y, closeTo(132, 1e-9));
    expect(
      controller.hitTestMarker(ViewportPoint(212, 132))!.marker.id,
      'unknown',
    );
    expect(controller.hitTestMarker(ViewportPoint(92, 92)), isNull);
  });

  test(
    'viewport framing: untouched revisited maps fit the current viewport',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      await controller.selectPersistedMap('icebreaker');
      controller.updateViewport(const Size(640, 480));
      await _settled(controller);
      await controller.selectPersistedMap('interchange');
      final center = controller.transform.sceneToViewport(ScenePoint(16, 16));
      final bottomRight = controller.transform.sceneToViewport(
        ScenePoint(32, 32),
      );
      expect(center.x, closeTo(320, 1e-9));
      expect(center.y, closeTo(240, 1e-9));
      expect(bottomRight.x, closeTo(536, 1e-9));
      expect(bottomRight.y, closeTo(456, 1e-9));
    },
  );

  test(
    'viewport framing: Fit map restores automatic fitting after a gesture',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      controller.panBy(37, -12);
      controller.zoomAt(ViewportPoint(120, 100), 1.5);
      controller.fit();
      controller.updateViewport(const Size(640, 480));
      await _settled(controller);
      final center = controller.transform.sceneToViewport(ScenePoint(16, 16));
      final bottomRight = controller.transform.sceneToViewport(
        ScenePoint(32, 32),
      );
      expect(center.x, closeTo(320, 1e-9));
      expect(center.y, closeTo(240, 1e-9));
      expect(bottomRight.x, closeTo(536, 1e-9));
      expect(bottomRight.y, closeTo(456, 1e-9));
    },
  );

  for (final gesture in ['pan', 'zoom']) {
    test(
      'viewport framing: deliberate $gesture survives resize and revisit',
      () async {
        final controller = _controller();
        addTearDown(controller.dispose);
        controller.updateViewport(const Size(320, 320));
        await controller.initialize(selectedMapId: 'interchange');
        if (gesture == 'pan') {
          controller.panBy(37, -12);
        } else {
          controller.zoomAt(ViewportPoint(120, 100), 1.5);
        }
        final before = controller.transform;
        controller.updateViewport(const Size(640, 480));
        await _settled(controller);
        expect(controller.transform.scale, before.scale);
        expect(controller.transform.translationX, before.translationX);
        expect(controller.transform.translationY, before.translationY);
        await controller.selectPersistedMap('icebreaker');
        controller.updateViewport(const Size(800, 600));
        await _settled(controller);
        await controller.selectPersistedMap('interchange');
        expect(controller.transform.scale, before.scale);
        expect(controller.transform.translationX, before.translationX);
        expect(controller.transform.translationY, before.translationY);
      },
    );
  }

  test('late A cannot publish after authoritative B selection', () async {
    final entered = Completer<void>();
    final lateA = Completer<ByteData>();
    final controller = _controller(
      artwork: (path) async {
        if (path.endsWith('interchange-base.vec')) {
          if (!entered.isCompleted) entered.complete();
          return lateA.future;
        }
        return _picture();
      },
    );
    addTearDown(controller.dispose);
    controller.updateViewport(const Size(320, 320));
    final initial = controller.initialize(selectedMapId: 'interchange');
    await entered.future;
    await controller.selectPersistedMap('icebreaker');
    expect(controller.selectedMapId, 'icebreaker');
    expect(controller.scene!.map.id, 'icebreaker');
    lateA.complete(_picture());
    await initial;
    expect(controller.scene!.map.id, 'icebreaker');
    expect(controller.resources.retainedResourceCount, 1);
    expect(controller.loading, isFalse);
  });

  test(
    'hidden floor art and marker hits disappear before late decode returns',
    () async {
      final entered = Completer<void>();
      final lateUpper = Completer<ByteData>();
      final controller = _controller(
        artwork: (path) async {
          if (path.endsWith('interchange-upper.vec')) {
            if (!entered.isCompleted) entered.complete();
            return lateUpper.future;
          }
          return _picture();
        },
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      expect(controller.visibleMarkers().map((m) => m.marker.id), ['unknown']);
      controller.toggleFloor('Upper');
      await entered.future;
      final upperPoint = controller
          .visibleMarkers()
          .singleWhere((m) => m.marker.id == 'upper')
          .viewportPoint;
      expect(controller.hitTestMarker(upperPoint)!.marker.id, 'upper');
      controller.toggleFloor('Upper');
      expect(
        controller.visibleMarkers().any((m) => m.marker.id == 'upper'),
        isFalse,
      );
      expect(controller.hitTestMarker(upperPoint), isNull);
      await _settled(controller);
      lateUpper.complete(_picture());
      await Future<void>.delayed(Duration.zero);
      expect(controller.floorSelection!.selectedOverlayIds, isEmpty);
      expect(controller.scene!.selection.selectedOverlayIds, isEmpty);
    },
  );

  test(
    'dispose fences late completion and emits no shutdown notification',
    () async {
      final entered = Completer<void>();
      final gate = Completer<ByteData>();
      final controller = _controller(
        artwork: (_) {
          if (!entered.isCompleted) entered.complete();
          return gate.future;
        },
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.updateViewport(const Size(320, 320));
      final initial = controller.initialize(selectedMapId: 'interchange');
      await entered.future;
      final beforeDispose = notifications;
      controller.dispose();
      gate.complete(_picture());
      await initial;
      expect(notifications, beforeDispose);
      expect(controller.scene, isNull);
      expect(controller.resources.accountedBytes, 0);
      expect(controller.resources.retainedResourceCount, 0);
    },
  );

  test(
    'failed new map cannot display previous-good art under its identity',
    () async {
      final controller = _controller(
        artwork: (path) async => path.contains('icebreaker')
            ? ByteData.sublistView(Uint8List.fromList([1, 2, 3]))
            : _picture(),
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final previous = controller.scene!;
      final switching = controller.selectPersistedMap('icebreaker');
      expect(controller.scene, isNull);
      expect(previous.isDisposed, isTrue);
      await switching;
      expect(controller.selectedMapId, 'icebreaker');
      expect(controller.preparedMap!.id, 'icebreaker');
      expect(controller.scene, isNull);
      expect(controller.error, isNotNull);
    },
  );

  test(
    'unbundled selection is honest and per-map transforms survive revisits',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      controller.panBy(37, -12);
      controller.zoomAt(ViewportPoint(120, 100), 1.5);
      final view = controller.transform;
      await controller.selectPersistedMap('icebreaker');
      await controller.selectPersistedMap('interchange');
      expect(controller.transform.scale, view.scale);
      expect(controller.transform.translationX, view.translationX);
      expect(controller.transform.translationY, view.translationY);
      // A complete pack carries every supported map, so the unbundled case is
      // an id the pack does not list.
      await controller.selectPersistedMap('retired-map');
      expect(controller.selectedMapId, 'retired-map');
      expect(controller.unavailable, isTrue);
      expect(controller.preparedMap, isNull);
      expect(controller.scene, isNull);
      expect(controller.visibleMarkers(), isEmpty);
    },
  );

  test('topmost equal-distance badge wins while nearest and inclusive radius remain', () async {
    final coincident = _controller(
      markers: [
        _marker(
          'generic-scav',
          'spawns',
          16,
          16,
          details: {
            'sides': ['scav'],
          },
        ),
        _marker(
          'named-boss',
          'bosses',
          16,
          16,
          details: {'mob': 'bossTagilla'},
        ),
      ],
    );
    addTearDown(coincident.dispose);
    coincident.updateViewport(const Size(320, 320));
    await coincident.initialize(selectedMapId: 'interchange');
    final coincidentPoint = coincident.visibleMarkers().first.viewportPoint;
    expect(coincident.hitTestMarker(coincidentPoint)!.marker.id, 'named-boss');

    final tied = _controller(
      markers: [
        _marker('left-switch', 'switches', 8, 16),
        _marker('right-extract', 'extracts', 24, 16),
      ],
    );
    addTearDown(tied.dispose);
    tied.updateViewport(const Size(320, 320));
    await tied.initialize(selectedMapId: 'interchange');
    final tiedMarkers = tied.visibleMarkers();
    final tiePoint = ViewportPoint(
      (tiedMarkers[0].viewportPoint.x + tiedMarkers[1].viewportPoint.x) / 2,
      (tiedMarkers[0].viewportPoint.y + tiedMarkers[1].viewportPoint.y) / 2,
    );
    expect(
      tied.hitTestMarker(tiePoint, radius: 100)!.marker.id,
      'right-extract',
    );

    final ordered = _controller(
      markers: [
        _marker('closer', 'switches', 16, 16),
        _marker('later-but-farther', 'extracts', 17, 16),
      ],
    );
    addTearDown(ordered.dispose);
    ordered.updateViewport(const Size(320, 320));
    await ordered.initialize(selectedMapId: 'interchange');
    final orderedMarkers = ordered.visibleMarkers();
    final anchor = orderedMarkers.first.viewportPoint;
    expect(
      ordered
          .hitTestMarker(ViewportPoint(anchor.x + 3, anchor.y), radius: 18)!
          .marker
          .id,
      'closer',
    );
    final boundary = _controller(
      markers: [_marker('boundary', 'switches', 16, 16)],
    );
    addTearDown(boundary.dispose);
    boundary.updateViewport(const Size(320, 320));
    await boundary.initialize(selectedMapId: 'interchange');
    final boundaryPoint = boundary.visibleMarkers().single.viewportPoint;
    expect(
      boundary
          .hitTestMarker(
            ViewportPoint(boundaryPoint.x + 18, boundaryPoint.y),
            radius: 18,
          )!
          .marker
          .id,
      'boundary',
    );
    expect(
      boundary.hitTestMarker(
        ViewportPoint(boundaryPoint.x + 18.01, boundaryPoint.y),
        radius: 18,
      ),
      isNull,
    );
    ordered.setCategoryVisibility({'Extracts': false});
    expect(
      ordered
          .hitTestMarker(ViewportPoint(anchor.x + 3, anchor.y), radius: 18)!
          .marker
          .id,
      'closer',
    );
  });

  test(
    'category/floor query and hit logic share cached viewport projections',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final first = controller.visibleMarkers();
      expect(identical(first, controller.visibleMarkers()), isTrue);
      expect(first.single.marker.position.height, isNull);
      expect(
        controller.hitTestMarker(first.single.viewportPoint)!.marker.id,
        'unknown',
      );
      controller.setCategoryVisibility({'Switches': false});
      expect(controller.visibleMarkers(), isEmpty);
      expect(controller.hitTestMarker(first.single.viewportPoint), isNull);
      controller.setCategoryVisibility({});
      final anchor = controller.visibleMarkers().single.viewportPoint;
      controller.zoomAt(anchor, 2);
      final zoomed = controller.visibleMarkers().single.viewportPoint;
      expect(zoomed.x, closeTo(anchor.x, 1e-9));
      expect(zoomed.y, closeTo(anchor.y, 1e-9));
      expect(
        controller
            .hitTestMarker(ViewportPoint(anchor.x + 17, anchor.y))!
            .marker
            .id,
        'unknown',
      );
      expect(
        controller.hitTestMarker(ViewportPoint(anchor.x + 19, anchor.y)),
        isNull,
      );
      expect(controller.applyOfflineHeight(4), isFalse);
      expect(controller.floorSelection!.selectedOverlayIds, isEmpty);
      await controller.selectPersistedMap('icebreaker');
      expect(controller.applyOfflineHeight(null), isFalse);
      expect(controller.applyOfflineHeight(3), isTrue);
      expect(controller.floorSelection!.selectedOverlayIds, {'Upper'});
      expect(controller.applyOfflineHeight(5), isTrue);
      expect(controller.floorSelection!.selectedOverlayIds, isEmpty);
    },
  );

  test(
    'finite pins with overflowing projections are skipped unchanged',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      // 1e308 overflows the legacy inverse; 1e306 reaches viewport scaling.
      for (final magnitude in [1e308, 1e306]) {
        for (final coordinate in [magnitude, -magnitude]) {
          for (final xAxis in [true, false]) {
            final pin = CustomPin(
              id: 'overflow',
              mapId: 'interchange',
              x: xAxis ? coordinate : .5,
              y: xAxis ? .5 : coordinate,
              frame: 'legacy-normalized',
              frameRevision: 0,
              label: 'Still editable',
              updatedAt: DateTime.utc(2026),
            );
            pin.validate();
            expect(controller.projectPin(pin), isNull);
            expect(pin.x, xAxis ? coordinate : .5);
            expect(pin.y, xAxis ? .5 : coordinate);
            expect(pin.frame, 'legacy-normalized');
            expect(pin.frameRevision, 0);
          }
        }
      }
    },
  );

  test(
    'legacy off-map pins round trip without frame conversion or clamping',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final pin = CustomPin(
        id: 'off-map',
        mapId: 'interchange',
        x: -.2,
        y: 1.5,
        frame: 'legacy-normalized',
        frameRevision: 0,
        label: 'Off map',
        updatedAt: DateTime.utc(2026),
      );
      final projected = controller.projectPin(pin)!;
      expect(projected.x, closeTo(-30.4, 1e-9));
      expect(projected.y, closeTo(-112, 1e-9));
      final stored = controller.pinAt(projected)!;
      expect(stored.point.x, closeTo(-.2, 1e-9));
      expect(stored.point.y, closeTo(1.5, 1e-9));
      expect(stored.frame, MapCoordinateFrame.legacyNormalized);
      controller.panBy(10, 20);
      final moved = controller.projectPin(pin)!;
      expect(moved.x, closeTo(projected.x + 10, 1e-9));
      expect(moved.y, closeTo(projected.y + 20, 1e-9));
      expect(pin.x, -.2);
      expect(pin.y, 1.5);
      expect(pin.frameRevision, 0);
    },
  );

  test('unsupported pack format surfaces as the map load error', () async {
    final manifest = preparedPackManifest()..['vectorCodecFormat'] = 2;
    final controller = _controllerFor(preparedPackBytes(manifest));
    addTearDown(controller.dispose);
    await controller.initialize(selectedMapId: 'interchange');
    expect(
      controller.error,
      contains(unsupportedVectorFormatMessage(2, preparedVectorCodecFormat)),
    );
    expect(controller.preparedMap, isNull);
  });

  test('broken active pack surfaces as the map load error', () async {
    final controller = _controllerFor((path) async {
      if (path.endsWith('active.json')) {
        return preparedJsonBytes({
          'schemaVersion': 1,
          'version': 'broken',
          'manifest': 'versions/broken/manifest.json',
        });
      }
      return ByteData.sublistView(Uint8List.fromList(utf8.encode('{')));
    });
    addTearDown(controller.dispose);
    await controller.initialize(selectedMapId: 'interchange');
    expect(controller.error, startsWith('Map list could not be opened: '));
    expect(controller.preparedMap, isNull);
  });

  group('outline hits follow outline visibility', () {
    late MapController controller;
    late ViewportPoint insideExtract;
    late ViewportPoint insideHazard;

    setUp(() async {
      controller = _controller(
        markers: [
          _marker(
            'gate',
            'extracts',
            4,
            4,
            name: 'Gate',
            details: {'faction': 'pmc'},
            outline: _square(2, 14),
          ),
          _marker(
            'minefield',
            'hazards',
            28,
            28,
            name: 'Minefield',
            outline: _square(18, 30),
          ),
        ],
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      insideExtract = controller.transform.sceneToViewport(ScenePoint(12, 20));
      insideHazard = controller.transform.sceneToViewport(ScenePoint(20, 12));
    });

    test('a hidden extract outline is not hit', () {
      expect(controller.hitTestMarker(insideExtract, radius: 1), isNull);
      expect(
        controller
            .hitTestMarker(insideExtract, radius: 1, hoveredMarkerId: 'gate')!
            .marker
            .id,
        'gate',
      );
      controller.setSelectedMarker('gate');
      expect(
        controller.hitTestMarker(insideExtract, radius: 1)!.marker.id,
        'gate',
      );
    });

    test(
      'a hovered extract keeps its hit over an overlapping hazard',
      () async {
        final overlap = _controller(
          markers: [
            _marker(
              'gate',
              'extracts',
              4,
              4,
              name: 'Gate',
              details: {'faction': 'pmc'},
              outline: _square(2, 14),
            ),
            _marker(
              'minefield',
              'hazards',
              18,
              18,
              name: 'Minefield',
              outline: _square(8, 20),
            ),
          ],
        );
        addTearDown(overlap.dispose);
        overlap.updateViewport(const Size(320, 320));
        await overlap.initialize(selectedMapId: 'interchange');
        final both = overlap.transform.sceneToViewport(ScenePoint(11, 21));

        // Hover and click both pass the hovered id, so a click inside the
        // highlighted extract selects the extract, not the zone on top.
        expect(
          overlap
              .hitTestMarker(both, radius: 1, hoveredMarkerId: 'gate')!
              .marker
              .id,
          'gate',
        );
        expect(
          overlap.hitTestMarker(both, radius: 1)!.marker.id,
          'minefield',
          reason: 'nothing hovered: the topmost drawn outline',
        );
      },
    );

    test('a hazard outline is still hit', () {
      expect(
        controller.hitTestMarker(insideHazard, radius: 1)!.marker.id,
        'minefield',
      );
    });
  });
}

LiveMapSnapshot _snapshot(
  MapController controller,
  Map<String, List<Map<String, Object?>>> inventory,
) {
  final completeInventory = <String, List<Map<String, Object?>>>{
    for (final map in controller.maps)
      map.id:
          inventory[map.id] ??
          [
            for (final marker in map.markers)
              {
                'id': marker.id,
                'category': marker.category,
                'filterKey': marker.filterKey,
                'name': marker.name,
                'position': {
                  'x': marker.position.x,
                  'z': marker.position.z,
                  'height': marker.position.height,
                },
                'floorId': marker.floorId,
                'heightBand': marker.heightBand == null
                    ? null
                    : [marker.heightBand!.min, marker.heightBand!.max],
                'details': marker.details,
                'source': marker.source,
                'outline': [
                  for (final point in marker.outline)
                    {'x': point.x, 'z': point.z, 'height': point.height},
                ],
              },
          ],
  };
  final pack = PreparedMapPack(
    version: 'test',
    assetRoot: 'assets/maps',
    maps: controller.maps,
  );
  final markerMaps = <String, List<PreparedMarker>>{
    for (final entry in completeInventory.entries)
      entry.key: [
        for (final marker in entry.value)
          PreparedMarker.fromJson(Map<String, dynamic>.from(marker)),
      ],
  };
  final budget = LiveMapBudget();
  return LiveMapSnapshot(
    mode: GameMode.pvp,
    checkedAt: DateTime.utc(2026),
    normalizedPayload: LiveMapInventory.fromMarkers(
      maps: markerMaps,
      budget: budget,
    ).encode(budget: budget),
    sources: [
      for (final dataset in LiveMapSourceDataset.values)
        LiveMapSourceBody(
          dataset: dataset,
          bytes: Uint8List.fromList(utf8.encode('{}')),
        ),
    ],
    formatVersion: liveMapSnapshotFormatVersion,
    normalizerVersion: liveMapNormalizerVersion,
    compatibility: LiveMapCompatibility.fromPreparedPack(pack, const []),
  );
}

Map<String, Object?> _snapshotMarker({
  required String id,
  required String category,
  required String filterKey,
  required String name,
  required double x,
  required double z,
  Map<String, Object?> details = const {},
}) => {
  'id': id,
  'category': category,
  'filterKey': filterKey,
  'name': name,
  'position': {'x': x, 'z': z},
  'details': details,
  'source': {'mapId': 'interchange'},
  'outline': const [],
};

List<Map<String, dynamic>> _square(double from, double to) => [
  {'x': from, 'z': from, 'height': null},
  {'x': to, 'z': from, 'height': null},
  {'x': to, 'z': to, 'height': null},
  {'x': from, 'z': to, 'height': null},
];

MapController _controllerFor(Future<ByteData> Function(String) loadBytes) {
  final loader = PreparedMapPackLoader(loadBytes: loadBytes);
  return MapController(
    loader: loader,
    resources: NativeMapResourceOwner(loader),
  );
}

MapController _controller({
  Future<ByteData> Function(String)? artwork,
  List<Map<String, dynamic>>? markers,
  int rotation = 0,
}) {
  final loader = PreparedMapPackLoader(
    loadBytes: preparedPackBytes(
      preparedPackManifest(
        maps: [
          _map('interchange', markers: markers, rotation: rotation),
          _map('icebreaker', exclusive: true),
        ],
      ),
      other: (path) async => artwork == null ? _picture() : artwork(path),
    ),
  );
  return MapController(
    loader: loader,
    resources: NativeMapResourceOwner(loader),
  );
}

Map<String, dynamic> _map(
  String id, {
  bool exclusive = false,
  List<Map<String, dynamic>>? markers,
  int rotation = 0,
}) => {
  'id': id,
  'name': '$id fixture',
  'kind': 'vector',
  'geometry': {
    'rotation': rotation,
    'affine': [1, 0, 1, 32],
    'bounds': [
      [0, 0],
      [32, 32],
    ],
    'nativeZoom': null,
    'coordinateRevision': 0,
    'pinFrame': 'legacy-normalized',
    'projection': 'bounds-normalized',
  },
  'artworkFrame': {'width': 32, 'height': 32},
  'displayCrop': {'left': 0, 'top': 0, 'right': 32, 'bottom': 32},
  'layerOrder': ['Base', 'Upper'],
  'floors': [
    {
      'id': 'Base',
      'base': true,
      'manual': true,
      'exclusive': exclusive,
      'attachedIds': [],
      'artwork': {
        'components': [
          {
            'id': 'Base',
            'type': 'vector',
            'path': '$id-base.vec',
            'effects': [],
          },
        ],
      },
    },
    {
      'id': 'Upper',
      'base': false,
      'manual': true,
      'exclusive': exclusive,
      'attachedIds': [],
      'heightBand': [3, 5],
      'artwork': {
        'components': [
          {
            'id': 'Upper',
            'type': 'vector',
            'path': '$id-upper.vec',
            'effects': [],
          },
        ],
      },
    },
  ],
  'markers':
      markers ??
      [
        {
          'id': 'unknown',
          'category': 'switches',
          'name': 'Unknown height',
          'position': {'x': 8, 'z': 24, 'height': null},
          'details': {},
          'source': {'url': 'fixture'},
        },
        {
          'id': 'upper',
          'category': 'switches',
          'name': 'Explicit upper',
          'floorId': 'Upper',
          'position': {'x': 24, 'z': 8, 'height': 0},
          'details': {},
          'source': {'url': 'fixture'},
        },
      ],
  'attribution': {'author': 'Independent fixture'},
};
Map<String, dynamic> _marker(
  String id,
  String category,
  double x,
  double z, {
  String? name,
  String? filterKey,
  Map<String, dynamic> details = const {},
  List<Map<String, dynamic>> outline = const [],
}) => {
  'id': id,
  'category': category,
  'name': name ?? id,
  'filterKey': ?filterKey,
  'position': {'x': x, 'z': z, 'height': null},
  'details': {...details, if (outline.isNotEmpty) 'outline': outline},
  'outline': outline,
  'source': {'url': 'fixture'},
};

class _PeakTrackingLiveMapBudget extends LiveMapBudget {
  int peakMaterializedBytes = 0;

  @override
  void reserveMaterialized(int bytes) {
    super.reserveMaterialized(bytes);
    if (materializedBytes > peakMaterializedBytes) {
      peakMaterializedBytes = materializedBytes;
    }
  }
}

ByteData _picture() => ByteData.sublistView(
  compiler.encodeSvg(
    xml: '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" fill="#336699"/></svg>',
    debugName: 'independent-controller-fixture',
    enableClippingOptimizer: false,
    enableMaskingOptimizer: false,
    enableOverdrawOptimizer: false,
  ),
);
Future<void> _settled(MapController controller) async {
  if (!controller.loading) return;
  final completer = Completer<void>();
  void listener() {
    if (!controller.loading && !completer.isCompleted) completer.complete();
  }

  controller.addListener(listener);
  try {
    await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    controller.removeListener(listener);
  }
}
