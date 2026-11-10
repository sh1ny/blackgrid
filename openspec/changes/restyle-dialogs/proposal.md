# Proposal

## Why

Settings is still the pre-Ember dialog: a 560px scroll of Material list tiles with Appearance, Map data, Map files, Raid timers, Live scan, Tracker and Diagnostics in one column. DESIGN.md X12 replaces it with a page that has seven sections and a sidebar, because a dialog with that much in it scrolls inside a scroll. Stats, Import, Map help, the marker browser sheet, the pin and confirm dialogs, and the startup screen still use the old Material look. The startup screen shows "BLACKGRID" without its tagline, which is not the brand lockup X9 approves.

This change serves milestone **M8.5 - Ember interface** (change 6, the last one). It closes the agent-verified exit criterion "Every setting that today sits in a Map or Scanner rail or the Settings dialog is reachable on the Settings page (DESIGN.md X12), and nothing is lost ... Proved by widget tests." It also finishes the criteria that both rooms are built from the DESIGN.md tokens and that Map and Scanner show no debug information: the map data status lines leave the visible settings for Diagnostics. The user-verified criterion ("In both rooms, on a second monitor and alt-tabbed full window, the verdict reads at a glance, and the map and dialogs look right") covers the whole redesign, so it is judged at the milestone close that follows this change, not by a task here.

## What Changes

- **Settings becomes a page** (X12). It opens in place of the answer strip and the main column; the top bar and the status bar stay. A sidebar lists the sections and a "Back to Map" or "Back to Scanner" button. The page is one scrolling column, at most 720px wide, with the title in Literata Display and section titles in Literata Title. Each setting is a row with its name, a one-line explanation and its control on the right. The Settings dialog is removed.
- **Sections:** General (theme, game mode, app version), Live scan, Item and map data, Tracker progress, Game files, Raid timers, Map, then the collapsed Diagnostics section. Every control in today's dialog keeps working. On/off settings use the Ember toggle switch (X13).
- **Saving:** every setting saves when it is changed. The game log and screenshot folder fields save on Enter or when focus leaves them, like the run-through and Fence reputation fields. A save that fails keeps the typed text and says why. The "Save map files" button goes. The Tracker token keeps its Save and Remove buttons.
- **Map data** moves into the "Item and map data" section (renamed from Item data): Refresh map data sits beside Refresh item data, each with one plain freshness line. The selected mode, map data mode, source and last check time move to Diagnostics' Data sources part.
- **Status bar targets:** the Item data and Tracker status items open the Settings page at their section, and so do any other links that opened the dialog at a section.
- **Stats and Import stay dialogs**, restyled in Ember: Panel surfaces, Literata titles, dense rows, one primary action and quiet secondary actions. The Import preview shows its summary, settings, pins, what was left out and the Replace switch. The file fingerprint and the per-record rows move under a collapsed "Details" toggle in the dialog.
- **Map help, the marker browser sheet, the pin editor and the confirm dialogs** (remove pin, clear stats) are restyled in Ember. Their content and keys do not change.
- **Startup screen:** the full brand lockup (hex logo, "BLACKGRID", "TRACK. PLAN. SURVIVE.") on the Canvas, in the Ember room the system asks for, with the loading indicator and storage errors in Ember styling. The messages and the Retry action stay word for word.

## Capabilities

### New Capabilities
- `settings-page`: the Settings page: how it opens and closes, its sections and their order, the rows and controls each section holds, opening at a section, saving as changes are made, and that every setting from the old dialog stays reachable.

### Modified Capabilities
- `workspace-shell`: the status bar's Item data and Tracker items open the Settings page at their section; the clause that kept displaced configuration in the Settings dialog is removed.
- `raid-timers`: the timer settings live in the Raid timers section of the Settings page, not the Settings dialog. Values, ranges and refusal messages are unchanged.
- `release-versioning`: the app version shows in the General section of the Settings page.
- `app-icon`: the startup screen shows the full brand lockup, with the tagline under the wordmark.
- `settings-diagnostics`: Data sources also shows the map data detail (selected mode, map data mode, source and last check time) that left the visible settings.
- `legacy-import`: the import preview keeps the file fingerprint and the per-record rows under a collapsed Details toggle.
- `interface-theme`: dialogs, bottom sheets and the startup screen take Ember's surfaces, type roles and button variants, with one primary action per dialog.

## Impact

- Code: `lib/ui/settings_dialog.dart` (becomes the Settings page), `lib/ui/shell.dart` (shows the page in place of the strip and main column, Back, status bar targets), `lib/ui/stats_dialog.dart`, `lib/ui/import_dialog.dart`, `lib/ui/map_workspace.dart` (Map help, marker browser sheet, remove-pin confirm), `lib/ui/map_inspector.dart` (remove-pin confirm), `lib/ui/pin_editor.dart`, `lib/ui/app.dart` (startup screen), `lib/ui/live_scan_panel.dart` and `lib/ui/live_map_status.dart` (split into settings rows and diagnostics lines), `lib/ui/ember/ember_theme.dart` (dialog, sheet, switch and segmented themes as needed).
- Tests: Settings widget tests rewritten for the page; shell tests for opening, Back and section targets; Stats, Import, Map help and startup screen tests updated; a test that every control in the old dialog has a row on the page.
- No data, model, service or stored setting changes. Saved settings load as before.
- Out of scope: new settings; filling the Scanner main column (X10); any change to the Map or Scanner work screens beyond how Settings opens.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Where map data goes on the Settings page

- **Choice:** Rename the Item data section to "Item and map data", with Refresh map data beside Refresh item data and one plain freshness line each. The map data detail lines move to Diagnostics › Data sources.
- **Rejected:** Map section (splits the two refresh actions the status bar and help treat as one kind of data); Diagnostics only (hides an action the player may need when map data is stale).
- **Reversal cost:** low
- **Important:** yes, it changes settings users see and fills a gap in DESIGN.md X12.
- **Chosen by:** user

### S2: How the folder fields save

- **Choice:** The game log and screenshot folder fields save on Enter or when focus leaves them. A failed save keeps the typed text and shows the reason. The "Save map files" button is removed.
- **Rejected:** Keep a "Save folders" button as a second exception to X12's save-as-you-go rule.
- **Reversal cost:** low
- **Important:** yes, it changes behaviour users see.
- **Chosen by:** user

### S3: Technical detail in the Import preview

- **Choice:** The file fingerprint and the per-record rows (kind, order, key, disposition, reason) sit under a collapsed "Details" toggle inside the Import dialog. The summary, settings, pins, what was left out and the Replace switch stay visible.
- **Rejected:** Keep every line visible and only restyle it.
- **Reversal cost:** low
- **Important:** yes, it changes what users see.
- **Chosen by:** user

### S4: Which dialogs this change restyles

- **Choice:** Every dialog and sheet the app opens: Stats, Import, Map help, the marker browser sheet, the pin editor and the remove-pin and clear-stats confirms, plus the startup screen.
- **Rejected:** Only those named in the roadmap (Stats, Import, Map help, sheets). That would leave the pin editor and confirms in the old look, against the exit criterion that both rooms come from the DESIGN.md tokens.
- **Reversal cost:** low
- **Important:** no; it follows the milestone's exit criteria and changes no behaviour.
- **Chosen by:** agent

### S5: Where the app version shows

- **Choice:** A read-only row in the General section of the Settings page.
- **Rejected:** The sidebar foot, which X12 does not describe.
- **Reversal cost:** low
- **Important:** no; it keeps today's information in the matching section.
- **Chosen by:** agent

### S6: The Settings dialog is removed

- **Choice:** The Settings page replaces the dialog everywhere. Nothing opens the dialog afterwards.
- **Rejected:** Keep the dialog as a fallback for narrow windows. That would leave two places for every setting to keep in step.
- **Reversal cost:** medium
- **Important:** no; DESIGN.md X12 and owner decision C4 already settle it.
- **Chosen by:** agent

## Release Notes

Settings is now a full page with a section list, in the new Ember look. Stats, Import, Map help, the pin editor and the startup screen are restyled to match.

### Changed
- Settings opens as a page with sections for General, Live scan, Item and map data, Tracker progress, Game files, Raid timers, Map and Diagnostics. Changes save as you make them; the folder fields save on Enter or when you leave them.
- Stats, Import, Map help, the marker list sheet, the pin editor and the confirm dialogs use the Ember look. Import's file fingerprint and per-record lines sit under a Details toggle.
- The startup screen shows the full Blackgrid logo with its tagline.
