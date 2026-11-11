# Proposal

## Why

Milestone M9 (local progress tracker) needs a mode-scoped catalog of tarkov.dev tasks and hideout stations. The availability rules (`add-task-rules`), log task progress, manual progress, the quest checklist and the Tracker token retirement all read it. Today the catalog downloads the `tasks` and `hideout` datasets but keeps only the item requirements they contain. Task prerequisites, alternatives, trader and level gates, faction, Kappa and Lightkeeper flags, objectives and station levels are thrown away.

This change keeps that data. It serves M9 exit criterion 2 (the availability rules as a plain Dart package, tested on frozen tarkov.dev fixtures). It supplies the package boundary and the model those rules read. It also provides the tarkov.dev task, objective and station IDs that criteria 1, 3 and 4 key progress by (ADR-0041). No user-verified criterion is advanced here: the change adds no screen and changes no advice, so its checks are all offline tests.

## What Changes

- Add a plain Dart path package, `packages/blackgrid_progress`, with no Flutter or Windows dependency. It holds the task and hideout catalog model, its stored JSON form and the parsing of the tarkov.dev `tasks` and `hideout` wire data. `add-task-rules` later adds the availability rules to the same package.
- For each task, keep:
  - the ID, name and normalized name;
  - the trader, minimum player level, faction, Kappa and Lightkeeper flags, the restartable flag, the map, and the prestige and game-mode restrictions;
  - prerequisites with their accepted statuses (including must-be-failed);
  - trader level and reputation requirements;
  - alternatives, taken from `taskStatus` fail conditions;
  - every objective, with its ID, type, optional flag, count, description text, maps and the type-specific facts the rules and checklist need: items and found-in-raid, task status, trader level, skill.
- For each hideout station, keep the ID, name and normalized name. For each station level, keep the construction time and its station, trader and skill requirements.
- Store this data as an optional `progressCatalog` block in the existing per-mode catalog snapshot, swapped atomically with the items. The snapshot schema version does not change. A snapshot cached before this change loads without the block until the next refresh.
- Validation:
  - Strict on identity. Missing or duplicate IDs and unresolved task, trader or station references reject the refresh, and the last-good catalog is kept as today.
  - Lenient on new facts. Fields the existing item-requirement parse already checks keep today's strictness. Everything newly retained (flags, unknown objective types, odd fact values, absent lists) becomes an explicit unknown and never blocks item or price updates.
- No UI, advice, timer or Tracker change. Nothing reads the new block yet apart from tests.

## Capabilities

### New Capabilities

- `task-catalog`: the mode-scoped catalog of tarkov.dev tasks, objectives and hideout stations kept for local progress. Covers what is retained, how identities and references are validated, how unknown facts are represented, how it is stored with the item catalog, and the plain-Dart package boundary that the rules and later apps build on.

### Modified Capabilities

- None. Item catalog authority, refresh, error text and requirement rows stay as specified. The new block rides on the existing snapshot swap and last-good behaviour.

## Impact

- New `packages/blackgrid_progress/` (pubspec, `lib/`, `test/`). The root `pubspec.yaml` gains a path dependency. `mise run analyze` and `mise run test` must cover the package.
- `lib/data/catalog_normalizer.dart` builds the block from the datasets it already downloads, so there are no new requests. `lib/domain/catalog.dart` (`CatalogSnapshot` JSON) carries the optional block.
- Snapshot JSON grows by the retained task text (about 500 tasks per mode). Decoding stays in the existing `Isolate.run` normalization and Drift background reads (ADR-0004). There is no Drift schema change (ADR-0003).
- `openspec/architecture.md` gains the package component and the catalog-snapshot state row update; the design decides whether this needs an ADR.
- Tests: package model, parse and JSON round-trip tests; normalizer tests on small synthetic fixtures modelled on the live wire shape; a cached-snapshot load test without the block.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Task model in a new plain-Dart package now

- **Choice:** Create `packages/blackgrid_progress` (a path package with no Flutter or Windows dependency) for the task and hideout model, its JSON form and the wire parsing. `add-task-rules` adds the rules there.
- **Rejected:** Keeping the model in `lib/domain/` and extracting it in `add-task-rules`. That change would then also have to move code and rewrite imports.
- **Reversal cost:** medium.
- **Important:** yes. It sets a boundary that future changes and the planned web and mobile apps build on.
- **Chosen by:** user.

### S2: Optional block in the per-mode catalog snapshot

- **Choice:** Add an optional `progressCatalog` block to the snapshot JSON, following the precedent of the `scavCooldown` block (ADR-0031). There is no schema bump and no Drift migration, and the block swaps atomically with items. Old cached snapshots load without it.
- **Rejected:**
  - Bumping the snapshot schema to 2. Old caches would be refused, leaving no item data on an offline launch.
  - Separate Drift tables. They would need a migration and a second swap kept in step with items.
- **Reversal cost:** medium.
- **Important:** yes. It is a durable data format.
- **Chosen by:** user.

### S3: Strict identities, lenient facts

- **Choice:** Missing or duplicate IDs and unresolved task, trader or station references reject the refresh, keeping the last-good catalog. Fields the existing item-requirement parse already validates keep today's strictness. Newly retained facts, unknown objective types and absent lists become explicit unknowns. This was narrowed by the user on 2026-11-12 after design review C1 showed the unchanged item parse already rejects those fields.
- **Rejected:**
  - Dropping the block on any problem, which could replace good task data with none.
  - Rejecting on any unexpected value, where a tarkov.dev schema tweak would stop price updates.
- **Reversal cost:** low.
- **Important:** yes. It changes refresh behaviour users see when tarkov.dev data changes.
- **Chosen by:** user.

### S4: Retained data scope

- **Choice:** The roadmap list plus objective descriptions, maps, the restartable flag, prestige and game-mode restrictions, and the station level requirements (station, trader, skill). These are what the rules and the checklist need.
- **Rejected:** Also keeping finish rewards (XP, standing, items) now, which have no consumer before M15. Hideout bonuses wait for M12.
- **Reversal cost:** low. A later change adds fields, and the next refresh fills them.
- **Important:** yes. It is chosen on partial evidence of what later changes need.
- **Chosen by:** user.

### S5: Synthetic fixtures in this change

- **Choice:** Test with small hand-written fixtures in the live wire shape (checked on 2026-11-12 against `json.tarkov.dev/regular/tasks`, `/pve/tasks` and `/regular/hideout`). The frozen tarkov.dev fixtures for exit criterion 2 belong to `add-task-rules`.
- **Rejected:** Committing a trimmed live excerpt now, ahead of the rules that need it.
- **Reversal cost:** low.
- **Important:** no.
- **Chosen by:** agent.

## Release Notes

Groundwork for the local progress tracker: item data downloads now keep tarkov.dev's tasks, objectives and hideout stations for each game mode. Nothing on screen changes yet.

### Added

- Item data now keeps each mode's tasks (prerequisites, alternatives, trader and level requirements, faction, Kappa and Lightkeeper flags, objectives) and hideout station levels, ready for the upcoming tracker. The data comes from the same tarkov.dev downloads, with no new requests.
- Unexpected values in newly retained task facts stay unknown rather than blocking item updates. Malformed condition lists stay unknown rather than meaning no alternatives. Existing validation and strict identity checks still reject invalid refreshes and keep the last good catalog.
