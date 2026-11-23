import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/session_log_reader.dart';
import '../domain/raid_lifecycle.dart';
import 'raid_timers_controller.dart';

/// Folds the log reader's events into the raid lifecycle state.
///
/// Subscribes to [SessionLogReader.eventBatches] in its constructor, so a
/// controller built before the first bind sees the whole session folder replay.
/// The reader stays owned by whoever binds and closes it.
class RaidLifecycleController extends ChangeNotifier
    implements RaidTimerLifecycleSource {
  /// Starts listening to [reader].
  RaidLifecycleController(SessionLogReader reader) {
    _subscription = reader.eventBatches.listen(_onBatch);
  }

  late final StreamSubscription<SessionLogBatch> _subscription;
  final StreamController<RaidTransition> _transitions =
      StreamController<RaidTransition>.broadcast(sync: true);
  final StreamController<RaidTransition> _cleanupTransitions =
      StreamController<RaidTransition>.broadcast(sync: true);
  RaidLifecycleState _state = RaidLifecycleState.initial;
  LogRecordId? _cleanupStart;
  bool _pendingStartLive = false;
  bool _restartProfileLive = false;
  bool _disposed = false;

  /// The state after the last event read.
  @override
  RaidLifecycleState get state => _state;

  /// Each transition, published once, in the order the events were read.
  @override
  Stream<RaidTransition> get transitions => _transitions.stream;

  /// Eligible live raid endings, with the publishing queue after a crash.
  Stream<RaidTransition> get cleanupTransitions => _cleanupTransitions.stream;

  void _onBatch(SessionLogBatch batch) {
    if (_disposed) return;
    final published = <RaidTransition>[];
    List<RaidTransition>? cleanup;
    for (final event in batch.events) {
      final before = _state;
      final (next, transitions) = reduce(before, event);
      _state = next;
      published.addAll(transitions);

      final live =
          event is RecordedGameLogEvent && batch.liveIds.contains(event.id);
      if (event is LogInputReset) _cleanupStart = null;
      var crashAdmitted = false;
      for (final transition in transitions) {
        switch (transition) {
          case RaidStartedTransition(:final raid):
            _cleanupStart =
                raid.entry != RaidEntry.reconnect &&
                    live &&
                    event is RaidStarted &&
                    (raid.startId == event.id || _pendingStartLive)
                ? raid.startId
                : null;
          case RaidEndedTransition(:final raid, :final cause)
              when raid.startId == _cleanupStart:
            _cleanupStart = null;
            if (!live) break;
            if (cause == RaidEndCause.clientRestart) {
              if (!_restartProfileLive) break;
              crashAdmitted = true;
            }
            (cleanup ??= []).add(transition);
          case QueueEnteredTransition() when crashAdmitted:
            (cleanup ??= []).add(transition);
          default:
            break;
        }
      }

      // Keep provenance only for the records the reducer itself still holds.
      if (next.pendingStart != before.pendingStart) {
        _pendingStartLive = next.pendingStart != null && live;
      }
      if (next.restartProfile != before.restartProfile) {
        _restartProfileLive = next.restartProfile != null && live;
      }
    }
    notifyListeners();
    published.forEach(_transitions.add);
    cleanup?.forEach(_cleanupTransitions.add);
  }

  /// Stops listening to the reader and closes both transition streams.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription.cancel());
    unawaited(_transitions.close());
    unawaited(_cleanupTransitions.close());
    super.dispose();
  }
}
