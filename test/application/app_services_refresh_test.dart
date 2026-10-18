import 'dart:async';
import 'dart:convert';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/application/catalog_controller.dart';
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

  /// When set, tracker requests wait on this completer before answering.
  Completer<void>? trackerGate;

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

  /// Completes once [count] tracker requests have started.
  Future<void> trackerStarted({int count = 1}) =>
      _until(() => trackerRequests >= count);

  /// Frees every held response so teardown never leaves a request pending.
  void releaseAll() {
    for (final route in _catalogGates.keys.toList()) {
      release(route, succeed: false);
    }
    final gate = trackerGate;
    if (gate != null && !gate.isCompleted) gate.complete();
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
      await trackerGate?.future;
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

  http.Response _tracker(http.Request request) {
    if (trackerStatus != 200) {
      return http.Response('', trackerStatus, headers: trackerHeaders);
    }
    final token = (request.headers['Authorization'] ?? '').replaceFirst(
      'Bearer ',
      '',
    );
    final mode = switch (token.split('_').first) {
      'PVE' => GameMode.pve,
      'SZN' => GameMode.seasonal,
      _ => GameMode.pvp,
    };
    final body = request.url.path == '/token'
        ? tokenWire(token, mode: mode)
        : progressWire();
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
}
