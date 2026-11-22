# Spec Delta

## Purpose

Lets the player opt in to having the game screenshots taken during a raid moved to the Windows Recycle Bin once that raid ends, so the screenshot folder does not fill up with the screenshots Blackgrid read positions from.

## ADDED Requirements

### Requirement: Screenshot cleanup is an opt-in setting
Screenshot cleanup SHALL be off by default. It SHALL be a saved setting that survives a restart, and a settings record without it SHALL load with cleanup off. While cleanup is off, no raid ending SHALL remove or move any file.

#### Scenario: Off by default
- **WHEN** Blackgrid starts with a settings record that has no cleanup setting and a raid then ends
- **THEN** cleanup reads as off and every file in the screenshot folder is still there

#### Scenario: The setting survives a restart
- **WHEN** the player switches cleanup on and Blackgrid restarts
- **THEN** cleanup reads as on

#### Scenario: Save fails
- **WHEN** saving the switch fails
- **THEN** the switch shows the setting in use, which is unchanged, and says it was not saved

### Requirement: Only a fresh raid ending starts a cleanup
A cleanup SHALL start only from a raid-ended transition that is fresh under the alerts' freshness rule, received while cleanup is on. A raid ended by a client restart SHALL be judged by the time of the queue entry published with its ending, not by the ending's own time. Each raid SHALL be cleaned up at most once, matched by the record identity of its start. A replayed or stale raid ending, a raid ended before cleanup was switched on, and a queue that ended without a raid SHALL start no cleanup.

#### Scenario: A live raid ends
- **WHEN** cleanup is on and a fresh raid-ended transition arrives
- **THEN** a cleanup of that raid's screenshots starts

#### Scenario: A raid ended by a client restart
- **WHEN** cleanup is on, the game restarted during a raid, the player reached the menus at 14:40:00 and entered the queue at 14:45:00, and the ending arrives while the clock reads 14:45:01
- **THEN** a cleanup of that raid's screenshots starts

#### Scenario: Replay at start-up
- **WHEN** cleanup is on and Blackgrid starts and replays a session folder whose raids ended an hour ago
- **THEN** no cleanup starts and no file is moved

#### Scenario: Switched on after the raid ended
- **WHEN** a raid ends while cleanup is off and the player then switches cleanup on
- **THEN** no cleanup starts for that raid

#### Scenario: Matching aborted
- **WHEN** cleanup is on and a queue ends without a raid
- **THEN** no cleanup starts

#### Scenario: The same raid ends again
- **WHEN** a raid-ended transition arrives for a raid that was already cleaned up
- **THEN** no second cleanup starts

### Requirement: A raid's screenshots are picked by folder, name and time
A cleanup SHALL take a file only when it is a regular file directly in the screenshot folder in use when the cleanup starts, not in a subfolder and not reached through a link; its extension is `.png`, `.jpg` or `.jpeg` in any case; its name parses as a game screenshot name; and its modified time is at or after the raid's start and at or before its end. No other file SHALL be moved or changed.

#### Scenario: A screenshot from the raid
- **WHEN** a raid ran from 14:00:00 to 14:30:00 and the folder holds `2026-11-22[14-05]_-120.5, 2.1, 33.4_0, 0.70711, 0, 0.70711_12.34.png` modified at 14:05:10
- **THEN** that file is moved to the Recycle Bin

#### Scenario: Screenshots outside the raid window
- **WHEN** the folder holds game-named screenshots modified at 13:59:59 and at 14:30:01 for that raid
- **THEN** both files stay where they are

#### Scenario: Files that are not game screenshots
- **WHEN** the folder holds `notes.png`, `2026-11-22[14-05]_renamed.png`, `shot.bmp` and a subfolder with a game-named screenshot, all modified during the raid
- **THEN** none of them is moved

#### Scenario: A link to a file elsewhere
- **WHEN** the folder holds a link with a game screenshot name, modified during the raid, that points to a file outside the folder
- **THEN** neither the link nor its target is moved

#### Scenario: The folder changed during the raid
- **WHEN** the player changes the screenshot folder during a raid and the raid then ends
- **THEN** only the new folder is searched and the old folder is unchanged

### Requirement: Screenshots go to the Recycle Bin, never deleted for good
A cleanup SHALL move each picked file to the Windows Recycle Bin. A file the Recycle Bin cannot take SHALL stay where it is and count as not moved; cleanup SHALL NOT delete any file permanently. A file that cannot be moved SHALL NOT stop the others from being moved.

#### Scenario: Every file moves
- **WHEN** a cleanup picks three screenshots and the Recycle Bin takes all three
- **THEN** the three files are gone from the folder and are in the Recycle Bin

#### Scenario: The Recycle Bin cannot take a file
- **WHEN** the screenshot folder is on a drive with no Recycle Bin
- **THEN** every picked file stays in the folder and the cleanup counts them as not moved

#### Scenario: The recycle call fails
- **WHEN** a cleanup sends its picked screenshots and the move call fails as a whole
- **THEN** every file of that call stays in the folder, counts as not moved, and the result line says how many could not be moved

#### Scenario: The recycle call does not answer
- **WHEN** a cleanup sends its picked screenshots and no answer comes within the time limit
- **THEN** no further file of that raid is sent, the move is told to stop before its next file, and the result line says how many screenshots could not be confirmed as moved

#### Scenario: One file is locked
- **WHEN** a cleanup picks three screenshots and one is open in another program
- **THEN** the other two are moved and the locked one stays and counts as not moved

#### Scenario: A file vanished before the move
- **WHEN** the player deletes a picked screenshot before the cleanup moves it
- **THEN** the cleanup counts it neither as moved nor as not moved and moves the rest

### Requirement: Cleanups run one at a time
Cleanups SHALL run one after another in the order their raids ended. Switching cleanup off SHALL start no further cleanup; one already moving files SHALL finish. Closing Blackgrid SHALL stop starting new moves and SHALL leave every file not yet moved where it is. At most 4 cleanups SHALL wait; a raid ending beyond that SHALL start no cleanup and the next result line SHALL say a raid was skipped.

#### Scenario: Two raids end close together
- **WHEN** a transit raid ends and the next raid ends before the first cleanup has finished
- **THEN** the second cleanup starts after the first has finished, and each moves only its own raid's screenshots

#### Scenario: Switched off while a cleanup waits
- **WHEN** a cleanup is waiting behind another and the player switches cleanup off
- **THEN** the waiting cleanup does not start

#### Scenario: Blackgrid closes during a cleanup
- **WHEN** Blackgrid closes while a cleanup is moving files
- **THEN** the move stops before its next file and files not yet moved stay in the folder

#### Scenario: Too many cleanups waiting
- **WHEN** 4 cleanups are waiting and a fifth raid ends
- **THEN** that raid's screenshots stay in the folder and the next result line says a raid was skipped

### Requirement: The last cleanup's result is shown
After each cleanup the setting SHALL show one line with its result: how many screenshots it moved to the Recycle Bin, how many could not be moved when any could not, or that the raid had no screenshots. A missing or unreadable folder SHALL show that the folder could not be read. Before the first cleanup since Blackgrid started, no line SHALL show.

#### Scenario: Screenshots moved
- **WHEN** a cleanup moves 12 screenshots
- **THEN** the line reads "Moved 12 screenshots from the last raid to the Recycle Bin."

#### Scenario: Some could not be moved
- **WHEN** a cleanup moves 10 screenshots and 2 cannot be moved
- **THEN** the line says 10 were moved and 2 could not be moved and are still in the folder

#### Scenario: No screenshots in the raid
- **WHEN** a cleanup finds no screenshot of the raid
- **THEN** the line reads "The last raid had no screenshots to move."

#### Scenario: The folder is missing
- **WHEN** a cleanup starts and the screenshot folder does not exist
- **THEN** no file is moved and the line says the screenshot folder could not be read

#### Scenario: Nothing yet
- **WHEN** Blackgrid has started and no cleanup has run
- **THEN** no result line shows under the switch
