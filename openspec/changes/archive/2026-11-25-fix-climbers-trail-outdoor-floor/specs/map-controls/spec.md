# Map controls delta

## MODIFIED Requirements

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

#### Scenario: Outdoor Climber’s Trail on bundled Shoreline
- **WHEN** the bundled Shoreline map shows the ground level with no overlay selected and the exit categories are enabled
- **THEN** Climber’s Trail is eligible to appear on the map and in This raid if matched, without selecting the second floor
- **AND** Admin Basement and Transit to Labyrinth remain ineligible until Underground is shown
