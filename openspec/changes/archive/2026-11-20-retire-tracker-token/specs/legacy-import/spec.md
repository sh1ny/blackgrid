# Spec Delta

## MODIFIED Requirements

### Requirement: An import never changes this computer's own inputs
An import SHALL NOT change the game log folder, screenshot folder, follow-game-logs switch, live scan switch or scan hotkey, whether or not "Replace" is chosen. When no settings were stored before the import, those fields SHALL take their defaults.

#### Scenario: Replace keeps live scan and hotkey
- **WHEN** the stored settings have live scan on and scan hotkey F8, and the user imports a settings file with "Replace" chosen
- **THEN** after the import live scan is still on and the scan hotkey is still F8, and the imported mode, map and marker filters are in use

#### Scenario: Replace keeps input folders
- **WHEN** the stored settings name a game log folder and a screenshot folder and follow game logs is off, and the user imports with "Replace" chosen
- **THEN** both folders and the follow switch are unchanged

#### Scenario: Import with no stored settings
- **WHEN** no settings were stored and the user imports a settings file
- **THEN** live scan is off, the scan hotkey is the default and follow game logs is on

#### Scenario: Imported Tracker switch is ignored
- **WHEN** the imported settings file has `TrackerProgressEnabled` set to true
- **THEN** the import succeeds, its preview does not mention Tracker progress, and no saved setting holds the Tracker switch
