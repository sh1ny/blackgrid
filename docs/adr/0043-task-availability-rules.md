# 0043 - Task availability is a pure projection with explicit unchecked gates

- Status: accepted
- Date: 2026-11-12 (change `add-task-rules`)
- Source: reviewed `add-task-rules` design D1–D6 and D9
- Extends: ADR-0042; no accepted ADR is superseded.

## Context and problem

The catalog keeps task gates and the local progress store keeps player facts, but later checklist and advice consumers need one portable answer about task availability without guessing missing progress or opaque game conditions.

## Decision

- **Pure package contract.** `blackgrid_progress` owns immutable `PlayerProgress` snapshots and `ProgressMode` (`regular`, `pve`, `seasonal`, mapped to tarkov.dev `regular`, `pve`, `pvp-season`). `evaluateTasks(catalog, mode, progress, {table = editionTable})` returns one `TaskAvailability` per catalog task in catalog order. It reads no clock, file, network or settings. The first app consumer supplies the store-to-snapshot reader; this change adds no app wiring.
- **Recorded state first.** Finished tasks are done. Failed tasks are done unless explicitly restartable, when they are evaluated as not started. Started tasks are available and marked started, without gate reasons. Missing or explicitly unset state is not started.
- **Checked failure wins; uncertainty never locks.** Every failing checked gate is collected. Any failure locks the task; otherwise it is available. Unset progress and undecidable gates are listed as unchecked on both locked and available not-started tasks. Consumers must surface unchecked reasons rather than imply certainty. Finished and started tasks have no unchecked reasons.
- **Typed, additive reasons.** Sealed `CheckedReason` and `UncheckedReason` hierarchies carry facts, not display text. Checked reasons cover finished/failed state, level, loyalty, prerequisites, alternatives, faction, mode and edition. Unchecked reasons distinguish absent or unknown progress/requirements, finished active-only prerequisites, reputation, global variables, dialogue, delay and prestige. New gates add reason subtypes; exhaustive consumer switches intentionally require updating. Display wording belongs to consumers.
- **Reviewed edition data.** A versioned const `EditionTable` belongs to the package. Every entry carries its source and allows or excludes known edition IDs. Every progress writer must use the table's edition IDs: `standard`, `left-behind`, `prepare-for-escape`, `edge-of-darkness`, `unheard`. Unset or unrecognised player editions are unchecked, never locks. Entries require owner review and checking each wipe. Version 1 includes only The Good Times - Part 1, allowed for Edge of Darkness and Unheard, owner-confirmed on 2026-11-12.

## Rejected alternatives

- Coupling the rules to storage-register types: makes other platforms inherit the ledger vocabulary.
- An unknown status or locking on opaque gates: hides tasks the player may take instead of exposing the uncertainty.
- English reason codes or a stateful evaluator: respectively couples UI wording to the package or adds unnecessary state.
- Guessing unset loyalty as 1: can incorrectly pass upper bounds. Only lower bounds satisfied by every possible loyalty pass without input.

## Consequences

Later progress writers and consumers share the snapshot, mode, edition vocabulary and sealed reason contracts. Evaluation remains synchronous and linear in tasks and gates, with immutable derived results. Catalog format version 1 remains compatible: absent other requirements and availability delays become unknown and produce unchecked reasons until refresh. No Flutter, Windows, IO, persistence or UI dependency is introduced.
