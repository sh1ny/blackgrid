# Proposal

## Why

Milestone M9 (local progress tracker) needs real task progress in the local ledger. `add-progress-store` (#110) stores progress events, `add-task-catalog` (#111) keeps the task facts and `add-task-rules` (#112) turns them into availability, but nothing writes the player's task progress yet. The game already tells us. Its push-notifications log carries a message whenever a task is started, failed or finished, and M7's log reader parses all three (ADR-0030). The raid reducer then drops them.

This change serves M9 exit criterion 3: "Task started, failed and finished events from the logs fill the store per mode and wipe. A log-folder replay rebuilds a wipe and is refused during a raid. Proved by offline fixture tests." It also feeds user-verified criterion 5, "A replay of the player's real log folders matches their in-game quest state". That criterion is judged at the milestone close, not in this change: until `add-quest-checklist` there is no screen that lists task states, so the owner has nothing to compare with the game yet. This change only gives a one-line replay result.

Three facts shape it:

- The ledger's cycles are local buckets. ADR-0041 leaves choosing an active cycle to the M9 changes and forbids resets and automatic rollover.
- Blackgrid reads only the newest log folder live, so sessions played while Blackgrid was closed are missed today.
- The game writes no push notification during raid loading or play (ADR-0030), so a task that fails mid-raid is not in the logs. Manual override (`add-manual-progress`) covers that gap.

## What Changes

- **Wipes.** Each game mode gets one active wipe: a progress cycle with a start date and the name of the last log folder fully read into it. The first task event seen for a mode with no wipe creates one automatically. Its start date is that event's log-folder date.
- **Live recording.** Task started, failed and finished messages from the live log folder are recorded as log-sourced task-state events in the active wipe of the session mode in force when the message was logged. Each event's ID comes from its log record and its wipe, so reading the same folder again adds nothing.
- **Startup catch-up.** On launch, and only outside a raid, Blackgrid reads the application and push-notifications logs of every log folder newer than the active wipe's last fully read folder. A month away from Blackgrid therefore fills in on its own, as long as the game has not deleted those folders.
- **Replay.** "Replay game logs from <date>" reads every log folder from that date, including what the live folder holds so far, into the active wipe. The date defaults to the wipe's start date, and picking an earlier one moves the start back, which covers installing Blackgrid mid-wipe. Manual edits are kept, and nothing is doubled.
- **New wipe.** "Start a new wipe" asks for the new start date, creates an empty cycle, makes it active for the mode and replays from that date. The old wipe stays stored, unchanged.
- **Raid guard.** Replay, new wipe and catch-up are refused while the player is queued, loading or in a raid, with that reason. Live recording continues.
- **Visible failures.** Records with no known session mode, task messages that cannot be stored and unreadable folders are counted and reported, never silently dropped or guessed.
- **Settings.** A new "Local progress" section after "Tracker progress" shows, for each mode, the active wipe's start date and the last folder read. It holds the Replay and Start a new wipe actions and the last run's result: folders read, tasks recorded, records skipped.
- **Unchanged.** Tracker stays the authority for keep/sell advice, the scav timer and task state until `retire-tracker-token`. There is no task list or checklist screen yet.

## Capabilities

### New Capabilities

- `task-log-progress`: recording task events from the game logs into the local ledger, covering active wipes per mode, live recording, startup catch-up, replay from a date, starting a new wipe, the raid guard and the run result.

### Modified Capabilities

- `raid-lifecycle`: task started, failed and finished messages are published as task transitions with their record identity, time and the session mode logged before them, as flea sales are today.
- `game-log-input`: older session folders can be read once, read-only, in folder-date order, on request from catch-up or replay, beside the live newest-folder reader.
- `settings-page`: the sections and their order gain "Local progress" after "Tracker progress", and a requirement describes its rows and actions.

## Impact

- `lib/domain/raid_lifecycle.dart`: task transitions from the reducer.
- `lib/data/`: a one-shot reader for older session folders that reuses the existing framing and parsers. The read-only audit test covers it.
- New application controller: active wipes, live recording, catch-up, replay, new wipe and the raid guard, writing through `LocalProgressStore`.
- `lib/data/database*.dart`: Drift schema 9 adds a `ProgressWipes` table holding the active wipe per mode (cycle, start date, last folder read). A new ADR records active wipes and the log-derived event ID format, extending ADR-0041.
- `lib/ui/`: the Settings "Local progress" section.
- Tests: reducer, folder reader, controller and Drift tests over small synthetic log folders and fixture lines from the existing game-log fixtures. There are no live-game tests.
- `openspec/architecture.md`: state ownership, resource-bounds rows and the component map.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Replay fills the active wipe; a new wipe is a separate action

- **Choice:** Each mode has one active wipe. Replay reads folders from a date into it, keeping manual edits and doubling nothing. "Start a new wipe" creates an empty cycle from a new start date, makes it active and replays into it. The old cycle stays stored.
- **Rejected:** Every replay builds a fresh cycle. The rebuild is always clean, but manual corrections in the old cycle are left behind with it.
- **Reversal cost:** high. It fixes how wipes map onto ledger cycles for every later M9 change.
- **Important:** yes. It binds future changes, and players see it.
- **Chosen by:** user. The owner first asked how a player who skipped a month would recover; startup catch-up (S2) answers that, and replay into the active wipe keeps their manual edits.

### S2: Catch up on missed folders at startup

- **Choice:** On launch, outside a raid, read every folder newer than the active wipe's last fully read folder.
- **Rejected:** Manual replay only, where progress silently falls behind whenever Blackgrid was closed.
- **Reversal cost:** medium.
- **Important:** yes. Players see it.
- **Chosen by:** user.

### S3: Settings "Local progress" section

- **Choice:** A new Settings section after "Tracker progress" with the wipe per mode, Replay, Start a new wipe and the last result. It is disabled with a reason during a raid.
- **Rejected:** Under the hidden-by-default Diagnostics section, where a player starting a wipe would not find it.
- **Reversal cost:** low.
- **Important:** yes. Players see it.
- **Chosen by:** user.

### S4: The first wipe is created automatically

- **Choice:** The first task event for a mode with no wipe creates one, with the start date of that event's log folder. Replay defaults to the wipe start, and an earlier date moves the start back.
- **Rejected:** Recording nothing until the player sets up a wipe, which loses what was seen before setup unless they replay.
- **Reversal cost:** low.
- **Important:** yes. Players see it.
- **Chosen by:** user.

### S5: A task ID is stored whether or not the catalog knows it

- **Choice:** Log task events are stored with the task ID the log gives, without checking it against the task catalog. The rules and the checklist ignore IDs they do not know.
- **Rejected:** Dropping unknown IDs, which would lose real progress whenever the catalog is stale or not yet downloaded for the mode.
- **Reversal cost:** low.
- **Important:** no. ADR-0041 already keeps catalog membership out of storage.
- **Chosen by:** agent.

### S6: An event without a known session mode is skipped and counted

- **Choice:** A task message logged before any `Session mode:` line in its folder, or after one whose value Blackgrid does not recognise, is not stored. It is counted as skipped in the run result.
- **Rejected:** Guessing the mode from the app's selected mode or from an earlier folder, which could put progress in the wrong mode.
- **Reversal cost:** low.
- **Important:** no.
- **Chosen by:** agent.

### S7: Tracker authority and screens stay unchanged

- **Choice:** No advice, scav-timer or task-state cutover, and no task list or checklist UI. Those belong to `retire-tracker-token` and `add-quest-checklist`.
- **Rejected:** Showing the recorded tasks here, which would duplicate the checklist change.
- **Reversal cost:** low.
- **Important:** no. It follows the roadmap's split.
- **Chosen by:** agent.

## Release Notes

Blackgrid now records your quest progress from the game's own logs. Tasks you start, fail or finish are kept locally per game mode and wipe, sessions played while Blackgrid was closed are caught up on the next launch, and Settings can replay your log folders or start a new wipe.

### Added

- Task started, failed and finished messages from the game logs are recorded in local progress, per game mode and wipe.
- Missed log folders are read at startup, outside a raid, so progress catches up after time away.
- A new "Local progress" section in Settings shows each mode's wipe and can replay game logs from a date or start a new wipe. Both are refused during a raid. Interrupted replays show the original retry date; closing Blackgrid stops replay and requires replaying again from the same date.
