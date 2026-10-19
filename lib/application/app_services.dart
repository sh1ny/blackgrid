import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../data/catalog_client.dart';
import '../data/credential_store.dart';
import '../data/database.dart';
import '../data/legacy_import.dart';
import '../data/local_paths.dart';
import '../data/game_paths.dart';
import '../data/raid_panel_ocr.dart';
import '../data/scan_frame_recorder.dart';
import '../data/scan_timing_log.dart';
import '../data/tracker_client.dart';
import '../domain/catalog.dart';
import '../domain/credential_store.dart';
import '../maps/native_map_scene.dart';
import '../maps/prepared_map_loader.dart';
import 'catalog_controller.dart';
import 'history_controller.dart';
import 'map_controller.dart';
import 'map_session_controller.dart';
import 'progress_controller.dart';
import 'scan_coordinator.dart';
import 'scan_decision_feed.dart';
import 'scan_epoch.dart';
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
    RaidPanelOcr? panelOcr,
    GamePathDiscovery? pathDiscovery,
    Directory? scanLogDirectory,
    Directory? scanFramesDirectory,
    String? scanRuntimeDirectory,
    ScanMarkerLoader? scanMarkerLoader,
    ScanCaptureFactory? scanCaptureFactory,
    ScanVisionFactory? scanVisionFactory,
    ScanPlatformFactory? scanPlatformFactory,
    ScanWaiter? scanWaiter,
    Duration scanSettleDelay = const Duration(milliseconds: 50),
    Duration scanFallbackDelay = const Duration(milliseconds: 200),
  }) : _client = client {
    final loader = PreparedMapPackLoader();
    maps =
        mapController ??
        MapController(
          loader: loader,
          resources: NativeMapResourceOwner(loader),
        );
    settings = SettingsController(database);
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
      epoch: _currentEpoch,
    );
    importer = LegacyImport(database);
    mapSession = MapSessionController(
      settings: settings,
      panelOcr: panelOcr ?? RaidPanelOcr(),
      clock: clock,
      discovery: pathDiscovery,
    );
    scanTimingLog = ScanTimingLog(
      scanLogDirectory ??
          Directory('${Directory.systemTemp.path}/blackgrid-scan-logs'),
    );
    scanFrameRecorder = ScanFrameRecorder(
      root:
          (scanFramesDirectory ??
                  Directory(
                    '${Directory.systemTemp.path}/blackgrid-scan-frames',
                  ))
              .path,
    );
    scanner = ScanCoordinator(
      settings: settings,
      catalog: catalog,
      appendLogLine: scanTimingLog.append,
      markerLoader: scanMarkerLoader ?? loadMarkerTemplateOffUi,
      captureFactory: scanCaptureFactory ?? openDefaultScanCapture,
      visionFactory: scanVisionFactory ?? openDefaultScanVision,
      platformFactory: scanPlatformFactory ?? openDefaultScanPlatform,
      runtimeDirectory: scanRuntimeDirectory,
      waiter: scanWaiter,
      recorder: scanFrameRecorder,
      settleDelay: scanSettleDelay,
      fallbackDelay: scanFallbackDelay,
      epoch: _currentEpoch,
    );
    scanFeed = ScanDecisionFeed(
      source: scanner,
      selection: selection,
      catalog: catalog,
      epoch: _currentEpoch,
    );
    _appliedSessionEpoch = mapSession.state.sessionEpoch;
    settings.addListener(_syncMapSettings);
    maps.addListener(_syncMapContext);
    mapSession.addListener(_syncMapSession);
  }
  final BlackgridDatabase database;
  final http.Client _client;
  late final SettingsController settings;
  late final MapController maps;
  late final MapSessionController mapSession;

  /// Owns live scanning: the switch, the worker, the hook and the scan flow.
  late final ScanCoordinator scanner;

  /// Carries accepted scans from [scanner] into [selection].
  late final ScanDecisionFeed scanFeed;

  /// The bounded timing log the scanner appends to.
  late final ScanTimingLog scanTimingLog;

  /// The opt-in recorder of scan frames, driven by the scanner.
  late final ScanFrameRecorder scanFrameRecorder;
  bool _mapsInitialized = false;
  int _mapContentGeneration = -1;
  Object? _publishedPlayerSample;
  Set<String>? _publishedRaidHighlights;
  GameMode? _appliedMode;
  int _appliedSessionEpoch = 0;
  Future<void> _modeChange = Future.value();
  late final HistoryController history;
  late final CatalogController catalog;
  late final ProgressController progress;
  late final SelectionController selection;
  late final LegacyImport importer;
  final scans = const SessionScanState();
  bool _disposed = false;
  int _modeTransition = 0;
  Future<void> _automaticRefreshes = Future.value();

  /// Completes when the latest mode selection's background work has finished.
  ///
  /// The work is both controllers' `setMode` calls and every catalog and
  /// progress refresh started after them. A selection that starts no refresh
  /// completes right after its `setMode` calls. Each selection gets its own
  /// future, so a caller that captured the value before a later switch still
  /// observes the earlier selection. Failures are reported through the
  /// controllers, not here.
  ///
  /// Tests await this instead of sleeping. `initialize` and `setMode` never
  /// wait on it.
  @visibleForTesting
  Future<void> get automaticRefreshes => _automaticRefreshes;

  /// The epoch a scan begins in and is fenced against.
  ScanEpoch _currentEpoch() =>
      ScanEpoch(_modeTransition, mapSession.state.sessionEpoch);
  static Future<AppServices> open() async {
    final paths = await LocalPaths.resolve();
    final result = AppServices(
      database: BlackgridDatabase.open(paths.database),
      credentials: DpapiCredentialStore(paths.credentials),
      client: http.Client(),
      pathDiscovery: GamePathDiscovery(),
      scanLogDirectory: paths.logs,
      scanFramesDirectory: paths.scanFrames,
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
        selectedMapId: mapSession.effectiveMapId,
        categoryVisibility: settings.settings.markerFilters,
      );
      if (_disposed) return;
      _mapsInitialized = true;
    } else {
      _syncMapSettings();
    }
    _syncMapContext();
    await history.load();
    await mapSession.initialize();
    _syncMapSession();
    await _modeChange;
    // Settings are loaded; a saved "on" starts the pipeline. Later calls and
    // later initialize() runs do nothing.
    if (!_disposed) scanner.startFromSettings();
  }

  void _syncMapSettings() {
    if (!_mapsInitialized || _disposed) return;
    maps.setCategoryVisibility(settings.settings.markerFilters);
  }

  void _syncMapContext() {
    if (!_mapsInitialized || _disposed) return;
    final generation = maps.contentGeneration;
    if (generation == _mapContentGeneration) return;
    _mapContentGeneration = generation;
    mapSession.updateMapContext(maps.preparedMap, generation);
  }

  void _syncMapSession() {
    if (!_mapsInitialized || _disposed) return;
    unawaited(maps.selectPersistedMap(mapSession.effectiveMapId));
    final state = mapSession.state;
    final sample = state.playerSample;
    if (!identical(sample, _publishedPlayerSample)) {
      _publishedPlayerSample = sample;
      maps.setPlayerSample(
        sample?.metadata.position,
        forwardX: sample?.metadata.forwardX,
        forwardZ: sample?.metadata.forwardZ,
      );
    }
    if (!identical(state.raidHighlightIds, _publishedRaidHighlights)) {
      _publishedRaidHighlights = state.raidHighlightIds;
      maps.setRaidHighlights(state.raidHighlightIds);
    }
    final mode = mapSession.effectiveMode;
    var epochChanged = false;
    if (mode != _appliedMode) {
      _appliedMode = mode;
      ++_modeTransition;
      epochChanged = true;
      // Both invalidate synchronously, before either asynchronous read ends.
      final transition = _modeTransition;
      final progressReady = progress.setMode(mode);
      final catalogReady = catalog.setMode(mode);
      _modeChange = Future.wait([progressReady, catalogReady]).then((_) {});
      // The refreshes are never part of _modeChange: startup and a switch must
      // not wait on the network.
      // The Tracker preference gates progress as it gates the manual Refresh
      // buttons; ProgressController.refresh does not read it.
      final progressRefresh = _refreshAfter(
        progressReady,
        transition,
        mode,
        progress.refresh,
        when: () => settings.settings.trackerEnabled,
      );
      final catalogRefresh = _refreshAfter(
        catalogReady,
        transition,
        mode,
        catalog.refresh,
        when: () => catalog.status != CatalogStatus.current,
      );
      _automaticRefreshes = Future.wait([progressRefresh, catalogRefresh])
          .then((_) {}, onError: (Object _) {});
    }
    if (state.sessionEpoch != _appliedSessionEpoch) {
      _appliedSessionEpoch = state.sessionEpoch;
      epochChanged = true;
    }
    // After the mode block, so a combined change retires once.
    if (epochChanged) scanFeed.epochChanged();
  }

  /// Starts [refresh] once [ready] completes, while the selection that made
  /// transition [transition] is still current, [mode] is known and [when]
  /// holds. Completes when the refresh, if any, has finished.
  Future<void> _refreshAfter(
    Future<void> ready,
    int transition,
    GameMode mode,
    Future<void> Function() refresh, {
    bool Function()? when,
  }) => ready.then((_) {
    if (_disposed ||
        transition != _modeTransition ||
        mode == GameMode.unknown ||
        !(when?.call() ?? true)) {
      return null;
    }
    return refresh();
  });

  Future<bool> setMode(GameMode mode) async {
    if (!await settings.setMode(mode) || _disposed) return false;
    _syncMapSession();
    final transition = _modeTransition;
    await _modeChange;
    return !_disposed && transition == _modeTransition;
  }

  Future<void> reloadAfterImport() async {
    await initialize();
    selection.closeHistory();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    settings.removeListener(_syncMapSettings);
    maps.removeListener(_syncMapContext);
    mapSession.removeListener(_syncMapSession);
    scanFeed.dispose();
    try {
      try {
        await scanner.dispose();
      } finally {
        try {
          await scanFrameRecorder.close();
        } finally {
          await scanTimingLog.close();
        }
      }
      await mapSession.close();
    } finally {
      selection.dispose();
      progress.dispose();
      catalog.dispose();
      maps.dispose();
      settings.dispose();
      history.dispose();
      _client.close();
      await database.close();
    }
  }
}
