import 'dart:async';

import 'package:http/http.dart' as http;

import '../data/catalog_client.dart';
import '../data/credential_store.dart';
import '../data/database.dart';
import '../data/legacy_import.dart';
import '../data/local_paths.dart';
import '../data/tracker_client.dart';
import '../domain/catalog.dart';
import '../domain/credential_store.dart';
import '../maps/native_map_scene.dart';
import '../maps/prepared_map_loader.dart';
import 'catalog_controller.dart';
import 'history_controller.dart';
import 'map_controller.dart';
import 'progress_controller.dart';
import 'selection_controller.dart';
import 'session_scan_state.dart';
import 'settings_controller.dart';

class AppServices {
  AppServices({
    required this.database,
    required CredentialStore credentials,
    required http.Client client,
    DateTime Function()? clock,
    MapController? mapController,
  }) : _client = client {
    final loader = PreparedMapPackLoader();
    maps =
        mapController ??
        MapController(
          loader: loader,
          resources: NativeMapResourceOwner(loader),
        );
    settings = SettingsController(database);
    settings.addListener(_syncMapSettings);
    history = HistoryController(database);
    catalog = CatalogController(
      store: database,
      client: CatalogClient(client: client, clock: clock),
      clock: clock,
    );
    progress = ProgressController(
      store: credentials,
      client: TrackerClient(client: client, clock: clock),
      clock: clock,
    );
    selection = SelectionController(
      database: database,
      catalog: catalog,
      progress: progress,
      history: history,
      clock: clock,
    );
    importer = LegacyImport(database);
  }
  final BlackgridDatabase database;
  final http.Client _client;
  late final SettingsController settings;
  late final MapController maps;
  bool _mapsInitialized = false;
  late final HistoryController history;
  late final CatalogController catalog;
  late final ProgressController progress;
  late final SelectionController selection;
  late final LegacyImport importer;
  final scans = const SessionScanState();
  bool _disposed = false;
  int _modeTransition = 0;
  static Future<AppServices> open() async {
    final paths = await LocalPaths.resolve();
    final result = AppServices(
      database: BlackgridDatabase.open(paths.database),
      credentials: DpapiCredentialStore(paths.credentials),
      client: http.Client(),
    );
    try {
      await result.initialize();
      return result;
    } catch (_) {
      await result.dispose();
      rethrow;
    }
  }

  Future<void> initialize() async {
    await settings.load();
    if (!_mapsInitialized) {
      await maps.initialize(
        selectedMapId: settings.settings.selectedMap,
        categoryVisibility: settings.settings.markerFilters,
      );
      if (_disposed) return;
      _mapsInitialized = true;
    } else {
      _syncMapSettings();
    }
    await history.load();
    await progress.setMode(settings.settings.mode);
    await catalog.setMode(settings.settings.mode);
  }

  void _syncMapSettings() {
    if (!_mapsInitialized || _disposed) return;
    maps.setCategoryVisibility(settings.settings.markerFilters);
    unawaited(maps.selectPersistedMap(settings.settings.selectedMap));
  }

  Future<bool> setMode(GameMode mode) async {
    if (!await settings.setMode(mode) || _disposed) return false;
    final transition = ++_modeTransition;
    // Both controllers invalidate synchronously before either async read ends.
    final progressChange = progress.setMode(mode);
    final catalogChange = catalog.setMode(mode);
    await Future.wait([progressChange, catalogChange]);
    return !_disposed && transition == _modeTransition;
  }

  Future<void> reloadAfterImport() async {
    await initialize();
    selection.closeHistory();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    selection.dispose();
    progress.dispose();
    catalog.dispose();
    maps.dispose();
    settings.removeListener(_syncMapSettings);
    settings.dispose();
    history.dispose();
    _client.close();
    await database.close();
  }
}
