# task-log-progress Specification

## Purpose

Records the player's task started, failed and finished messages from the game's own logs into local progress, one active wipe per game mode, and keeps it current through live reading, startup catch-up, replay from a date and starting a new wipe.

## Requirements

### Requirement: Each game mode has at most one active wipe
Blackgrid SHALL keep, for each game mode (PvP, PvE, seasonal), at most one active wipe: a local progress cycle of that mode, its start date and the last log folder fully read into it. The active wipe SHALL survive restart. Task events of a mode SHALL be recorded only in that mode's active wipe. A wipe whose cycle cannot be opened SHALL be reported unavailable and SHALL NOT be replaced automatically.

#### Scenario: Wipe survives restart
- **WHEN** PvE has an active wipe started 2026-11-01 and Blackgrid restarts
- **THEN** PvE's active wipe is the same cycle with start date 2026-11-01 and the same last folder read

#### Scenario: Modes are separate
- **WHEN** PvP and PvE each have an active wipe and a PvE task-finished message is recorded
- **THEN** the event is in PvE's cycle and PvP's cycle is unchanged

#### Scenario: Damaged wipe stays visible
- **WHEN** PvP's active cycle reports its history unavailable on open
- **THEN** PvP's wipe is shown as unavailable, no task event is recorded for PvP, and no new cycle is created for PvP

### Requirement: The first task event of a mode creates its wipe
When a task message is to be recorded for a mode with no active wipe, Blackgrid SHALL create a new progress cycle for that mode and make it active, with the start date of the log folder the message came from, then record the message in it. A failed creation SHALL record nothing for that mode and SHALL be reported.

#### Scenario: First PvP task
- **WHEN** PvP has no wipe and a task-started message for PvP is read from folder `log_2026.11.12_18-02-11_1.3.0.0.48484`
- **THEN** a new PvP cycle is active with start date 2026-11-12, and it holds one log-sourced started event for that task

#### Scenario: Creation fails
- **WHEN** PvP has no wipe and creating its cycle fails with a storage failure
- **THEN** no PvP wipe exists, no event is recorded, and the Local progress section shows that task progress could not be saved

### Requirement: Task messages become log-sourced task-state events
Each task-started, task-failed and task-finished message SHALL be recorded as one log-sourced event setting that task's state to started, failed or finished. The event SHALL carry the record's log time converted from local time to UTC milliseconds, and an event ID derived only from the wipe's cycle and the record identity. The task ID SHALL be stored as the log gives it, whether or not the task catalog knows it.

#### Scenario: Task finished
- **WHEN** a task-finished message for task `5936d90786f7742b1420ba5b` logged at 2026-11-12 18:40:00.125 local time is recorded in PvP's wipe
- **THEN** PvP's current state for that task is finished, from a log-sourced event whose time is that local instant in UTC milliseconds

#### Scenario: Unknown task ID
- **WHEN** a task-started message names a task ID that the PvP task catalog does not hold
- **THEN** the event is recorded with that task ID

#### Scenario: Identity over budget
- **WHEN** a record's derived event ID is longer than the progress identity budget
- **THEN** that message is not recorded, it is counted as skipped, and the other messages of the batch are recorded

### Requirement: Reading the same record again changes nothing
Recording a task message whose record was already recorded in the same wipe SHALL add no event and SHALL NOT advance the wipe's revision, whether the record is read again live, by catch-up or by replay.

#### Scenario: Restart replays the live folder
- **WHEN** Blackgrid restarts and the live reader reads the current folder again from its start
- **THEN** every task message in it is recorded with the same event ID as before, and the wipe's revision is unchanged

#### Scenario: Replay overlaps catch-up
- **WHEN** catch-up has read folder A into PvE's wipe and a replay then reads folder A again
- **THEN** no new event is added for folder A's task messages

### Requirement: A message without a known mode is skipped
A task message logged before any session mode in its log folder, or after a session mode Blackgrid does not recognise, SHALL NOT be recorded. It SHALL be counted as skipped for no mode, never assigned to the app's selected mode or to another folder's mode.

#### Scenario: Message before the mode line
- **WHEN** a folder's push-notifications log has a task-finished message logged before the folder's first session-mode line
- **THEN** no event is recorded for it and the run result counts one record skipped for no mode

#### Scenario: Unrecognised session mode
- **WHEN** a folder logs a `Session mode:` line whose value Blackgrid does not recognise, then a task-started message
- **THEN** no event is recorded, the message is counted as skipped for no mode, and no cycle is created

#### Scenario: Mode changes within a folder
- **WHEN** session mode PvP is logged, a task-started message follows, then session mode PvE is logged and another task-started message follows
- **THEN** the first message is recorded in PvP's wipe and the second in PvE's wipe

### Requirement: Live task messages are recorded as they are read
Task transitions published by the raid lifecycle from the live log folder SHALL be recorded in publication order, during raids and outside them. A failed write SHALL be reported until the next successful write, and SHALL NOT stop later messages from being recorded.

#### Scenario: Live task start
- **WHEN** session mode PvE is logged and a task-started message is then read from the live folder
- **THEN** PvE's current state for that task becomes started

#### Scenario: Store busy or failing
- **WHEN** recording a live message fails with a storage failure and the next live message succeeds
- **THEN** the first message is not recorded, the failure is shown until the second is recorded, and the second message is recorded

#### Scenario: One conflicting record in a live batch
- **WHEN** a live batch holds three task messages and the store rejects one of them as conflicting
- **THEN** the other two are recorded and the rejected one is reported as not saved

### Requirement: Startup catch-up reads the folders missed since the last run
After launch, once the raid lifecycle has read the live folder, and while the player is not in a raid, Blackgrid SHALL read every log folder of each mode's wipe that is dated on or after the wipe's start, later than its last folder read and older than the live folder, by folder date and time. It SHALL read them in that order and advance the last folder read after each folder's events are stored. Catch-up refused for a raid SHALL run when the player is next outside a raid.

#### Scenario: A month away
- **WHEN** PvE's last folder read is from 2026-10-05, the log root holds 30 later folders and the live folder, and Blackgrid starts in the menus
- **THEN** the task messages of the 30 folders are recorded, PvE's last folder read is the newest of them, and the live folder is left to the live reader

#### Scenario: Started during a raid
- **WHEN** Blackgrid starts while the live folder shows the player in a raid
- **THEN** catch-up does not start until the lifecycle reaches the menus or the raid ends, and then it runs once

#### Scenario: Interrupted catch-up
- **WHEN** storing the third of five folders fails with a storage failure
- **THEN** the last folder read is the second folder, the failure is shown, and the next catch-up starts from the third folder

#### Scenario: A conflicting record does not block catch-up
- **WHEN** a re-read record's derived event ID is already stored with a different time, as after a change of the Windows time zone
- **THEN** that record is counted as skipped for a conflicting record, the rest of the folder is recorded, the last folder read advances past it, and the next catch-up does not stop at that folder

#### Scenario: A mode without a wipe in a caught-up folder
- **WHEN** only PvP has a wipe and a folder that catch-up reads for it also holds PvE task messages
- **THEN** a PvE wipe is created with that folder's date as its start and the PvE messages are recorded in it, as for the first task event of a mode

#### Scenario: Folders ordered by date, not by name
- **WHEN** PvP's last folder read is `log_2026.11.02_9-00-00_1.3.0.0.48484` and the root also holds `log_2026.11.02_10-00-00_1.3.0.0.48484` and a newer live folder
- **THEN** catch-up reads `log_2026.11.02_10-00-00_1.3.0.0.48484`, because it is the later folder by date and time

### Requirement: Replay reads the log folders from a date into the active wipe
Replay SHALL read, for one mode, every log folder dated on or after the chosen date, the live folder up to what is written, into that mode's active wipe. It SHALL record only that mode's task messages. The date SHALL default to the wipe's start. An earlier date SHALL move the wipe's start back to it once the replay has stored its first folder. With no active wipe, the replay SHALL create one starting on the chosen date. Events already in the wipe, including manual ones, SHALL be kept.

#### Scenario: Installed mid-wipe
- **WHEN** PvP's wipe starts 2026-11-12 and the player replays PvP from 2026-10-20, with folders from 2026-10-20 to 2026-11-11 present
- **THEN** PvP task messages of those folders are recorded in the same PvP cycle, and its start date becomes 2026-10-20

#### Scenario: Other modes are left alone
- **WHEN** a PvP replay reads a folder that also holds PvE task messages
- **THEN** only the PvP messages are recorded, and PvE's wipe is unchanged

#### Scenario: No folder from that date
- **WHEN** PvE's wipe starts 2026-11-01 and the player replays PvE from 2026-11-12, but the newest folder is dated 2026-11-10
- **THEN** no event is recorded, the start date stays 2026-11-01, and the result says no folders were read

#### Scenario: The live folder is never the last folder read
- **WHEN** a replay reads the live folder after three older folders
- **THEN** the live folder's PvE task messages are recorded, and the wipe's last folder read is at most the newest of the three older folders

#### Scenario: Replay sees a folder newer than the live reader
- **WHEN** a replay admitted with live folder A lists a newer folder B before the live reader has bound it
- **THEN** B's available records may be replayed but B is not marked fully read, and catch-up from a later live folder still reads B's subsequently written records

### Requirement: Starting a new wipe creates a fresh cycle and replays into it
Starting a new wipe for a mode SHALL ask for its start date, create a new cycle for the mode, make it the mode's active wipe with that start date and no folder read, and then replay that mode from the start date into it. The previous wipe's cycle and events SHALL be kept unchanged. A failed creation SHALL leave the previous wipe active.

#### Scenario: New wipe
- **WHEN** PvP's wipe started 2026-06-20 and the player starts a new PvP wipe dated 2026-11-12
- **THEN** a new PvP cycle is active with start date 2026-11-12, it holds only PvP task messages from folders dated on or after 2026-11-12, and the old cycle still holds its events

#### Scenario: Creation fails
- **WHEN** creating the new cycle fails
- **THEN** the previous wipe stays active and unchanged, and the section shows that the new wipe could not be started

#### Scenario: Live replay predates a newly selected wipe
- **WHEN** a new wipe starts November 12 while the latest log folder is dated November 10, and restart or rebind republishes that folder's task messages
- **THEN** those messages are not recorded in the new wipe, and its selected start date is unchanged

### Requirement: Replay, catch-up and new wipe are refused during a raid
Replay, catch-up and starting a new wipe SHALL be refused while the raid lifecycle's phase is in queue, match found, raid starting or in raid, with that reason. Replay and new wipe SHALL be refused while another catch-up, replay or new wipe is running. A refused run SHALL change no wipe and record nothing.

#### Scenario: Replay requested in a raid
- **WHEN** the phase is in raid and the player asks to replay PvE
- **THEN** nothing is read or recorded, and the section says the replay is not available during a raid

#### Scenario: Replay while catch-up runs
- **WHEN** catch-up is reading folders and the player asks to start a new PvP wipe
- **THEN** no cycle is created and the section says another log read is running

#### Scenario: Raid starts during a replay
- **WHEN** a replay is running and the phase moves to in queue
- **THEN** the replay stops after the folder it is storing, that folder's events are kept, the wipe's last folder read never moves back to an older folder, and the result says it was stopped by a raid

### Requirement: Each run reports its result
Every catch-up, replay and new-wipe run SHALL produce one result naming its kind, its mode or modes, the folders read, the task events recorded, the records skipped by reason (no mode, unreadable record, identity over budget, conflicting record) and the folders that could not be read, or the failure that stopped it. An unreadable folder, and a record the progress store rejects as conflicting or invalid, SHALL be counted and skipped without stopping the run.

#### Scenario: Successful replay
- **WHEN** a PvE replay reads 12 folders, records 9 task events and skips 1 message for no mode
- **THEN** the result reads 12 folders, 9 task events, 1 skipped for no mode, and no failure

#### Scenario: Unreadable folder
- **WHEN** one of the folders cannot be opened for reading
- **THEN** that folder is counted as unreadable, the other folders are read, and a replay from its date reads it again

#### Scenario: Older replay fails below an existing watermark
- **WHEN** the wipe's last folder is November 11, a replay from October 20 stores that date and fails before October 21
- **THEN** the November 11 watermark stays unchanged and the failed result instructs replaying again from October 20, without promising startup catch-up will resume the older replay
