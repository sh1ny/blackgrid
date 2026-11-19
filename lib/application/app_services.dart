import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;

import '../data/catalog_client.dart';
import '../data/database.dart';
import '../data/legacy_import.dart';
import '../data/local_paths.dart';
import '../data/retired_tokens.dart';
import '../data/game_paths.dart';
import '../data/item_icon_client.dart';
import '../data/live_map_cache.dart';
import '../data/live_map_refresh.dart';
import '../data/raid_panel_ocr.dart';
import '../data/scan_frame_recorder.dart';
import '../data/scan_timing_log.dart';
import '../data/session_log_reader.dart';
import '../domain/catalog.dart';
import '../maps/map_marker_icons.dart';
import '../maps/native_map_scene.dart';
import '../maps/prepared_map_loader.dart';
import 'catalog_controller.dart';
import 'history_controller.dart';
import 'live_map_data_controller.dart';
import 'item_icon_cache.dart';
import 'local_stats_controller.dart';
import 'map_controller.dart';
import 'map_session_controller.dart';
import 'manual_progress_controller.dart';
import 'progress_authority.dart';
import 'raid_lifecycle_controller.dart';
import 'raid_timers_controller.dart';
import 'task_log_progress_controller.dart';
import 'scan_coordinator.dart';
import 'scan_decision_feed.dart';
import 'scan_epoch.dart';
import 'selection_controller.dart';
import 'session_scan_state.dart';
import 'settings_controller.dart';

class AppServices {
  /// Creates the application services and owns their disposal.
  ///
  /// If [scanFrameRecorder] is supplied, these services own and dispose it in
  /// the same way as the default recorder.
  AppServices({
    required this.database,
    required http.Client client,
    DateTime Function()? clock,
    MapController? mapController,
    LiveMapDataController? mapDataController,
    RaidPanelOcr? panelOcr,
    GamePathDiscovery? pathDiscovery,
    Directory? scanLogDirectory,
    Directory? scanFramesDirectory,
    ScanFrameRecorder? scanFrameRecorder,
    ItemIconCache? itemIcons,
    MapMarkerIcons? markerIcons,
    String? scanRuntimeDirectory,
    ScanTemplatesLoader? scanTemplatesLoader,
    ScanCaptureFactory? scanCaptureFactory,
    ScanVisionFactory? scanVisionFactory,
    ScanPlatformFactory? scanPlatformFactory,
    ScanWaiter? scanWaiter,
    Duration scanSettleDelay = const Duration(milliseconds: 50),
    Duration scanFallbackDelay = const Duration(milliseconds: 200),
  }) : _client = client,
       itemIcons = itemIcons ?? ItemIconCache.disabled(),
       markerIcons = markerIcons ?? MapMarkerIcons.disabled() {
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
    // The lifecycle controller subscribes before MapSessionController binds,
    // so the first replay of the session folder reaches it.
    final logReader = SessionLogReader();
    raidLifecycle = RaidLifecycleController(logReader);
    localProgress = TaskLogProgressController(
      store: database,
      wipeStore: database,
      lifecycle: raidLifecycle,
      logRoot: () => logReader.root,
      clock: clock,
    );
    // Before selection and the timers, which read its facts.
    progress = ProgressAuthority(
      access: localProgress,
      modeChanges: catalog,
      mode: () => catalog.mode,
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
    // Also before the first bind: it records cooldown starts from the replay.
    raidTimers = RaidTimersController(
      lifecycle: raidLifecycle,
      settings: settings,
      catalog: catalog,
      progress: progress,
      clock: clock ?? DateTime.now,
    );
    // Also before the first bind: the transitions stream does not buffer.
    localStats = LocalStatsController(
      transitions: raidLifecycle.transitions,
      modeChanges: catalog,
      mode: () => catalog.mode,
      store: database,
      clock: clock ?? DateTime.now,
    );
    mapData =
        mapDataController ??
        LiveMapDataController(
          store: LiveMapCacheStore(database: database),
          fetcher: LiveMapFetcher(client: client, clock: clock),
          publish: maps.publishMarkers,
        );
    mapSession = MapSessionController(
      settings: settings,
      logReader: logReader,
      panelOcr: panelOcr ?? RaidPanelOcr(),
      clock: clock,
      discovery: pathDiscovery,
    );
    manualProgress = ManualProgressController(
      access: localProgress,
      catalog: catalog,
      modeChanges: mapSession,
      effectiveMode: () => mapSession.effectiveMode,
    );
    scanTimingLog = ScanTimingLog(
      scanLogDirectory ??
          Directory('${Directory.systemTemp.path}/blackgrid-scan-logs'),
    );
    this.scanFrameRecorder =
        scanFrameRecorder ??
        ScanFrameRecorder(
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
      templatesLoader: scanTemplatesLoader ?? loadInspectionTemplatesOffUi,
      captureFactory: scanCaptureFactory ?? openDefaultScanCapture,
      visionFactory: scanVisionFactory ?? openDefaultScanVision,
      platformFactory: scanPlatformFactory ?? openDefaultScanPlatform,
      runtimeDirectory: scanRuntimeDirectory,
      waiter: scanWaiter,
      recorder: this.scanFrameRecorder,
      settleDelay: scanSettleDelay,
      fallbackDelay: scanFallbackDelay,
      epoch: _currentEpoch,
    );
    scanFeed = ScanDecisionFeed(
      source: scanner,
      selection: selection,
      catalog: catalog,
      scans: scans,
      epoch: _currentEpoch,
    );
    _appliedSessionEpoch = mapSession.state.sessionEpoch;
    settings.addListener(_syncMapSettings);
    maps.addListener(_syncMapContext);
    mapSession.addListener(_syncMapSession);
  }
  final BlackgridDatabase database;
  final http.Client _client;

  /// Downloads and stores item icons; disabled unless one is passed in.
  final ItemIconCache itemIcons;

  /// Loads the map marker badge icons; disabled unless one is passed in.
  final MapMarkerIcons markerIcons;
  late final SettingsController settings;
  late final MapController maps;
  late final LiveMapDataController mapData;
  late final MapSessionController mapSession;

  /// Folds the session logs into the raid phase; the reader is owned by
  /// [mapSession], which binds and closes it.
  late final RaidLifecycleController raidLifecycle;

  /// Projects the raid timers for the shell strip and records scav cooldown
  /// starts as raids end.
  late final RaidTimersController raidTimers;

  /// Stores raids and flea sales as the lifecycle publishes them and serves
  /// the Stats dialog.
  late final LocalStatsController localStats;

  /// Records log task transitions into active local progress wipes.
  late final TaskLogProgressController localProgress;

  /// Owns the mounted Settings projection and manual local-progress edits.
  late final ManualProgressController manualProgress;

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

  /// Publishes the applied mode's local progress facts to advice and timers.
  late final ProgressAuthority progress;
  late final SelectionController selection;
  late final LegacyImport importer;
  final scans = SessionScanState();
  bool _disposed = false;
  int _modeTransition = 0;
  Future<void> _automaticRefreshes = Future.value();

  /// Completes when the latest mode selection's background work has finished.
  ///
  /// The work is the catalog's `setMode` call and the catalog refresh started
  /// after it. A selection that starts no refresh completes right after its
  /// `setMode` call. Each selection gets its own
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
    // Start-up never waits on it; it swallows its own errors.
    unawaited(deleteRetiredTokens(paths));
    final database = BlackgridDatabase.open(paths.database);
    final client = http.Client();
    final result = AppServices(
      database: database,
      client: client,
      itemIcons: await _openItemIcons(paths, database, client),
      markerIcons: MapMarkerIcons(),
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

  /// Builds the real icon cache, or the disabled one when the folder cannot
  /// be created, so a cosmetic feature never fails start-up.
  static Future<ItemIconCache> _openItemIcons(
    LocalPaths paths,
    BlackgridDatabase database,
    http.Client client,
  ) async {
    try {
      await paths.itemIcons.create(recursive: true);
    } on FileSystemException catch (error) {
      debugPrint('Item icons disabled: cannot create folder ($error)');
      return ItemIconCache.disabled();
    }
    return ItemIconCache(
      database: database,
      client: ItemIconClient(client: client),
      directory: paths.itemIcons,
    );
  }

  Future<void> initialize() async {
    await itemIcons.open();
    // Cosmetic and never throws: start-up does not wait for the badge glyphs.
    unawaited(markerIcons.open());
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
    mapSession.updateMapContext(
      maps.preparedMap,
      generation,
      activeMarkers: maps.activeMarkers,
    );
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
      unawaited(_selectLiveMapMode(mode));
      _appliedMode = mode;
      ++_modeTransition;
      epochChanged = true;
      // Both invalidate synchronously, before either asynchronous read ends.
      final transition = _modeTransition;
      final catalogReady = catalog.setMode(mode);
      _modeChange = catalogReady;
      // The refresh is never part of _modeChange: startup and a switch must
      // not wait on the network.
      final catalogRefresh = _refreshAfter(
        catalogReady,
        transition,
        mode,
        catalog.refresh,
        when: () => catalog.status != CatalogStatus.current,
      );
      _automaticRefreshes = catalogRefresh.then((_) {}, onError: (Object _) {});
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

  Future<void> _selectLiveMapMode([GameMode? selected]) async {
    final mode = selected ?? mapSession.effectiveMode;
    final pack = maps.pack;
    final failure =
        maps.packLoadFailure ??
        (maps.unavailable
            ? StateError('The active prepared map is unavailable.')
            : null);
    await mapData.selectMode(mode: mode, pack: pack, packFailure: failure);
  }

  /// Performs the separate map-data refresh action.
  Future<void> refreshMapData() => mapData.refresh();

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
    manualProgress.dispose();
    settings.removeListener(_syncMapSettings);
    maps.removeListener(_syncMapContext);
    mapSession.removeListener(_syncMapSession);
    await mapData.close();
    mapData.dispose();
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
      // Consumers before the authority they listen to, the authority before
      // the sources it listens to. After mapSession.close() has closed the
      // reader the timers listen to.
      raidTimers.dispose();
      selection.dispose();
      progress.dispose();
      await localProgress.close();
      localProgress.dispose();
      localStats.dispose();
      raidLifecycle.dispose();
      scans.dispose();
      catalog.dispose();
      maps.dispose();
      markerIcons.dispose();
      settings.dispose();
      history.dispose();
      try {
        await itemIcons.dispose();
      } finally {
        _client.close();
        await database.close();
      }
    }
  }
}
