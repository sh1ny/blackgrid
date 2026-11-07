@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/map_controller.dart';
import 'package:blackgrid/data/live_map_cache.dart';
import 'package:blackgrid/data/live_map_refresh.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/map_floors.dart';
import 'package:blackgrid/domain/map_geometry.dart';
import 'package:blackgrid/maps/live_map_budget.dart';
import 'package:blackgrid/maps/live_map_normalizer.dart';
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:blackgrid/maps/native_map_scene.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../data/support/reopenable_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('complete frozen runtime pipeline fits default budgets and preserves local facts', () async {
    final pointer = jsonDecode(
      await File('assets/maps/active.json').readAsString(),
    ) as Map<String, dynamic>;
    final version = pointer['version'] as String;
    final manifest = jsonDecode(
      await File('assets/maps/${pointer['manifest']}').readAsString(),
    ) as Map<String, dynamic>;
    final expectedMapIds = {
      for (final map in manifest['maps'] as List)
        (map as Map<String, dynamic>)['id'] as String,
    };
    final evidenceRoot = 'assets/maps/versions/$version/evidence';
    final sourceIndex = jsonDecode(
      await File('$evidenceRoot/sources.json').readAsString(),
    ) as Map<String, dynamic>;
    final sourceBodies = <Uri, Uint8List>{};
    for (final value in sourceIndex['sources'] as List<dynamic>) {
      final source = value as Map<String, dynamic>;
      final uri = Uri.parse(source['url'] as String);
      if (uri.host != 'json.tarkov.dev' || !uri.path.startsWith('/regular/')) {
        continue;
      }
      sourceBodies[uri] = await File('$evidenceRoot/${source['path']}')
          .readAsBytes();
    }
    final frozenSourceBytes = sourceBodies.values.fold<int>(
      0,
      (total, bytes) => total + bytes.length,
    );
    final expectedEndpoints = _regularEndpoints;
    expect(sourceBodies.keys.toSet(), expectedEndpoints);
    final bodies = _decodeSourceBodies(sourceBodies);

    final loader = _filePackLoader();
    final resources = _NoNativeSceneResourceOwner(loader);
    final maps = MapController(loader: loader, resources: resources);
    final database = await ReopenableDatabase.open();
    var store = LiveMapCacheStore(database: database.db);
    final client = _FrozenSourceClient(sourceBodies);
    var now = DateTime.utc(2026, 11, 6);
    final acquirer = LiveMapRefreshAcquirer(
      client: client,
      store: store,
      clock: () => now,
    );
    try {
      // This deliberately unbundled selection loads the full local pack and
      // marker inventory without requesting artwork or creating a native scene.
      maps.updateViewport(const Size(320, 320));
      await maps.initialize(selectedMapId: 'deliberately-unbundled');
      final pack = maps.pack;
      expect(pack, isNotNull);
      expect(pack!.version, version);
      expect(pack.maps.length, expectedMapIds.length);
      expect(expectedMapIds.every(pack.byId.containsKey), isTrue);

      final expectedFacts = normalizeLiveMapData(
        sources: bodies,
        bindings: pack.liveMapBindings,
        mode: 'regular',
      );
      final expectedMarkerFacts = _expectedMarkerFacts(expectedFacts);

      final expectedMarkerCount = expectedFacts.values.fold<int>(
        0,
        (total, markers) => total + markers.length,
      );
      final budgetEvidence = <String, Map<String, int>>{};
      final fallbackBudget = LiveMapBudget();
      final activateFallback = maps.prepareMarkerInventory(
        null,
        budget: fallbackBudget,
      );
      budgetEvidence['initial bundled fallback preparation'] = {
        'after prepareMarkerInventory': fallbackBudget.materializedBytes,
      };
      expect(activateFallback(), isFalse);
      final startedAt = now;
      bool Function()? activate;
      final first = await acquirer.refresh(
        mode: GameMode.pvp,
        intent: LiveMapRefreshIntent(
          startedAt: startedAt,
          isCurrent: () => true,
        ),
        pack: pack,
        bindings: pack.liveMapBindings,
        beforeCommit: (candidate, budget) {
          final beforePreparation = budget.materializedBytes;
          activate = maps.prepareMarkerInventory(candidate, budget: budget);
          budgetEvidence['first beforeCommit'] = {
            'before prepareMarkerInventory': beforePreparation,
            'after prepareMarkerInventory': budget.materializedBytes,
          };
        },
      );
      expect(activate, isNotNull);
      activate!();
      expect(maps.selectedMapId, 'deliberately-unbundled');
      final firstPublishedFacts = await _publishedMarkerFacts(
        maps,
        expectedMapIds,
      );
      expect(firstPublishedFacts, equals(expectedMarkerFacts));
      await maps.selectPersistedMap('deliberately-unbundled');
      expect(maps.selectedMapId, 'deliberately-unbundled');
      expect(client.phaseRequests, 6);
      expect(client.conditionalRequests, 0);
      expect(_sourceProofs(first), equals(_frozenSourceProofs(sourceBodies)));

      client.phase = 1;
      now = now.add(const Duration(days: 1));
      activate = null;
      final checked = await acquirer.refresh(
        mode: GameMode.pvp,
        intent: LiveMapRefreshIntent(startedAt: now, isCurrent: () => true),
        pack: pack,
        bindings: pack.liveMapBindings,
        beforeCommit: (candidate, budget) {
          final beforePreparation = budget.materializedBytes;
          activate = maps.prepareMarkerInventory(candidate, budget: budget);
          budgetEvidence['304 beforeCommit'] = {
            'before prepareMarkerInventory': beforePreparation,
            'after prepareMarkerInventory': budget.materializedBytes,
          };
        },
      );
      expect(activate, isNotNull);
      expect(activate!(), isFalse);
      expect(client.phaseRequests, 12);
      expect(maps.selectedMapId, 'deliberately-unbundled');
      expect(client.conditionalRequests, 6);
      expect(checked.checkedAt, now);
      expect(_sourceProofs(checked), equals(_sourceProofs(first)));
      expect(checked.normalizedPayload, orderedEquals(first.normalizedPayload));
      final checkedPublishedFacts = await _publishedMarkerFacts(
        maps,
        expectedMapIds,
      );
      expect(checkedPublishedFacts, equals(expectedMarkerFacts));
      await maps.selectPersistedMap('deliberately-unbundled');
      expect(maps.selectedMapId, 'deliberately-unbundled');
      final persisted = await store.read(
        GameMode.pvp,
        compatibility: checked.compatibility,
      );
      expect(persisted, isNotNull);
      expect(persisted!.checkedAt, checked.checkedAt);
      expect(
        persisted.normalizedPayload,
        orderedEquals(first.normalizedPayload),
      );
      expect(_sourceProofs(persisted), equals(_sourceProofs(checked)));

      final reopened = await database.reopen();
      store = LiveMapCacheStore(database: reopened);
      final reloaded = await store.read(
        GameMode.pvp,
        compatibility: first.compatibility,
      );
      expect(reloaded, isNotNull);
      expect(reloaded!.mode, GameMode.pvp);
      expect(reloaded.checkedAt, checked.checkedAt);
      expect(
        reloaded.normalizedPayload,
        orderedEquals(first.normalizedPayload),
      );
      expect(_sourceProofs(reloaded), equals(_sourceProofs(checked)));

      final freshLoader = _filePackLoader();
      final freshResources = _NoNativeSceneResourceOwner(freshLoader);
      final freshMaps = MapController(
        loader: freshLoader,
        resources: freshResources,
      );
      var reloadedMarkerCount = 0;
      try {
        freshMaps.updateViewport(const Size(320, 320));
        await freshMaps.initialize(selectedMapId: 'deliberately-unbundled');
        final freshPack = freshMaps.pack;
        expect(freshPack, isNotNull);
        expect(freshPack!.version, version);
        expect(freshMaps.selectedMapId, 'deliberately-unbundled');
        expect(expectedMapIds.every(freshPack.byId.containsKey), isTrue);
        final defaultPublicationBudget = LiveMapBudget();
        final reloadedActivation = freshMaps.prepareMarkerInventory(
          reloaded,
          budget: defaultPublicationBudget,
        );
        budgetEvidence['reopen default-budget preparation'] = {
          'after prepareMarkerInventory':
              defaultPublicationBudget.materializedBytes,
        };
        reloadedActivation();
        expect(freshMaps.selectedMapId, 'deliberately-unbundled');
        final reloadedPublishedFacts = await _publishedMarkerFacts(
          freshMaps,
          expectedMapIds,
        );
        expect(reloadedPublishedFacts, equals(expectedMarkerFacts));
        reloadedMarkerCount = reloadedPublishedFacts.values.fold<int>(
          0,
          (total, markers) => total + markers.length,
        );
      } finally {
        freshMaps.dispose();
        freshResources.dispose();
      }
      expect(reloadedMarkerCount, expectedMarkerCount);
      expect(client.phaseRequests, 12);
      expect(
        client.requestCounts,
        equals({for (final endpoint in _regularEndpoints) endpoint: 2}),
      );
      expect(client.conditionalRequests, 6);
      // Qualification emits a durable resource/parity receipt for operators.
      // ignore: avoid_print
      print(
        jsonEncode({
          'actualFrozenSourceBytes': frozenSourceBytes,
          'compactNormalizedPayloadBytes': reloaded.normalizedPayload.length,
          'manifestDrivenMapCount': pack.maps.length,
          'logicalMarkerCount': reloadedMarkerCount,
          'logicalMarkerParity': true,
          'sixConditional304Reuse': client.conditionalRequests == 6,
          'compatibleCacheReopen': reloaded.mode == GameMode.pvp,
          'beforeCommitMaterializedBytesByStage': budgetEvidence,
        }),
      );
    } finally {
      client.close();
      maps.dispose();
      resources.dispose();
      await database.delete();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

PreparedMapPackLoader _filePackLoader() => PreparedMapPackLoader(
  loadBytes: (path) async =>
      ByteData.sublistView(await File(path).readAsBytes()),
);

Future<Map<String, List<Map<String, Object?>>>> _publishedMarkerFacts(
  MapController controller,
  Set<String> expectedMapIds,
) async {
  final mapIds = expectedMapIds.toList()..sort();
  final facts = <String, List<Map<String, Object?>>>{};
  final sourceTasksById = <String, Map<String, dynamic>>{};
  final sourceTaskMapIds = <String, Set<String>>{};
  for (final mapId in mapIds) {
    await controller.selectPersistedMap(mapId);
    expect(controller.preparedMap?.id, mapId);
    final activeMarkers = controller.activeMarkers;
    for (final marker in activeMarkers) {
      final sourceTask = marker.details['sourceTask'];
      if (sourceTask is Map<String, dynamic>) {
        final taskId = sourceTask['id'];
        if (taskId is String) {
          sourceTaskMapIds.putIfAbsent(taskId, () => <String>{}).add(mapId);
          final prior = sourceTasksById.putIfAbsent(taskId, () => sourceTask);
          expect(
            identical(prior, sourceTask),
            isTrue,
            reason:
                'All published markers for source task $taskId must share its facts.',
          );
        }
      }
    }
    final markers = [for (final marker in activeMarkers) _markerFacts(marker)]
      ..sort(
        (left, right) =>
            (left['id'] as String).compareTo(right['id'] as String),
      );
    facts[mapId] = markers;
  }
  expect(
    sourceTaskMapIds.values.any((ids) => ids.length > 1),
    isTrue,
    reason: 'The frozen inventory must exercise shared source-task facts across maps.',
  );
  return facts;
}

class _NoNativeSceneResourceOwner extends NativeMapResourceOwner {
  _NoNativeSceneResourceOwner(super.loader);

  @override
  Future<NativeMapScene?> loadScene(
    PreparedMap map,
    MapFloorSelection selection,
    MapViewTransform transform,
    Size viewportSize, {
    required bool Function() isCurrent,
  }) async {
    throw StateError(
      'This offline qualification must not decode artwork or create a native scene.',
    );
  }
}

const Map<LiveMapSourceDataset, String> _datasetPaths = {
  LiveMapSourceDataset.maps: 'maps',
  LiveMapSourceDataset.mapTranslations: 'maps_en',
  LiveMapSourceDataset.tasks: 'tasks',
  LiveMapSourceDataset.taskTranslations: 'tasks_en',
  LiveMapSourceDataset.traders: 'traders',
  LiveMapSourceDataset.traderTranslations: 'traders_en',
};

Set<Uri> get _regularEndpoints => {
  for (final path in _datasetPaths.values)
    Uri.https('json.tarkov.dev', '/regular/$path'),
};

Map<String, List<Map<String, Object?>>> _expectedMarkerFacts(
  Map<String, List<Map<String, Object?>>> facts,
) => {
  for (final entry in facts.entries)
    entry.key: [
      for (final marker
          in entry.value.map((raw) => PreparedMarker.fromJson(raw)).toList()
            ..sort((a, b) => a.id.compareTo(b.id)))
        _markerFacts(marker),
    ],
};

Map<String, Object?> _markerFacts(PreparedMarker marker) => {
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
  'details': marker.details,
  'source': marker.source,
  'outline': [
    for (final point in marker.outline)
      {'x': point.x, 'z': point.z, 'height': point.height},
  ],
  'heightBand': switch (marker.heightBand) {
    final band? => [band.min, band.max],
    null => null,
  },
};

LiveMapSourceBodies _decodeSourceBodies(Map<Uri, Uint8List> sourceBodies) {
  final decoded = <String, Map<String, dynamic>>{};
  for (final entry in _datasetPaths.entries) {
    final uri = Uri.https('json.tarkov.dev', '/regular/${entry.value}');
    final raw = jsonDecode(utf8.decode(sourceBodies[uri]!));
    if (raw is! Map<String, dynamic>) {
      throw FormatException('Frozen source $uri must have a JSON object root.');
    }
    decoded[entry.key.name] = raw;
  }
  return LiveMapSourceBodies(
    maps: decoded[LiveMapSourceDataset.maps.name]!,
    mapTranslations: decoded[LiveMapSourceDataset.mapTranslations.name]!,
    tasks: decoded[LiveMapSourceDataset.tasks.name]!,
    taskTranslations: decoded[LiveMapSourceDataset.taskTranslations.name]!,
    traders: decoded[LiveMapSourceDataset.traders.name]!,
    traderTranslations: decoded[LiveMapSourceDataset.traderTranslations.name]!,
  );
}

Map<LiveMapSourceDataset, (String, String?, String?)> _frozenSourceProofs(
  Map<Uri, Uint8List> bodies,
) => {
  for (final entry in _datasetPaths.entries)
    entry.key: (
      sha256
          .convert(
            bodies[Uri.https('json.tarkov.dev', '/regular/${entry.value}')]!,
          )
          .toString(),
      'frozen-${entry.key.name}',
      null,
    ),
};

Map<LiveMapSourceDataset, (String, String?, String?)> _sourceProofs(
  LiveMapSnapshot snapshot,
) => {
  for (final source in snapshot.sources)
    source.dataset: (source.sha256, source.etag, source.lastModified),
};

class _FrozenSourceClient extends http.BaseClient {
  _FrozenSourceClient(this.bodies);

  final Map<Uri, Uint8List> bodies;
  int phase = 0;
  int phaseRequests = 0;
  int conditionalRequests = 0;
  final requestCounts = <Uri, int>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET' || !_regularEndpoints.contains(request.url)) {
      throw StateError(
        'Unexpected offline qualification request: ${request.url}.',
      );
    }
    requestCounts.update(request.url, (count) => count + 1, ifAbsent: () => 1);
    final dataset = _datasetPaths.entries
        .singleWhere((entry) => request.url.path == '/regular/${entry.value}')
        .key;
    final expectedEtag = 'frozen-${dataset.name}';
    if (phase == 0) {
      if (request.headers.containsKey('if-none-match') ||
          request.headers.containsKey('if-modified-since')) {
        throw StateError(
          'The initial frozen request unexpectedly had validators.',
        );
      }
      phaseRequests++;
      final bytes = bodies[request.url];
      if (bytes == null) {
        throw StateError('No frozen source indexed for ${request.url}.');
      }
      return http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        200,
        contentLength: bytes.length,
        headers: {'content-type': 'application/json', 'etag': expectedEtag},
        request: request,
      );
    }
    if (phase != 1 || request.headers['if-none-match'] != expectedEtag) {
      throw StateError(
        'The conditional frozen request had unexpected validators for $dataset.',
      );
    }
    if (request.headers.containsKey('if-modified-since')) {
      throw StateError(
        'The conditional request sent an unexpected date validator.',
      );
    }
    phaseRequests++;
    conditionalRequests++;
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      304,
      request: request,
    );
  }
}
