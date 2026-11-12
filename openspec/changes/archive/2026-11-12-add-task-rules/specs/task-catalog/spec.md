# Spec Delta

## ADDED Requirements

### Requirement: Other task requirements are retained leniently

For each task the catalog SHALL keep its `otherRequirements` in source order: a `globalVariable` entry with its ID, variable ID, comparison and value; a `dialogue` entry with its ID and trader IDs; any other type with its ID, an unknown type and its raw type. An absent, malformed or wrong-typed list SHALL be kept as unknown, distinct from an empty list, and SHALL NOT reject the refresh. These references SHALL NOT be resolved.

#### Scenario: Global-variable requirement kept

- **WHEN** a task arrives with an other requirement of type `globalVariable`, variable `var-1`, comparison `>=` and value 5
- **THEN** the catalog task lists that requirement with variable `var-1`, comparison at-least and value 5

#### Scenario: Malformed other requirements

- **WHEN** a task arrives with `otherRequirements: "none"`, or with an entry that has no `type`
- **THEN** the catalog task reports its other requirements as unknown and the refresh succeeds

#### Scenario: Absent list

- **WHEN** a task arrives without `otherRequirements`
- **THEN** the catalog task reports its other requirements as unknown, while a task with `otherRequirements: []` reports none

### Requirement: Availability delays are retained leniently

For each task the catalog SHALL keep `availableDelaySecondsMin` and `availableDelaySecondsMax` as nonnegative whole seconds. An absent, negative or wrong-typed value SHALL be kept as unknown and SHALL NOT reject the refresh.

#### Scenario: Ten-hour delay

- **WHEN** a task arrives with both delay fields set to 36000
- **THEN** the catalog task reports a delay of 36000 to 36000 seconds

#### Scenario: Wrong-typed delay

- **WHEN** a task arrives with `availableDelaySecondsMin: "soon"` and no `availableDelaySecondsMax`
- **THEN** both delays are unknown and the refresh succeeds

### Requirement: Stored catalogs without the new facts still load

A stored task catalog written before other requirements and delays were kept SHALL load with both unknown on every task, without changing its stored format version. A stored catalog that has them SHALL restore them unchanged.

#### Scenario: Older stored catalog

- **WHEN** the app loads a snapshot whose stored task catalog has no other-requirement or delay fields
- **THEN** the task catalog is available, and every task reports its other requirements and delays as unknown

#### Scenario: Round trip

- **WHEN** a catalog with a dialogue requirement and a 1800-2100 second delay is stored and loaded
- **THEN** the loaded task has the same dialogue requirement and delay
