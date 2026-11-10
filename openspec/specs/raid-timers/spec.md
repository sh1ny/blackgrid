# raid-timers Specification

## Purpose
Shows the player's raid timers in Blackgrid's own window: time in raid, the run-through countdown and the scav cooldown, worked out from the game's log times, the item data, the player's Fence reputation and their Tracker hideout progress, never drawn on the game screen.

## Requirements

### Requirement: Time in raid counts from the raid's log start
While a raid is current, time in raid SHALL be the current time minus the raid's start time from the log, never below zero. When the raid ends, it SHALL freeze at end minus start and SHALL be shown as the last raid's time until the next raid starts. A reconnect SHALL keep the raid's start; a transit SHALL start a new count.

#### Scenario: Raid in progress
- **WHEN** a raid started at 19:41:06 is current and the clock reads 19:53:40
- **THEN** time in raid is 12:34

#### Scenario: Blackgrid restarted mid-raid
- **WHEN** Blackgrid starts at 20:10:00, the replay of the session folder finds a current raid started at 19:41:06, and no tick has run yet
- **THEN** time in raid is 28:54, not 0:00

#### Scenario: Raid ended
- **WHEN** a raid started at 19:41:06 ended at 20:05:00 and the clock reads 20:30:00
- **THEN** the last raid's time is 23:54 and it does not change while the clock moves

#### Scenario: Reconnect continues the count
- **WHEN** a raid started at 21:00:00 is interrupted by a client restart and continued by a reconnect at 21:12:00, and the clock reads 21:20:00
- **THEN** time in raid is 20:00

#### Scenario: Log time ahead of the clock
- **WHEN** a current raid's start time is 10 s after the clock's time
- **THEN** time in raid is 0:00

#### Scenario: No raid known
- **WHEN** no raid has started since the log input was bound
- **THEN** no time in raid is shown, only a dash

### Requirement: The run-through countdown runs while the raid is current
While a raid is current, the run-through countdown SHALL be the run-through length minus time in raid, and SHALL stop at 0:00 and then show as done. It SHALL be shown only while a raid is current. The run-through length SHALL be a setting between 1:00 and 30:00 in whole seconds, 7:10 by default.

#### Scenario: Counting down
- **WHEN** the run-through length is 7:10 and time in raid is 2:00
- **THEN** the run-through countdown shows 5:10

#### Scenario: Past the run-through length
- **WHEN** the run-through length is 7:10 and time in raid is 9:00
- **THEN** the run-through countdown shows as done and never a negative time

#### Scenario: Raid ended before the length
- **WHEN** a raid ends with time in raid 4:00 and the run-through length 7:10
- **THEN** no run-through countdown is shown, only a dash

#### Scenario: Length changed mid-raid
- **WHEN** time in raid is 3:00 and the run-through length is changed from 7:10 to 10:00
- **THEN** the countdown shows 7:00 at once

### Requirement: A scav raid's end starts that mode's scav cooldown
A raid SHALL count as a scav raid when its mode is PvE, or when its guessed side is scav. When a scav raid ends, by any cause, the scav cooldown for the raid's mode SHALL start at the raid's end time from the log. A raid with an unknown mode SHALL start no cooldown.

#### Scenario: Scav raid ends
- **WHEN** a raid in seasonal mode with guessed side scav ends at 20:05:00
- **THEN** the seasonal scav cooldown starts at 20:05:00

#### Scenario: PMC raid ends
- **WHEN** a raid in PvP mode with guessed side PMC ends
- **THEN** no scav cooldown starts and a running PvP cooldown is unchanged

#### Scenario: PvE raid ends
- **WHEN** a raid in PvE mode with guessed side PMC ends at 18:00:00
- **THEN** the PvE scav cooldown starts at 18:00:00

#### Scenario: Unknown mode
- **WHEN** a scav raid with no recorded mode ends
- **THEN** no scav cooldown starts for any mode

#### Scenario: Ended by client restart
- **WHEN** a scav raid ends with cause client restart at 23:15:20
- **THEN** that mode's scav cooldown starts at 23:15:20

### Requirement: A cooldown start is never moved back or started twice
A mode's cooldown start SHALL change only to a later end time. A raid ending with an end time at or before the stored start for its mode SHALL change nothing, so a replay of the same session folder after a restart SHALL leave the cooldown as it was.

#### Scenario: Replay after restart
- **WHEN** the seasonal cooldown start of 20:05:00 is stored, Blackgrid restarts and the replay publishes the same raid ending at 20:05:00 again
- **THEN** the seasonal cooldown start stays 20:05:00 and nothing is saved

#### Scenario: Older folder replayed
- **WHEN** the stored PvP cooldown start is 22:00:00 and a scav raid ending at 19:00:00 is read
- **THEN** the PvP cooldown start stays 22:00:00

#### Scenario: Settings saved from older values
- **WHEN** a seasonal cooldown start of 20:05:00 is recorded and then a settings change made from values read before it is saved
- **THEN** the stored seasonal cooldown start is still 20:05:00

#### Scenario: Newer scav raid
- **WHEN** the stored PvP cooldown start is 19:00:00 and a scav raid ending at 21:30:00 is read
- **THEN** the PvP cooldown start becomes 21:30:00

### Requirement: The scav cooldown length comes from item data, Fence reputation and hideout progress
The cooldown length for a mode SHALL be that mode's base scav cooldown from item data, times the modifier of the Fence reputation level with the highest minimum at or below the player's Fence reputation (the lowest level when it is below all), times one plus the sum of the scav-cooldown bonuses of the hideout levels built (each a negative fraction), rounded to whole seconds and never below zero.

#### Scenario: Neutral reputation, no bonus
- **WHEN** the base is 1500 s, the Fence reputation is 0.00 with modifier 1, and no hideout level with a scav-cooldown bonus is built
- **THEN** the cooldown length is 25:00

#### Scenario: Reputation and hideout bonuses
- **WHEN** the base is 1500 s, the Fence reputation is 2.50 (levels at 2 with modifier 0.8 and 3 with modifier 0.7), and Intelligence Center levels 1 (−0.15) and 3 (−0.2) are built
- **THEN** the cooldown length is 13:00 (1500 × 0.8 × 0.65 = 780 s)

#### Scenario: Reputation below every level
- **WHEN** the lowest reputation level has minimum −7 and modifier 6 and the Fence reputation is −7.00
- **THEN** the modifier 6 is used

#### Scenario: Item data has no cooldown inputs
- **WHEN** the mode's catalog has no base scav cooldown or no Fence reputation levels
- **THEN** the cooldown length is unknown and the scav entry shows "unknown" with a reason

### Requirement: Built hideout levels come from Tracker progress for the same mode
A hideout level SHALL count as built only when the Tracker progress for the cooldown's mode marks that level complete. Without Tracker progress for that mode, no bonus SHALL apply and the scav entry SHALL say the length has no hideout bonuses. Progress that is no longer current SHALL still be used.

#### Scenario: Progress for the mode
- **WHEN** PvP progress marks Intelligence Center level 1 complete
- **THEN** the PvP cooldown length includes its −0.15 bonus

#### Scenario: Progress for another mode
- **WHEN** only PvE progress is loaded and the PvP cooldown is shown
- **THEN** no hideout bonus applies to the PvP length and the scav entry says it has no hideout bonuses

#### Scenario: Stale progress
- **WHEN** the PvP progress is older than 15 minutes and marks Intelligence Center level 3 complete
- **THEN** the PvP cooldown length still includes the level 3 bonus

### Requirement: The scav cooldown counts down to ready
The scav cooldown shown SHALL be the active mode's (the mode detected from the game's logs, else the mode chosen in Settings): the start plus the length, minus the current time. It SHALL show the remaining time while above zero and "ready" once it reaches zero or when that mode has no start. A change of reputation, item data or progress SHALL change the remaining time at once.

#### Scenario: Counting down
- **WHEN** the seasonal start is 20:05:00, the length is 25:00 and the clock reads 20:20:30
- **THEN** the scav entry shows 9:30

#### Scenario: Ready
- **WHEN** the seasonal start is 20:05:00, the length is 25:00 and the clock reads 20:31:00
- **THEN** the scav entry shows ready

#### Scenario: Reputation changed while counting
- **WHEN** the scav entry shows 9:30 with modifier 1 and the Fence reputation is raised to a level with modifier 0.8
- **THEN** the scav entry shows 4:30 at the next display update

#### Scenario: Mode switched
- **WHEN** a seasonal cooldown is running and the active mode changes to PvE, which has no start
- **THEN** the scav entry shows ready for PvE and the seasonal start is kept

#### Scenario: Mode from the logs
- **WHEN** the mode chosen in Settings is unknown, the logs detect PvP, and a PvP cooldown is running
- **THEN** the scav entry shows the PvP countdown

#### Scenario: No mode known
- **WHEN** the logs detect no mode and no mode is chosen in Settings
- **THEN** the scav entry shows "unknown" with the reason that no mode is known

### Requirement: Timer displays follow the clock, not a tick count
Every shown timer SHALL be computed from the current clock reading and the stored times, and SHALL update at least once per second while any shown timer is moving. A late or missed update SHALL NOT make a timer drift.

#### Scenario: Missed ticks
- **WHEN** a raid started at 19:41:06 is current and the display updates at 19:42:00 and then not again until 19:45:00
- **THEN** the display shows 3:54 at 19:45:00

#### Scenario: Nothing moving
- **WHEN** no raid is current and the active mode's scav cooldown is ready
- **THEN** no periodic update runs

### Requirement: Timers show in a strip in Blackgrid's window only
A timer strip under the shell header SHALL show, on both Map and Scanner, each timer that is on, labelled "In raid", "Last raid", "Run-through" and "Scav". Times SHALL read m:ss under an hour and h:mm:ss from an hour. The strip SHALL be hidden when the timers are off or none is chosen. Nothing SHALL be drawn outside Blackgrid's window.

#### Scenario: All timers on in a raid
- **WHEN** all timers are on, time in raid is 12:34, the run-through countdown is 0:00 and the scav cooldown is ready
- **THEN** the strip shows "In raid 12:34", "Run-through done" and "Scav ready" on Map, and the same on Scanner

#### Scenario: Long raid
- **WHEN** time in raid is 1 h 2 min 5 s
- **THEN** the strip shows "In raid 1:02:05"

#### Scenario: Timers off
- **WHEN** the timers are turned off
- **THEN** no timer strip is shown on Map or Scanner and no periodic update runs

#### Scenario: Only the scav cooldown chosen
- **WHEN** the timers are on and only the scav cooldown is chosen
- **THEN** the strip shows only the scav entry

### Requirement: Timer settings live on the Settings page
A "Raid timers" section on the Settings page SHALL set: timers on or off (on by default), which of time in raid, run-through and scav cooldown show (all by default), the run-through length (m:ss) and the Fence reputation for the active mode (−7.00 to 6.00, two decimals, 0.00 by default). An invalid entry SHALL be refused with a message and SHALL keep the previous value.

#### Scenario: Valid run-through length
- **WHEN** the run-through length "8:00" is entered
- **THEN** the run-through length becomes 8:00

#### Scenario: Invalid run-through length
- **WHEN** "0:30", "31:00" or "abc" is entered as the run-through length
- **THEN** a message says the length must be between 1:00 and 30:00 and the previous length is kept

#### Scenario: Fence reputation out of range
- **WHEN** "7.5" is entered as the Fence reputation
- **THEN** a message says the reputation must be between −7.00 and 6.00 and the previous value is kept

#### Scenario: Reputation for the detected mode
- **WHEN** the mode chosen in Settings is unknown, the logs detect PvP, and "2.50" is entered as the Fence reputation
- **THEN** the PvP Fence reputation becomes 2.50

#### Scenario: No mode known
- **WHEN** the logs detect no mode and no mode is chosen in Settings
- **THEN** the Fence reputation field is disabled with a note to choose a mode first

### Requirement: Timer settings and cooldown starts survive restart
The timer settings, each mode's Fence reputation and each mode's cooldown start SHALL be stored in the local settings record and SHALL be restored at startup. A stored record without them SHALL load with the defaults and no cooldown start. A failed save SHALL keep the previous stored value and report the failure as other settings saves do.

#### Scenario: Restart restores everything
- **WHEN** the run-through length is 8:00, the seasonal Fence reputation is 3.20, a seasonal cooldown started at 20:05:00, and Blackgrid restarts
- **THEN** the run-through length is 8:00, the seasonal Fence reputation is 3.20 and the seasonal cooldown start is 20:05:00

#### Scenario: Record from an older version
- **WHEN** the stored settings record has no timer fields
- **THEN** the timers are on, all three show, the length is 7:10, every Fence reputation is 0.00 and no mode has a cooldown start

#### Scenario: Save fails
- **WHEN** saving a new cooldown start fails
- **THEN** the countdown still runs for this app run, the stored start is unchanged, and the settings save error is shown

#### Scenario: Stored settings unreadable
- **WHEN** the stored settings record could not be read and the replay publishes a scav raid ending
- **THEN** the cooldown runs, nothing is saved, and the notice that default settings are in use stays until the user changes a setting
