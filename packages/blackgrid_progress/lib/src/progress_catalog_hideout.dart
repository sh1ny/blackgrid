part of 'progress_catalog.dart';

/// A hideout station and its levels.
final class HideoutStation {
  /// Creates a station, copying its levels.
  HideoutStation({
    required this.id,
    required this.name,
    this.normalizedName,
    Iterable<StationLevel> levels = const [],
  }) : levels = List<StationLevel>.unmodifiable(levels);

  /// Restores a station from stored JSON.
  factory HideoutStation.fromJson(Map<String, Object?> json) => HideoutStation(
    id: _required(json['id']),
    name: _required(json['name']),
    normalizedName: _optional(json['normalizedName']),
    levels: _requiredList(
      json['levels'],
      (v) => StationLevel.fromJson(_object(v)),
    ),
  );

  /// The station ID.
  final String id;

  /// The display name.
  final String name;

  /// The normalized source name, if known.
  final String? normalizedName;

  /// The station levels.
  final List<StationLevel> levels;

  /// Encodes the station and its levels.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'normalizedName': normalizedName,
    'levels': levels.map((v) => v.toJson()).toList(),
  };
}

/// A hideout station level and its requirements.
final class StationLevel {
  /// Creates a station level, copying its requirement lists.
  StationLevel({
    required this.id,
    required this.level,
    this.constructionTime,
    Iterable<StationRequirement>? stationRequirements,
    Iterable<TraderRequirement>? traderRequirements,
    Iterable<SkillRequirement>? skillRequirements,
  }) : stationRequirements = _freeze(stationRequirements),
       traderRequirements = _freeze(traderRequirements),
       skillRequirements = _freeze(skillRequirements);

  /// Restores a station level from stored JSON.
  factory StationLevel.fromJson(Map<String, Object?> json) => StationLevel(
    id: _required(json['id']),
    level: _required(json['level']),
    constructionTime: _optional(json['constructionTime']),
    stationRequirements: _optionalList(
      json['stationRequirements'],
      (v) => StationRequirement.fromJson(_object(v)),
    ),
    traderRequirements: _optionalList(
      json['traderRequirements'],
      (v) => TraderRequirement.fromJson(_object(v)),
    ),
    skillRequirements: _optionalList(
      json['skillRequirements'],
      (v) => SkillRequirement.fromJson(_object(v)),
    ),
  );

  /// The station level ID.
  final String id;

  /// The level number.
  final int level;

  /// The construction time in seconds, if known.
  final num? constructionTime;

  /// The required station levels, or null if unknown.
  final List<StationRequirement>? stationRequirements;

  /// The trader requirements, or null if unknown.
  final List<TraderRequirement>? traderRequirements;

  /// The skill requirements, or null if unknown.
  final List<SkillRequirement>? skillRequirements;

  /// Encodes the level and its requirements.
  Map<String, Object?> toJson() => {
    'id': id,
    'level': level,
    'constructionTime': constructionTime,
    'stationRequirements': stationRequirements?.map((v) => v.toJson()).toList(),
    'traderRequirements': traderRequirements?.map((v) => v.toJson()).toList(),
    'skillRequirements': skillRequirements?.map((v) => v.toJson()).toList(),
  };
}

/// A required level of another hideout station.
final class StationRequirement {
  /// Creates a station requirement.
  const StationRequirement({required this.stationId, this.level});

  /// Restores a station requirement from stored JSON.
  factory StationRequirement.fromJson(Map<String, Object?> json) =>
      StationRequirement(
        stationId: _required(json['stationId']),
        level: _optional(json['level']),
      );

  /// The required station ID.
  final String stationId;

  /// The required level, if known.
  final int? level;

  /// Encodes the station requirement.
  Map<String, Object?> toJson() => {'stationId': stationId, 'level': level};
}

/// A required skill level.
final class SkillRequirement {
  /// Creates a skill requirement.
  const SkillRequirement({this.skillId, this.level});

  /// Restores a skill requirement from stored JSON.
  factory SkillRequirement.fromJson(Map<String, Object?> json) =>
      SkillRequirement(
        skillId: _optional(json['skillId']),
        level: _optional(json['level']),
      );

  /// The required skill ID, if known.
  final String? skillId;

  /// The required level, if known.
  final num? level;

  /// Encodes the skill requirement.
  Map<String, Object?> toJson() => {'skillId': skillId, 'level': level};
}
