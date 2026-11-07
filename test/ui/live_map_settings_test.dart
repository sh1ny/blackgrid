import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/application/live_map_data_controller.dart';
import 'package:blackgrid/application/map_controller.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/live_map_refresh.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/credential_store.dart';
import 'package:blackgrid/maps/live_map_budget.dart';
import 'package:blackgrid/maps/live_map_inventory.dart';
import 'package:blackgrid/maps/live_map_normalizer.dart'
    show liveMapNormalizerVersion;
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:blackgrid/maps/native_map_scene.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:blackgrid/ui/live_map_status.dart';
import 'package:blackgrid/ui/settings_dialog.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final _checkedAt = DateTime.utc(2021, 4, 5, 6, 7);
final _now = DateTime.utc(2026, 11, 6, 12);
final _pack = PreparedMapPack(
  version: 'settings-test',
  assetRoot: 'test',
  maps: [],
);

void main() {
  testWidgets(
    'map status stays independent while navigation remains available',
    (tester) async {
      late Completer<void> failed;
      final rig = (await tester.runAsync(() async {
        final client = _ControlledMapClient()..holdMapRequests = true;
        final rig = await _SettingsRig.create(client: client);
        failed = rig.whenState(
          (state) => !state.refreshing && state.failure != null,
        );
        unawaited(
          rig.controller.selectMode(
            mode: GameMode.pve,
            pack: _pack,
            bindings: const [],
          ),
        );
        await client.firstMapRequest.future;
        return rig;
      }))!;
      final client = rig.client;
      addTearDown(rig.close);
      expect(rig.controller.state.mode, GameMode.pve);
      expect(rig.controller.state.source, LiveMapDataSource.bundled);
      expect(rig.controller.state.refreshing, isTrue);

      await _showSettings(tester, rig.services);
      final mapStatus = find.byType(LiveMapStatus);
      expect(tester.widget<LiveMapStatus>(mapStatus).refreshing, isTrue);
      final mapRefreshButton = find.descendant(
        of: mapStatus,
        matching: find.byType(OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(mapRefreshButton).onPressed, isNull);
      expect(find.textContaining('PvE'), findsWidgets);
      expect(_textContaining('bundled'), findsOneWidget);
      final close = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Close'),
      );
      expect(close.onPressed, isNotNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsNothing);

      await tester.runAsync(() async {
        client.release.complete(
          http.Response('synthetic map source unavailable', 503),
        );
        await failed.future;
      });
      await tester.pump();
      expect(rig.controller.state.mode, GameMode.pve);
      expect(rig.controller.state.dataMode, GameMode.pvp);
      expect(rig.controller.state.source, LiveMapDataSource.bundled);
      expect(rig.controller.state.failure, isNotNull);

      await _showSettings(tester, rig.services);
      expect(find.textContaining('PvE'), findsWidgets);
      expect(find.textContaining('PvP'), findsWidgets);
      expect(_textContaining('bundled'), findsOneWidget);
      expect(
        _textContainingAny(['fail', 'unavailable', 'could not']),
        findsWidgets,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('manual map refresh does not refresh items', (tester) async {
    final rig = (await tester.runAsync(() async {
      final client = _ControlledMapClient();
      client.response = http.Response('synthetic map source unavailable', 503);
      final store = _SettingsStore(snapshot: _cachedSnapshot());
      final rig = await _SettingsRig.create(client: client, store: store);
      final failed = rig.whenState(
        (state) => !state.refreshing && state.failure != null,
      );
      unawaited(
        rig.controller.selectMode(
          mode: GameMode.pve,
          pack: _pack,
          bindings: const [],
        ),
      );
      await failed.future;
      return rig;
    }))!;
    final client = rig.client;
    addTearDown(rig.close);
    await _showSettings(tester, rig.services);

    expect(rig.controller.state.source, LiveMapDataSource.cached);
    expect(rig.controller.state.checkedAt, _checkedAt);
    expect(_textContaining('cached'), findsOneWidget);
    expect(find.textContaining('2021'), findsWidgets);
    expect(
      _textContainingAny(['fail', 'unavailable', 'could not']),
      findsWidgets,
    );
    final itemStatusBefore = find.textContaining('Item data:');
    expect(itemStatusBefore, findsOneWidget);
    final catalogSnapshot = rig.services.catalog.snapshot;
    final itemRequestsBefore = client.itemRequests;
    final mapRequestsBefore = client.mapRequests;
    final mapRefresh = find.text('Refresh map data');
    await tester.ensureVisible(mapRefresh);
    await tester.pumpAndSettle();
    expect(mapRefresh.hitTestable(), findsOneWidget);

    await tester.runAsync(() async {
      final refreshed = rig.whenNextSettled();
      final nextMapBatch = client.whenMapRequests(mapRequestsBefore + 1);
      await tester.tap(mapRefresh);
      await nextMapBatch.future;
      await refreshed.future;
    });
    await tester.pump();

    expect(client.mapRequests, greaterThan(mapRequestsBefore));
    expect(client.itemRequests, itemRequestsBefore);
    expect(rig.services.catalog.snapshot, same(catalogSnapshot));
    expect(rig.controller.state.source, LiveMapDataSource.cached);
    expect(rig.controller.state.checkedAt, _checkedAt);
    expect(find.textContaining('Item data:'), findsOneWidget);
    expect(_textContaining('cached'), findsOneWidget);
    expect(find.textContaining('2021'), findsWidgets);
  });
}

Finder _textContaining(String value) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      widget.data?.toLowerCase().contains(value.toLowerCase()) == true,
);

Finder _textContainingAny(List<String> values) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      values.any((value) => widget.data?.toLowerCase().contains(value) == true),
);

Future<void> _showSettings(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SettingsDialog(services: services),
            ),
            child: const Text('Open settings'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open settings'));
  await tester.pumpAndSettle();
}

class _SettingsRig {
  _SettingsRig(this.services, this.controller, this.client);

  static Future<_SettingsRig> create({
    required _ControlledMapClient client,
    _SettingsStore? store,
  }) async {
    final database = BlackgridDatabase(NativeDatabase.memory());
    final snapshots = store ?? _SettingsStore();
    final acquirer = LiveMapRefreshAcquirer(
      client: client,
      store: snapshots,
      clock: () => _now,
    );
    final controller = LiveMapDataController(
      store: snapshots,
      acquirer: acquirer,
      clock: () => _now,
      preparePublication: (snapshot, budget) => () {},
    );
    final credentials = _SettingsCredentials();
    final loader = PreparedMapPackLoader(
      loadBytes: (_) async =>
          ByteData.sublistView(Uint8List.fromList(utf8.encode('{}'))),
    );
    final services = AppServices(
      database: database,
      credentials: credentials,
      client: client,
      clock: () => _now,
      mapController: MapController(
        loader: loader,
        resources: NativeMapResourceOwner(loader),
      ),
      mapDataController: controller,
    );
    return _SettingsRig(services, controller, client);
  }

  final AppServices services;
  final LiveMapDataController controller;
  final _ControlledMapClient client;

  Completer<void> whenState(bool Function(LiveMapDataState) predicate) {
    final completer = Completer<void>();
    void listener() {
      if (predicate(controller.state)) {
        controller.removeListener(listener);
        completer.complete();
      }
    }

    controller.addListener(listener);
    listener();
    return completer;
  }

  Completer<void> whenNextSettled() {
    var refreshingObserved = false;
    return whenState((state) {
      refreshingObserved = refreshingObserved || state.refreshing;
      return refreshingObserved && !state.refreshing && state.failure != null;
    });
  }

  Future<void> close() async {
    await services.dispose();
    client.close();
  }
}

class _SettingsCredentials implements CredentialStore {
  @override
  Future<String?> readCredential(GameMode mode) async => null;

  @override
  Future<void> writeCredential(GameMode mode, String token) async {}

  @override
  Future<void> removeCredential(GameMode mode) async {}
}

class _SettingsStore implements LiveMapStore {
  _SettingsStore({this._snapshot});

  final LiveMapSnapshot? _snapshot;

  @override
  Future<LiveMapSnapshot?> read(
    GameMode mode, {
    required LiveMapCompatibility compatibility,
    void Function(Object failure)? onRejected,
  }) async =>
      _snapshot?.mode == mode &&
          _snapshot?.compatibility.fingerprint == compatibility.fingerprint
      ? _snapshot
      : null;

  @override
  Future<void> commit(
    LiveMapSnapshot snapshot, {
    LiveMapBudget? budget,
  }) async {}
}

class _ControlledMapClient extends http.BaseClient {
  final firstMapRequest = Completer<void>();
  final release = Completer<http.Response>();
  final mapRequestWaiters = <(int, Completer<void>)>[];
  var mapRequests = 0;
  var itemRequests = 0;
  var holdMapRequests = false;
  http.Response response = http.Response(
    'synthetic map source unavailable',
    503,
  );

  Completer<void> whenMapRequests(int target) {
    final completer = Completer<void>();
    if (mapRequests >= target) {
      completer.complete();
    } else {
      mapRequestWaiters.add((target, completer));
    }
    return completer;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.pathSegments;
    final dataset = path.last == 'en' && path.length > 1
        ? path[path.length - 2]
        : path.last;
    final isMapRequest =
        request.url.host == 'json.tarkov.dev' &&
        (dataset == 'maps' || dataset == 'tasks' || dataset == 'traders');
    if (isMapRequest) {
      mapRequests++;
      if (!firstMapRequest.isCompleted) firstMapRequest.complete();
      for (final (target, completer) in mapRequestWaiters) {
        if (!completer.isCompleted && mapRequests >= target) {
          completer.complete();
        }
      }
      if (holdMapRequests) {
        final response = await release.future;
        return _streamed(response, request);
      }
    } else {
      itemRequests++;
    }
    return _streamed(response, request);
  }

  http.StreamedResponse _streamed(
    http.Response response,
    http.BaseRequest request,
  ) => http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(response.body)),
    response.statusCode,
    request: request,
    headers: response.headers,
  );

  @override
  void close() {}
}

LiveMapSnapshot _cachedSnapshot() {
  final budget = LiveMapBudget();
  final payload = LiveMapInventory.fromMarkers(
    maps: {for (final map in _pack.maps) map.id: map.markers},
    budget: budget,
  ).encode(budget: budget);
  final sources = [
    for (final dataset in LiveMapSourceDataset.values)
      LiveMapSourceBody(
        dataset: dataset,
        bytes: Uint8List.fromList(utf8.encode('{}')),
      ),
  ];
  return LiveMapSnapshot(
    mode: GameMode.pve,
    checkedAt: _checkedAt,
    normalizedPayload: payload,
    sources: sources,
    formatVersion: liveMapSnapshotFormatVersion,
    normalizerVersion: liveMapNormalizerVersion,
    compatibility: LiveMapCompatibility.fromPreparedPack(_pack, const []),
  );
}
