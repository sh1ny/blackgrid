# Tasks

## Test map

All tests are offline with fixtures and hand-written fakes. Names below are the exact planned test names unless an existing name is shown. Green denotes retained existing coverage, to be re-run during apply; it does not claim a fresh test run during planning. New or relocated UI assertions start red. Parameterise both Ember rooms and the declared widths where applicable. Each row's state turns green only after its named test passes.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| local-data-durability → History retains the recorded verdict | Each source records its verdict | `test/application/selection_controller_test.dart` | local-data-durability: Each source records its verdict | green |
| local-data-durability → History retains the recorded verdict | Later data changes | `test/application/selection_controller_test.dart` | local-data-durability: Later data changes | green |
| local-data-durability → History retains the recorded verdict | No available decision or failed write | `test/application/selection_controller_test.dart` | local-data-durability: No available decision or failed write | green |
| local-data-durability → Missing history verdicts remain readable | Upgrade and reopen | `test/data/migration_test.dart` | local-data-durability: Upgrade and reopen | green |
| local-data-durability → Missing history verdicts remain readable | Import and round trip | `test/data/database_test.dart` | local-data-durability: Import and round trip | green |
| local-data-durability → Missing history verdicts remain readable | Unrecognised optional value | `test/data/database_test.dart` | local-data-durability: Unrecognised optional value | green |
| map-rail → Rail order puts raid-time sections first | Wide layout order | `test/ui/map_screen_test.dart` | map-rail: Wide layout order | green |
| map-rail → Rail order puts raid-time sections first | Compact layout order | `test/ui/map_screen_test.dart` | map-rail: Compact layout order | green |
| map-rail → Rail order puts raid-time sections first | Active map row stays alone | `test/ui/map_screen_test.dart` | map-rail: Active map row stays alone | green |
| scanner-evidence → Scanner shows the live scan switch and status | Switching on from Scanner | `test/ui/settings_dialog_test.dart` | scanner-evidence: Switching on from Scanner | green |
| scanner-evidence → Scanner shows the live scan switch and status | Unavailable runtime | `test/ui/settings_dialog_test.dart` | scanner-evidence: Unavailable runtime | green |
| scanner-evidence → Scanner shows the live scan switch and status | Setting cannot be saved | `test/ui/settings_dialog_test.dart` | scanner-evidence: Setting cannot be saved | green |
| scanner-evidence → Scanner shows the live scan switch and status | Setting cannot be saved when switching off | `test/ui/settings_dialog_test.dart` | scanner-evidence: Setting cannot be saved when switching off | green |
| scanner-evidence → Scan evidence panel is visible without scrolling | Desktop window | `test/ui/shell_test.dart` | scanner-evidence: Desktop window | green |
| scanner-evidence → Scan evidence panel is visible without scrolling | Short desktop window | `test/ui/shell_test.dart` | scanner-evidence: Short desktop window | green |
| scanner-evidence → Scan evidence panel is visible without scrolling | Narrow window | `test/ui/shell_test.dart` | scanner-evidence: Narrow window | green |
| scanner-evidence → Footer shows the live scan state | Live scan on | `test/ui/shell_test.dart` | footer says live scan is on when ready | green |
| scanner-evidence → Footer shows the live scan state | Live scan off | `test/ui/shell_test.dart` | footer says live scan is off and nothing is captured | green |
| scanner-evidence → Footer shows the live scan state | Live scan unavailable | `test/ui/shell_test.dart` | footer says live scan is unavailable | green |
| scanner-evidence → Scanner shows the record switch and its status | Recording runs | `test/ui/settings_dialog_test.dart` | scanner-evidence: Recording runs | green |
| scanner-evidence → Scanner shows the record switch and its status | Live scan not ready | `test/ui/settings_dialog_test.dart` | scanner-evidence: Live scan not ready | green |
| scanner-evidence → Scanner shows the record switch and its status | Write failure | `test/ui/shell_test.dart` | scanner-evidence: Write failure | green |
| scanner-evidence → Scanner shows the scan hotkey and lets the user rebind it | Registered hotkey | `test/ui/settings_dialog_test.dart` | scanner-evidence: Registered hotkey | green |
| scanner-evidence → Scanner shows the scan hotkey and lets the user rebind it | Hotkey held by another application | `test/ui/settings_dialog_test.dart` | scanner-evidence: Hotkey held by another application | green |
| scanner-evidence → Scanner shows the scan hotkey and lets the user rebind it | Rebind refused | `test/ui/settings_dialog_test.dart` | scanner-evidence: Rebind refused | green |
| scanner-evidence → Scanner shows the scan hotkey and lets the user rebind it | Live scan off | `test/ui/settings_dialog_test.dart` | scanner-evidence: Live scan off | green |
| scanner-evidence → Scanner shows the scan hotkey and lets the user rebind it | Live scan starting | `test/ui/settings_dialog_test.dart` | scanner-evidence: Live scan starting | green |
| workspace-shell → Answer precedes the workspace | Answer first in both areas | `test/ui/shell_test.dart` | workspace-shell: Answer first in both areas | green |
| workspace-shell → Answer precedes the workspace | Missing item and long reason | `test/ui/shell_test.dart` | workspace-shell: Missing item and long reason | green |
| workspace-shell → Selection semantics survive the new layout | Selection changes across areas | `test/ui/shell_test.dart` | workspace-shell: Selection changes across areas | green |
| workspace-shell → Selection semantics survive the new layout | History and later rejected scan | `test/ui/shell_test.dart` | workspace-shell: History and later rejected scan | green |
| workspace-shell → Top bar keeps navigation and timers reachable | Wide navigation | `test/ui/shell_test.dart` | workspace-shell: Wide navigation | green |
| workspace-shell → Top bar keeps navigation and timers reachable | Narrow navigation and disabled timers | `test/ui/shell_test.dart` | workspace-shell: Narrow navigation and disabled timers | green |
| workspace-shell → Inspector preserves the workspace | Docked details | `test/ui/shell_test.dart` | workspace-shell: Docked details | green |
| workspace-shell → Inspector preserves the workspace | Resize with open details | `test/ui/shell_test.dart` | workspace-shell: Resize with open details | green |
| workspace-shell → History rows show item pictures | History selection | `test/ui/history_panel_test.dart` | workspace-shell: History selection | green |
| workspace-shell → History rows show item pictures | Missing history picture | `test/ui/history_panel_test.dart` | workspace-shell: Missing history picture | green |
| workspace-shell → History rows show item pictures | Legacy history verdict | `test/ui/history_panel_test.dart` | workspace-shell: Legacy history verdict | green |
| workspace-shell → Status actions lead to their controls | Settings targets | `test/ui/shell_test.dart` | workspace-shell: Settings targets | green |
| workspace-shell → Status actions lead to their controls | Failed live scan save | `test/ui/shell_test.dart` | workspace-shell: Failed live scan save | green |

## 1. Recorded activity verdict and migration

- [x] 1.1 Record the accepted activity-verdict ADR using the next free number; document optional recorded verdict, unknown legacy data, coalesced item/mode history and distinction from current advice. Update openspec/architecture.md's index and ownership description; verify agreement with design D2 and existing ADR-0003.
- [x] 1.2 Add failing codec, database, migration and import round-trip tests for all local-data-durability → Missing history verdicts remain readable rows; cover v6→v7, earlier committed schema paths, missing/unsupported optional values without row loss or load-time mutation, and retaining unrelated settings/pins. Verify failures are the missing verdict field/migration, not fixture errors.
- [x] 1.3 Add the optional named verdict to ItemActivity/JSON and ActivityRecords, migrate additively, regenerate database.g.dart and drift_schemas/drift_schema_v7.json, and preserve import merge/replace behaviour. Verify 1.2 tests pass, existing newer-schema refusal tests still pass, and flip those map rows green. Document the optional field's meaning on the public API.
- [x] 1.4 Add failing controller tests for all local-data-durability → History retains the recorded verdict rows: manual, accepted scan and correction, later FIR/authority changes, null decision, failed write and a gated pending write while selection changes. Use explicit completers, not sleeps; verify the missing immutable verdict argument causes the red step.
- [x] 1.5 Capture the projected verdict before each recording await, pass it through HistoryController and persist in the existing transaction; keep existing generation and source fences. Verify 1.4 tests and current scan-feed/correction/history tests pass; flip the mapped rows green. Confirm no additional recording on history viewing or authority ticks.

## 2. Shared answer strip, top bar and targeted Settings

- [x] 2.1 Add failing shell widget tests for workspace-shell → Answer precedes the workspace, Selection semantics survive the new layout and Top bar keeps navigation and timers reachable. Assert both rooms at 1660×870, 1100×720, 960×720 and 900px width, empty/loading state, long reason, per-item FIR, all six plates and raw-ID absence. Retain existing controller-level authority tests; verify failures identify the displaced layout.
- [x] 2.2 Extract shared summary/FIR presentation and compose the one strip directly under the top bar; move enabled timers into the bar using existing projections. Preserve Ctrl K, search selection and labelled/compact actions. Verify 2.1 tests pass, including text scale 2, no horizontal page overflow, scan rejection retention, history close and return-to-latest-scan; flip those map rows green. Update widget API documentation with the new composition.
- [x] 2.3 Add failing widget tests for workspace-shell → Status actions lead to their controls and scanner-evidence's live-switch, hotkey and record-switch requirements. Open Settings through the actual shell entry points. Cover section visibility/focus, live-scan save failure in both directions, all hotkey states and rebind refusal, recording readiness, counters/path and close/reopen after recording write failure. Verify red steps fail for missing relocation/targeting, using fake scanner ports only.
- [x] 2.4 Move displaced configuration to the existing Settings dialog, add section targeting, connect status actions through existing controllers and keep Scanner's stop/error note visible after closing Settings. Preserve effective-mode authority and expose game-mode switching without overriding detected log mode. Verify 2.3 tests, existing live_scan_panel tests, Settings tests and retained footer tests pass; flip their mapped rows green. Document section-target and focus behaviour on affected APIs.

## 3. Inspector, history rows and area integration

- [x] 3.1 Add failing tests for workspace-shell → Inspector preserves the workspace and History rows show item pictures; assert docked/overlay boundary, Escape, focus return, reduced motion, preserved map viewport/detail expansion, all saved-verdict indicators, unknown legacy rows, missing/mode-mismatched icon fallbacks and recorded/current verdict disagreement. Verify failures reflect the new UI requirements.
- [x] 3.2 Build the inspector from current detail/requirement/source/history presentation, keeping state above breakpoint branches and both area workspaces mounted. Render X14 rows through existing ItemIcon leases and the recorded verdict, with accessible unknown/current-advice labels. Verify 3.1 tests pass, existing icon request-bound tests remain green and no per-row decision or timer is introduced; flip mapped rows green. Document state ownership and recorded/current advice distinction.
- [x] 3.3 Add failing map-rail ordering and scanner-evidence geometry tests from the map; update obsolete placement assertions rather than deleting behavioural checks. Verify no duplicate decision card, evidence frame visibility at desktop sizes, narrow answer-first order and preserved inputs/filter/search/Read Latest/floor/pin actions. Verify the intended relocation causes failures.
- [x] 3.4 Recompose Map and Scanner under the shell, retain temporary rail control order and saved-input expansion behaviour, and fit Scanner evidence into its remaining area with internal scrolling. Verify 3.3 tests and existing map-control/pin/scan-evidence/navigation regression tests pass; flip remaining mapped rows green. Update affected layout documentation to describe interim controls until map restyling.

## 4. Integration verification

- [ ] 4.1 Run `dart format` on changed Dart files, then `mise run analyze` and `mise run test`; verify no new findings or failing offline tests. Confirm every scenario maps to exactly one test-map row and each row has passing evidence before changing its state. Do not run qualification or launch the app as part of these commands.
- [ ] 4.2 Verify the complete shell across both rooms and the size/text-scale matrix with offline widget fixtures; run relevant Impeccable checks where supported for Dart and record actual support/results without claiming a web-only detector checked Flutter. Confirm preserved map controls, icon fallbacks, dialog entry points, section focus, timer settings and no UI colour literals outside theme roles. Keep live-game visual judgment unverified for milestone close.
- [ ] 4.3 Check release notes with `mise run release-notes -- --check openspec/changes/add-answer-strip/proposal.md`, run `openspec validate add-answer-strip --strict` and `git diff --check`; verify all pass and update proposal release notes to match shipped behaviour. No version bump: releases are disabled for this workflow.

## Workflow follow-up

- Implementation requires a new explicit apply request. Follow AGENTS.md's Dart skills and game-testing boundary in every implementation/review packet; use fresh workers per task group as the apply workflow directs.
- Commit each verified group through specwright-commit. Pre-ship review, archive and PR handling follow their own workflows after implementation.
- M8.5's second-monitor and alt-tab visual criterion is judged by the owner at milestone close after map and dialogs are restyled, as proposal.md explains. Agents never run live-game checks.
