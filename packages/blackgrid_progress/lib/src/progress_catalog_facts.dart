part of 'progress_catalog.dart';

/// Type-specific facts retained for an objective.
sealed class ObjectiveFacts {
  const ObjectiveFacts._();

  /// Restores a facts subtype from its stored discriminator and fields.
  static ObjectiveFacts fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'item' => ItemFacts.fromJson(json),
        'questItem' => QuestItemFacts.fromJson(json),
        'taskStatus' => TaskStatusFacts.fromJson(json),
        'traderLevel' => TraderLevelFacts.fromJson(json),
        'traderStanding' => TraderStandingFacts.fromJson(json),
        'skill' => SkillFacts.fromJson(json),
        'none' => NoFacts.fromJson(json),
        _ => throw const FormatException('Unknown objective facts kind'),
      };

  /// Encodes the facts with a subtype discriminator.
  Map<String, Object?> toJson();
}

void _expectKind(Map<String, Object?> json, String kind) {
  if (json['kind'] != kind) throw FormatException('Expected facts kind $kind');
}

/// Item IDs and found-in-raid status for an item objective.
final class ItemFacts extends ObjectiveFacts {
  /// Creates item facts, copying the item IDs.
  ItemFacts({Iterable<String>? itemIds, this.foundInRaid})
    : itemIds = _freeze(itemIds),
      super._();

  /// Restores item facts from stored JSON.
  factory ItemFacts.fromJson(Map<String, Object?> json) {
    _expectKind(json, 'item');
    return ItemFacts(
      itemIds: _strings(json['itemIds']),
      foundInRaid: _optional(json['foundInRaid']),
    );
  }

  /// The item IDs, or null if unknown.
  final List<String>? itemIds;

  /// Whether items must be found in raid, if known.
  final bool? foundInRaid;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'item',
    'itemIds': itemIds,
    'foundInRaid': foundInRaid,
  };
}

/// A quest item target.
final class QuestItemFacts extends ObjectiveFacts {
  /// Creates quest item facts.
  const QuestItemFacts({this.questItemId}) : super._();

  /// Restores quest item facts from stored JSON.
  factory QuestItemFacts.fromJson(Map<String, Object?> json) {
    _expectKind(json, 'questItem');
    return QuestItemFacts(questItemId: _optional(json['questItemId']));
  }

  /// The quest item ID, if known.
  final String? questItemId;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'questItem',
    'questItemId': questItemId,
  };
}

/// A target task and accepted statuses.
final class TaskStatusFacts extends ObjectiveFacts {
  /// Creates task status facts, copying the status lists.
  TaskStatusFacts({
    this.taskId,
    Iterable<TaskStatus>? statuses,
    Iterable<String>? rawStatuses,
  }) : statuses = _freeze(statuses),
       rawStatuses = _freeze(rawStatuses),
       super._();

  /// Restores task status facts from stored JSON.
  factory TaskStatusFacts.fromJson(Map<String, Object?> json) {
    _expectKind(json, 'taskStatus');
    return TaskStatusFacts(
      taskId: _optional(json['taskId']),
      statuses: _statuses(json['statuses']),
      rawStatuses: _strings(json['rawStatuses']),
    );
  }

  /// The target task ID, if known.
  final String? taskId;

  /// The accepted statuses in source order, or null if unknown.
  final List<TaskStatus>? statuses;

  /// The source status strings in source order, or null if unknown.
  final List<String>? rawStatuses;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'taskStatus',
    'taskId': taskId,
    'statuses': _statusNames(statuses),
    'rawStatuses': rawStatuses,
  };
}

/// A trader level target.
final class TraderLevelFacts extends ObjectiveFacts {
  /// Creates trader level facts.
  const TraderLevelFacts({this.traderId, this.level}) : super._();

  /// Restores trader level facts from stored JSON.
  factory TraderLevelFacts.fromJson(Map<String, Object?> json) {
    _expectKind(json, 'traderLevel');
    return TraderLevelFacts(
      traderId: _optional(json['traderId']),
      level: _optional(json['level']),
    );
  }

  /// The target trader ID, if known.
  final String? traderId;

  /// The target level, if known.
  final int? level;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'traderLevel',
    'traderId': traderId,
    'level': level,
  };
}

/// A trader standing comparison and target.
final class TraderStandingFacts extends ObjectiveFacts {
  /// Creates trader standing facts.
  const TraderStandingFacts({
    this.traderId,
    this.comparison = Comparison.unknown,
    this.rawComparison,
    this.value,
  }) : super._();

  /// Restores trader standing facts from stored JSON.
  factory TraderStandingFacts.fromJson(Map<String, Object?> json) {
    _expectKind(json, 'traderStanding');
    return TraderStandingFacts(
      traderId: _optional(json['traderId']),
      comparison: _enumValue(json['comparison'], Comparison.values),
      rawComparison: _optional(json['rawComparison']),
      value: _optional(json['value']),
    );
  }

  /// The target trader ID, if known.
  final String? traderId;

  /// The comparison to apply.
  final Comparison comparison;

  /// The source comparison, if known.
  final String? rawComparison;

  /// The target value, if known.
  final num? value;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'traderStanding',
    'traderId': traderId,
    'comparison': comparison.name,
    'rawComparison': rawComparison,
    'value': value,
  };
}

/// A skill level target.
final class SkillFacts extends ObjectiveFacts {
  /// Creates skill facts.
  const SkillFacts({this.skillId, this.level}) : super._();

  /// Restores skill facts from stored JSON.
  factory SkillFacts.fromJson(Map<String, Object?> json) {
    _expectKind(json, 'skill');
    return SkillFacts(
      skillId: _optional(json['skillId']),
      level: _optional(json['level']),
    );
  }

  /// The target skill ID, if known.
  final String? skillId;

  /// The target level, if known.
  final num? level;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'skill',
    'skillId': skillId,
    'level': level,
  };
}

/// The absence of type-specific objective facts.
final class NoFacts extends ObjectiveFacts {
  /// Creates empty facts.
  const NoFacts() : super._();

  /// Restores empty facts from stored JSON.
  factory NoFacts.fromJson(Map<String, Object?> json) {
    _expectKind(json, 'none');
    return const NoFacts();
  }

  @override
  Map<String, Object?> toJson() => {'kind': 'none'};
}
