# Tasks

Every task group follows the "Dart and Flutter code" section of AGENTS.md. Before writing Dart, load `dart-use-pattern-matching`, `dart-write-documentation`, `dart-add-unit-test` and `dart-run-static-analysis`; also load `flutter-add-widget-test` for group 4. Fakes are hand-written and injected through constructors; no arbitrary sleeps (use completers, fake clocks and injected ID generators). Ordering, derivation and lock rules are proved in application tests; widget tests only check what the section shows and that clicks reach the controller.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| quest-checklist → Quests lists the mode's started tasks | Current map's quests first | test/application/quest_checklist_test.dart | started tasks with a quest marker on the map come first, then by trader and name | red |
| quest-checklist → Quests lists the mode's started tasks | No quest markers loaded | test/application/quest_checklist_test.dart | without quest markers every started task is one group and nothing is on this map | red |
| quest-checklist → Quests lists the mode's started tasks | Finished and failed tasks are not listed | test/application/quest_checklist_test.dart | finished and failed tasks leave the list on the next read | red |
| quest-checklist → Quests lists the mode's started tasks | No started task | test/ui/map_quests_section_test.dart | no started quest shows how to start one | red |
| quest-checklist → Quests lists the mode's started tasks | Unknown task ID | test/application/quest_checklist_test.dart | a started ID missing from the catalog is not listed | red |
| quest-checklist → Objectives show their progress | Counter objective | test/application/quest_checklist_test.dart | a counter objective shows its count and target and is not done below it | red |
| quest-checklist → Objectives show their progress | Count reached | test/application/quest_checklist_test.dart | a counter objective at its target reads done | red |
| quest-checklist → Objectives show their progress | Missing description | test/ui/map_quests_section_test.dart | an objective without a description shows its type and keeps its controls | red |
| quest-checklist → Ticking records objective completion | Tick a single objective | test/application/manual_progress_controller_test.dart | ticking a single objective records completion true | red |
| quest-checklist → Ticking records objective completion | Counter reaches its target | test/application/manual_progress_controller_test.dart | plus at target minus one records the target and disables plus | red |
| quest-checklist → Ticking records objective completion | Tick a counter objective | test/application/manual_progress_controller_test.dart | ticking a counter objective records the target count | red |
| quest-checklist → Ticking records objective completion | Counter bounds | test/application/manual_progress_controller_test.dart | minus at zero is disabled and records nothing | red |
| quest-checklist → Ticks never finish a task | Every objective done | test/application/manual_progress_controller_test.dart | ticking the last objective records no task-state event | red |
| quest-checklist → Ticks never finish a task | Turn-in from the logs | test/application/quest_checklist_test.dart | a task finished from the logs leaves the list and keeps its objective values | red |
| quest-checklist → Objective progress uses the manual-entry rules | Undo a counter step | test/application/manual_progress_controller_test.dart | undo after a plus step restores the count and offers redo | red |
| quest-checklist → Objective progress uses the manual-entry rules | Storage failure | test/application/manual_progress_controller_test.dart | an objective storage failure keeps the previous value and shows the reason | red |
| quest-checklist → Objective progress uses the manual-entry rules | Entry during replay | test/application/local_progress_access_test.dart | an objective entry queued during replay is recorded after it | red |
| quest-checklist → Shared objectives share one value | Tick a shared objective | test/application/quest_checklist_test.dart | a shared objective reads the same value under each task and names the others | red |
| quest-checklist → Shared objectives share one value | Shared with an unlisted task | test/application/quest_checklist_test.dart | a shared objective names a task that is not started | red |
| quest-checklist → Quests follows the effective mode and fresh values | Mode switch | test/application/manual_progress_controller_test.dart | a mode switch re-reads quest progress for the new mode | red |
| quest-checklist → Quests follows the effective mode and fresh values | Catalog unavailable | test/ui/map_quests_section_test.dart | without a task catalog Quests shows the reason and no controls | red |
| quest-checklist → Quests follows the effective mode and fresh values | Unavailable wipe | test/ui/map_quests_section_test.dart | an unavailable wipe shows its reason and no controls | red |
| quest-checklist → Quest markers follow active quests | Ticked objective leaves the map | test/application/map_controller_test.dart | quest filter hides a done objective and keeps the task's open ones | red |
| quest-checklist → Quest markers follow active quests | Not-started task hidden | test/application/map_controller_test.dart | quest filter hides markers of tasks that are not started | red |
| quest-checklist → Quest markers follow active quests | Nothing started | test/application/map_controller_test.dart | a null quest filter keeps every quest marker eligible | red |
| quest-checklist → Quest markers follow active quests | Show all quests | test/ui/map_workspace_controls_test.dart | Show all quests pushes a null filter and the name and trader filters still apply | red |
| quest-checklist → Advice stays on the Tracker token | Ticking does not change advice | test/application/app_services_test.dart | an objective tick does not change advice progress | red |
| quest-checklist → Advice stays on the Tracker token | Token removed | test/application/app_services_test.dart | quest progress and the marker filter work without a token | red |
| workspace-shell → Inspector preserves the workspace | Docked details | test/ui/shell_test.dart | workspace-shell: Docked details | green |
| workspace-shell → Inspector preserves the workspace | Resize with open details | test/ui/shell_test.dart | workspace-shell: Resize with open details | green |
| workspace-shell → Inspector preserves the workspace | Scanner history leads the inspector | test/ui/shell_test.dart | workspace-shell: Scanner history leads the inspector | green |
| workspace-shell → Inspector preserves the workspace | Initial inspector state follows window width | test/ui/shell_test.dart | workspace-shell: Initial inspector state follows window width | green |
| workspace-shell → Inspector preserves the workspace | Map inspector holds working lists | test/ui/shell_test.dart | workspace-shell: Map inspector holds working lists | red |
| workspace-shell → Inspector preserves the workspace | Quests without quest data | test/ui/shell_test.dart | workspace-shell: Quests without quest data | red |
| marker-preferences → Bulk, search and quest controls keep working | Hide all then Show all | test/ui/marker_preferences_test.dart | marker-preferences: Hide all then Show all | red |
| marker-preferences → Bulk, search and quest controls keep working | Show all keeps other maps' choices | test/ui/marker_preferences_test.dart | marker-preferences: Show all keeps other maps' choices | green |
| marker-preferences → Bulk, search and quest controls keep working | Bulk action with an unsaveable category | test/ui/marker_preferences_test.dart | marker-preferences: Bulk action with an unsaveable category | green |
| marker-preferences → Bulk, search and quest controls keep working | Search dims without hiding | test/ui/marker_preferences_test.dart | marker-preferences: Search dims without hiding | green |
| marker-preferences → Bulk, search and quest controls keep working | Quest filter keeps tiles | test/ui/marker_preferences_test.dart | marker-preferences: Quest filter keeps tiles | green |
| marker-preferences → Bulk, search and quest controls keep working | Active trader absent from the map | test/ui/marker_preferences_test.dart | marker-preferences: Active trader absent from the map | green |
| marker-preferences → Show all quests switch | Turn the switch on | test/ui/marker_preferences_test.dart | marker-preferences: Show all quests turns on without changing rows | red |
| marker-preferences → Show all quests switch | Not saved without Save marker filters | test/application/settings_load_test.dart | showAllQuests resets on load when Save marker filters is off | red |
| marker-preferences → Show all quests switch | Saved with marker filters | test/application/settings_load_test.dart | showAllQuests is restored when Save marker filters is on | red |
| marker-preferences → Show all quests switch | Hide all keeps the switch | test/ui/marker_preferences_test.dart | marker-preferences: Hide all and Show all keep Show all quests | red |
| marker-preferences → Show all quests switch | Map without quest markers | test/ui/marker_preferences_test.dart | marker-preferences: no switch on a map without quest markers | red |

## 1. Objective entries and quest progress in ManualProgressController

- [ ] 1.1 Write failing tests in `test/application/manual_progress_controller_test.dart` for the objective rows of the test map (tick, counter target, tick counter, bounds, no task event, undo a step, storage failure, mode switch) and for the lock from design.md Flow & State Gaps: with the post-append read held on a completer a second + is ignored, and after it lands at 3, + records 4 (two + clicks from 2 end at 4); a failed append releases the lock at once. Add "an objective entry queued during replay is recorded after it" to `test/application/local_progress_access_test.dart`. Verify each fails for the missing API, not a harness error.
- [ ] 1.2 Add `setObjectiveComplete`, `stepObjectiveCount` and `setObjectiveCount` to `ManualProgressController` (design D1, D3): counters are objectives whose catalog `count` is a whole number over 1 and write only `ProgressField.count`, bounded 0..target; others write only `ProgressField.complete`; objective registers stay pending until a read started after the append has landed. Document the public API. Verify the 1.1 tests pass and flip their rows green.
- [ ] 1.3 Write failing tests in `test/application/quest_checklist_test.dart` for the derivation rows (ordering with and without quest markers, finished/failed and unknown IDs, counter and done reading, turn-in keeps values, shared objectives naming other tasks), then implement a pure `QuestChecklist` builder (design D4, D5) from the progress catalog, the winners and the current map's quest-marker task and objective IDs, plus the `QuestMarkerFilter` value (started task IDs, done objective IDs; `null` when progress is not loaded, unavailable or nothing is started; without the mode's catalog an objective is done only by recorded completion). Verify they pass and flip the rows green.

## 2. Quest-marker filter on the map

- [ ] 2.1 Write failing tests in `test/application/map_controller_test.dart` for the three marker-filter rows (done objective hidden, not-started task hidden, null filter keeps all) and for D7 (a quest marker without task or objective ID stays eligible), plus a `test/maps/quest_marker_identity_test.dart` fixture test that quest-objective and quest-item markers from a small frozen tasks body carry `details.quest.id` and `details.id` equal to the progress catalog's task and objective IDs parsed from the same body. Verify they fail for the missing filter.
- [ ] 2.2 Add `questTaskId` to `MapMarkerMetadata` (from `details.quest.id`) and `MapController.setQuestProgressFilter(QuestMarkerFilter?)`, applied in `_markerEligible` beside the category, quest name and trader checks (design D2, D7). Verify 2.1 passes, the existing map controller and map marker query tests still pass, and flip the rows green.

## 3. showAllQuests setting

- [ ] 3.1 Write failing tests: `test/domain/settings_test.dart` (`showAllQuests` round-trips, defaults to false when absent, and an older settings JSON without it decodes) and `test/application/settings_load_test.dart` (the two persistence rows). Verify they fail for the missing field.
- [ ] 3.2 Add `AppSettings.showAllQuests` (design D6): `toJson` writes it, `fromJson` reads `as bool? ?? false`, `SettingsController.load` resets it to false when `saveMarkerFilters` is off, and a `setShowAllQuests` setter saves it. Verify 3.1 passes and flip the rows green.

## 4. Quests section, Markers switch and wiring

- [ ] 4.1 Write failing widget tests: `test/ui/map_quests_section_test.dart` (empty state, missing description, catalog unavailable, unavailable wipe, and that tick, +, - and Undo reach the controller), `test/ui/shell_test.dart` (updated "Map inspector holds working lists" and new "Quests without quest data"), `test/ui/marker_preferences_test.dart` (updated "Hide all then Show all" and the four switch rows; the switch ignores clicks while settings save, like the rows) and `test/ui/map_workspace_controls_test.dart` (Show all quests pushes a null filter; name and trader filters still apply). Verify they fail for the missing UI.
- [ ] 4.2 Build the Quests inspector section after Pins in `lib/ui/map_inspector.dart` using Ember theme roles only (ADR-0037) and no amber band for done states on the map (ADR-0039): started tasks with their objectives, optional marks, "On this map" marks, counts, tick, +/- and Undo/Redo with pending and failure states, shared-objective notes and the empty and reason states. Add the Show all quests switch to the Quests group of `lib/ui/marker_preferences.dart`, shown only when the map has quest markers. Have `MapWorkspace` attach `ManualProgressController` while mounted and push `QuestMarkerFilter` (or `null` when Show all quests is on) to `MapController`; note in its doc comment that the Map stays mounted, so the projection is read for the app session, one read in flight and changes coalesced. Verify 4.1 passes, `test/ui/theme_source_test.dart` passes, and flip the rows green.
- [ ] 4.3 Write and pass the two `test/application/app_services_test.dart` rows (advice unchanged by an objective tick; quest progress and the marker filter work without a Tracker token). Flip the rows green.

## 5. Verification

- [ ] 5.1 Re-run the green carried rows (`test/ui/shell_test.dart`, `test/ui/marker_preferences_test.dart`) and the full `mise run test`; all pass. Run `mise run analyze` with no issues and `dart format` with no changes.
- [ ] 5.2 Run `mise run release-notes -- --check openspec/changes/add-quest-checklist/proposal.md`; it exits 0 and the Release Notes still describe what ships.
- [ ] 5.3 [user] With a built app and the game running, the owner checks in play: Quests lists the started quests of the current mode with this map's first; ticking an objective and moving a counter to its target removes its markers from the map; Undo brings them back; Show all quests shows every quest; and a quest turned in leaves the list. This is the checklist half of M9's "the checklist and manual progress entry work in play"; the whole criterion is judged again at the milestone close.
