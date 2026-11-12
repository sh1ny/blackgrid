part of 'progress_catalog.dart';

/// A task and the facts needed to evaluate and display it.
final class CatalogTask {
  /// Creates a task, copying all supplied collections.
  CatalogTask({
    required this.id,
    required this.name,
    this.normalizedName,
    this.traderId,
    this.minPlayerLevel,
    this.faction = TaskFaction.unknown,
    this.rawFaction,
    this.kappaRequired,
    this.lightkeeperRequired,
    this.restartable,
    this.mapId,
    this.requiredPrestigeId,
    this.availableDelaySecondsMin,
    this.availableDelaySecondsMax,
    Iterable<OtherRequirement>? otherRequirements,
    Iterable<String>? gameModes,
    Iterable<TaskPrerequisite>? prerequisites,
    Iterable<TraderRequirement>? traderRequirements,
    Iterable<FailCondition>? failConditions,
    Iterable<TaskAlternative>? alternatives,
    Iterable<TaskObjective> objectives = const [],
  }) : gameModes = _freeze(gameModes),
       otherRequirements = _freeze(otherRequirements),
       prerequisites = _freeze(prerequisites),
       traderRequirements = _freeze(traderRequirements),
       failConditions = _freeze(failConditions),
       alternatives = _freeze(alternatives),
       objectives = List<TaskObjective>.unmodifiable(objectives);

  CatalogTask._withObjectives(CatalogTask task, this.objectives)
    : id = task.id,
      name = task.name,
      normalizedName = task.normalizedName,
      traderId = task.traderId,
      minPlayerLevel = task.minPlayerLevel,
      faction = task.faction,
      rawFaction = task.rawFaction,
      kappaRequired = task.kappaRequired,
      lightkeeperRequired = task.lightkeeperRequired,
      restartable = task.restartable,
      mapId = task.mapId,
      requiredPrestigeId = task.requiredPrestigeId,
      gameModes = task.gameModes,
      prerequisites = task.prerequisites,
      traderRequirements = task.traderRequirements,
      failConditions = task.failConditions,
      alternatives = task.alternatives,
      otherRequirements = task.otherRequirements,
      availableDelaySecondsMin = task.availableDelaySecondsMin,
      availableDelaySecondsMax = task.availableDelaySecondsMax;

  /// Restores a task from its stored JSON representation.
  factory CatalogTask.fromJson(Map<String, Object?> json) => CatalogTask(
    id: _required(json['id']),
    name: _required(json['name']),
    normalizedName: _optional(json['normalizedName']),
    traderId: _optional(json['traderId']),
    minPlayerLevel: _optional(json['minPlayerLevel']),
    faction: _enumValue(json['faction'], TaskFaction.values),
    rawFaction: _optional(json['rawFaction']),
    kappaRequired: _optional(json['kappaRequired']),
    lightkeeperRequired: _optional(json['lightkeeperRequired']),
    restartable: _optional(json['restartable']),
    mapId: _optional(json['mapId']),
    requiredPrestigeId: _optional(json['requiredPrestigeId']),
    availableDelaySecondsMin: _optional(json['availableDelaySecondsMin']),
    availableDelaySecondsMax: _optional(json['availableDelaySecondsMax']),
    otherRequirements: _optionalList(
      json['otherRequirements'],
      (v) => OtherRequirement.fromJson(_object(v)),
    ),
    gameModes: _strings(json['gameModes']),
    prerequisites: _optionalList(
      json['prerequisites'],
      (v) => TaskPrerequisite.fromJson(_object(v)),
    ),
    traderRequirements: _optionalList(
      json['traderRequirements'],
      (v) => TraderRequirement.fromJson(_object(v)),
    ),
    failConditions: _optionalList(
      json['failConditions'],
      (v) => FailCondition.fromJson(_object(v)),
    ),
    alternatives: _optionalList(
      json['alternatives'],
      (v) => TaskAlternative.fromJson(_object(v)),
    ),
    objectives: _requiredList(
      json['objectives'],
      (v) => TaskObjective.fromJson(_object(v)),
    ),
  );

  /// The task ID.
  final String id;

  /// The display name.
  final String name;

  /// The normalized source name, if known.
  final String? normalizedName;

  /// The assigning trader ID, if known.
  final String? traderId;

  /// The minimum player level, if known.
  final int? minPlayerLevel;

  /// The faction restriction.
  final TaskFaction faction;

  /// The source faction text, if known.
  final String? rawFaction;

  /// Whether the task is required for Kappa, if known.
  final bool? kappaRequired;

  /// Whether the task is required for Lightkeeper, if known.
  final bool? lightkeeperRequired;

  /// Whether the task can be restarted, if known.
  final bool? restartable;

  /// The associated map ID, if known.
  final String? mapId;

  /// The required prestige ID, if known.
  final String? requiredPrestigeId;

  /// The extra game conditions, or `null` if unknown.
  final List<OtherRequirement>? otherRequirements;

  /// The minimum availability delay in seconds, or `null` if unknown.
  final int? availableDelaySecondsMin;

  /// The maximum availability delay in seconds, or `null` if unknown.
  final int? availableDelaySecondsMax;

  /// The restricted game modes, or null if unknown.
  final List<String>? gameModes;

  /// The prerequisites, or null if unknown.
  final List<TaskPrerequisite>? prerequisites;

  /// The trader requirements, or null if unknown.
  final List<TraderRequirement>? traderRequirements;

  /// The fail conditions, or null if unknown.
  final List<FailCondition>? failConditions;

  /// The alternative tasks, or null if unknown.
  final List<TaskAlternative>? alternatives;

  /// The objectives in source order.
  final List<TaskObjective> objectives;

  CatalogTask _withSharedObjectives(Set<String> shared) {
    List<TaskObjective>? updated;
    for (var i = 0; i < objectives.length; i++) {
      final objective = objectives[i];
      final isShared = shared.contains(objective.id);
      if (objective.isShared != isShared) {
        updated ??= List<TaskObjective>.of(objectives);
        updated[i] = objective._withShared(isShared);
      }
    }
    return updated == null
        ? this
        : CatalogTask._withObjectives(this, List.unmodifiable(updated));
  }

  /// Encodes the task and its nested facts.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'normalizedName': normalizedName,
    'traderId': traderId,
    'minPlayerLevel': minPlayerLevel,
    'faction': faction.name,
    'rawFaction': rawFaction,
    'kappaRequired': kappaRequired,
    'lightkeeperRequired': lightkeeperRequired,
    'restartable': restartable,
    'mapId': mapId,
    'requiredPrestigeId': requiredPrestigeId,
    'otherRequirements': otherRequirements?.map((v) => v.toJson()).toList(),
    'availableDelaySecondsMin': availableDelaySecondsMin,
    'availableDelaySecondsMax': availableDelaySecondsMax,
    'gameModes': gameModes,
    'prerequisites': prerequisites?.map((v) => v.toJson()).toList(),
    'traderRequirements': traderRequirements?.map((v) => v.toJson()).toList(),
    'failConditions': failConditions?.map((v) => v.toJson()).toList(),
    'alternatives': alternatives?.map((v) => v.toJson()).toList(),
    'objectives': objectives.map((v) => v.toJson()).toList(),
  };
}

/// A prerequisite task and its accepted statuses.
final class TaskPrerequisite {
  /// Creates a prerequisite, copying its status lists.
  TaskPrerequisite({
    required this.taskId,
    Iterable<TaskStatus>? statuses,
    Iterable<String>? rawStatuses,
  }) : statuses = _freeze(statuses),
       rawStatuses = _freeze(rawStatuses);

  /// Restores a prerequisite from stored JSON.
  factory TaskPrerequisite.fromJson(Map<String, Object?> json) =>
      TaskPrerequisite(
        taskId: _required(json['taskId']),
        statuses: _statuses(json['statuses']),
        rawStatuses: _strings(json['rawStatuses']),
      );

  /// The prerequisite task ID.
  final String taskId;

  /// The accepted statuses in source order, or null if unknown.
  final List<TaskStatus>? statuses;

  /// The source status strings in source order, or null if unknown.
  final List<String>? rawStatuses;

  /// Encodes the prerequisite.
  Map<String, Object?> toJson() => {
    'taskId': taskId,
    'statuses': _statusNames(statuses),
    'rawStatuses': rawStatuses,
  };
}

/// A task whose status can fail another task.
final class TaskAlternative {
  /// Creates an alternative, copying its status lists.
  TaskAlternative({
    required this.taskId,
    Iterable<TaskStatus>? statuses,
    Iterable<String>? rawStatuses,
  }) : statuses = _freeze(statuses),
       rawStatuses = _freeze(rawStatuses);

  /// Restores an alternative from stored JSON.
  factory TaskAlternative.fromJson(Map<String, Object?> json) =>
      TaskAlternative(
        taskId: _required(json['taskId']),
        statuses: _statuses(json['statuses']),
        rawStatuses: _strings(json['rawStatuses']),
      );

  /// The alternative task ID.
  final String taskId;

  /// The statuses in source order, or null if unknown.
  final List<TaskStatus>? statuses;

  /// The source status strings in source order, or null if unknown.
  final List<String>? rawStatuses;

  /// Encodes the alternative.
  Map<String, Object?> toJson() => {
    'taskId': taskId,
    'statuses': _statusNames(statuses),
    'rawStatuses': rawStatuses,
  };
}

/// The retained identity and type of a fail condition.
final class FailCondition {
  /// Creates a fail condition.
  const FailCondition({
    required this.id,
    this.type = ObjectiveType.unknown,
    this.rawType,
  });

  /// Restores a fail condition from stored JSON.
  factory FailCondition.fromJson(Map<String, Object?> json) => FailCondition(
    id: _required(json['id']),
    type: _enumValue(json['type'], ObjectiveType.values),
    rawType: _optional(json['rawType']),
  );

  /// The condition ID.
  final String id;

  /// The condition type.
  final ObjectiveType type;

  /// The source type string, if known.
  final String? rawType;

  /// Encodes the fail condition.
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'rawType': rawType,
  };
}

/// A trader level or reputation requirement.
final class TraderRequirement {
  /// Creates a trader requirement.
  const TraderRequirement({
    required this.traderId,
    this.type = TraderRequirementType.unknown,
    this.rawType,
    this.comparison = Comparison.unknown,
    this.rawComparison,
    this.value,
  });

  /// Restores a trader requirement from stored JSON.
  factory TraderRequirement.fromJson(Map<String, Object?> json) =>
      TraderRequirement(
        traderId: _required(json['traderId']),
        type: _enumValue(json['type'], TraderRequirementType.values),
        rawType: _optional(json['rawType']),
        comparison: _enumValue(json['comparison'], Comparison.values),
        rawComparison: _optional(json['rawComparison']),
        value: _optional(json['value']),
      );

  /// The trader ID.
  final String traderId;

  /// The requirement type.
  final TraderRequirementType type;

  /// The source requirement type, if known.
  final String? rawType;

  /// The comparison to apply.
  final Comparison comparison;

  /// The source comparison, if known.
  final String? rawComparison;

  /// The comparison target, if known.
  final num? value;

  /// Encodes the trader requirement.
  Map<String, Object?> toJson() => {
    'traderId': traderId,
    'type': type.name,
    'rawType': rawType,
    'comparison': comparison.name,
    'rawComparison': rawComparison,
    'value': value,
  };
}

/// A task objective with common and type-specific facts.
final class TaskObjective {
  /// Creates an objective, copying its map IDs.
  TaskObjective({
    required this.id,
    this.type = ObjectiveType.unknown,
    this.rawType,
    this.optional,
    this.count,
    this.description,
    Iterable<String>? mapIds,
    this.facts = const NoFacts(),
    this.isShared = false,
  }) : mapIds = _freeze(mapIds);

  TaskObjective._copy(TaskObjective objective, this.isShared)
    : id = objective.id,
      type = objective.type,
      rawType = objective.rawType,
      optional = objective.optional,
      count = objective.count,
      description = objective.description,
      mapIds = objective.mapIds,
      facts = objective.facts;

  /// Restores an objective from stored JSON.
  factory TaskObjective.fromJson(Map<String, Object?> json) => TaskObjective(
    id: _required(json['id']),
    type: _enumValue(json['type'], ObjectiveType.values),
    rawType: _optional(json['rawType']),
    optional: _optional(json['optional']),
    count: _optional(json['count']),
    description: _optional(json['description']),
    mapIds: _strings(json['mapIds']),
    facts: ObjectiveFacts.fromJson(_object(json['facts'])),
  );

  /// The objective ID.
  final String id;

  /// The objective type.
  final ObjectiveType type;

  /// The source type string, if known.
  final String? rawType;

  /// Whether the objective is optional, if known.
  final bool? optional;

  /// The target count, if known.
  final num? count;

  /// The translated description, if known.
  final String? description;

  /// The associated map IDs, or null if unknown.
  final List<String>? mapIds;

  /// The objective's type-specific facts.
  final ObjectiveFacts facts;

  /// Whether the ID belongs to objectives under multiple tasks.
  final bool isShared;

  TaskObjective _withShared(bool value) => TaskObjective._copy(this, value);

  /// Encodes the objective without its derived shared flag.
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'rawType': rawType,
    'optional': optional,
    'count': count,
    'description': description,
    'mapIds': mapIds,
    'facts': facts.toJson(),
  };
}
