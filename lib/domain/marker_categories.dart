/// Player-facing labels and display order for marker category keys.
library;

/// The saveable marker category keys and their player-facing labels, in
/// display order.
///
/// Related categories sit together: extracts and transits, quests, danger,
/// spawns, loot, utility, and Saved pins last. The keys are exactly
/// `markerCategories` without `Labels`, which no marker carries.
const markerCategoryLabels = <(String key, String label)>[
  ('PmcExtracts', 'PMC extracts'),
  ('ScavExtracts', 'Scav extracts'),
  ('SharedExtracts', 'Shared extracts'),
  ('Transits', 'Transits'),
  ('QuestItems', 'Quest items'),
  ('QuestObjectives', 'Quest objectives'),
  ('Hazards', 'Hazards'),
  ('HazardZones', 'Hazard zones'),
  ('BossSpawns', 'Bosses'),
  ('CultistSpawns', 'Cultists'),
  ('PmcSpawns', 'PMC spawns'),
  ('ScavSpawns', 'Scav spawns'),
  ('lootContainers', 'Containers'),
  ('lootLoose', 'Loose loot'),
  ('locks', 'Locks'),
  ('Switches', 'Switches'),
  ('BtrStops', 'BTR stops'),
  ('stationaryWeapons', 'Stationary weapons'),
  ('CustomPins', 'Saved pins'),
];

final _labelByKey = {
  for (final (key, label) in markerCategoryLabels) key: label,
};

/// Returns the player-facing label for the marker category [key].
///
/// A key with no label, such as an unmapped pack category, is returned
/// unchanged.
String markerCategoryLabel(String key) => _labelByKey[key] ?? key;

/// Returns the [keys] that are saveable marker preferences, in display
/// order.
///
/// Keys without a label are dropped, so they never get a tile or a
/// settings write. The order of [keys] does not matter.
List<String> markerPreferenceKeys(Iterable<String> keys) {
  final present = keys.toSet();
  return [
    for (final (key, _) in markerCategoryLabels)
      if (present.contains(key)) key,
  ];
}
