# Tasks

## Test map

Test names follow the repo's `<capability>: <Scenario>` convention. `settings_page_test.dart` and `settings_page_shell_test.dart` are new; `settings_dialog_raid_timers_test.dart` is renamed `settings_page_raid_timers_test.dart` and opens the page instead of the dialog.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| settings-page → Settings opens as a page | Open and go back | test/ui/settings_page_shell_test.dart | settings-page: Open and go back | red |
| settings-page → Settings opens as a page | Inspector hidden while open | test/ui/settings_page_shell_test.dart | settings-page: Inspector hidden while open | red |
| settings-page → Settings opens as a page | Switch area from Settings | test/ui/settings_page_shell_test.dart | settings-page: Switch area from Settings | red |
| settings-page → Settings opens as a page | Item search from Settings | test/ui/settings_page_shell_test.dart | settings-page: Item search from Settings | red |
| settings-page → Settings opens as a page | Escape with an unsaved invalid edit | test/ui/settings_page_shell_test.dart | settings-page: Escape with an unsaved invalid edit | red |
| settings-page → Settings opens as a page | Map keys while Settings is open | test/ui/settings_page_shell_test.dart | settings-page: Map keys while Settings is open | red |
| settings-page → Settings opens as a page | Escape with a valid edit | test/ui/settings_page_shell_test.dart | settings-page: Escape with a valid edit | red |
| settings-page → Settings opens as a page | Scan while Settings is open | test/ui/settings_page_shell_test.dart | settings-page: Scan while Settings is open | red |
| settings-page → Settings opens as a page | Settings action while open | test/ui/settings_page_shell_test.dart | settings-page: Settings action while open | red |
| settings-page → Settings sections and their order | Sidebar order | test/ui/settings_page_test.dart | settings-page: Sidebar order | red |
| settings-page → Settings sections and their order | Jump to a section | test/ui/settings_page_test.dart | settings-page: Jump to a section | red |
| settings-page → Settings sections and their order | Jump to Diagnostics | test/ui/settings_page_test.dart | settings-page: Jump to Diagnostics | red |
| settings-page → Settings opens at a requested section | Status bar Tracker | test/ui/settings_page_shell_test.dart | settings-page: Status bar Tracker | red |
| settings-page → Settings opens at a requested section | Already open | test/ui/settings_page_shell_test.dart | settings-page: Already open | red |
| settings-page → Diagnostics starts collapsed each time | Reopen | test/ui/settings_page_shell_test.dart | settings-page: Reopen | red |
| settings-page → Diagnostics starts collapsed each time | Open at a section | test/ui/settings_page_shell_test.dart | settings-page: Open at a section | red |
| settings-page → Settings rows | Toggle by row | test/ui/settings_page_test.dart | settings-page: Toggle by row | red |
| settings-page → Settings rows | Wide window | test/ui/settings_page_test.dart | settings-page: Wide window | red |
| settings-page → Settings rows | Setting disabled while saving | test/ui/settings_page_test.dart | settings-page: Setting disabled while saving | red |
| settings-page → General, Live scan and Map sections | Game mode | test/ui/settings_page_test.dart | settings-page: Game mode | red |
| settings-page → General, Live scan and Map sections | Scan key refused | test/ui/settings_page_test.dart | settings-page: Scan key refused | red |
| settings-page → General, Live scan and Map sections | Live scan unavailable | test/ui/settings_page_test.dart | settings-page: Live scan unavailable | red |
| settings-page → Item and map data section | Refresh map data | test/ui/settings_page_test.dart | settings-page: Refresh map data | red |
| settings-page → Item and map data section | Unknown mode | test/ui/settings_page_test.dart | settings-page: Unknown mode | red |
| settings-page → Item and map data section | No map data available | test/ui/settings_page_test.dart | settings-page: No map data available | red |
| settings-page → Item and map data section | Map data refresh fails | test/ui/settings_page_test.dart | settings-page: Map data refresh fails | red |
| settings-page → Tracker progress section | Save token | test/ui/settings_page_test.dart | settings-page: Save token | red |
| settings-page → Tracker progress section | Token action fails | test/ui/settings_page_test.dart | settings-page: Token action fails | red |
| settings-page → Tracker progress section | No mode | test/ui/settings_page_test.dart | settings-page: No mode | red |
| settings-page → Game files section | Save a folder on Enter | test/ui/settings_page_test.dart | settings-page: Save a folder on Enter | red |
| settings-page → Game files section | Save on leaving | test/ui/settings_page_test.dart | settings-page: Save on leaving | red |
| settings-page → Game files section | Save fails | test/ui/settings_page_test.dart | settings-page: Save fails | red |
| settings-page → Changes save as they are made | Switch saves at once | test/ui/settings_page_test.dart | settings-page: Switch saves at once | red |
| settings-page → Changes save as they are made | Settings could not be read | test/ui/settings_page_test.dart | settings-page: Settings could not be read | red |
| settings-page → Every setting stays reachable | All controls present | test/ui/settings_page_test.dart | settings-page: All controls present | red |
| settings-page → Every setting stays reachable | Disabled rule kept | test/ui/settings_page_test.dart | settings-page: Disabled rule kept | red |
| workspace-shell → Status actions lead to their controls | Settings targets | test/ui/shell_test.dart | workspace-shell: Settings targets | red |
| workspace-shell → Status actions lead to their controls | Settings target while the page is open | test/ui/shell_test.dart | workspace-shell: Settings target while the page is open | red |
| workspace-shell → Status actions lead to their controls | Failed live scan save | test/ui/shell_test.dart | workspace-shell: Failed live scan save | green |
| workspace-shell → Status actions lead to their controls | Status bar presentation and binding | test/ui/shell_test.dart | workspace-shell: Status bar presentation and binding | green |
| raid-timers → Timer settings live on the Settings page | Valid run-through length | test/ui/settings_page_raid_timers_test.dart | valid run-through length is saved | green |
| raid-timers → Timer settings live on the Settings page | Invalid run-through length | test/ui/settings_page_raid_timers_test.dart | invalid run-through lengths are refused | green |
| raid-timers → Timer settings live on the Settings page | Fence reputation out of range | test/ui/settings_page_raid_timers_test.dart | out-of-range reputation is refused | green |
| raid-timers → Timer settings live on the Settings page | Reputation for the detected mode | test/ui/settings_page_raid_timers_test.dart | reputation edits the active mode's value | green |
| raid-timers → Timer settings live on the Settings page | No mode known | test/ui/settings_page_raid_timers_test.dart | reputation field disabled without a mode | green |
| release-versioning → The running app reports its version | Release build shows its version | test/ui/settings_page_test.dart | release-versioning: Release build shows its version | red |
| release-versioning → The running app reports its version | Development build | test/ui/settings_page_test.dart | release-versioning: Development build | red |
| app-icon → The app header and the startup screen show the application icon | Header shows the logo | test/ui/shell_test.dart | header shows the 32x32 app logo and no hub icon | green |
| app-icon → The app header and the startup screen show the application icon | Startup screen shows the logo | test/ui/app_test.dart | app-icon: Startup screen shows the logo | red |
| app-icon → The app header and the startup screen show the application icon | Logo is not announced | test/ui/app_logo_test.dart | the logo adds no semantics node | green |
| app-icon → The app header and the startup screen show the application icon | Vector fails to load | test/ui/app_logo_test.dart | a failed load leaves an empty box of the same size with no error | green |
| settings-diagnostics → Diagnostics shows map data detail | Fallback map data | test/ui/settings_diagnostics_test.dart | settings-diagnostics: Fallback map data | red |
| settings-diagnostics → Diagnostics shows map data detail | Never checked | test/ui/settings_diagnostics_test.dart | settings-diagnostics: Never checked | red |
| legacy-import → The import preview keeps technical detail under Details | Preview read | test/ui/import_dialog_test.dart | legacy-import: Preview read | red |
| legacy-import → The import preview keeps technical detail under Details | Details opened | test/ui/import_dialog_test.dart | legacy-import: Details opened | red |
| legacy-import → The import preview keeps technical detail under Details | New preview resets Details | test/ui/import_dialog_test.dart | legacy-import: New preview resets Details | red |
| legacy-import → The import preview keeps technical detail under Details | Already imported | test/ui/import_dialog_test.dart | legacy-import: Already imported | red |
| interface-theme → Dialogs, sheets and the startup screen in Ember | Stats dialog | test/ui/ember_surfaces_test.dart | interface-theme: Stats dialog | red |
| interface-theme → Dialogs, sheets and the startup screen in Ember | Confirm dialog | test/ui/ember_surfaces_test.dart | interface-theme: Confirm dialog | red |
| interface-theme → Dialogs, sheets and the startup screen in Ember | Map help closes | test/ui/map_help_test.dart | interface-theme: Map help closes | red |
| interface-theme → Dialogs, sheets and the startup screen in Ember | Startup error | test/ui/app_test.dart | interface-theme: Startup error | red |

## 1. Shared Ember building blocks

Skills: `dart-write-documentation`, `flutter-add-widget-test`, `dart-run-static-analysis`.

- [ ] 1.1 Move `MarkerToggleSwitch` (`lib/ui/marker_preferences.dart:158`) to `lib/ui/ember/ember_toggle_switch.dart` as `EmberToggleSwitch` and update the Map inspector's import (D7); verify `flutter test test/ui/marker_preferences_test.dart` passes unchanged.
- [ ] 1.2 Write failing widget tests for a `SettingsRow` (name, one-line explanation, trailing control; a switch row toggles on a press anywhere in the row and exposes `toggled` semantics; disabled rows ignore presses), then build `SettingsRow` in `lib/ui/settings/settings_row.dart` (D7); verify the new tests pass.
- [ ] 1.3 Move `_CommitField` out of `settings_dialog.dart` into `lib/ui/settings/commit_field.dart` with a `SettingsFlushScope` that lets a parent ask every field with pending text to call `onCommit` before unmount (D3, D5). Write failing tests first: a flush commits pending valid text, a flush of refused text keeps the saved value, a flush with no edit commits nothing. Verify they pass.
- [ ] 1.4 Write a failing test, then add `BrandLockup` (logo, `BLACKGRID`, `TRACK. PLAN. SURVIVE.`; top bar and startup sizes) in `lib/ui/brand_lockup.dart`, and use it in the shell header in place of `shell.dart:452-459` (D9); verify `header shows the 32x32 app logo and no hub icon` and `the logo adds no semantics node` still pass.
- [ ] 1.5 Add `bottomSheetTheme` and dialog title and actions styles to `blackgridTheme` (`lib/ui/ember/ember_theme.dart`) from Ember tokens only (D8, ADR-0037); verify `test/ui/ember_theme_test.dart` and `test/ui/theme_source_test.dart` pass.

## 2. The Settings page and its sections

Skills: `dart-use-pattern-matching`, `dart-write-documentation`, `flutter-add-widget-test`, `dart-run-static-analysis`.

- [ ] 2.1 Write the failing `settings_page_test.dart` tests for the sections, rows, saving and reachability rows of the test map (Sidebar order through Disabled rule kept, and both release-versioning rows), pumping the page alone with fake services. Verify each fails for the missing page, not for setup.
- [ ] 2.2 Build `SettingsPage` (`lib/ui/settings/settings_page.dart`): sidebar with the eight sections, a column at most 720px wide with Literata Display and Title roles, `SettingsSection` with the eight values, `GlobalKey`/`FocusNode` targeting with a request number (D4), and Diagnostics collapsed on each mount. Fill General (theme, game mode, version), Live scan (rows from `LiveScanPanel`'s controls and status lines, keys kept), Tracker progress, Raid timers and Map with `SettingsRow` and `EmberToggleSwitch`. Verify the matching rows turn green.
- [ ] 2.3 Game files: two commit fields that each call `setMapInputs` with only their folder, plus Follow logs; remove "Save map files" (S2, D5). Verify Save a folder on Enter, Save on leaving and Save fails turn green.
- [ ] 2.4 Split `LiveMapStatus` (D6): an Item and map data section with both refresh actions and one plain line each, Refresh map data disabled while refreshing, with no mode, or with no map data; add the map data part to `DataSourceDiagnostics` (`lib/ui/evidence_panels.dart:363`). Write the two settings-diagnostics tests first. Verify Refresh map data, Unknown mode, No map data available, Map data refresh fails, Fallback map data and Never checked turn green, and port `test/ui/live_map_settings_test.dart` to the new rows.
- [ ] 2.5 Rename `settings_dialog_raid_timers_test.dart` to `settings_page_raid_timers_test.dart`, point it at the page, and re-run it; the five raid-timers rows stay green.

## 3. Shell integration

Skills: `flutter-add-widget-test`, `dart-run-static-analysis`.

- [ ] 3.1 Write the failing `settings_page_shell_test.dart` tests (Open and go back through Open at a section) and the two red workspace-shell rows in `shell_test.dart`, using the existing shell test fakes. Verify each fails for the missing behaviour.
- [ ] 3.2 In `lib/ui/shell.dart`, add the Settings view state (D1): `_openSettings({section})` with the back area and inspector state, page shown in place of the strip and main column, areas and inspector under `Offstage` plus `ExcludeFocus` while open, focus moved into the page on open and back to the root `Focus` on close, inspector toggle disabled while open (D2). Route the top bar's Settings and the status bar's Item data and Tracker items through it.
- [ ] 3.3 One close method used by Back, Escape (D3, after any open menu), choosing an area and an item pick: flush through `SettingsFlushScope`, then clear the view state. Add `onPicked` to `TopItemSearch` (`lib/ui/top_item_search.dart:97`) and close Settings only from it. Verify all `settings_page_shell_test.dart` rows and both workspace-shell red rows turn green, and `workspace-shell: Failed live scan save` and `workspace-shell: Status bar presentation and binding` still pass.
- [ ] 3.4 Delete `lib/ui/settings_dialog.dart` and `showSettings` (S6); move what `settings_dialog_test.dart` and `settings_dialog_theme_test.dart` still cover onto the page (rename to `settings_page_*`), keeping their live scan and theme assertions. Verify `rg "SettingsDialog|showSettings" lib test` finds nothing and the suite passes.

## 4. Dialogs, sheets and the startup screen

Skills: `flutter-add-widget-test`, `dart-run-static-analysis`.

- [ ] 4.1 Write failing tests for Stats dialog and Confirm dialog in `ember_surfaces_test.dart` (both rooms), then restyle `lib/ui/stats_dialog.dart` (dense rows, Literata title, Close primary, Clear stats quiet) and the remove-pin and clear-stats confirms (`map_workspace.dart:242`, `map_inspector.dart:228`, `stats_dialog.dart:129`). Verify both rows turn green and `test/ui/stats_dialog_test.dart` passes.
- [ ] 4.2 Write the four failing legacy-import tests, then restyle `lib/ui/import_dialog.dart` with the collapsed Details toggle reset on each preview read (S3, D10) and an Ember switch row for Replace. Verify the rows turn green and the existing `import_dialog_test.dart` cases pass.
- [ ] 4.3 Write the failing Map help closes test, then restyle Map help, the marker browser sheet (`map_workspace.dart:299`) and the pin editor (`lib/ui/pin_editor.dart`) with Ember rows and buttons; content and keys unchanged. Verify the row turns green and `test/ui/map_help_test.dart` and `test/ui/map_workspace_controls_test.dart` pass.
- [ ] 4.4 Write the failing app-icon Startup screen shows the logo and interface-theme Startup error tests, then rebuild the startup screen in `lib/ui/app.dart` with `BrandLockup` on the Canvas, Ember loading indicator and Retry; messages word for word. Verify both rows turn green and the two existing `app_test.dart` cases pass.

## 5. Integration

- [ ] 5.1 Run `dart format lib test`, `mise run analyze` and `mise run test`; all pass, and every test map row reads green.
- [ ] 5.2 Re-check the proposal's `## Release Notes` against what shipped and run `mise run release-notes -- --check openspec/changes/restyle-dialogs/proposal.md`; it exits 0.

## Workflow follow-up

- The user-verified M8.5 criterion (verdict, map and dialogs look right on a second monitor, both rooms) is judged at the M8.5 close, which follows this change.
