# legacy-import Specification

## Purpose
Defines what an explicit import of the reference companion's settings and history files may change in Blackgrid's stored data, and guarantees that an import either completes as a whole or leaves every stored record unchanged.

## Requirements

### Requirement: An import never changes this computer's own inputs
An import SHALL NOT change the game log folder, screenshot folder, follow-game-logs switch, live scan switch or scan hotkey, whether or not "Replace" is chosen. When no settings were stored before the import, those fields SHALL take their defaults.

#### Scenario: Replace keeps live scan and hotkey
- **WHEN** the stored settings have live scan on and scan hotkey F8, and the user imports a settings file with "Replace" chosen
- **THEN** after the import live scan is still on and the scan hotkey is still F8, and the imported mode, map, marker filters and Tracker switch are in use

#### Scenario: Replace keeps input folders
- **WHEN** the stored settings name a game log folder and a screenshot folder and follow game logs is off, and the user imports with "Replace" chosen
- **THEN** both folders and the follow switch are unchanged

#### Scenario: Import with no stored settings
- **WHEN** no settings were stored and the user imports a settings file
- **THEN** live scan is off, the scan hotkey is the default and follow game logs is on

### Requirement: A failed import changes nothing, also after a restart
An import SHALL write its settings, pins, history entries and import record in one step. When any write fails, the stored settings, pins, history and import records SHALL be exactly as before the import, also after the database is closed and reopened, and the same files SHALL still be importable.

#### Scenario: Failure on the last write
- **WHEN** an import of settings, two pins and two history entries fails while writing its import record, and the database is closed and reopened
- **THEN** settings, pins and history read back equal to their state before the import, no import record exists, and importing the same files again succeeds

#### Scenario: Successful import survives a restart
- **WHEN** an import of settings, two pins and two history entries succeeds, and the database is closed and reopened
- **THEN** the imported pins and history entries read back and the import record exists

### Requirement: The import dialog says why nothing was imported
When the user commits an import of files that were already imported, the dialog SHALL say "These files were already imported. Nothing was changed." When the commit fails for any other reason, it SHALL say "The import could not be saved. Nothing was changed."

#### Scenario: Files already imported
- **WHEN** the user commits an import whose files another import committed first (after the preview was shown)
- **THEN** the dialog shows "These files were already imported. Nothing was changed."

#### Scenario: Storage failure during commit
- **WHEN** the commit fails because the database write fails
- **THEN** the dialog shows "The import could not be saved. Nothing was changed."

### Requirement: The import preview keeps technical detail under Details
The import preview SHALL show the record, pin and history counts, the settings to import, each pin, what was left out, what is never imported and the Replace choice. The file fingerprint and the per-record lines (kind, input order, key, disposition and reason) SHALL sit under a "Details" toggle that is collapsed each time a preview is read.

#### Scenario: Preview read
- **WHEN** the player reads a preview of a history file with 3 records
- **THEN** the dialog shows "3 records found" and the Replace choice, and shows no fingerprint or per-record line until Details is opened

#### Scenario: Details opened
- **WHEN** the player opens Details
- **THEN** the file fingerprint and one line per record show

#### Scenario: New preview resets Details
- **WHEN** Details is open and the player reads another preview
- **THEN** Details is collapsed

#### Scenario: Already imported
- **WHEN** the preview is of files that were already imported
- **THEN** the dialog says "These files were already imported." and Import now is disabled
