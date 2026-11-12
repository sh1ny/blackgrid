# task-catalog Specification

## Purpose

Keeps a mode-scoped catalog of tarkov.dev tasks, objectives and hideout stations with their identities, prerequisites and requirements, so local progress, the availability rules and the quest checklist share one validated source.

## Requirements

### Requirement: Task catalog comes with each item catalog refresh

Each successful catalog refresh for a known mode SHALL build that mode's task catalog from the `tasks` and `hideout` datasets and their English dictionaries that the refresh already downloads. Building it SHALL NOT make any additional network request. The task catalog SHALL be published, stored and replaced together with that mode's item catalog, never on its own.

#### Scenario: Refresh carries the mode's tasks

- **WHEN** a PvE refresh succeeds with 499 tasks and 26 stations in its datasets
- **THEN** the PvE snapshot carries a task catalog with 499 tasks and 26 stations, and the refresh made the same requests as before this change

#### Scenario: Failed refresh keeps the last-good task catalog

- **WHEN** a refresh for a mode whose cached snapshot has a task catalog fails for any reason
- **THEN** that cached snapshot, with its task catalog, stays in use unchanged

#### Scenario: Other modes are untouched

- **WHEN** a regular-mode refresh succeeds
- **THEN** the stored PvE and seasonal snapshots and their task catalogs are unchanged

### Requirement: Task facts are retained

For each task the catalog SHALL keep:

- the tarkov.dev ID, display name and normalized name;
- the trader ID, minimum player level and faction (`Any`, `BEAR`, `USEC` or unknown);
- the Kappa-required, Lightkeeper-required and restartable flags;
- the map ID, the required prestige ID and the game-mode restriction list.

An absent or wrong-typed value SHALL be kept as unknown, never as `false`, zero or `Any`, except where the next requirement keeps today's strictness.

#### Scenario: Kappa task kept with its flags

- **WHEN** a task arrives with `kappaRequired: true`, `lightkeeperRequired: false`, `factionName: "USEC"` and `minPlayerLevel: 15`
- **THEN** the catalog task reports Kappa required, Lightkeeper not required, faction USEC and minimum level 15

#### Scenario: Missing flag stays unknown

- **WHEN** a task arrives without `lightkeeperRequired` and without `minPlayerLevel`, with `factionName: "Marauder"` and with `kappaRequired: "yes"`
- **THEN** the catalog task reports Lightkeeper unknown, minimum level unknown, faction unknown and Kappa unknown, and the refresh still succeeds

### Requirement: Already-validated task fields keep today's strictness

The fields the existing item-requirement parse already validates SHALL keep exactly their current strictness:

- `minPlayerLevel` and `factionName`;
- prerequisite statuses;
- every objective's `type`;
- the count, found-in-raid, optional and item fields of `findItem`, `giveItem`, `plantItem` and `buildWeapon` objectives.

A value that parse rejects SHALL still reject the refresh.

#### Scenario: Already-validated value rejects as today

- **WHEN** a task arrives with `minPlayerLevel: "ten"`, or an objective with no `type`, or a `giveItem` objective whose `foundInRaid` is `"yes"`
- **THEN** the refresh is rejected as invalid data, exactly as before this change, and the previous snapshot stays in use

#### Scenario: Valid values pass unchanged

- **WHEN** a task has `minPlayerLevel: 10`, `factionName: "Any"` and a `giveItem` objective with `foundInRaid: true`
- **THEN** the refresh succeeds and the catalog task reports minimum level 10, faction Any and found in raid

### Requirement: Absent lists stay unknown

An absent `taskRequirements`, `traderRequirements` or `failConditions` on a task, and an absent `stationLevelRequirements`, `traderRequirements` or `skillRequirements` on a station level, SHALL be kept as unknown, distinct from an empty list, and SHALL NOT reject the refresh. A present empty list SHALL mean none.

#### Scenario: Task without fail conditions

- **WHEN** a task arrives with no `failConditions` field
- **THEN** the catalog task reports its alternatives as unknown and the refresh succeeds

#### Scenario: Empty list means none

- **WHEN** a task arrives with `taskRequirements: []`
- **THEN** the catalog task reports no prerequisites, not unknown prerequisites

### Requirement: Prerequisites keep their accepted statuses

For each task prerequisite the catalog SHALL keep the prerequisite task ID and the full list of accepted statuses (`complete`, `active`, `failed`, or unknown for any other value), in source order. Must-be-failed prerequisites therefore stay distinguishable from completion prerequisites.

#### Scenario: Must-be-failed prerequisite

- **WHEN** a task requires task B with status `["complete", "failed"]` and task C with status `["failed"]`
- **THEN** the catalog task lists prerequisite B accepting complete or failed and prerequisite C accepting failed only

#### Scenario: Unknown status value

- **WHEN** a prerequisite's status list holds `"expired"`
- **THEN** that status is kept as unknown, the prerequisite and its task are kept, and the refresh succeeds

### Requirement: Alternatives come from task-status fail conditions

The catalog SHALL record, for each task, its alternative tasks: those named by its fail conditions of type `taskStatus`, each with its statuses. Fail conditions of any other type SHALL be kept only as their condition ID and type, and SHALL NOT be listed as alternatives.

#### Scenario: Completing another task fails this one

- **WHEN** task A has a `taskStatus` fail condition naming task B with status `["complete"]`
- **THEN** the catalog lists B as an alternative of A, accepting complete

#### Scenario: Non-task fail condition

- **WHEN** task A has a fail condition of type `extract`
- **THEN** A lists no alternative from that condition, and the condition is kept with its ID and type

### Requirement: Trader requirements keep their comparison

For each task trader requirement the catalog SHALL keep the trader ID, the requirement type (`level`, `reputation` or unknown), the comparison (`>=`, `>`, `<=`, `<`, `=` or unknown) and the numeric value (or unknown).

#### Scenario: Loyalty level gate

- **WHEN** a task requires Prapor `level` `>=` 2
- **THEN** the catalog task lists a Prapor level requirement of at least 2

#### Scenario: Unknown comparison

- **WHEN** a trader requirement has comparison `"~"`
- **THEN** the requirement is kept with an unknown comparison and the refresh succeeds

### Requirement: Objectives are retained with their checklist facts

For each task the catalog SHALL keep every objective, in source order, with its ID, type, optional flag, count, English description and map IDs. An objective of an unrecognized type SHALL be kept with its ID, an unknown type and its raw type string.

#### Scenario: Found-in-raid hand-over

- **WHEN** a task has a `giveItem` objective for 3 items found in raid
- **THEN** the catalog objective reports type give item, count 3, found in raid and its item IDs

#### Scenario: New objective type

- **WHEN** an objective arrives with type `"photograph"`
- **THEN** the objective is kept with its ID, count and description, an unknown type and raw type `photograph`, and the refresh succeeds

### Requirement: Item-bearing objectives carry their items

Item and quest-item objectives SHALL carry these facts:

| Wire types | Facts |
|---|---|
| `findItem`, `giveItem`, `plantItem`, `sellItem` | item IDs from `items`; found in raid from `foundInRaid` |
| `buildWeapon`, `useItem`, `mark` | item IDs from `item`, `useAny` or `markerItem`; found in raid unknown |
| `findQuestItem`, `giveQuestItem`, `plantQuestItem` | quest item ID from `questItem` (string or object `id`) |

An absent fact is unknown.

#### Scenario: Quest item objective

- **WHEN** a task has a `findQuestItem` objective with `questItem: "qi-1"` and no `items`
- **THEN** the catalog objective reports type find quest item with quest item `qi-1` and no item IDs

#### Scenario: Missing item fact

- **WHEN** a `useItem` objective has no `useAny`
- **THEN** the objective reports unknown item IDs and the refresh succeeds

### Requirement: Target objectives carry their targets

`taskStatus` objectives SHALL carry the task ID and statuses, `traderLevel` the trader ID and level, `traderStanding` the trader ID, comparison and value, and `skill` the skill ID and level. Every other objective type SHALL carry no facts. An absent fact is unknown.

#### Scenario: Trader standing objective

- **WHEN** a `traderStanding` objective names trader T with comparison `>=` and value 5
- **THEN** the objective reports trader T with comparison at-least and value 5

#### Scenario: Missing target fact

- **WHEN** a `traderStanding` objective has no `value`, and a `visit` objective carries `items`
- **THEN** the standing objective reports an unknown value, the visit objective carries no facts, and the refresh succeeds

### Requirement: Shared objective IDs are flagged

An objective ID that appears under more than one task SHALL be kept under each of those tasks and marked as shared, so that progress keyed by objective ID can detect the ambiguity. An objective ID that repeats within one task SHALL be an identity error.

#### Scenario: Objective shared by task variants

- **WHEN** the BEAR and USEC variants of a task both carry objective `obj-1`
- **THEN** both tasks list `obj-1`, each marked shared

#### Scenario: Repeat within a task

- **WHEN** one task lists objective `obj-2` twice
- **THEN** the refresh is rejected as invalid data

### Requirement: Hideout stations and levels are retained

For each hideout station the catalog SHALL keep its ID, display name and normalized name. For each station level it SHALL keep:

- the level ID, level number and construction time in seconds;
- the required station levels;
- the trader requirements, in the same form as task trader requirements;
- the skill requirements.

Levels SHALL be ordered by level number.

#### Scenario: Station with prerequisites

- **WHEN** Library level 1 requires Rest space level 3 and Hideout Management skill 5
- **THEN** the catalog's Library level 1 lists Rest space's station ID at level 3 and skill ID `HideoutManagement` at level 5

#### Scenario: Invalid level number

- **WHEN** a station level has level number 0 or none
- **THEN** the refresh is rejected as invalid data

### Requirement: Identities and references are validated strictly

The refresh SHALL be rejected as invalid data, keeping the last-good snapshot, when any of the following holds:

- a task, objective, station or station level lacks an ID;
- a task or station ID repeats;
- a task's trader, a prerequisite, an alternative, a `taskStatus` objective's task, a requirement's trader or a required station is not in the mode's datasets.

Map, prestige, quest item and objective item IDs, and objective traders, are not resolved by this rule.

#### Scenario: Unresolved prerequisite

- **WHEN** a task's prerequisite names a task ID that is not in the mode's tasks dataset
- **THEN** the refresh fails with the invalid-data error and the previous snapshot stays in use

#### Scenario: Unknown map ID is accepted

- **WHEN** a task names a map ID that no catalog dataset contains
- **THEN** the task keeps that map ID and the refresh succeeds

### Requirement: Display text falls back without failing

Task, objective and station display text SHALL come from the mode's English dictionaries. A missing translation SHALL fall back to the normalized name and then the ID for tasks and stations, and to unknown for objective descriptions. A dictionary that fails to load SHALL be reported as today and SHALL NOT reject the refresh.

#### Scenario: Translated objective

- **WHEN** an objective's description key has the English text "Locate the Emercom station on Ground Zero"
- **THEN** the catalog objective's description is that text

#### Scenario: Missing tasks dictionary

- **WHEN** the tasks dictionary download fails
- **THEN** the refresh succeeds, task names fall back to normalized names, objective descriptions are unknown, and the tasks dictionary is listed among the names that could not be loaded

### Requirement: Stored snapshots carry the task catalog optionally

A stored snapshot SHALL keep its task catalog and restore it unchanged on load. A snapshot stored without one, or whose stored task catalog cannot be read, SHALL load with its item data intact and its task catalog unavailable. The snapshot's schema version, authority and freshness rules SHALL NOT change.

#### Scenario: Restart restores the task catalog

- **WHEN** the app restarts with a cached snapshot that has a task catalog
- **THEN** the loaded snapshot's task catalog equals the stored one

#### Scenario: Snapshot cached before this change

- **WHEN** the app loads a snapshot stored without a task catalog
- **THEN** item data, prices and status behave as before and the task catalog reports unavailable until the next successful refresh

#### Scenario: Damaged stored task catalog

- **WHEN** a stored snapshot's task catalog has a field of the wrong type
- **THEN** the snapshot loads with its item data and an unavailable task catalog

### Requirement: The task catalog model is usable without Flutter or Windows

The task catalog model, its stored form and the parsing of the tarkov.dev task and hideout data SHALL be usable from a plain Dart program with no Flutter or Windows dependency. The rules and later non-desktop apps can then use them.

#### Scenario: Plain Dart test run

- **WHEN** the model's tests run under plain `dart test`
- **THEN** they pass without loading Flutter or any Windows library

#### Scenario: Flutter dependency introduced

- **WHEN** a change adds a Flutter or Windows-only dependency to the model
- **THEN** a dependency check fails the offline test suite

### Requirement: Existing advice and Tracker behaviour are unchanged

Introducing the task catalog SHALL NOT change keep/sell advice, requirement rows, raid timers, Tracker requests or credentials, or any screen.

#### Scenario: Same advice with and without the block

- **WHEN** the same item data is loaded once with a task catalog and once without one
- **THEN** the advice, requirement rows and timer inputs are identical

#### Scenario: Task catalog unavailable

- **WHEN** the active snapshot has no task catalog
- **THEN** every existing screen shows what it showed before this change
