# Spec Delta

## MODIFIED Requirements

### Requirement: Shown states use plain-language labels
Wherever a screen shows a catalog status, a local progress status, a map input status, a raid panel state, a scan rejection reason, a scan failure code, a scan pass, a found-in-raid state or an activity source, it SHALL show a plain-language label for that value, never the value's internal name. Every value of each of these SHALL have a label, written as words with spaces, not camelCase.

#### Scenario: Stale catalog in the footer
- **WHEN** the catalog status is stale
- **THEN** the footer says the item data is out of date, and no footer text contains `stale`

#### Scenario: Imported scan in history
- **WHEN** a history row's activity source is an imported scan
- **THEN** the row says "Imported scan", and no row text contains `importedScan`

#### Scenario: Every value has a label
- **WHEN** the label of each value of each listed kind is taken
- **THEN** every label is non-empty, differs from the value's internal name unless that name is one lowercase word, and contains no lowercase letter followed by an uppercase letter

#### Scenario: Unknown found-in-raid state
- **WHEN** the decision card shows an item whose found-in-raid state is unknown
- **THEN** the card says found in raid is unknown in words, and no card text contains `FIR: unknown`

### Requirement: Times are shown in local time
History row ages and the answer strip's provenance line SHALL be relative ages (workspace-shell). Other times shown outside the Diagnostics section of Settings SHALL be in the user's local time zone, as a time for today and a date and time for an earlier day, never as a UTC ISO 8601 string. A missing time SHALL be shown as unknown. UTC ISO 8601 times SHALL appear only inside Diagnostics.

#### Scenario: History row time
- **WHEN** a history row was observed 3 minutes ago
- **THEN** the row shows `3 min` and no `T` or `Z` ISO time

#### Scenario: Earlier day
- **WHEN** a history row was observed 2 days ago
- **THEN** the row shows `2 d`

#### Scenario: Missing flea quote time
- **WHEN** the flea quote has no source time
- **THEN** the answer strip and the Updated row of the Scanner's Prices section say "price time unknown"

#### Scenario: No UTC time in the inspector
- **WHEN** the Scanner's inspector is open with item data, a price time and progress all known
- **THEN** no text in the inspector contains an ISO 8601 time with `T` and `Z`
