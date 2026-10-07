import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/game_paths.dart';
import '../data/raid_panel_ocr.dart';
import '../data/screenshot_directory_watcher.dart';
import '../data/session_log_reader.dart';
import '../domain/catalog.dart';
import '../domain/map_session.dart';
import '../domain/raid_exfil_matcher.dart';
import '../domain/raid_panel_text_parser.dart';
import '../domain/screenshot_filename.dart';
import '../domain/settings.dart';
import '../maps/prepared_map.dart';
import 'settings_controller.dart';

/// The sole ephemeral selection/evidence authority. No Scanner collaborator.
class MapSessionController extends ChangeNotifier {
  MapSessionController({
    required this.settings,
    RaidPanelOcr? panelOcr,
    DateTime Function()? clock,
    SessionLogReader? logReader,
    ScreenshotDirectoryWatcher? screenshotWatcher,
    Future<RaidPanelEvidence> Function(Uint8List)? recognize,
    this._discovery,
  }) : _panelOcr = panelOcr,
       _clock = clock ?? DateTime.now,
       _logs = logReader ?? SessionLogReader(),
       _screenshots = screenshotWatcher ?? ScreenshotDirectoryWatcher(),
       _recognize = recognize ?? panelOcr?.recognize;
  final SettingsController settings;
  final RaidPanelOcr? _panelOcr;
  final DateTime Function() _clock;
  final SessionLogReader _logs;
  final ScreenshotDirectoryWatcher _screenshots;
  final Future<RaidPanelEvidence> Function(Uint8List)? _recognize;

  /// Locates unconfigured inputs; null keeps empty settings disabled.
  final GamePathDiscovery? _discovery;
  String _logDirectory = '';
  String _screenshotDirectory = '';
  SessionLogState _log = const SessionLogState();
  MapInputStatus _screenshotStatus = MapInputStatus.disabled;
  String? _screenshotMessage;
  MapPlayerSample? _sample;
  bool _assumedAssociation = false;
  String? _savedPath;
  DateTime? _savedModifiedAt;
  RaidPanelEvidence? _evidence;
  Set<String> _highlights = const {};
  PreparedMap? _map;
  RaidExfilMatcher? _matcher;
  int _contentGeneration = -1;
  int _epoch = 0;
  int _context = 0;
  int _order = 0;
  DateTime? _contextStarted;
  AppSettings? _preferences;
  bool _initialized = false;
  bool _closed = false;
  bool _readingLatest = false;
  StreamSubscription<SessionLogState>? _logSubscription;
  StreamSubscription<SavedScreenshot>? _screenshotSubscription;
  StreamSubscription<(MapInputStatus, String?)>? _statusSubscription;
  Future<void> _binding = Future.value();
  Future<void>? _active;
  Future<void>? _closing;
  Future<void>? _initializing;
  _ScreenshotRequest? _pending;

  String get effectiveMapId =>
      settings.settings.followGameLogs && _log.detectedMapId != null
      ? _log.detectedMapId!
      : settings.settings.selectedMap;
  GameMode get effectiveMode => _log.detectedMode != GameMode.unknown
      ? _log.detectedMode
      : settings.settings.mode;
  bool get _disagreement =>
      _log.detectedMapId != null && _log.detectedMapId != effectiveMapId;
  bool get _waitingForLogContext =>
      _log.detectedMapId == null ||
      _log.sessionId == null ||
      _log.status != MapInputStatus.watching;
  MapSessionState get state => MapSessionState(
    effectiveMapId: effectiveMapId,
    effectiveMode: effectiveMode,
    followGameLogs: settings.settings.followGameLogs,
    detectedMapId: _log.detectedMapId,
    detectedMode: _log.detectedMode,
    sessionEpoch: _epoch,
    sessionId: _log.sessionId,
    logStatus: _log.status,
    logDirectory: _logDirectory,
    logDirectoryDetected:
        _logDirectory.isNotEmpty && settings.settings.gameLogDirectory.isEmpty,
    screenshotDirectory: _screenshotDirectory,
    screenshotDirectoryDetected:
        _screenshotDirectory.isNotEmpty &&
        settings.settings.screenshotDirectory.isEmpty,
    screenshotStatus: _screenshotStatus,
    logMessage: _log.message,
    screenshotMessage: _disagreement
        ? '${_screenshotMessage == null ? '' : '$_screenshotMessage '}Detected map differs from the selected map; watched screenshots are ignored. Read Latest can apply a saved sample to the selected map as assumed evidence.'
        : _screenshotMessage,
    playerSample: _sample,
    raidEvidence: _evidence,
    raidHighlightIds: _highlights,
    mapDisagreement: _disagreement,
    readingLatest: _readingLatest,
    assumedAssociation: _assumedAssociation,
    savedScreenshotPath: _savedPath,
    savedScreenshotModifiedAt: _savedModifiedAt,
    processingScreenshot: _active != null,
    pendingScreenshotPath: _pending?.saved.path,
  );

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (_closed || _initialized) return;
    _initialized = true;
    _logSubscription = _logs.states.listen(_onLog);
    // Without log context, watched samples are labeled assumed. A known map
    // disagreement requires the explicit Read Latest association instead.
    _screenshotSubscription = _screenshots.screenshots.listen((saved) {
      if (_closed ||
          _disagreement ||
          (_contextStarted != null &&
              !saved.modifiedAt.isAfter(_contextStarted!))) {
        return;
      }
      _readingLatest = false;
      _enqueue(
        saved,
        assumed: _waitingForLogContext,
        order: ++_order,
        context: _context,
      );
    });
    _statusSubscription = _screenshots.statuses.listen((status) {
      if (_closed) return;
      _screenshotStatus = status.$1;
      _screenshotMessage = status.$2;
      notifyListeners();
    });
    settings.addListener(_onPreferences);
    _onPreferences();
    await _binding;
  }

  void _invalidate() {
    ++_context;
    ++_order;
    _contextStarted = _clock();
    _readingLatest = false;
    _sample = null;
    _assumedAssociation = false;
    _savedPath = null;
    _savedModifiedAt = null;
    _evidence = null;
    _highlights = const {};
    _pending?.complete();
    _pending = null;
  }

  void _onPreferences() {
    if (_closed) return;
    final next = settings.settings;
    final previous = _preferences;
    _preferences = next;
    final logChanged =
        previous == null || previous.gameLogDirectory != next.gameLogDirectory;
    final screenshotsChanged =
        previous == null ||
        previous.screenshotDirectory != next.screenshotDirectory;
    if (previous == null ||
        previous.selectedMap != next.selectedMap ||
        previous.followGameLogs != next.followGameLogs ||
        logChanged ||
        screenshotsChanged) {
      _invalidate();
    }
    if (logChanged) {
      _log = const SessionLogState();
      ++_epoch;
    }
    if (logChanged || screenshotsChanged) {
      _binding = _binding.then((_) async {
        if (_closed) return;
        // Each input reports its own bind failure; a throw here would also
        // poison every later bind and shutdown awaiting this chain.
        if (logChanged && _unchanged(next, (p) => p.gameLogDirectory)) {
          try {
            final root = next.gameLogDirectory.isNotEmpty
                ? next.gameLogDirectory
                : await _discovery?.logs() ?? '';
            if (_unchanged(next, (p) => p.gameLogDirectory)) {
              _logDirectory = root;
              notifyListeners();
              await _logs.bind(root);
            }
          } catch (error) {
            if (!_closed) {
              _onLog(
                SessionLogState(
                  status: MapInputStatus.error,
                  message: 'Log input could not be bound: $error',
                ),
              );
            }
          }
        }
        if (screenshotsChanged &&
            _unchanged(next, (p) => p.screenshotDirectory)) {
          try {
            final directory = next.screenshotDirectory.isNotEmpty
                ? next.screenshotDirectory
                : await _discovery?.screenshots() ?? '';
            if (_unchanged(next, (p) => p.screenshotDirectory)) {
              _screenshotDirectory = directory;
              notifyListeners();
              await _screenshots.bind(directory);
            }
          } catch (error) {
            if (!_closed) {
              _screenshotStatus = MapInputStatus.error;
              _screenshotMessage =
                  'Screenshot input could not be bound: $error';
              notifyListeners();
            }
          }
        }
      });
    }
    notifyListeners();
  }

  /// Whether [input] still has the value it had in [next].
  bool _unchanged(AppSettings next, String Function(AppSettings) input) =>
      !_closed && _preferences != null && input(_preferences!) == input(next);

  void _onLog(SessionLogState log) {
    if (_closed) return;
    final oldMap = effectiveMapId;
    final oldDisagreement = _disagreement;
    final sessionChanged =
        log.sessionId != _log.sessionId || log.incarnation != _log.incarnation;
    final detectionChanged = log.detectedMapId != _log.detectedMapId;
    final modeChanged = log.detectedMode != _log.detectedMode;
    _log = log;
    if (sessionChanged) ++_epoch;
    // An error with unchanged session, map and mode is transient (sharing
    // violation, rejected record): it stays visible but keeps the evidence.
    if (sessionChanged ||
        detectionChanged ||
        modeChanged ||
        oldMap != effectiveMapId ||
        oldDisagreement != _disagreement ||
        log.status == MapInputStatus.unavailable ||
        log.status == MapInputStatus.missing) {
      _invalidate();
    }
    notifyListeners();
  }

  void updateMapContext(PreparedMap? map, int contentGeneration) {
    if (_closed ||
        (identical(_map, map) && _contentGeneration == contentGeneration)) {
      return;
    }
    if (!identical(_map, map)) {
      _matcher = map == null
          ? null
          : RaidExfilMatcher([
              for (final marker in map.markers)
                if (marker.category == 'extracts' ||
                    marker.category == 'transits')
                  RaidExitIdentity(
                    id: marker.id,
                    name: marker.name,
                    transit: marker.category == 'transits',
                    aliases:
                        (marker.details['aliases'] as List?)
                            ?.whereType<String>()
                            .toList() ??
                        const [],
                  ),
            ]);
    }
    _map = map;
    _contentGeneration = contentGeneration;
    _invalidate();
    notifyListeners();
  }

  Future<void> readLatest() async {
    if (_closed) return;
    final order = ++_order;
    final context = _context;
    _readingLatest = true;
    notifyListeners();
    try {
      await _binding;
      final saved = await _screenshots.readLatest();
      if (_closed || order != _order || context != _context || saved == null) {
        return;
      }
      await _enqueue(saved, assumed: true, order: order, context: context);
    } finally {
      if (!_closed && order == _order) {
        _readingLatest = false;
        notifyListeners();
      }
    }
  }

  Future<void> _enqueue(
    SavedScreenshot saved, {
    required bool assumed,
    required int order,
    required int context,
  }) {
    final request = _ScreenshotRequest(
      saved,
      assumed,
      order,
      context,
      _epoch,
      _contentGeneration,
    );
    if (_active != null) {
      _pending?.complete();
      _pending = request;
      notifyListeners();
    } else {
      _start(request);
    }
    return request.done.future;
  }

  bool _current(_ScreenshotRequest request) =>
      !_closed &&
      request.context == _context &&
      request.order == _order &&
      request.epoch == _epoch &&
      request.contentGeneration == _contentGeneration;

  void _start(_ScreenshotRequest request) {
    _active = _process(request).whenComplete(() {
      request.complete();
      _active = null;
      final next = _pending;
      _pending = null;
      if (next != null && !_closed) {
        _start(next);
      } else {
        next?.complete();
      }
      if (!_closed) notifyListeners();
    });
    if (!_closed) notifyListeners();
  }

  Future<void> _process(_ScreenshotRequest request) async {
    if (!_current(request)) return;
    final metadata = parseScreenshotFilename(request.saved.path);
    _assumedAssociation = request.assumed;
    _savedPath = request.saved.path;
    _savedModifiedAt = request.saved.modifiedAt;
    _sample = metadata == null
        ? null
        : MapPlayerSample(
            metadata: metadata,
            path: request.saved.path,
            modifiedAt: request.saved.modifiedAt,
            observedAt: _clock(),
            assumedAssociation: request.assumed,
            sessionEpoch: _epoch,
          );
    _screenshotStatus = MapInputStatus.reading;
    _screenshotMessage = metadata == null
        ? 'Saved screenshot has no supported position metadata.'
        : request.assumed
        ? 'Saved sample assumed associated with the selected map; not proof of a live raid.'
        : null;
    notifyListeners();
    try {
      await _recognizePanel(request);
    } finally {
      // A superseded job must not leave its reading state or sample message.
      if (_screenshotStatus == MapInputStatus.reading) {
        _screenshotStatus = MapInputStatus.watching;
        if (!_current(request)) _screenshotMessage = null;
        if (!_closed) notifyListeners();
      }
    }
  }

  Future<void> _recognizePanel(_ScreenshotRequest request) async {
    if (!_current(request)) return;
    RaidPanelEvidence evidence;
    try {
      evidence = _recognize == null
          ? RaidPanelEvidence(
              state: RaidPanelState.unavailable,
              message: 'Saved-panel OCR is unavailable.',
            )
          : await _recognize(request.saved.bytes);
    } catch (error) {
      evidence = RaidPanelEvidence(
        state: RaidPanelState.error,
        message: 'Saved-panel recognition failed: $error',
      );
    }
    if (!_current(request)) return;
    final map = _map;
    _evidence = evidence;
    if (map != null && map.id == effectiveMapId) {
      final result = _matcher!.match(evidence);
      _evidence = RaidPanelEvidence(
        state: result.state,
        extractNames: evidence.extractNames,
        transitNames: evidence.transitNames,
        message: result.message ?? evidence.message,
        panel: evidence.panel,
        rawText: evidence.rawText,
      );
      if (result.state == RaidPanelState.recognized ||
          result.state == RaidPanelState.empty) {
        _highlights = Set.unmodifiable(result.ids);
      }
    }
  }

  /// Stop ingress, fence publications, then drain OCR before freeing its owner.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _invalidate();
    settings.removeListener(_onPreferences);
    await _logSubscription?.cancel();
    await _screenshotSubscription?.cancel();
    await _statusSubscription?.cancel();
    try {
      await _binding;
      await _logs.close();
      await _screenshots.close();
      await _active;
      await _panelOcr?.close();
    } finally {
      super.dispose();
    }
  }
}

class _ScreenshotRequest {
  _ScreenshotRequest(
    this.saved,
    this.assumed,
    this.order,
    this.context,
    this.epoch,
    this.contentGeneration,
  );
  final SavedScreenshot saved;
  final bool assumed;
  final int order;
  final int context;
  final int epoch;
  final int contentGeneration;
  final Completer<void> done = Completer<void>();
  void complete() {
    if (!done.isCompleted) done.complete();
  }
}
