## ADDED Requirements

### Requirement: A chosen floor fades the base floor
While any non-base floor is visible, the base floor and its attached layers SHALL be drawn faded, at one strength on every map, whether that floor is vector artwork or raster tiles. Otherwise the base SHALL be drawn at full strength. Chosen floors SHALL stay at full strength.

#### Scenario: Vector underground floor
- **WHEN** Reserve is shown and the player chooses Bunkers
- **THEN** the ground level is drawn faded under the bunkers

#### Scenario: Vector upper floor
- **WHEN** Streets is shown and the player chooses the second floor
- **THEN** the ground level, with its attached first floor, is drawn faded

#### Scenario: Tile floor over vector artwork
- **WHEN** Reserve is shown and the player chooses the second floor
- **THEN** the ground level is drawn faded at the same strength as under Bunkers

#### Scenario: Raster map
- **WHEN** Labs is shown and the Second Level is visible
- **THEN** the First Level is drawn faded

#### Scenario: Base only
- **WHEN** a map shows only its base floor and the layers attached to it
- **THEN** the base is drawn at full strength

#### Scenario: Exclusive floors
- **WHEN** Icebreaker is shown and the player chooses a floor other than its base
- **THEN** only the chosen floor is drawn, as before
