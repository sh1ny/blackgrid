import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/data/catalog_normalizer.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/catalog_store.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/stalling_http_client.dart';

class MemoryCatalogStore implements CatalogStore {
  final Map<GameMode, CatalogSnapshot> catalogs = {};
  Completer<void>? commitBarrier;
  Completer<CatalogSnapshot?>? loadBarrier;
  Object? failure;
  int commits = 0, loads = 0;
  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) async {
    loads++;
    if (loadBarrier != null) return loadBarrier!.future;
    return catalogs[mode];
  }

  @override
  Future<void> commitCatalog(CatalogSnapshot snapshot) async {
    commits++;
    await commitBarrier?.future;
    if (failure != null) throw failure!;
    catalogs[snapshot.mode] = snapshot;
  }
}

class ControlledCatalogClient extends CatalogClient {
  ControlledCatalogClient(this.handler)
    : super(client: MockClient((r) async => http.Response('', 500)));
  final Future<CatalogSnapshot> Function(GameMode) handler;
  int calls = 0;
  @override
  Future<CatalogSnapshot> fetch(GameMode mode) {
    calls++;
    return handler(mode);
  }
}

void main() {
  testWidgets(
    'review 2 deadline preserves last-good and releases coalesced next refresh',
    (tester) async {
      final old = fixtureCatalog();
      final transport = StallingHttpClient(
        stallPath: 'items',
        body: true,
        responses: wireFixture(),
      );
      addTearDown(transport.close);
      final store = MemoryCatalogStore()..catalogs[GameMode.pvp] = old;
      final c = CatalogController(
        store: store,
        client: CatalogClient(client: transport, clock: () => fixtureNow),
        clock: () => fixtureNow,
      );
      addTearDown(c.dispose);
      await c.setMode(GameMode.pvp);
      final pending = c.refresh();
      final coalesced = c.refresh();
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      await Future.wait([pending, coalesced]);
      expect(c.snapshot, same(old));
      expect(c.status, CatalogStatus.stale);
      expect(store.commits, 0);
      transport.stall = false;
      await tester.runAsync(c.refresh);
      expect(c.status, CatalogStatus.current);
      expect(store.commits, 1);
    },
  );
  test('unknown cold startup has no fabricated items and sends no requests/store reads', () async {
    final store = MemoryCatalogStore();
    final client = ControlledCatalogClient(
      (m) async => fixtureCatalog(mode: m),
    );
    final c = CatalogController(store: store, client: client);
    addTearDown(c.dispose);
    await c.setMode(GameMode.unknown);
    await c.refresh();
    expect(c.snapshot, isNull);
    expect(c.status, CatalogStatus.missing);
    expect(store.loads, 0);
    expect(client.calls, 0);
  });
  test('cached startup stale; candidate invisible until durable commit then current', () async {
    final old = fixtureCatalog();
    final store = MemoryCatalogStore()..catalogs[GameMode.pvp] = old;
    final candidate = decisionCatalog();
    final client = ControlledCatalogClient((m) async => candidate);
    final c = CatalogController(
      store: store,
      client: client,
      clock: () => fixtureNow,
    );
    addTearDown(c.dispose);
    await c.setMode(GameMode.pvp);
    expect(c.snapshot, same(old));
    expect(c.status, CatalogStatus.stale);
    final barrier = Completer<void>();
    store.commitBarrier = barrier;
    final started = Completer<void>();
    c.addListener(() {
      if (c.loading && !started.isCompleted) started.complete();
    });
    final refreshing = c.refresh();
    await started.future;
    await Future<void>.delayed(Duration.zero);
    expect(c.snapshot, same(old));
    expect(c.status, CatalogStatus.loading);
    expect(store.catalogs[GameMode.pvp], same(old));
    barrier.complete();
    await refreshing;
    expect(c.snapshot, same(candidate));
    expect(c.status, CatalogStatus.current);
    expect(store.catalogs[GameMode.pvp], same(candidate));
    expect(store.commits, 1);
  });
  for (final result in ['old snapshot', 'null', 'error']) {
    test(
      'late mode cache $result cannot overwrite a committed refresh',
      () async {
        final cached = fixtureCatalog();
        final candidate = decisionCatalog();
        final load = Completer<CatalogSnapshot?>();
        final response = Completer<CatalogSnapshot>();
        final store = MemoryCatalogStore()
          ..catalogs[GameMode.pvp] = cached
          ..loadBarrier = load;
        final client = ControlledCatalogClient((m) => response.future);
        final c = CatalogController(
          store: store,
          client: client,
          clock: () => fixtureNow,
        );
        addTearDown(c.dispose);
        var notifications = 0;
        c.addListener(() => notifications++);
        final loading = c.setMode(GameMode.pvp);
        final refreshing = c.refresh();
        final duplicate = c.refresh();
        response.complete(candidate);
        await Future.wait([refreshing, duplicate]);
        expect(c.snapshot, same(candidate));
        expect(c.status, CatalogStatus.current);
        expect(c.error, isNull);
        expect(store.catalogs[GameMode.pvp], same(candidate));
        expect(store.commits, 1);
        expect(client.calls, 1);
        final version = c.authorityVersion;
        final published = notifications;

        if (result == 'error') {
          load.completeError(StateError('synthetic late cache error'));
        } else {
          load.complete(result == 'null' ? null : cached);
        }
        await loading;
        expect(c.snapshot, same(candidate));
        expect(c.status, CatalogStatus.current);
        expect(c.error, isNull);
        expect(store.catalogs[GameMode.pvp], same(candidate));
        expect(c.authorityVersion, version);
        expect(notifications, published);
      },
    );
  }
  for (final cacheFirst in [false, true]) {
    test(
      'overlapping failed refresh retains cache loaded ${cacheFirst ? 'before' : 'after'} failure',
      () async {
        final cached = fixtureCatalog();
        final load = Completer<CatalogSnapshot?>();
        final response = Completer<CatalogSnapshot>();
        final store = MemoryCatalogStore()
          ..catalogs[GameMode.pvp] = cached
          ..loadBarrier = load;
        final c = CatalogController(
          store: store,
          client: ControlledCatalogClient((m) => response.future),
        );
        addTearDown(c.dispose);
        final loading = c.setMode(GameMode.pvp);
        final refreshing = c.refresh();
        if (cacheFirst) {
          load.complete(cached);
          await loading;
        }
        response.completeError(
          const CatalogException(
            'synthetic download error',
            CatalogFailure.transport,
          ),
        );
        await refreshing;
        if (!cacheFirst) {
          expect(c.snapshot, isNull);
          expect(c.status, CatalogStatus.failed);
          load.complete(cached);
          await loading;
        }
        expect(c.snapshot, same(cached));
        expect(c.status, CatalogStatus.stale);
        expect(
          c.error,
          'Item data could not be downloaded: no connection to tarkov.dev. '
          'The last item data is still in use.',
        );
        expect(store.catalogs[GameMode.pvp], same(cached));
        expect(store.commits, 0);
      },
    );
  }
  for (final commitFailure in [false, true]) {
    test(
      '${commitFailure ? 'commit' : 'download'} failure retains last-good UI and reopened store',
      () async {
        final old = fixtureCatalog();
        final store = MemoryCatalogStore()..catalogs[GameMode.pvp] = old;
        if (commitFailure) store.failure = StateError('synthetic commit error');
        final client = ControlledCatalogClient((m) async {
          if (!commitFailure) {
            throw const CatalogException(
              'synthetic download error',
              CatalogFailure.transport,
            );
          }
          return decisionCatalog();
        });
        final c = CatalogController(store: store, client: client);
        addTearDown(c.dispose);
        await c.setMode(GameMode.pvp);
        await c.refresh();
        expect(c.snapshot, same(old));
        expect(c.status, CatalogStatus.stale);
        expect(c.error, isNotNull);
        expect(await store.loadCatalog(GameMode.pvp), same(old));
      },
    );
  }
  test('cold offline failure has no replacement data', () async {
    final c = CatalogController(
      store: MemoryCatalogStore(),
      client: ControlledCatalogClient(
        (m) async =>
            throw const CatalogException('offline', CatalogFailure.transport),
      ),
    );
    addTearDown(c.dispose);
    await c.setMode(GameMode.pve);
    await c.refresh();
    expect(c.status, CatalogStatus.failed);
    expect(c.snapshot, isNull);
  });
  test(
    'review 7 returning mode rebinds coalesced refresh publication',
    () async {
      final response = Completer<CatalogSnapshot>();
      final store = MemoryCatalogStore();
      final client = ControlledCatalogClient((m) => response.future);
      final c = CatalogController(
        store: store,
        client: client,
        clock: () => fixtureNow,
      );
      addTearDown(c.dispose);
      await c.setMode(GameMode.pvp);
      final first = c.refresh();
      await c.setMode(GameMode.pve);
      await c.setMode(GameMode.pvp);
      final rebound = c.refresh();
      final candidate = decisionCatalog();
      response.complete(candidate);
      await Future.wait([first, rebound]);
      expect(c.snapshot, same(candidate));
      expect(c.status, CatalogStatus.current);
      expect(client.calls, 1);
      expect(store.commits, 1);
    },
  );
  test('same-key duplicate refreshes coalesce commit exactly once', () async {
    final response = Completer<CatalogSnapshot>();
    final store = MemoryCatalogStore();
    final client = ControlledCatalogClient((m) => response.future);
    final c = CatalogController(store: store, client: client);
    addTearDown(c.dispose);
    await c.setMode(GameMode.pvp);
    final a = c.refresh();
    final b = c.refresh();
    response.complete(fixtureCatalog());
    await Future.wait([a, b]);
    expect(client.calls, 1);
    expect(store.commits, 1);
  });
  test(
    'late previous-mode refresh may cache but cannot replace active mode',
    () async {
      final pvp = Completer<CatalogSnapshot>();
      final store = MemoryCatalogStore();
      final client = ControlledCatalogClient(
        (m) => m == GameMode.pvp
            ? pvp.future
            : Future.value(fixtureCatalog(mode: m)),
      );
      final c = CatalogController(store: store, client: client);
      addTearDown(c.dispose);
      await c.setMode(GameMode.pvp);
      final old = c.refresh();
      await c.setMode(GameMode.pve);
      await c.refresh();
      final active = c.snapshot;
      pvp.complete(fixtureCatalog());
      await old;
      expect(c.mode, GameMode.pve);
      expect(c.snapshot, same(active));
      expect(store.catalogs.keys, containsAll([GameMode.pvp, GameMode.pve]));
    },
  );
  test('refresh of the live wire shape publishes current', () async {
    final j = wireFixture();
    final store = MemoryCatalogStore();
    final c = CatalogController(
      store: store,
      client: CatalogClient(
        client: MockClient(
          (r) async =>
              http.Response(jsonEncode(j[r.url.pathSegments.last]), 200),
        ),
        clock: () => fixtureNow,
      ),
      clock: () => fixtureNow,
    );
    addTearDown(c.dispose);
    await c.setMode(GameMode.pvp);
    await c.refresh();
    expect(c.error, isNull);
    expect(store.commits, 1);
    expect(c.status, CatalogStatus.current);
  });
  test('authority transitions and expiration emit notifications', () async {
    var now = fixtureNow;
    final c = CatalogController(
      store: MemoryCatalogStore(),
      client: ControlledCatalogClient((m) async => decisionCatalog()),
      clock: () => now,
    );
    addTearDown(c.dispose);
    var notifications = 0;
    c.addListener(() => notifications++);
    await c.setMode(GameMode.pvp);
    await c.refresh();
    final version = c.authorityVersion;
    now = now.add(const Duration(hours: 25));
    c.updateAge();
    expect(c.status, CatalogStatus.stale);
    expect(c.authorityVersion, greaterThan(version));
    expect(notifications, c.authorityVersion);
  });
  testWidgets(
    'catalog local/source expiry timer notifies without scheduling requests',
    (tester) async {
      var now = fixtureNow;
      final client = ControlledCatalogClient((m) async => decisionCatalog());
      final c = CatalogController(
        store: MemoryCatalogStore(),
        client: client,
        clock: () => now,
      );
      addTearDown(c.dispose);
      await c.setMode(GameMode.pvp);
      await c.refresh();
      final version = c.authorityVersion;
      now = now.add(const Duration(hours: 24, milliseconds: 1));
      await tester.pump(const Duration(hours: 24, milliseconds: 1));
      expect(c.status, CatalogStatus.stale);
      expect(c.authorityVersion, greaterThan(version));
      expect(client.calls, 1);
    },
  );
  testWidgets('old items source time does not shorten the current window', (
    tester,
  ) async {
    var now = fixtureNow;
    final client = ControlledCatalogClient(
      (m) async => decisionCatalog(
        times: {
          for (final key in catalogDatasets)
            key: key == 'items'
                ? fixtureNow.subtract(const Duration(hours: 23))
                : null,
        },
      ),
    );
    final c = CatalogController(
      store: MemoryCatalogStore(),
      client: client,
      clock: () => now,
    );
    addTearDown(c.dispose);
    await c.setMode(GameMode.pvp);
    await c.refresh();
    expect(c.status, CatalogStatus.current);
    now = fixtureNow.add(const Duration(hours: 2));
    await tester.pump(const Duration(hours: 2));
    expect(c.status, CatalogStatus.current);
    now = fixtureNow.add(const Duration(hours: 24, milliseconds: 1));
    await tester.pump(const Duration(hours: 22, milliseconds: 1));
    expect(c.status, CatalogStatus.stale);
    expect(client.calls, 1);
  });
  test(
    'disposal fences publication while durable cache still commits',
    () async {
      final response = Completer<CatalogSnapshot>();
      final store = MemoryCatalogStore();
      final c = CatalogController(
        store: store,
        client: ControlledCatalogClient((m) => response.future),
      );
      await c.setMode(GameMode.pvp);
      final old = c.refresh();
      c.dispose();
      response.complete(fixtureCatalog());
      await old;
      expect(store.catalogs[GameMode.pvp], isNotNull);
      expect(c.snapshot, isNull);
    },
  );
  group('failure causes', () {
    const kept = 'The last item data is still in use.';
    const none = 'No item data is available yet.';
    test('transport failure with a kept snapshot names no connection and kept data', () async {
      final old = fixtureCatalog();
      final store = MemoryCatalogStore()..catalogs[GameMode.pvp] = old;
      final c = CatalogController(
        store: store,
        client: CatalogClient(
          client: MockClient((r) async => throw http.ClientException('off')),
        ),
      );
      addTearDown(c.dispose);
      await c.setMode(GameMode.pvp);
      await c.refresh();
      expect(c.status, CatalogStatus.stale);
      expect(c.snapshot, same(old));
      expect(
        c.error,
        'Item data could not be downloaded: no connection to tarkov.dev. '
        '$kept',
      );
    });
    test(
      'HTTP 503 with a kept snapshot names the server error and kept data',
      () async {
        final j = wireFixture();
        final store = MemoryCatalogStore()
          ..catalogs[GameMode.pvp] = fixtureCatalog();
        final c = CatalogController(
          store: store,
          client: CatalogClient(
            client: MockClient(
              (r) async => r.url.pathSegments.last == 'items'
                  ? http.Response('private', 503)
                  : http.Response(jsonEncode(j[r.url.pathSegments.last]), 200),
            ),
          ),
        );
        addTearDown(c.dispose);
        await c.setMode(GameMode.pvp);
        await c.refresh();
        expect(c.status, CatalogStatus.stale);
        expect(
          c.error,
          'Item data could not be downloaded: tarkov.dev answered with an '
          'error. $kept',
        );
      },
    );
    test(
      'invalid data with no snapshot fails naming invalid data and no data',
      () async {
        final c = CatalogController(
          store: MemoryCatalogStore(),
          client: ControlledCatalogClient(
            (m) async =>
                throw const CatalogException('bad', CatalogFailure.invalid),
          ),
        );
        addTearDown(c.dispose);
        await c.setMode(GameMode.pvp);
        await c.refresh();
        expect(c.status, CatalogStatus.failed);
        expect(c.snapshot, isNull);
        expect(
          c.error,
          'Item data from tarkov.dev was incomplete or invalid. $none',
        );
      },
    );
    test('a non-catalog fetch throw is treated as invalid data', () async {
      final c = CatalogController(
        store: MemoryCatalogStore(),
        client: ControlledCatalogClient((m) async => throw StateError('x')),
      );
      addTearDown(c.dispose);
      await c.setMode(GameMode.pvp);
      await c.refresh();
      expect(
        c.error,
        'Item data from tarkov.dev was incomplete or invalid. $none',
      );
    });
    test(
      'commit failure names the local save and keeps the stored snapshot',
      () async {
        final old = fixtureCatalog();
        final store = MemoryCatalogStore()
          ..catalogs[GameMode.pvp] = old
          ..failure = StateError('disk');
        final c = CatalogController(
          store: store,
          client: ControlledCatalogClient((m) async => decisionCatalog()),
        );
        addTearDown(c.dispose);
        await c.setMode(GameMode.pvp);
        await c.refresh();
        expect(c.status, CatalogStatus.stale);
        expect(c.snapshot, same(old));
        expect(c.error, 'Item data could not be saved on this computer. $kept');
        expect(await store.loadCatalog(GameMode.pvp), same(old));
      },
    );
  });
}
