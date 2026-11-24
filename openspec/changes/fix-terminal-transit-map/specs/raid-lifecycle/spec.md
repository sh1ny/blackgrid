# Spec Delta

## MODIFIED Requirements

### Requirement: A raid records its map, mode, times and entry
A raid SHALL record its map (from the last scene loaded or rejoin location since the queue that named a supported map; a scene with no supported map SHALL NOT replace a map already known), its mode (the last session mode logged before it), its queue, start and end times from the log, and how it was entered: queue, transit or reconnect. The end SHALL record its cause: raid exit, menus or client restart.

#### Scenario: Recorded raid
- **WHEN** session mode PvpSeason, queue entered at 19:38:10, scene loaded on Lighthouse, raid started at 19:41:06 and raid exit at 19:54:20 are read
- **THEN** the raid has map Lighthouse, mode seasonal, queue time 19:38:10, start 19:41:06, end 19:54:20, entry queue and end cause raid exit

#### Scenario: Map unknown
- **WHEN** a raid starts after a scene-loaded event with no supported map
- **THEN** the raid's map is unknown and the phase is still in raid

#### Scenario: Unsupported scene after a transit keeps the transit map
- **WHEN** a raid on Shoreline ends by raid exit, then profile selected, raid rejoined with location Terminal, a scene-loaded event with no supported map and raid started are applied in the same session folder
- **THEN** a new raid starts on Terminal with entry transit

#### Scenario: Supported scene after a rejoin replaces the map
- **WHEN** raid rejoined with location Woods, then a scene-loaded event on Customs and raid started are applied
- **THEN** the raid's map is Customs

#### Scenario: Unknown rejoin and unsupported scene
- **WHEN** raid rejoined with a location Blackgrid does not know, then a scene-loaded event with no supported map and raid started are applied
- **THEN** the raid's map is unknown

#### Scenario: Unsupported scene in a queue after a known scene
- **WHEN** queue entered, a scene-loaded event on Customs, a scene-loaded event with no supported map and raid started are applied
- **THEN** the raid's map is Customs, and the second scene still publishes one map-known transition with no map
