# Tasks

Each implementer and reviewer packet includes the "Dart and Flutter code" section of `AGENTS.md`. Skills used throughout: `dart-use-pattern-matching` (sealed facts, wire parsing), `dart-write-documentation` (public package API), `dart-add-unit-test` and `dart-run-static-analysis`.

Paths:

- `P` is `packages/blackgrid_progress/test/`.
- `N` is `test/data/catalog_normalizer_progress_test.dart`.
- `D` is `test/data/catalog_store_progress_test.dart`.
- `A` is `test/data/progress_package_audit_test.dart`.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Task catalog comes with each item catalog refresh | Refresh carries the mode's tasks | N | `refresh builds the mode's task catalog from the existing datasets` | red |
| Task catalog comes with each item catalog refresh | Failed refresh keeps the last-good task catalog | `test/application/catalog_controller_test.dart` | `failed refresh keeps the cached task catalog` | red |
| Task catalog comes with each item catalog refresh | Other modes are untouched | D | `committing one mode leaves other modes' task catalogs unchanged` | red |
| Task facts are retained | Kappa task kept with its flags | `P/parse_task_test.dart` | `keeps Kappa, Lightkeeper, faction and level` | red |
| Task facts are retained | Missing flag stays unknown | `P/parse_task_test.dart` | `absent or odd new facts are unknown` | red |
| Already-validated task fields keep today's strictness | Already-validated value rejects as today | N | `values the item parse rejects still reject the refresh` | red |
| Already-validated task fields keep today's strictness | Valid values pass unchanged | N | `valid level, faction and found-in-raid pass into the task catalog` | red |
| Absent lists stay unknown | Task without fail conditions | `P/parse_task_test.dart` | `absent failConditions means alternatives unknown` | red |
| Absent lists stay unknown | Empty list means none | `P/parse_task_test.dart` | `empty taskRequirements means no prerequisites` | red |
| Prerequisites keep their accepted statuses | Must-be-failed prerequisite | `P/parse_task_test.dart` | `keeps must-be-failed prerequisite statuses in order` | red |
| Prerequisites keep their accepted statuses | Unknown status value | `P/parse_task_test.dart` | `unknown prerequisite status is kept as unknown` | red |
| Alternatives come from task-status fail conditions | Completing another task fails this one | `P/parse_task_test.dart` | `taskStatus fail condition becomes an alternative` | red |
| Alternatives come from task-status fail conditions | Non-task fail condition | `P/parse_task_test.dart` | `other fail conditions are kept but are not alternatives` | red |
| Trader requirements keep their comparison | Loyalty level gate | `P/parse_task_test.dart` | `keeps trader level requirement with comparison` | red |
| Trader requirements keep their comparison | Unknown comparison | `P/parse_task_test.dart` | `unknown comparison is kept as unknown` | red |
| Objectives are retained with their checklist facts | Found-in-raid hand-over | `P/parse_objective_test.dart` | `giveItem keeps count, found in raid and items` | red |
| Objectives are retained with their checklist facts | New objective type | `P/parse_objective_test.dart` | `unrecognized type keeps raw type string` | red |
| Item-bearing objectives carry their items | Quest item objective | `P/parse_objective_test.dart` | `quest item objectives carry the quest item ID` | red |
| Item-bearing objectives carry their items | Missing item fact | `P/parse_objective_test.dart` | `useItem without useAny has unknown items` | red |
| Target objectives carry their targets | Trader standing objective | `P/parse_objective_test.dart` | `traderStanding carries trader, comparison and value` | red |
| Target objectives carry their targets | Missing target fact | `P/parse_objective_test.dart` | `missing target fact is unknown; other types carry no facts` | red |
| Shared objective IDs are flagged | Objective shared by task variants | `P/parse_objective_test.dart` | `objective ID under two tasks is marked shared on both` | red |
| Shared objective IDs are flagged | Repeat within a task | `P/parse_objective_test.dart` | `repeated objective ID within a task is an identity error` | red |
| Hideout stations and levels are retained | Station with prerequisites | `P/parse_hideout_test.dart` | `station level keeps station, trader and skill requirements` | red |
| Hideout stations and levels are retained | Invalid level number | `P/parse_hideout_test.dart` | `level number 0 or absent is an identity error` | red |
| Identities and references are validated strictly | Unresolved prerequisite | N | `unresolved prerequisite rejects the refresh as invalid` | red |
| Identities and references are validated strictly | Unknown map ID is accepted | `P/parse_task_test.dart` | `unknown map ID is kept, not resolved` | red |
| Display text falls back without failing | Translated objective | `P/parse_objective_test.dart` | `objective description comes from the dictionary` | red |
| Display text falls back without failing | Missing tasks dictionary | N | `missing tasks dictionary falls back and is reported` | red |
| Stored snapshots carry the task catalog optionally | Restart restores the task catalog | D | `stored task catalog survives reopen unchanged` | red |
| Stored snapshots carry the task catalog optionally | Snapshot cached before this change | D | `snapshot stored without a block loads with items and no task catalog` | red |
| Stored snapshots carry the task catalog optionally | Damaged stored task catalog | D | `damaged or other-version block loads as unavailable` | red |
| The task catalog model is usable without Flutter or Windows | Plain Dart test run | `mise run test` package step | n/a: mechanical check. `dart test` in `packages/blackgrid_progress` passes as part of `mise run test` (task 1.3) | green |
| The task catalog model is usable without Flutter or Windows | Flutter dependency introduced | A | `package declares and imports nothing Flutter, Windows or IO` | green |
| Existing advice and Tracker behaviour are unchanged | Same advice with and without the block | N | `item requirements, index and scav inputs are identical with and without the block` | red |
| Existing advice and Tracker behaviour are unchanged | Task catalog unavailable | A | `no UI or application code reads the task catalog yet` | green |

## 1. ADR, architecture and package scaffolding

- [x] 1.1 Write `docs/adr/0042-progress-catalog-package.md` (MADR short form, `Status: accepted`, date, source change `add-task-catalog`). It records D1, D2, D4 and D5 (with S3 as narrowed): the plain-Dart workspace package, the optional versioned `progressCatalog` block in the per-mode snapshot, and strict identities with lenient new facts. Index it in `openspec/architecture.md` In-force ADRs. Add the package component row, and add the block to the "Catalog snapshot" state row. Verify the link check passes (the ADR file exists and the index row resolves) by reading the rendered table.
- [x] 1.2 Create `packages/blackgrid_progress/`:
  - `pubspec.yaml` with `resolution: workspace`, the SDK constraint of the root, and dev dependencies `test` and `lints` at the versions in the root lock;
  - `analysis_options.yaml` with `include: package:lints/recommended.yaml` and strict casts, inference and raw types;
  - `lib/blackgrid_progress.dart`, exporting nothing yet.

  Add `workspace: [packages/blackgrid_progress]` and the path dependency to the root `pubspec.yaml`. Verify `flutter pub get` succeeds with one root `pubspec.lock` and no `packages/blackgrid_progress/pubspec.lock`.
- [x] 1.3 Add a step to the `test` and `test:all` tasks in `mise.toml` that runs `dart test` in `packages/blackgrid_progress`. Add one trivial package test so the step runs. Verify `mise run test` runs both suites and fails when that package test is made to fail, then restore the test. Test map row "Plain Dart test run" turns green.
- [x] 1.4 Write the audit tests in `A` (red first). One fails if the package `pubspec.yaml` depends on the Flutter SDK, or if any `packages/blackgrid_progress/lib/**.dart` imports `package:flutter`, `dart:ui`, `dart:ffi`, `dart:io`, `dart:isolate` or `package:win32`. The other fails if any file under `lib/ui/` or `lib/application/` references `progressCatalog` or `package:blackgrid_progress`. Prove each fails on a temporary bad import, then remove it. Verify `mise run analyze` is clean, and flip both A rows green.

## 2. Task and hideout model with its stored form (package)

- [x] 2.1 Write failing round-trip tests in `P/progress_catalog_json_test.dart`. Cover every model class and every `ObjectiveFacts` subtype, including `null` versus `[]` lists and unknown enums with raw strings. Also cover `ProgressCatalog.fromJson` throwing `FormatException` for `formatVersion` other than 1 and for wrong-typed stored fields.
- [x] 2.2 Implement the immutable model (D2) in `packages/blackgrid_progress/lib/src/`:
  - `ProgressCatalog`, with derived indexes (tasks by ID, stations by ID, shared objective IDs);
  - `CatalogTask`, `TaskPrerequisite`, `TaskAlternative`, `FailCondition`, `TraderRequirement`, `TaskObjective` and the `sealed ObjectiveFacts` (`ItemFacts`, `QuestItemFacts`, `TaskStatusFacts`, `TraderLevelFacts`, `TraderStandingFacts`, `SkillFacts`, `NoFacts`);
  - `HideoutStation`, `StationLevel`, `StationRequirement`, `SkillRequirement`;
  - the enums with `unknown`.

  Add `toJson` and `fromJson` (`formatVersion: 1`) and `///` docs on every public API. Verify 2.1 passes under `dart test` and `mise run analyze` is clean.

## 3. Wire parsing (package)

- [ ] 3.1 Write failing tests in `P/parse_task_test.dart` for every test map row that points there. Use small synthetic wire maps in the live shape (design Context), built in a shared `P/support/wire.dart`.
- [ ] 3.2 Write failing tests in `P/parse_objective_test.dart` and `P/parse_hideout_test.dart` for their test map rows. These include the type-to-facts table (`findItem`, `giveItem`, `plantItem`, `sellItem`, `buildWeapon`, `useItem`, `mark`, the three `*QuestItem` types with string and object `questItem`, `taskStatus`, `traderLevel`, `traderStanding`, `skill`, and a `visit` with stray `items`), levels sorted by number, and shared and repeated objective IDs.
- [ ] 3.3 Implement `parseProgressCatalog(tasksData, hideoutData, traderIds, taskDictionary, hideoutDictionary)` (D3, D5), using patterns over the wire maps:
  - Strict: IDs, duplicates, level numbers, and references to tasks, traders and stations within the mode, throwing `FormatException`.
  - Lenient: every newly retained fact.
  - Absent lists are `null`.
  - Display-name fallback: dictionary, then normalized name, then ID; descriptions fall back to unknown.

  Verify the 3.1 and 3.2 rows turn green under `dart test`, and flip them.

## 4. Catalog integration and storage (app)

- [ ] 4.1 Write failing tests in `N`, using the M1 fixture builder `test/fixtures/m1/catalog/fixture.dart` (extended with a few live-shaped task fields):
  - the refresh carries the task catalog with the dataset counts and makes no new request (assert the client's request list is unchanged);
  - already-validated values still reject the refresh, and valid ones pass into the block;
  - an unresolved prerequisite or alternative rejects the refresh as `CatalogFailure.invalid`;
  - a missing tasks dictionary falls back and lists `tasks` in `localizationErrors`;
  - the item `requirements`, `requirementIndex` and `scavCooldown` are identical to a run with the progress parse disabled.
- [ ] 4.2 Write failing tests:
  - in `D`, against a real in-memory `BlackgridDatabase`: reopen restores the block; a payload without the block (the existing fixture JSON) loads with `progressCatalog == null` and unchanged items; a block with `formatVersion: 2`, or with a wrong-typed field, loads as `null` with the items intact; committing regular leaves the stored PvE block unchanged;
  - in `test/application/catalog_controller_test.dart`: a failed refresh keeps the cached snapshot's task catalog.
- [ ] 4.3 Implement the integration:
  - `CatalogSnapshot.progressCatalog` (optional). `toJson` writes it only when it is present. `fromJson` decodes it in its own `try`, and an absent block, another version or a decode error give `null`. Keep `schemaVersion` and `normalizerVersion` at 1.
  - `normalizeCatalog` calls `parseProgressCatalog` after the unchanged item parse, inside the existing `Isolate.run`.

  Verify the 4.1 and 4.2 rows pass. Run `mise run test` and `mise run analyze` clean, run `dart format`, and flip the rows green.

## 5. Integration check

- [ ] 5.1 Run `mise run analyze`, `mise run test` (root and package suites) and `mise run release-notes -- --check openspec/changes/add-task-catalog/proposal.md`. All must exit 0. Confirm every test map row is green or `n/a`.
- [ ] 5.2 Re-run `openspec validate add-task-catalog --strict`. It must report the change valid.

## Workflow follow-up

- Pre-ship review, PR, archive and finish follow `specwright-commit` and `specwright-pr` in `pr` mode.
- No user-verified M9 exit criterion is checked by this change. The task data first becomes visible in `add-quest-checklist` and `add-manual-progress`, where the owner's checks belong.
