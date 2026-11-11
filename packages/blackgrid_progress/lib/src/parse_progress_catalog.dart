import 'progress_catalog.dart';

/// Parses a mode's task and hideout dataset `data` objects and dictionaries.
///
/// [tasksData] contains the keyed `tasks` collection; [hideoutData] is the
/// keyed station collection. Dictionaries contain unwrapped English text.
/// Throws [FormatException] for invalid identities, level numbers or required
/// references. Newly retained malformed facts remain unknown. Existing item
/// validation belongs to the caller and is not replaced by this parser.
ProgressCatalog parseProgressCatalog(
  Object? tasksData,
  Object? hideoutData,
  Set<String> traderIds,
  Map<String, dynamic>? taskDictionary,
  Map<String, dynamic>? hideoutDictionary,
) {
  final tasks = _entities(_wireMap(tasksData)['tasks']);
  final stations = _entities(hideoutData);
  final taskIds = tasks.keys.toSet();
  final stationIds = stations.keys.toSet();

  TraderRequirement traderRequirement(Map<String, dynamic> wire) =>
      TraderRequirement(
        traderId: _reference(wire['trader'], traderIds),
        type: switch (wire['requirementType']) {
          'level' => TraderRequirementType.level,
          'reputation' => TraderRequirementType.reputation,
          _ => TraderRequirementType.unknown,
        },
        rawType: _text(wire['requirementType']),
        comparison: _comparison(wire['compareMethod']),
        rawComparison: _text(wire['compareMethod']),
        value: _number(wire['value']),
      );

  ObjectiveFacts facts(ObjectiveType type, Map<String, dynamic> wire) =>
      switch (type) {
        ObjectiveType.findItem ||
        ObjectiveType.giveItem ||
        ObjectiveType.plantItem ||
        ObjectiveType.sellItem => ItemFacts(
          itemIds: _stringList(wire['items']),
          foundInRaid: _fact<bool>(wire['foundInRaid']),
        ),
        ObjectiveType.buildWeapon => ItemFacts(itemIds: _single(wire['item'])),
        ObjectiveType.useItem => ItemFacts(
          itemIds: _stringList(wire['useAny']),
        ),
        ObjectiveType.mark => ItemFacts(itemIds: _single(wire['markerItem'])),
        ObjectiveType.findQuestItem ||
        ObjectiveType.giveQuestItem ||
        ObjectiveType.plantQuestItem => QuestItemFacts(
          questItemId: switch (wire['questItem']) {
            {'id': final String id} => _text(id),
            final String id => _text(id),
            _ => null,
          },
        ),
        ObjectiveType.taskStatus => TaskStatusFacts(
          taskId: _optionalReference(wire['task'], taskIds),
          statuses: _statuses(wire['status']),
          rawStatuses: _stringList(wire['status']),
        ),
        ObjectiveType.traderLevel => TraderLevelFacts(
          traderId: _text(wire['trader']),
          level: _integer(wire['level']),
        ),
        ObjectiveType.traderStanding => TraderStandingFacts(
          traderId: _text(wire['trader']),
          comparison: _comparison(wire['compareMethod']),
          rawComparison: _text(wire['compareMethod']),
          value: _number(wire['value']),
        ),
        ObjectiveType.skill => SkillFacts(
          skillId: _text(wire['skill']),
          level: _number(wire['level']),
        ),
        ObjectiveType.dialogue ||
        ObjectiveType.experience ||
        ObjectiveType.extract ||
        ObjectiveType.globalVariable ||
        ObjectiveType.shoot ||
        ObjectiveType.visit ||
        ObjectiveType.unknown => const NoFacts(),
      };

  CatalogTask task(Map<String, dynamic> wire) {
    final objectives = <TaskObjective>[];
    final localIds = <String>{};
    for (final objective in _requiredRows(wire['objectives'])) {
      final id = _id(objective['id']);
      if (!localIds.add(id)) {
        throw const FormatException('Repeated objective identity within task');
      }
      final type = _objectiveType(objective['type']);
      objectives.add(
        TaskObjective(
          id: id,
          type: type,
          rawType: _text(objective['type']),
          optional: _fact<bool>(objective['optional']),
          count: _number(objective['count']),
          description: _translation(taskDictionary, objective['description']),
          mapIds: _stringList(objective['maps']),
          facts: facts(type, objective),
        ),
      );
    }
    final failRows = _optionalRows(wire['failConditions']);
    final failConditions = failRows == null ? null : <FailCondition>[];
    final alternatives = failRows == null ? null : <TaskAlternative>[];
    if (failRows != null) {
      for (final condition in failRows) {
        final type = _objectiveType(condition['type']);
        failConditions!.add(
          FailCondition(
            id: _id(condition['id']),
            type: type,
            rawType: _text(condition['type']),
          ),
        );
        if (type == ObjectiveType.taskStatus) {
          alternatives!.add(
            TaskAlternative(
              taskId: _reference(condition['task'], taskIds),
              statuses: _statuses(condition['status']),
              rawStatuses: _stringList(condition['status']),
            ),
          );
        }
      }
    }
    final id = _id(wire['id']);
    final normalized = _text(wire['normalizedName']);
    return CatalogTask(
      id: id,
      name: _translation(taskDictionary, wire['name']) ?? normalized ?? id,
      normalizedName: normalized,
      traderId: _reference(wire['trader'], traderIds),
      minPlayerLevel: _integer(wire['minPlayerLevel']),
      faction: switch (wire['factionName']) {
        'Any' => TaskFaction.any,
        'BEAR' => TaskFaction.bear,
        'USEC' => TaskFaction.usec,
        _ => TaskFaction.unknown,
      },
      rawFaction: _text(wire['factionName']),
      kappaRequired: _fact<bool>(wire['kappaRequired']),
      lightkeeperRequired: _fact<bool>(wire['lightkeeperRequired']),
      restartable: _fact<bool>(wire['restartable']),
      mapId: _text(wire['map']),
      requiredPrestigeId: _text(wire['requiredPrestige']),
      gameModes: _stringList(wire['gameMode']),
      prerequisites: _optionalRows(wire['taskRequirements'])?.map(
        (r) => TaskPrerequisite(
          taskId: _reference(r['task'], taskIds),
          statuses: _statuses(r['status']),
          rawStatuses: _stringList(r['status']),
        ),
      ),
      traderRequirements: _optionalRows(wire['traderRequirements'])
          ?.map(traderRequirement),
      failConditions: failConditions,
      alternatives: alternatives,
      objectives: objectives,
    );
  }

  HideoutStation station(Map<String, dynamic> wire) {
    final levels = <StationLevel>[];
    for (final level in _requiredRows(wire['levels'])) {
      final number = _integer(level['level']);
      if (number == null || number < 1) {
        throw const FormatException('Invalid station level number');
      }
      levels.add(
        StationLevel(
          id: _id(level['id']),
          level: number,
          constructionTime: _number(level['constructionTime']),
          stationRequirements: _optionalRows(level['stationLevelRequirements'])
              ?.map(
                (r) => StationRequirement(
                  stationId: _reference(r['station'], stationIds),
                  level: _integer(r['level']),
                ),
              ),
          traderRequirements: _optionalRows(level['traderRequirements'])
              ?.map(traderRequirement),
          skillRequirements: _skillRequirements(level['skillRequirements']),
        ),
      );
    }
    levels.sort((a, b) => a.level.compareTo(b.level));
    final id = _id(wire['id']);
    final normalized = _text(wire['normalizedName']);
    return HideoutStation(
      id: id,
      name: _translation(hideoutDictionary, wire['name']) ?? normalized ?? id,
      normalizedName: normalized,
      levels: levels,
    );
  }

  return ProgressCatalog(
    tasks: tasks.values.map(task),
    stations: stations.values.map(station),
  );
}

Map<String, dynamic> _wireMap(Object? value) => switch (value) {
  final Map<String, dynamic> map => map,
  _ => throw const FormatException('Expected wire object'),
};

Map<String, Map<String, dynamic>> _entities(Object? value) {
  final result = <String, Map<String, dynamic>>{};
  for (final entry in _wireMap(value).entries) {
    final entity = _wireMap(entry.value);
    final id = _id(entity['id']);
    if (id != entry.key || result.containsKey(id)) {
      throw const FormatException('Duplicate or mismatched wire identity');
    }
    result[id] = entity;
  }
  return result;
}

Iterable<Map<String, dynamic>> _requiredRows(Object? value) => switch (value) {
  final List<Object?> rows => rows.map(_wireMap),
  _ => throw const FormatException('Expected wire list'),
};

Iterable<Map<String, dynamic>>? _optionalRows(Object? value) =>
    value is List<Object?> ? value.map(_wireMap) : null;

Iterable<SkillRequirement>? _skillRequirements(Object? value) =>
    value is List<Object?>
    ? value.map(
        (row) => switch (row) {
          final Map<String, dynamic> wire => SkillRequirement(
            skillId: _text(wire['skill']),
            level: _number(wire['level']),
          ),
          _ => const SkillRequirement(),
        },
      )
    : null;

String _id(Object? value) =>
    _text(value) ?? (throw const FormatException('Missing wire identity'));

String _reference(Object? value, Set<String> ids) {
  final id = _id(value);
  if (!ids.contains(id)) {
    throw const FormatException('Unresolved required reference');
  }
  return id;
}

String? _optionalReference(Object? value, Set<String> ids) =>
    _text(value) == null ? null : _reference(value, ids);

T? _fact<T>(Object? value) => value is T ? value : null;

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

num? _number(Object? value) => value is num && value.isFinite ? value : null;

int? _integer(Object? value) {
  final number = _number(value);
  if (number == null || number != number.roundToDouble()) return null;
  return number.toInt();
}

Iterable<String>? _stringList(Object? value) =>
    value is List<Object?> && value.every((v) => v is String)
    ? value.cast<String>()
    : null;

Iterable<String>? _single(Object? value) {
  final id = _text(value);
  return id == null ? null : [id];
}

Iterable<TaskStatus>? _statuses(Object? value) => _stringList(value)?.map(
  (status) => switch (status) {
    'complete' => TaskStatus.complete,
    'active' => TaskStatus.active,
    'failed' => TaskStatus.failed,
    _ => TaskStatus.unknown,
  },
);

Comparison _comparison(Object? value) => switch (value) {
  '>=' => Comparison.atLeast,
  '>' => Comparison.greaterThan,
  '<=' => Comparison.atMost,
  '<' => Comparison.lessThan,
  '=' => Comparison.equal,
  _ => Comparison.unknown,
};

final _objectiveTypes = {
  for (final type in ObjectiveType.values) type.name: type,
};

ObjectiveType _objectiveType(Object? value) =>
    _objectiveTypes[value] ?? ObjectiveType.unknown;

String? _translation(Map<String, dynamic>? dictionary, Object? key) =>
    key is String ? _text(dictionary?[key]) : null;
