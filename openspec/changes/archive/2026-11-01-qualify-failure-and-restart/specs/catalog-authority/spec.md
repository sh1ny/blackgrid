# Spec Delta

## MODIFIED Requirements

### Requirement: A failed automatic catalog refresh is not retried
A failed automatic catalog refresh SHALL keep the last-good snapshot and SHALL NOT be retried automatically. The next fetch for that mode SHALL happen only on a manual refresh or a later selection of a mode.

#### Scenario: Startup fetch fails with a cached snapshot
- **WHEN** the app launches into a known mode with a cached snapshot and the automatic fetch fails because the source cannot be reached
- **THEN** the cached snapshot is kept, the status is `stale` with the error "Item data could not be downloaded: no connection to tarkov.dev. The last item data is still in use.", and no further fetch is made until the user refreshes or selects a mode

#### Scenario: Startup fetch fails with no cache
- **WHEN** the app launches into a known mode with no cached snapshot and the automatic fetch fails because the source cannot be reached
- **THEN** the status is `failed` with the error "Item data could not be downloaded: no connection to tarkov.dev. No item data is available yet.", no snapshot is published, and no further fetch is made until the user refreshes or selects a mode

#### Scenario: Manual refresh after a failure
- **WHEN** the automatic fetch has failed and the user then presses Refresh
- **THEN** exactly one more fetch is made

## ADDED Requirements

### Requirement: A catalog failure message names its cause
A failed catalog refresh SHALL set an error whose first sentence names the cause: no connection or a timeout, an HTTP error status, invalid or incomplete data, or a local save failure. Its second sentence SHALL be "The last item data is still in use." when a snapshot is kept and "No item data is available yet." when none is.

#### Scenario: No connection with a kept snapshot
- **WHEN** a refresh for a mode with a snapshot fails because the source cannot be reached
- **THEN** the error is "Item data could not be downloaded: no connection to tarkov.dev. The last item data is still in use."

#### Scenario: Server error with a kept snapshot
- **WHEN** a refresh for a mode with a snapshot fails because one dataset answers HTTP 503
- **THEN** the error is "Item data could not be downloaded: tarkov.dev answered with an error. The last item data is still in use."

#### Scenario: Invalid data with no snapshot
- **WHEN** a refresh for a mode with no snapshot fails validation
- **THEN** the status is `failed` and the error is "Item data from tarkov.dev was incomplete or invalid. No item data is available yet."

#### Scenario: Local save failure
- **WHEN** a refresh downloads a valid catalog but storing it fails
- **THEN** the previous snapshot stays in use and stored, and the error is "Item data could not be saved on this computer. The last item data is still in use."

#### Scenario: Timeout
- **WHEN** a dataset download stalls past the request timeout
- **THEN** the error starts "Item data could not be downloaded: no connection to tarkov.dev."

### Requirement: The Data sources panel shows the catalog error
When the catalog has an error, the Data sources panel SHALL show that error text in its open view next to the item data status, and SHALL show no catalog error once a refresh succeeds.

#### Scenario: Failure shown in the panel
- **WHEN** a catalog refresh fails while a snapshot is kept
- **THEN** the Data sources panel shows "out of date" for item data and the error text

#### Scenario: Error cleared by a successful refresh
- **WHEN** a later refresh succeeds
- **THEN** the Data sources panel shows "up to date" and no catalog error
