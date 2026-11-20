# Spec Delta

## ADDED Requirements

### Requirement: Problems the player must act on stay reachable from the main windows
Moving diagnostic detail SHALL NOT hide a problem the player must act on. In plain words, the Map and Scanner SHALL keep showing scan rejection and failure reasons, the recording stop note and the live scan state. Catalog and local progress errors SHALL stay reachable from them: the status bar SHALL show the item data and progress status words, which lead to the Settings sections that show the error text (Item and map data, Local progress).

#### Scenario: Rejected scan still explains itself
- **WHEN** a scan ends rejected `belowSimilarity` with best candidate X
- **THEN** the Scanner says the name did not match any item closely enough and shows X labelled not accepted, and no text on it contains `belowSimilarity`

#### Scenario: Errors the player must act on stay visible
- **WHEN** the catalog has an error, recording stopped because a write failed, and the Scanner is shown
- **THEN** the Scanner still shows the recording stop note and the status bar says item data is out of date, and following that status opens Settings at Item and map data, which shows the catalog error text

#### Scenario: Local progress error stays reachable
- **WHEN** local progress failed to load with an error and the Scanner is shown
- **THEN** the status bar says "Progress unavailable", and following it opens Settings at Local progress, which shows the load error text

### Requirement: Diagnostics shows item data and progress source detail
Expanded, Diagnostics SHALL describe the item data behind the item shown (a history item's saved data, else the live catalog): its source, its download time in UTC, the items source update time, the record count of each dataset, the price time in UTC, whether the effective mode's local progress can be read, and the age limits after which item data and prices count as old. With no complete catalog it SHALL say so.

#### Scenario: Current catalog
- **WHEN** a catalog downloaded at 2026-11-10T08:05:00Z is current and Diagnostics is expanded
- **THEN** Diagnostics shows the source, `2026-11-10T08:05:00.000Z` and each dataset's record count

#### Scenario: No catalog
- **WHEN** no complete catalog is available and Diagnostics is expanded
- **THEN** Diagnostics says there is no complete item data download and shows no record counts

#### Scenario: Local progress unavailable
- **WHEN** the effective mode's local progress cannot be read and Diagnostics is expanded
- **THEN** Diagnostics says local progress is unavailable, and no Diagnostics text mentions Tracker, a progress update time or a refresh cooldown

## REMOVED Requirements

### Requirement: Problems the player must act on stay on the main windows
**Reason**: Replaced by "Problems the player must act on stay reachable from the main windows", which names local progress instead of the removed Tracker.
**Migration**: None; the same rules apply with Local progress in place of Tracker progress.

### Requirement: Diagnostics shows data source detail
**Reason**: Replaced by "Diagnostics shows item data and progress source detail"; the Tracker update time and cooldown no longer exist.
**Migration**: None; Diagnostics shows whether local progress can be read.
