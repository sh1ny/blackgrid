# Proposal

## Why

The local progress tracker (M9, local progress tracker) now records task events from the game logs, but the logs never say the player's level, faction, edition, trader loyalty or built hideout stations, and they miss tasks finished before the log folders Blackgrid can read. Without a way to enter these by hand the availability rules leave level, loyalty, faction and edition gates unchecked, and a task the logs missed stays wrong. This change is M9's change 6, `add-manual-progress`.

It advances two M9 exit criteria:

- "Every progress change is stored as an event ... game-log events beat older manual edits": every manual entry and override is written as a manual event in the mode's active wipe, so the store's existing newest-wins ordering decides between it and log evidence. Proved by service tests.
- "The checklist and manual progress entry work in play" (user-verified): manual entry is checked by a `[user]` task in tasks.md once the app is built; the checklist half belongs to `add-quest-checklist` and the whole criterion is judged again at the milestone close.

## What Changes

- A new **Your progress** part of the Settings page's Local progress section, for the app's effective game mode (the game's detected session mode, else the header choice), where the player sets:
  - their level, faction (BEAR or USEC) and game edition (the editions the availability rules' edition table knows);
  - the loyalty level of each trader that has more than one loyalty level, bounded by that trader's real levels;
  - the built level of each hideout station, from not built up to the station's highest level;
  - the state of any task of the mode (not started, started, failed or finished), found by searching task names, with each task showing its current state and whether it came from the game logs or by hand.
- Every entry is appended as one manual event in the mode's active wipe. A value can be cleared back to unknown. The last manual change of a value can be undone, and an undo can be redone, using the store's guarded undo. Redo alone has a timestamp floor after the verified undo winner; ordinary manual entries retain wall-clock timestamps and existing log precedence.
- When the mode has no active wipe, the first entry creates one, as the log path does, starting on the earlier of today and the current game-log session folder's date, then records the entry.
- The task catalog keeps each trader's loyalty level numbers from tarkov.dev, so the loyalty picker lists real levels only.
- Nothing that reads progress changes: keep/sell advice, raid timers and task state still come from the Tracker token until `retire-tracker-token`.

**Not in this change:** objective counts and the quest checklist (`add-quest-checklist`); showing each task's availability; switching any consumer to local progress or removing the token (`retire-tracker-token`); sync.

## Capabilities

### New Capabilities

- `manual-progress`: entering and undoing the player's own progress values (level, faction, edition, trader loyalty, hideout station levels, task state overrides) as manual events in a mode's active wipe.

### Modified Capabilities

- `settings-page`: the Local progress section gains the Your progress entry part beside the per-mode wipe rows.
- `task-catalog`: traders and their loyalty level numbers are retained in the task catalog.
- `local-progress`: one event of a cycle can be read by its ID, so Redo can find the value an undo removed.

## Impact

- `lib/application/`: a manual progress controller over a narrow progress-access interface that `TaskLogProgressController` implements on its shared queue, reusing its active-wipe creation.
- `lib/ui/settings/local_progress_settings.dart` and new widgets for the entry part; `lib/ui/settings/settings_page.dart` wiring.
- `packages/blackgrid_progress`: trader entries in `ProgressCatalog` and its parser; the progress catalog's format version.
- `lib/data/catalog_normalizer.dart`: passes the raw trader levels to the progress catalog parser.
- `LocalProgressStore` and its Drift adapter: a read-only single-event read by ID.
- No database schema change: manual values use the existing event registers. No new dependency.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Where manual entry lives

- **Choice:** a Your progress part of Settings' Local progress section, per mode.
- **Rejected:** a new top-level Progress area next to Map and Scanner: it pre-empts the checklist's layout and adds shell work now.
- **Reversal cost:** low
- **Important:** yes: changes what users see.
- **Chosen by:** user

### S2: Faction and edition are entered too

- **Choice:** the player also sets faction and edition, beside level, loyalty and stations.
- **Rejected:** the roadmap's fields only: faction- and edition-gated tasks would stay unchecked.
- **Reversal cost:** low
- **Important:** yes: changes what users see.
- **Chosen by:** user

### S3: An entry with no active wipe creates one

- **Choice:** create the mode's active wipe starting on the earlier of today and the current game-log session folder's date (today when no folder is known), then record the entry; replay from an earlier date still works later. Amended after design review round 1 (user decision): starting on today alone would make the live path drop the running session's task events when that session began before midnight.
- **Rejected:** refuse entry until a wipe exists: one more step before first use.
- **Reversal cost:** medium (wipes created this way persist)
- **Important:** yes: changes behaviour users see.
- **Chosen by:** user

### S4: Task overrides are search, set and undo

- **Choice:** search the mode's tasks by name, see each one's state and its source, set a state (not started records unknown), undo the last manual change and redo an undo. Redo amended after design review round 1 (user decision): the store's undo restores its target's predecessor, so a second undo re-applies the undone value. After PR review, the owner approved a Redo-only timestamp floor strictly after the verified undo winner, including when the clock does not advance or moves backward; ordinary manual/log ordering stays unchanged.
- **Rejected:** also showing availability (overlaps the checklist); set only without undo (leaves the store's undo unused and mistakes harder to fix).
- **Reversal cost:** low
- **Important:** yes: changes what users see.
- **Chosen by:** user

### S5: Trader loyalty levels come from the catalog

- **Choice:** the task catalog keeps each trader's loyalty level numbers from tarkov.dev; the picker lists traders with more than one level, bounded by their levels.
- **Rejected:** a fixed 1-4 picker for every trader: offers impossible levels and needs upkeep.
- **Reversal cost:** medium (progress catalog format)
- **Important:** yes: binds the progress catalog format.
- **Chosen by:** user

### S6: Your progress edits the effective mode

- **Choice:** Your progress edits the app's effective mode, which follows the game's detected session mode and switches with it; it has no mode chooser of its own. Studied TarkovMonitor's behaviour first (at the user's request): it switches its data and progress profile when the game's session mode changes and writes each log task event to that session's mode, and it has no manual level, loyalty or station entry. Blackgrid already follows the detected mode and routes log events by their folder's mode, so this matches.
- **Rejected:** an own PvP/PvE/seasonal choice: needs another mode's stored catalog decoded from disk and diverges from the game-following model.
- **Reversal cost:** low
- **Important:** yes: changes what users see.
- **Chosen by:** user

### S7: Consumers stay on the Tracker token

- **Choice:** no consumer reads local progress yet; advice, timers and task state are unchanged.
- **Rejected:** switching them now: that is `retire-tracker-token`, after the checklist.
- **Reversal cost:** low
- **Important:** no
- **Chosen by:** agent

## Release Notes

You can now enter your own progress for each game mode in Settings: level, faction, edition, trader loyalty, built hideout stations, and the state of any quest the game logs missed. The last change of each value can be undone, and an undo can be redone. Redo remains effective when the system clock moves backward. Advice still uses Tracker progress for now.

### Added

- Settings, Local progress: a Your progress part for entering level, faction, edition, trader loyalty, hideout station levels and quest states by hand, per game mode, with undo and redo of the last change (add-manual-progress).
