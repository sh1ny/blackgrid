# Proposal

## Why

Milestone M9 (local progress tracker) needs to know, for each task in a mode, whether the player has done it, can take it now, or is locked out, and why. The log progress, manual progress, quest checklist and Tracker token retirement changes all depend on that answer. `add-task-catalog` (#111) keeps the tarkov.dev task facts and `add-progress-store` (#110) keeps the player's progress, but nothing yet joins the two.

This change serves M9 exit criterion 2: "The availability rules are a plain Dart package with no Flutter or Windows dependency. For each task they say done, available or locked, and why: level, trader loyalty, a missing or must-be-failed prerequisite, an alternative task, faction or edition. Proved by tests on frozen tarkov.dev fixtures." It advances no user-verified criterion. Nothing on screen changes, so all its checks are offline tests.

Research on the live data (regular mode, 503 tasks, fetched 2026-11-12) found gates the roadmap did not list:

- 168 tasks have `globalVariable` requirements, opaque game counters that nothing in the data sets.
- 12 tasks need a trader dialogue.
- 10 tasks have an availability delay after their prerequisites.
- 3 tasks need a prestige.
- 8 trader requirements are on reputation, which local progress does not store.

The catalog drops the first three today. A rule set that ignored them would call about a third of all tasks available when the game says otherwise, so this change also keeps them.

## What Changes

- Add availability rules to the plain Dart package `packages/blackgrid_progress`. They still have no Flutter or Windows dependency.
- Given a mode's task catalog and a plain snapshot of the player's progress for that mode, the rules return one result per task:
  - `done` when the task is finished (or failed and not restartable);
  - `locked` when any gate the rules can check fails;
  - otherwise `available`.
- Each result lists its reasons, so the player sees why: player level, trader loyalty level, a prerequisite not yet in an accepted status (including must-be-failed and must-be-active), an alternative task that has already closed this one, faction, game mode or edition.
- Gates the rules cannot decide never lock a task on their own. They are listed as unchecked reasons on the result, so a later screen can show the doubt. These are game global variables, trader dialogues, availability delays, prestige, trader reputation, and any progress value the player has not entered yet (an unset level, faction or edition).
- Edition rules are written by us as a small, versioned table in the package that maps task IDs to the editions allowed or excluded. The owner seeds it during design, and each entry carries its source. An unset or unrecognised player edition is an unchecked gate, never a lock.
- The task catalog now also keeps each task's `otherRequirements` (global-variable and dialogue gates, with any other type kept as unknown) and `availableDelaySecondsMin/Max`. Both are lenient. A malformed or unknown value stays unknown and never rejects a refresh. A catalog stored before this change loads with these gates unknown, which the rules report as unchecked.
- Frozen fixtures: an excerpt of real tarkov.dev tasks from regular and PvE mode, with fields unchanged apart from removed zone geometry and translations. They are chosen so that every rule has at least one real case. The source URLs and fetch date are recorded with them.
- No UI, advice, timer, Tracker or progress-store change. Nothing in the app calls the rules yet.

## Capabilities

### New Capabilities

- `task-availability`: the plain-Dart rules that turn a mode's task catalog and a player's progress into done / available / locked per task, with checked and unchecked reasons, plus the edition table they use.

### Modified Capabilities

- `task-catalog`: tasks also keep their other requirements (global-variable, dialogue, unknown) and availability delays, both lenient and unknown when absent.

## Impact

- `packages/blackgrid_progress/lib/`: new rules and edition table sources, exported from `blackgrid_progress.dart`. Catalog model, JSON and wire parse gain the two retained fields. The stored `formatVersion` stays 1, and a missing field reads as unknown.
- `packages/blackgrid_progress/test/`: rule tests over the frozen excerpt and small synthetic cases, plus catalog parse and JSON tests for the new fields.
- `lib/data/catalog_normalizer.dart` and the app are unaffected beyond carrying the larger block. There is no new request, no Drift schema change and no snapshot schema change.
- `openspec/architecture.md`: the package component row gains the rules. The design decides whether the rules contract needs an ADR.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Undecidable gates do not lock

- **Choice:** When no checkable gate fails, the task is `available`, and every gate the rules cannot decide is listed as an unchecked reason. A failing checkable gate locks the task whatever the unchecked ones say.
- **Rejected:**
  - A fourth `unknown` status, which about a third of all tasks would get.
  - Treating undecidable gates as locked, which hides tasks the player can take.
- **Reversal cost:** medium. The result contract feeds the checklist and advice changes.
- **Important:** yes. It binds future changes and is what players will see.
- **Chosen by:** user.

### S2: Keep the missing gates in the task catalog in this change

- **Choice:** Retain `otherRequirements` and `availableDelaySecondsMin/Max` leniently in the task catalog here, modifying `task-catalog`.
- **Rejected:** Leaving them out, so the rules would miss the gates on about 36% of regular tasks.
- **Reversal cost:** low. The fields are lenient and optional.
- **Important:** yes. It extends a stored data format.
- **Chosen by:** user.

### S3: Edition rules from a reviewed table seeded by the owner

- **Choice:** A versioned table in the package, task ID to editions allowed or excluded, seeded from the owner's list during design, with a source note per entry. An unset or unknown player edition is unchecked, never a lock.
- **Rejected:**
  - An empty table that ships the mechanism only.
  - Dropping edition from M9, which would amend the exit criterion.
- **Reversal cost:** low. It is data in one file.
- **Important:** yes. It is chosen on weak evidence, because tarkov.dev has no edition data.
- **Chosen by:** user.

### S4: Frozen fixtures are a real per-rule excerpt

- **Choice:** About 30-50 real regular and PvE tasks, unmodified apart from removed zone geometry and translations, picked so that every rule has a real case, with the source and date recorded.
- **Rejected:**
  - Adding a full frozen snapshot per mode for a qualification-tier test.
  - Using full snapshots only, both against the keep-fixtures-small rule.
- **Reversal cost:** low.
- **Important:** yes. It defines how exit criterion 2 is proved.
- **Chosen by:** user.

### S5: Task availability only, no hideout build availability

- **Choice:** Rules cover tasks only. Whether a hideout station level can be built is left to the hideout milestone.
- **Rejected:** Adding station-level availability now, which has no consumer in M9.
- **Reversal cost:** low. It can be added beside the task rules later.
- **Important:** no.
- **Chosen by:** agent.

### S6: No app wiring

- **Choice:** The rules are a library with no caller in the app yet. Reading the progress store into the rules' input belongs to the first change that shows or uses the answer (`add-manual-progress` or `add-quest-checklist`).
- **Rejected:** Adding a store-to-rules reader now with no consumer.
- **Reversal cost:** low.
- **Important:** no.
- **Chosen by:** agent.

## Release Notes

Groundwork for the local progress tracker: Blackgrid can now work out, for each task, whether you have done it, can take it now or are locked out, and why. Nothing on screen changes yet.

### Added

- Task availability rules check player level, trader loyalty, prerequisites (including tasks that must be failed or active), alternative tasks, faction, game mode and edition. Gates that local progress cannot check yet are flagged rather than guessed.

### Changed

- Item data downloads now also keep each task's extra game conditions and its availability delay, so the availability rules can see every gate.
