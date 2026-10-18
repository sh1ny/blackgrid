import 'dart:async';
import 'dart:convert';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/progress_controller.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/credential_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../data/tracker_client_test.dart' show tokenWire;
import '../fixtures/m1/catalog/fixture.dart';

/// A recording HTTP client for catalog and tracker routes.
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

  /// Status the tracker answers with, and the headers it adds.
  int trackerStatus = 200;
  Map<String, String> trackerHeaders = const {};

  final _heldModes = <GameMode>{};
  final _heldTracker = <Completer<bool>>[];

  /// The number of catalog fetches made for [route] (`regular`, `pve`,
  /// `pvp-season`). A fetch makes one request per dataset, so the `items`
  /// dataset counts the fetches.
  int fetches(String route) => requests
      .where((r) => r.url.host == 'json.tarkov.dev')
      .where((r) => r.url.path == '/$route/items')
      .length;

  /// The number of requests to the tracker host.
  int get trackerRequests =>
      requests.where((r) => r.url.host == 'api.tarkovtracker.org').length;

  /// The number of tracker fetches made for [mode], or for any mode when it is
  /// null. A fetch starts with one `/token` request.
  int trackerFetches([GameMode? mode]) => requests
      .where((r) => r.url.host == 'api.tarkovtracker.org')
      .where((r) => r.url.path == '/token')
      .where((r) => mode == null || _modeOf(r) == mode)
      .length;

  /// Holds the `/token` request of every later tracker fetch for [mode], in
  /// request order, until [releaseTracker] answers it.
  void holdTracker(GameMode mode) => _heldModes.add(mode);

  /// Answers the held tracker fetch number [index] (counting from 0 across all
  /// modes): valid when [succeed], otherwise a 503.
  void releaseTracker(int index, {bool succeed = true}) {
    final gate = _heldTracker[index];
    if (!gate.isCompleted) gate.complete(succeed);
  }

  /// Holds every catalog response for [route] until [release] is called.
  void holdCatalog(String route) => _catalogGates[route] = Completer<bool>();

  /// Answers the held catalog requests for [route]: valid when [succeed],
  /// otherwise a 503.
  void release(String route, {bool succeed = true}) {
    final gate = _catalogGates.remove(route);
    if (gate != null && !gate.isCompleted) gate.complete(succeed);
  }

  /// Makes every catalog response for [route] a 503 while [failing].
  void failCatalog(String route, {bool failing = true}) {
    failing ? _failingRoutes.add(route) : _failingRoutes.remove(route);
  }

  /// Forgets the recorded requests.
  void clear() => requests.clear();

  /// Completes once [count] fetches for [route] have started.
  Future<void> fetchStarted(String route, {int count = 1}) =>
      _until(() => fetches(route) >= count);

  /// Completes once [count] tracker fetches for [mode] have started.
  Future<void> trackerStarted(GameMode mode, {int count = 1}) =>
      _until(() => trackerFetches(mode) >= count);

  /// Frees every held response so teardown never leaves a request pending.
  void releaseAll() {
    for (final route in _catalogGates.keys.toList()) {
      release(route, succeed: false);
    }
    for (final gate in _heldTracker) {
      if (!gate.isCompleted) gate.complete(false);
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
    if (request.url.host == 'api.tarkovtracker.org') {
      if (request.url.path == '/token' &&
          _heldModes.contains(_modeOf(request))) {
        final gate = Completer<bool>();
        _heldTracker.add(gate);
        if (!await gate.future) return http.Response('synthetic', 503);
      }
      return _tracker(request);
    }
    final segments = request.url.pathSegments;
    final route = segments.first;
    final key = segments.last;
    final gate = _catalogGates[route];
    final succeed = gate == null ? true : await gate.future;
    if (!succeed || _failingRoutes.contains(route)) {
      return http.Response('synthetic unavailable', 503);
    }
    if (_wire.containsKey(key)) {
      return http.Response(jsonEncode(_wire[key]), 200);
    }
    return http.Response('{}', 404);
  }

  static String _tokenOf(http.Request request) =>
      (request.headers['Authorization'] ?? '').replaceFirst('Bearer ', '');

  static GameMode _modeOf(http.Request request) =>
      switch (_tokenOf(request).split('_').first) {
        'PVE' => GameMode.pve,
        'SZN' => GameMode.seasonal,
        _ => GameMode.pvp,
      };

  http.Response _tracker(http.Request request) {
    if (trackerStatus != 200) {
      return http.Response('', trackerStatus, headers: trackerHeaders);
    }
    final token = _tokenOf(request);
    final mode = _modeOf(request);
    final body = request.url.path == '/token'
        ? tokenWire(token, mode: mode)
        : (progressWire()
            ..['meta'] = {
              ...progressWire()['meta'] as Map,
              'gameMode': mode.trackerMode,
            });
    return http.Response(jsonEncode(body), 200, headers: trackerHeaders);
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
    if (holdLoads) {
      final gate = Completer<void>();
      _gates.add(gate);
      await gate.future;
    }
    if (failLoads) throw StateError('synthetic cache failure');
    return super.loadCatalog(mode);
  }
}

/// A credential store whose reads can be held, or made to throw.
class HoldableCredentials implements CredentialStore {
  final values = <GameMode, String>{};
  final reads = <GameMode>[];
  final _holds = <GameMode, Completer<void>>{};
  Object? readFailure;

  final _readWaiters = <({int count, Completer<void> signal})>[];

  /// Completes once [count] credential reads have started.
  Future<void> readsStarted(int count) {
    if (reads.length >= count) return Future.value();
    final signal = Completer<void>();
    _readWaiters.add((count: count, signal: signal));
    return signal.future;
  }

  /// Holds reads for [mode] until [release].
  void hold(GameMode mode) => _holds[mode] = Completer<void>();

  /// Lets the held reads for [mode] continue.
  void release(GameMode mode) => _holds.remove(mode)?.complete();

  /// Lets every held read continue.
  void releaseAll() {
    for (final mode in _holds.keys.toList()) {
      release(mode);
    }
  }

  @override
  Future<String?> readCredential(GameMode mode) async {
    reads.add(mode);
    _readWaiters.removeWhere((w) {
      if (reads.length < w.count) return false;
      w.signal.complete();
      return true;
    });
    await _holds[mode]?.future;
    final failure = readFailure;
    if (failure != null) throw failure;
    return values[mode];
  }

  @override
  Future<void> writeCredential(GameMode mode, String token) async {
    values[mode] = token;
  }

  @override
  Future<void> removeCredential(GameMode mode) async {
    values.remove(mode);
  }
}

/// A real [AppServices] over the recording rig.
class RefreshRig {
  RefreshRig() {
    services = AppServices(
      database: database,
      credentials: credentials,
      client: net.client,
      clock: () => fixtureNow,
    );
  }

  final net = RefreshHttp();
  final database = HoldableDatabase();
  final credentials = HoldableCredentials();
  late final AppServices services;

  /// Selects [mode] in the settings and initializes the app.
  Future<void> launch(GameMode mode) async {
    await services.settings.setMode(mode);
    await services.initialize();
  }

  /// Commits a catalog for [mode] so the next cached load finds it.
  Future<void> seedCache(GameMode mode) =>
      database.commitCatalog(fixtureCatalog(mode: mode));

  /// Releases every held operation and disposes the app.
  Future<void> dispose() async {
    net.releaseAll();
    database.releaseLoads();
    credentials.releaseAll();
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
      database.holdLoads = true;
      final launched = rig.launch(GameMode.pvp);
      await database.loadsStarted(1);
      final superseded = services.automaticRefreshes;
      final switched = services.setMode(GameMode.pve);
      await database.loadsStarted(2);
      database.releaseLoads();
      await launched;
      await switched;
      await superseded;
      await services.automaticRefreshes;
      expect(net.fetches('regular'), 0);
      expect(net.fetches('pve'), 1);
      expect(services.catalog.mode, GameMode.pve);
      expect(services.catalog.status, CatalogStatus.current);
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
        'Catalog refresh failed; last-good data retained',
      );
    });

    test('catalog: startup fetch fails with no cache', () async {
      net.failCatalog('regular');
      await rig.launch(GameMode.pvp);
      await services.automaticRefreshes;
      expect(net.fetches('regular'), 1);
      expect(services.catalog.status, CatalogStatus.failed);
      expect(services.catalog.snapshot, isNull);
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

  group('progress', () {
    const pvpToken = 'PVP_synthetic-fixture-only';
    const pveToken = 'PVE_synthetic-fixture-only';
    // Completes when the fetch has started, or when the selection has ended
    // without starting one, so the count assertion that follows fails fast.
    Future<void> started(GameMode mode, {int count = 1}) => Future.any([
      net.trackerStarted(mode, count: count),
      services.automaticRefreshes,
    ]);

    test('progress: launch with a saved credential', () async {
      rig.credentials.values[GameMode.pvp] = pvpToken;
      net.holdTracker(GameMode.pvp);
      await rig.launch(GameMode.pvp);
      // Startup returned while the fetch is still held.
      await started(GameMode.pvp);
      expect(net.trackerFetches(GameMode.pvp), 1);
      net.releaseTracker(0);
      await services.automaticRefreshes;
      expect(net.trackerFetches(), 1);
      expect(services.progress.status, ProgressStatus.current);
      expect(services.progress.snapshot?.mode, GameMode.pvp);
    });

    test('progress: no saved credential', () async {
      await rig.launch(GameMode.pvp);
      await services.automaticRefreshes;
      expect(net.trackerRequests, 0);
      expect(services.progress.status, ProgressStatus.missing);
    });

    test('progress: unreadable credential', () async {
      rig.credentials.values[GameMode.pvp] = pvpToken;
      rig.credentials.readFailure = StateError('synthetic');
      await rig.launch(GameMode.pvp);
      await services.automaticRefreshes;
      expect(net.trackerRequests, 0);
      expect(services.progress.status, ProgressStatus.failed);
      expect(services.progress.error, 'Protected credential unavailable');
    });

    test('progress: unknown mode makes no request', () async {
      rig.credentials.values[GameMode.pvp] = pvpToken;
      await rig.launch(GameMode.unknown);
      await services.automaticRefreshes;
      expect(net.trackerRequests, 0);
      expect(await services.setMode(GameMode.pvp), isTrue);
      await services.automaticRefreshes;
      net.clear();
      expect(await services.setMode(GameMode.unknown), isTrue);
      await services.automaticRefreshes;
      expect(net.trackerRequests, 0);
      expect(services.progress.status, ProgressStatus.missing);
    });

    test('progress: selection superseded during the credential read', () async {
      rig.credentials.values[GameMode.pvp] = pvpToken;
      rig.credentials.values[GameMode.pve] = pveToken;
      rig.credentials.hold(GameMode.pvp);
      final launched = rig.launch(GameMode.pvp);
      await rig.credentials.readsStarted(1);
      final superseded = services.automaticRefreshes;
      expect(await services.setMode(GameMode.pve), isTrue);
      // B's refresh has finished before A's credential read ends, so only the
      // transition fence stops A from starting a second fetch.
      await services.automaticRefreshes;
      expect(net.trackerFetches(GameMode.pve), 1);
      rig.credentials.release(GameMode.pvp);
      await launched;
      await superseded;
      await services.automaticRefreshes;
      expect(net.trackerFetches(GameMode.pvp), 0);
      expect(net.trackerFetches(GameMode.pve), 1);
      expect(services.progress.mode, GameMode.pve);
      expect(services.progress.status, ProgressStatus.current);
    });

    test('progress: saving a credential does not refresh', () async {
      await rig.launch(GameMode.pvp);
      await services.automaticRefreshes;
      await services.progress.saveCredential(pvpToken);
      expect(services.progress.hasCredential, isTrue);
      expect(net.trackerRequests, 0);
    });

    test('progress: tracker unavailable at launch', () async {
      rig.credentials.values[GameMode.pvp] = pvpToken;
      net.trackerStatus = 503;
      await rig.launch(GameMode.pvp);
      await services.automaticRefreshes;
      expect(net.trackerFetches(), 1);
      expect(services.progress.status, ProgressStatus.failed);
      expect(services.progress.error, 'Tracker transport unavailable');
    });

    test('progress: tracker answers with a cooldown', () async {
      rig.credentials.values[GameMode.pvp] = pvpToken;
      net.trackerStatus = 429;
      net.trackerHeaders = {'retry-after': '120'};
      await rig.launch(GameMode.pvp);
      await services.automaticRefreshes;
      expect(net.trackerFetches(), 1);
      expect(services.progress.status, ProgressStatus.cooldown);
      expect(
        services.progress.cooldownUntil,
        fixtureNow.add(const Duration(seconds: 120)),
      );
      await services.progress.refresh();
      expect(net.trackerFetches(), 1);
    });

    test('progress: rejected credential', () async {
      rig.credentials.values[GameMode.pvp] = pvpToken;
      net.trackerStatus = 401;
      await rig.launch(GameMode.pvp);
      await services.automaticRefreshes;
      expect(net.trackerFetches(), 1);
      expect(services.progress.status, ProgressStatus.failed);
      expect(services.progress.snapshot, isNull);
    });

    test('progress: switch during the automatic refresh', () async {
      rig.credentials.values[GameMode.pvp] = pvpToken;
      rig.credentials.values[GameMode.pve] = pveToken;
      net.holdTracker(GameMode.pvp);
      await rig.launch(GameMode.pvp);
      await started(GameMode.pvp);
      expect(net.trackerFetches(GameMode.pvp), 1);
      final first = services.automaticRefreshes;
      expect(await services.setMode(GameMode.pve), isTrue);
      await services.automaticRefreshes;
      final published = services.progress.snapshot;
      final version = services.progress.authorityVersion;
      expect(published?.mode, GameMode.pve);
      net.releaseTracker(0);
      await first;
      expect(services.progress.snapshot, same(published));
      expect(services.progress.authorityVersion, version);
      expect(services.progress.status, ProgressStatus.current);
    });

    test('progress: switch back before the old fetch returns', () async {
      rig.credentials.values[GameMode.pvp] = pvpToken;
      rig.credentials.values[GameMode.pve] = pveToken;
      net.holdTracker(GameMode.pvp);
      await rig.launch(GameMode.pvp);
      await started(GameMode.pvp);
      expect(net.trackerFetches(GameMode.pvp), 1);
      final first = services.automaticRefreshes;
      expect(await services.setMode(GameMode.pve), isTrue);
      await services.automaticRefreshes;
      expect(await services.setMode(GameMode.pvp), isTrue);
      final latest = services.automaticRefreshes;
      await started(GameMode.pvp, count: 2);
      expect(net.trackerFetches(GameMode.pvp), 2);
      // The first fetch returns while the latest one is still in flight.
      net.releaseTracker(0);
      await first;
      expect(services.progress.snapshot, isNull);
      expect(services.progress.status, ProgressStatus.loading);
      net.releaseTracker(1);
      await latest;
      expect(services.progress.status, ProgressStatus.current);
      expect(services.progress.snapshot?.mode, GameMode.pvp);
      expect(net.trackerFetches(GameMode.pvp), 2);
    });
  });
}
