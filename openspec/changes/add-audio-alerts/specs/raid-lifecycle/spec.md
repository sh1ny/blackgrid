# Spec Delta

## ADDED Requirements

### Requirement: Queue progress transitions are published once
Each queue entered, match found and raid starting event SHALL publish one transition of that kind, and each scene loaded event read while the phase is in queue, match found or raid starting, after a queue entered and before any raid rejoined since, SHALL publish one map-known transition with the map, or no map when it is not a supported map. Each SHALL carry the record identity and time of its event, and a re-read SHALL publish them with the same identities.

#### Scenario: Queue to raid
- **WHEN** the events are queue entered, scene loaded on Customs, match found, raid starting and raid started
- **THEN** one queue-entered, one map-known with Customs, one match-found, one raid-starting and one raid-started transition are published, in that order

#### Scenario: Scene outside a queue
- **WHEN** a scene loaded event is read while the phase is in menus
- **THEN** no map-known transition is published

#### Scenario: Rejoin publishes no map-known
- **WHEN** a raid rejoined event is read
- **THEN** no map-known transition is published for it

#### Scenario: Scene after a rejoin
- **WHEN** a raid rejoined event for a transit is followed by a scene loaded event while the phase is raid starting
- **THEN** no map-known transition is published

#### Scenario: Unsupported scene
- **WHEN** a scene loaded event for a scene that is not a supported map is read while in queue
- **THEN** one map-known transition with no map is published

#### Scenario: Re-read after restart
- **WHEN** the app restarts and reads the same session folder again
- **THEN** each queue-entered, map-known, match-found and raid-starting transition has the same record identity and time as before the restart

## MODIFIED Requirements

### Requirement: Each lifecycle transition is published once
Raid started, raid ended and matching aborted SHALL each be published once, with the record identity and time of the event that caused it. Reading the same session folder again after an app restart SHALL publish them with the same identities, so later consumers can drop duplicates.

#### Scenario: One transition per event
- **WHEN** a whole raid is read
- **THEN** exactly one raid-started and one raid-ended transition are published

#### Scenario: Re-read after restart
- **WHEN** the app restarts and reads the same session folder again
- **THEN** each raid-started, raid-ended and matching-aborted transition has the same record identity, time and cause as before the restart

#### Scenario: Queue progress does not change the raid transitions
- **WHEN** a whole raid is read, with its queue progress transitions
- **THEN** exactly one raid-started and one raid-ended transition are still published, with the same identities as without the queue progress transitions
