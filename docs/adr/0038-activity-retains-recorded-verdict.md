# 0038 - Activity retains the recorded verdict

- Status: accepted
- Date: 2026-11-08 (change `add-answer-strip`)
- Source: change `add-answer-strip`, decisions S3 and D2

## Context and problem

History identifies the items a player inspected, with one activity per item and mode. Current advice can change as item data, progress and Found in raid change. Recomputing a history indicator from current advice would misrepresent the verdict shown when the activity was recorded.

## Decision

- Record the optional displayed verdict as a stable named value with each explicit manual selection, accepted scan or correction. Capture it with the projected item and mode before asynchronous persistence, and write it in the existing activity transaction.
- Preserve one row per item and mode and its revision. A later observation replaces the row, including replacing a known verdict with unknown when no decision is available.
- Schema 7 adds a nullable text column. Missing, invalid and unsupported values remain readable as unknown; loading does not rewrite them. Legacy imports and rows have unknown verdicts rather than invented history.
- Opening a history row continues to calculate current advice. The recorded verdict is a historical fact, not a decision replay or authority for current selling advice.

## Rejected alternatives

- Recompute history indicators from current data: those indicators would imply an observation the app did not record.
- Persist full decision snapshots or an event log: the requested indicator needs neither a change to activity uniqueness nor historical prices and reasons.

## Consequences

- Migration and import retain user records and the existing transaction and merge rules from ADR-0003.
- Each activity adds one small optional value, with no new per-row calculation or timer.
- **Reversal cost:** medium. Stored values and old rows must remain readable across future versions.
