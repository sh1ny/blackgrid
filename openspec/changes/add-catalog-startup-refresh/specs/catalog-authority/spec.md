# Spec Delta

## ADDED Requirements

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
