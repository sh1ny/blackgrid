# Spec Delta

## Purpose

Lets the player enter their own progress for a game mode by hand (level, faction, edition, trader loyalty, built hideout stations and task states) and undo it, as manual events in that mode's active local wipe.

## ADDED Requirements

### Requirement: Manual entries are manual events in the mode's active wipe
Each manual entry SHALL append one manual-sourced event to the chosen mode's active wipe, with a new random event ID, the device ID and the current UTC time in milliseconds. It SHALL NOT write to another mode or wipe. The store's ordering SHALL decide between it and log events: newer log evidence beats it, and it beats older log evidence.

#### Scenario: Set level
- **WHEN** the player sets PvE level 34 and PvE has an active wipe
- **THEN** that wipe has one new manual event setting the player's level to 34, and PvE's current level is 34

#### Scenario: Newer log event beats the edit
- **WHEN** the player sets task T to failed by hand at 18:00 and the logs record T finished at 18:05
- **THEN** T's current state is finished and its source is the game logs

#### Scenario: Edit beats older log evidence
- **WHEN** the logs recorded task T started at 17:00 and the player sets T to finished by hand at 18:00
- **THEN** T's current state is finished and it shows as set by hand

#### Scenario: Other mode unchanged
- **WHEN** the player sets PvP level 20
- **THEN** PvE and seasonal progress gain no event

### Requirement: The first entry creates a wipe when none is active
When the chosen mode has no active wipe, an entry SHALL first create a new progress cycle for that mode and make it the active wipe, with no log folder read and a start date that is the earlier of today's local date and the current game-log session folder's date (today when no folder is known), then record the entry. A failed creation SHALL record nothing and SHALL report the failure.

#### Scenario: No wipe yet
- **WHEN** seasonal mode has no wipe, no session folder is known and the player sets faction USEC on 2026-11-13
- **THEN** seasonal has an active wipe starting 2026-11-13 with no folder read, holding one manual event setting faction to USEC

#### Scenario: Session began before midnight
- **WHEN** the live session folder is dated 2026-11-12 23:10, PvE has no wipe and the player sets their level at 00:30 on 2026-11-13
- **THEN** PvE's new wipe starts 2026-11-12, and later task messages from that session folder are recorded in it

#### Scenario: Creation fails
- **WHEN** creating the cycle fails
- **THEN** seasonal still has no active wipe, no event is recorded and the failure is shown

### Requirement: Player values are bounded
The player SHALL be able to set their level to a whole number from 1 to 79, their faction to BEAR or USEC, and their edition to one of the editions the availability rules know: Standard, Left Behind, Prepare for Escape, Edge of Darkness and Unheard. Values outside these SHALL NOT be recorded.

#### Scenario: Edition chosen
- **WHEN** the player chooses Edge of Darkness for PvP
- **THEN** PvP's current edition is `edge-of-darkness`

#### Scenario: Level out of range
- **WHEN** the player enters level 0, 80 or a non-number
- **THEN** no event is recorded and the field says the level must be from 1 to 79

### Requirement: Trader loyalty uses the trader's real levels
The player SHALL be able to set the loyalty level of each trader in the mode's task catalog that has more than one loyalty level, to one of that trader's level numbers. Traders with one level SHALL NOT be listed. Without a task catalog for the mode, or without its trader levels, loyalty entry SHALL be unavailable with that reason.

#### Scenario: Fence bounded
- **WHEN** the catalog lists Fence with levels 1 to 3
- **THEN** Fence's picker offers 1, 2 and 3 only

#### Scenario: Single-level trader
- **WHEN** the catalog lists Lightkeeper with one level
- **THEN** Lightkeeper is not listed

#### Scenario: No task catalog
- **WHEN** the mode's catalog has no task catalog
- **THEN** loyalty, station and task entry say the task data is not loaded yet, and level, faction and edition can still be set

### Requirement: Hideout station levels run from not built to the highest level
The player SHALL be able to set each hideout station of the mode's task catalog to not built (level 0) or one of its level numbers. Not built SHALL be recorded as 0, distinct from unknown.

#### Scenario: Station built
- **WHEN** the player sets Medstation to level 2 and the catalog lists levels 1 to 3
- **THEN** Medstation's current level is 2

#### Scenario: Not built versus unknown
- **WHEN** the player sets Library to not built, and has never set Booze generator
- **THEN** Library's current level is 0 and Booze generator's is unknown

### Requirement: Task states can be overridden by search
The player SHALL be able to search the mode's tasks by name, case-insensitively, and set a task to not started, started, failed or finished. Each task SHALL show its current state and whether it came from the game logs or was set by hand. Not started SHALL be recorded as unset.

#### Scenario: Override a missed task
- **WHEN** the player searches "debut", picks Debut, which has no state, and sets it to finished
- **THEN** Debut's current state is finished and it shows as set by hand

#### Scenario: No match
- **WHEN** the search matches no task name
- **THEN** the list says no task matches and nothing is recorded

### Requirement: Any value can be cleared to unknown
Each player, trader and station value SHALL offer a clear action that records an unset value; for a task, choosing not started records the unset value. Cleared values SHALL read as unknown, not as zero or an older value.

#### Scenario: Clear level
- **WHEN** the player's PvE level is 34 and the player clears it
- **THEN** PvE's current level is unknown

#### Scenario: Clear unknown value
- **WHEN** a value is already unknown
- **THEN** its clear action is disabled and nothing is recorded

### Requirement: The last manual change of a value can be undone and redone
When a value's winner is a manual edit that is not an undo, Undo SHALL restore the preceding value or unknown through the store's guarded undo. When the winner is an undo, the control SHALL read Redo and record a new manual edit with the value that undo removed, after which it reads Undo again. An undo SHALL never be undone. Neither SHALL be offered for a log winner or a value with no event. A stale undo SHALL report the conflict and change nothing.

#### Scenario: Undo a level change
- **WHEN** the level went from 30 to 34 by hand and the player undoes
- **THEN** the current level is 30 and both earlier events remain in the history

#### Scenario: Redo after undo
- **WHEN** the level went from 30 to 34 by hand, the player undoes and then chooses Redo
- **THEN** the current level is 34 again, shown as set by hand with Undo offered, and the history holds the original edit, the undo and the new edit

#### Scenario: Undo after redo
- **WHEN** after that redo the player chooses Undo
- **THEN** the current level is 30 and the control reads Redo

#### Scenario: Winner came from the logs
- **WHEN** task T's current state was recorded from the game logs
- **THEN** T offers no undo

#### Scenario: Stale undo
- **WHEN** a log event replaces T's manual state after it was shown and the player then undoes
- **THEN** the undo reports that the value changed, records nothing and the shown state refreshes

### Requirement: Entry failures are visible and change nothing
Entries SHALL wait their turn behind other local progress work, including replay, and SHALL NOT be refused for it. A busy store, a storage failure or an unavailable wipe SHALL record nothing and SHALL show its reason, without automatic retry. While local progress is not loaded, or the mode's wipe is unavailable, entry SHALL be disabled with that reason. Manual entry SHALL stay possible during raids.

#### Scenario: Entry during replay
- **WHEN** a PvE replay is reading folders and the player sets their PvE level to 40
- **THEN** the level event is recorded between the replay's writes and PvE's level shows 40

#### Scenario: Storage failure
- **WHEN** the store reports a storage failure or busy for an entry
- **THEN** the entry shows that reason, records nothing and keeps the previous value shown

#### Scenario: Damaged wipe
- **WHEN** PvE's wipe history is unavailable
- **THEN** PvE entry is disabled with the reason that its wipe cannot be read

#### Scenario: Local progress not loaded
- **WHEN** local progress failed to load at launch
- **THEN** entry is disabled for every mode with the reason that local progress could not be loaded, and no wipe is created

#### Scenario: During a raid
- **WHEN** the raid lifecycle phase is in raid and the player sets a trader's loyalty
- **THEN** the event is recorded

### Requirement: Shown values follow the store
The shown values SHALL be the current values of the mode's active wipe, read again after each entry, undo, log event, replay, new wipe or catalog change for that mode. Values of IDs the catalog no longer lists SHALL be kept in the store and not shown.

#### Scenario: Log event arrives
- **WHEN** the Your progress part is open on PvE and the logs record a task finished
- **THEN** that task shows finished from the game logs without reopening Settings

#### Scenario: New wipe
- **WHEN** the player starts a new PvE wipe
- **THEN** every PvE value shows unknown until set again or replayed

### Requirement: Consumers keep their current progress source
This change SHALL NOT switch keep/sell advice, raid timers or task state away from the Tracker token, and SHALL NOT change the token's requests or credentials.

#### Scenario: Advice unchanged
- **WHEN** the player sets their level by hand with a Tracker token saved
- **THEN** keep/sell advice uses the Tracker snapshot's level as before

#### Scenario: No token
- **WHEN** no Tracker token is saved and manual values exist
- **THEN** advice behaves as it does today without progress
