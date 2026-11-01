# local-data-durability Specification

## Purpose
Defines how stored settings, custom pins and item history load at startup, survive a restart, and degrade when a stored record or the database itself cannot be read, so that a bad record never costs the user the rest of their data or the app.

## Requirements

### Requirement: Settings, pins and history survive a restart
Settings, custom pins and item history that were saved SHALL be read back unchanged after the app closes its database and opens it again. A pin the user removed SHALL stay removed after the restart.

#### Scenario: Saved records reopen unchanged
- **WHEN** the user saves non-default settings, adds two pins on different maps and records two history entries, and the database is closed and reopened
- **THEN** the settings, both pins and both history entries read back equal to what was saved

#### Scenario: Removed pin stays removed
- **WHEN** the user adds two pins, removes one, and the database is closed and reopened
- **THEN** only the pin that was not removed reads back

#### Scenario: Failed save is not visible after restart
- **WHEN** saving new settings fails, and the database is closed and reopened
- **THEN** the settings read back are the ones saved before the failed save

### Requirement: Unreadable settings start the session with defaults
When the stored settings record cannot be read, because it is damaged or was written by a newer Blackgrid version, the app SHALL start with default settings and show "Your saved settings could not be read. Default settings are in use until you change one." Loading SHALL NOT rewrite the stored record. The next successful settings save SHALL replace it.

#### Scenario: Damaged settings record at startup
- **WHEN** the stored settings record is not valid JSON and the app starts
- **THEN** the app finishes starting with default settings, the message is shown, and the stored record's bytes are unchanged

#### Scenario: Settings written by a newer version
- **WHEN** the stored settings record names a mode or map this version does not know and the app starts
- **THEN** the app finishes starting with default settings and the message is shown

#### Scenario: Readable settings show no message
- **WHEN** the stored settings record is valid and the app starts
- **THEN** the saved settings are in use and no settings message is shown

#### Scenario: Next save replaces the unreadable record
- **WHEN** the app started with defaults after an unreadable settings record, and the user changes one setting
- **THEN** the save succeeds, the message is cleared, and after a restart the changed settings read back

#### Scenario: Replace import clears the message
- **WHEN** the app started with defaults after an unreadable settings record, and an import of a settings file with "Replace" chosen succeeds
- **THEN** the imported settings are in use and the settings message is cleared

### Requirement: Unreadable pins are skipped, not fatal
When some stored pin records cannot be read, the app SHALL start, show every readable pin, and show "N saved pins could not be read and are not shown." (with N the count, "1 saved pin" for one). Loading SHALL NOT delete or rewrite the unreadable records.

#### Scenario: One damaged pin among readable ones
- **WHEN** three pins are stored, one of them not valid JSON, and the app starts
- **THEN** the two readable pins are shown, the message says "1 saved pin could not be read and is not shown.", and all three records are still stored

#### Scenario: All pins readable
- **WHEN** every stored pin is readable and the app starts
- **THEN** every pin is shown and no pin message is shown

### Requirement: Unreadable history entries are skipped, not fatal
When some stored history entries cannot be read, the history panel SHALL show every readable entry and the message "N history entries could not be read and are not shown." ("1 history entry … is not shown" for one). Loading SHALL NOT delete or rewrite the unreadable entries.

#### Scenario: One entry with an unknown mode
- **WHEN** three history entries are stored, one naming a mode this version does not know, and history loads
- **THEN** the two readable entries are listed and the message says "1 history entry could not be read and is not shown."

#### Scenario: All entries readable
- **WHEN** every stored history entry is readable and history loads
- **THEN** every entry is listed and no history message is shown

### Requirement: History errors stay visible while entries are listed
The history panel SHALL show its current error message whether or not it lists entries.

#### Scenario: Recording fails while entries are listed
- **WHEN** the history panel lists entries and recording an accepted scan fails
- **THEN** the panel still lists the entries and shows "The accepted scan was not recorded in history."

#### Scenario: Empty history with no error
- **WHEN** no history entries are stored and none failed to load
- **THEN** the panel shows "No items yet." and no error

### Requirement: A database from a newer version is refused with its own message
When the stored database was written by a newer Blackgrid version, the startup screen SHALL show "Your data was saved by a newer version of Blackgrid. Install that version or a later one to open it. Your data has not been changed." The database file SHALL NOT be downgraded, reset, deleted or modified. Other storage failures SHALL keep the existing generic message.

#### Scenario: Newer schema version on disk
- **WHEN** the database file's schema version is higher than this build's and the app starts
- **THEN** the startup screen shows the newer-version message and the file's bytes are unchanged

#### Scenario: Other open failure
- **WHEN** opening local storage fails for any other reason
- **THEN** the startup screen shows "Local storage or current-user protection could not be opened. Existing data is not reset, downgraded or deleted."

### Requirement: A damaged saved token reports the token as unavailable
When the saved Tracker token file for a mode holds bytes that cannot be decrypted, reading it SHALL report the token as unavailable without any Tracker request and without any plaintext fallback. Saving a new token for that mode SHALL replace the damaged file, and the new token SHALL read back after a restart.

#### Scenario: Corrupt token bytes on disk
- **WHEN** the token file for a mode holds random bytes and the app selects that mode
- **THEN** progress status is `failed` with "Tracker token unavailable" and no Tracker request is made

#### Scenario: Saving a new token recovers
- **WHEN** the token file is damaged and the user saves a new token for that mode, and the store is reopened
- **THEN** the new token reads back
