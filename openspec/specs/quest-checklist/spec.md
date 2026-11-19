# quest-checklist Specification

## Purpose
Lets the player see the quests they have started in the current game mode, record objective progress as local manual events, and have the map's quest markers follow that progress.

## Requirements

### Requirement: Quests lists the mode's started tasks
The Map inspector's Quests section SHALL list every task of the effective mode's task catalog whose current state in the mode's active wipe is started, from the game logs or set by hand. Tasks with a quest marker on the current map SHALL come first, then the rest; each group SHALL be ordered by trader name, then task name. While the current map has no quest markers loaded, all tasks SHALL form one group. Started IDs the catalog does not list SHALL be kept in the store and not shown.

#### Scenario: Current map's quests first
- **GIVEN** started tasks A (Prapor, an objective on Customs) and B (Mechanic, no objective on Customs) in the PvP wipe
- **WHEN** the player opens Map on Customs in PvP
- **THEN** Quests lists A, then B, each with its objectives

#### Scenario: No quest markers loaded
- **WHEN** the current map has no quest markers loaded
- **THEN** Quests lists every started task in one group, ordered by trader name, then task name, and marks no objective as on this map

#### Scenario: Finished and failed tasks are not listed
- **WHEN** a listed task becomes finished from the game logs
- **THEN** Quests no longer lists it, without a restart

#### Scenario: No started task
- **WHEN** the mode's active wipe has no started task, or the mode has no active wipe
- **THEN** Quests shows that no quest is started and how to start one (accept it in game, or set it in Settings, Your progress)

#### Scenario: Unknown task ID
- **WHEN** the wipe holds a started task whose ID the catalog does not list
- **THEN** that task is not shown, and its event stays in the store

### Requirement: Objectives show their progress
Each listed task SHALL show its objectives in catalog order with their English description, an optional mark for optional objectives, and an "On this map" mark when a quest marker of the current map carries its objective ID. An objective with a target count over 1 SHALL show its current count and target. An objective SHALL read done when its completion is set to true or its count has reached its target. An objective with no recorded value SHALL read not done with a count of 0.

#### Scenario: Counter objective
- **GIVEN** an objective "Eliminate Scavs on Customs" with target 5 and a recorded count of 3
- **WHEN** Quests shows its task
- **THEN** the objective shows 3/5 and reads not done

#### Scenario: Count reached
- **WHEN** the same objective's recorded count is 5
- **THEN** it reads done

#### Scenario: Missing description
- **WHEN** an objective has no English description in the catalog
- **THEN** it shows its objective type instead, and still offers its controls

### Requirement: Ticking records objective completion
An objective with no target count over 1 SHALL offer a tick that records its completion as true or, when done, as false. An objective with a target count over 1 SHALL offer + and - controls that record the count one higher or lower, bounded by 0 and the target, and a tick that records the count as the target; it SHALL offer no untick. Every click SHALL append exactly one manual event to the mode's active wipe.

#### Scenario: Tick a single objective
- **WHEN** the player ticks a not-done objective without a counter
- **THEN** one manual event setting its completion to true is recorded and the objective reads done

#### Scenario: Counter reaches its target
- **GIVEN** a counter objective at 4/5
- **WHEN** the player clicks +
- **THEN** one manual event setting its count to 5 is recorded, the objective reads done, and + is disabled

#### Scenario: Tick a counter objective
- **GIVEN** a counter objective at 2/5
- **WHEN** the player ticks it
- **THEN** one manual event setting its count to 5 is recorded and the objective reads done

#### Scenario: Counter bounds
- **WHEN** a counter objective is at 0
- **THEN** - is disabled and no event can be recorded below 0

### Requirement: Ticks never finish a task
Recording objective progress SHALL NOT change any task's state. A task SHALL stay listed while it is started, even when every objective reads done.

#### Scenario: Every objective done
- **WHEN** the player ticks the last not-done objective of a started task
- **THEN** no task-state event is recorded and the task stays listed as started

#### Scenario: Turn-in from the logs
- **WHEN** the game logs then record the task as finished
- **THEN** the task leaves Quests and its objective values stay in the store

### Requirement: Objective progress uses the manual-entry rules
Objective events SHALL follow the manual progress rules: one event per entry in the effective mode's active wipe, a new wipe created first when the mode has none, entries queued behind other progress work, failures shown without retry, and Undo of the last manual change and Redo of an undo for each objective's value.

#### Scenario: Undo a counter step
- **GIVEN** the player clicked + on an objective from 2/5 to 3/5
- **WHEN** they choose Undo on that objective
- **THEN** a manual undo event restores the count to 2, and Redo is offered

#### Scenario: Storage failure
- **WHEN** recording a tick fails with a storage failure
- **THEN** nothing is recorded, the objective keeps its previous state and the row shows the failure's reason

#### Scenario: Entry during replay
- **WHEN** the player ticks an objective while a log replay is running
- **THEN** the tick waits for the replay and is then recorded, not refused

### Requirement: Shared objectives share one value
An objective whose ID the catalog marks as shared between tasks SHALL read and record the same value under every task that lists it, and its row SHALL name the other started or unstarted tasks that share it.

#### Scenario: Tick a shared objective
- **GIVEN** objective O is listed under started tasks A and B
- **WHEN** the player ticks O under A
- **THEN** O reads done under A and under B, and both rows name the other task

#### Scenario: Shared with an unlisted task
- **WHEN** O is shared with a task that is not started
- **THEN** O's row under the started task still names that task

### Requirement: Quests follows the effective mode and fresh values
Quests SHALL show the effective mode's active wipe and SHALL read its values again after each entry, undo, log event, replay, new wipe, catalog change or mode switch. While local progress is not loaded, the wipe is unavailable or the mode has no task catalog, the section SHALL show that reason and offer no controls.

#### Scenario: Mode switch
- **WHEN** the game's detected mode changes from PvP to PvE
- **THEN** Quests lists PvE's started tasks with PvE's objective values

#### Scenario: Catalog unavailable
- **WHEN** the effective mode has no task catalog
- **THEN** Quests shows that the quest data is not available yet and offers no tick or counter

#### Scenario: Unavailable wipe
- **WHEN** the mode's wipe is unavailable because its history is damaged
- **THEN** Quests shows that reason and offers no controls, and no event is recorded

### Requirement: Quest markers follow active quests
Unless Show all quests is on, a quest objective or quest item marker SHALL be drawn only when its task is started in the effective mode's active wipe and its objective is not done. When that wipe has no started task, or local progress is not loaded or unavailable, every quest marker SHALL be eligible as before this change. The category rows, quest name and trader filters SHALL still apply.

#### Scenario: Ticked objective leaves the map
- **GIVEN** Show all quests is off and task A is started with objective O on Customs
- **WHEN** the player ticks O
- **THEN** O's markers are no longer drawn and A's other not-done objectives' markers still are

#### Scenario: Not-started task hidden
- **WHEN** Show all quests is off and task C is not started
- **THEN** C's quest markers are not drawn

#### Scenario: Nothing started
- **WHEN** Show all quests is off and the wipe has no started task
- **THEN** every quest marker is drawn as before this change

#### Scenario: Show all quests
- **WHEN** the player turns Show all quests on
- **THEN** every quest marker is eligible again, subject to the category rows and the quest name and trader filters

### Requirement: Advice stays on the Tracker token
This change SHALL NOT switch keep/sell advice, raid timers or task state away from the Tracker token, and SHALL NOT change the token's requests or credentials.

#### Scenario: Ticking does not change advice
- **WHEN** the player ticks an objective of a quest that needs the selected item
- **THEN** the item's verdict and requirement rows are unchanged

#### Scenario: Token removed
- **WHEN** no Tracker token is configured
- **THEN** Quests and the quest-marker filter still work from local progress
