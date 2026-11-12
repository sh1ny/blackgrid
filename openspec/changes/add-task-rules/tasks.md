# Tasks

## Test map

Package tests live under `packages/blackgrid_progress/test/` (written `pkg/test/` below). Rules tests use `evaluateTasks` over small synthetic catalogs unless the row names the excerpt.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| task-catalog → Other task requirements are retained leniently | Global-variable requirement kept | pkg/test/parse_task_test.dart | `otherRequirements keeps a globalVariable gate` | green |
| task-catalog → Other task requirements are retained leniently | Malformed other requirements | pkg/test/parse_task_test.dart | `malformed otherRequirements become unknown` | green |
| task-catalog → Other task requirements are retained leniently | Absent list | pkg/test/parse_task_test.dart | `absent otherRequirements is unknown, empty is none` | green |
| task-catalog → Availability delays are retained leniently | Ten-hour delay | pkg/test/parse_task_test.dart | `availability delay is kept in seconds` | green |
| task-catalog → Availability delays are retained leniently | Wrong-typed delay | pkg/test/parse_task_test.dart | `wrong-typed availability delay is unknown` | green |
| task-catalog → Stored catalogs without the new facts still load | Older stored catalog | pkg/test/progress_catalog_json_test.dart | `catalog stored without other requirements and delays loads them as unknown` | green |
| task-catalog → Stored catalogs without the new facts still load | Round trip | pkg/test/progress_catalog_json_test.dart | `dialogue requirement and delay round-trip` | green |
| task-availability → Every catalog task gets one result | Results follow the catalog | pkg/test/task_rules_test.dart | `one result per task in catalog order` | green |
| task-availability → Every catalog task gets one result | Progress for an unknown task | pkg/test/task_rules_test.dart | `progress for a task outside the catalog is ignored` | green |
| task-availability → Results are deterministic and side-effect free | Repeated evaluation | pkg/test/task_rules_fixture_test.dart | `repeated evaluation over the excerpt is equal` | red |
| task-availability → Results are deterministic and side-effect free | Progress changes between runs | pkg/test/task_rules_test.dart | `a new snapshot does not change earlier results` | green |
| task-availability → Recorded task state decides done and started | Finished task | pkg/test/task_rules_test.dart | `finished task is done without gate reasons` | green |
| task-availability → Recorded task state decides done and started | Failed restartable task | pkg/test/task_rules_test.dart | `failed restartable task is evaluated as not started` | green |
| task-availability → Recorded task state decides done and started | Failed with unknown restartability | pkg/test/task_rules_test.dart | `failed task with unknown restartability is done` | green |
| task-availability → A failing checked gate locks the task | Two gates fail | pkg/test/task_rules_test.dart | `locked result lists every failing gate` | green |
| task-availability → A failing checked gate locks the task | Failing gate beside an unchecked one | pkg/test/task_rules_test.dart | `failing gate locks and unchecked gates are still listed` | green |
| task-availability → Player level gate | Level too low | pkg/test/task_rules_gates_test.dart | `level below minimum locks` | green |
| task-availability → Player level gate | Level not entered | pkg/test/task_rules_gates_test.dart | `unset level is unchecked above minimum 1` | green |
| task-availability → Trader loyalty gate | Loyalty met | pkg/test/task_rules_gates_test.dart | `loyalty at the required level passes` | green |
| task-availability → Trader loyalty gate | Reputation requirement | pkg/test/task_rules_gates_test.dart | `reputation requirement is always unchecked` | green |
| task-availability → Trader loyalty gate | Loyalty not entered | pkg/test/task_rules_gates_test.dart | `unset loyalty is unchecked for at least 2` | green |
| task-availability → Trader loyalty gate | Upper bound with loyalty not entered | pkg/test/task_rules_gates_test.dart | `unset loyalty is unchecked for at most 2` | green |
| task-availability → Prerequisite gate | Prerequisite not done | pkg/test/task_rules_gates_test.dart | `missing completion prerequisite locks` | green |
| task-availability → Prerequisite gate | Must-be-failed prerequisite | pkg/test/task_rules_gates_test.dart | `must-be-failed prerequisite finished locks` | green |
| task-availability → Prerequisite gate | Unknown prerequisite list | pkg/test/task_rules_gates_test.dart | `unknown prerequisites are unchecked` | green |
| task-availability → Finished active-only prerequisite is unchecked | Prerequisite finished after unlocking | pkg/test/task_rules_gates_test.dart | `finished active-only prerequisite is unchecked` | green |
| task-availability → Finished active-only prerequisite is unchecked | Prerequisite never taken | pkg/test/task_rules_gates_test.dart | `never-taken active-only prerequisite locks` | green |
| task-availability → Alternative tasks close a task | Alternative completed | pkg/test/task_rules_gates_test.dart | `completed alternative locks` | green |
| task-availability → Alternative tasks close a task | Alternative not taken | pkg/test/task_rules_gates_test.dart | `started alternative accepting complete passes` | green |
| task-availability → Faction gate | Wrong faction | pkg/test/task_rules_gates_test.dart | `other faction locks` | green |
| task-availability → Faction gate | Faction not entered | pkg/test/task_rules_gates_test.dart | `unset faction is unchecked for a faction task` | green |
| task-availability → Game mode gate | Regular-only task in PvE | pkg/test/task_rules_gates_test.dart | `regular-only task locks in pve` | green |
| task-availability → Game mode gate | No restriction | pkg/test/task_rules_gates_test.dart | `unrestricted task passes in every ProgressMode` | green |
| task-availability → Edition gate from a reviewed table | Edition excluded | pkg/test/task_rules_gates_test.dart | `edition outside the allowed set locks` | green |
| task-availability → Edition gate from a reviewed table | Unrecognised edition | pkg/test/task_rules_gates_test.dart | `unrecognised edition is unchecked` | green |
| task-availability → Undecidable gates are listed, never locking | Global-variable gate | pkg/test/task_rules_gates_test.dart | `global-variable gate is unchecked and available` | green |
| task-availability → Undecidable gates are listed, never locking | Catalog stored before other requirements were kept | pkg/test/task_rules_gates_test.dart | `unknown other requirements and delay are unchecked` | green |
| task-availability → Rules are proved on frozen tarkov.dev data | Excerpt covers each gate | pkg/test/task_rules_fixture_test.dart | `every gate kind is hit by an excerpt task` | red |
| task-availability → Rules are proved on frozen tarkov.dev data | Excerpt edited out of shape | pkg/test/task_rules_fixture_test.dart | `excerpt manifest records source URLs and fetch date` | red |
| task-availability → Rules run without Flutter or Windows | Plain Dart run | pkg/test (all) | `mise run test` runs `cd packages/blackgrid_progress && dart test` (`mise.toml:12`) | green |
| task-availability → Rules run without Flutter or Windows | Flutter dependency introduced | test/data/progress_package_audit_test.dart | existing package audit (pubspec deps and `lib/` imports) | green |

## 1. Contract ADR and architecture

- [x] 1.1 Write `docs/adr/0043-task-availability-rules.md` (MADR-short, `Status: accepted`, the date, extends ADR-0042). It records the contract from design D2: a pure `evaluateTasks` over package-owned `PlayerProgress` and `ProgressMode`; state precedence; failing checked gates lock and unchecked gates never lock; the sealed, additive reason vocabulary; the edition table as reviewed const data whose IDs every progress writer must use for the player's edition. Verify the file exists and `openspec validate add-task-rules --strict` passes.
- [x] 1.2 Update `openspec/architecture.md`: the `blackgrid_progress` component row gains the availability rules and edition table, the ADR-0043 index row is added, and the catalog state row notes the two new lenient task fields. Verify with `mise run test` (it includes the planning-document checks).

## 2. Catalog keeps other requirements and delays

- [x] 2.1 Write the failing parse tests for the test-map rows "Global-variable requirement kept", "Malformed other requirements", "Absent list", "Ten-hour delay" and "Wrong-typed delay" in `pkg/test/parse_task_test.dart`, using the existing `support/wire.dart` builders. Verify they fail for the missing fields (`cd packages/blackgrid_progress && dart test test/parse_task_test.dart`).
- [x] 2.2 Write the failing JSON tests for "Older stored catalog" and "Round trip" in `pkg/test/progress_catalog_json_test.dart`. Verify they fail.
- [x] 2.3 Implement design D7 in the package:
  - the sealed `OtherRequirement` (`GlobalVariableRequirement`, `DialogueRequirement`, `UnknownOtherRequirement`) with a `kind` JSON discriminator;
  - `CatalogTask.otherRequirements` and `availableDelaySecondsMin/Max` in the constructor, `fromJson`, `toJson` and `_withObjectives`;
  - the lenient wire parse in `parse_progress_catalog.dart` (the whole list becomes null on a malformed row; a delay that is not a nonnegative int becomes null);
  - `formatVersion` stays 1;
  - `///` docs on all new public API.

  Verify that the 2.1 and 2.2 tests pass, that the existing package tests and `test/data/catalog_normalizer_progress_test.dart` still pass, and that `mise run analyze` is clean. Flip the seven task-catalog rows green.

## 3. Availability rules and edition table

- [x] 3.1 Add the public types from design D1/D2, with `///` docs, and export them from `blackgrid_progress.dart`:
  - `ProgressMode {regular, pve, seasonal}` with tarkov.dev names `regular`, `pve` and `pvp-season`;
  - `TaskProgressState`, `PlayerFaction` and an immutable `PlayerProgress`;
  - `AvailabilityStatus` and `TaskAvailability`;
  - the sealed `CheckedReason` and `UncheckedReason` sets, including `AvailabilityDelayUnknown`;
  - `EditionTable` and `EditionRule`.

  Verify that `mise run analyze` is clean and that the package still compiles without a `GameMode` name clash in `lib/data/catalog_normalizer.dart`.
- [x] 3.2 Write the failing tests in `pkg/test/task_rules_test.dart` (results, determinism with a new snapshot, recorded state, lock precedence) and `pkg/test/task_rules_gates_test.dart` (every gate row in the test map). Use small synthetic catalogs built with `ProgressCatalog(...)` and a synthetic `EditionTable`. Verify they fail.
- [x] 3.3 Implement `evaluateTasks` per design D5 and D6:
  - state first; collect all failing checked gates; unchecked reasons for not-started tasks only;
  - unset loyalty passes only `>= v` (v ≤ 1) and `> v` (v < 1);
  - a finished active-only prerequisite is unchecked;
  - an unknown availability delay and unknown other requirements are both unchecked, so a catalog stored before this change gives both;
  - never throw on any catalog `ProgressCatalog` accepts.

  Verify that the 3.2 tests pass, and flip those rows green.
- [x] 3.4 Add `lib/src/edition_table.dart` with `const editionTable` (`version: 1`, the five edition IDs) and the single owner-confirmed entry, The Good Times - Part 1 `666314b4d7f171c4c20226c3` allowed `{edge-of-darkness, unheard}`. Its source names the official wiki quest page and the owner's confirmation on 2026-11-12 (design D4). Add `pkg/test/edition_table_test.dart`, which checks that every entry uses known edition IDs and a non-empty source. Verify it passes.

## 4. Frozen tarkov.dev excerpt

- [ ] 4.1 Build `pkg/test/fixtures/tarkov_dev/`:
  - `regular_tasks.json` and `pve_tasks.json`: real wire `data.tasks` objects for 30-50 tasks picked per gate, plus the transitive closure of the tasks they reference (prerequisites, alternatives and `taskStatus` objectives), with `zones`, `position` and `outline` removed and translations dropped;
  - `traders.json`: the trader IDs used;
  - `SOURCE.md`: URLs, fetch date and the selection by gate.

  Download into the session scratchpad, not the repo, and delete the download afterwards. Each mode file stays under 150 KB. Verify both files parse with `parseProgressCatalog`.
- [ ] 4.2 Write `pkg/test/task_rules_fixture_test.dart`:
  - repeated evaluation is equal;
  - each gate kind (level, loyalty, prerequisite complete, failed and active, alternative, faction, game mode, edition, global variable, dialogue, delay, prestige and reputation) is hit by at least one excerpt task under a progress snapshot built to provoke it;
  - `SOURCE.md` has its URLs and fetch date;
  - each fixture is at most 200 KB.

  Verify it passes, and flip the three excerpt and determinism rows green.

## 5. Integration checks

- [ ] 5.1 Re-run the green-at-start rows: `mise run test` (it includes the package `dart test` and `test/data/progress_package_audit_test.dart`) and `mise run analyze`. Both must be clean. Run `dart format` over the changed files.
- [ ] 5.2 Check that nothing in `lib/` imports the rules (design D9 and S6): `rg "evaluateTasks|editionTable" lib` returns nothing. Check `mise run release-notes -- --check openspec/changes/add-task-rules/proposal.md` exits 0. Update the proposal's `## Release Notes` if anything shipped differs.

## Workflow follow-up

- Pre-ship review, then PR (finish: pr), then archive and the roadmap's next change (`add-task-log-progress`).
