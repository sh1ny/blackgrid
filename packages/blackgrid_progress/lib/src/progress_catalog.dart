/// Immutable task and hideout catalog models and their stored JSON form.
library;

part 'progress_catalog_tasks.dart';
part 'progress_catalog_facts.dart';
part 'progress_catalog_hideout.dart';
part 'progress_catalog_other_requirements.dart';

/// The faction restriction on a task.
enum TaskFaction {
  /// Any faction may undertake the task.
  any,

  /// Only BEAR may undertake the task.
  bear,

  /// Only USEC may undertake the task.
  usec,

  /// The restriction is unknown.
  unknown,
}

/// A task status accepted by a requirement.
enum TaskStatus {
  /// The task is complete.
  complete,

  /// The task is active.
  active,

  /// The task has failed.
  failed,

  /// The status is unknown.
  unknown,
}

/// The kind of trader requirement.
enum TraderRequirementType {
  /// A trader loyalty level.
  level,

  /// A trader reputation value.
  reputation,

  /// An unknown requirement type.
  unknown,
}

/// A numeric comparison used by a requirement.
enum Comparison {
  /// Greater than or equal to the target.
  atLeast,

  /// Greater than the target.
  greaterThan,

  /// Less than or equal to the target.
  atMost,

  /// Less than the target.
  lessThan,

  /// Equal to the target.
  equal,

  /// An unknown comparison.
  unknown,
}

/// A task objective or fail-condition type.
enum ObjectiveType {
  /// Build a weapon.
  buildWeapon,

  /// Complete a dialogue.
  dialogue,

  /// Earn experience.
  experience,

  /// Extract from a raid.
  extract,

  /// Find an item.
  findItem,

  /// Find a quest item.
  findQuestItem,

  /// Hand over an item.
  giveItem,

  /// Hand over a quest item.
  giveQuestItem,

  /// Meet a global variable condition.
  globalVariable,

  /// Mark a target.
  mark,

  /// Plant an item.
  plantItem,

  /// Plant a quest item.
  plantQuestItem,

  /// Sell an item.
  sellItem,

  /// Shoot a target.
  shoot,

  /// Reach a skill target.
  skill,

  /// Meet a task status condition.
  taskStatus,

  /// Reach a trader level.
  traderLevel,

  /// Reach a trader standing.
  traderStanding,

  /// Use an item.
  useItem,

  /// Visit a location.
  visit,

  /// An unrecognized objective type.
  unknown,
}

/// A mode's immutable tasks and hideout stations.
///
/// Indexes and shared objective flags are derived on construction and are not
/// part of the stored representation.
final class ProgressCatalog {
  /// Creates a catalog and derives its indexes and shared objective flags.
  factory ProgressCatalog({
    required Iterable<CatalogTask> tasks,
    required Iterable<HideoutStation> stations,
  }) {
    final inputTasks = List<CatalogTask>.unmodifiable(tasks);
    final owners = <String, String>{};
    final shared = <String>{};
    for (final task in inputTasks) {
      for (final objective in task.objectives) {
        final owner = owners.putIfAbsent(objective.id, () => task.id);
        if (owner != task.id) shared.add(objective.id);
      }
    }
    List<CatalogTask>? changedTasks;
    final taskIndex = <String, CatalogTask>{};
    for (var i = 0; i < inputTasks.length; i++) {
      final task = inputTasks[i];
      final resolved = task._withSharedObjectives(shared);
      if (!identical(task, resolved)) {
        changedTasks ??= List<CatalogTask>.of(inputTasks);
        changedTasks[i] = resolved;
      }
      taskIndex[resolved.id] = resolved;
    }
    final stationList = List<HideoutStation>.unmodifiable(stations);
    return ProgressCatalog._(
      changedTasks == null
          ? inputTasks
          : List<CatalogTask>.unmodifiable(changedTasks),
      stationList,
      Map<String, CatalogTask>.unmodifiable(taskIndex),
      Map<String, HideoutStation>.unmodifiable({
        for (final station in stationList) station.id: station,
      }),
      Set<String>.unmodifiable(shared),
    );
  }

  ProgressCatalog._(
    this.tasks,
    this.stations,
    this.tasksById,
    this.stationsById,
    this.sharedObjectiveIds,
  );

  /// Restores a version-one stored catalog, rejecting malformed fields.
  factory ProgressCatalog.fromJson(Map<String, Object?> json) {
    final version = json['formatVersion'];
    if (version is! int || version != 1) {
      throw const FormatException(
        'Unsupported progress catalog format version',
      );
    }
    return ProgressCatalog(
      tasks: _requiredList(
        json['tasks'],
        (v) => CatalogTask.fromJson(_object(v)),
      ),
      stations: _requiredList(
        json['stations'],
        (v) => HideoutStation.fromJson(_object(v)),
      ),
    );
  }

  /// The tasks in source order.
  final List<CatalogTask> tasks;

  /// The hideout stations in source order.
  final List<HideoutStation> stations;

  /// Tasks indexed by their IDs.
  final Map<String, CatalogTask> tasksById;

  /// Stations indexed by their IDs.
  final Map<String, HideoutStation> stationsById;

  /// Objective IDs appearing under more than one task.
  final Set<String> sharedObjectiveIds;

  /// Encodes the versioned catalog without derived indexes or flags.
  Map<String, Object?> toJson() => {
    'formatVersion': 1,
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'stations': stations.map((station) => station.toJson()).toList(),
  };
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected an object');
  }
  return value;
}

T _required<T>(Object? value) {
  if (value is! T) throw FormatException('Expected $T');
  return value;
}

T? _optional<T>(Object? value) {
  if (value == null) return null;
  return _required<T>(value);
}

Iterable<T> _requiredList<T>(Object? value, T Function(Object?) decode) {
  if (value is! List<Object?>) throw const FormatException('Expected a list');
  return value.map(decode);
}

Iterable<T>? _optionalList<T>(Object? value, T Function(Object?) decode) =>
    value == null ? null : _requiredList(value, decode);

List<T>? _freeze<T>(Iterable<T>? value) =>
    value == null ? null : List<T>.unmodifiable(value);

T _enumValue<T extends Enum>(Object? value, List<T> values) {
  final name = _required<String>(value);
  for (final entry in values) {
    if (entry.name == name) return entry;
  }
  throw FormatException('Unknown enum value: $name');
}

Iterable<String>? _strings(Object? value) =>
    _optionalList(value, _required<String>);

Iterable<TaskStatus>? _statuses(Object? value) =>
    _optionalList(value, (v) => _enumValue(v, TaskStatus.values));

List<String>? _statusNames(List<TaskStatus>? statuses) =>
    statuses?.map((status) => status.name).toList();
