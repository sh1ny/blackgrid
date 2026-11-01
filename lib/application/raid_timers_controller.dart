import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';
import '../domain/progress.dart';
import '../domain/raid_lifecycle.dart';
import '../domain/raid_timers.dart';
import '../domain/settings.dart';

/// What [RaidTimersController] reads from the raid lifecycle.
///
/// [RaidLifecycleController] is the real source.
abstract interface class RaidTimerLifecycleSource implements Listenable {
  /// The state after the last event read.
  RaidLifecycleState get state;

  /// Each lifecycle transition, published once, synchronously.
  Stream<RaidTransition> get transitions;
}

/// What [RaidTimersController] reads from and writes to the settings.
///
/// [SettingsController] is the real source.
abstract interface class RaidTimerSettingsSource implements Listenable {
  /// The timer settings.
  RaidTimerSettings get raidTimers;

  /// The cooldown starts in effect, including starts not yet saved.
  Map<GameMode, DateTime> get effectiveScavCooldownStarts;

  /// Records the start of [mode]'s scav cooldown; the source never moves a
  /// start back.
  Future<void> recordScavCooldownStart(GameMode mode, DateTime start);
}

/// What [RaidTimersController] reads from the catalog.
///
/// [CatalogController] is the real source.
abstract interface class RaidTimerCatalogSource implements Listenable {
  /// The app's effective mode, as the logs and settings settled it.
  GameMode get mode;

  /// The item data, which may still belong to an earlier mode.
  CatalogSnapshot? get snapshot;
}

/// What [RaidTimersController] reads from the Tracker progress.
///
/// [ProgressController] is the real source.
abstract interface class RaidTimerProgressSource implements Listenable {
  /// The mode the progress is loaded for.
  GameMode get mode;

  /// The progress, which may still belong to an earlier mode.
  ProgressSnapshot? get snapshot;
}

/// Projects the raid timers for the shell strip and records scav cooldown
/// starts when raids end.
///
/// Recomputes [view] whenever the lifecycle, settings, catalog or progress
/// change, and on a periodic tick that runs only while [RaidTimersView.moving].
/// Every recomputation reads the clock afresh, so a missed tick never drifts.
/// The active mode is the catalog's mode, never the saved setting.
class RaidTimersController extends ChangeNotifier {
  /// Starts listening to the sources and computes the first [view].
  ///
  /// [clock] supplies the current time; [tick] is the update period while a
  /// timer is counting. Subscribes to [lifecycle]'s transitions here, so a
  /// controller built before the log reader binds sees the replay.
  RaidTimersController({
    required this._lifecycle,
    required this._settings,
    required this._catalog,
    required this._progress,
    required this._clock,
    this._tick = const Duration(seconds: 1),
  }) {
    _subscription = _lifecycle.transitions.listen(_onTransition);
    for (final source in _sources) {
      source.addListener(_recompute);
    }
    _view = _project();
    _syncTimer();
  }

  final RaidTimerLifecycleSource _lifecycle;
  final RaidTimerSettingsSource _settings;
  final RaidTimerCatalogSource _catalog;
  final RaidTimerProgressSource _progress;
  final DateTime Function() _clock;
  final Duration _tick;
  late final StreamSubscription<RaidTransition> _subscription;
  late RaidTimersView _view;
  Timer? _timer;
  bool _disposed = false;

  List<Listenable> get _sources => [_lifecycle, _settings, _catalog, _progress];

  /// What the strip shows now.
  RaidTimersView get view => _view;

  void _onTransition(RaidTransition transition) {
    switch (transition) {
      case RaidEndedTransition(:final raid):
        _recordStart(raid);
      case RaidStartedTransition() || MatchingAbortedTransition():
        break;
    }
  }

  void _recordStart(Raid raid) {
    final mode = raid.mode;
    final end = raid.endTime;
    if (mode == null || mode == GameMode.unknown || end == null) return;
    if (!countsAsScavRaid(raid)) return;
    unawaited(_settings.recordScavCooldownStart(mode, end));
  }

  RaidTimersView _project() {
    final mode = _catalog.mode;
    final snapshot = _catalog.snapshot;
    final progress = _progress.mode == mode ? _progress.snapshot : null;
    return raidTimersView(
      now: _clock(),
      lifecycle: _lifecycle.state,
      settings: _settings.raidTimers,
      activeMode: mode,
      cooldownStarts: _settings.effectiveScavCooldownStarts,
      inputs: snapshot != null && snapshot.mode == mode
          ? snapshot.scavCooldown
          : null,
      progress: progress,
    );
  }

  void _recompute() {
    if (_disposed) return;
    _view = _project();
    _syncTimer();
    notifyListeners();
  }

  /// Keeps exactly one periodic timer while the view moves, none otherwise.
  void _syncTimer() {
    if (_view.moving) {
      _timer ??= Timer.periodic(_tick, (_) => _recompute());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Stops the timer, the transition subscription and all listening.
  ///
  /// Safe to call more than once.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_subscription.cancel());
    for (final source in _sources) {
      source.removeListener(_recompute);
    }
    super.dispose();
  }
}
