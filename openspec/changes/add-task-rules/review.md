# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** openspec/changes/add-task-rules/proposal.md, design.md, specs/task-availability/spec.md, specs/task-catalog/spec.md; openspec/specs/task-catalog/spec.md (size only); openspec/architecture.md (blackgrid_progress row, ADR index); openspec/roadmap.md (M9); docs/adr/0041, docs/adr/0042; packages/blackgrid_progress/lib/blackgrid_progress.dart and lib/src/progress_catalog.dart, progress_catalog_tasks.dart, parse_progress_catalog.dart; lib/domain/local_progress.dart; lib/domain/catalog.dart (GameMode); lib/data/catalog_normalizer.dart (imports); test/data/catalog_normalizer_progress_test.dart (imports); test/data/progress_package_audit_test.dart; mise.toml. Re-fetched json.tarkov.dev/{regular,pve,pvp-season}/tasks on 2026-11-12 (read-only) to check the Context counts and the fixture closure size. Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis.
- **Re-check (Required Changes only):** fresh-context subagent (Claude Code specwright-reviewer), 2026-11-12. Re-read design.md (D2, D4, D6, D7, D8, decision summary, Flow & State Gaps, Open Questions), specs/task-availability/spec.md, specs/task-catalog/spec.md (delay requirements), proposal.md (edition and mode wording), and packages/blackgrid_progress/lib/src/parse_progress_catalog.dart (reference paths, lines 59-62, 109-145, 172) and progress_catalog_tasks.dart (`_withObjectives`, lines 32-49). Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

The Context facts check out against the live data: regular has 503 tasks, 168 `globalVariable` rows (all `>=`, int values), 12 `dialogue` rows (`id`, `type`, `traders`), 10 nonzero delays, 8 tasks with neither `otherRequirements` nor delay fields, prerequisite status sets 195/12/10/3/2, 112 `level >=` plus 8 reputation trader requirements, 34 faction-only tasks, 3 prestige tasks and 4 `['regular']` restrictions. Both edition seed task IDs exist in all three mode catalogs. The precedence, the unchecked-never-locks contract and the lenient catalog extension are consistent with ADR-0041 and ADR-0042. Stored-format compatibility holds in both directions: `CatalogTask.fromJson` ignores unknown keys, and `_optional` reads absent keys as null (`progress_catalog.dart:244-247`).

### Critical (blocking)

None.

### Moderate

**M1. The package `GameMode` enum clashes with the app's `GameMode` and cannot express the seasonal catalog (D2).** *Resolved in re-check.*
- **Name clash:** D2 adds a public `GameMode` enum (regular/pve) exported from `blackgrid_progress.dart`. The app already declares `enum GameMode { unknown, pvp, pve, seasonal }` in `lib/domain/catalog.dart:5`.
  - `lib/data/catalog_normalizer.dart:3,6` imports both the package and `../domain/catalog.dart` and uses `GameMode` (lines 29 and 36).
  - `test/data/catalog_normalizer_progress_test.dart` does the same (imports at lines 5 and 11, uses at lines 97-99).
  - Both files would fail to compile with `ambiguous_import` as soon as the package exports the new enum.
- **Missing mode:** the app fetches and stores a third task catalog for `GameMode.seasonal` (route `pvp-season`, `catalog.dart:15`; 462 tasks live today). `ProgressScope` accepts seasonal progress (`local_progress.dart:40-44`). A regular/pve-only enum in the ADR-0043 contract leaves the first consumer unable to evaluate seasonal progress without changing the public API this change fixes.
- The mode is used only for the game-mode gate, which compares against tarkov.dev route strings (`regular`, `pve`; seasonal tasks carry no restriction today).

**M2. Trivial-pass loyalty rule passes requirements that an unset loyalty may fail (D6, spec "Trader loyalty gate").** *Resolved in re-check.*
- **The rule:** D6 passes `<= n` (n ≥ 1), `< n` (n > 1) and `= 1` with loyalty unset, "because trader loyalty starts at 1". A starting value is not the current value. A player whose real loyalty is 3 fails `<= 2`.
- **The conflict:** a pass on unknown input is a guess. That contradicts S1 (undecidable gates are unchecked, chosen by the user) and ADR-0042's "never invented" values.
- **Exposure:** no live `level` requirement uses these comparisons today; all 112 are `>=`. tarkov.dev does use `<=` and `<` on trader requirements (5 reputation rows), so the shape is real.
- **Consequence:** a future `<=` loyalty requirement would report `available` with no doubt shown. The sound rule is "passes when every possible loyalty passes", which in practice means `>= v` with v ≤ 1 or `> v` with v < 1. The spec sentence "A requirement that a loyalty of 1 always meets SHALL pass" carries the same flaw.

### Suggestions

- **S-a. Fixture references must be closed transitively (D8).** *Applied (Required Change 4).*
  - **Why:** `parseProgressCatalog` rejects any unresolved task reference: prerequisites through `_reference` (`parse_progress_catalog.dart:172`), fail-condition `taskStatus` at line 123 and objective `taskStatus` at line 60. "plus every task they reference" must therefore mean the transitive closure over all three kinds, or the excerpt will not parse.
  - **Size:** measured on today's data, picking one task per gate gives a union closure of about 15 tasks / 50 KB in regular, 36 tasks / 96 KB in PvE (the `['pve']` restricted task pulls a 22-task chain) and 17 tasks / 50 KB in seasonal. That fits the 150 KB target, so only the wording needs fixing.
- **S-b. Unknown delays are invisible.** The unchecked set has `AvailabilityDelay(min, max)` but nothing for an unknown delay. A stale stored catalog, or a wrong-typed `availableDelaySecondsMin`, drops the delay gate silently. *Applied: `AvailabilityDelayUnknown` added to D2, and the spec lists "a nonzero or unknown availability delay" as unchecked.*
  - Today the 8 tasks without delays also lack `otherRequirements`, so `OtherRequirementsUnknown` covers them. A malformed delay beside a valid list would show no doubt.
  - Either add `AvailabilityDelayUnknown` or state in the spec that an unknown delay is not reported.
- **S-c. Two spec sentences read as contradictory.** "The unchecked reasons SHALL be listed whatever the status" (task-availability spec line 58) and "A started or done task SHALL list none" (line 194) conflict unless line 58 is read as "locked or available". Reword line 58 to say "whether locked or available". *Applied: line 58 now reads "whether the task is locked or available".*
- **S-d. Edition vocabulary ownership.** `PlayerProgress.edition` is opaque text (ADR-0041), so the table's five IDs (`standard`, ..., `unheard`) become the vocabulary that any future writer must use. Otherwise every entered edition reads as `EditionUnrecognised`. Say so in ADR-0043 so that `add-manual-progress` writes these IDs. *Applied: D2 now puts this into the ADR-0043 scope.*
- **S-e. Small Business - Part 3 `excluded {unheard}` locks on conflicting evidence.** Design Context says the wiki contradicts itself. A wrong exclusion hides a takeable task from Unheard owners, which is the harm S1 was chosen to avoid. Unless the owner confirms it from the game, drop the entry. An absent entry passes. *Applied: the owner dropped the entry (D4).*
- **S-f. Implementation trap.** `CatalogTask._withObjectives` (`progress_catalog_tasks.dart:32-49`) copies every field by hand. The new `otherRequirements` and delay fields must be added there, or tasks with shared objectives lose them inside `ProgressCatalog`. No live task has shared objectives today, so only a test with a shared objective would catch the omission. *Applied: D7 now requires every hand-written copy, naming `_withObjectives`, to copy the new fields.*

### Re-check of the applied suggestions (no new problem; editorial only, not required)

None of the applied suggestions introduces a contradiction with the specs, the ADRs or the code. Four small editorial slips were noticed. None changes behaviour, and none is a Required Change:
- D7 cites `_withObjectives` at `progress_catalog_tasks.dart:36-54`; it is at lines 32-49 on the branch. The name is correct, so an implementer finds it.
- D8's first fixture bullet has a broken sentence: "... 96 KB for PvE. with `zones`, `position` and `outline` removed ...". The period should be a comma.
- D3's Rejected line still says "about 2 entries", and the Flow & State Gaps "Stale catalog" bullet names only `OtherRequirementsUnknown`. A stale catalog now also gives `AvailabilityDelayUnknown`, as the spec and the task-catalog "stored before" scenario already state.
- D8 lists "alternatives" where Required Change 4 said "fail-condition task statuses". The parser derives alternatives only from fail-condition `taskStatus` rows (`parse_progress_catalog.dart:122-145`), so the two are the same set of references. This is accepted as equivalent.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **(M1)** In design D2, the diagrams and the ADR-0043 scope, replace the package `GameMode` with a name that does not clash with `lib/domain/catalog.dart`'s `GameMode` (for example `CatalogMode`), or take the mode as the tarkov.dev route string. Make it cover the seasonal catalog (`pvp-season`). Update the task-availability spec's game-mode requirement accordingly: the evaluated mode is compared with the task's restriction strings, and a seasonal evaluation is defined. This touches D2 (`Chosen by: user`). The type name and the seasonal coverage are additive and do not reverse the chosen contract, but put it to the owner if the decision mode requires.
   - **Resolved.** D2 now defines `ProgressMode {regular, pve, seasonal}`, each carrying its tarkov.dev name (`regular`, `pve`, `pvp-season`). It records why the name is not `GameMode` and that the owner chose it on 2026-11-12. The T1 diagram and the decision-summary row use `ProgressMode`, and the summary row lists the package `GameMode` as rejected. The spec's "Game mode gate" now says the evaluated mode is one of regular, PvE or seasonal, and that a known restriction list without the mode's tarkov.dev name fails the gate.
2. **(M2)** In design D6 and the task-availability spec "Trader loyalty gate", restrict the unset-loyalty pass to requirements that every loyalty value meets (`>= v` with v ≤ 1, `> v` with v < 1). Make `<=`, `<` and `=` with loyalty unset produce `LoyaltyUnset`. Add a scenario: "a task requires Fence level at most 2 and loyalty is unset → listed as unchecked". D6 is `Chosen by: agent`.
   - **Resolved.** D6 passes an unset loyalty only for `>= v` (v ≤ 1) and `> v` (v < 1), and makes upper bounds and `=` unchecked. The decision-summary row matches. The spec requirement says the same and makes every other unset-loyalty case unchecked. The new scenario "Upper bound with loyalty not entered" uses Ragman instead of Fence. That has the same effect: a level requirement of at most 2 with loyalty unset is listed as unchecked and does not lock the task.
3. **(D4 open question)** Record the owner's answer on the two edition seed entries in design D4 (kept, changed or dropped, with the owner's words) and remove the Open Question before tasks are written. D4 states the entries stay only if the owner confirms them at design review. This reviewer cannot give that confirmation (see S-e).
   - **Resolved.** D4 records the owner's decision of 2026-11-12. The Good Times - Part 1 (`666314b4d7f171c4c20226c3`) is kept as `allowed {edge-of-darkness, unheard}`, with the owner confirming that Unheard is included. Small Business - Part 3 is dropped on the owner's decision, because the reward-only reading is more likely. The decision-summary row matches, and Open Questions now reads "None".
4. **(S-a)** In design D8, change "plus every task they reference" to "plus the transitive closure of every task referenced through prerequisites, fail-condition task statuses and objective task statuses".
   - **Resolved.** D8 now requires "the transitive closure of every task they reference (prerequisites, alternatives and `taskStatus` objectives)" and gives the parse-rejection reason. Alternatives are the fail-condition `taskStatus` references (see the re-check note above), so all three reference kinds are covered.

CHANGES_APPLIED: yes

## Rebuttals
