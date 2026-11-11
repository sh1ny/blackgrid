# Local Progress Spec Delta

## Purpose

Defines local progress history and its deterministic current values, isolated by game mode and locally created progress cycle, for later tracker writers and consumers.

## ADDED Requirements

### Requirement: Local cycles and device identity survive restart
The store SHALL persist one locally generated device ID and explicitly created, mode-scoped progress-cycle IDs. A cycle SHALL NOT imply an official game wipe. Creation SHALL preserve other cycles and their events; restarting SHALL preserve IDs. Unknown modes and missing or mismatched cycle identities SHALL be rejected. No automatic wipe detection or reset SHALL occur.

#### Scenario: Create and reopen cycles
- **WHEN** two cycles are explicitly created for a known mode and storage is reopened
- **THEN** both distinct cycle IDs and the original device ID remain available, with the first cycle's events unchanged

#### Scenario: Wrong scope
- **WHEN** an event names an absent cycle, an unknown mode or another mode's cycle
- **THEN** the operation fails without creating a cycle or changing progress

### Requirement: Events have a portable versioned identity
Every event SHALL carry a unique event ID, origin device ID, UTC occurrence time at millisecond precision, known game mode, cycle ID, format version, source, target and typed value. Version 1 SHALL use stable named fields and tags, not enum ordinals. Locally created identities SHALL be random; replayed inputs SHALL support stable caller-provided event IDs. Identity and occurrence time SHALL remain unchanged on replay.

#### Scenario: Event round trip
- **WHEN** a valid event is encoded, stored, reopened and decoded
- **THEN** all identity, scope, time, source, target and value fields equal the original event

#### Scenario: Unsupported or malformed envelope
- **WHEN** an event has an unsupported version, invalid source, missing identity or invalid target/value combination
- **THEN** the complete write is rejected and existing events and current values are unchanged

### Requirement: Accepted values remain encodable in compensation
Each identity string token, including an undo request or target ID, SHALL use at most 256 canonical JSON UTF-8 bytes; edition text SHALL use at most 1024. Limits SHALL include quotes and escaping. Version 1 SHALL reserve enough envelope space for every supported timestamp and an undo link, so any accepted predecessor value fits a compensation within the event cap. Violating a field budget SHALL reject the complete batch without truncation.

#### Scenario: Largest edition survives repeated undo
- **WHEN** the largest admissible edition token is stored, replaced, restored by undo and then that compensation is undone, using maximum permitted identity tokens and timestamp widths
- **THEN** both compensations fit the event cap and restore the correct predecessor values without truncation

#### Scenario: Escaped token exceeds budget
- **WHEN** an event identity or edition token exceeds its encoded budget, including because JSON escaping increases its size
- **THEN** the whole batch is rejected and previously stored events and current values are unchanged


### Requirement: Progress values are independent typed registers
The store SHALL support task state; objective absolute count and completion; hideout station level; player level, faction and edition; and trader loyalty. Each field SHALL resolve independently under its entity ID, mode and cycle. Catalog entities SHALL use tarkov.dev IDs. An explicit unset value SHALL mean unknown, not zero or an older value. Persistence SHALL NOT decide task availability or infer one field from another.

#### Scenario: Independent objective fields
- **WHEN** objective count 4 and completion true are written separately, then count 2 is written later
- **THEN** the projected count is 2 and completion remains true; no increment or automatic completion rule runs

#### Scenario: Unset and invalid counts
- **WHEN** the latest field value is unset, or a write attempts a negative objective count
- **THEN** the field is unknown without resurrecting an older value, or the invalid write is rejected without mutation, respectively

### Requirement: Replays are idempotent and batches are atomic
An exact replay of an event ID and content SHALL change nothing. Reusing an event ID with different content SHALL reject the entire batch. Accepted batches SHALL persist all new events and corresponding winning-field changes atomically. A failure SHALL expose neither a partial history nor a partial projection. Event IDs SHALL be unique across cycles and modes.

#### Scenario: Duplicate batch
- **WHEN** the same valid batch is submitted twice, including a repeated identical event inside one batch
- **THEN** each event exists once and projected values equal the first successful submission

#### Scenario: Conflicting identity or failed commit
- **WHEN** a batch contains an ID already used for different content, including in another cycle, or its commit fails
- **THEN** none of that batch's new events or current-value changes is committed

### Requirement: Newest field value wins deterministically
For each field the winner SHALL be the maximum of occurrence time, source rank (manual before log), device ID and event ID, compared in that order. IDs SHALL compare by ordinal string order. Arrival order SHALL NOT affect the result. Newer log evidence SHALL beat older manual edits; a newer manual correction SHALL beat older log evidence. Unset participates in the same ordering.

#### Scenario: Log and manual precedence
- **WHEN** an older manual edit, a newer log event and a still newer manual correction for one task arrive in any order
- **THEN** the correction wins; at equal times the log event wins over manual

#### Scenario: Equal-time deterministic ties
- **WHEN** two same-source events share a timestamp and arrive in opposite orders on two stores
- **THEN** both stores select the same winner by device ID then event ID

### Requirement: Current values are reproducible and isolated
The event history SHALL be authoritative. Rebuilding current values SHALL produce the same winners as incremental writes, without deleting or rewriting events. Every read and rebuild SHALL name a mode and cycle and SHALL expose only that scope. A rebuild SHALL replace current values atomically; an interrupted rebuild SHALL expose no partial replacement.

#### Scenario: Rebuild after reopening
- **WHEN** interleaved events from two modes and multiple cycles are persisted, reopened and rebuilt
- **THEN** each scope's values and winning event IDs equal its pre-rebuild projection, with no events from another scope

#### Scenario: Interrupted rebuild
- **WHEN** rebuilding a cycle fails before commit
- **THEN** no partial current-value replacement is visible and the history is unchanged

### Requirement: Current-value pages use one revision snapshot
Each current-value page SHALL validate its cursor and cycle revision and return rows from one database snapshot. Validation or rebuild SHALL establish that same revision. A continuation with a different committed revision SHALL report stale-cursor. No transaction SHALL remain open between page calls. A commit racing a read SHALL NOT produce mixed-revision success.

#### Scenario: Stable page continuation
- **WHEN** successive current-value pages are read without a committed cycle change
- **THEN** every page reports the same revision and each register appears once

#### Scenario: Commit races the final page
- **WHEN** another database instance commits after a continuation checks its revision but before it reads its rows, including when that continuation is the final page
- **THEN** the whole page comes from the checked snapshot or reports an explicit stale-cursor or storage failure, never successful rows from a newer revision under the old cursor


### Requirement: Undo appends a guarded compensating event
Undo SHALL restore the target winner's preceding value, or unset when none exists, by appending a new manual event linked to that target. It SHALL NOT delete history. Undo SHALL check the target is still the current winner in the same transaction as its append, and choose a timestamp later than the target. A repeated undo request ID SHALL return its original result without another event.

#### Scenario: Undo current value
- **WHEN** the current event sets count 5 over count 2 and undo succeeds
- **THEN** count 2 is current, both original events remain, and one new manual event records the compensation and target link

#### Scenario: Undo first value and retry
- **WHEN** the first value of a field is undone and the same undo request is retried
- **THEN** the field is unknown, and the same single compensation event is returned

#### Scenario: Stale undo
- **WHEN** another event has replaced the requested target before undo commits
- **THEN** undo reports a conflict and creates no event or field change

### Requirement: History failures do not become partial progress
Unsupported or damaged history encountered while opening or reading a cycle SHALL make that cycle unavailable with an explicit failure. The store SHALL NOT silently skip events, report an empty successful projection or reset data. Reads and unsuccessful recovery SHALL preserve stored events. Write, busy, validation and undo-conflict failures SHALL be distinguishable to callers; no automatic retry SHALL run.

#### Scenario: Readable cycle
- **WHEN** a cycle's stored events are supported and valid
- **THEN** opening it returns its current values and readable history, not an unavailable result

#### Scenario: Damaged or future event
- **WHEN** opening or reading a cycle encounters malformed event data or an unsupported event version
- **THEN** that cycle reports unavailable, publishes no partial successful progress and retains the original event bytes

### Requirement: Operations are bounded without discarding history
Append batches and read pages SHALL contain at most 256 records; encoded events SHALL be at most 4 KiB. Oversized inputs SHALL fail without mutation. At most one local-progress operation SHALL be admitted per store instance; concurrent calls SHALL report busy rather than accumulate in an application queue. History SHALL remain durable without automatic trimming, and history/projection traversal SHALL be paged.

#### Scenario: Paged history
- **WHEN** a cycle contains more than one page of events
- **THEN** successive stable keyset cursors return its events once each, with each page within the limit

#### Scenario: Busy or oversized operation
- **WHEN** a call arrives during another local-progress operation, or exceeds a batch, page or event limit
- **THEN** it reports busy or invalid input, respectively, without accepting partial work

### Requirement: Database upgrade preserves existing application behavior
Upgrading storage SHALL preserve settings, pins, activity, caches, statistics and their existing semantics while adding empty local-progress storage. A newer unsupported database SHALL still be refused without mutation. This change SHALL NOT switch advice, timers or task authority away from Tracker, change its credentials or requests, or initiate progress ingestion or synchronization.

#### Scenario: Upgrade and reopen
- **WHEN** an existing database with user records is upgraded and reopened
- **THEN** existing records retain their values, local progress starts empty, and Tracker remains the existing progress source

#### Scenario: Newer database
- **WHEN** the database has a schema newer than the supported version
- **THEN** opening fails with the existing newer-database error and leaves its bytes unchanged
