# Spec Delta

## ADDED Requirements

### Requirement: Local progress holds a Your progress part
The Local progress section SHALL hold, after the wipe rows, a Your progress part for the app's effective mode, named in its title, with no mode choice of its own. It SHALL show the player's level, faction and edition, then trader loyalty, hideout stations and task search, each value with its set, clear and undo or redo actions. The section order SHALL NOT change.

#### Scenario: Shows the effective mode
- **WHEN** the app's effective mode is PvE and the player opens Local progress
- **THEN** Your progress is titled for PvE and shows PvE's values

#### Scenario: Effective mode changes while open
- **WHEN** the game's detected session mode changes from PvE to PvP while Your progress is open
- **THEN** it shows PvP's values, and an entry submitted while PvE was shown is recorded in PvE, never in PvP

#### Scenario: Unknown mode
- **WHEN** the effective mode is unknown
- **THEN** Your progress says to choose a game mode and offers no entry

#### Scenario: Mode without a wipe
- **WHEN** the chosen mode has no wipe
- **THEN** every value shows unknown and the part says the first entry starts a wipe, dated today or the current game session's date when that is earlier

### Requirement: Your progress values show their source
Each value SHALL show "From game logs" when its current winner is a log event, "Set by hand" when it is a manual event, and nothing when it is unknown. A failure SHALL show beside the value it concerns.

#### Scenario: Source shown
- **WHEN** task Debut was finished from the logs and level was set by hand
- **THEN** Debut shows "From game logs" and the level shows "Set by hand"

#### Scenario: Failure shown
- **WHEN** setting a station level fails with a storage failure
- **THEN** the station's row shows that failure and its previous value
