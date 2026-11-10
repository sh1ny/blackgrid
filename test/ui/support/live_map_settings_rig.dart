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
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:blackgrid/maps/native_map_scene.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;

/// The time of the cached map data snapshot.
final settingsCheckedAt = DateTime.utc(2021, 4, 5, 6, 7);

/// The clock the rig's services run on.
final settingsNow = DateTime.utc(2026, 11, 6, 12);

/// An empty prepared map pack, enough to start a map data refresh.
final settingsPack = PreparedMapPack(
  version: 'settings-test',
  assetRoot: 'test',
  maps: [],
);

class SettingsRig {
  SettingsRig(this.services, this.controller, this.client);

  /// Builds services with a real map data controller over [client] and [store].
  static Future<SettingsRig> create({
    required ControlledMapClient client,
    SettingsStore? store,
  }) async {
    final database = BlackgridDatabase(NativeDatabase.memory());
    final snapshots = store ?? SettingsStore();
    final controller = LiveMapDataController(
      store: snapshots,
      fetcher: LiveMapFetcher(client: client, clock: () => settingsNow),
      publish: (_, {required changed}) {},
      buildMarkers: (_, _) async => const {},
    );
    final credentials = SettingsCredentials();
    final loader = PreparedMapPackLoader(
      loadBytes: (_) async =>
          ByteData.sublistView(Uint8List.fromList(utf8.encode('{}'))),
    );
    final services = AppServices(
      database: database,
      credentials: credentials,
      client: client,
      clock: () => settingsNow,
      mapController: MapController(
        loader: loader,
        resources: NativeMapResourceOwner(loader),
      ),
      mapDataController: controller,
    );
    return SettingsRig(services, controller, client);
  }

  final AppServices services;
  final LiveMapDataController controller;
  final ControlledMapClient client;

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

class SettingsCredentials implements CredentialStore {
  @override
  Future<String?> readCredential(GameMode mode) async => null;

  @override
  Future<void> writeCredential(GameMode mode, String token) async {}

  @override
  Future<void> removeCredential(GameMode mode) async {}
}

class SettingsStore implements LiveMapStore {
  SettingsStore({this._snapshot});

  final LiveMapSnapshot? _snapshot;

  @override
  Future<LiveMapSnapshot?> read(GameMode mode) async =>
      _snapshot?.mode == mode ? _snapshot : null;

  @override
  Future<void> commit(LiveMapSnapshot snapshot) async {}
}

class ControlledMapClient extends http.BaseClient {
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
        LiveMapSourceDataset.values.any((source) => source.path == dataset);
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

LiveMapSnapshot cachedSnapshot() => LiveMapSnapshot(
  mode: GameMode.pve,
  checkedAt: settingsCheckedAt,
  sources: [
    for (final dataset in LiveMapSourceDataset.values)
      LiveMapSourceBody(
        dataset: dataset,
        bytes: Uint8List.fromList(utf8.encode('{}')),
      ),
  ],
);
