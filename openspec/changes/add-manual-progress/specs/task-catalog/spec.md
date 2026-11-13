# Spec Delta

## ADDED Requirements

### Requirement: Traders and their loyalty levels are retained
The task catalog SHALL keep, from the `traders` dataset the refresh already downloads, each trader's tarkov.dev ID, English display name, normalized name and loyalty level numbers in ascending order. Building it SHALL NOT make another request. A trader with absent or malformed levels SHALL keep its levels as unknown without rejecting the refresh.

#### Scenario: Traders with levels
- **WHEN** a refresh's traders dataset lists Prapor with levels 1 to 4 and Fence with levels 1 to 3
- **THEN** the task catalog's Prapor has levels 1, 2, 3, 4 and Fence has 1, 2, 3, and the refresh made the same requests as before

#### Scenario: Malformed levels
- **WHEN** a trader arrives with `levels` missing, or with a level whose number is not a positive whole number
- **THEN** that trader's levels are unknown, the other traders keep theirs and the refresh succeeds

#### Scenario: Duplicate level numbers
- **WHEN** a trader lists level 2 twice
- **THEN** that trader's levels are unknown and the refresh succeeds

### Requirement: Stored catalogs without traders still load
A stored task catalog written before traders were kept SHALL load with its traders unknown and every other fact unchanged. A stored catalog with traders SHALL restore them unchanged.

#### Scenario: Older stored catalog
- **WHEN** the app loads a snapshot whose stored task catalog has no traders
- **THEN** the task catalog is available, its tasks and stations are unchanged and its traders are unknown

#### Scenario: Round trip
- **WHEN** a catalog with Fence at levels 1 to 3 is stored and loaded
- **THEN** the loaded catalog has Fence at levels 1, 2, 3
