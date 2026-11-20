# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: Existing advice and Tracker behaviour are unchanged`
- TO: `### Requirement: The task catalog does not change advice`

## MODIFIED Requirements

### Requirement: The task catalog does not change advice

Introducing the task catalog SHALL NOT change keep/sell advice, requirement rows or raid timers.

#### Scenario: Same advice with and without the block

- **WHEN** the same item data is loaded once with a task catalog and once without one
- **THEN** the advice, requirement rows and timer inputs are identical

#### Scenario: Task catalog unavailable

- **WHEN** the active snapshot has no task catalog
- **THEN** advice, requirement rows and timer inputs are the same as with one
