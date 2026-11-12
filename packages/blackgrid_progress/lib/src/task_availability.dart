import 'progress_catalog.dart';

/// The computed availability of a task.
enum AvailabilityStatus {
  /// The task is already finished or permanently failed.
  done,

  /// No checked gate prevents the player from taking the task.
  available,

  /// At least one checked gate prevents the player from taking the task.
  locked,
}

/// An immutable task result with checked and unchecked reasons.
final class TaskAvailability {
  /// Creates a result, snapshotting both reason collections.
  TaskAvailability({
    required this.taskId,
    required this.status,
    this.started = false,
    Iterable<CheckedReason> checked = const [],
    Iterable<UncheckedReason> unchecked = const [],
  }) : checked = List.unmodifiable(checked),
       unchecked = List.unmodifiable(unchecked);

  /// The task ID.
  final String taskId;

  /// The computed status.
  final AvailabilityStatus status;

  /// Whether the player has already started the task.
  final bool started;

  /// Reasons established from known input facts.
  final List<CheckedReason> checked;

  /// Reasons that could not be evaluated from known input facts.
  final List<UncheckedReason> unchecked;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskAvailability &&
          taskId == other.taskId &&
          status == other.status &&
          started == other.started &&
          _listEquals(checked, other.checked) &&
          _listEquals(unchecked, other.unchecked);

  @override
  int get hashCode => Object.hash(
    taskId,
    status,
    started,
    Object.hashAll(checked),
    Object.hashAll(unchecked),
  );
}

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _setEquals<T>(Set<T> a, Set<T> b) =>
    identical(a, b) || a.length == b.length && a.containsAll(b);

/// A known task-state or failing gate reason.
sealed class CheckedReason {
  /// Creates a checked reason.
  const CheckedReason();
}

/// A gate that cannot be evaluated from the available facts.
sealed class UncheckedReason {
  /// Creates an unchecked reason.
  const UncheckedReason();
}

/// The task is recorded as finished.
final class Finished extends CheckedReason {
  /// Creates the reason.
  const Finished();

  @override
  bool operator ==(Object other) => identical(this, other) || other is Finished;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The task is recorded as failed and cannot be restarted.
final class Failed extends CheckedReason {
  /// Creates the reason.
  const Failed();

  @override
  bool operator ==(Object other) => identical(this, other) || other is Failed;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The player does not meet the minimum level.
final class LevelTooLow extends CheckedReason {
  /// Creates the reason with its source facts.
  const LevelTooLow({required this.required, required this.actual});

  /// The minimum player level.
  final int required;

  /// The recorded player level.
  final int actual;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LevelTooLow &&
          required == other.required &&
          actual == other.actual;

  @override
  int get hashCode => Object.hash(runtimeType, required, actual);
}

/// A trader loyalty requirement is not met.
final class LoyaltyTooLow extends CheckedReason {
  /// Creates the reason with its source facts.
  const LoyaltyTooLow({
    required this.traderId,
    required this.comparison,
    required this.required,
    required this.actual,
  });

  /// The required trader ID.
  final String traderId;

  /// The required comparison.
  final Comparison comparison;

  /// The required comparison value.
  final num required;

  /// The recorded loyalty level.
  final int actual;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoyaltyTooLow &&
          traderId == other.traderId &&
          comparison == other.comparison &&
          required == other.required &&
          actual == other.actual;

  @override
  int get hashCode =>
      Object.hash(runtimeType, traderId, comparison, required, actual);
}

/// A prerequisite task has not reached an accepted state.
final class PrerequisiteNotMet extends CheckedReason {
  /// Creates the reason with its source facts.
  PrerequisiteNotMet({required this.taskId, required Set<TaskStatus> needed})
    : needed = Set.unmodifiable(needed);

  /// The prerequisite task ID.
  final String taskId;

  /// The accepted prerequisite statuses.
  final Set<TaskStatus> needed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrerequisiteNotMet &&
          taskId == other.taskId &&
          _setEquals(needed, other.needed);

  @override
  int get hashCode =>
      Object.hash(runtimeType, taskId, Object.hashAllUnordered(needed));
}

/// A conflicting alternative task has been taken.
final class AlternativeTaken extends CheckedReason {
  /// Creates the reason with its source facts.
  const AlternativeTaken({required this.taskId});

  /// The alternative task ID.
  final String taskId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlternativeTaken && taskId == other.taskId;

  @override
  int get hashCode => Object.hash(runtimeType, taskId);
}

/// The player has the wrong faction for the task.
final class WrongFaction extends CheckedReason {
  /// Creates the reason with its source facts.
  const WrongFaction({required this.required});

  /// The task’s required faction.
  final TaskFaction required;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WrongFaction && required == other.required;

  @override
  int get hashCode => Object.hash(runtimeType, required);
}

/// The task is not available in the evaluated game mode.
final class WrongGameMode extends CheckedReason {
  /// Creates the reason with its source facts.
  WrongGameMode({required List<String> allowed})
    : allowed = List.unmodifiable(allowed);

  /// The allowed tarkov.dev game mode identifiers.
  final List<String> allowed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WrongGameMode && _listEquals(allowed, other.allowed);

  @override
  int get hashCode => Object.hash(runtimeType, Object.hashAll(allowed));
}

/// The player’s edition is not permitted for the task.
final class EditionNotPermitted extends CheckedReason {
  /// Creates the reason with its source facts.
  const EditionNotPermitted({required this.edition});

  /// The recorded edition identifier.
  final String edition;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditionNotPermitted && edition == other.edition;

  @override
  int get hashCode => Object.hash(runtimeType, edition);
}

/// The player level is unset.
final class LevelUnset extends UncheckedReason {
  /// Creates the reason with its source facts.
  const LevelUnset({required this.required});

  /// The minimum player level.
  final int required;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LevelUnset && required == other.required;

  @override
  int get hashCode => Object.hash(runtimeType, required);
}

/// The task’s minimum player level is unknown.
final class LevelRequirementUnknown extends UncheckedReason {
  /// Creates the reason.
  const LevelRequirementUnknown();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LevelRequirementUnknown;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A required trader loyalty level is unset.
final class LoyaltyUnset extends UncheckedReason {
  /// Creates the reason with its source facts.
  const LoyaltyUnset({required this.traderId});

  /// The required trader ID.
  final String traderId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoyaltyUnset && traderId == other.traderId;

  @override
  int get hashCode => Object.hash(runtimeType, traderId);
}

/// A trader loyalty requirement cannot be interpreted.
final class LoyaltyRequirementUnknown extends UncheckedReason {
  /// Creates the reason with its source facts.
  const LoyaltyRequirementUnknown({required this.traderId});

  /// The required trader ID.
  final String traderId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoyaltyRequirementUnknown && traderId == other.traderId;

  @override
  int get hashCode => Object.hash(runtimeType, traderId);
}

/// A trader reputation requirement cannot be evaluated.
final class ReputationRequirement extends UncheckedReason {
  /// Creates the reason with its source facts.
  const ReputationRequirement({required this.traderId});

  /// The required trader ID.
  final String traderId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReputationRequirement && traderId == other.traderId;

  @override
  int get hashCode => Object.hash(runtimeType, traderId);
}

/// The task’s prerequisite list is unknown.
final class PrerequisitesUnknown extends UncheckedReason {
  /// Creates the reason.
  const PrerequisitesUnknown();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PrerequisitesUnknown;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A prerequisite has no known accepted status.
final class PrerequisiteStatusUnknown extends UncheckedReason {
  /// Creates the reason with its source facts.
  const PrerequisiteStatusUnknown({required this.taskId});

  /// The prerequisite task ID.
  final String taskId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrerequisiteStatusUnknown && taskId == other.taskId;

  @override
  int get hashCode => Object.hash(runtimeType, taskId);
}

/// A finished prerequisite may have unlocked the task while active.
final class ActivePrerequisiteFinished extends UncheckedReason {
  /// Creates the reason with its source facts.
  const ActivePrerequisiteFinished({required this.taskId});

  /// The prerequisite task ID.
  final String taskId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivePrerequisiteFinished && taskId == other.taskId;

  @override
  int get hashCode => Object.hash(runtimeType, taskId);
}

/// The task’s alternative list is unknown.
final class AlternativesUnknown extends UncheckedReason {
  /// Creates the reason.
  const AlternativesUnknown();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AlternativesUnknown;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The player faction is unset for a restricted task.
final class FactionUnset extends UncheckedReason {
  /// Creates the reason with its source facts.
  const FactionUnset({required this.required});

  /// The task’s required faction.
  final TaskFaction required;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FactionUnset && required == other.required;

  @override
  int get hashCode => Object.hash(runtimeType, required);
}

/// The task’s faction restriction is unknown.
final class FactionUnknown extends UncheckedReason {
  /// Creates the reason.
  const FactionUnknown();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FactionUnknown;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The player edition is unset for a restricted task.
final class EditionUnset extends UncheckedReason {
  /// Creates the reason.
  const EditionUnset();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EditionUnset;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The player edition is not in the table vocabulary.
final class EditionUnrecognised extends UncheckedReason {
  /// Creates the reason with its source facts.
  const EditionUnrecognised({required this.edition});

  /// The recorded edition identifier.
  final String edition;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditionUnrecognised && edition == other.edition;

  @override
  int get hashCode => Object.hash(runtimeType, edition);
}

/// A global-variable requirement cannot be evaluated.
final class GlobalVariable extends UncheckedReason {
  /// Creates the reason with its source facts.
  const GlobalVariable({required this.variableId});

  /// The variable ID, or null if unknown.
  final String? variableId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlobalVariable && variableId == other.variableId;

  @override
  int get hashCode => Object.hash(runtimeType, variableId);
}

/// A trader-dialogue requirement cannot be evaluated.
final class TraderDialogue extends UncheckedReason {
  /// Creates the reason with its source facts.
  TraderDialogue({required List<String>? traderIds})
    : traderIds = traderIds == null ? null : List.unmodifiable(traderIds);

  /// The trader IDs, or null if unknown.
  final List<String>? traderIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraderDialogue && _listEquals(traderIds, other.traderIds);

  @override
  int get hashCode => Object.hash(
    runtimeType,
    traderIds == null ? null : Object.hashAll(traderIds!),
  );
}

/// An other requirement has an unrecognized type.
final class OtherRequirementUnknownType extends UncheckedReason {
  /// Creates the reason with its source facts.
  const OtherRequirementUnknownType({required this.rawType});

  /// The original type, or null if unknown.
  final String? rawType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OtherRequirementUnknownType && rawType == other.rawType;

  @override
  int get hashCode => Object.hash(runtimeType, rawType);
}

/// The task’s other requirements are unknown.
final class OtherRequirementsUnknown extends UncheckedReason {
  /// Creates the reason.
  const OtherRequirementsUnknown();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is OtherRequirementsUnknown;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A nonzero availability delay cannot be evaluated.
final class AvailabilityDelay extends UncheckedReason {
  /// Creates the reason with its source facts.
  const AvailabilityDelay({required this.minSeconds, required this.maxSeconds});

  /// The minimum delay in seconds, or null if unknown.
  final int? minSeconds;

  /// The maximum delay in seconds, or null if unknown.
  final int? maxSeconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvailabilityDelay &&
          minSeconds == other.minSeconds &&
          maxSeconds == other.maxSeconds;

  @override
  int get hashCode => Object.hash(runtimeType, minSeconds, maxSeconds);
}

/// The task’s availability delay is unknown.
final class AvailabilityDelayUnknown extends UncheckedReason {
  /// Creates the reason.
  const AvailabilityDelayUnknown();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AvailabilityDelayUnknown;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A prestige requirement cannot be evaluated.
final class PrestigeRequired extends UncheckedReason {
  /// Creates the reason with its source facts.
  const PrestigeRequired({required this.prestigeId});

  /// The required prestige ID.
  final String prestigeId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrestigeRequired && prestigeId == other.prestigeId;

  @override
  int get hashCode => Object.hash(runtimeType, prestigeId);
}
