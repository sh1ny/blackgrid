# Spec Delta

## ADDED Requirements

### Requirement: Advice reads the effective mode's local progress
Keep/sell advice, requirement rows and Flea eligibility SHALL use the current values of the effective mode's active wipe as their progress, and no other progress source. A mode with no active wipe SHALL count as progress with nothing recorded. The `unknown` mode SHALL have no progress. A change to local progress for the effective mode SHALL recompute the shown advice without a new scan.

#### Scenario: Finished task from the logs
- **WHEN** the PvP wipe records the task "Shortage" finished from a game log, and an item that "Shortage" needs is selected in PvP
- **THEN** that need is satisfied with "task completed", and no request is made to any progress site

#### Scenario: Manual edit recomputes the shown advice
- **WHEN** an item that "Shortage" needs is shown with a Keep verdict, and the player then marks "Shortage" finished by hand
- **THEN** the shown verdict and requirement rows are recomputed from the new value, and no scan or history entry is added

#### Scenario: Other mode's progress is not used
- **WHEN** "Shortage" is finished only in the PvE wipe and the effective mode is PvP
- **THEN** PvP advice treats "Shortage" as not started

#### Scenario: Unknown mode
- **WHEN** the effective mode is `unknown`
- **THEN** the decision's open inputs include progress

### Requirement: Unrecorded progress counts as not started, zero or not built
In advice, a task with no recorded state SHALL count as not started, an objective with no recorded count as 0 and not done, and a station with no recorded level as level 0. As in the availability rules, a started task's needs SHALL skip its gates, and a failed task SHALL count as done unless the item data says it is restartable. A gate that needs an unset level (above 1), faction or edition SHALL be unknown, and only that gate.

#### Scenario: Empty wipe with level set
- **WHEN** the PvP wipe records only player level 20, and an item needed 2 times by the level-10 task "Shortage" is selected
- **THEN** the need is "needed now" with 2 remaining

#### Scenario: Level unset
- **WHEN** the PvP wipe has no player level, and an item needed by a task with a minimum level is selected
- **THEN** that need is unresolved because whether the player can do it is not known yet, and other needs keep their states

#### Scenario: Counted objective
- **WHEN** the PvP wipe records count 1 for an objective that needs 3 of the item, and the task is started
- **THEN** the need has 2 remaining

#### Scenario: Started task skips its gates
- **WHEN** the PvP wipe records "Shortage" started from the logs and no player level, and an item "Shortage" needs 2 times is selected
- **THEN** that need is "needed now" with 2 remaining

#### Scenario: Started task with an unrecorded prerequisite
- **WHEN** the PvP wipe records "Shortage" started and nothing for the task it requires to be complete, and an item "Shortage" needs is selected
- **THEN** that need is "needed now", not "needed later"

#### Scenario: Restartable failed task
- **WHEN** the PvP wipe records a restartable task failed, and an item that task needs is selected
- **THEN** that need is treated as for a not-started task, not satisfied

#### Scenario: Non-restartable failed task
- **WHEN** the PvP wipe records a task failed that the item data does not mark restartable
- **THEN** that need is satisfied with "task failed; no active obligation"

#### Scenario: Level 1 minimum with no level
- **WHEN** the player level is unset and an item is needed by a not-started task whose minimum level is 1
- **THEN** the level does not make that need unresolved

#### Scenario: Unset faction
- **WHEN** the faction is unset and an item is needed only by a USEC task
- **THEN** that need is unresolved, not "does not apply to you"

### Requirement: Hideout items count in full until the level is built
A hideout station level's item requirement SHALL be satisfied when the station's recorded level is at least that level. Otherwise it SHALL need its full count, because item hand-ins toward an unbuilt level are not recorded. The previous level SHALL gate it as needed now or needed later.

#### Scenario: Level built
- **WHEN** the PvP wipe records Medstation at level 2, and an item needed for Medstation level 2 is selected
- **THEN** that need is satisfied

#### Scenario: Next level
- **WHEN** the PvP wipe records Medstation at level 1, and an item needed 2 times for Medstation level 2 is selected
- **THEN** that need is "needed now" with 2 remaining

#### Scenario: Later level
- **WHEN** Medstation has no recorded level, and an item needed for Medstation level 2 is selected
- **THEN** that need is "needed later" with its full count remaining

### Requirement: Edition gates stay unknown
An item requirement whose item data lists game editions SHALL have an unknown edition gate, whatever edition the player recorded, because the item data's edition values have no reviewed mapping to the player's edition.

#### Scenario: Edition-gated task
- **WHEN** an item is needed by a task whose item data lists game editions, and the player's edition is recorded
- **THEN** that need is unresolved

#### Scenario: No edition list
- **WHEN** an item is needed by a task whose item data lists no game editions, and the player's edition is unset
- **THEN** the edition does not make that need unresolved

### Requirement: Unavailable local progress is reported, never treated as empty
When the effective mode's local progress cannot be read (local progress failed to load, the mode's wipe history is unavailable, or a read fails), advice SHALL have no progress and SHALL name progress as the missing input. Local progress SHALL have no age limit while it can be read.

#### Scenario: Wipe history unavailable
- **WHEN** PvP's wipe history is unavailable and an item with a task need is selected in PvP
- **THEN** the decision is Check, names progress as the missing input, and never says the task is not started

#### Scenario: Old progress still counts
- **WHEN** the last PvP progress event is a week old
- **THEN** advice uses it, and nothing says progress is out of date

#### Scenario: Read fails after a good read
- **WHEN** advice used PvP progress and the next read of PvP progress fails
- **THEN** advice has no progress until a later read succeeds

## REMOVED Requirements

### Requirement: Selecting a known mode with a saved credential starts one progress refresh
**Reason**: The Tracker integration is removed; progress comes from local progress, which needs no refresh.
**Migration**: Progress is recorded from game logs and entered in Settings → Local progress.

### Requirement: A failed automatic progress refresh is not retried
**Reason**: There is no Tracker refresh any more.
**Migration**: None needed; local progress is read from the local database.

### Requirement: An automatic progress refresh never publishes into another selection
**Reason**: There is no Tracker refresh any more; advice reads the effective mode's local progress.
**Migration**: None needed.

### Requirement: A malformed Tracker response keeps the session's last good progress
**Reason**: There is no Tracker response any more.
**Migration**: An unreadable local progress history is reported as unavailable (see "Unavailable local progress is reported, never treated as empty").
