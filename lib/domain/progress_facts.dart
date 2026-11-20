import 'catalog.dart';
import 'local_progress.dart';

/// The local progress facts advice and timers read for one game mode.
///
/// Lookups return the defaults for unrecorded facts: a task with no state is
/// not started, an objective with no count is 0 and not done, and a station
/// with no level is level 0. The player's [level], [faction] and [edition]
/// stay `null` when unset.
final class ProgressFacts {
  /// Creates facts for [mode], copying every supplied collection.
  ProgressFacts({
    required this.mode,
    Map<String, ProgressTaskStatus> taskStates = const {},
    Map<String, int> objectiveCounts = const {},
    Set<String> objectivesComplete = const {},
    Map<String, int> stationLevels = const {},
    this.level,
    this.faction,
    this.edition,
  }) : _taskStates = Map.unmodifiable(taskStates),
       _objectiveCounts = Map.unmodifiable(objectiveCounts),
       _objectivesComplete = Set.unmodifiable(objectivesComplete),
       _stationLevels = Map.unmodifiable(stationLevels);

  /// Builds the facts of [mode] from the winning event of each register.
  ///
  /// An explicit unset value leaves the default, as an absent register does.
  /// The faction is upper-cased to `BEAR` or `USEC`. Trader loyalty is not
  /// used by advice and is skipped.
  factory ProgressFacts.fromWinners(
    GameMode mode,
    Map<ProgressTarget, ProgressEvent> winners,
  ) {
    final tasks = <String, ProgressTaskStatus>{};
    final counts = <String, int>{};
    final complete = <String>{};
    final stations = <String, int>{};
    int? level;
    String? faction;
    String? edition;
    for (final MapEntry(key: target, value: event) in winners.entries) {
      final value = event.value;
      switch ((target.kind, target.field, value)) {
        case (
          ProgressEntityKind.task,
          ProgressField.state,
          ProgressTaskState(value: final status),
        ):
          tasks[target.id] = status;
        case (
          ProgressEntityKind.objective,
          ProgressField.count,
          ProgressInteger(value: final count),
        ):
          counts[target.id] = count;
        case (
          ProgressEntityKind.objective,
          ProgressField.complete,
          ProgressBoolean(value: true),
        ):
          complete.add(target.id);
        case (
          ProgressEntityKind.station,
          ProgressField.level,
          ProgressInteger(value: final built),
        ):
          stations[target.id] = built;
        case (
          ProgressEntityKind.player,
          ProgressField.level,
          ProgressInteger(value: final recorded),
        ):
          level = recorded;
        case (
          ProgressEntityKind.player,
          ProgressField.faction,
          ProgressText(value: final text),
        ):
          faction = text.toUpperCase();
        case (
          ProgressEntityKind.player,
          ProgressField.edition,
          ProgressText(value: final text),
        ):
          edition = text;
        case _:
          break;
      }
    }
    return ProgressFacts(
      mode: mode,
      taskStates: tasks,
      objectiveCounts: counts,
      objectivesComplete: complete,
      stationLevels: stations,
      level: level,
      faction: faction,
      edition: edition,
    );
  }

  /// The game mode whose active wipe these facts describe.
  final GameMode mode;

  /// The player level, or `null` when unset.
  final int? level;

  /// The faction as `BEAR` or `USEC`, or `null` when unset.
  final String? faction;

  /// The edition identifier, or `null` when unset.
  final String? edition;

  final Map<String, ProgressTaskStatus> _taskStates;
  final Map<String, int> _objectiveCounts;
  final Set<String> _objectivesComplete;
  final Map<String, int> _stationLevels;

  /// The recorded state of task [id], or `null` when it is not started.
  ProgressTaskStatus? taskState(String id) => _taskStates[id];

  /// The recorded count of objective [id], or 0.
  int objectiveCount(String id) => _objectiveCounts[id] ?? 0;

  /// Whether objective [id] is recorded as done.
  bool objectiveComplete(String id) => _objectivesComplete.contains(id);

  /// The recorded level of station [id], or 0 when it is not built.
  int stationLevel(String id) => _stationLevels[id] ?? 0;
}
