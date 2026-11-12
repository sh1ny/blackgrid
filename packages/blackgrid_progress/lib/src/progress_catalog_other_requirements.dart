part of 'progress_catalog.dart';

/// An extra task condition whose game state is not locally observable.
sealed class OtherRequirement {
  const OtherRequirement._(this.id);

  /// The source requirement ID.
  final String id;

  /// Restores a condition from its stored discriminator and fields.
  static OtherRequirement fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'globalVariable' => GlobalVariableRequirement(
          id: _required(json['id']),
          variableId: _optional(json['variableId']),
          comparison: _enumValue(json['comparison'], Comparison.values),
          rawComparison: _optional(json['rawComparison']),
          value: _optional(json['value']),
        ),
        'dialogue' => DialogueRequirement(
          id: _required(json['id']),
          traderIds: _strings(json['traderIds']),
        ),
        'unknown' => UnknownOtherRequirement(
          id: _required(json['id']),
          rawType: _optional(json['rawType']),
        ),
        _ => throw const FormatException('Unknown other requirement kind'),
      };

  /// Encodes the condition with a stored subtype discriminator.
  Map<String, Object?> toJson();
}

/// An opaque game counter comparison.
final class GlobalVariableRequirement extends OtherRequirement {
  /// Creates an unresolved global-variable condition.
  const GlobalVariableRequirement({
    required String id,
    this.variableId,
    this.comparison = Comparison.unknown,
    this.rawComparison,
    this.value,
  }) : super._(id);

  /// The game variable ID, if known.
  final String? variableId;

  /// The comparison against the counter.
  final Comparison comparison;

  /// The source comparison, if known.
  final String? rawComparison;

  /// The comparison target, if known.
  final num? value;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'globalVariable',
    'id': id,
    'variableId': variableId,
    'comparison': comparison.name,
    'rawComparison': rawComparison,
    'value': value,
  };
}

/// A required dialogue with one or more unresolved traders.
final class DialogueRequirement extends OtherRequirement {
  /// Creates a dialogue condition, copying the trader IDs.
  DialogueRequirement({required String id, Iterable<String>? traderIds})
    : traderIds = _freeze(traderIds),
      super._(id);

  /// The source trader IDs, or `null` if unknown.
  final List<String>? traderIds;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'dialogue',
    'id': id,
    'traderIds': traderIds,
  };
}

/// An extra condition with an unrecognised source type.
final class UnknownOtherRequirement extends OtherRequirement {
  /// Creates an unknown condition without discarding its source type.
  const UnknownOtherRequirement({required String id, this.rawType})
    : super._(id);

  /// The unrecognised source type, if known.
  final String? rawType;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'unknown',
    'id': id,
    'rawType': rawType,
  };
}
