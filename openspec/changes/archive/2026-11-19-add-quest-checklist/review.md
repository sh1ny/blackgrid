# Review

## Metadata

- **Round:** 1
- **Prior round:** none (this run re-checks only the round-1 Required Changes)
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** openspec/changes/add-quest-checklist/{proposal.md, design.md, specs/quest-checklist/spec.md, specs/workspace-shell/spec.md, specs/marker-preferences/spec.md}; main specs openspec/specs/{workspace-shell, marker-preferences, map-marker-popups}/spec.md; docs/adr/0041-local-progress-event-ledger.md; source lib/application/manual_progress_controller.dart, lib/application/local_progress_access.dart, lib/application/task_log_progress_controller.dart (readCurrent, _progressChanged), lib/application/map_controller.dart, lib/application/app_services.dart, lib/application/settings_controller.dart, lib/domain/settings.dart, lib/domain/local_progress.dart, lib/domain/map_marker_query.dart, lib/maps/live_map_normalizer.dart, lib/maps/prepared_map.dart, lib/ui/map_inspector.dart, lib/ui/shell.dart, lib/ui/panels.dart, packages/blackgrid_progress/lib/src/{progress_catalog_tasks.dart, parse_progress_catalog.dart}; bundled marker manifest (assets/maps/versions/d0f76ede.../manifest.json: all 803 bundled quest markers carry `details.id` and `details.quest.id`). Re-check run: design.md (Context, D5, decision summary, Resource Bounds, Flow & State Gaps, Mechanism Ledger), specs/marker-preferences/spec.md, specs/quest-checklist/spec.md, and the author's Rebuttals in review.md. Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, flutter-add-widget-test, dart-run-static-analysis.

## Findings

### Critical (blocking)

None.

### Moderate

**M1. The per-register pending lock does not stop a lost +/- step; the Mechanism Ledger's claim is false against the existing controller.** (Re-checked: fixed.)
Design (Flow & State Gaps, "Rapid +/- clicks"; Mechanism Ledger row 1) said the next step "reads the refreshed winner". In `ManualProgressController._perform` (`lib/application/manual_progress_controller.dart:341-370`) the key is removed from `_pending` as soon as the append returns, then `_requestRead()` only starts an async read and `notifyListeners()` fires. Until the read lands, `pending(target)` is false while `value(target)` still returns the pre-append winner, so a second + click appends the same absolute count (ADR-0041) and one step is silently lost.
Re-check: design.md "Rapid +/- clicks" now holds the register pending until a projection read that started after the append has landed (or failed), releases at once on a failed append, and names a controller test in `test/application/manual_progress_controller_test.dart` (read held on a completer; a second + is ignored; two + clicks from 2 end at 4). The Mechanism Ledger's first row and the Resource Bounds "Pending entries" row say the same. Holds.

**M2. The marker-preferences main spec keeps a scenario this change breaks.** (Re-checked: fixed.)
`openspec/specs/marker-preferences/spec.md`, "Bulk, search and quest controls keep working", scenario "Hide all then Show all", said "every marker is drawn" after Show all, which the active-quest filter makes false.
Re-check: specs/marker-preferences/spec.md now carries a MODIFIED block with the requirement's full text (all six scenarios kept). The requirement says the active-quest filter and Show all quests apply beside the quest name and trader filters, and the scenario reads "every marker that the active-quest filter leaves eligible is drawn". Holds.

**M3. D5 orders by "the live-map binding's source ID", which does not exist; the source of the current map's tarkov.dev ID and of map names is unspecified.** (Re-checked: fixed, with one note below.)
`LiveMapBinding` (`lib/maps/live_map_normalizer.dart:45-60`) holds only `sourceKey`, `mapId` and calibration; the tarkov.dev map ID appears only inside the live maps body during normalization (`live_map_normalizer.dart:159-166`), and the catalog has no maps table.
Re-check: D5 and Context now read "on the current map" from the current map's loaded quest markers (`details.quest.id` for the task, `details.id` for the objective), which live and bundled markers both carry. They define the fallback (no quest markers loaded: one group, ordered by trader then name, no marks) and drop per-objective map names. The decision summary row says so. specs/quest-checklist/spec.md has the matching ordering text, the "On this map" mark and a new "No quest markers loaded" scenario. Holds.
Note for the coordinator (not a new finding): dropping per-objective map names changes what users see under D5, which is `Chosen by: user`; the original D5 promised map names per objective. The ordering choice the user made is unchanged. The review instruction says a change to a `Chosen by: user` decision goes to the user first. I cannot see whether that happened, so confirm it with the user (or record their agreement in D5) before tasks.

### Suggestions

**S1. The projection stays attached for the app's lifetime; say so and bound it.** The Map workspace lives in an `IndexedStack` (`lib/ui/shell.dart:402`) and stays mounted on Scanner, so with D2's `attach()` in `MapWorkspace` the controller re-reads all winners (`readCurrent`, `task_log_progress_controller.dart:523-534`) on the shared queue after every inserted log batch, including during replay. State that this is now always, and that a replay interleaves at most one coalesced read per batch.

**S2. Specify the map filter when the mode has no catalog.** The done set for counter objectives needs catalog targets (D3). With winners loaded but `progressCatalog == null`, counters can never read done, yet the started-task filter still hides unstarted quests. Say whether the filter applies or falls back to `null`.

**S3. Align "count over 1" between spec and design.** D3 treats only whole-number counts over 1 as counters; the spec says "a target count over 1".

**S4. The "lazy list" bound is not achievable where the section lives.** The Map inspector is a single child of a `ListView` (`shell.dart:455-466`) and panels use `fitContent`, so a nested list must shrink-wrap. At the stated bound this is fine; correct the Resource Bounds row.

**S5. Quest row counts and the switch while saving.** Under the filter the quest rows will count markers that are not drawn, and the new switch's spec does not say whether it ignores clicks while settings save, as rows do.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1) In design.md, replace the "Rapid +/- clicks" gap and the first Mechanism Ledger row with a lock that holds until a projection read started after the append has landed (or stepping from the controller's last appended value until a read supersedes it), and name the controller-level test that proves two quick + clicks record +2. **Re-checked: applied** (Flow & State Gaps "Rapid +/- clicks", Mechanism Ledger row 1, Resource Bounds "Pending entries").
2. (M2) Add a MODIFIED "Bulk, search and quest controls keep working" requirement to `specs/marker-preferences/spec.md`, carrying its full text, with the "Hide all then Show all" scenario reworded so that after Show all every marker eligible under the active-quest filter is drawn, and the progress filter listed beside the quest name and trader filters. **Re-checked: applied.**
3. (M3) In design.md D5 (and Context), replace "the live-map binding's source ID" with the actual source of the current map's tarkov.dev ID and of per-objective map names, and state the fallback when that source is unavailable; reflect the fallback in the quest-checklist spec if it changes what users see. **Re-checked: applied** (D5, decision summary row, spec ordering, "On this map" mark, "No quest markers loaded" scenario). The removal of per-objective map names from a `Chosen by: user` decision still needs the user's confirmation (see the note under M3).

CHANGES_APPLIED: yes

## Rebuttals

- M1: fixed. design.md Flow & State Gaps "Rapid +/- clicks", Mechanism Ledger first row and Resource Bounds "Pending entries": the register stays pending until a read started after its append has landed; controller test named (two + clicks from 2 end at 4, second click ignored while the read is held).
- M2: fixed. specs/marker-preferences/spec.md now MODIFIES "Bulk, search and quest controls keep working" with its full text; the active-quest filter and Show all quests apply beside the quest name and trader filters, and "Hide all then Show all" draws every marker the active-quest filter leaves eligible.
- M3: fixed. design.md D5 and Context: "on the current map" is read from the current map's loaded quest markers (task ID `details.quest.id`, objective ID `details.id`), not a map ID; no per-objective map names; fallback with no quest markers loaded is one group and no marks. specs/quest-checklist/spec.md ordering text, the "On this map" mark and a new "No quest markers loaded" scenario reflect it.
