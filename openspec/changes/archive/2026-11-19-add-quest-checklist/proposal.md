# Proposal

## Why

The local progress tracker (M9, local progress tracker) now records task states from the game logs and by hand, and the store already holds objective counts and completion, but nothing lets the player see their active quests or record objective progress, and the map still shows every quest's markers whether the player has the task or not. This change is M9's change 7, `add-quest-checklist`.

It advances the M9 exit criterion "A replay of the player's real log folders matches their in-game quest state, and the checklist and manual progress entry work in play" (user-verified). This change delivers the checklist half and checks it with a `[user]` task in tasks.md once the app is built: the owner ticks objectives and moves counters in play and confirms that the list and the map's quest markers follow. The whole criterion, with the log replay, is judged again at the milestone close.

## What Changes

- A **Quests** section in the Map's inspector, beside This raid, Markers and Pins, for the app's effective game mode (the game's detected session mode, else the header choice). It lists the mode's started tasks (started from the game logs or set by hand) with their objectives.
- Each objective can be ticked done or not done. An objective whose target count is over 1 gets **+/-** counters, stored as absolute counts. Reaching the target count marks the objective done; ticking it done sets the count to the target. Every tick and counter step is one manual event in the mode's active wipe, through the same progress access the Your progress panel uses, and the last change of a value can be undone.
- Ticking every objective never finishes the task: a task becomes finished from the game logs or a manual task state, as today.
- The map's quest markers follow the checklist: by default they show only for objectives of started tasks that are not done. A **Show all quests** switch in Markers restores today's view of every quest's markers. While the mode has no started task recorded, every quest marker shows as today.
- Nothing that reads progress for advice changes: keep/sell advice, raid timers and Tracker task state still come from the Tracker token until `retire-tracker-token`.

**Not in this change:** listing available or locked tasks, or their availability reasons (quest planning, M11); finishing a task from its objectives; hideout progress views; switching any consumer to local progress or removing the token (`retire-tracker-token`); sync.

## Capabilities

### New Capabilities

- `quest-checklist`: the Map inspector's Quests section, listing a mode's started tasks with tickable objectives and objective counters recorded as manual events, and the map's quest-marker filter driven by that progress.

### Modified Capabilities

- `workspace-shell`: the Map inspector provides Quests beside This raid, Markers and Pins.
- `marker-preferences`: the Markers section gains the Show all quests switch, and the quest-marker visibility rule follows local progress.

## Impact

- `lib/application/`: a checklist controller over `LocalProgressAccess` (objective count and completion targets, undo), and a quest-progress view the map controller reads for marker eligibility.
- `lib/application/map_controller.dart`: quest-marker eligibility uses the started-task and done-objective sets, keyed by the task and objective IDs the quest markers already carry.
- `lib/ui/`: a new Quests inspector section on Map; `lib/ui/marker_preferences.dart` gains the switch.
- Settings: the Show all quests choice is saved with the marker filters.
- No database schema change: objective counts and completion use the store's existing event fields. No new dependency.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: The checklist lives in the Map inspector

- **Choice:** a Quests section in the Map inspector beside This raid, Markers and Pins.
- **Rejected:** a third top-level area (shell work, takes the player off the map in raid); Settings' Your progress (awkward during play).
- **Reversal cost:** low
- **Important:** yes: changes what users see.
- **Chosen by:** user

### S2: Active means started

- **Choice:** the checklist lists the mode's tasks whose local state is started, from the logs or set by hand.
- **Rejected:** also listing available tasks: longer list, overlaps quest planning (M11).
- **Reversal cost:** low
- **Important:** yes: changes what users see.
- **Chosen by:** user

### S3: Quest markers follow active quests

- **Choice:** by default the map shows quest markers only for not-done objectives of started tasks; a Show all quests switch restores today's view; with no started task recorded every quest marker shows.
- **Rejected:** hiding only done objectives (the map stays cluttered with quests the player does not have); dimming done objectives (nothing is removed).
- **Reversal cost:** low
- **Important:** yes: changes behaviour users see, and adds a saved marker setting.
- **Chosen by:** user

### S4: Counters complete objectives, never tasks

- **Choice:** objectives with a target count over 1 get +/- counters stored as absolute counts; reaching the target marks the objective done and ticking done sets the count to the target. Ticking every objective does not finish the task.
- **Rejected:** independent tick and count (two clicks for one fact); auto-finishing the task (contradicts the game until turn-in is logged).
- **Reversal cost:** low
- **Important:** yes: changes behaviour users see.
- **Chosen by:** user

### S5: The checklist edits the effective mode

- **Choice:** the checklist and the marker filter use the app's effective mode, as Your progress does; no mode chooser of their own.
- **Rejected:** an own mode choice: diverges from the game-following model `add-manual-progress` settled.
- **Reversal cost:** low
- **Important:** no
- **Chosen by:** agent

### S6: Consumers stay on the Tracker token

- **Choice:** no advice, timer or Tracker task-state consumer reads local progress yet.
- **Rejected:** switching them now: that is `retire-tracker-token`.
- **Reversal cost:** low
- **Important:** no
- **Chosen by:** agent

## Release Notes

The Map now has a Quests panel listing the quests you have started in the current game mode. Tick objectives as you complete them and count kills or found items with +/- buttons. The map's quest markers show only what you still have to do on your active quests, and a Show all quests switch brings every quest back. Advice still uses Tracker progress for now.

### Added

- Map inspector: a Quests panel with your started quests, tickable objectives and +/- counters, with undo (add-quest-checklist).
- Markers: a Show all quests switch; by default quest markers show only the open objectives of your started quests (add-quest-checklist).
