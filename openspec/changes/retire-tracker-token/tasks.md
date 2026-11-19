# Tasks

## Test map

Rows marked green ride along unchanged inside a MODIFIED requirement. Task 8.2 re-runs them. Where a row says "(locate)", task 8.2 finds the existing test that proves the scenario and writes its name in the row, or adds one if none exists.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| progress-authority → Advice reads the effective mode's local progress | Finished task from the logs | test/domain/decision_engine_test.dart | progress-authority: Finished task from the logs | green |
| progress-authority → Advice reads the effective mode's local progress | Manual edit recomputes the shown advice | test/application/selection_controller_test.dart | progress-authority: Manual edit recomputes the shown advice | green |
| progress-authority → Advice reads the effective mode's local progress | Other mode's progress is not used | test/application/progress_authority_test.dart | progress-authority: Other mode's progress is not used | green |
| progress-authority → Advice reads the effective mode's local progress | Unknown mode | test/application/progress_authority_test.dart | progress-authority: Unknown mode | green |
| progress-authority → Unrecorded progress counts as not started, zero or not built | Empty wipe with level set | test/domain/decision_engine_test.dart | progress-authority: Empty wipe with level set | green |
| progress-authority → Unrecorded progress counts as not started, zero or not built | Level unset | test/domain/decision_engine_test.dart | progress-authority: Level unset | green |
| progress-authority → Unrecorded progress counts as not started, zero or not built | Counted objective | test/domain/decision_engine_test.dart | progress-authority: Counted objective | green |
| progress-authority → Unrecorded progress counts as not started, zero or not built | Started task skips its gates | test/domain/decision_engine_test.dart | progress-authority: Started task skips its gates | green |
| progress-authority → Unrecorded progress counts as not started, zero or not built | Started task with an unrecorded prerequisite | test/domain/decision_engine_test.dart | progress-authority: Started task with an unrecorded prerequisite | green |
| progress-authority → Unrecorded progress counts as not started, zero or not built | Restartable failed task | test/domain/decision_engine_test.dart | progress-authority: Restartable failed task | green |
| progress-authority → Unrecorded progress counts as not started, zero or not built | Non-restartable failed task | test/domain/decision_engine_test.dart | progress-authority: Non-restartable failed task | green |
| progress-authority → Unrecorded progress counts as not started, zero or not built | Level 1 minimum with no level | test/domain/decision_engine_test.dart | progress-authority: Level 1 minimum with no level | green |
| progress-authority → Unrecorded progress counts as not started, zero or not built | Unset faction | test/domain/decision_engine_test.dart | progress-authority: Unset faction | green |
| progress-authority → Hideout items count in full until the level is built | Level built | test/domain/decision_engine_test.dart | progress-authority: Level built | green |
| progress-authority → Hideout items count in full until the level is built | Next level | test/domain/decision_engine_test.dart | progress-authority: Next level | green |
| progress-authority → Hideout items count in full until the level is built | Later level | test/domain/decision_engine_test.dart | progress-authority: Later level | green |
| progress-authority → Edition gates stay unknown | Edition-gated task | test/domain/decision_engine_test.dart | progress-authority: Edition-gated task | green |
| progress-authority → Edition gates stay unknown | No edition list | test/domain/decision_engine_test.dart | progress-authority: No edition list | green |
| progress-authority → Unavailable local progress is reported, never treated as empty | Wipe history unavailable | test/application/progress_authority_test.dart | progress-authority: Wipe history unavailable | green |
| progress-authority → Unavailable local progress is reported, never treated as empty | Old progress still counts | test/application/progress_authority_test.dart | progress-authority: Old progress still counts | green |
| progress-authority → Unavailable local progress is reported, never treated as empty | Read fails after a good read | test/application/progress_authority_test.dart | progress-authority: Read fails after a good read | green |
| raid-timers → Built hideout levels come from local progress for the same mode | Progress for the mode | test/domain/raid_timers_test.dart | raid-timers: Progress for the mode | green |
| raid-timers → Built hideout levels come from local progress for the same mode | Higher level counts lower bonuses | test/domain/raid_timers_test.dart | raid-timers: Higher level counts lower bonuses | green |
| raid-timers → Built hideout levels come from local progress for the same mode | Progress for another mode | test/domain/raid_timers_test.dart | raid-timers: Progress for another mode | green |
| raid-timers → Built hideout levels come from local progress for the same mode | Progress unavailable | test/domain/raid_timers_test.dart | raid-timers: Progress unavailable | green |
| raid-timers → Built hideout levels come from local progress for the same mode | Stale progress | test/domain/raid_timers_test.dart | raid-timers: Stale progress | green |
| local-data-durability → Saved progress-site tokens are deleted at startup | Upgrade with saved tokens | test/data/retired_tokens_test.dart | local-data-durability: Upgrade with saved tokens | green |
| local-data-durability → Saved progress-site tokens are deleted at startup | Temporary token file left by a crash | test/data/retired_tokens_test.dart | local-data-durability: Temporary token file left by a crash | green |
| local-data-durability → Saved progress-site tokens are deleted at startup | Nothing saved | test/data/retired_tokens_test.dart | local-data-durability: Nothing saved | green |
| local-data-durability → Saved progress-site tokens are deleted at startup | A file cannot be deleted | test/data/retired_tokens_test.dart | local-data-durability: A file cannot be deleted | green |
| local-data-durability → Saved progress-site tokens are deleted at startup | Unexpected file in the folder | test/data/retired_tokens_test.dart | local-data-durability: Unexpected file in the folder | green |
| local-progress → Database upgrade preserves existing application behavior | Upgrade and reopen | test/data/migration_test.dart | local-data-durability: Upgrade and reopen | green |
| local-progress → Database upgrade preserves existing application behavior | Newer database | test/data/migration_test.dart | (locate) | green |
| settings-page → Settings sections and their order | Sidebar order | test/ui/settings_page_test.dart | sidebar lists eight sections in order | green |
| settings-page → Settings sections and their order | Jump to a section | test/ui/settings_page_test.dart | settings-page: Jump to a section | green |
| settings-page → Settings sections and their order | Jump to Diagnostics | test/ui/settings_page_test.dart | settings-page: Jump to Diagnostics | green |
| settings-page → Diagnostics starts collapsed each time | Reopen | test/ui/settings_page_shell_test.dart | settings-page: Reopen | green |
| settings-page → Diagnostics starts collapsed each time | Open at a section | test/ui/settings_page_shell_test.dart | settings-page: Open at a section | green |
| settings-page → Changes save as they are made | Switch saves at once | test/ui/settings_page_test.dart | settings-page: Switch saves at once | green |
| settings-page → Changes save as they are made | Settings could not be read | test/ui/settings_page_test.dart | settings-page: Settings could not be read | green |
| settings-page → Every setting stays reachable | All controls present | test/ui/settings_page_test.dart | settings-page: All controls present | green |
| settings-page → Every setting stays reachable | Disabled rule kept | test/ui/settings_page_test.dart | settings-page: Disabled rule kept | green |
| settings-page → Settings opens at the section a link names | Status bar Progress | test/ui/settings_page_shell_test.dart | settings-page: Status bar Progress | green |
| settings-page → Settings opens at the section a link names | Already open | test/ui/settings_page_shell_test.dart | settings-page: Already open | green |
| workspace-shell → Status actions lead to their controls | Settings targets | test/ui/shell_test.dart | workspace-shell: Settings targets | green |
| workspace-shell → Status actions lead to their controls | Settings target while the page is open | test/ui/shell_test.dart | workspace-shell: Settings target while the page is open | green |
| workspace-shell → Status actions lead to their controls | Progress status words | test/ui/shell_test.dart | workspace-shell: Progress status words | green |
| workspace-shell → Status actions lead to their controls | Loading after a mode switch | test/application/progress_authority_test.dart | workspace-shell: Loading after a mode switch | green |
| workspace-shell → Status actions lead to their controls | Edit keeps the label | test/application/progress_authority_test.dart | workspace-shell: Edit keeps the label | green |
| workspace-shell → Status actions lead to their controls | Progress unavailable | test/ui/shell_test.dart | workspace-shell: Progress unavailable | green |
| workspace-shell → Status actions lead to their controls | Failed live scan save | test/ui/shell_test.dart | workspace-shell: Failed live scan save | green |
| workspace-shell → Status actions lead to their controls | Status bar presentation and binding | test/ui/shell_test.dart | workspace-shell: Status bar presentation and binding | green |
| settings-diagnostics → Problems the player must act on stay reachable from the main windows | Rejected scan still explains itself | test/ui/scan_diagnostics_test.dart | (locate) | green |
| settings-diagnostics → Problems the player must act on stay reachable from the main windows | Errors the player must act on stay visible | test/ui/settings_page_shell_test.dart | (locate) | green |
| settings-diagnostics → Problems the player must act on stay reachable from the main windows | Local progress error stays reachable | test/ui/settings_page_shell_test.dart | settings-diagnostics: Local progress error stays reachable | green |
| settings-diagnostics → Diagnostics shows item data and progress source detail | Current catalog | test/ui/settings_diagnostics_test.dart | (locate) | green |
| settings-diagnostics → Diagnostics shows item data and progress source detail | No catalog | test/ui/settings_diagnostics_test.dart | Diagnostics says there is no complete item data download | green |
| settings-diagnostics → Diagnostics shows item data and progress source detail | Local progress unavailable | test/ui/settings_diagnostics_test.dart | settings-diagnostics: Local progress unavailable | green |
| verdict-presentation → One-line verdict reason | Keep names the need that decided it | test/domain/verdict_reason_test.dart | Keep names the first actionable need with its count | green |
| verdict-presentation → One-line verdict reason | Keep with an unknown count | test/domain/verdict_reason_test.dart | Keep with an unknown count has no number | green |
| verdict-presentation → One-line verdict reason | Keep for later names the future need | test/domain/verdict_reason_test.dart | Keep for later names the first future need | green |
| verdict-presentation → One-line verdict reason | Check names the first open question | test/domain/verdict_reason_test.dart | Check with only found in raid open names it | green |
| verdict-presentation → One-line verdict reason | Check picks questions in a fixed order | test/domain/verdict_reason_test.dart | Check names the first open input in the fixed order | green |
| verdict-presentation → One-line verdict reason | Check wording for each open input | test/domain/verdict_reason_test.dart | Check wording for each open input | green |
| verdict-presentation → One-line verdict reason | Found in raid unknown outranks the needs it leaves open | test/domain/verdict_reason_test.dart | found in raid outranks an unresolved found-in-raid need | green |
| verdict-presentation → One-line verdict reason | Found in raid unknown names the first need that requires it | test/domain/verdict_reason_test.dart | Found in raid unknown names the first need that requires it | green |
| verdict-presentation → One-line verdict reason | Needs that do not apply are skipped | test/domain/verdict_reason_test.dart | Needs that do not apply are skipped | green |
| verdict-presentation → One-line verdict reason | Found in raid unknown with no need that requires it | test/domain/verdict_reason_test.dart | Check with only found in raid open names it | green |
| verdict-presentation → One-line verdict reason | Flea and Trader compare the prices | test/domain/verdict_reason_test.dart | Flea compares gross prices with the best trader | green |
| verdict-presentation → One-line verdict reason | Trader for each way the engine reaches it | test/domain/verdict_reason_test.dart | Trader wording for each engine path | green |
| verdict-presentation → One-line verdict reason | Flea with no trader offer | test/domain/verdict_reason_test.dart | Flea with no trader offer | green |
| verdict-presentation → One-line verdict reason | Price unavailable | test/domain/verdict_reason_test.dart | Price unavailable wording | green |
| verdict-presentation → One-line verdict reason | A long reason at the narrowest card | test/ui/shell_test.dart | long catalog reason wraps fully inside the shared strip | green |
| player-facing-text → Shown states use plain-language labels | Stale catalog in the footer | test/ui/shell_test.dart | (locate) | green |
| player-facing-text → Shown states use plain-language labels | Imported scan in history | test/ui/history_panel_test.dart | (locate) | green |
| player-facing-text → Shown states use plain-language labels | Every value has a label | test/ui/labels_test.dart | every value of every shown kind has a plain label | green |
| player-facing-text → Shown states use plain-language labels | Unknown found-in-raid state | test/ui/shell_test.dart | (locate) | green |
| player-facing-text → Times are shown in local time | History row time | test/ui/history_panel_test.dart | (locate) | green |
| player-facing-text → Times are shown in local time | Earlier day | test/ui/history_panel_test.dart | player-facing-text: Earlier day | green |
| player-facing-text → Times are shown in local time | Missing flea quote time | test/ui/scanner_workspace_test.dart | scanner-workspace: Missing prices | green |
| player-facing-text → Times are shown in local time | No UTC time in the inspector | test/ui/scanner_workspace_test.dart | (locate) | green |
| scanner-evidence → Scanner workspace omits configuration rail | Scanner functions remain reachable without the old rail | test/ui/scanner_screen_test.dart | scanner-evidence: Scanner functions remain reachable without the old rail | green |
| scan-frame-recording → Recordings stay local and carry no credentials or progress | Recording with local progress recorded | test/application/scan_coordinator_recording_test.dart | scan-frame-recording: Recording with local progress recorded | green |
| scan-frame-recording → Recordings stay local and carry no credentials or progress | Timing log while recording | test/application/scan_coordinator_recording_test.dart | timing log line keys are the same with recording on | green |
| legacy-import → An import never changes this computer's own inputs | Replace keeps live scan and hotkey | test/data/legacy_import_test.dart | a Replace import keeps live scan and the scan hotkey and applies imported preferences | green |
| legacy-import → An import never changes this computer's own inputs | Replace keeps input folders | test/data/legacy_import_test.dart | (locate) | green |
| legacy-import → An import never changes this computer's own inputs | Import with no stored settings | test/data/legacy_import_test.dart | (locate) | green |
| legacy-import → An import never changes this computer's own inputs | Imported Tracker switch is ignored | test/data/legacy_import_test.dart | legacy-import: Imported Tracker switch is ignored | green |
| task-catalog → The task catalog does not change advice | Same advice with and without the block | test/domain/decision_engine_test.dart | (locate) | green |
| task-catalog → The task catalog does not change advice | Task catalog unavailable | test/domain/decision_engine_test.dart | task-catalog: Task catalog unavailable | green |

## 1. ADR and architecture

- [x] 1.1 Write `docs/adr/0046-local-progress-is-the-only-progress-authority.md` (MADR short form, `Status: accepted`, today's date, `Supersedes: 0007 (partly), 0031 (partly), 0041 (partly), 0044 (partly)`) recording design D1, D3–D5 and D7 with their rejected alternatives. Verify the file exists and its Supersedes line names the four ADRs.
- [x] 1.2 Update `openspec/architecture.md`: the T4 boundary list (drop tarkovtracker.org and the DPAPI channel; name `blackgrid/local_data`), the component diagram and table (`ProgressAuthority` replaces `ProgressController` + `TrackerClient`; the runner row lists `localDataPath` only), the state table (remove the Tracker token and Tracker progress rows; add the `ProgressAuthority` facts row), contracts (remove the Tracker and credentials-channel bullets), resource rows (Tracker progress; HTTP bodies → catalog only) and the ADR index (add 0046; mark 0007, 0031, 0041 and 0044 "partly superseded by 0046"). Verify with `grep -n -i "tracker\|dpapi" openspec/architecture.md`, which returns only historical ADR index wording.

## 2. Progress facts and the decision engine

- [x] 2.1 Read the `dart-use-pattern-matching`, `dart-write-documentation` and `dart-add-unit-test` skills. Add `lib/domain/progress_facts.dart`: an immutable `ProgressFacts` (mode, task states, objective counts and completions, station levels, level, faction upper-cased to `BEAR`/`USEC`, edition), with lookups that return the D3 defaults and a builder from `LocalProgressSnapshot` winners. Add `test/domain/progress_facts_test.dart` for the defaults and the winner mapping, including unset events and faction case. Verify with `mise run test -- test/domain/progress_facts_test.dart`.
- [x] 2.2 Write failing engine tests in `test/domain/decision_engine_test.dart` for the progress-authority rows: Finished task from the logs, Empty wipe with level set, Level unset, Counted objective, Started task skips its gates, Started task with an unrecorded prerequisite, Restartable failed task, Non-restartable failed task, Level 1 minimum with no level, Unset faction, Level built, Next level, Later level, Edition-gated task and No edition list. Add task-catalog: Task catalog unavailable (the same advice with and without `progressCatalog`, apart from restartable failed tasks). Use small synthetic catalogs. Verify they fail for the missing `ProgressFacts` input.
- [x] 2.3 Change `InspectionContext` to carry `ProgressFacts?` (drop `progressStale`). Change `DecisionEngine._need`, `_gate` and `_fleaEligible` to the D3/D4 mapping: started skips gates; a failed task counts as done unless `progressCatalog` marks it `restartable == true`; levels ≤1 pass; edition lists are unknown; hideout parts count 0; stations are built when `stationLevel >= level`. Rename `OpenInput.trackerProgress` to `OpenInput.progress`, with the warning "Progress unavailable". Verify the 2.2 tests pass and flip their rows green.
- [x] 2.4 Update `test/domain/verdict_reason_test.dart` and `lib/domain/verdict_reason.dart` so the progress open input reads "Progress unavailable" in the fixed order (rows: Check picks questions in a fixed order, Check wording for each open input). Verify with `mise run test -- test/domain/verdict_reason_test.dart` and flip the rows green.
- [x] 2.5 Write failing tests in `test/domain/raid_timers_test.dart` for the raid-timers rows (Progress for the mode, Higher level counts lower bonuses, Progress for another mode, Progress unavailable, Stale progress), then change `scavCooldownLength`, `raidTimersView` and the no-bonus tooltip to take `ProgressFacts?`. Bonus keys split at the last `-`, and a station counts when its level ≥ the bonus level. The tooltip reads "Progress unavailable: no hideout bonuses". Verify the tests pass and flip the rows green.

## 3. ProgressAuthority and wiring

- [x] 3.1 Write failing service tests in `test/application/progress_authority_test.dart` with a hand-written fake `LocalProgressAccess` and a fake mode source that use completers, never sleeps. Cover these rows: Other mode's progress is not used, Unknown mode, Wipe history unavailable, Old progress still counts, Read fails after a good read, Loading after a mode switch and Edit keeps the label. Also cover a stale PvP read dropped after a switch to PvE, coalesced reads (one in flight plus one dirty), and `loading` while access has not loaded. Verify they fail.
- [x] 3.2 Implement `lib/application/progress_authority.dart` per design D1, D2 and D5: it follows `CatalogController.mode` and listens to `LocalProgressAccess`, and it publishes `mode`, `status` (`loading`, `local`, `unavailable`) and `facts`. Verify the 3.1 tests pass and flip their rows green.
- [x] 3.3 Wire it in `AppServices`: move `localProgress` construction above `selection` and `raidTimers`, build `ProgressAuthority` before both, and pass it to `SelectionController` (in place of `ProgressController`, dropping `updateAge`) and `RaidTimersController` (as the `RaidTimerProgressSource`, now exposing `facts`). Remove the progress refresh from `setMode` and dispose it in order. Write a failing `selection_controller_test.dart` test for "progress-authority: Manual edit recomputes the shown advice" first, then verify it and `mise run test -- test/application` pass.
- [x] 3.4 Delete `lib/application/progress_controller.dart`, `lib/data/tracker_client.dart`, `lib/domain/progress.dart`, `lib/data/credential_store.dart`, `lib/domain/credential_store.dart` and their tests (`progress_controller_test.dart`, `tracker_client_test.dart`, `credential_store_test.dart`). Move the remaining tests that built `ProgressSnapshot`s (`app_services*_test.dart`, `scan_*_test.dart`, `raid_timer*_test.dart`, `decision_engine_test.dart` and the UI tests) to `ProgressFacts` fixtures. Verify `grep -rn "ProgressSnapshot\|TrackerClient\|ProgressController\|CredentialStore" lib test` is empty and `mise run analyze` passes.

## 4. Status bar, Settings and Diagnostics

- [x] 4.1 Read the `flutter-add-widget-test` skill. Write failing widget tests for these rows: workspace-shell Settings targets, Settings target while the page is open, Progress status words and Progress unavailable (`shell_test.dart`); settings-page Status bar Progress, Open at a section and settings-diagnostics Local progress error stays reachable (`settings_page_shell_test.dart`); Sidebar order and All controls present (`settings_page_test.dart`); settings-diagnostics Local progress unavailable (`settings_diagnostics_test.dart`); scanner-evidence Scanner functions remain reachable without the old rail (`scanner_screen_test.dart`); and player-facing-text Every value has a label (`labels_test.dart`, with the local progress status values). Delete the Save token, Token action fails and No mode tests, plus the Tracker cooldown Diagnostics test. Verify they fail.
- [x] 4.2 Replace the status bar's Tracker item with the Progress item (`Key('status-progress')`, "Progress loading/local/unavailable", opening `SettingsSection.localProgress`). Remove `SettingsSection.tracker`, the Tracker section and the token handling from `settings_page.dart`. Replace `progressStatusLabel` in `labels.dart` with labels for the `ProgressAuthority` status. Change the Diagnostics progress lines in `evidence_panels.dart` to local progress availability and drop "tracker progress 15m", and change the "Tracker progress may still be unknown" texts in `evidence_panels.dart` and `scanner_sections.dart` to name progress. Verify the 4.1 tests pass, flip their rows green, and check that `grep -rn -i "tracker" lib/ui` returns nothing.

## 5. Settings key and legacy import

- [x] 5.1 Write failing tests: `settings_test.dart` checks that a `settings.json` holding `trackerEnabled` loads and that `toJson` no longer writes it. `legacy_import_test.dart` adds legacy-import: Imported Tracker switch is ignored, and updates the Replace test so it no longer expects the Tracker switch. Verify they fail.
- [x] 5.2 Remove `trackerEnabled` from `Settings` (constructor, `copyWith`, `toJson`; `fromJson` ignores the key), from `ImportPreview` and `import_dialog.dart`, and from the `LegacyImport` mapping, keeping `TrackerProgressEnabled` in the allowed-key list. Verify the 5.1 tests pass, flip the legacy-import rows green, and `mise run analyze` is clean.

## 6. Token clean-up and the runner channel

- [x] 6.1 Write failing tests in `test/data/retired_tokens_test.dart` against a temp directory for the local-data-durability rows: Upgrade with saved tokens, Temporary token file left by a crash, Nothing saved, A file cannot be deleted (an injected delete function that throws, then succeeds on a second call) and Unexpected file in the folder. Verify they fail.
- [x] 6.2 Implement `deleteRetiredTokens` (design D6) in `lib/data/local_paths.dart` or a sibling file. Remove the `credentials` getter and folder creation from `LocalPaths`, and call it unawaited from `AppServices.open`. Update `test/data/local_paths_test.dart`. Verify the 6.1 tests pass and flip their rows green.
- [x] 6.3 Rename the runner channel per design D7: `credential_protector.{h,cpp}` becomes `local_data_channel.{h,cpp}`, `RegisterCredentialProtector` becomes `RegisterLocalDataChannel`, and the channel becomes `blackgrid/local_data` with only `localDataPath`. Update `CMakeLists.txt` and `flutter_window.{h,cpp}`, and point `LocalPaths.resolve` at the new channel. Add a source test that reads both files and checks that the channel names match and that `protect`, `unprotect` and `atomicReplace` are gone. Verify with `mise run test -- <that test>`, then `mise exec -- flutter build windows --release` (builds, does not launch) and `mise run bundle:check -- build/windows/x64/runner/Release`.
- [x] 6.4 Update the scan-recording test: "Recording with local progress recorded" asserts that no case line holds task states, objective counts, station levels or the player level (it replaces "recorded files never contain the saved Tracker token"). Verify with `mise run test -- test/application/scan_coordinator_recording_test.dart` and flip the row green.

## 7. Documentation and main spec Purposes

- [x] 7.1 Update README (the data sources table, privacy paragraph, contracts bullets, mermaid diagram, Progress row, first-run step 4, file table rows, settings sample, the "Never imported" row as needed and the TarkovTracker credit section, which now says the API is no longer used), THIRD_PARTY_NOTICES (remote data: json.tarkov.dev only) and STRATEGY (the token line says it was retired in M9). Verify with `grep -n -i "tarkovtracker\|tracker token" README.md STRATEGY.md THIRD_PARTY_NOTICES.md`, which shows only historical or credit wording.
- [x] 7.2 Rewrite the Purpose of `openspec/specs/progress-authority/spec.md` and drop its "assume the read-only Tracker integration is enabled" preamble. Rewrite the Purpose sentences of `openspec/specs/raid-timers/spec.md` and `openspec/specs/local-progress/spec.md` so they name local progress, not Tracker. Verify with `openspec validate --specs --strict` and `grep -n -i tracker` on those three Purpose sections.

## 8. Integration

- [ ] 8.1 Check that no network path to the progress site is left: `grep -rn -i "tarkovtracker" lib windows test` is empty, and the HTTP client is used only by the catalog, map data and icon clients. Verify by command output.
- [ ] 8.2 For every green row of the test map, find its test (replace each "(locate)" with the real test name, or add the test if none exists) and re-run those files. Then run `mise run analyze`, `mise run test` and `openspec validate retire-tracker-token --strict`. All must pass, and every test map row must be green.

## Workflow follow-up

- The M9 user-verified exit criteria (real log replay matching in-game quest state; checklist and manual entry in play; live FIR scans and `polish-ember-ui`) are judged at the M9 close, after `polish-ember-ui`. This change only switches the consumers. See the proposal's Why.
- Pre-ship review, PR, archive and finish follow the Specwright workflow (`specwright-commit`, `specwright-review`, `specwright-pr`, `specwright-finish`).
