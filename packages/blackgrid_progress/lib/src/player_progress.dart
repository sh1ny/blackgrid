/// The game mode evaluated by the progress rules.
enum ProgressMode {
  /// The regular PvP mode.
  regular('regular'),

  /// The PvE mode.
  pve('pve'),

  /// The seasonal PvP mode.
  seasonal('pvp-season');

  const ProgressMode(this.tarkovDevName);

  /// The mode identifier used by tarkov.dev task restrictions.
  final String tarkovDevName;
}

/// A recorded task state; an absent state means not started.
enum TaskProgressState {
  /// The player has started the task.
  started,

  /// The player has failed the task.
  failed,

  /// The player has finished the task.
  finished,
}

/// The player's selected faction.
enum PlayerFaction {
  /// The BEAR faction.
  bear,

  /// The USEC faction.
  usec,
}

/// An immutable snapshot of the player's known progress in one mode.
///
/// A missing map key or a null scalar represents an unset value.
final class PlayerProgress {
  /// Creates a snapshot, copying both maps so later caller changes are isolated.
  PlayerProgress({
    Map<String, TaskProgressState> taskStates = const {},
    this.level,
    this.faction,
    this.edition,
    Map<String, int> traderLoyalty = const {},
  }) : taskStates = Map.unmodifiable(taskStates),
       traderLoyalty = Map.unmodifiable(traderLoyalty);

  /// Recorded task states keyed by task ID.
  final Map<String, TaskProgressState> taskStates;

  /// The player's level, or null if unset.
  final int? level;

  /// The player's faction, or null if unset.
  final PlayerFaction? faction;

  /// The edition identifier, or null if unset.
  final String? edition;

  /// Recorded trader loyalty levels keyed by trader ID.
  final Map<String, int> traderLoyalty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerProgress &&
          level == other.level &&
          faction == other.faction &&
          edition == other.edition &&
          _mapEquals(taskStates, other.taskStates) &&
          _mapEquals(traderLoyalty, other.traderLoyalty);

  @override
  int get hashCode => Object.hash(
    level,
    faction,
    edition,
    _mapHash(taskStates),
    _mapHash(traderLoyalty),
  );
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}

int _mapHash<K, V>(Map<K, V> values) => Object.hashAllUnordered(
  values.entries.map((entry) => Object.hash(entry.key, entry.value)),
);
