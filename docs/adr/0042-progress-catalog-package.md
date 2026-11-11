# 0042 - Progress catalog uses a portable workspace package and optional snapshot block

- Status: accepted
- Date: 2026-11-12 (change `add-task-catalog`)
- Source: reviewed `add-task-catalog` proposal S1–S5 and design D1, D2, D4, D5 and D7
- Extends: ADR-0003, ADR-0004 and ADR-0041; no accepted ADR is superseded.

## Context and problem

Local progress rules and the future checklist need task, objective and hideout facts that the item catalog currently discards. The model must be reusable without Flutter or Windows, while existing advice and offline cached item data remain unchanged.

## Decision

- **Portable workspace package.** `packages/blackgrid_progress` owns the immutable catalog model, stored JSON codec and tarkov.dev wire parsing. It has no runtime dependency beyond Dart. The root app uses a path dependency in a Pub workspace with one root lockfile. Both fast and complete test tasks run the package under plain Dart; source audits guard against Flutter, Windows and IO dependencies.
- **Explicit unknowns.** Missing facts are nullable or an explicit enum `unknown`, never invented false, zero or Any values. Absent requirement lists remain `null`, distinct from empty lists. Sealed objective facts represent only the fields belonging to each objective type. Read-only task, station and shared-objective indexes are derived, not stored.
- **One atomic mode snapshot.** The optional `progressCatalog` block carries `formatVersion: 1` inside the existing per-mode item snapshot. Snapshot schema and normalizer versions stay 1; no Drift migration or separate freshness clock is added. Item and progress catalogs are published and persisted together. An absent, damaged or unsupported stored block loads as unavailable without discarding items; the next successful refresh rebuilds it.
- **Strict identities, lenient new facts.** Missing identities, duplicate task/station IDs, objective IDs repeated within a task, invalid station level numbers and unresolved task/trader/station references reject the refresh and retain the last-good snapshot. Shared objective IDs across tasks remain flagged on each occurrence. Existing item-requirement validation stays unchanged: its already-validated fields retain their strictness, as narrowed in S3. Newly retained odd facts become unknown. Map, prestige, quest-item and objective-trader IDs are not newly resolved.
- **Existing execution and authority.** Parsing and decode stay in the existing background-isolate paths. No new request, controller, UI, advice, timer or Tracker consumer is introduced.

## Rejected alternatives

- Keeping the model in the app and extracting it later: forces a later interface migration.
- Independent package lockfiles: permit toolchain and dependency drift.
- Bumping the item snapshot version or adding separate tables: loses usable offline caches or requires coordinated dual swaps.
- Rejecting every new fact or dropping only a broken refreshed block: respectively blocks price updates on new wire values or replaces last-good progress data with none.

## Consequences

The package interface and versioned block become shared contracts for later rules and non-desktop clients. Stored JSON grows linearly with task and objective counts, about 1.1 MB per mode at design time; background decode and one cached snapshot per mode bound the impact. Identity failures can reject price updates, deliberately preserving coherent last-good data. No progress UI is advanced by this change.
