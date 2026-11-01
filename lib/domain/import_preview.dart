import 'catalog.dart';
import 'settings.dart';

class ImportAccounting {
  const ImportAccounting({
    required this.kind,
    required this.key,
    required this.inputOrder,
    required this.disposition,
    required this.reason,
  });
  final String kind, key, disposition, reason;
  final int inputOrder;
}

/// The preferences a settings file carries into an import.
///
/// Holds only what an import may change. Local inputs such as the game log
/// folder, screenshot folder, follow-game-logs switch, live scan switch and
/// scan hotkey always come from the stored settings at commit time.
class ImportedPreferences {
  /// Creates the imported preferences.
  ImportedPreferences({
    required this.mode,
    required this.selectedMap,
    required this.saveMarkerFilters,
    required Map<String, bool> markerFilters,
    required this.trackerEnabled,
  }) : markerFilters = Map.unmodifiable(markerFilters);

  /// The imported game mode.
  final GameMode mode;

  /// The imported selected map id.
  final String selectedMap;

  /// Whether marker filters are remembered.
  final bool saveMarkerFilters;

  /// The imported marker filter switches by category.
  final Map<String, bool> markerFilters;

  /// Whether Tracker progress is used.
  final bool trackerEnabled;

  /// Returns [base] with these preferences applied and every other field kept.
  AppSettings applyTo(AppSettings base) => base.copyWith(
    mode: mode,
    selectedMap: selectedMap,
    saveMarkerFilters: saveMarkerFilters,
    markerFilters: markerFilters,
    trackerEnabled: trackerEnabled,
  );
}

class ImportPreview {
  ImportPreview({
    required this.digest,
    this.formatVersion = 1,
    this.settings,
    required Iterable<CustomPin> pins,
    required Iterable<ItemActivity> winningActivity,
    required Iterable<ImportAccounting> accounting,
    required Iterable<String> exclusions,
    required Iterable<String> sourcePaths,
    this.alreadyImported = false,
  }) : pins = List.unmodifiable(pins),
       winningActivity = List.unmodifiable(winningActivity),
       accounting = List.unmodifiable(accounting),
       exclusions = List.unmodifiable(exclusions),
       sourcePaths = List.unmodifiable(sourcePaths);
  final String digest;
  final int formatVersion;
  final ImportedPreferences? settings;
  final List<CustomPin> pins;
  final List<ItemActivity> winningActivity;
  final List<ImportAccounting> accounting;
  final List<String> exclusions, sourcePaths;
  final bool alreadyImported;
}
