# task-availability Specification

## Purpose

Works out, for each task in a game mode, whether the player has done it, can take it now or is locked out, and why, from the mode's task catalog and the player's local progress, in plain Dart that any app can share.

## Requirements

### Requirement: Every catalog task gets one result

Given one mode's task catalog, that mode and a snapshot of the player's progress in it, the rules SHALL return exactly one result per catalog task, in catalog order. Each result SHALL hold a status (`done`, `available` or `locked`), the checked reasons and the unchecked reasons. Progress for task IDs that are not in the catalog SHALL be ignored.

#### Scenario: Results follow the catalog

- **WHEN** the rules run over a catalog of 3 tasks with empty progress
- **THEN** they return 3 results in the catalog's task order, each with a status

#### Scenario: Progress for an unknown task

- **WHEN** the progress snapshot records task `gone-1` as finished and `gone-1` is not in the catalog
- **THEN** the results are the same as without that record, and no error is raised

### Requirement: Results are deterministic and side-effect free

The rules SHALL depend only on their inputs: the same catalog, mode, progress and edition table SHALL give equal results on every run and platform. They SHALL NOT read the clock, files, network, settings or any other state.

#### Scenario: Repeated evaluation

- **WHEN** the rules run twice over the same frozen fixture and progress
- **THEN** both runs return equal results, reason for reason

#### Scenario: Progress changes between runs

- **WHEN** the rules run, the player level in the snapshot is raised from 4 to 10 and the rules run again
- **THEN** the second run reflects level 10 and the first run's results are unchanged

### Requirement: Recorded task state decides done and started

A task recorded as finished SHALL be `done`. A task recorded as failed SHALL be `done` unless the catalog says it is restartable, in which case it SHALL be evaluated as not started. A task recorded as started SHALL be `available` and marked started, without evaluating its gates. A task with no recorded state, or an explicit unset, SHALL count as not started.

#### Scenario: Finished task

- **WHEN** task A is recorded finished and its level gate would fail
- **THEN** A is `done` with the reason finished and no gate reasons

#### Scenario: Failed restartable task

- **WHEN** task A is recorded failed, the catalog marks A restartable, and all its gates pass
- **THEN** A is `available` and not marked started

#### Scenario: Failed with unknown restartability

- **WHEN** task A is recorded failed and its restartable flag is unknown
- **THEN** A is `done` with the reason failed

### Requirement: A failing checked gate locks the task

A not-started task SHALL be `locked` when at least one checked gate fails, and `available` otherwise. A locked result SHALL list every failing checked gate, not only the first. The unchecked reasons SHALL be listed whether the task is locked or available.

#### Scenario: Two gates fail

- **WHEN** a not-started task needs level 15 and Prapor loyalty 2, and the player is level 10 with Prapor at loyalty 1
- **THEN** the task is `locked` with a level reason (needs 15, has 10) and a loyalty reason (Prapor needs at least 2, has 1)

#### Scenario: Failing gate beside an unchecked one

- **WHEN** a not-started task fails its level gate and also has a global-variable requirement
- **THEN** the task is `locked` with the level reason and lists the global-variable requirement as unchecked

### Requirement: Player level gate

A task whose minimum player level is above the player's recorded level SHALL fail its level gate. A minimum of 1 or less SHALL always pass. When the minimum is above 1 and the player's level is unset, or the task's minimum is unknown, the level gate SHALL be unchecked.

#### Scenario: Level too low

- **WHEN** a not-started task has minimum level 20 and the player is level 19
- **THEN** the task is `locked` with a level reason naming 20 and 19

#### Scenario: Level not entered

- **WHEN** a not-started task has minimum level 20 and the player's level is unset
- **THEN** the level gate is listed as unchecked and does not lock the task

### Requirement: Trader loyalty gate

A trader requirement of type level SHALL be checked against the player's recorded loyalty level for that trader, using its comparison and value. When the loyalty is unset, only an at-least requirement of 1 or less and a greater-than requirement below 1 SHALL pass, because every loyalty is at least 1. Otherwise an unset loyalty, an unknown comparison, an unknown value or an unknown requirement type SHALL make that requirement unchecked. A reputation requirement SHALL always be unchecked.

#### Scenario: Loyalty met

- **WHEN** a task requires Skier level at least 3 and the player has Skier at 3
- **THEN** the loyalty gate passes

#### Scenario: Reputation requirement

- **WHEN** a task requires Fence reputation at most -1
- **THEN** that requirement is listed as unchecked and does not lock the task

#### Scenario: Loyalty not entered

- **WHEN** a task requires Mechanic level at least 2 and the player's Mechanic loyalty is unset
- **THEN** the requirement is listed as unchecked

#### Scenario: Upper bound with loyalty not entered

- **WHEN** a task requires Ragman level at most 2 and the player's Ragman loyalty is unset
- **THEN** the requirement is listed as unchecked and does not lock the task

### Requirement: Unknown trader requirements remain unchecked

An unknown trader-requirements list SHALL produce a list-level unchecked reason for a not-started task; a known empty list SHALL pass without that reason.

#### Scenario: Unknown trader requirements remain uncertain

- **WHEN** a not-started task's trader requirements are unknown, while its other gates are known and pass
- **THEN** the task is available with a list-level unchecked trader-requirements reason, distinct from a known empty list which has no such reason

### Requirement: Prerequisite gate

A prerequisite SHALL pass when the prerequisite task's recorded state is one of its accepted statuses: finished for complete, started for active, failed for failed. Otherwise it SHALL fail and name the statuses it needs, so must-be-failed and must-be-active prerequisites read differently from completion. Unknown accepted statuses SHALL be ignored, and a prerequisite with none known SHALL be unchecked, as SHALL an unknown prerequisite list.

#### Scenario: Prerequisite not done

- **WHEN** task B requires task A complete and A has no recorded state
- **THEN** B is `locked` with a prerequisite reason naming A and complete

#### Scenario: Must-be-failed prerequisite

- **WHEN** task B requires task A failed and A is recorded finished
- **THEN** B is `locked` with a prerequisite reason naming A and failed

#### Scenario: Unknown prerequisite list

- **WHEN** task B's prerequisites are unknown in the catalog
- **THEN** B lists its prerequisites as unchecked and they do not lock it

### Requirement: Finished active-only prerequisite is unchecked

When a prerequisite accepts active but not complete, and the prerequisite task is recorded finished, the prerequisite SHALL be unchecked rather than failed, because the task may have unlocked while the prerequisite was active.

#### Scenario: Prerequisite finished after unlocking

- **WHEN** task B requires task A active only and A is recorded finished
- **THEN** B lists the prerequisite on A as unchecked and is not locked by it

#### Scenario: Prerequisite never taken

- **WHEN** task B requires task A active only and A has no recorded state
- **THEN** B is `locked` with a prerequisite reason naming A and active

### Requirement: Alternative tasks close a task

A not-started task SHALL fail its alternative gate when an alternative task's recorded state is one of that alternative's statuses (finished for complete, started for active, failed for failed). The reason SHALL name the alternative. Unknown alternative statuses SHALL be ignored, and an unknown alternatives list SHALL be unchecked.

#### Scenario: Alternative completed

- **WHEN** task A has alternative B accepting complete and B is recorded finished
- **THEN** A is `locked` with an alternative reason naming B

#### Scenario: Alternative not taken

- **WHEN** task A has alternative B accepting complete and B is recorded started
- **THEN** A's alternative gate passes

### Requirement: Faction gate

A BEAR-only or USEC-only task SHALL fail its faction gate when the player's recorded faction is the other one. An unset player faction for a faction-restricted task, or an unknown task faction, SHALL make the gate unchecked. A task open to any faction SHALL pass.

#### Scenario: Wrong faction

- **WHEN** a not-started task is USEC-only and the player is BEAR
- **THEN** the task is `locked` with a faction reason naming USEC

#### Scenario: Faction not entered

- **WHEN** a not-started task is BEAR-only and the player's faction is unset
- **THEN** the faction gate is listed as unchecked

### Requirement: Game mode gate

The evaluated mode SHALL be one of regular, PvE or seasonal. A task whose game-mode restriction list is known and does not include the evaluated mode's tarkov.dev name SHALL fail its game-mode gate. An unknown or absent restriction list SHALL pass, because the catalog is already scoped to the mode.

#### Scenario: Regular-only task in PvE

- **WHEN** a task restricted to `regular` is evaluated for PvE
- **THEN** the task is `locked` with a game-mode reason

#### Scenario: No restriction

- **WHEN** a task has no game-mode restriction
- **THEN** the game-mode gate passes in every mode

### Requirement: Edition gate from a reviewed table

The rules SHALL take edition restrictions from a versioned table that maps task IDs to the editions allowed or excluded. Each entry SHALL name its source. A task with an entry SHALL fail its edition gate when the player's recorded edition is a known table edition that the entry does not permit. An unset or unrecognised player edition SHALL make the gate unchecked. A task without an entry SHALL pass.

#### Scenario: Edition excluded

- **WHEN** a task's entry allows only edition `unheard` and the player's edition is `standard`
- **THEN** the task is `locked` with an edition reason

#### Scenario: Unrecognised edition

- **WHEN** a task has an edition entry and the player's recorded edition is `collector-2031`, which the table does not know
- **THEN** the edition gate is listed as unchecked

### Requirement: Undecidable gates are listed, never locking

The rules SHALL list as unchecked, and SHALL NOT lock on: each global-variable requirement, each trader-dialogue requirement, each other requirement of unknown type, unknown other requirements, a nonzero or unknown availability delay, a required prestige and any unchecked gate named by the other requirements. A started or done task SHALL list none.

#### Scenario: Global-variable gate

- **WHEN** a not-started task's checked gates all pass and it has a global-variable requirement
- **THEN** the task is `available` and lists that requirement as unchecked

#### Scenario: Catalog stored before other requirements were kept

- **WHEN** a not-started task's other requirements are unknown because its catalog was stored before they were kept
- **THEN** the task lists other requirements as unchecked and is not locked by them

### Requirement: Rules are proved on frozen tarkov.dev data

The rules SHALL be tested against a committed, unchanged excerpt of real regular and PvE tarkov.dev task data with source URLs and fetch date. Each data-backed gate SHALL have a real excerpt case. Unknown, malformed, absent-field and input-boundary cases SHALL be proved with small synthetic catalog/progress tests, without fabricating source facts.

#### Scenario: Excerpt covers each gate

- **WHEN** the offline test suite runs
- **THEN** each data-backed gate (level, loyalty, prerequisite including failed and active, alternative, faction, game mode, edition, global variable, dialogue, delay, prestige and reputation) is exercised by at least one task from the excerpt; catalog uncertainty and input-boundary cases are exercised by synthetic tests

#### Scenario: Excerpt edited out of shape

- **WHEN** the excerpt's recorded source or fetch date is removed
- **THEN** the offline test suite fails

### Requirement: Rules run without Flutter or Windows

The rules and the edition table SHALL be usable from a plain Dart program with no Flutter or Windows dependency, in the same package as the task catalog model.

#### Scenario: Plain Dart run

- **WHEN** the rules' tests run under plain `dart test`
- **THEN** they pass without loading Flutter or any Windows library

#### Scenario: Flutter dependency introduced

- **WHEN** a change adds a Flutter or Windows-only dependency to the package
- **THEN** the offline dependency check fails
