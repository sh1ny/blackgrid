import 'package:blackgrid_progress/blackgrid_progress.dart';

/// A small edition vocabulary with both kinds of rule.
const testEditionTable = EditionTable(
  version: 1,
  editions: {'standard', 'unheard', 'other'},
  entries: {
    'allowed': EditionRule.allowed({'unheard'}, source: 'test'),
    'excluded': EditionRule.excluded({'standard'}, source: 'test'),
  },
);

/// Builds a task with otherwise known, passing gates.
CatalogTask testTask(
  String id, {
  int? minPlayerLevel = 1,
  TaskFaction faction = TaskFaction.any,
  bool? restartable,
  String? requiredPrestigeId,
  int? delayMin = 0,
  int? delayMax = 0,
  Iterable<OtherRequirement>? otherRequirements = const [],
  Iterable<String>? gameModes,
  Iterable<TaskPrerequisite>? prerequisites = const [],
  Iterable<TraderRequirement>? traderRequirements = const [],
  Iterable<TaskAlternative>? alternatives = const [],
}) => CatalogTask(
  id: id,
  name: id,
  minPlayerLevel: minPlayerLevel,
  faction: faction,
  restartable: restartable,
  requiredPrestigeId: requiredPrestigeId,
  availableDelaySecondsMin: delayMin,
  availableDelaySecondsMax: delayMax,
  otherRequirements: otherRequirements,
  gameModes: gameModes,
  prerequisites: prerequisites,
  traderRequirements: traderRequirements,
  alternatives: alternatives,
);

/// Creates a catalog in the supplied task order.
ProgressCatalog testCatalog(Iterable<CatalogTask> tasks) =>
    ProgressCatalog(tasks: tasks, stations: const []);

/// Evaluates a task with catalog-owned prerequisite and alternative IDs.
TaskAvailability evaluateTestTask(
  CatalogTask task, {
  PlayerProgress? progress,
  ProgressMode mode = ProgressMode.regular,
}) => evaluateTasks(
  testCatalog([
    task,
    for (final id in <String>{
      for (final prerequisite
          in task.prerequisites ?? const <TaskPrerequisite>[])
        prerequisite.taskId,
      for (final alternative in task.alternatives ?? const <TaskAlternative>[])
        alternative.taskId,
    })
      if (id != task.id) testTask(id),
  ]),
  mode,
  progress ?? PlayerProgress(),
  table: testEditionTable,
).singleWhere((result) => result.taskId == task.id);

/// Creates a trader-level comparison.
TraderRequirement loyalty(String traderId, Comparison comparison, num? value) =>
    TraderRequirement(
      traderId: traderId,
      type: TraderRequirementType.level,
      comparison: comparison,
      value: value,
    );
