import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';
import '../domain/local_stats.dart';
import '../domain/raid_lifecycle.dart';

/// Shown until the next successful totals read.
const localStatsReadErrorMessage = 'Stats could not be read.';

/// Shown until the next successful insert.
const localStatsWriteErrorMessage = 'Some raids or sales could not be saved.';

/// Shown until the next successful clear or [LocalStatsController.dismissClearError].
const localStatsClearErrorMessage = 'Stats could not be cleared.';

/// Stores raids and flea sales as the lifecycle publishes them and serves the
/// active mode's totals to the Stats dialog.
///
/// Every insert and the clear run one at a time, in publication order. After a
/// write, a clear or a mode change the active mode's totals are reloaded;
/// reloads coalesce so at most one is pending behind the running one. Read,
/// write and clear failures each keep their own message, and no failure stops
/// the queue or escapes as an uncaught error.
class LocalStatsController extends ChangeNotifier {
  /// Subscribes to [transitions] and, when the mode is known, loads totals.
  ///
  /// [mode] reads the app's current mode and [modeChanges] notifies when it may
  /// have changed. [clock] supplies the clear time. Subscribes here, so a
  /// controller built before the log reader binds sees the replay.
  LocalStatsController({
    required Stream<RaidTransition> transitions,
    required this._modeChanges,
    required this._mode,
    required this._store,
    required this._clock,
  }) {
    _lastMode = _mode();
    _subscription = transitions.listen(_onTransition);
    _modeChanges.addListener(_onModeChanged);
    if (modeKnown) _requestReload();
  }

  final Listenable _modeChanges;
  final GameMode Function() _mode;
  final LocalStatsStore _store;
  final DateTime Function() _clock;
  late final StreamSubscription<RaidTransition> _subscription;
  late GameMode _lastMode;
  Future<void> _tail = Future<void>.value();
  bool _reloading = false;
  bool _reloadAgain = false;
  bool _disposed = false;
  LocalStatsTotals _totals = LocalStatsTotals.empty;
  DateTime? _since;
  String? _readError;
  String? _writeError;
  String? _clearError;

  /// The active mode's totals; empty while the mode is unknown.
  LocalStatsTotals get totals => _totals;

  /// When the stats were last cleared, or `null` when they never were.
  DateTime? get since => _since;

  /// The app's current mode, which [totals] belong to when it is known.
  GameMode get mode => _mode();

  /// Whether the app's mode is known, so [totals] belong to a mode.
  bool get modeKnown => mode != GameMode.unknown;

  /// The message for a failed totals read, until the next successful read.
  String? get readError => _readError;

  /// The message for a failed insert, until the next successful insert.
  String? get writeError => _writeError;

  /// The message for a failed clear, until the next successful clear or
  /// [dismissClearError].
  String? get clearError => _clearError;

  /// Removes the clear message, as when the dialog closes.
  void dismissClearError() {
    if (_clearError == null) return;
    _clearError = null;
    _notify();
  }

  /// Queues a clear behind the writes already published.
  ///
  /// The returned future completes when the clear has run, whether or not it
  /// succeeded. A failure sets [clearError] and leaves the stored stats and
  /// [since] as they were. Does nothing after disposal.
  Future<void> clear() => _enqueue(() async {
    try {
      await _store.clear(_clock());
      _clearError = null;
    } catch (_) {
      _clearError = localStatsClearErrorMessage;
    }
    _notify();
    _requestReload();
  });

  void _onTransition(RaidTransition transition) {
    switch (transition) {
      case RaidStartedTransition(:final id, :final time, :final raid):
        final row = RaidStatRow(
          id: id,
          mode: raid.mode,
          mapId: raid.mapId,
          start: time,
          entry: raid.entry,
        );
        unawaited(_enqueueWrite(() => _store.recordRaid(row)));
      case FleaSoldTransition(
        :final id,
        :final time,
        :final itemId,
        :final count,
        :final roubles,
        :final mode,
      ):
        final row = FleaSaleRow(
          id: id,
          mode: mode,
          time: time,
          itemId: itemId,
          count: count,
          roubles: roubles,
        );
        unawaited(_enqueueWrite(() => _store.recordSale(row)));
      case RaidEndedTransition() || MatchingAbortedTransition():
        break;
    }
  }

  Future<void> _enqueueWrite(Future<void> Function() write) =>
      _enqueue(() async {
        try {
          await write();
          _writeError = null;
        } catch (_) {
          _writeError = localStatsWriteErrorMessage;
        }
        _notify();
        _requestReload();
      });

  /// Chains [job] after every earlier job; it never runs once disposed.
  Future<void> _enqueue(Future<void> Function() job) {
    if (_disposed) return Future<void>.value();
    final next = _tail.then((_) {
      if (!_disposed) return job();
    });
    _tail = next;
    return next;
  }

  void _onModeChanged() {
    if (_disposed) return;
    final mode = _mode();
    if (mode == _lastMode) return;
    _lastMode = mode;
    _requestReload();
  }

  void _requestReload() {
    if (_disposed) return;
    if (_reloading) {
      _reloadAgain = true;
      return;
    }
    _reloading = true;
    unawaited(_reloadLoop());
  }

  Future<void> _reloadLoop() async {
    try {
      do {
        _reloadAgain = false;
        await _reloadOnce();
      } while (_reloadAgain && !_disposed);
    } finally {
      _reloading = false;
    }
  }

  Future<void> _reloadOnce() async {
    final mode = _mode();
    if (mode == GameMode.unknown) {
      _totals = LocalStatsTotals.empty;
      _notify();
      return;
    }
    try {
      final totals = await _store.readTotals(mode);
      final since = await _store.readSince();
      if (_disposed) return;
      _totals = totals;
      _since = since;
      _readError = null;
    } catch (_) {
      _readError = localStatsReadErrorMessage;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Stops reloading and notifying, drops queued work and cancels listening.
  ///
  /// A store call already running finishes. Safe to call more than once.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription.cancel());
    _modeChanges.removeListener(_onModeChanged);
    super.dispose();
  }
}
