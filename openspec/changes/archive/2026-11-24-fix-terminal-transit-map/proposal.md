# Proposal

## Why

Raids entered on Terminal by transit count as "Unknown map" in the stats dialog, and Terminal never gets its own row (#129). The owner's game logs show two causes.

First, a Terminal transit writes `Transit reconnect ... location:Terminal`, and the table that reads that location has no Terminal entry. Second, the line logged right after it, `scene preset path:maps/terminal_preset.bundle`, names a scene the scene table doesn't know either, because the table only accepts the bare `terminal`. While the raid loads, that unrecognised scene replaces the map, so it would erase the right map even once the location is fixed. The same scene gap also stops the Map tab from detecting Terminal.

In the owner's seasonal stats, 8 of the 9 "Unknown map" raids are Terminal transits. Each points at a `location:Terminal` line, and Terminal has no row.

This is a corrective entry in M10, the current milestone, added from #129. It advances no M10 exit criterion. It fixes the local stats behaviour shipped earlier, where a raid on a supported map must count under that map. The owner asked the agent to check the real log lines, so the evidence is captured from the logs rather than through a `[user]` task.

## What Changes

- A transit or reconnect line whose `location:` is Terminal or Labyrinth, compared case-insensitively, resolves to that map.
- The scene names `terminal_preset` and `labyrinth_preset` resolve to Terminal and Labyrinth. This adds to the bare names, which keep working.
- During loading, a scene with no supported map no longer replaces a map already known for the pending raid, whether that map came from a transit or reconnect location or from an earlier scene. A supported scene still replaces it. An unsupported scene still publishes a map-known transition with no map in a queue.
- Raids stored before the fix keep no map and stay "Unknown map". Nothing is rebuilt or migrated.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `game-log-input`: the rejoin line must resolve every supported map a transit or reconnect can enter, including Terminal and Labyrinth. The Terminal and Labyrinth `_preset` scene names must resolve to their maps.
- `raid-lifecycle`: a raid's map is no longer erased by a later scene that names no supported map.

## Impact

- `lib/data/game_log/game_locations.dart` (`sceneMapId`, `rejoinLocationMapId`) and `lib/domain/raid_lifecycle.dart` (scene-loaded reduction), with tests under `test/data/game_log/` and `test/domain/`.
- The Map tab now detects Terminal from its scene. Stats count Terminal transit raids under Terminal.
- No schema, settings, dependency or UI changes. Stats rows already stored are untouched.
- Roadmap: a corrective entry in M10 that names #129.

## Decision Making

DECISION_MAKING: important
- **Source:** setting (`openspec/specwright.yaml`).

### S1: Fix raids from now on; leave stored rows as they are

- **Choice:** Only raids recorded after the fix get the right map. The stored null-map rows stay "Unknown map".
- **Rejected:** Re-read the logs behind stored null-map transit rows and fill in their map. That needs a one-off repair that re-reads game log files, which is a lot of change for a handful of rows.
- **Reversal cost:** low. A repair could still be added later.
- **Important:** yes. It changes what users see in their stats.
- **Chosen by:** user

### S2: Include Labyrinth

- **Choice:** Add Labyrinth alongside Terminal in both tables.
- **Rejected:** Terminal only. That would leave the same gap for Labyrinth.
- **Reversal cost:** low.
- **Important:** yes. It changes what users see in their stats.
- **Chosen by:** user

### S3: Settle the location and scene names from the owner's real logs

- **Choice:** Read the owner's game log lines and capture them as evidence. The owner said: "check the actual logs, should be plenty of entries about it. Tarkov is not running, so you can read the logs safely." This replaces the earlier plan in which the owner pasted one line.
- **Rejected:** Ship on the assumption alone. The logs showed that assumption was incomplete, because the scene is `terminal_preset`.
- **Reversal cost:** low.
- **Important:** yes. The first evidence was weak.
- **Chosen by:** user

### S4: Accept the `terminal_preset` scene name

- **Choice:** Map `terminal_preset` to Terminal. Without it, the scene line after a Terminal transit erases the map and the stats fix does nothing.
- **Rejected:** Fix only the transit table. The logs show that alone leaves Terminal raids unknown.
- **Reversal cost:** low.
- **Important:** yes. It changes what users see: Map detection and stats.
- **Chosen by:** user

### S5: Accept `labyrinth_preset` by analogy

- **Choice:** Map `labyrinth_preset` to Labyrinth, following Terminal's naming. The owner's logs hold no Labyrinth raid, so this name is unverified, and it is harmless if the game never logs it.
- **Rejected:** Accept only proven names. That would probably leave Labyrinth with the same gap until someone logs a raid there.
- **Reversal cost:** low.
- **Important:** yes. It was chosen on weak evidence.
- **Chosen by:** user

### S6: An unsupported scene keeps the map already known

- **Choice:** During loading, a scene with no supported map leaves the pending raid's map as it is, so an unrecognised scene name can't erase a known transit map.
- **Rejected:** Keep the lifecycle unchanged and rely only on the table fixes. That keeps working for today's names but breaks again on the next rename.
- **Reversal cost:** low.
- **Important:** yes. It changes raid behaviour users see and amends the `raid-lifecycle` spec.
- **Chosen by:** user

## Release Notes

Raids entered on Terminal or Labyrinth by transit or reconnect now count under that map in Stats, not under "Unknown map". The Map tab now detects Terminal. Raids counted before this fix keep their "Unknown map" entry.

### Fixed
- Transit and reconnect raids on Terminal and Labyrinth count under their map in Stats, not under "Unknown map". Raids counted before this fix keep their "Unknown map" entry.
- The Map detects Terminal, and an unrecognised scene no longer erases a raid's known map.
