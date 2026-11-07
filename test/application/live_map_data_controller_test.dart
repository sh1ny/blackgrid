import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:blackgrid/application/live_map_data_controller.dart';
import 'package:blackgrid/application/map_controller.dart';
import 'package:blackgrid/data/live_map_refresh.dart';
import 'package:blackgrid/data/live_map_cache.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/maps/live_map_budget.dart';
import 'package:blackgrid/maps/live_map_inventory.dart';
import 'package:blackgrid/maps/live_map_normalizer.dart';
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:blackgrid/maps/native_map_scene.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart'
    as compiler;

import '../data/support/reopenable_database.dart';

import '../../tool/maps/calibration.dart' show calibrationFor;
import '../support/prepared_pack_manifest.dart'
    show minimalPreparedMap, preparedPackBytes, preparedPackManifest;

final _oldCheck = DateTime.utc(2001, 1, 1);
final _now = DateTime.utc(2026, 11, 6, 12);
const _datasets = LiveMapSourceDataset.values;

Map<String, Object?> _emptySource(LiveMapSourceDataset dataset) =>
    switch (dataset) {
      LiveMapSourceDataset.maps => {
        'data': {'maps': <String, Object?>{}, 'mobs': <String, Object?>{}},
      },
      LiveMapSourceDataset.mapTranslations => {'data': <String, Object?>{}},
      LiveMapSourceDataset.tasks => {
        'data': {
          'tasks': <String, Object?>{},
          'questItems': <String, Object?>{},
        },
      },
      LiveMapSourceDataset.taskTranslations => {'data': <String, Object?>{}},
      LiveMapSourceDataset.traders => {'data': <String, Object?>{}},
      LiveMapSourceDataset.traderTranslations => {'data': <String, Object?>{}},
    };

Uint8List _jsonBytes(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));
Uint8List _compactPayload(Map<String, Object?> expanded) {
  final maps = <String, List<PreparedMarker>>{
    for (final entry in expanded.entries)
      entry.key: [
        for (final raw in entry.value as List)
          PreparedMarker.fromJson(Map<String, dynamic>.from(raw as Map)),
      ],
  };
  final budget = LiveMapBudget();
  return LiveMapInventory.fromMarkers(
    maps: maps,
    budget: budget,
  ).encode(budget: budget);
}

LiveMapSourceBody _source(
  LiveMapSourceDataset dataset, {
  Object? body,
  String? etag,
  String? lastModified,
}) => LiveMapSourceBody(
  dataset: dataset,
  bytes: _jsonBytes(body ?? _emptySource(dataset)),
  etag: etag,
  lastModified: lastModified,
);

LiveMapSnapshot _snapshot({
  required GameMode mode,
  required PreparedMapPack pack,
  required List<LiveMapBinding> bindings,
  required String markerId,
  DateTime? checkedAt,
}) => LiveMapSnapshot(
  mode: mode,
  checkedAt: checkedAt ?? _oldCheck,
  normalizedPayload: _compactPayload({
    for (final map in pack.maps)
      if (map.id != 'customs') map.id: const <Object?>[],
    'customs': [
      {
        'id': markerId,
        'category': 'switches',
        'filterKey': 'Switches',
        'name': markerId,
        'position': {'x': 10, 'z': 10, 'height': null},
        'details': <String, Object?>{},
        'source': {'mapId': 'customs'},
        'outline': <Object?>[],
      },
    ],
  }),
  sources: [for (final dataset in _datasets) _source(dataset)],
  formatVersion: liveMapSnapshotFormatVersion,
  normalizerVersion: liveMapNormalizerVersion,
  compatibility: LiveMapCompatibility.fromPreparedPack(pack, bindings),
);

final _customsPack = PreparedMapPack(
  version: 'lifecycle-customs',
  assetRoot: 'test',
  maps: [
    PreparedMap.fromJson(minimalPreparedMap('customs'), assetRoot: 'test'),
  ],
);
final _customsBindings = [
  LiveMapBinding(
    sourceKey: 'customs',
    mapId: 'customs',
    calibration: calibrationFor('customs'),
  ),
];

List<LiveMapBinding> _bindingsForPack(PreparedMapPack pack) => [
  for (final map in pack.maps)
    if (map.id == 'customs')
      _customsBindings.single
    else
      LiveMapBinding(
        sourceKey: map.id,
        mapId: map.id,
        calibration: {
          'sourceKey': map.id,
          'geometry': <String, Object?>{},
          'floors': <Object?>[],
        },
      ),
];

Map<String, Object?> _expandedSources(
  int positions, {
  String description = 'Inspect the shared nested location.',
  Map<String, Object?>? unknownTaskFact,
  int distinctZoneFactBytes = 0,
  bool geometrySentinel = false,
}) {
  final bodies = [for (final dataset in _datasets) _emptySource(dataset)];
  (bodies[0]['data']! as Map<String, Object?>)['maps'] = {
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
  };
  (bodies[1]['data']! as Map<String, Object?>)['customs'] = 'Customs';
  (bodies[2]['data']! as Map<String, Object?>)['tasks'] = {
    'task-1': {
      'id': 'task-1',
      'name': 'TASK_NAME',
      'trader': 'trader-1',
      'wikiLink': 'https://example.invalid/task',
      'unknownFutureFact': ?unknownTaskFact,
      if (geometrySentinel)
        'geometry': {
          'position': {'x': 987654321},
        },
      'objectives': [
        {
          'id': 'objective-1',
          'description': 'OBJECTIVE_DESCRIPTION',
          'zones': [
            for (var index = 0; index < positions; index++)
              {
                'id': 'zone-$index',
                'map': 'source-customs',
                'position': {'x': index, 'y': index + 1, 'z': index + 2},
                if (distinctZoneFactBytes > 0)
                  'unknownZoneFact':
                      'zone-$index-${List.filled(distinctZoneFactBytes, 'z').join()}',
              },
          ],
          'possibleLocations': <Object?>[],
        },
      ],
    },
  };
  (bodies[3]['data']! as Map<String, Object?>).addAll({
    'TASK_NAME': 'Synthetic task',
    'OBJECTIVE_DESCRIPTION': description,
  });
  (bodies[4]['data']! as Map<String, Object?>)['trader-1'] = {
    'id': 'trader-1',
    'name': 'TRADER_NAME',
  };
  (bodies[5]['data']! as Map<String, Object?>)['TRADER_NAME'] =
      'Synthetic trader';
  return {
    for (var index = 0; index < _datasets.length; index++)
      _datasets[index].name: bodies[index],
  };
}

LiveMapSourceDataset _datasetFor(http.BaseRequest request) =>
    switch (request.url.pathSegments.skip(1).join('/')) {
      'maps' => LiveMapSourceDataset.maps,
      'maps_en' => LiveMapSourceDataset.mapTranslations,
      'tasks' => LiveMapSourceDataset.tasks,
      'tasks_en' => LiveMapSourceDataset.taskTranslations,
      'traders' => LiveMapSourceDataset.traders,
      'traders_en' => LiveMapSourceDataset.traderTranslations,
      final path => throw StateError('Unexpected live-map dataset $path.'),
    };

GameMode _modeFor(http.BaseRequest request) =>
    switch (request.url.pathSegments.first) {
      'regular' => GameMode.pvp,
      'pve' => GameMode.pve,
      'pvp-season' => GameMode.seasonal,
      final route => throw StateError('Unexpected live-map route $route.'),
    };

class _RequestPlan {
  _RequestPlan(this.mode, this.dataset, this.controller, this.listened);

  final GameMode mode;
  final LiveMapSourceDataset dataset;
  final StreamController<List<int>> controller;
  final Completer<void> listened;
  bool cancelled = false;
}

/// Serves six-source fixtures and can hold response streams for explicit races.
class _ControlledClient extends http.BaseClient {
  _ControlledClient({
    this.holdMode,
    this.heldModes = const {},
    this.cancelGate,
    this.sourceBodies,
    this.failMode,
    this.failDataset,
  });

  final GameMode? holdMode;
  final Set<GameMode> heldModes;
  final Completer<void>? cancelGate;
  final Map<String, Object?>? sourceBodies;
  final GameMode? failMode;
  final LiveMapSourceDataset? failDataset;
  final requests = <http.BaseRequest>[];
  final plans = <_RequestPlan>[];
  final _requestWaiters = <({int count, Completer<void> signal})>[];
  final _releasedModes = <GameMode>{};
  final _cancelWaiters = <({int count, Completer<void> signal})>[];
  int closes = 0;

  Future<void> requestsStarted(int count) {
    if (requests.length >= count) return Future.value();
    final signal = Completer<void>();
    _requestWaiters.add((count: count, signal: signal));
    return signal.future;
  }

  Future<void> cancelledCount(int count) {
    if (plans.where((plan) => plan.cancelled).length >= count) {
      return Future.value();
    }
    final signal = Completer<void>();
    _cancelWaiters.add((count: count, signal: signal));
    return signal.future;
  }

  void answerMode(GameMode mode, {Map<String, Object?>? bodies}) {
    _releasedModes.add(mode);
    for (final plan in plans.where((plan) => plan.mode == mode)) {
      if (plan.cancelled) continue;
      final response =
          bodies?[plan.dataset.name] ??
          sourceBodies?[plan.dataset.name] ??
          _emptySource(plan.dataset);
      plan.controller
        ..add(_jsonBytes(response))
        ..close();
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    _requestWaiters.removeWhere((waiter) {
      if (requests.length < waiter.count) return false;
      waiter.signal.complete();
      return true;
    });
    final mode = _modeFor(request);
    final dataset = _datasetFor(request);
    final status = mode == failMode && dataset == failDataset ? 503 : 200;
    final listened = Completer<void>();
    late final _RequestPlan plan;
    final controller = StreamController<List<int>>(
      onListen: listened.complete,
      onCancel: () async {
        plan.cancelled = true;
        _cancelWaiters.removeWhere((waiter) {
          if (plans.where((value) => value.cancelled).length < waiter.count) {
            return false;
          }
          waiter.signal.complete();
          return true;
        });
        await cancelGate?.future;
      },
    );
    plan = _RequestPlan(mode, dataset, controller, listened);
    plans.add(plan);
    final response = http.StreamedResponse(controller.stream, status);
    if ((mode != holdMode && !heldModes.contains(mode)) ||
        _releasedModes.contains(mode) ||
        status != 200) {
      final body = sourceBodies?[dataset.name] ?? _emptySource(dataset);
      controller
        ..add(_jsonBytes(body))
        ..close();
    }
    return response;
  }

  @override
  void close() => closes++;
}

class _Store implements LiveMapStore {
  final snapshots = <GameMode, LiveMapSnapshot>{};
  final reads = <GameMode>[];
  final _readGates = <GameMode, Completer<void>>{};
  final _readReleases = <GameMode, Completer<void>>{};
  final commits = <LiveMapSnapshot>[];
  Completer<void>? commitGate;
  Completer<void>? commitStarted;
  Object? commitFailure;

  void holdRead(GameMode mode) {
    final gate = Completer<void>();
    _readGates[mode] = gate;
    _readReleases[mode] = gate;
  }

  void releaseRead(GameMode mode) => _readReleases.remove(mode)?.complete();

  @override
  Future<LiveMapSnapshot?> read(
    GameMode mode, {
    required LiveMapCompatibility compatibility,
    void Function(Object failure)? onRejected,
  }) async {
    reads.add(mode);
    final snapshot = snapshots[mode];
    await _readGates.remove(mode)?.future;
    return snapshot?.compatibility.fingerprint == compatibility.fingerprint
        ? snapshot
        : null;
  }

  @override
  Future<void> commit(LiveMapSnapshot snapshot, {LiveMapBudget? budget}) async {
    if (commitStarted case final started? when !started.isCompleted) {
      started.complete();
    }
    await commitGate?.future;
    if (commitFailure case final failure?) throw failure;
    snapshots[snapshot.mode] = snapshot;
    commits.add(snapshot);
  }
}

class _Clock {
  DateTime value = _now;
  DateTime call() => value;
}

class _ManualTimer implements Timer {
  _ManualTimer(this.callback);

  final void Function() callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }
}

class _ManualTimers {
  final timers = <_ManualTimer>[];

  Timer create(Duration duration, void Function() callback) {
    final timer = _ManualTimer(callback);
    timers.add(timer);
    return timer;
  }
}

class _Rig {
  _Rig({
    required this.client,
    required this.store,
    PreparedMapPack? pack,
    List<LiveMapBinding>? bindings,
    LiveMapRefreshLimits limits = const LiveMapRefreshLimits(),
    Timer Function(Duration, void Function())? createTimer,
  }) : pack = pack ?? _customsPack,
       bindings = bindings ?? _customsBindings {
    acquirer = LiveMapRefreshAcquirer(
      client: client,
      store: store,
      clock: clock.call,
      limits: limits,
    );
    controller = LiveMapDataController(
      store: store,
      acquirer: acquirer,
      clock: clock.call,
      createTimer: createTimer,
      preparePublication: (snapshot, budget) => () {
        publications.add(snapshot);
      },
    );
  }

  final _ControlledClient client;
  final _Store store;
  final PreparedMapPack pack;
  final List<LiveMapBinding> bindings;
  final _Clock clock = _Clock();
  bool _controllerDisposed = false;
  late final LiveMapRefreshAcquirer acquirer;
  late final LiveMapDataController controller;
  final publications = <LiveMapSnapshot?>[];

  Future<void> select(GameMode mode, {Object? packFailure}) =>
      controller.selectMode(
        mode: mode,
        pack: packFailure == null ? pack : null,
        bindings: bindings,
        packFailure: packFailure,
      );

  void disposeController() {
    if (_controllerDisposed) return;
    _controllerDisposed = true;
    controller.dispose();
  }

  Future<void> close() async {
    disposeController();
    await controller.close();
    for (final plan in List<_RequestPlan>.of(client.plans)) {
      if (!plan.cancelled && !plan.controller.isClosed) {
        await plan.controller.close();
      }
    }
  }
}

Future<void> _waitForState(
  LiveMapDataController controller,
  bool Function(dynamic state) matches,
) {
  if (matches(controller.state)) return Future<void>.value();
  final reached = Completer<void>();
  void listener() {
    if (!reached.isCompleted && matches(controller.state)) {
      reached.complete();
      controller.removeListener(listener);
    }
  }

  controller.addListener(listener);
  listener();
  return reached.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mode-scoped live map authority', () {
    test(
      'unknown mode uses regular bundle and makes no cache or HTTP request',
      () async {
        final client = _ControlledClient();
        final store = _Store();
        final rig = _Rig(client: client, store: store);
        addTearDown(rig.close);

        await rig.select(GameMode.unknown);

        expect(store.reads, isEmpty);
        expect(client.requests, isEmpty);
        expect(rig.controller.state.mode, GameMode.unknown);
        expect(rig.controller.state.dataMode, GameMode.pvp);
        expect(rig.controller.state.source, LiveMapDataSource.bundled);
        expect(rig.publications, [null]);
      },
    );

    test(
      'old compatible cache remains authoritative after refresh failure',
      () async {
        final old = _snapshot(
          mode: GameMode.pve,
          pack: _customsPack,
          bindings: _customsBindings,
          markerId: 'old-pve',
        );
        final client = _ControlledClient(
          failMode: GameMode.pve,
          failDataset: LiveMapSourceDataset.maps,
        );
        final store = _Store()..snapshots[GameMode.pve] = old;
        final rig = _Rig(client: client, store: store);
        addTearDown(rig.close);

        await rig.select(GameMode.pve);
        await client.requestsStarted(1);
        await _waitForState(
          rig.controller,
          (state) => state.failure != null && !state.refreshing,
        );

        expect(rig.controller.state.mode, GameMode.pve);
        expect(rig.controller.state.dataMode, GameMode.pve);
        expect(rig.controller.state.source, LiveMapDataSource.cached);
        expect(rig.controller.state.checkedAt, _oldCheck);
        expect(rig.controller.state.failure, isNotNull);
        expect(store.snapshots[GameMode.pve], same(old));
        expect(rig.publications.whereType<LiveMapSnapshot>().single, same(old));
      },
    );

    test(
      'rejected durable cache reports its diagnostic while refresh continues',
      () async {
        final database = await ReopenableDatabase.open();
        final cache = LiveMapCacheStore(database: database.db);
        await cache.commit(
          _snapshot(
            mode: GameMode.pve,
            pack: _customsPack,
            bindings: _customsBindings,
            markerId: 'corrupted-cache',
          ),
        );
        await database.writeRawRow(
          'UPDATE live_map_snapshots SET compatibility_fingerprint = ? '
          'WHERE mode = ?',
          ['corrupt-fingerprint', GameMode.pve.index],
        );
        final client = _ControlledClient(holdMode: GameMode.pve);
        final acquirer = LiveMapRefreshAcquirer(
          client: client,
          store: cache,
          clock: () => _now,
        );
        final publications = <LiveMapSnapshot?>[];
        final controller = LiveMapDataController(
          store: cache,
          acquirer: acquirer,
          clock: () => _now,
          preparePublication: (snapshot, budget) => () {
            publications.add(snapshot);
          },
        );
        addTearDown(() async {
          controller.dispose();
          await controller.close();
          for (final plan in List<_RequestPlan>.of(client.plans)) {
            if (!plan.cancelled && !plan.controller.isClosed) {
              await plan.controller.close();
            }
          }
          await database.delete();
        });

        await controller.selectMode(
          mode: GameMode.pve,
          pack: _customsPack,
          bindings: _customsBindings,
        );
        await client.requestsStarted(1);
        await _waitForState(controller, (state) => state.failure != null);

        expect(controller.state.source, LiveMapDataSource.bundled);
        expect(controller.state.failure, isA<FormatException>());
        expect(controller.state.refreshing, isTrue);
        expect(client.requests, hasLength(1));
        expect(publications.whereType<LiveMapSnapshot>(), isEmpty);
      },
    );

    test(
      'slow initial cache read remains authoritative after refresh failure',
      () async {
        final cached = _snapshot(
          mode: GameMode.pve,
          pack: _customsPack,
          bindings: _customsBindings,
          markerId: 'slow-cache',
          checkedAt: _oldCheck,
        );
        final client = _ControlledClient(
          failMode: GameMode.pve,
          failDataset: LiveMapSourceDataset.maps,
        );
        final store = _Store()
          ..snapshots[GameMode.pve] = cached
          ..holdRead(GameMode.pve);
        final rig = _Rig(client: client, store: store);
        addTearDown(rig.close);

        final selecting = rig.select(GameMode.pve);
        final failedRefresh = rig.controller.refresh();
        await failedRefresh;
        store.releaseRead(GameMode.pve);
        await selecting;

        expect(rig.controller.state.source, LiveMapDataSource.cached);
        expect(rig.controller.state.dataMode, GameMode.pve);
        expect(rig.controller.state.checkedAt, _oldCheck);
        expect(
          rig.publications.whereType<LiveMapSnapshot>().last,
          same(cached),
        );
      },
    );

    test('pve without cache shows labelled regular bundled fallback', () async {
      final client = _ControlledClient(
        failMode: GameMode.pve,
        failDataset: LiveMapSourceDataset.maps,
      );
      final store = _Store();
      final rig = _Rig(client: client, store: store);
      addTearDown(rig.close);

      await rig.select(GameMode.pve);
      expect(rig.controller.state.dataMode, GameMode.pvp);
      await client.requestsStarted(1);
      await _waitForState(
        rig.controller,
        (state) => state.failure != null && !state.refreshing,
      );

      expect(rig.controller.state.mode, GameMode.pve);
      expect(rig.controller.state.dataMode, GameMode.pvp);
      expect(rig.controller.state.source, LiveMapDataSource.bundled);
      expect(rig.controller.state.failure, isNotNull);
      expect(rig.publications, [null]);
    });

    test('cached metadata cannot hide active pack failure', () async {
      final cached = _snapshot(
        mode: GameMode.pve,
        pack: _customsPack,
        bindings: _customsBindings,
        markerId: 'cached-but-inactive',
      );
      final client = _ControlledClient();
      final store = _Store()..snapshots[GameMode.pve] = cached;
      final rig = _Rig(client: client, store: store);
      addTearDown(rig.close);

      await rig.select(
        GameMode.pve,
        packFailure: StateError('broken active pack'),
      );

      expect(store.reads, isEmpty);
      expect(client.requests, isEmpty);
      expect(rig.controller.state.source, LiveMapDataSource.unavailable);
      expect(rig.controller.state.failure, isNotNull);
    });

    test('each mode retains its own cache and check status', () async {
      final pvp = _snapshot(
        mode: GameMode.pvp,
        pack: _customsPack,
        bindings: _customsBindings,
        markerId: 'regular-facts',
        checkedAt: DateTime.utc(2024),
      );
      final pve = _snapshot(
        mode: GameMode.pve,
        pack: _customsPack,
        bindings: _customsBindings,
        markerId: 'pve-facts',
        checkedAt: DateTime.utc(2025),
      );
      final client = _ControlledClient(
        holdMode: GameMode.pvp,
        heldModes: {GameMode.pvp, GameMode.pve},
      );
      final store = _Store()
        ..snapshots[GameMode.pvp] = pvp
        ..snapshots[GameMode.pve] = pve;
      final rig = _Rig(client: client, store: store);
      addTearDown(rig.close);

      await rig.select(GameMode.pvp);
      await client.requestsStarted(1);
      expect(rig.controller.state.source, LiveMapDataSource.cached);
      expect(rig.controller.state.checkedAt, pvp.checkedAt);
      await rig.select(GameMode.pve);
      await client.cancelledCount(1);
      await client.requestsStarted(2);

      expect(rig.controller.state.mode, GameMode.pve);
      expect(rig.controller.state.dataMode, GameMode.pve);
      expect(rig.controller.state.source, LiveMapDataSource.cached);
      expect(rig.controller.state.checkedAt, pve.checkedAt);
      expect(rig.controller.state.failure, isNull);
      expect(rig.publications.last, same(pve));
    });

    test('startup selection returns while refresh is held and same-mode calls join', () async {
      final client = _ControlledClient(holdMode: GameMode.pvp);
      final store = _Store();
      final rig = _Rig(client: client, store: store);
      addTearDown(rig.close);

      await rig.select(GameMode.pvp);
      await client.requestsStarted(1);
      expect(rig.controller.state.refreshing, isTrue);
      final joinedA = rig.controller.refresh();
      final joinedB = rig.controller.refresh();
      expect(client.requests, hasLength(1));

      client.answerMode(GameMode.pvp);
      await Future.wait([joinedA, joinedB]);
      expect(store.commits, hasLength(1));
      expect(rig.controller.state.source, LiveMapDataSource.refreshed);
      expect(rig.controller.state.checkedAt, _now);
    });

    test(
      'superseded mode cancels response streams and cannot publish late',
      () async {
        final cancelGate = Completer<void>();
        final client = _ControlledClient(
          holdMode: GameMode.pvp,
          cancelGate: cancelGate,
        );
        final store = _Store();
        final rig = _Rig(client: client, store: store);
        addTearDown(() async {
          if (!cancelGate.isCompleted) cancelGate.complete();
          await rig.close();
        });

        await rig.select(GameMode.pvp);
        await client.requestsStarted(1);
        await rig.select(GameMode.pve);
        await client.cancelledCount(1);
        cancelGate.complete();
        await client.requestsStarted(2);
        await _waitForState(
          rig.controller,
          (state) =>
              state.source == LiveMapDataSource.refreshed && !state.refreshing,
        );

        expect(rig.controller.state.mode, GameMode.pve);
        expect(rig.controller.state.dataMode, GameMode.pve);
        expect(rig.controller.state.source, LiveMapDataSource.refreshed);
        expect(store.snapshots[GameMode.pvp], isNull);
        expect(
          rig.publications.whereType<LiveMapSnapshot>().map((s) => s.mode),
          [GameMode.pve],
        );
      },
    );

    test(
      'one active refresh keeps only the latest replaceable pending mode',
      () async {
        final cancelGate = Completer<void>();
        final client = _ControlledClient(
          holdMode: GameMode.pvp,
          cancelGate: cancelGate,
        );
        final store = _Store();
        final rig = _Rig(client: client, store: store);
        addTearDown(() async {
          if (!cancelGate.isCompleted) cancelGate.complete();
          await rig.close();
        });

        await rig.select(GameMode.pvp);
        await client.requestsStarted(1);
        await rig.select(GameMode.pve);
        await client.cancelledCount(1);
        await rig.select(GameMode.seasonal);
        cancelGate.complete();
        await client.requestsStarted(2);
        expect(client.requests.map(_modeFor).toSet(), {
          GameMode.pvp,
          GameMode.seasonal,
        });
        await rig.controller.refresh();

        expect(rig.controller.state.mode, GameMode.seasonal);
        expect(rig.controller.state.source, LiveMapDataSource.refreshed);
        expect(store.snapshots.containsKey(GameMode.pve), isFalse);
        expect(store.snapshots[GameMode.seasonal]?.mode, GameMode.seasonal);
      },
    );

    test('reselected mode refreshes after cancelled cleanup drains and manual calls join it', () async {
      final cancelGate = Completer<void>();
      final client = _ControlledClient(
        holdMode: GameMode.pvp,
        cancelGate: cancelGate,
      );
      final store = _Store();
      final rig = _Rig(client: client, store: store);
      addTearDown(() async {
        if (!cancelGate.isCompleted) cancelGate.complete();
        await rig.close();
      });

      await rig.select(GameMode.pvp);
      await client.requestsStarted(1);
      final cancelledJoin = rig.controller.refresh();
      await rig.select(GameMode.pve);
      await client.cancelledCount(1);
      await rig.select(GameMode.pvp);

      expect(rig.publications.whereType<LiveMapSnapshot>(), isEmpty);
      cancelGate.complete();
      await cancelledJoin;
      expect(rig.controller.state.refreshing, isTrue);
      await client.requestsStarted(2);

      final manualRefresh = rig.controller.refresh();
      expect(client.requests, hasLength(2));
      expect(rig.publications.whereType<LiveMapSnapshot>(), isEmpty);

      client.answerMode(GameMode.pvp);
      await manualRefresh;
      await _waitForState(
        rig.controller,
        (state) =>
            state.mode == GameMode.pvp &&
            state.source == LiveMapDataSource.refreshed &&
            !state.refreshing,
      );

      expect(client.requests, hasLength(7));
      expect(store.commits, hasLength(1));
      expect(
        rig.publications.whereType<LiveMapSnapshot>().map(
          (snapshot) => snapshot.mode,
        ),
        [GameMode.pvp],
      );
      expect(rig.controller.state.mode, GameMode.pvp);
      expect(rig.controller.state.source, LiveMapDataSource.refreshed);
    });

    test(
      'begun atomic commit drains without publishing after a mode fence',
      () async {
        final client = _ControlledClient();
        final store = _Store()
          ..commitGate = Completer<void>()
          ..commitStarted = Completer<void>();
        final rig = _Rig(client: client, store: store);
        addTearDown(rig.close);

        await rig.select(GameMode.pvp);
        await store.commitStarted!.future;
        await rig.select(GameMode.pve);
        expect(rig.controller.state.mode, GameMode.pve);
        expect(rig.publications.whereType<LiveMapSnapshot>(), isEmpty);
        store.commitGate!.complete();
        await client.requestsStarted(12);
        await _waitForState(
          rig.controller,
          (state) =>
              state.source == LiveMapDataSource.refreshed && !state.refreshing,
        );

        expect(store.snapshots[GameMode.pvp]?.mode, GameMode.pvp);
        expect(rig.controller.state.mode, GameMode.pve);
        expect(
          rig.publications.whereType<LiveMapSnapshot>().map((s) => s.mode),
          [GameMode.pve],
        );
      },
    );

    test(
      'expired pending refresh reports deadline while held commit drains',
      () async {
        final timers = _ManualTimers();
        final client = _ControlledClient();
        final store = _Store()
          ..commitGate = Completer<void>()
          ..commitStarted = Completer<void>();
        final rig = _Rig(
          client: client,
          store: store,
          limits: const LiveMapRefreshLimits(
            overallTimeout: Duration(seconds: 5),
          ),
          createTimer: timers.create,
        );
        addTearDown(rig.close);

        await rig.select(GameMode.pvp);
        await store.commitStarted!.future;
        await rig.select(GameMode.pve);

        expect(timers.timers, hasLength(2));
        rig.clock.value = _now.add(const Duration(seconds: 5));
        expect(
          client.requests.map(_modeFor).where((mode) => mode == GameMode.pve),
          isEmpty,
        );
        timers.timers.last.fire();

        expect(rig.controller.state.mode, GameMode.pve);
        expect(rig.controller.state.source, LiveMapDataSource.bundled);
        expect(
          rig.controller.state.failure,
          isA<LiveMapResourceLimitException>(),
        );
        expect(rig.controller.state.refreshing, isFalse);
        expect(
          client.requests.map(_modeFor).where((mode) => mode == GameMode.pve),
          isEmpty,
        );

        store.commitGate!.complete();
        await rig.close();
      },
    );

    test(
      'older cache read cannot replace a newer committed snapshot',
      () async {
        final stale = _snapshot(
          mode: GameMode.pve,
          pack: _customsPack,
          bindings: _customsBindings,
          markerId: 'stale-cache',
        );
        final client = _ControlledClient();
        final store = _Store()
          ..snapshots[GameMode.pve] = stale
          ..holdRead(GameMode.pve);
        final rig = _Rig(client: client, store: store);
        addTearDown(() {
          store.releaseRead(GameMode.pve);
          return rig.close();
        });

        final selecting = rig.select(GameMode.pve);
        final refreshing = rig.controller.refresh();
        await refreshing;
        final committed = store.snapshots[GameMode.pve]!;
        expect(committed, isNot(same(stale)));
        store.releaseRead(GameMode.pve);
        await selecting;

        expect(rig.controller.state.source, LiveMapDataSource.refreshed);
        expect(
          rig.publications.whereType<LiveMapSnapshot>().last,
          same(committed),
        );
      },
    );

    test(
      'dispose cancels active response streams before close completes',
      () async {
        final client = _ControlledClient(holdMode: GameMode.pvp);
        final store = _Store();
        final rig = _Rig(client: client, store: store);
        addTearDown(rig.close);
        var notifications = 0;
        rig.controller.addListener(() => notifications++);

        await rig.select(GameMode.pvp);
        await client.requestsStarted(1);
        final publicationBaseline = List<LiveMapSnapshot?>.of(rig.publications);
        final beforeDispose = notifications;
        rig.disposeController();
        final closing = rig.controller.close();
        await client.cancelledCount(1);
        await closing;

        expect(client.plans, hasLength(1));
        expect(client.plans.single.cancelled, isTrue);
        expect(rig.publications, publicationBaseline);
        expect(rig.publications.whereType<LiveMapSnapshot>(), isEmpty);
        expect(notifications, beforeDispose);
        expect(client.closes, 0);
      },
    );

    test(
      'close fences listeners and waits for an already-started transaction',
      () async {
        final client = _ControlledClient();
        final store = _Store()
          ..commitGate = Completer<void>()
          ..commitStarted = Completer<void>();
        final rig = _Rig(client: client, store: store);
        var notifications = 0;
        rig.controller.addListener(() => notifications++);
        await rig.select(GameMode.pvp);
        await store.commitStarted!.future;
        final publicationBaseline = List<LiveMapSnapshot?>.of(rig.publications);
        final beforeClose = notifications;

        rig.disposeController();
        final closing = rig.controller.close();
        store.commitGate!.complete();
        await closing;

        expect(store.snapshots[GameMode.pvp], isNotNull);
        expect(rig.publications, publicationBaseline);
        expect(rig.publications.whereType<LiveMapSnapshot>(), isEmpty);
        expect(notifications, beforeClose);
        expect(client.closes, 0);
      },
    );
  });

  group('expanded candidate authority through the real publisher', () {
    test(
      'publication materialization overflow rejects before durable commit',
      () async {
        await _exerciseExpandedCandidate(
          positions: 3,
          limits: LiveMapRefreshLimits(maxMaterializedBytes: 200 * 1024),
          expectFailure: true,
          activeMarkerCount: 500,
        );
      },
    );

    for (final (label, limits) in [
      (
        'materialized nested expansion overflow',
        LiveMapRefreshLimits(maxMaterializedBytes: 128 * 1024),
      ),
      (
        'serialized normalized output overflow',
        LiveMapRefreshLimits(maxSerializedBytes: 8 * 1024),
      ),
    ]) {
      test('$label preserves durable and active marker authority', () async {
        await _exerciseExpandedCandidate(
          positions: 24,
          limits: limits,
          expectFailure: true,
        );
      });
    }

    test(
      'held cache read cannot publish over a prepared refresh transaction',
      () async {
        final manifest = preparedPackManifest(
          maps: [minimalPreparedMap('customs')],
        );
        final loader = PreparedMapPackLoader(
          loadBytes: preparedPackBytes(
            manifest,
            other: (_) async => ByteData.sublistView(_picture()),
          ),
        );
        final maps = MapController(
          loader: loader,
          resources: NativeMapResourceOwner(loader),
        );
        await maps.initialize(selectedMapId: 'customs');
        final pack = maps.pack!;
        final bindings = _bindingsForPack(pack);
        final cached = _snapshot(
          mode: GameMode.pve,
          pack: pack,
          bindings: bindings,
          markerId: 'stale-cache',
        );
        final store = _Store()
          ..snapshots[GameMode.pve] = cached
          ..holdRead(GameMode.pve)
          ..commitGate = Completer<void>()
          ..commitStarted = Completer<void>();
        final client = _ControlledClient(sourceBodies: _expandedSources(3));
        final publications = <LiveMapSnapshot?>[];
        final acquirer = LiveMapRefreshAcquirer(
          client: client,
          store: store,
          clock: () => _now,
        );
        final controller = LiveMapDataController(
          store: store,
          acquirer: acquirer,
          clock: () => _now,
          preparePublication: (snapshot, budget) {
            final activate = maps.prepareMarkerInventory(
              snapshot,
              budget: budget,
            );
            return () {
              publications.add(snapshot);
              activate();
            };
          },
        );
        addTearDown(() async {
          await controller.close();
          maps.dispose();
        });

        final selecting = controller.selectMode(
          mode: GameMode.pve,
          pack: pack,
          bindings: bindings,
        );
        final refreshing = controller.refresh();
        await store.commitStarted!.future;

        expect(maps.activeMarkers, isEmpty);
        store.releaseRead(GameMode.pve);
        store.commitGate!.complete();
        await Future.wait([selecting, refreshing]);

        final committed = store.snapshots[GameMode.pve]!;
        expect(committed, isNot(same(cached)));
        expect(controller.state.source, LiveMapDataSource.refreshed);
        expect(maps.activeMarkers, isNotEmpty);
        expect(publications.whereType<LiveMapSnapshot>(), [committed]);
      },
    );

    test(
      'fitting nested candidate commits and publishes through MapController',
      () async {
        await _exerciseExpandedCandidate(
          positions: 3,
          limits: LiveMapRefreshLimits(),
          expectFailure: false,
        );
      },
    );

    test('shared searchable task fact publishes and searches within a compact budget', () async {
      await _exerciseExpandedCandidate(
        positions: 32,
        limits: LiveMapRefreshLimits(maxMaterializedBytes: 2 * 1024 * 1024),
        expectFailure: false,
        verifySharedFactSearch: true,
        geometrySentinel: true,
        unknownTaskFact: {
          'nested': {
            'needle': 'CompactTaskNeedle',
            'phraseParts': ['phrase', 'crossing', 'scalar', 'leaves'],
            'largePayload': List.filled(64 * 1024, 'q').join(),
          },
        },
      );
    });

    test(
      'distinct oversized search facts preserve prior authority before commit',
      () async {
        await _exerciseExpandedCandidate(
          positions: 32,
          limits: LiveMapRefreshLimits(maxMaterializedBytes: 2 * 1024 * 1024),
          expectFailure: true,
          distinctZoneFactBytes: 64 * 1024,
        );
      },
    );
  });
}

Future<void> _exerciseExpandedCandidate({
  required int positions,
  required LiveMapRefreshLimits limits,
  required bool expectFailure,
  int activeMarkerCount = 1,
  bool verifySharedFactSearch = false,
  bool geometrySentinel = false,
  Map<String, Object?>? unknownTaskFact,
  int distinctZoneFactBytes = 0,
}) async {
  final manifest = preparedPackManifest(maps: [minimalPreparedMap('customs')]);
  final loader = PreparedMapPackLoader(
    loadBytes: preparedPackBytes(
      manifest,
      other: (_) async => ByteData.sublistView(_picture()),
    ),
  );
  final maps = MapController(
    loader: loader,
    resources: NativeMapResourceOwner(loader),
  );
  maps.updateViewport(const Size(320, 320));
  await maps.initialize(selectedMapId: 'customs');
  final pack = maps.pack!;
  final bindings = _bindingsForPack(pack);
  final baseOld = _snapshot(
    mode: GameMode.pve,
    pack: pack,
    bindings: bindings,
    markerId: 'last-good-authority',
  );
  final old = activeMarkerCount == 1
      ? baseOld
      : LiveMapSnapshot(
          mode: baseOld.mode,
          checkedAt: baseOld.checkedAt,
          normalizedPayload: _compactPayload({
            for (final map in pack.maps)
              if (map.id != 'customs') map.id: const <Object?>[],
            'customs': [
              for (var index = 0; index < activeMarkerCount; index++)
                {
                  'id': 'last-good-$index',
                  'category': 'switches',
                  'filterKey': 'Switches',
                  'name': 'Last good $index',
                  'position': {'x': index, 'z': index, 'height': null},
                  'details': <String, Object?>{},
                  'source': {'mapId': 'customs'},
                  'outline': <Object?>[],
                },
            ],
          }),
          sources: baseOld.sources,
          formatVersion: baseOld.formatVersion,
          normalizerVersion: baseOld.normalizerVersion,
          compatibility: baseOld.compatibility,
        );
  expect(maps.prepareMarkerInventory(old, budget: LiveMapBudget())(), isTrue);
  final oldVisibleIds = maps.activeMarkers.map((marker) => marker.id).toList();
  final input = _expandedSources(
    positions,
    unknownTaskFact: unknownTaskFact,
    distinctZoneFactBytes: distinctZoneFactBytes,
    geometrySentinel: geometrySentinel,
  );
  final client = _ControlledClient(sourceBodies: input);
  final store = _Store()..snapshots[GameMode.pve] = old;
  final publications = <LiveMapSnapshot?>[];
  final acquirer = LiveMapRefreshAcquirer(
    client: client,
    store: store,
    clock: () => _now,
    limits: limits,
  );
  final controller = LiveMapDataController(
    store: store,
    acquirer: acquirer,
    clock: () => _now,
    preparePublication: (snapshot, budget) {
      final activate = maps.prepareMarkerInventory(snapshot, budget: budget);
      return () {
        publications.add(snapshot);
        activate();
      };
    },
  );
  addTearDown(() async {
    await controller.close();
    maps.dispose();
  });

  await controller.selectMode(
    mode: GameMode.pve,
    pack: pack,
    bindings: bindings,
  );
  await _waitForState(
    controller,
    (state) =>
        !state.refreshing &&
        (state.failure != null || state.source == LiveMapDataSource.refreshed),
  );

  if (expectFailure) {
    expect(store.snapshots[GameMode.pve], same(old));
    expect(store.commits, isEmpty);
    expect(maps.activeMarkers.map((marker) => marker.id), oldVisibleIds);
    expect(controller.state.source, LiveMapDataSource.cached);
    expect(controller.state.failure, isA<LiveMapResourceLimitException>());
    expect(publications.whereType<LiveMapSnapshot>().single, same(old));
  } else {
    expect(
      controller.state.failure,
      isNull,
      reason: 'A fitting candidate must reach publication without a resource failure.',
    );
    final committed = store.snapshots[GameMode.pve]!;
    expect(store.commits, hasLength(1));
    expect(committed, isNot(same(old)));
    expect(committed.sources, hasLength(6));
    expect(controller.state.source, LiveMapDataSource.refreshed);
    expect(controller.state.failure, isNull);
    expect(publications.last, same(committed));
    final activeIds = maps.activeMarkers.map((marker) => marker.id).toList();
    expect(activeIds, isNot(oldVisibleIds));
    expect(activeIds, hasLength(positions));
    expect(activeIds, isNotEmpty);
    if (verifySharedFactSearch) {
      final firstTask = maps.activeMarkers.first.details['sourceTask'];
      expect(
        maps.activeMarkers.every(
          (marker) => identical(marker.details['sourceTask'], firstTask),
        ),
        isTrue,
      );
      final unknownTaskFact =
          ((firstTask as Map<String, dynamic>)['unknownFutureFact']
              as Map<String, dynamic>);
      final phraseParts = unknownTaskFact['nested'] as Map<String, dynamic>;
      expect(() => phraseParts['mutated'] = true, throwsUnsupportedError);
      expect(
        () => (phraseParts['phraseParts'] as List).add('mutated'),
        throwsUnsupportedError,
      );
      expect(
        maps.activeMarkers.map(
          (marker) => marker.source['originalIdentity']['zoneId'],
        ),
        [for (var index = 0; index < positions; index++) 'zone-$index'],
      );
      maps.setSearch('phrase crossing scalar leaves');
      expect(
        maps.visibleMarkers().where((marker) => !marker.dimmed),
        hasLength(positions),
      );
      maps.setSearch('cOmPaCtTaSkNeEdLe, phrase crossing scalar leaves');
      expect(
        maps.visibleMarkers().where((marker) => !marker.dimmed),
        hasLength(positions),
      );
      maps.setSearch('987654321');
      expect(
        maps.visibleMarkers().where((marker) => !marker.dimmed),
        isEmpty,
        reason: 'marker geometry must not enter recursive searchable facts',
      );
    }
  }
}

ByteData _picture() => ByteData.sublistView(
  compiler.encodeSvg(
    xml: '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" fill="#336699"/></svg>',
    debugName: 'live-map-lifecycle-fixture',
    enableClippingOptimizer: false,
    enableMaskingOptimizer: false,
    enableOverdrawOptimizer: false,
  ),
);
