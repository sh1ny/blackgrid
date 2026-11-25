# Map controls delta

## MODIFIED Requirements

### Requirement: Floor control sits beside the picker
A segmented control beside the picker SHALL offer Auto exactly when the prepared map has at least one floor extent, and then each of the map's floors. Choosing a floor SHALL change the visible layers as the floor chips did, and each visible layer SHALL show as selected. A map with no floors SHALL show no floor control.

#### Scenario: Choosing a floor
- **WHEN** a map with Ground and Underground floors is shown and the player chooses Underground
- **THEN** that floor's visibility changes and its segment shows its new state

#### Scenario: Manual-only floors
- **WHEN** a map with selectable floors has no floor extents
- **THEN** the floor segments are shown without Auto

#### Scenario: Map with no floors
- **WHEN** the current map has no floor policy floors and no automatic floor support
- **THEN** no floor control is shown

#### Scenario: Artwork unavailable
- **WHEN** the selected map's artwork is not available
- **THEN** the picker stays usable and no floor segment is shown

## ADDED Requirements

### Requirement: Auto follows the sampled player position
Auto SHALL initially be on for a map with extents. A known position matches an extent in its lower-inclusive, upper-exclusive height range and inside or on an edge of one rectangle in game-space X/Z, if bounded. The narrowest matching height span SHALL win. Equal spans SHALL use ascending floor ID. A known unmatched position SHALL select base. Unknown height SHALL leave the selection unchanged.

#### Scenario: Position changes at the same height
- **WHEN** Auto is on and a Reserve position at height −9 moves from inside a command-bunker rectangle to outside every matching rectangle
- **THEN** Bunkers is selected at the first position and base at the second

#### Scenario: Height-only extent
- **WHEN** Auto is on and a Streets position at height −9 is followed by one at height 16
- **THEN** Underground is selected first and the 3rd Floor second, regardless of their horizontal coordinates

#### Scenario: Overlapping extents
- **WHEN** a position matches a wide extent and two equally narrow extents on floors `Narrow_A` and `Narrow_B`, with both floor and extent iteration order varied
- **THEN** `Narrow_A` wins in both orders

#### Scenario: Unknown height
- **WHEN** an Auto position update does not have a height
- **THEN** the current floor selection stays unchanged rather than falling back to ground

#### Scenario: Exclusive map
- **WHEN** the known position selects a non-base floor of an exclusive map
- **THEN** only the selected floor's layers are visible; on a later unmatched known position only the base floor's layers are visible

### Requirement: Manual floor selection overrides Auto
A manual floor selection SHALL disable Auto on that map, without affecting Auto on other maps. Re-enabling Auto SHALL apply the latest position if its floor resolves. Existing additive and exclusive visibility rules SHALL stay in force.

#### Scenario: Manual choice overrides Auto only on that map
- **WHEN** the player manually chooses a floor on one Auto-capable map, visits another Auto-capable map, then returns and receives a position on a different floor
- **THEN** Auto still follows samples on the second map, the first retains its manual floor, and re-enabling Auto on the first applies its latest known position

### Requirement: Unassigned markers use the prepared floor extents
A marker's explicit prepared floor ownership SHALL take precedence. An unassigned marker SHALL use the same position-based floor classification as player Auto, independent of whether Auto is currently on. A marker without a resolvable floor SHALL follow the existing unknown-floor visibility policy.

#### Scenario: Spatial inference for an unassigned marker
- **WHEN** an unassigned marker's position matches a hidden floor by both height and rectangle
- **THEN** that floor's visibility controls marker paint and hit eligibility

#### Scenario: Marker outside a rectangle
- **WHEN** an unassigned marker lies within a floor's extent height but outside every rectangle and no other extent matches
- **THEN** the marker is eligible on the base floor

#### Scenario: Explicit marker ownership
- **WHEN** a marker's explicit floor differs from its inferred floor
- **THEN** eligibility follows its explicit floor
