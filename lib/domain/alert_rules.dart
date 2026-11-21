import 'package:blackgrid_progress/blackgrid_progress.dart';

import 'local_progress.dart' show ProgressTaskStatus;
import 'objective_progress.dart';
import 'progress_facts.dart';
import 'settings.dart' show supportedMaps;

/// How old a log transition may be and still fire an alert.
const alertFreshness = Duration(seconds: 30);

/// The catalog `normalizedName` of the Air Filtering Unit station.
const airFilteringUnitName = 'air-filtering-unit';

/// Whether a transition logged at [logTime] is fresh at the clock reading
/// [now].
///
/// A transition up to [alertFreshness] old is fresh, and so is one logged in
/// the future.
bool isFreshLogTime(DateTime logTime, DateTime now) =>
    now.difference(logTime) <= alertFreshness;

/// The data an alert rule needed and did not have.
enum AlertDataGap {
  /// No map pack is loaded, so the queued map's quest markers are unknown.
  markers,

  /// The progress catalog of the active mode is missing.
  questData,

  /// The active mode's local progress cannot be read.
  progress,
}

/// The outcome of the quest items rule.
sealed class QuestItemsCheck {
  const QuestItemsCheck();
}

/// A started task has an unfinished item objective on the map.
final class QuestItemsFire extends QuestItemsCheck {
  /// Creates the fire outcome.
  const QuestItemsFire();
}

/// Nothing to remind about, or the map is unknown.
final class QuestItemsQuiet extends QuestItemsCheck {
  /// Creates the quiet outcome.
  const QuestItemsQuiet();
}

/// The rule could not decide because [reason] is missing.
final class QuestItemsUnavailable extends QuestItemsCheck {
  /// Creates the unavailable outcome.
  const QuestItemsUnavailable(this.reason);

  /// The missing data.
  final AlertDataGap reason;
}

const _itemObjectiveTypes = {
  ObjectiveType.plantItem,
  ObjectiveType.plantQuestItem,
  ObjectiveType.mark,
  ObjectiveType.giveQuestItem,
};

/// A quest objective that a marker of the queued map carries.
final class QuestObjectiveRef {
  /// Creates a reference to objective [objectiveId] of task [taskId].
  const QuestObjectiveRef(this.taskId, this.objectiveId);

  /// The task ID.
  final String taskId;

  /// The objective ID.
  final String objectiveId;
}

/// Decides whether the quest items reminder fires for the queued [mapId].
///
/// [objectives] are the quest objectives the Map shows for that map, or
/// `null` when no map pack is loaded. One counts when its task is started,
/// its catalog objective is a plant item, plant quest item, mark or hand over
/// quest item objective, and it is not done: neither recorded complete nor,
/// for a counter objective, at its target count. A map that is `null` or not
/// supported is quiet before any data is checked. The player's inventory is
/// never read.
QuestItemsCheck questItemsCheck({
  required String? mapId,
  required Iterable<QuestObjectiveRef>? objectives,
  required ProgressCatalog? catalog,
  required ProgressFacts? facts,
}) {
  if (mapId == null || !supportedMaps.contains(mapId)) {
    return const QuestItemsQuiet();
  }
  if (objectives == null) {
    return const QuestItemsUnavailable(AlertDataGap.markers);
  }
  if (catalog == null) {
    return const QuestItemsUnavailable(AlertDataGap.questData);
  }
  if (facts == null) return const QuestItemsUnavailable(AlertDataGap.progress);
  for (final QuestObjectiveRef(:taskId, :objectiveId) in objectives) {
    if (facts.taskState(taskId) != ProgressTaskStatus.started) continue;
    final taskObjectives = catalog.tasksById[taskId]?.objectives ?? const [];
    for (final objective in taskObjectives) {
      if (objective.id == objectiveId &&
          _itemObjectiveTypes.contains(objective.type) &&
          !objectiveDone(
            objective,
            complete: facts.objectiveComplete(objective.id),
            count: facts.objectiveCount(objective.id),
          )) {
        return const QuestItemsFire();
      }
    }
  }
  return const QuestItemsQuiet();
}

/// Whether the Air Filtering Unit is recorded built.
enum AirFilterStatus {
  /// The station is at level 1 or higher.
  built,

  /// The station has no recorded level.
  notBuilt,

  /// The catalog or the facts are missing, or the catalog has no such station.
  unavailable,
}

/// Reads the Air Filtering Unit's level from [facts], finding the station in
/// [catalog] by [airFilteringUnitName].
AirFilterStatus airFilterStatus({
  required ProgressCatalog? catalog,
  required ProgressFacts? facts,
}) {
  if (catalog == null || facts == null) return AirFilterStatus.unavailable;
  for (final station in catalog.stations) {
    if (station.normalizedName == airFilteringUnitName) {
      return facts.stationLevel(station.id) >= 1
          ? AirFilterStatus.built
          : AirFilterStatus.notBuilt;
    }
  }
  return AirFilterStatus.unavailable;
}

/// Whether [catalog] marks task [taskId] restartable.
///
/// A missing catalog, an unknown task and an unknown flag are not restartable.
bool isRestartable(ProgressCatalog? catalog, String taskId) =>
    catalog?.tasksById[taskId]?.restartable ?? false;
