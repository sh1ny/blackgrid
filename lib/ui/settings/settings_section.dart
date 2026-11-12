/// A section of the Settings page that a link can target.
///
/// The values are in the order the page lists them, in its sidebar and in its
/// scrolling column.
enum SettingsSection {
  /// Theme, game mode and the app version.
  general('General'),

  /// Live scan, the scan key and recording scan frames.
  liveScan('Live scan'),

  /// Refreshing item data and map data.
  itemData('Item and map data'),

  /// Tracker progress and the Tracker token.
  tracker('Tracker progress'),

  /// Local log-derived progress and its active wipes.
  localProgress('Local progress'),

  /// The game log and screenshot folders, and Follow logs.
  gameFiles('Game files'),

  /// The raid timers and their settings.
  raidTimers('Raid timers'),

  /// Save marker filters.
  map('Map'),

  /// The collapsed technical detail.
  diagnostics('Diagnostics');

  const SettingsSection(this.title);

  /// The name shown in the sidebar and as the section title.
  final String title;
}
