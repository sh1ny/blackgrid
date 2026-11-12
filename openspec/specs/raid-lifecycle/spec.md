# raid-lifecycle Specification

## Purpose
Follows the player's raid from the game's log events, from queue to the return to the menus, so timers, stats and task progress know when a raid starts, on which map and mode, how it was entered and when it ends.

## Requirements

### Requirement: Raid phases follow the log events
The raid phase SHALL be one of unknown, in menus, in queue, match found, raid starting, in raid and raid ended. It SHALL start as unknown and SHALL change only on log events: profile selected → in menus; queue entered → in queue; match found → match found; raid starting → raid starting; raid started → in raid; raid exit → raid ended.

#### Scenario: A whole raid
- **WHEN** the events are profile selected, queue entered, scene loaded on Customs, match found, raid starting, raid started, raid exit and profile selected
- **THEN** the phase goes in menus, in queue, match found, raid starting, in raid, raid ended and in menus, and the raid's map is Customs

#### Scenario: No events yet
- **WHEN** no log event has been read
- **THEN** the phase is unknown and no raid is current

#### Scenario: Raid without a starting countdown
- **WHEN** match found is followed directly by raid started, with no raid starting event
- **THEN** the phase goes from match found to in raid

#### Scenario: Out-of-place event
- **WHEN** a raid-started event arrives while the phase is in menus with no queue entered since
- **THEN** the phase becomes in raid with no map, and the raid is marked as entered without a queue

### Requirement: A raid records its map, mode, times and entry
A raid SHALL record its map (from the last scene loaded or rejoin location since the queue), its mode (the last session mode logged before it), its queue, start and end times from the log, and how it was entered: queue, transit or reconnect. The end SHALL record its cause: raid exit, menus or client restart.

#### Scenario: Recorded raid
- **WHEN** session mode PvpSeason, queue entered at 19:38:10, scene loaded on Lighthouse, raid started at 19:41:06 and raid exit at 19:54:20 are read
- **THEN** the raid has map Lighthouse, mode seasonal, queue time 19:38:10, start 19:41:06, end 19:54:20, entry queue and end cause raid exit

#### Scenario: Map unknown
- **WHEN** a raid starts after a scene-loaded event with no supported map
- **THEN** the raid's map is unknown and the phase is still in raid

### Requirement: Events read together are reduced in log-time order
All events read from the three files in one read SHALL be applied in order of log time, then application before backend before push-notifications, then byte offset. A replay of a session folder SHALL therefore give each raid the same start, end, end cause and record identities as a live read of the same folder in which every file was read on each poll.

#### Scenario: Replay matches the live read
- **WHEN** a session folder holds a raid whose raid exit (backend, 22:09:04) is 9 minutes before the next profile selected (application, 22:17:49), and the folder is read once whole at startup
- **THEN** the raid ends at 22:09:04 with cause raid exit and the backend record's identity, as it does when the same lines are read live

#### Scenario: Same time in two files
- **WHEN** a raid exit and a profile selected carry the same log time and are read together
- **THEN** the profile selected is applied first and the raid ends from the menus at that time

#### Scenario: A file could not be read for a poll
- **WHEN** the backend log cannot be read for one poll while the application log's profile selected is read, and the raid exit is read on the next poll
- **THEN** the raid ends from the menus at the profile-selected time and the late raid exit ends nothing

### Requirement: The first ending of a raid wins and later endings change nothing
Raid exit and the next profile selected SHALL each end the current raid with their own time. The first one applied SHALL end it; the other SHALL NOT end or change any raid and SHALL publish no transition. A raid exit or profile selected logged before the current queue or rejoin time SHALL NOT end anything.

#### Scenario: Raid exit first
- **WHEN** a raid is in progress and raid exit at 19:54:20 is applied, then profile selected at 19:54:35
- **THEN** the raid ends at 19:54:20 by raid exit, the phase becomes raid ended and then in menus, and only one raid-ended transition is published

#### Scenario: Profile select first
- **WHEN** a raid is in progress and profile selected at 19:54:35 is applied, then a raid exit at 19:54:36
- **THEN** the raid ends at 19:54:35 from the menus, the phase is in menus, and the raid exit publishes nothing

#### Scenario: Stale raid exit after a new queue
- **WHEN** a raid ended from the menus, queue entered at 19:56:45 is applied, and then a raid exit logged at 19:54:20 is applied
- **THEN** the phase stays in queue and nothing is published

#### Scenario: Raid exit with no raid
- **WHEN** a raid exit is applied while the phase is in menus and no raid is current
- **THEN** the phase stays in menus and nothing is published

### Requirement: A queue that ends without a raid is aborted
Matching aborted, or a profile selected or raid exit logged after the queue or rejoin time while the phase is in queue, match found or raid starting and no raid has started, SHALL end the queue without a raid: the phase SHALL become in menus, the last queue SHALL be recorded as aborted and one matching-aborted transition SHALL be published.

#### Scenario: Matching cancelled after a match was found
- **WHEN** queue entered, scene loaded on Shoreline, match found and matching aborted are applied
- **THEN** the phase is in menus, no raid started, the last queue is recorded as aborted and one matching-aborted transition is published

#### Scenario: Back to menus while loading
- **WHEN** queue entered, match found, raid starting and then profile selected are applied, with no raid started
- **THEN** the phase is in menus, the last queue is recorded as aborted and one matching-aborted transition is published

#### Scenario: Aborted with no queue
- **WHEN** a matching-aborted event is applied while the phase is in menus
- **THEN** the phase stays in menus and nothing is published

### Requirement: Rejoining a raid is a transit or a reconnect
A raid-rejoined event SHALL set the phase to raid starting with the rejoin location as the map. It SHALL be a transit when the last raid ended by raid exit or from the menus in the same session folder and no queue was entered or aborted since; otherwise it SHALL be a reconnect. The following raid started SHALL start the raid with that entry.

#### Scenario: Transit to another map
- **WHEN** a raid on Shoreline ends by raid exit, then profile selected, raid rejoined with location Icebreaker and raid started are applied in the same session folder
- **THEN** a new raid starts on Icebreaker with entry transit

#### Scenario: Queue between the raid and the rejoin
- **WHEN** a raid ends, then queue entered, matching aborted and raid rejoined with location Woods are applied in the same session folder
- **THEN** the rejoin is a reconnect, not a transit

#### Scenario: Unknown rejoin location
- **WHEN** a raid-rejoined event names a location Blackgrid does not know
- **THEN** the phase becomes raid starting with no map

### Requirement: A client restart during a raid continues that raid
When a new session folder is read while a raid is current, the raid SHALL become interrupted. The new folder's profile selected SHALL set the phase to in menus without ending the raid or publishing a transition. A rejoin that follows SHALL continue the same raid with no new raid-started transition. A queue entered first SHALL end it with cause client restart at the time of that profile selected.

#### Scenario: Restart and reconnect while Blackgrid runs
- **WHEN** a raid on The Lab is in progress, a new session folder appears, and its session mode, profile selected, raid rejoined with location laboratory and raid started are applied
- **THEN** one raid continues on The Lab, no raid-ended or second raid-started transition is published, and the phase is in raid

#### Scenario: Restart without reconnecting
- **WHEN** a raid is in progress, a new session folder appears, and its profile selected at 23:15:20 and then queue entered are applied
- **THEN** after the profile selected and before the queue entered, the phase is in menus and no transition is published; then the raid ends at 23:15:20 with cause client restart and the phase is in queue

#### Scenario: Blackgrid starts after the restart
- **WHEN** Blackgrid starts with only the new folder to read, and that folder holds profile selected, raid rejoined with status MatchWait and location laboratory, and raid started
- **THEN** one raid starts on The Lab with entry reconnect and the raid-rejoined record's identity

### Requirement: Each lifecycle transition is published once
Raid started, raid ended and matching aborted SHALL each be published once, with the record identity and time of the event that caused it. Reading the same session folder again after an app restart SHALL publish them with the same identities, so later consumers can drop duplicates.

#### Scenario: One transition per event
- **WHEN** a whole raid is read
- **THEN** exactly one raid-started and one raid-ended transition are published

#### Scenario: Re-read after restart
- **WHEN** the app restarts and reads the same session folder again
- **THEN** each raid-started, raid-ended and matching-aborted transition has the same record identity, time and cause as before the restart

### Requirement: Map shows the raid phase
The Map saved-file inputs section SHALL show a "Raid:" line with the phase in plain words and, when known, the map, for example "Raid: in raid on Customs" or "Raid: in menus". It SHALL NOT show a raw phase name. Raid state SHALL NOT change the selected map, the manual map or Follow logs.

#### Scenario: In raid
- **WHEN** the section is expanded and a raid on Customs is in progress
- **THEN** the section shows "Raid: in raid on Customs"

#### Scenario: Matching cancelled
- **WHEN** the section is expanded and the last queue was aborted
- **THEN** the section shows "Raid: in menus (matching cancelled)"

#### Scenario: No log input
- **WHEN** the section is expanded and no log folder is configured or found
- **THEN** the section shows "Raid: unknown" and no raw phase name

### Requirement: A raid records its countdown and a guessed side
A raid entered from a queue SHALL record the time of the last raid-starting event since its queue, if any, and a guessed side: PMC when that event came more than 3 s before raid started, otherwise scav. A transit raid SHALL take the side of the raid it left. A reconnect SHALL keep the raid's side. A raid entered without a queue, or by a reconnect with no earlier raid known, SHALL have side unknown.

#### Scenario: PMC countdown
- **WHEN** queue entered, match found, raid starting at 19:40:51 and raid started at 19:41:06 are applied
- **THEN** the raid records raid starting at 19:40:51 and side PMC

#### Scenario: No countdown
- **WHEN** queue entered, match found and raid started are applied, with no raid-starting event
- **THEN** the raid records no raid-starting time and side scav

#### Scenario: Short countdown
- **WHEN** raid starting is applied at 19:41:04 and raid started at 19:41:06, after a queue
- **THEN** the raid's side is scav

#### Scenario: Countdown exactly 3 s
- **WHEN** raid starting is applied at 19:41:03.000 and raid started at 19:41:06.000, after a queue
- **THEN** the raid's side is scav

#### Scenario: Raid starting from an aborted queue
- **WHEN** a queue with raid starting at 19:30:00 is aborted, then a new queue, match found and raid started at 19:41:06 are applied
- **THEN** the raid records no raid-starting time and side scav

#### Scenario: Transit keeps the side
- **WHEN** a raid with side scav ends and a transit into another map starts a new raid
- **THEN** the new raid's entry is transit and its side is scav

#### Scenario: Reconnect keeps the side
- **WHEN** a raid with side PMC is interrupted by a client restart and continued by a reconnect
- **THEN** the continued raid's side is PMC

#### Scenario: No queue
- **WHEN** a raid starts while the phase is in menus with no queue entered since
- **THEN** the raid's side is unknown

#### Scenario: Reconnect after Blackgrid starts
- **WHEN** Blackgrid starts with only a new session folder holding profile selected, raid rejoined and raid started
- **THEN** the raid's entry is reconnect and its side is unknown

### Requirement: Each flea sale is published once with its mode
Each flea sale read from the push-notifications log SHALL be published once as a flea-sale transition, with the identity and time of its record, the sold item, the count, the rouble payout when the sale paid in roubles, and the last session mode logged before it. A sale SHALL NOT change the raid phase or any raid. Reading the same session folder again SHALL publish it with the same identity.

#### Scenario: Sale during a session
- **WHEN** session mode PvE is logged, then a flea sale of 2 of one item paying 45 000 roubles is applied
- **THEN** one flea-sale transition is published with that record's identity and time, count 2, 45 000 roubles and mode PvE, and the phase is unchanged

#### Scenario: Sale before any mode is logged
- **WHEN** a flea sale is applied before any session mode was logged in the folder
- **THEN** the flea-sale transition is published with no mode

#### Scenario: Sale paid in another currency
- **WHEN** a flea sale whose payout holds no roubles is applied
- **THEN** the flea-sale transition is published with no rouble payout

#### Scenario: Replay after an app restart
- **WHEN** the same session folder is read again from the start after Blackgrid restarts
- **THEN** each flea sale is published again with the same record identity as before

#### Scenario: Sale during a raid
- **WHEN** a flea sale is applied while the phase is in raid
- **THEN** the phase stays in raid, the current raid is unchanged and one flea-sale transition is published

### Requirement: Each task message is published once with its mode
Each task-started, task-failed and task-finished event read from the push-notifications log SHALL be published once as a task transition, carrying its record identity and time, the task ID, its state (started, failed or finished) and the last session mode logged before it in the same folder: no mode when that folder logged none or the last one is not recognised. It SHALL NOT change the raid phase or any raid, and a re-read SHALL publish it with the same identity.

#### Scenario: Task finished in the menus
- **WHEN** session mode PvP is logged, then a task-finished event for task `5936d90786f7742b1420ba5b` is applied while the phase is in menus
- **THEN** one task transition is published with that record's identity and time, that task ID, finished and mode PvP, and the phase is in menus

#### Scenario: Task message before any mode is logged
- **WHEN** a task-failed event is applied before any session mode was logged in the folder
- **THEN** the task transition is published with no mode

#### Scenario: Mode from an earlier folder is not carried
- **WHEN** session mode PvP was logged in one folder, a newer folder starts, and a task-started event is applied before that folder logs a session mode
- **THEN** the task transition is published with no mode

#### Scenario: Unrecognised mode
- **WHEN** a session mode Blackgrid does not recognise is logged, then a task-finished event is applied
- **THEN** the task transition is published with no mode

#### Scenario: Replay after an app restart
- **WHEN** the same session folder is read again from the start after Blackgrid restarts
- **THEN** each task message is published again with the same record identity, task ID and state as before

#### Scenario: Push records recover after a mode change
- **WHEN** one scan reads PvP at 10:00 and PvE at 10:02, then a later scan recovers a task message logged at 10:01 in the same folder
- **THEN** the task transition carries PvP, matching a one-shot read of that folder rather than the latest delivered mode
