# catalog-authority Specification

## Purpose
Decides when a validated mode-scoped catalog snapshot may back item decisions, how long that authority lasts, and which source-time evidence the snapshot keeps for display.

## Requirements

### Requirement: Catalog authority is measured from download time
A catalog snapshot SHALL be authoritative only when its source is `json.tarkov.dev`, its schema and normalizer versions are supported, its mode is known, and the check time is at or after its observation (validated download) time and no more than 24 h after it. Source timestamps SHALL neither grant nor revoke authority.

#### Scenario: Live wire shape becomes current
- **WHEN** a refresh validates six datasets shaped like the live API (top-level `data` and `translations` only, with no top-level `updated`), observed at T
- **THEN** the snapshot is authoritative at T and the catalog status after the refresh is `current`

#### Scenario: No source timestamp anywhere
- **WHEN** a snapshot observed at T has no source timestamp for any dataset
- **THEN** it is authoritative at T + 24 h and not authoritative at T + 24 h + 1 ms

#### Scenario: Old source timestamp does not revoke authority
- **WHEN** a snapshot observed at T records an items source update time of T − 30 days
- **THEN** it is authoritative at T + 1 h

#### Scenario: Observation in the future
- **WHEN** a snapshot's observation time is later than the check time
- **THEN** it is not authoritative

#### Scenario: Unsupported source or unknown mode
- **WHEN** a snapshot observed at T claims a source other than `json.tarkov.dev`, or its mode is unknown
- **THEN** it is not authoritative at T

### Requirement: Current catalog status expires 24 h after observation
After a refresh publishes a `current` catalog observed at T, the status SHALL change to `stale` once the time passes T + 24 h, without any new network request. A source timestamp SHALL NOT bring that expiry earlier. A catalog loaded from the local cache SHALL start `stale` until a refresh succeeds.

#### Scenario: Expiry at the observation limit
- **WHEN** a refresh publishes a `current` catalog observed at T and the time reaches T + 24 h + 1 ms
- **THEN** the status is `stale`, authority listeners are notified, and no further fetch was made

#### Scenario: Old items update time does not shorten the window
- **WHEN** a refresh publishes a catalog observed at T whose items source update time is T − 23 h
- **THEN** the status is still `current` at T + 2 h, and it becomes `stale` at T + 24 h + 1 ms through the expiry timer alone, with no other age check and no further fetch

#### Scenario: Cached snapshot at startup
- **WHEN** the app selects a mode and loads a cached snapshot observed less than 24 h ago, before any refresh
- **THEN** the status is `stale`

### Requirement: Source-time evidence reflects what the source provides
A snapshot SHALL keep one source-time entry for each of the six datasets. The `items` entry SHALL be the newest per-item `updated` value. Every other entry SHALL be absent, and so SHALL the `items` entry when no item has `updated`. A per-item `updated` that is not a time SHALL fail validation, as before. A dataset-level `updated` field SHALL be ignored. The evidence view SHALL show the items source update time or say it is unknown.

#### Scenario: Newest item update recorded
- **WHEN** items carry `updated` values `2026-10-05T10:00:00Z` and `2026-10-05T23:00:00Z`
- **THEN** the items source time is `2026-10-05T23:00:00Z` and the other five datasets have no source time

#### Scenario: Items without update times
- **WHEN** no item carries an `updated` value
- **THEN** every source time is absent and the snapshot is still authoritative at its observation time

#### Scenario: Malformed item update time
- **WHEN** one item's `updated` is the string `yesterday`
- **THEN** the refresh fails validation, no snapshot is published, and the last-good snapshot is kept

#### Scenario: Dataset-level update field is ignored
- **WHEN** a dataset carries a top-level `updated` of `2020-01-01T00:00:00Z`
- **THEN** that dataset's source time is not taken from it

#### Scenario: Evidence view with no items update time
- **WHEN** the evidence panel shows a snapshot whose items source time is absent
- **THEN** it reads that the items source update time is unknown

### Requirement: Selecting a known mode starts one catalog refresh
When the app selects a known mode, at launch or by switching, and its cached load ends, the app SHALL start one catalog refresh without user action and without delaying startup or the switch, unless a later selection superseded it or its catalog is already `current`. `unknown` mode SHALL start none. The app thus contacts the catalog source on every launch and mode switch.

#### Scenario: Launch with a cached snapshot
- **WHEN** the app launches into a known mode whose cached snapshot loads, and the source returns a valid catalog
- **THEN** the cached snapshot is published `stale` first, the status is `loading` while the fetch is in flight, startup completes before the fetch returns, exactly one fetch is made for that mode, and the status then becomes `current`

#### Scenario: Launch with no cache
- **WHEN** the app launches into a known mode with no cached snapshot, and the source returns a valid catalog
- **THEN** the status is `missing` once the cached load ends, then `loading` while the fetch is in flight, exactly one fetch is made, and the status then becomes `current`

#### Scenario: Unreadable cache still refreshes
- **WHEN** the cached catalog for the selected known mode fails to load
- **THEN** the status is first `failed` with "Stored catalog unavailable", then exactly one fetch is made, and its valid result makes the status `current`

#### Scenario: Unknown mode makes no request
- **WHEN** the selected mode is `unknown`, at launch or by switching
- **THEN** no catalog fetch is made and the status is `missing`

#### Scenario: Selection superseded during the cached load
- **WHEN** the user switches from mode A to mode B before A's cached load has ended
- **THEN** no fetch is made for A, and exactly one fetch is made for B

#### Scenario: Manual refresh already succeeded during the cached load
- **WHEN** the user presses Refresh while the selected mode's cached load is running, and that fetch publishes a `current` catalog before the cached load ends
- **THEN** no automatic fetch is made for that selection

#### Scenario: Manual refresh during the automatic one
- **WHEN** the user presses Refresh while the automatic refresh for the same mode is in flight
- **THEN** no second fetch is made, and both complete with the one fetch's result

### Requirement: A failed automatic catalog refresh is not retried
A failed automatic catalog refresh SHALL keep the last-good snapshot and SHALL NOT be retried automatically. The next fetch for that mode SHALL happen only on a manual refresh or a later selection of a mode.

#### Scenario: Startup fetch fails with a cached snapshot
- **WHEN** the app launches into a known mode with a cached snapshot and the automatic fetch fails
- **THEN** the cached snapshot is kept, the status is `stale` with the error "Catalog refresh failed; last-good data retained", and no further fetch is made until the user refreshes or selects a mode

#### Scenario: Startup fetch fails with no cache
- **WHEN** the app launches into a known mode with no cached snapshot and the automatic fetch fails
- **THEN** the status is `failed`, no snapshot is published, and no further fetch is made until the user refreshes or selects a mode

#### Scenario: Manual refresh after a failure
- **WHEN** the automatic fetch has failed and the user then presses Refresh
- **THEN** exactly one more fetch is made

### Requirement: An automatic refresh never publishes into another mode
A catalog refresh started for one mode SHALL NOT publish its result, success or failure, once a different mode is selected. A switch back to a mode whose refresh is still in flight SHALL join that refresh, not start a concurrent second fetch.

#### Scenario: Switch during the automatic refresh
- **WHEN** the automatic refresh for mode A is in flight and the user switches to mode B, and A's fetch then succeeds
- **THEN** B's snapshot and status are not replaced by A's result, and exactly one fetch is made for B

#### Scenario: Failure after a switch
- **WHEN** the automatic refresh for mode A is in flight, the user switches to mode B, and A's fetch then fails
- **THEN** B's status and error are not changed by A's failure

#### Scenario: Switch back while the refresh is still in flight
- **WHEN** the automatic refresh for mode A is still in flight after the user has switched to B and back to A and A's cached load has ended, and A's fetch then succeeds
- **THEN** no second fetch is made for A, and A's result is published with status `current`
