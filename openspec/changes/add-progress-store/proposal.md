# Proposal

## Why

M9 needs a durable local progress history before its catalog, rules, log ingestion and checklist can share state. This change advances the event identity, mode/wipe isolation, replay safety and newest-change-wins exit criterion; real-log/checklist validation remains at milestone close because those consumers ship in later M9 changes.

## What Changes

- Record an ADR for the local tracker event format and ownership, extending the single Drift database rather than adding another store.
- Add versioned progress events with unique event and device IDs, occurrence times, game mode, local progress-cycle (wipe) ID, source and tarkov.dev entity IDs.
- Persist locally generated progress cycles and device identity. A cycle is not an official game wipe identifier; creation is explicit, old cycles remain, and no upstream wipe discovery or automatic reset occurs.
- Derive current task, objective, hideout, player and trader values from events. Replays are idempotent; newest values win and newer log evidence supersedes older manual changes. Counters store absolute values, not increments.
- Provide durable history and undo through the store interface, with offline model, persistence and migration coverage.
- Preserve the read-only Tracker integration and all existing advice/timers unchanged until `retire-tracker-token`.

## Capabilities

### New Capabilities

- `local-progress`: durable progress cycles, versioned events, deterministic projection, history and undo.

### Modified Capabilities

None. `progress-authority` continues to describe Tracker authority; `local-data-durability` remains unchanged for existing records.

## Impact

- New pure Dart progress models and store contract alongside, not replacing, `lib/domain/progress.dart`'s Tracker snapshot.
- `lib/data/database.dart`, generated Drift code, schema snapshots and migration fixtures; current schema is 7.
- New ADR under `docs/adr/` and its architecture index entry during implementation.
- No new screen, network integration, native code or dependency on the game. No task catalog/rules, log ingestion/replay, manual-entry UI, checklist, consumer cutover, export/import or synchronization in this change.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Store-only delivery

- **Choice:** Implement the store, projection, history and undo interface without a new tracker/history screen. Keep Tracker and its consumers unchanged.
- **Rejected:** Pulling later M9 screens and the token retirement into this change; they need the catalog and rules first.
- **Reversal cost:** medium.
- **Important:** yes — binds later changes and the user-visible delivery boundary.
- **Chosen by:** user (scope form and agreed roadmap).

### S2: Cover M9 value families now

- **Choice:** Cover task state, objective counts/completion, hideout levels, player level, trader loyalty, faction and edition in the initial format. Keep catalog/edition availability rules out of persistence.
- **Rejected:** Entity-only storage followed by a separate player/trader format extension.
- **Reversal cost:** high.
- **Important:** yes — durable data format and future consumer contract.
- **Chosen by:** user.

### S3: Local progress-cycle identity

- **Choice:** Generate and persist opaque local cycle IDs on explicit creation, scoped by mode. Callers later select an active cycle; no automatic wipe detection, reset UI or guessed official wipe IDs. Future transfer preserves cycle IDs.
- **Rejected:** Requiring an unproven external wipe identifier; deriving identity from a date or from a log-folder name.
- **Reversal cost:** high.
- **Important:** yes — identity binds stored events and later transfer.
- **Chosen by:** user, after clarification that no wipe-ID source currently exists.

## Release Notes

Adds local progress storage for the upcoming tracker. Existing Tracker-backed advice is unchanged; tracker screens and log ingestion arrive in later M9 changes.

### Added

- Durable, mode-separated progress histories with local progress cycles, replay-safe event projection and an undo interface.
- A strict versioned event format and typed store interface covering task, objective, hideout, player and trader progress, with deterministic conflict ordering and explicit failures.
