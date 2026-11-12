import 'edition_rules.dart';
import 'edition_table.dart';
import 'player_progress.dart';
import 'progress_catalog.dart';
import 'task_availability.dart';

/// Evaluates each catalog task in source order using only the supplied facts.
///
/// Recorded finished, nonrestartable failed and started states take precedence
/// over gates. All failing checked gates lock a not-started task; unchecked
/// reasons expose uncertainty but never lock it. Unknown progress IDs are ignored.
List<TaskAvailability> evaluateTasks(
  ProgressCatalog catalog,
  ProgressMode mode,
  PlayerProgress progress, {
  EditionTable table = editionTable,
}) => List<TaskAvailability>.unmodifiable(
  catalog.tasks.map(
    (task) => _evaluateTask(task, mode, progress, table, catalog.tasksById),
  ),
);

TaskAvailability _evaluateTask(
  CatalogTask task,
  ProgressMode mode,
  PlayerProgress progress,
  EditionTable table,
  Map<String, CatalogTask> tasksById,
) {
  final state = progress.taskStates[task.id];
  if (state == TaskProgressState.finished) {
    return TaskAvailability(
      taskId: task.id,
      status: AvailabilityStatus.done,
      checked: const [Finished()],
    );
  }
  if (state == TaskProgressState.failed && task.restartable != true) {
    return TaskAvailability(
      taskId: task.id,
      status: AvailabilityStatus.done,
      checked: const [Failed()],
    );
  }
  if (state == TaskProgressState.started) {
    return TaskAvailability(
      taskId: task.id,
      status: AvailabilityStatus.available,
      started: true,
    );
  }
  final checked = <CheckedReason>[];
  final unchecked = <UncheckedReason>[];
  final minimum = task.minPlayerLevel;
  if (minimum == null) {
    unchecked.add(const LevelRequirementUnknown());
  } else if (minimum > 1) {
    final level = progress.level;
    if (level == null) {
      unchecked.add(LevelUnset(required: minimum));
    } else if (level < minimum) {
      checked.add(LevelTooLow(required: minimum, actual: level));
    }
  }

  for (final requirement
      in task.traderRequirements ?? const <TraderRequirement>[]) {
    final trader = requirement.traderId;
    if (requirement.type == TraderRequirementType.reputation) {
      unchecked.add(ReputationRequirement(traderId: trader));
      continue;
    }
    final value = requirement.value;
    final comparison = requirement.comparison;
    if (requirement.type == TraderRequirementType.unknown ||
        value == null ||
        comparison == Comparison.unknown) {
      unchecked.add(LoyaltyRequirementUnknown(traderId: trader));
      continue;
    }
    final loyalty = progress.traderLoyalty[trader];
    if (loyalty == null) {
      final trivial =
          (comparison == Comparison.atLeast && value <= 1) ||
          (comparison == Comparison.greaterThan && value < 1);
      if (!trivial) unchecked.add(LoyaltyUnset(traderId: trader));
    } else if (!_meets(loyalty, comparison, value)) {
      checked.add(
        LoyaltyTooLow(
          traderId: trader,
          comparison: comparison,
          required: value,
          actual: loyalty,
        ),
      );
    }
  }

  final prerequisites = task.prerequisites;
  if (prerequisites == null) {
    unchecked.add(const PrerequisitesUnknown());
  } else {
    for (final prerequisite in prerequisites) {
      final statuses = prerequisite.statuses;
      if (statuses == null ||
          !statuses.any((status) => status != TaskStatus.unknown)) {
        unchecked.add(PrerequisiteStatusUnknown(taskId: prerequisite.taskId));
        continue;
      }
      final recorded = _status(
        tasksById.containsKey(prerequisite.taskId)
            ? progress.taskStates[prerequisite.taskId]
            : null,
      );
      if (statuses.contains(recorded)) continue;
      if (recorded == TaskStatus.complete &&
          statuses.contains(TaskStatus.active) &&
          !statuses.contains(TaskStatus.complete)) {
        unchecked.add(ActivePrerequisiteFinished(taskId: prerequisite.taskId));
      } else {
        checked.add(
          PrerequisiteNotMet(
            taskId: prerequisite.taskId,
            needed: {
              for (final status in statuses)
                if (status != TaskStatus.unknown) status,
            },
          ),
        );
      }
    }
  }
  final alternatives = task.alternatives;
  if (alternatives == null) {
    unchecked.add(const AlternativesUnknown());
  } else {
    for (final alternative in alternatives) {
      final recorded = _status(
        tasksById.containsKey(alternative.taskId)
            ? progress.taskStates[alternative.taskId]
            : null,
      );
      if (recorded != null &&
          (alternative.statuses?.contains(recorded) ?? false)) {
        checked.add(AlternativeTaken(taskId: alternative.taskId));
      }
    }
  }

  switch (task.faction) {
    case TaskFaction.unknown:
      unchecked.add(const FactionUnknown());
    case TaskFaction.any:
      break;
    case TaskFaction.bear || TaskFaction.usec:
      final faction = progress.faction;
      if (faction == null) {
        unchecked.add(FactionUnset(required: task.faction));
      } else if ((task.faction == TaskFaction.bear &&
              faction != PlayerFaction.bear) ||
          (task.faction == TaskFaction.usec && faction != PlayerFaction.usec)) {
        checked.add(WrongFaction(required: task.faction));
      }
  }
  final modes = task.gameModes;
  if (modes != null && !modes.contains(mode.tarkovDevName)) {
    checked.add(WrongGameMode(allowed: modes));
  }
  final editionRule = table.entries[task.id];
  if (editionRule != null) {
    final edition = progress.edition;
    if (edition == null) {
      unchecked.add(const EditionUnset());
    } else if (!table.editions.contains(edition)) {
      unchecked.add(EditionUnrecognised(edition: edition));
    } else if (!editionRule.permits(edition)) {
      checked.add(EditionNotPermitted(edition: edition));
    }
  }

  final other = task.otherRequirements;
  if (other == null) {
    unchecked.add(const OtherRequirementsUnknown());
  } else {
    for (final requirement in other) {
      unchecked.add(switch (requirement) {
        GlobalVariableRequirement(:final variableId) => GlobalVariable(
          variableId: variableId,
        ),
        DialogueRequirement(:final traderIds) => TraderDialogue(
          traderIds: traderIds,
        ),
        UnknownOtherRequirement(:final rawType) => OtherRequirementUnknownType(
          rawType: rawType,
        ),
      });
    }
  }
  final minDelay = task.availableDelaySecondsMin;
  final maxDelay = task.availableDelaySecondsMax;
  if (minDelay == null || maxDelay == null) {
    unchecked.add(const AvailabilityDelayUnknown());
  } else if (minDelay > 0 || maxDelay > 0) {
    unchecked.add(
      AvailabilityDelay(minSeconds: minDelay, maxSeconds: maxDelay),
    );
  }
  final prestige = task.requiredPrestigeId;
  if (prestige != null) unchecked.add(PrestigeRequired(prestigeId: prestige));

  return TaskAvailability(
    taskId: task.id,
    status: checked.isEmpty
        ? AvailabilityStatus.available
        : AvailabilityStatus.locked,
    checked: checked,
    unchecked: unchecked,
  );
}

TaskStatus? _status(TaskProgressState? state) => switch (state) {
  TaskProgressState.finished => TaskStatus.complete,
  TaskProgressState.started => TaskStatus.active,
  TaskProgressState.failed => TaskStatus.failed,
  null => null,
};

bool _meets(int actual, Comparison comparison, num required) =>
    switch (comparison) {
      Comparison.atLeast => actual >= required,
      Comparison.greaterThan => actual > required,
      Comparison.atMost => actual <= required,
      Comparison.lessThan => actual < required,
      Comparison.equal => actual == required,
      Comparison.unknown => false,
    };
