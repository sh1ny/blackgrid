# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| game-log-input → Application log lines become lifecycle events | Menu events | test/data/game_log/game_log_parsers_test.dart | session mode and profile selected | green |
| game-log-input → Application log lines become lifecycle events | Rejoin line | test/data/game_log/game_log_parsers_test.dart | transit reconnect line becomes raid rejoined | green |
| game-log-input → Application log lines become lifecycle events | Rejoin into Terminal or Labyrinth | test/data/game_log/game_log_parsers_test.dart | transit reconnect into Terminal or Labyrinth has its map | green |
| game-log-input → Application log lines become lifecycle events | Every supported map can be rejoined | test/data/game_log/game_log_parsers_test.dart | rejoin locations are case-insensitive and cover every map | green |
| game-log-input → Application log lines become lifecycle events | Rejoin into an unknown location | test/data/game_log/game_log_parsers_test.dart | transit reconnect into an unknown location has no map | green |
| game-log-input → Application log lines become lifecycle events | A full raid in the application log | test/data/game_log/game_log_parsers_test.dart | full raid lines in order | green |
| game-log-input → Application log lines become lifecycle events | Matching cancelled | test/data/game_log/game_log_parsers_test.dart | matching cancelled line | green |
| game-log-input → Application log lines become lifecycle events | Unknown scene | test/data/game_log/game_log_parsers_test.dart | unknown scene has no map | green |
| game-log-input → Application log lines become lifecycle events | Event map presets | test/data/game_log/game_log_parsers_test.dart | event presets map to Factory and The Lab | green |
| game-log-input → Application log lines become lifecycle events | Terminal and Labyrinth preset scenes | test/data/game_log/game_log_parsers_test.dart | Terminal and Labyrinth preset scenes have their map | green |
| game-log-input → Application log lines become lifecycle events | Unrelated line | test/data/game_log/game_log_parsers_test.dart | unrelated line produces nothing | green |
| raid-lifecycle → A raid records its map, mode, times and entry | Recorded raid | test/domain/raid_lifecycle_test.dart | records map, mode, times, entry and cause | green |
| raid-lifecycle → A raid records its map, mode, times and entry | Map unknown | test/domain/raid_lifecycle_test.dart | unsupported scene leaves the map unknown | green |
| raid-lifecycle → A raid records its map, mode, times and entry | Unsupported scene after a transit keeps the transit map | test/domain/raid_lifecycle_test.dart | unsupported scene after a transit keeps the transit map | red |
| raid-lifecycle → A raid records its map, mode, times and entry | Supported scene after a rejoin replaces the map | test/domain/raid_lifecycle_test.dart | supported scene after a rejoin replaces the map | red |
| raid-lifecycle → A raid records its map, mode, times and entry | Unknown rejoin and unsupported scene | test/domain/raid_lifecycle_test.dart | unknown rejoin and unsupported scene leave the map unknown | red |
| raid-lifecycle → A raid records its map, mode, times and entry | Unsupported scene in a queue after a known scene | test/domain/raid_lifecycle_test.dart | unsupported scene in a queue keeps the earlier map | red |

Some rows start red only because their test is new. Their behaviour already holds, so they may pass as soon as they are written: the unknown-location rejoin, the scene that replaces a rejoin map, and the unknown rejoin followed by an unsupported scene. That is expected and is not a red-first failure.

## 1. Lookup tables cover Terminal and Labyrinth

- [x] 1.1 [evidence] Capture the owner's real log lines that settle the names: the `location:Terminal` transit lines behind the stored null-map raids, the `terminal_preset` scene line that follows each one, and the tally of transit locations and scene names across all session folders. Copy the lines from the logs and keep no profile or account IDs. → evidence/owner-log-lines.txt
- [x] 1.2 Write the failing parser tests in `test/data/game_log/game_log_parsers_test.dart`:
  - (a) `transit reconnect into Terminal or Labyrinth has its map`: `location:Terminal` and `location:terminal` give `terminal`, and `location:Labyrinth` gives `labyrinth`.
  - (b) Extend `rejoin locations are case-insensitive and cover every map` so every ID in `supportedMaps` is reached by at least one rejoin location (D2).
  - (c) `transit reconnect into an unknown location has no map`: location `nowhere` gives a null map.
  - (d) `Terminal and Labyrinth preset scenes have their map`: `terminal_preset` gives `terminal` and `labyrinth_preset` gives `labyrinth`. Add a scene coverage check so every ID in `supportedMaps` is reached by at least one scene name (D2).

  Run `mise run test -- test/data/game_log/game_log_parsers_test.dart`. (a), (b) and (d) must fail because those names map to null.
- [x] 1.3 Add `terminal` and `labyrinth` to `rejoinLocationMapId`, and `terminal_preset` and `labyrinth_preset` to `sceneMapId` (D1). Write C1 into the doc comment of `rejoinLocationMapId`: every supported map must be reachable from both tables, and the coverage tests enforce it. Verify that the 1.2 tests pass, then flip their test-map rows green.
- [x] 1.4 Add `terminal_preset` to the recognised scenes in the game-inputs paragraph of `openspec/architecture.md`. Verify by reading the paragraph.

## 2. An unsupported scene keeps the known map

- [ ] 2.1 Write the failing reducer tests in the `raid record` group of `test/domain/raid_lifecycle_test.dart`:
  - `unsupported scene after a transit keeps the transit map`: a Shoreline raid ends, then profile selected, rejoin Terminal, an unsupported scene and raid started. The raid is on `terminal` with entry transit.
  - `supported scene after a rejoin replaces the map`: rejoin Woods, then a Customs scene and raid started. The map is `customs`.
  - `unknown rejoin and unsupported scene leave the map unknown`.
  - `unsupported scene in a queue keeps the earlier map`: queue, Customs scene, unsupported scene and raid started. The raid map is `customs`, and the second scene publishes one map-known transition with no map.

  Run `mise run test -- test/domain/raid_lifecycle_test.dart`. The transit-map and queue tests must fail because the unsupported scene erases the map.
- [ ] 2.2 In `_sceneLoaded`, keep the pending map when the scene names no supported map (D3), and say so in its comment. The map-known transition keeps the scene's own map. Verify that the 2.1 tests and the whole `test/domain/` folder pass, flip the 2.1 rows green, and re-run `unsupported scene leaves the map unknown` and `records map, mode, times, entry and cause` (rows already green).
- [ ] 2.3 Add `fix-terminal-transit-map` to M10's change list in `openspec/roadmap.md` as a corrective entry from #129. Verify by reading the roadmap.
- [ ] 2.4 Run `mise run analyze` and `mise run test`, and format with `dart format`. Verify that all of them pass.

## Workflow follow-up

- Pre-ship review, PR with `Closes #129`, archive.
- After merge the owner may check that the next Terminal transit raid counts under Terminal in Stats and that the Map tab detects Terminal. It is not a gate, because the parser and reducer tests prove the behaviour from the owner's real lines.
