# Spec Delta

## Purpose

Speaks short alerts in Blackgrid's own audio when something in the player's raid needs attention: a match found, a raid starting, a timer reaching zero, or a reminder before or after a raid. Each alert has its own switch, a choice of sound and a test button.

## ADDED Requirements

### Requirement: The alerts and their spoken lines
Blackgrid SHALL offer eight alerts, each with a fixed spoken line: match found ("Match found"), raid starting ("Raid starting"), run-through over ("Run-through over"), scav ready ("Scav ready"), air filter on ("Air filter on"), air filter off ("Air filter off"), quest items ("Check your quest items") and failed tasks ("Restart failed tasks").

#### Scenario: Spoken line of an alert
- **WHEN** the scav ready alert plays with the speech sound
- **THEN** the voice says "Scav ready"

#### Scenario: Unknown alert in stored settings
- **WHEN** the stored settings name an alert that is not one of the eight
- **THEN** that entry is ignored, the eight alerts load with their stored or default values, and the record loads without a load notice

### Requirement: Match found and raid starting fire from the raid lifecycle
The match found alert SHALL fire on a match-found transition and the raid starting alert on a raid-starting transition, each at most once per transition identity.

#### Scenario: A queue to a raid
- **WHEN** a queue entered, match found, raid starting and raid started are read live, with both alerts on
- **THEN** "Match found" plays once, then "Raid starting" plays once

#### Scenario: Raid with no countdown
- **WHEN** match found is followed directly by raid started
- **THEN** "Match found" plays and "Raid starting" does not

#### Scenario: Same transition delivered twice
- **WHEN** a match-found transition with an identity that already fired an alert arrives again
- **THEN** no alert plays

### Requirement: Run-through over fires when the countdown reaches zero
The run-through over alert SHALL fire once per raid when the run-through countdown reaches 0:00 while that raid is current and Blackgrid is open.

#### Scenario: Countdown reaches zero
- **WHEN** a raid is current, the run-through length is 7:10 and the clock moves from 7:09 to 7:10 after the raid's start
- **THEN** "Run-through over" plays once, and not again later in the same raid

#### Scenario: Raid ends first
- **WHEN** the raid ends at 5:00 after its start, with a run-through length of 7:10
- **THEN** the run-through over alert does not play for that raid

#### Scenario: Already over at startup
- **WHEN** Blackgrid starts while a raid is current whose run-through countdown is already 0:00
- **THEN** the run-through over alert does not play for that raid

### Requirement: Scav ready fires when the active mode's cooldown reaches ready
The scav ready alert SHALL fire once per cooldown start when the active mode's scav cooldown moves from a remaining time above zero to ready while Blackgrid is open.

#### Scenario: Cooldown runs out
- **WHEN** the active mode's cooldown shows 0:01 and the clock moves past its end
- **THEN** "Scav ready" plays once

#### Scenario: Ready at startup
- **WHEN** Blackgrid starts and the active mode's scav cooldown is already ready
- **THEN** the scav ready alert does not play

#### Scenario: Mode switch to a ready mode
- **WHEN** the active mode changes from one with a running cooldown to one whose cooldown is ready
- **THEN** the scav ready alert does not play

#### Scenario: Progress loads after startup
- **WHEN** Blackgrid starts while progress is still loading, the cooldown shows time left without hideout bonuses, and the loaded progress makes it ready
- **THEN** the scav ready alert does not play

### Requirement: Air filter reminders follow the queue and the raid's end
The air filter on alert SHALL fire on a queue-entered transition, and the air filter off alert on a raid-ended transition whose cause is not a client restart. Each SHALL fire only when the local progress of the active mode records the Air Filtering Unit at level 1 or higher.

#### Scenario: Unit built
- **WHEN** the Air Filtering Unit is recorded built, both air filter alerts are on, and a queue entered and later a raid ended are read live
- **THEN** "Air filter on" plays at the queue and "Air filter off" plays at the raid's end

#### Scenario: Raid ended by a client restart
- **WHEN** the unit is built and a raid ends with cause client restart as the next queue is entered
- **THEN** "Air filter off" does not play, and "Air filter on" plays once for the queue

#### Scenario: Unit not built
- **WHEN** local progress records no level for the Air Filtering Unit
- **THEN** neither air filter alert plays

#### Scenario: Progress unavailable
- **WHEN** the active mode's local progress cannot be read
- **THEN** neither air filter alert plays, and the Alerts section says the air filter reminders wait for local progress

### Requirement: Quest items reminder fires once per queue for item objectives on the map
The quest items alert SHALL fire at most once per queue, on the map-known transition, when a started task has an objective that is not done, is of type plant item, plant quest item, mark or hand over quest item, and is on that map. It SHALL NOT read or guess the player's inventory.

#### Scenario: A plant objective on the queued map
- **WHEN** a started task has an unfinished plant-item objective on Customs and the map known while queuing is Customs
- **THEN** "Check your quest items" plays once for that queue

#### Scenario: Objective already done
- **WHEN** the only matching objective on the queued map is done
- **THEN** the quest items alert does not play

#### Scenario: Map changes in the same queue
- **WHEN** a second map-known transition arrives in the same queue after the alert already played
- **THEN** the quest items alert does not play again

#### Scenario: Unknown map
- **WHEN** the map-known transition names no supported map
- **THEN** the quest items alert does not play

#### Scenario: Map or quest data unavailable
- **WHEN** the queued map's quest-data identity, the quest data or the active mode's local progress is unavailable
- **THEN** the quest items alert does not play, and the Alerts section says the quest items reminder waits for map, quest or progress data

### Requirement: Failed tasks reminder waits for the menus
When a fresh task-failed transition names a task that the quest data marks restartable, the failed tasks alert SHALL fire once as soon as the phase is in menus with no raid current, however many such tasks failed since. The alert SHALL never fire while a raid is current, including an interrupted raid that can still be rejoined.

#### Scenario: Failure mid-raid
- **WHEN** a restartable task fails during a raid and the player later returns to the menus
- **THEN** "Restart failed tasks" plays once on the return to the menus, not during the raid

#### Scenario: Failure that cannot be restarted
- **WHEN** a failed task is not marked restartable, or is unknown to the quest data
- **THEN** the failed tasks alert does not play for it

#### Scenario: Two failures in one raid
- **WHEN** two restartable tasks fail in the same raid
- **THEN** "Restart failed tasks" plays once on the return to the menus

#### Scenario: Failure read while in menus
- **WHEN** a restartable task's failure is read fresh while the player is in the menus with no current raid
- **THEN** "Restart failed tasks" plays once, at once

#### Scenario: Client restart mid-raid
- **WHEN** a restartable task failed in a raid and the game client restarts to the menus while that raid can still be rejoined
- **THEN** the alert does not play until that raid has ended and the player is in the menus

### Requirement: Only fresh log events fire alerts
An alert from a log transition SHALL fire only when the transition's log time is no more than 30 s before the clock reading at the moment the transition is read. Older transitions, such as those replayed when Blackgrid starts or a log folder is read again, SHALL fire nothing.

#### Scenario: Live event
- **WHEN** a match-found transition logged 2 s ago is read
- **THEN** the match found alert plays

#### Scenario: Replay at startup
- **WHEN** Blackgrid starts and reads today's session folder, which holds a match found logged 20 minutes ago
- **THEN** no alert plays for it

#### Scenario: Log time in the future
- **WHEN** a transition's log time is later than the clock reading
- **THEN** it counts as fresh and its alert plays

### Requirement: Each alert has a switch
Each alert SHALL have its own on/off switch. Match found, raid starting, run-through over and scav ready SHALL be on by default, and air filter on, air filter off, quest items and failed tasks SHALL be off by default. An alert that is off SHALL NOT play from its event.

#### Scenario: Defaults
- **WHEN** Blackgrid starts with no stored alert settings
- **THEN** match found, raid starting, run-through over and scav ready are on, and the other four are off

#### Scenario: Alert off
- **WHEN** the match found alert is off and a fresh match-found transition is read
- **THEN** no alert plays

### Requirement: Each alert plays speech or the player's sound file
Each alert's sound SHALL be either Windows speech, which says its line, or a WAV or MP3 file the player chose. Speech SHALL be the default. When a chosen file is missing or fails to play, the alert SHALL say its line instead, and the Alerts section SHALL show the problem under that alert's row.

#### Scenario: Custom file
- **WHEN** the raid starting alert has a readable custom MP3 and fires
- **THEN** that file plays and no speech plays

#### Scenario: File removed
- **WHEN** the raid starting alert's custom file has been deleted and the alert fires
- **THEN** the voice says "Raid starting", and the row shows that the sound file could not be played

#### Scenario: Unsupported file chosen
- **WHEN** the player chooses a file that is not WAV or MP3
- **THEN** the choice is refused with a message, and the previous sound is kept

#### Scenario: File choice cancelled
- **WHEN** the player opens the Windows file dialog for an alert's sound and cancels it
- **THEN** the alert keeps its previous sound and no message shows

### Requirement: Alerts play one at a time
Alerts SHALL play in the order they fired, one at a time, never overlapping. An alert that has waited more than 15 s without starting SHALL be dropped. At most 8 alerts SHALL wait at once; an alert firing while 8 wait SHALL be dropped.

#### Scenario: Two alerts close together
- **WHEN** match found and raid starting fire 1 s apart
- **THEN** "Match found" finishes before "Raid starting" begins

#### Scenario: Stale alert
- **WHEN** an alert has waited 16 s behind a long custom sound
- **THEN** it is dropped without playing

### Requirement: Playback failures stay visible and never stop the alerts
When speech or playback fails, the alert SHALL be dropped, the next waiting alert SHALL play, and the Alerts section SHALL show the last playback failure in plain words until a later alert plays successfully.

#### Scenario: Speech unavailable
- **WHEN** Windows speech fails for one alert
- **THEN** the Alerts section shows that the alert could not be spoken, and the next alert still plays

#### Scenario: Recovery
- **WHEN** a later alert plays successfully
- **THEN** the playback failure message is cleared

### Requirement: One voice for all spoken alerts
The Alerts section SHALL let the player choose the voice used for every spoken alert from the voices installed in Windows, with "Windows default" first and selected by default. It SHALL also offer speed and volume, a preview that speaks a sample line, and a "Get more voices" action that opens Windows' speech settings.

#### Scenario: Voice list
- **WHEN** the Alerts section opens on a machine with the voices Zira, David and Mark
- **THEN** the voice choice lists "Windows default", then Zira, David and Mark

#### Scenario: Saved voice uninstalled
- **WHEN** the saved voice is no longer installed
- **THEN** spoken alerts use the Windows default voice, the saved choice is kept, and the voice row says the saved voice is not installed

#### Scenario: No voices listed
- **WHEN** Windows reports no installed voices or the list cannot be read
- **THEN** the voice choice offers only "Windows default", and the row says the voice list is unavailable

### Requirement: Speed and volume stay in range
Speed SHALL be a whole step from −5 to 5, 0 by default, and volume a whole percentage from 0 to 100, 100 by default. Both SHALL apply to speech; volume SHALL also apply to custom files.

#### Scenario: Volume applies to files
- **WHEN** volume is 50 and an alert plays a custom file
- **THEN** the file plays at half volume

#### Scenario: Out-of-range stored value
- **WHEN** the stored speed is 9
- **THEN** speed loads as 5, the nearest value in range

### Requirement: Each alert has a test button
Each alert's row SHALL have a test button that plays that alert's sound with the current voice, speed and volume, whether the alert is on or off and whatever the raid state. A test SHALL wait in the same queue as other alerts.

#### Scenario: Test an alert that is off
- **WHEN** the quest items alert is off and the player presses its test button
- **THEN** "Check your quest items" plays

#### Scenario: Test while another alert plays
- **WHEN** the player presses a test button while an alert is playing
- **THEN** the test plays after the current alert finishes

### Requirement: Alert settings survive restart
Each alert's switch and sound, the voice, speed and volume SHALL be stored in the local settings record and restored at startup. A record without them SHALL load the defaults. A failed save SHALL keep the previous stored value and report the failure as other settings saves do.

#### Scenario: Restart keeps choices
- **WHEN** the player turns the quest items alert on, chooses a custom file for scav ready and sets volume 70, then restarts Blackgrid
- **THEN** the quest items alert is on, scav ready uses that file, and volume is 70

#### Scenario: Older record
- **WHEN** a settings record saved before alerts existed is loaded
- **THEN** every alert has its default switch and speech sound, the voice is "Windows default", speed is 0 and volume is 100

#### Scenario: Save fails
- **WHEN** saving the volume change fails
- **THEN** the previous stored volume stays in effect and the failure shows under the volume row

### Requirement: Alerts never touch the game
Alerts SHALL play only through Blackgrid's own audio output. They SHALL NOT draw on the game screen, focus the game, send it input or read its memory.

#### Scenario: Alerts use only the audio channel
- **WHEN** every alert fires once and every test button is pressed, with a recording fake audio port
- **THEN** the only native calls made are the audio channel's own methods, and none of them names a window other than Blackgrid's

#### Scenario: An alert while the game has focus
- **WHEN** an alert fires while the game window has focus
- **THEN** the alert plays, and the game window keeps focus
