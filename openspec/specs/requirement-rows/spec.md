# requirement-rows Specification

## Purpose
Defines how the Requirements & uses panel names, labels, orders and groups an inspected item's task, hideout, craft and barter rows, and which display facts the catalog keeps so that a player can read each row without tarkov.dev ids.

## Requirements

### Requirement: The catalog keeps craft and barter display facts
A catalog snapshot SHALL keep, on each craft row, the product item and count, the station and its level, the unlocking task when one is set, and whether the required item is a tool; and on each barter row, the offered item and count, the trader and its minimum loyalty level, and the unlocking task when one is set. These facts SHALL be saved with the cached snapshot and read back from it.

#### Scenario: Craft facts kept
- **WHEN** a refresh normalizes a craft at station `station-a` level 1 whose product is `item-b` ×1 and whose required item is `item-a` ×1.5
- **THEN** the `item-a` craft row keeps product `item-b`, product count 1, station `station-a`, station level 1, no unlocking task and no tool flag

#### Scenario: Barter facts kept
- **WHEN** a refresh normalizes a barter from `trader-a` with `minTraderLevel` 1, no `taskUnlock`, and offered item `item-b` ×1
- **THEN** its row keeps offered item `item-b`, count 1, trader `trader-a`, trader level 1 and no unlocking task

#### Scenario: Tool flag kept
- **WHEN** a craft's required item has the attribute `tool: true`
- **THEN** that row is marked as a tool

#### Scenario: Facts survive the cache
- **WHEN** a snapshot holding these facts is saved and loaded again
- **THEN** every kept fact on every craft and barter row is equal to the one before saving

#### Scenario: Malformed display fact
- **WHEN** a craft's `level` is the string `three`, or a barter's `minTraderLevel` is missing
- **THEN** the refresh still publishes the snapshot, that level is absent on the row, and every other fact on the row is kept

### Requirement: Display facts never change validation
Keeping display facts SHALL NOT add a reason for a catalog refresh to fail, and SHALL NOT remove one. Every existing integrity and reference check SHALL behave as before, and the snapshot's schema and normalizer versions SHALL stay the same.

#### Scenario: Existing reference check still rejects
- **WHEN** a craft names a product item that is not in the items dataset
- **THEN** the refresh fails validation as before and the last-good snapshot is kept

#### Scenario: Unresolvable craft unlock task
- **WHEN** a craft's `taskUnlock` names a task id that is not in the tasks dataset
- **THEN** the refresh still publishes the snapshot, and the row's unlocking task falls back to that id

### Requirement: Craft and barter rows name their source
A craft row's title SHALL be its product item's name, followed by `×N` when the product count is not 1, and its source line SHALL be `<station> level <L>`. A barter row's title SHALL be its offered item's name, with `×N` on the same rule, and its source line SHALL be `<trader> LL<L>`. When an unlocking task is set, the source line SHALL end with `, unlocked by <task>`. A level that is absent SHALL be left out of the line.

#### Scenario: Craft row
- **WHEN** the inspected item is used by a craft at the Workbench level 2 producing 2 `Gunpowder "Kite"`
- **THEN** the row's title is `Gunpowder "Kite" ×2` and its source line is `Workbench level 2`

#### Scenario: Barter row with an unlocking task
- **WHEN** the inspected item is used by a Prapor LL3 barter for one `AK-74N` unlocked by `Gunsmith - Part 4`
- **THEN** the row's title is `AK-74N` and its source line is `Prapor LL3, unlocked by Gunsmith - Part 4`

#### Scenario: Level absent
- **WHEN** a barter row has no trader level
- **THEN** its source line is the trader's name alone

### Requirement: Task and hideout rows name their source
A task row's title SHALL be the task's name. A hideout row's title SHALL be `<station> level <L>`, or the station's name alone when the level is absent.

#### Scenario: Hideout row
- **WHEN** the inspected item is a part of the Defective Wall level 2
- **THEN** the row's title is `Defective Wall level 2`

#### Scenario: Task row
- **WHEN** the inspected item is needed by the task `Delivery from the Past`
- **THEN** the row's title is `Delivery from the Past`

### Requirement: A missing name falls back to its id
When an item, trader, station or task name does not resolve, the row SHALL show that entity's id in its place, and the row SHALL still be shown. A station or task name SHALL first fall back to its normalized name when one is set. No row SHALL show a tarkov.dev id for an entity whose name resolves.

#### Scenario: Missing trader translation
- **WHEN** a barter's trader has no name in the traders dictionary
- **THEN** the row's source line shows the trader's id and the row is still listed

#### Scenario: Missing product item in a history catalog
- **WHEN** a craft row's product item id is not in the catalog the row is shown with
- **THEN** the row's title shows that product item id and the row is still listed

#### Scenario: Resolved names hide ids
- **WHEN** every name on a craft row resolves
- **THEN** no 24-character hexadecimal id appears anywhere in the row

### Requirement: Each row tags its kind and states its need in plain words
Each row SHALL carry a kind tag, `Task`, `Hideout`, `Craft` or `Barter`, and a state label: `Needed now` for actionable, `Needed later` for future, `Done` for satisfied and `Can't confirm` for unresolved. An irrelevant row SHALL be labelled as the next requirement says. A raw state or kind name SHALL NOT be shown.

#### Scenario: Unknown progress
- **WHEN** a hideout row is unresolved because progress authority is unknown
- **THEN** its tag reads `Hideout`, its state reads `Can't confirm`, and the texts `unresolved` and `hideout` do not appear in the row

#### Scenario: Actionable task
- **WHEN** a task row is actionable
- **THEN** its tag reads `Task` and its state reads `Needed now`

### Requirement: An irrelevant row says why it does not count
An irrelevant row's state label SHALL be `Optional use` on a craft or barter, `Optional objective` on an optional task objective, and `Needs found in raid` on a found-in-raid task or hideout row with more than 0 remaining, where this copy is not found in raid but the obligation stands. Any other irrelevant row SHALL read `Not for you`.

#### Scenario: Craft row state
- **WHEN** a craft row is shown
- **THEN** its tag reads `Craft`, its state reads `Optional use`, and the texts `irrelevant` and `craft` do not appear in the row

#### Scenario: Gate excludes the player
- **WHEN** a task row is irrelevant because the player's faction does not match the task's
- **THEN** its state reads `Not for you`

#### Scenario: Non-FIR copy of a FIR obligation
- **WHEN** a task row is irrelevant because the inspected copy is not found in raid, while the task needs a found-in-raid item with 2 remaining
- **THEN** its state reads `Needs found in raid`, not `Not for you`, and the row shows `2 remaining`

### Requirement: Rows show quantities only when they mean something
A row SHALL show `Needs N` when its count is known, with whole counts written without decimals, or `Tool, not used up` instead when the row is a craft tool. A row SHALL show `N remaining` only when the remaining quantity is known and its state is needed now, needed later, can't confirm or needs found in raid. A row SHALL show its found-in-raid rule only when the source states it, as `Found in raid required` or `Found in raid not required`.

#### Scenario: Optional use with unknown remaining
- **WHEN** a craft row needs 1.5 of the item and states no found-in-raid rule
- **THEN** the row shows `Needs 1.5`, shows no remaining text and shows no found-in-raid line

#### Scenario: Needed now
- **WHEN** a hideout row needs 2 of the item, 1 remains, and its found-in-raid rule is false
- **THEN** the row shows `Needs 2`, `1 remaining` and `Found in raid not required`

#### Scenario: Done row
- **WHEN** a task row is satisfied with 0 remaining
- **THEN** the row shows no remaining text

#### Scenario: Tool row
- **WHEN** a craft row is a tool needing 1
- **THEN** the row shows `Tool, not used up` and does not show `Needs 1`

#### Scenario: Count unknown
- **WHEN** a row's count is absent
- **THEN** the row shows no `Needs` text

### Requirement: The reason line does not repeat the source
An obligation row SHALL show its decision reason without the source name prefixed to it. A craft or barter row SHALL show no reason line, since its state already says it is optional. The decision's message SHALL keep its `<source>: <reason>` form.

#### Scenario: Hideout reason
- **WHEN** a hideout row of the Defective Wall is unresolved with the reason `station module status unknown`
- **THEN** its reason line reads `station module status unknown` and does not start with `Defective Wall`

#### Scenario: Craft reason
- **WHEN** a craft row is shown
- **THEN** the text `optional use, not an automatic obligation` does not appear in the row

### Requirement: Obligations come first and optional uses group after them
Task and hideout rows SHALL be listed first, ordered needed now, needed later, can't confirm, done, then the rest, keeping catalog order within a state. Craft and barter rows SHALL follow under one `Optional uses (N)` header, collapsed by default and again for each newly inspected item, where N is their number; opening the header SHALL list them in catalog order. With no craft or barter row, no header SHALL be shown.

#### Scenario: Mixed rows
- **WHEN** an item has a satisfied task row, an actionable hideout row and three craft rows
- **THEN** the panel lists the hideout row, then the task row, then a collapsed `Optional uses (3)` header with no craft row visible

#### Scenario: Open the group
- **WHEN** the player taps `Optional uses (3)`
- **THEN** the three craft rows are listed below the header

#### Scenario: Only optional uses
- **WHEN** an item has only barter rows
- **THEN** the panel shows only the collapsed `Optional uses (N)` header

#### Scenario: A new item starts collapsed
- **WHEN** the player has opened `Optional uses (3)` and then a different item is inspected
- **THEN** the new item's `Optional uses` header is collapsed

#### Scenario: No optional uses
- **WHEN** an item has only task rows
- **THEN** no `Optional uses` header is shown

### Requirement: Older cached projections still load
A cached catalog projection saved without the new display facts SHALL load without error. Its craft and barter rows SHALL keep their stored source name as the title and show no source line until a refresh replaces the snapshot.

#### Scenario: Cached projection from before this change
- **WHEN** the app loads a cached projection whose craft rows have the source name `craft craft-a` and no display facts
- **THEN** the snapshot loads, the row's title is `craft craft-a`, its tag reads `Craft` and its state reads `Optional use`

#### Scenario: Refresh replaces the old projection
- **WHEN** that cached projection is followed by a successful refresh
- **THEN** the craft row's title is its product item's name

### Requirement: Row display does not change decisions
Keeping display facts and changing the row display SHALL NOT change any requirement's need state, remaining quantity, the found-in-raid totals or the recommendation for the same catalog, progress and inspection.

#### Scenario: Same decision before and after
- **WHEN** the existing decision tests evaluate their catalogs, progress and inspections after this change
- **THEN** every need state, remaining quantity, found-in-raid total and recommendation they assert is unchanged

#### Scenario: Tool flag does not count
- **WHEN** a craft row is a tool
- **THEN** its need state is still optional use and the found-in-raid totals are the same as for the same craft without the tool flag
