# Spec Delta

## MODIFIED Requirements

### Requirement: Application log lines become lifecycle events
Blackgrid SHALL turn application log records into session mode, profile selected, queue entered, scene loaded, match found, server joined, raid starting, raid started, matching aborted and raid rejoined events, each recognised by its fixed message text. Any other record SHALL produce no event.

#### Scenario: Menu events
- **WHEN** the application log holds `Session mode: PvpSeason` and `PrepareSelectedProfileLocally ProfileId:<id> AccountId:<n>`
- **THEN** a session-mode event for seasonal and a profile-selected event are produced

#### Scenario: Rejoin line
- **WHEN** the application log holds `Transit reconnect status:MatchWait raidMode:Online location:bigmap settingsLocal:False`
- **THEN** a raid-rejoined event is produced with status MatchWait and map Customs

#### Scenario: Rejoin into Terminal or Labyrinth
- **WHEN** the application log holds `Transit reconnect status:MatchWait raidMode:Online location:Terminal settingsLocal:False`, or the same line with `location:terminal` or `location:Labyrinth`
- **THEN** a raid-rejoined event is produced whose map is Terminal for either Terminal spelling and Labyrinth for the Labyrinth line

#### Scenario: Every supported map can be rejoined
- **WHEN** a transit or reconnect line names the location of any supported map
- **THEN** the raid-rejoined event's map is that map, so no supported map is recorded as "Unknown map" when entered by transit or reconnect

#### Scenario: Rejoin into an unknown location
- **WHEN** the application log holds `Transit reconnect status:MatchWait raidMode:Online location:nowhere settingsLocal:False`
- **THEN** a raid-rejoined event is produced with location `nowhere` and no map

#### Scenario: A full raid in the application log
- **WHEN** the application log holds, in order, `Matching with group id: 6601208`, `scene preset path:maps/lighthouse_preset.bundle rcid:lighthouse.scenespreset.asset`, `MatchingCompleted:89.19 real:97.16 diff:7.97`, `TRACE-NetworkGameCreate profileStatus: 'Profileid: <id>, Status: Busy, RaidMode: Online, Location: Lighthouse, shortId: <id>'`, `GameStarting:150.37(26.13) real:164.48(26.56) diff:14.11` and `GameStarted:161.35(10.98) real:176.48(12) diff:15.12`
- **THEN** the events are queue entered, scene loaded on Lighthouse, match found, server joined, raid starting and raid started, in that order

#### Scenario: Matching cancelled
- **WHEN** the application log holds `Network game matching cancelled.`
- **THEN** one matching-aborted event is produced

#### Scenario: Unknown scene
- **WHEN** the application log holds `scene preset path:maps/unknown_place.bundle`
- **THEN** a scene-loaded event with no map is produced, and the map status says the current scene is unsupported

#### Scenario: Event map presets
- **WHEN** the application log holds `scene preset path:maps/factory_event_preset.bundle` or `scene preset path:maps/laboratory_event_preset.bundle`
- **THEN** the scene-loaded event's map is Factory or The Lab, and Factory or The Lab is the detected map

#### Scenario: Terminal and Labyrinth preset scenes
- **WHEN** the application log holds `scene preset path:maps/terminal_preset.bundle rcid:terminal.scenespreset.asset`, or the same line with `labyrinth_preset`
- **THEN** the scene-loaded event's map is Terminal, or Labyrinth for the Labyrinth line

#### Scenario: Unrelated line
- **WHEN** the application log holds `Reason:PacketsQueue, Position:(62.883, 10.690, -947.049), SpeedLimit:1.0595`
- **THEN** no event is produced
