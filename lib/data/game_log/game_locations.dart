import '../../domain/catalog.dart';

/// Maps the scene name of a `scene preset path:maps/<scene>.bundle` line to a
/// settings map ID, or `null` when the scene is not a supported map.
///
/// [scene] is compared case-insensitively. Persisted IDs remain settings IDs.
String? sceneMapId(String scene) {
  final name = scene.toLowerCase();
  return switch (name) {
    'factory4_day' ||
    'factory4_night' ||
    'factory_day_preset' ||
    'factory_night_preset' ||
    'factory_event_preset' => 'factory',
    'bigmap' || 'customs_preset' => 'customs',
    'woods' || 'woods_preset' => 'woods',
    'shoreline' || 'shoreline_preset' => 'shoreline',
    'interchange' || 'shopping_mall' => 'interchange',
    'laboratory' ||
    'laboratory_preset' ||
    'laboratory_event_preset' => 'thelab',
    'rezervbase' || 'rezerv_base_preset' => 'reserve',
    'lighthouse' || 'lighthouse_preset' => 'lighthouse',
    'tarkovstreets' || 'city_preset' => 'streetsoftarkov',
    'sandbox' ||
    'sandbox_preset' ||
    'sandbox_high' ||
    'sandbox_high_preset' ||
    'sandbox_start_preset' => 'groundzero',
    'terminal' || 'terminal_preset' => 'terminal',
    'labyrinth' || 'labyrinth_preset' => 'labyrinth',
    'icebreaker' => 'icebreaker',
    _ => null,
  };
}

/// Maps the `location:` of a transit reconnect line to a settings map ID, or
/// `null` when the location is unknown. [location] is case-insensitive.
///
/// Every map in `supportedMaps` must be reachable from this table and from
/// [sceneMapId]. A missing name makes that map's transit raids count as
/// "Unknown map" (#129). The coverage tests in `game_log_parsers_test.dart`
/// check both tables against `supportedMaps`.
String? rejoinLocationMapId(String location) =>
    switch (location.toLowerCase()) {
      'bigmap' => 'customs',
      'tarkovstreets' => 'streetsoftarkov',
      'shoreline' => 'shoreline',
      'rezervbase' => 'reserve',
      'lighthouse' => 'lighthouse',
      'laboratory' || 'laboratory_event' => 'thelab',
      'interchange' => 'interchange',
      'woods' => 'woods',
      'sandbox' || 'sandbox_high' => 'groundzero',
      'factory4_day' || 'factory4_night' || 'factory_event' => 'factory',
      'icebreaker' => 'icebreaker',
      'terminal' => 'terminal',
      'labyrinth' => 'labyrinth',
      _ => null,
    };

/// Maps the value of a `Session mode:` line to a [GameMode].
///
/// `PvpSeason` is [GameMode.seasonal]; unrecognised values are
/// [GameMode.unknown].
GameMode gameModeFromLog(String value) => switch (value.toLowerCase()) {
  'pve' => GameMode.pve,
  'pvp' || 'regular' => GameMode.pvp,
  'pvpseason' || 'seasonal' || 'szn' => GameMode.seasonal,
  _ => GameMode.unknown,
};
