# Spec Delta

## MODIFIED Requirements

### Requirement: Developer wording stays out of the open view
Text shown outside the Diagnostics section of Settings SHALL NOT contain these terms: `canonical`, `identity`, `durable`, `DPAPI`, `authority`, `authorized`, `normalized`, `M1`, `gross RUB` or `session-only`. Internal category keys and tarkov.dev IDs SHALL NOT be shown when a name resolves. Search SHALL still find an item by its ID.

#### Scenario: Search field hint
- **WHEN** the shell's search field is empty
- **THEN** its hint asks for an item name and does not contain `canonical`

#### Scenario: Searching by ID still works
- **WHEN** the user types a known item's tarkov.dev ID into the search field
- **THEN** that item is offered as a result

#### Scenario: Name does not resolve
- **WHEN** a history row's item has no name in the current catalog
- **THEN** the row shows the item's ID instead of dropping the row

#### Scenario: Term check over the UI sources
- **WHEN** the offline source check reads the string literals under `lib/ui`, in the controllers that write player-visible messages, in the decision engine's warnings and reasons, and in the legacy import plan
- **THEN** no string literal other than a widget key contains a listed term, and the check fails naming the file and line when one does

### Requirement: Times are shown in local time
Times shown outside the Diagnostics section of Settings SHALL be in the user's local time zone, as a time for today and a date and time for an earlier day, never as a UTC ISO 8601 string. A missing time SHALL be shown as unknown. UTC ISO 8601 times SHALL appear only inside Diagnostics.

#### Scenario: History row time
- **WHEN** a history row was observed today at 14:32 local time
- **THEN** the row shows `14:32` and no `T` or `Z` ISO time

#### Scenario: Earlier day
- **WHEN** a history row was observed on an earlier day
- **THEN** the row shows that day's date with the time

#### Scenario: Missing flea quote time
- **WHEN** the flea quote has no source time
- **THEN** the Data sources panel says the price time is unknown

#### Scenario: No UTC time in the inspector
- **WHEN** the Scanner's inspector is open with item data, a price time and Tracker progress all known
- **THEN** no text in the inspector contains an ISO 8601 time with `T` and `Z`

### Requirement: Data sources panel reads in plain language
The Scanner panel that showed source authority SHALL be titled "Data sources". It SHALL say whether item data and Tracker progress are up to date, missing, loading, out of date, failed or cooling down, and when each was last updated. It SHALL have no Details section: the source URL, UTC times, record counts, freshness limits and the cooldown end time SHALL be shown only in Settings under Diagnostics. Refresh read-only progress SHALL stay in the panel.

#### Scenario: Current item data
- **WHEN** the catalog is current and was downloaded today at 09:05
- **THEN** the panel says item data is up to date and was updated at 09:05, and shows no source URL, no record count and no Details control

#### Scenario: No catalog
- **WHEN** no complete catalog is available and the catalog status is missing (no download running or failed)
- **THEN** the panel says item data is not downloaded yet

#### Scenario: Tracker in cooldown
- **WHEN** Tracker progress is in cooldown
- **THEN** the panel says progress refresh is cooling down and shows no cooldown end time

## REMOVED Requirements

### Requirement: Details sections start collapsed
**Reason**: The scan evidence and Data sources Details sections were the only Details sections on the Map and Scanner. Their content moves to the Diagnostics section of Settings, which starts collapsed each time Settings opens (`map-rail`), so no Details section is left whose expansion could persist.
**Migration**: Diagnostic detail is in Settings under Diagnostics; see `settings-diagnostics` and `map-rail`.
