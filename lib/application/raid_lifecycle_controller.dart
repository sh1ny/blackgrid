import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/session_log_reader.dart';
import '../domain/raid_lifecycle.dart';

/// Folds the log reader's events into the raid lifecycle state.
///
/// Subscribes to [SessionLogReader.events] in its constructor, so a controller
/// built before the first bind sees the replay of the whole session folder.
/// The reader stays owned by whoever binds and closes it.
class RaidLifecycleController extends ChangeNotifier {
  /// Starts listening to [reader].
  RaidLifecycleController(SessionLogReader reader) {
    _subscription = reader.events.listen(_onBatch);
  }

  late final StreamSubscription<List<GameLogEvent>> _subscription;
  final StreamController<RaidTransition> _transitions =
      StreamController<RaidTransition>.broadcast(sync: true);
  RaidLifecycleState _state = RaidLifecycleState.initial;
  bool _disposed = false;

  /// The state after the last event read.
  RaidLifecycleState get state => _state;

  /// Each transition, published once, in the order the events were read.
  Stream<RaidTransition> get transitions => _transitions.stream;

  void _onBatch(List<GameLogEvent> batch) {
    if (_disposed) return;
    final published = <RaidTransition>[];
    for (final event in batch) {
      final (next, transitions) = reduce(_state, event);
      _state = next;
      published.addAll(transitions);
    }
    notifyListeners();
    published.forEach(_transitions.add);
  }

  /// Stops listening to the reader and closes [transitions].
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription.cancel());
    unawaited(_transitions.close());
    super.dispose();
  }
}
