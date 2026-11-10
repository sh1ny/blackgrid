# player-facing-text Specification

## Purpose
Defines what Blackgrid's screens may say to a player: plain-language labels for every state, reason and category it shows, local times, and developer detail kept in the Diagnostics section of Settings rather than in Details sections on the main windows.

## Requirements

### Requirement: Shown states use plain-language labels
Wherever a screen shows a catalog or Tracker progress status, a map input status, a raid panel state, a scan rejection reason, a scan failure code, a scan pass, a found-in-raid state or an activity source, it SHALL show a plain-language label for that value, never the value's internal name. Every value of each of these SHALL have a label, written as words with spaces, not camelCase.

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
- **WHEN** the Scanner's inspector is open with item data, a price time and Tracker progress all known
- **THEN** no text in the inspector contains an ISO 8601 time with `T` and `Z`

### Requirement: Raw enum names are never interpolated into UI text
The offline test suite SHALL include a check over `lib/ui` that fails when UI text interpolates `.name` of a status, state, reason, code, pass or found-in-raid value. The check SHALL name the file and line of each hit.

#### Scenario: Clean sources
- **WHEN** the check runs over the UI sources after this change
- **THEN** it reports no hit

#### Scenario: A regression
- **WHEN** a UI file contains `'Catalog: ${catalog.status.name}'`
- **THEN** the check fails and names that file and line

#### Scenario: A destructured regression
- **WHEN** a UI file contains `'Reason: ${reason.name}'` for a reason taken from a rejected scan
- **THEN** the check fails and names that file and line

#### Scenario: Keys are not text
- **WHEN** a UI file uses `ValueKey('results-${mode.name}')`
- **THEN** the check reports no hit for that line
