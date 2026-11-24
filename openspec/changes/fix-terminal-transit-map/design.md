# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components (new component, or 3+ with directed relationships) | no | One pure function changes: `lib/data/game_log/game_locations.dart:37-51`. |
| T2 State (persistent state, caches, 3+ state machine) | no | No stored data or state machine changes. The raid lifecycle already takes the rejoin event's map as given (`lib/domain/raid_lifecycle.dart:1037-1041`). |
| T3 Concurrency (background work, workers/isolates, async, retries) | no | Synchronous lookup on the parse path (`lib/data/game_log/game_log_parsers.dart:100-110`). |
| T4 Boundaries (data format, migration, shared interface, IPC, external) | no | The game's log line format and its parser regex are unchanged (`lib/data/game_log/game_log_parsers.dart:86-89`). Only the set of recognised location values grows. No stored-row migration (proposal S1). |
| T5 Volume (grows without a fixed bound) | no | A fixed set of map names. |
| T6 Risk (security, money, data loss, unrecoverable user data) | no | Stored stats rows are never touched (proposal S1). |

TIER: LIGHT

## Context

- A transit or reconnect line produces a raid-rejoined event whose map is `rejoinLocationMapId(location)` (`lib/data/game_log/game_log_parsers.dart:100-110`).
- `rejoinLocationMapId` knows every supported map except Terminal and Labyrinth and returns `null` for anything else (`lib/data/game_log/game_locations.dart:37-51`). `supportedMaps` lists 13 maps, including `terminal` and `labyrinth` (`lib/domain/settings.dart:5-19`).
- The scene table already maps the bare `terminal`, `icebreaker` and `labyrinth` scene names to their IDs (`lib/data/game_log/game_locations.dart:30`).
- A rejoin sets the pending map to the event's map (`lib/domain/raid_lifecycle.dart:1037-1041`). The started raid takes that pending map (`lib/domain/raid_lifecycle.dart:1069-1070`), and the stats controller stores it as the raid row's map (`lib/application/local_stats_controller.dart:109-117`). So a `null` from the table becomes an "Unknown map" row.
- The existing test named "rejoin locations are case-insensitive and cover every map" leaves out Terminal and Labyrinth, so it never caught the gap (`test/data/game_log/game_log_parsers_test.dart:135-158`).

## Decisions

### D1: Add explicit entries to the rejoin table

- **Choice:** Add `'terminal' => 'terminal'` and `'labyrinth' => 'labyrinth'` to `rejoinLocationMapId`. The lookup stays case-insensitive.
- **Rejected:** Resolve rejoin locations through `sceneMapId`, making one shared table. That loses because the two inputs use different names. Transit locations are location IDs such as `bigmap` and `laboratory_event`, and scenes are bundle names such as `customs_preset` and `laboratory_preset`. Merging them would accept names that never occur in one of the two lines, and would tie two independent game formats together.
- **Reversal cost:** low
- **Important:** no
- **Chosen by:** agent

### D2: Make the coverage test check every supported map

- **Choice:** Extend the rejoin coverage test so that every ID in `supportedMaps` is reached by at least one location. A map added later without a rejoin entry then fails the fast test suite.
- **Rejected:** Only add the two missing rows to the hand-written expected map. That repeats the gap the old test already had: nothing ties it to `supportedMaps`.
- **Reversal cost:** low
- **Important:** no
- **Chosen by:** agent

### Decision summary

| # | Decision | Choice | Rejected | Reversal cost | Important | Chosen by |
|---|---|---|---|---|---|---|
| S1 | Stored rows | Fix raids from now on; stored rows stay Unknown map | Repair stored null-map rows from the logs | low | yes (changes what users see) | user |
| S2 | Labyrinth | Include Labyrinth with Terminal | Terminal only | low | yes (changes what users see) | user |
| S3 | Location string evidence | Assume `terminal`/`labyrinth`; owner confirms one real line | Ship on the assumption alone | low | yes (weak evidence) | user |
| D1 | How to map the new locations | Explicit rejoin-table entries | Reuse the scene table | low | no | agent |
| D2 | Coverage guard | Test that every supported map is reachable | Two more hand-written rows | low | no | agent |

## Assumptions

- **A1:** The game's transit or reconnect line names Terminal as `location:Terminal` or `location:terminal`, and Labyrinth as `location:Labyrinth` or `location:labyrinth`. Any case works, because the lookup ignores case. Not checked because agents don't read the game's own log files (AGENTS.md). The evidence is indirect: the scene names match, and the owner's 6 null-map transit raids fall on their Terminal days. Depends on it: D1, and the `[user]` confirmation task (proposal S3).

## Carried constraints

- **C1:** The rejoin table must reach every ID in `supportedMaps`. A newly supported map needs its transit location added here too, or its transit raids count as "Unknown map". The D2 test enforces this. Kind: invariant. Destination: doc comment: `lib/data/game_log/game_locations.dart` `rejoinLocationMapId`
