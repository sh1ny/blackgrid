import 'package:blackgrid_progress/blackgrid_progress.dart';

import '../domain/local_progress.dart';
import '../domain/objective_progress.dart';

/// The register a counter objective's count is recorded in.
ProgressTarget objectiveCountRegister(String objectiveId) => ProgressTarget(
  kind: ProgressEntityKind.objective,
  id: objectiveId,
  field: ProgressField.count,
);

/// The register an objective's completion is recorded in.
ProgressTarget objectiveCompleteRegister(String objectiveId) => ProgressTarget(
  kind: ProgressEntityKind.objective,
  id: objectiveId,
  field: ProgressField.complete,
);

/// A task named only by its identity and display name.
final class QuestTaskRef {
  /// Creates a task reference.
  const QuestTaskRef({required this.id, required this.name});

  /// The task ID.
  final String id;

  /// The task's display name.
  final String name;
}

/// One objective of a started task with its recorded progress.
final class QuestObjective {
  /// Creates an objective row.
  const QuestObjective({
    required this.id,
    required this.description,
    required this.optional,
    required this.onThisMap,
    required this.target,
    required this.count,
    required this.done,
    required this.sharedWith,
  });

  /// The objective ID.
  final String id;

  /// The English description, or the objective type when it has none.
  final String description;

  /// Whether the objective is optional.
  final bool optional;

  /// Whether a quest marker of the current map carries this objective.
  final bool onThisMap;

  /// The target count of a counter objective, or `null` for any other.
  final int? target;

  /// The recorded count, 0 when none is recorded or for a non-counter.
  final int count;

  /// Whether the objective is complete or its count reached the target.
  final bool done;

  /// The other tasks of the catalog that list this shared objective.
  final List<QuestTaskRef> sharedWith;

  /// Whether the objective has a target count over 1.
  bool get isCounter => target != null;
}

/// A started task and its objectives.
final class QuestTask {
  /// Creates a task row.
  const QuestTask({
    required this.id,
    required this.name,
    required this.traderName,
    required this.onThisMap,
    required this.objectives,
  });

  /// The task ID.
  final String id;

  /// The task's display name.
  final String name;

  /// The assigning trader's name, or `null` when unknown.
  final String? traderName;

  /// Whether a quest marker of the current map carries this task.
  final bool onThisMap;

  /// The objectives in catalog order.
  final List<QuestObjective> objectives;
}

/// The started tasks of one mode, ordered for display.
final class QuestChecklist {
  /// Creates a checklist from ordered tasks.
  const QuestChecklist(this.tasks);

  /// The empty checklist.
  static const empty = QuestChecklist([]);

  /// Tasks on the current map first, then the rest; each by trader and name.
  final List<QuestTask> tasks;
}

/// The quest markers' view of progress: which tasks are started and which
/// objectives are done.
final class QuestMarkerFilter {
  /// Creates a filter from copies of the given sets.
  QuestMarkerFilter({
    required Set<String> startedTaskIds,
    required Set<String> doneObjectiveIds,
  }) : startedTaskIds = Set.unmodifiable(startedTaskIds),
       doneObjectiveIds = Set.unmodifiable(doneObjectiveIds);

  /// IDs of tasks whose current state is started, listed in the catalog or not.
  final Set<String> startedTaskIds;

  /// IDs of objectives whose completion or count says they are done.
  final Set<String> doneObjectiveIds;

  @override
  bool operator ==(Object other) =>
      other is QuestMarkerFilter &&
      startedTaskIds.length == other.startedTaskIds.length &&
      doneObjectiveIds.length == other.doneObjectiveIds.length &&
      startedTaskIds.containsAll(other.startedTaskIds) &&
      doneObjectiveIds.containsAll(other.doneObjectiveIds);

  @override
  int get hashCode =>
      Object.hash(startedTaskIds.length, doneObjectiveIds.length);
}

bool _isStarted(Map<ProgressTarget, ProgressEvent> winners, String taskId) =>
    winners[ProgressTarget(
          kind: ProgressEntityKind.task,
          id: taskId,
          field: ProgressField.state,
        )]
        ?.value ==
    const ProgressTaskState(ProgressTaskStatus.started);

bool _completed(Map<ProgressTarget, ProgressEvent> winners, String id) =>
    winners[objectiveCompleteRegister(id)]?.value ==
    const ProgressBoolean(true);

int _recordedCount(Map<ProgressTarget, ProgressEvent> winners, String id) =>
    switch (winners[objectiveCountRegister(id)]?.value) {
      ProgressInteger(:final value) => value,
      _ => 0,
    };

/// Derives the checklist of started tasks from the mode's catalog and winners.
///
/// [markerTaskIds] and [markerObjectiveIds] are the task and objective IDs
/// carried by the current map's quest markers; with none loaded, nothing is
/// on the map and all tasks form one group. Started IDs the [catalog] does not
/// list are not shown, and a missing catalog yields an empty checklist.
QuestChecklist buildQuestChecklist({
  required ProgressCatalog? catalog,
  required Map<ProgressTarget, ProgressEvent> winners,
  Set<String> markerTaskIds = const {},
  Set<String> markerObjectiveIds = const {},
}) {
  if (catalog == null) return QuestChecklist.empty;
  final traderNames = <String, String>{
    for (final trader in catalog.traders ?? const <CatalogTraderLevels>[])
      trader.id: trader.name,
  };
  final listing = <String, List<QuestTaskRef>>{};
  for (final task in catalog.tasks) {
    for (final objective in task.objectives) {
      if (!catalog.sharedObjectiveIds.contains(objective.id)) continue;
      (listing[objective.id] ??= []).add(
        QuestTaskRef(id: task.id, name: task.name),
      );
    }
  }
  final tasks = <QuestTask>[];
  for (final task in catalog.tasks) {
    if (!_isStarted(winners, task.id)) continue;
    tasks.add(
      QuestTask(
        id: task.id,
        name: task.name,
        traderName: traderNames[task.traderId],
        onThisMap: markerTaskIds.contains(task.id),
        objectives: List.unmodifiable([
          for (final objective in task.objectives)
            _objectiveRow(
              objective,
              task.id,
              winners,
              markerObjectiveIds.contains(objective.id),
              listing[objective.id],
            ),
        ]),
      ),
    );
  }
  int byTrader(QuestTask a, QuestTask b) {
    final aTrader = a.traderName, bTrader = b.traderName;
    if (aTrader != bTrader) {
      if (aTrader == null) return 1;
      if (bTrader == null) return -1;
      final compared = _compareText(aTrader, bTrader);
      if (compared != 0) return compared;
    }
    return _compareText(a.name, b.name);
  }

  tasks.sort((a, b) {
    if (a.onThisMap != b.onThisMap) return a.onThisMap ? -1 : 1;
    return byTrader(a, b);
  });
  return QuestChecklist(List.unmodifiable(tasks));
}

QuestObjective _objectiveRow(
  TaskObjective objective,
  String taskId,
  Map<ProgressTarget, ProgressEvent> winners,
  bool onThisMap,
  List<QuestTaskRef>? listing,
) {
  final target = objectiveCounterTarget(objective);
  final count = target == null ? 0 : _recordedCount(winners, objective.id);
  return QuestObjective(
    id: objective.id,
    description:
        objective.description ?? objective.rawType ?? objective.type.name,
    optional: objective.optional ?? false,
    onThisMap: onThisMap,
    target: target,
    count: count,
    done: objectiveDone(
      objective,
      complete: _completed(winners, objective.id),
      count: count,
    ),
    sharedWith: List.unmodifiable([
      for (final ref in listing ?? const <QuestTaskRef>[])
        if (ref.id != taskId) ref,
    ]),
  );
}

int _compareText(String a, String b) {
  final folded = a.toLowerCase().compareTo(b.toLowerCase());
  return folded != 0 ? folded : a.compareTo(b);
}

/// Derives the quest marker filter, or `null` when no task is started.
///
/// Without the mode's [catalog] an objective is done only by a recorded
/// completion, since its target count is unknown.
QuestMarkerFilter? buildQuestMarkerFilter({
  required ProgressCatalog? catalog,
  required Map<ProgressTarget, ProgressEvent> winners,
}) {
  final started = <String>{};
  final done = <String>{};
  for (final MapEntry(key: target, value: event) in winners.entries) {
    switch ((target.kind, target.field, event.value)) {
      case (
        ProgressEntityKind.task,
        ProgressField.state,
        ProgressTaskState(value: ProgressTaskStatus.started),
      ):
        started.add(target.id);
      case (
        ProgressEntityKind.objective,
        ProgressField.complete,
        ProgressBoolean(value: true),
      ):
        done.add(target.id);
      default:
    }
  }
  if (started.isEmpty) return null;
  if (catalog != null) {
    for (final task in catalog.tasks) {
      for (final objective in task.objectives) {
        if (objectiveDone(
          objective,
          complete: done.contains(objective.id),
          count: _recordedCount(winners, objective.id),
        )) {
          done.add(objective.id);
        }
      }
    }
  }
  return QuestMarkerFilter(startedTaskIds: started, doneObjectiveIds: done);
}
