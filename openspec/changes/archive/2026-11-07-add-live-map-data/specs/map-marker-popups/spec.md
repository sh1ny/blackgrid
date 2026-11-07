# Spec Delta

## MODIFIED Requirements

### Requirement: Summaries reflect prepared marker facts
The bubble SHALL use player-facing category and marker names from the active validated marker generation, whether downloaded, cached or bundled, and show available category-specific facts without inventing data or initiating a map-data request. Quest markers show their quest and objective or item text; extracts show linked switch names and required or payment item counts; locks show lock type and key name; containers show their name; bosses show their name and available boss-wide spawn chance.

#### Scenario: Quest and container
- **WHEN** a selected quest objective contains a translated quest name and objective description, or a container has an available display name
- **THEN** the bubble shows those available names and description in plain language

#### Scenario: Linked extract and lock
- **WHEN** an extract contains a required item count and a source link to a named switch on the same map, or a lock has a lock type and a named key
- **THEN** the bubble shows the count and item name and linked switch name, or the lock type and key name, respectively

#### Scenario: Missing or misleading fields
- **WHEN** an optional fact is absent, a marker name is only its raw category key, a switch is not source-linked on the same map, or a boss chance is missing or invalid
- **THEN** the bubble uses the player-facing category label instead of the raw fallback name, omits unavailable optional facts and does not invent a switch or chance

#### Scenario: Boss chance scope
- **WHEN** the active boss-wide spawn chance is 0.35
- **THEN** the bubble presents 35% as the boss spawn chance and does not claim it is the chance for that location

#### Scenario: Refreshed marker facts
- **WHEN** a validated replacement changes a marker's facts and the player selects a marker from that generation
- **THEN** the bubble shows the new available facts without initiating a map-data request
