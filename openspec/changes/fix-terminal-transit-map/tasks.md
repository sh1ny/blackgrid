# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| game-log-input → Application log lines become lifecycle events | Menu events | test/data/game_log/game_log_parsers_test.dart | session mode and profile selected | green |
| game-log-input → Application log lines become lifecycle events | Rejoin line | test/data/game_log/game_log_parsers_test.dart | transit reconnect line becomes raid rejoined | green |
| game-log-input → Application log lines become lifecycle events | Rejoin into Terminal or Labyrinth | test/data/game_log/game_log_parsers_test.dart | transit reconnect into Terminal or Labyrinth has its map | red |
| game-log-input → Application log lines become lifecycle events | Every supported map can be rejoined | test/data/game_log/game_log_parsers_test.dart | rejoin locations are case-insensitive and cover every map | red |
| game-log-input → Application log lines become lifecycle events | Rejoin into an unknown location | test/data/game_log/game_log_parsers_test.dart | transit reconnect into an unknown location has no map | red |
| game-log-input → Application log lines become lifecycle events | A full raid in the application log | test/data/game_log/game_log_parsers_test.dart | full raid lines in order | green |
| game-log-input → Application log lines become lifecycle events | Matching cancelled | test/data/game_log/game_log_parsers_test.dart | matching cancelled line | green |
| game-log-input → Application log lines become lifecycle events | Unknown scene | test/data/game_log/game_log_parsers_test.dart | unknown scene has no map | green |
| game-log-input → Application log lines become lifecycle events | Event map presets | test/data/game_log/game_log_parsers_test.dart | event presets map to Factory and The Lab | green |
| game-log-input → Application log lines become lifecycle events | Unrelated line | test/data/game_log/game_log_parsers_test.dart | unrelated line produces nothing | green |

The unknown-location row starts red only because its test is new. The behaviour already holds, so it may pass as soon as it is written. That is expected and is not a red-first failure.

## 1. Rejoin table covers Terminal and Labyrinth

- [ ] 1.1 Verify A1 as far as the repo allows: confirm that `sceneMapId` and `supportedMaps` use the IDs `terminal` and `labyrinth`. The real transit location string stays with the owner in 2.2. Verify by reading `lib/data/game_log/game_locations.dart` and `lib/domain/settings.dart`.
- [ ] 1.2 Write the failing tests in `test/data/game_log/game_log_parsers_test.dart`. (a) `transit reconnect into Terminal or Labyrinth has its map`: `location:Terminal` and `location:terminal` give map `terminal`, and `location:Labyrinth` gives `labyrinth`. (b) Extend `rejoin locations are case-insensitive and cover every map` so that every ID in `supportedMaps` is reached by at least one location (D2). (c) `transit reconnect into an unknown location has no map`: location `nowhere`, map null. Run `mise run test -- test/data/game_log/game_log_parsers_test.dart`. (a) and (b) must fail because Terminal and Labyrinth map to null.
- [ ] 1.3 Add `terminal` and `labyrinth` to `rejoinLocationMapId` (D1), and write C1 into its doc comment: the table must reach every supported map, and the coverage test enforces it. Verify that the 1.2 tests pass, then flip their test-map rows green.
- [ ] 1.4 Run `mise run analyze` and `mise run test` and format with `dart format`. Verify that all of them pass.

## 2. Roadmap and owner check

- [ ] 2.1 Add `fix-terminal-transit-map` to M10's change list in `openspec/roadmap.md` as a corrective entry from #129. Verify by reading the roadmap.
- [ ] 2.2 [user] Paste one real `Transit reconnect ... location:` line from a raid entered on Terminal, to confirm A1. If you can, also say whether Terminal raids now count under Terminal in Stats.

## Workflow follow-up

- Pre-ship review, PR with `Closes #129`, archive.
