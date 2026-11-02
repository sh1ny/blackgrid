# Spec Delta

## Purpose

Keeps the player's flea market sales and raids per map, read from the game's logs, in the local database only, counted once each across log replays and app restarts, shown per game mode and emptied on request.

## ADDED Requirements

### Requirement: Each raid start counts once for its map and mode
Each published raid start SHALL be stored once under its record identity, with its map, mode, start time and entry. Queue, transit and no-queue raids SHALL each count. Storing a raid start whose record identity is already stored SHALL change nothing. A raid with no known map SHALL count under "Unknown map".

#### Scenario: Two raids on one map
- **WHEN** two raid starts on Customs in PvP mode with different record identities are stored
- **THEN** the PvP raids-per-map totals show Customs: 2

#### Scenario: Transit counts as a new raid
- **WHEN** a raid on Woods ends and a transit raid on Customs starts
- **THEN** Woods and Customs each gain one raid

#### Scenario: Replay after a restart
- **WHEN** Blackgrid restarts and the same session folder publishes the same raid start again
- **THEN** the totals are unchanged

#### Scenario: Unknown map
- **WHEN** a raid start with no known map is stored
- **THEN** the totals show it under "Unknown map"

### Requirement: A reconnect continuing a counted raid does not count again
A raid start entered by reconnect SHALL NOT be counted when the newest stored raid of the same mode that started strictly before it is on the same map and started at most 2 hours before it. Raids stored with a later start SHALL NOT affect the decision, so a replay decides the same way. Any other reconnect SHALL count as a new raid.

#### Scenario: Both apps restarted mid-raid
- **WHEN** a PvP raid on Customs started at 20:00 is stored, and a reconnect raid start on Customs in PvP at 20:25 is published from a new session folder
- **THEN** Customs keeps 1 raid

#### Scenario: Reconnect on another map
- **WHEN** the newest stored PvP raid is on Woods and a reconnect raid start on Customs in PvP is published
- **THEN** Customs gains one raid

#### Scenario: Reconnect long after the last raid
- **WHEN** the newest stored PvP raid on Customs started 2 hours and 1 minute before a reconnect raid start on Customs in PvP
- **THEN** Customs gains one raid

#### Scenario: Reconnect with nothing stored
- **WHEN** no raid of that mode is stored and a reconnect raid start is published
- **THEN** its map gains one raid

#### Scenario: Replay of a skipped reconnect after a later raid
- **WHEN** a PvP Customs raid at 20:00 is stored, a reconnect on Customs at 20:25 is skipped, a PvP Woods raid at 21:00 is stored, and the session folder is replayed
- **THEN** Customs keeps 1 raid and Woods 1

### Requirement: Each flea sale counts once
Each published flea sale SHALL be stored once under its record identity with its mode, item, count and rouble payout. Storing a sale whose record identity is already stored SHALL change nothing.

#### Scenario: Two sales
- **WHEN** a PvP sale of 1 item for 30 000 roubles and a PvP sale of 3 items for 12 000 roubles are stored
- **THEN** the PvP flea totals show 2 sales, 4 items sold and 42 000 roubles

#### Scenario: Replayed sale
- **WHEN** the same sale record is published again after the log reader replays the folder
- **THEN** the flea totals are unchanged

#### Scenario: Sale not paid in roubles
- **WHEN** a sale with no rouble payout is stored
- **THEN** it counts as a sale and its items count, the rouble total is unchanged and the totals report 1 sale not paid in roubles

### Requirement: Raids and sales with no mode are kept apart
A raid start or flea sale with no known mode SHALL be stored under an unknown mode and SHALL NOT be added to the totals of any known mode.

#### Scenario: Sale before the mode is logged
- **WHEN** a flea sale with no mode is stored
- **THEN** the PvP and PvE flea totals are both unchanged

#### Scenario: Known mode
- **WHEN** a flea sale in PvE is stored
- **THEN** only the PvE flea totals change

### Requirement: Stats stay on this PC and survive a restart
Stats SHALL be stored only in the local database. After Blackgrid closes its database and opens it again, every mode's stored raids and sales SHALL read back with the same totals. Stats SHALL NOT be sent over the network.

#### Scenario: Restart
- **WHEN** 3 raids and 2 sales are stored, the database is closed and opened again
- **THEN** the totals are 3 raids and 2 sales

#### Scenario: Upgrade from an older database
- **WHEN** a database at the previous schema version with settings, pins and history is opened by this version
- **THEN** it opens with empty stats and the settings, pins and history read back unchanged

### Requirement: Clear empties stats and keeps them empty
Clearing SHALL delete every stored raid and sale of every mode and record the clear time, together, so that either both happen or neither does. A raid start or flea sale whose log time is at or before the last clear time SHALL NOT be stored. The clear time SHALL survive a restart.

#### Scenario: Clear
- **WHEN** PvP and PvE raids and sales are stored and Clear stats is confirmed
- **THEN** the totals of every mode are empty

#### Scenario: Replay after a clear and a restart
- **WHEN** stats are cleared at 21:00, Blackgrid restarts and the session folder replays raids and sales logged before 21:00
- **THEN** the totals stay empty

#### Scenario: New activity after a clear
- **WHEN** stats are cleared at 21:00 and a raid start logged at 21:10 is published
- **THEN** its map shows 1 raid

#### Scenario: Clear fails
- **WHEN** the clear cannot be written to the database
- **THEN** the stored stats and the previous clear time are unchanged and the dialog shows "Stats could not be cleared."

### Requirement: The Stats dialog shows the current mode's stats
A Stats button in the header SHALL open a dialog for the app's current mode showing flea sales, items sold, roubles earned and raids per map with their total, maps ordered by raid count. It SHALL show since when stats are counted: the last clear time, or "since stats began" when never cleared. With nothing stored for the mode it SHALL say "No raids or flea sales counted yet."

#### Scenario: Stats for the current mode
- **WHEN** the current mode is PvP with 3 Customs raids, 1 Woods raid and 2 sales, and the dialog opens
- **THEN** it shows Customs 3, then Woods 1, a total of 4 raids, and 2 flea sales, without PvE stats

#### Scenario: Empty stats
- **WHEN** the dialog opens for a mode with nothing stored
- **THEN** it shows "No raids or flea sales counted yet."

#### Scenario: Mode not known yet
- **WHEN** the dialog opens while the app's mode is unknown
- **THEN** it shows "Stats show once the game mode is known." and no totals, not those of raids and sales stored with no mode

#### Scenario: Mode changes while open
- **WHEN** the current mode changes from PvP to PvE while the dialog is open
- **THEN** the dialog shows the PvE stats

#### Scenario: New sale while open
- **WHEN** a sale is stored while the dialog is open
- **THEN** the shown sale count goes up by one

### Requirement: Clearing asks for confirmation
Clear stats SHALL ask "Clear the stats of every mode? This cannot be undone." and SHALL clear only when the player confirms.

#### Scenario: Confirmed
- **WHEN** the player presses Clear stats and confirms
- **THEN** the stats are cleared

#### Scenario: Cancelled
- **WHEN** the player presses Clear stats and cancels
- **THEN** nothing is deleted and the dialog shows the same totals

### Requirement: Stats failures are visible and contained
Read, write and clear failures SHALL each show their own message: "Stats could not be read." until the next successful read, "Some raids or sales could not be saved." until the next successful write, and "Stats could not be cleared." until the next successful clear or the dialog closes. One kind's success SHALL NOT remove another kind's message. No failure SHALL stop the raid state, timers or the rest of the app.

#### Scenario: Read fails
- **WHEN** reading the stats from the database fails
- **THEN** the dialog shows "Stats could not be read." and the raid timers keep updating

#### Scenario: Write fails
- **WHEN** storing a raid start fails
- **THEN** the dialog shows "Some raids or sales could not be saved." and the next raid start is still stored

#### Scenario: Write message survives a reload
- **WHEN** storing a raid start fails and the totals are then read again successfully
- **THEN** the dialog still shows "Some raids or sales could not be saved."

#### Scenario: Write message clears on the next write
- **WHEN** storing a raid start fails and the next sale is stored successfully
- **THEN** "Some raids or sales could not be saved." is no longer shown

#### Scenario: Clear message survives a reload
- **WHEN** a clear fails and the totals are then read again successfully
- **THEN** the dialog still shows "Stats could not be cleared."
