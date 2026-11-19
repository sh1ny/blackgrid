import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/live_map_data_controller.dart';
import 'package:blackgrid/application/progress_authority.dart';
import 'package:blackgrid/application/map_controller.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/data/raid_panel_ocr.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/native_map_scene.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/m1/catalog/fixture.dart';
import 'support/fake_progress_access.dart' show progressPublished;
import '../support/prepared_pack_manifest.dart'
    show minimalPreparedMap, preparedPackBytes, preparedPackManifest;

/// A recording HTTP client for catalog routes.
///
/// Catalog datasets come from the M1 fixture. A catalog route can be held on a
/// completer, or made to fail, so a test observes the in-flight state.
class RefreshHttp {
  RefreshHttp() : _wire = wireFixture() {
    client = MockClient(_handle);
  }

  late final http.Client client;
  final Map<String, dynamic> _wire;
  final requests = <http.Request>[];
  final _catalogGates = <String, Completer<bool>>{};
  final _failingRoutes = <String>{};
  final _waiters = <({bool Function() ready, Completer<void> signal})>[];

  /// The number of catalog fetches made for [route] (`regular`, `pve`,
  /// `pvp-season`). A fetch makes one request per dataset, so the `items`
  /// dataset counts the fetches.
  int fetches(String route) => requests
      .where((r) => r.url.host == 'json.tarkov.dev')
      .where((r) => r.url.path == '/$route/items')
      .length;

  /// Holds every catalog response for [route] until [release] is called.
  void holdCatalog(String route) => _catalogGates[route] = Completer<bool>();

  /// Answers the held catalog requests for [route]: valid when [succeed],
  /// otherwise a 503.
  void release(String route, {bool succeed = true}) {
    final gate = _catalogGates.remove(route);
    if (gate != null && !gate.isCompleted) gate.complete(succeed);
  }

  /// Makes every catalog request for [route] fail as unreachable while
  /// [failing].
  void failCatalog(String route, {bool failing = true}) {
    failing ? _failingRoutes.add(route) : _failingRoutes.remove(route);
  }

  /// Forgets the recorded requests.
  void clear() => requests.clear();

  /// Completes once [count] fetches for [route] have started.
  Future<void> fetchStarted(String route, {int count = 1}) =>
      _until(() => fetches(route) >= count);

  /// Frees every held response so teardown never leaves a request pending.
  void releaseAll() {
    for (final route in _catalogGates.keys.toList()) {
      release(route, succeed: false);
    }
  }

  Future<void> _until(bool Function() ready) {
    if (ready()) return Future.value();
    final signal = Completer<void>();
    _waiters.add((ready: ready, signal: signal));
    return signal.future;
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    _waiters.removeWhere((w) {
      if (!w.ready()) return false;
      w.signal.complete();
      return true;
    });
    final segments = request.url.pathSegments;
    final route = segments.first;
    final key = segments.last;
    final gate = _catalogGates[route];
    final succeed = gate == null ? true : await gate.future;
    if (_failingRoutes.contains(route)) {
      throw http.ClientException('synthetic offline');
    }
    if (!succeed) {
      return http.Response('synthetic unavailable', 503);
    }
    if (_wire.containsKey(key)) {
      return http.Response(jsonEncode(_wire[key]), 200);
    }
    return http.Response('{}', 404);
  }
}

/// An in-memory database whose cached catalog read can be held or made to
/// throw.
class HoldableDatabase extends BlackgridDatabase {
  HoldableDatabase() : super(NativeDatabase.memory());

  /// Modes of every `loadCatalog` call, in call order.
  final loadCalls = <GameMode>[];
  final _gates = <Completer<void>>[];
  final _waiters = <({int count, Completer<void> signal})>[];

  /// When true, each `loadCatalog` waits for [releaseLoads].
  bool holdLoads = false;

  /// Modes whose `loadCatalog` calls wait for [releaseLoads].
  final heldModes = <GameMode>{};

  /// When true, `loadCatalog` throws.
  bool failLoads = false;

  /// Completes once [count] `loadCatalog` calls have started.
  Future<void> loadsStarted(int count) {
    if (loadCalls.length >= count) return Future.value();
    final signal = Completer<void>();
    _waiters.add((count: count, signal: signal));
    return signal.future;
  }

  /// Lets every held `loadCatalog` call continue.
  void releaseLoads() {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
    _gates.clear();
  }

  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) async {
    loadCalls.add(mode);
    _waiters.removeWhere((w) {
      if (loadCalls.length < w.count) return false;
      w.signal.complete();
      return true;
    });
    if (holdLoads || heldModes.contains(mode)) {
      final gate = Completer<void>();
      _gates.add(gate);
      await gate.future;
    }
    if (failLoads) throw StateError('synthetic cache failure');
    return super.loadCatalog(mode);
  }
}

/// A real [AppServices] over the recording rig.
class RefreshRig {
  RefreshRig({RaidPanelOcr? panelOcr, MapController? mapController}) {
    services = AppServices(
      database: database,
      client: net.client,
      clock: () => fixtureNow,
      panelOcr: panelOcr,
      mapController: mapController,
    );
  }

  final net = RefreshHttp();
  final database = HoldableDatabase();
  late final AppServices services;

  /// Selects [mode] in the settings and initializes the app.
  Future<void> launch(GameMode mode) async {
    await services.settings.save(
      services.settings.settings.copyWith(mode: mode),
    );
    await services.initialize();
  }

  /// Commits a catalog for [mode] so the next cached load finds it.
  Future<void> seedCache(GameMode mode) =>
      database.commitCatalog(fixtureCatalog(mode: mode));

  /// Releases every held operation and disposes the app.
  Future<void> dispose() async {
    net.releaseAll();
    database.releaseLoads();
    await services.dispose();
  }
}

/// The catalog statuses and errors published after construction.
class CatalogLog {
  CatalogLog(this._catalog) {
    _catalog.addListener(_record);
  }

  final CatalogController _catalog;
  final entries = <(CatalogStatus, String?)>[];

  /// The published statuses, in order.
  List<CatalogStatus> get statuses => [
    for (final (status, _) in entries) status,
  ];

  void _record() => entries.add((_catalog.status, _catalog.error));
}

class _FixtureRaidPanelOcr extends RaidPanelOcr {
  @override
  Future<RaidPanelEvidence> recognize(Uint8List imageBytes) async =>
      RaidPanelEvidence(
        state: RaidPanelState.recognized,
        extractNames: ['Fixture exit'],
      );
}

MapController _fixtureMapController() {
  final woods = minimalPreparedMap('woods')
    ..['markers'] = [
      {
        'id': 'woods-exit',
        'name': 'Fixture exit',
        'category': 'extracts',
        'filterKey': 'PmcExtracts',
        'position': {'x': 1, 'z': 2},
        'details': <String, Object?>{},
        'source': {'mapId': 'woods'},
        'outline': <Object?>[],
      },
    ];
  final loader = PreparedMapPackLoader(
    loadBytes: preparedPackBytes(preparedPackManifest(maps: [woods])),
  );
  return MapController(
    loader: loader,
    resources: NativeMapResourceOwner(loader),
  );
}

Map<String, List<PreparedMarker>> _markersWithExit(AppServices services) {
  final pack = services.maps.pack!;
  final mapId = services.maps.selectedMapId!;
  return <String, List<PreparedMarker>>{
    for (final map in pack.maps) map.id: map.markers,
    mapId: [
      ...pack.byId[mapId]!.markers.where(
        (marker) =>
            marker.category != 'extracts' && marker.category != 'transits',
      ),
      PreparedMarker(
        id: 'refreshed-exit',
        category: 'extracts',
        filterKey: 'PmcExtracts',
        name: 'Refreshed exit',
        position: GamePoint(1, 2),
        details: const {
          'aliases': ['Fixture exit'],
        },
        source: const {},
        outline: const [],
      ),
    ],
  };
}

void main() {
  late RefreshRig rig;
  late CatalogLog log;
  late AppServices services;
  late RefreshHttp net;
  late HoldableDatabase database;

  setUp(() {
    rig = RefreshRig();
    services = rig.services;
    net = rig.net;
    database = rig.database;
    log = CatalogLog(services.catalog);
  });
  tearDown(() => rig.dispose());

  group('catalog', () {
    test('catalog: launch with a cached snapshot', () async {
      await rig.seedCache(GameMode.pvp);
      net.holdCatalog('regular');
      await rig.launch(GameMode.pvp);
      // Startup returned while the fetch is still held.
      await net.fetchStarted('regular');
      expect(services.catalog.status, CatalogStatus.loading);
      expect(services.catalog.snapshot, isNotNull);
      net.release('regular');
      await services.automaticRefreshes;
      expect(net.fetches('regular'), 1);
      expect(services.catalog.status, CatalogStatus.current);
      expect(log.statuses, [
        CatalogStatus.loading,
        CatalogStatus.stale,
        CatalogStatus.loading,
        CatalogStatus.current,
      ]);
    });

    test('catalog: launch with no cache', () async {
      net.holdCatalog('regular');
      await rig.launch(GameMode.pvp);
      await net.fetchStarted('regular');
      expect(services.catalog.status, CatalogStatus.loading);
      net.release('regular');
      await services.automaticRefreshes;
      expect(net.fetches('regular'), 1);
      expect(services.catalog.status, CatalogStatus.current);
      expect(log.statuses, [
        CatalogStatus.loading,
        CatalogStatus.missing,
        CatalogStatus.loading,
        CatalogStatus.current,
      ]);
    });

    test('catalog: unreadable cache still refreshes', () async {
      database.failLoads = true;
      await rig.launch(GameMode.pvp);
      await services.automaticRefreshes;
      expect(net.fetches('regular'), 1);
      expect(services.catalog.status, CatalogStatus.current);
      expect(log.entries, [
        (CatalogStatus.loading, null),
        (CatalogStatus.failed, 'Stored catalog unavailable'),
        (CatalogStatus.loading, null),
        (CatalogStatus.current, null),
      ]);
    });

    test('catalog: unknown mode makes no request', () async {
      await rig.launch(GameMode.unknown);
      await services.automaticRefreshes;
      expect(net.requests, isEmpty);
      expect(services.catalog.status, CatalogStatus.missing);

      expect(await services.setMode(GameMode.pvp), isTrue);
      await services.automaticRefreshes;
      net.clear();
      expect(await services.setMode(GameMode.unknown), isTrue);
      await services.automaticRefreshes;
      expect(net.requests, isEmpty);
      expect(services.catalog.status, CatalogStatus.missing);
    });

    test('catalog: selection superseded during the cached load', () async {
      database.heldModes.add(GameMode.pvp);
      net.failCatalog('pve');
      final launched = rig.launch(GameMode.pvp);
      await database.loadsStarted(1);
      final superseded = services.automaticRefreshes;
      expect(await services.setMode(GameMode.pve), isTrue);
      // B's cached load and automatic fetch end, failing, before A's cached
      // load does. Only the transition fence then stops A's late callback from
      // starting a second fetch for B, which would be an automatic retry.
      await services.automaticRefreshes;
      expect(net.fetches('pve'), 1);
      expect(services.catalog.status, CatalogStatus.failed);
      database.releaseLoads();
      await launched;
      await superseded;
      expect(net.fetches('regular'), 0);
      expect(net.fetches('pve'), 1);
      expect(services.catalog.mode, GameMode.pve);
      expect(services.catalog.status, CatalogStatus.failed);
    });

    test(
      'catalog: manual refresh already succeeded during the cached load',
      () async {
        database.holdLoads = true;
        final launched = rig.launch(GameMode.pvp);
        await database.loadsStarted(1);
        await services.catalog.refresh();
        expect(services.catalog.status, CatalogStatus.current);
        expect(net.fetches('regular'), 1);
        database.releaseLoads();
        await launched;
        await services.automaticRefreshes;
        expect(net.fetches('regular'), 1);
        expect(services.catalog.status, CatalogStatus.current);
      },
    );

    test('catalog: manual refresh during the automatic one', () async {
      net.holdCatalog('regular');
      await rig.launch(GameMode.pvp);
      await net.fetchStarted('regular');
      final manual = services.catalog.refresh();
      net.release('regular');
      await manual;
      await services.automaticRefreshes;
      expect(net.fetches('regular'), 1);
      expect(services.catalog.status, CatalogStatus.current);
    });

    test('catalog: startup fetch fails with a cached snapshot', () async {
      await rig.seedCache(GameMode.pvp);
      net.failCatalog('regular');
      await rig.launch(GameMode.pvp);
      await services.automaticRefreshes;
      expect(net.fetches('regular'), 1);
      expect(services.catalog.status, CatalogStatus.stale);
      expect(services.catalog.snapshot, isNotNull);
      expect(
        services.catalog.error,
        'Item data could not be downloaded: no connection to tarkov.dev. '
        'The last item data is still in use.',
      );
    });

    test('catalog: startup fetch fails with no cache', () async {
      net.failCatalog('regular');
      await rig.launch(GameMode.pvp);
      await services.automaticRefreshes;
      expect(net.fetches('regular'), 1);
      expect(services.catalog.status, CatalogStatus.failed);
      expect(services.catalog.snapshot, isNull);
      expect(
        services.catalog.error,
        'Item data could not be downloaded: no connection to tarkov.dev. '
        'No item data is available yet.',
      );
    });

    test('catalog: manual refresh after a failure', () async {
      net.failCatalog('regular');
      await rig.launch(GameMode.pvp);
      await services.automaticRefreshes;
      expect(net.fetches('regular'), 1);
      net.failCatalog('regular', failing: false);
      await services.catalog.refresh();
      expect(net.fetches('regular'), 2);
      expect(services.catalog.status, CatalogStatus.current);
    });

    test('catalog: switch during the automatic refresh', () async {
      net.holdCatalog('regular');
      await rig.launch(GameMode.pvp);
      await net.fetchStarted('regular');
      final first = services.automaticRefreshes;
      expect(await services.setMode(GameMode.pve), isTrue);
      await services.automaticRefreshes;
      expect(services.catalog.status, CatalogStatus.current);
      expect(services.catalog.snapshot?.mode, GameMode.pve);
      net.release('regular');
      await first;
      expect(services.catalog.mode, GameMode.pve);
      expect(services.catalog.snapshot?.mode, GameMode.pve);
      expect(services.catalog.status, CatalogStatus.current);
      expect(net.fetches('regular'), 1);
      expect(net.fetches('pve'), 1);
    });

    test('catalog: failure after a switch', () async {
      net.holdCatalog('regular');
      await rig.launch(GameMode.pvp);
      await net.fetchStarted('regular');
      final first = services.automaticRefreshes;
      expect(await services.setMode(GameMode.pve), isTrue);
      await services.automaticRefreshes;
      net.release('regular', succeed: false);
      await first;
      expect(services.catalog.mode, GameMode.pve);
      expect(services.catalog.status, CatalogStatus.current);
      expect(services.catalog.error, isNull);
    });

    test('catalog: switch back while the refresh is still in flight', () async {
      net.holdCatalog('regular');
      await rig.launch(GameMode.pvp);
      await net.fetchStarted('regular');
      expect(await services.setMode(GameMode.pve), isTrue);
      await services.automaticRefreshes;
      expect(await services.setMode(GameMode.pvp), isTrue);
      final back = services.automaticRefreshes;
      net.release('regular');
      await back;
      expect(net.fetches('regular'), 1);
      expect(services.catalog.mode, GameMode.pvp);
      expect(services.catalog.snapshot?.mode, GameMode.pvp);
      expect(services.catalog.status, CatalogStatus.current);
    });
  });

  test('prepared pack load failures make map data unavailable', () async {
    await rig.dispose();
    final failure = StateError('synthetic pack failure');
    final loader = PreparedMapPackLoader(loadBytes: (_) async => throw failure);
    rig = RefreshRig(
      mapController: MapController(
        loader: loader,
        resources: NativeMapResourceOwner(loader),
      ),
    );
    services = rig.services;
    net = rig.net;
    await rig.launch(GameMode.pvp);
    await services.automaticRefreshes;
    expect(services.maps.pack, isNull);
    expect(services.maps.packLoadFailure, same(failure));
    expect(services.mapData.state.source, LiveMapDataSource.unavailable);
    expect(services.mapData.state.failure, same(failure));
    expect(services.mapData.state.refreshing, isFalse);
    expect(
      net.requests.where(
        (request) =>
            request.url.host == 'json.tarkov.dev' &&
            const {'maps', 'maps_en'}.contains(request.url.pathSegments.last),
      ),
      isEmpty,
    );

    net.clear();
    await services.refreshMapData();
    expect(services.mapData.state.source, LiveMapDataSource.unavailable);
    expect(services.mapData.state.failure, same(failure));
    expect(services.mapData.state.refreshing, isFalse);
    expect(net.requests, isEmpty);
  });

  test(
    'map publication refreshes saved-panel matching from active markers',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'blackgrid-app-services-map-exits-',
      );
      final screenshots = await Directory(
        '${root.path}${Platform.pathSeparator}screenshots',
      ).create();
      addTearDown(() => root.delete(recursive: true));
      await rig.dispose();
      final panelOcr = _FixtureRaidPanelOcr();
      rig = RefreshRig(
        panelOcr: panelOcr,
        mapController: _fixtureMapController(),
      );
      services = rig.services;
      net = rig.net;
      database = rig.database;
      await services.settings.save(
        services.settings.settings.copyWith(
          mode: GameMode.pvp,
          selectedMap: 'woods',
          screenshotDirectory: screenshots.path,
        ),
      );
      await services.initialize();
      expect(services.maps.pack, isNotNull);
      expect(services.maps.selectedMapId, 'woods');

      await File(
        '${screenshots.path}${Platform.pathSeparator}'
        '2026-11-06[12-00]_1, 0, 2_0, 0, 0, 1_0.png',
      ).writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/pZ8AAAAASUVORK5CYII=',
        ),
        flush: true,
      );
      await services.mapSession.readLatest();
      expect(
        services.mapSession.state.raidEvidence?.state,
        RaidPanelState.recognized,
      );
      expect(services.mapSession.state.raidHighlightIds, {'woods-exit'});

      services.maps.publishMarkers(_markersWithExit(services), changed: true);

      expect(
        services.maps.activeMarkers.map((marker) => marker.id),
        contains('refreshed-exit'),
      );
      expect(
        services.mapSession.state.raidEvidence?.state,
        RaidPanelState.recognized,
      );
      expect(services.mapSession.state.raidHighlightIds, {'refreshed-exit'});
    },
  );

  test('map refresh does not block service startup', () async {
    final mapRequestStarted = Completer<void>();
    final releaseMapResponses = Completer<void>();
    final client = MockClient((request) async {
      final path = request.url.pathSegments.last;
      if (request.url.host == 'json.tarkov.dev' &&
          const {
            'maps',
            'maps_en',
            'tasks',
            'tasks_en',
            'traders',
            'traders_en',
          }.contains(path)) {
        if (!mapRequestStarted.isCompleted) mapRequestStarted.complete();
        await releaseMapResponses.future;
      }
      return http.Response('', 503);
    });
    final services = AppServices(
      database: BlackgridDatabase(NativeDatabase.memory()),
      client: client,
    );
    addTearDown(() async {
      if (!releaseMapResponses.isCompleted) releaseMapResponses.complete();
      await services.dispose();
    });
    await services.settings.save(
      services.settings.settings.copyWith(mode: GameMode.pvp),
    );

    await services.initialize();
    await mapRequestStarted.future;

    releaseMapResponses.complete();
    await services.dispose();
  });

  group('progress', () {
    test(
      'progress: launch reads local progress and makes no request',
      () async {
        await rig.launch(GameMode.pvp);
        await services.automaticRefreshes;
        await progressPublished(services.progress);

        expect(services.progress.mode, GameMode.pvp);
        expect(services.progress.status, ProgressAuthorityStatus.local);
        expect(services.progress.facts!.mode, GameMode.pvp);
        expect(
          net.requests.map((request) => request.url.host),
          everyElement('json.tarkov.dev'),
        );
      },
    );

    test('progress: a mode switch follows the applied mode', () async {
      await rig.launch(GameMode.pvp);
      await progressPublished(services.progress);

      expect(await services.setMode(GameMode.pve), isTrue);
      expect(services.progress.mode, GameMode.pve);
      await progressPublished(services.progress);
      expect(services.progress.facts!.mode, GameMode.pve);
    });

    test('progress: an unknown mode is unavailable', () async {
      await rig.launch(GameMode.unknown);

      expect(services.progress.mode, GameMode.unknown);
      expect(services.progress.status, ProgressAuthorityStatus.unavailable);
      expect(services.progress.facts, isNull);
    });
  });
}
