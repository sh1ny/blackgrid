# Spec Delta

## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: Data sources panel reads in plain language
**Reason**: The Scanner no longer has a Data sources panel (owner decision S2 of `restyle-scanner-workspace`): it repeated the status bar, and the B view has no such section.
**Migration**: Item data and Tracker freshness are in the status bar and in Settings → Item and map data and Tracker progress, in the same plain words; the price time is in the strip and in the Prices section's Updated row; Refresh read-only progress is in Settings → Tracker progress; source URLs, UTC times and record counts stay in Diagnostics.
