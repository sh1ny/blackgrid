import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';
import '../domain/local_progress.dart';
import '../domain/local_progress_store.dart';
import '../domain/progress_wipe_store.dart';

/// A consistent projection of one mode's active local progress cycle.
final class LocalProgressSnapshot {
  /// Creates a snapshot with an immutable copy of its winning events.
  LocalProgressSnapshot({
    required this.scope,
    required Map<ProgressTarget, ProgressEvent> winners,
  }) : winners = Map.unmodifiable(winners);

  /// The active cycle, or `null` when the mode has no wipe.
  final ProgressScope? scope;

  /// The winning event for each known register, including unset values.
  final Map<ProgressTarget, ProgressEvent> winners;
}

/// Serialized access to active local progress and manual edits.
abstract interface class LocalProgressAccess implements Listenable {
  /// Whether active wipes and the local device identity loaded successfully.
  bool get loaded;

  /// The initial load failure, or `null` when initialization did not fail.
  String? get loadError;

  /// A notification counter for changes to progress data or availability.
  int get progressRevision;

  /// The active wipe for each mode.
  Map<GameMode, ProgressWipe> get wipes;

  /// Modes whose active cycles are unavailable.
  Set<GameMode> get unavailableModes;

  /// Appends a manual event to the active wipe of [mode].
  Future<ProgressResult<ProgressEvent>> appendManual(
    GameMode mode,
    ProgressTarget target,
    ProgressValue value,
  );

  /// Compensates a current manual edit in the named active cycle.
  Future<ProgressResult<ProgressEvent>> undo(
    GameMode mode,
    String cycleId,
    String targetEventId,
  );

  /// Reapplies the value removed by a current compensation as a new edit.
  Future<ProgressResult<ProgressEvent>> redo(
    GameMode mode,
    String cycleId,
    String undoEventId,
  );

  /// Reads all current winners of the active wipe for [mode].
  Future<ProgressResult<LocalProgressSnapshot>> readCurrent(GameMode mode);
}
