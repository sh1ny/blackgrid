# Proposal

## Why

Raids entered on Terminal by transit count as "Unknown map" in the stats dialog, and Terminal never gets its own row (#129). When a raid starts from a transit or reconnect line, the map comes from that line's `location:` value. The table that reads it knows every supported map except Terminal and Labyrinth, so those raids get no map. The owner's seasonal stats show 6 null-map transit raids on the days they were grinding Terminal, and no Terminal row at all.

This is a corrective entry in M10, the current milestone, added from #129. It advances no M10 exit criterion. It fixes the local stats behaviour shipped earlier, where a raid on a supported map must count under that map. The game's exact location string is checked by a `[user]` task, because agents don't read the game's logs.

## What Changes

- A transit or reconnect line whose `location:` is `terminal` or `labyrinth`, compared case-insensitively, resolves to the Terminal or Labyrinth map, so the raid starts on that map and is counted under it.
- Raids stored before the fix keep no map and stay "Unknown map". Nothing is rebuilt or migrated.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `game-log-input`: the rejoin line must resolve every supported map that a transit or reconnect can enter, including Terminal and Labyrinth.

## Impact

- `lib/data/game_log/game_locations.dart` (`rejoinLocationMapId`) and its tests under `test/data/game_log/`.
- No schema, settings, dependency or UI changes. Stats rows already stored are untouched.
- Roadmap: a corrective entry in M10 that names #129.

## Decision Making

DECISION_MAKING: important
- **Source:** setting (`openspec/specwright.yaml`).

### S1: Fix raids from now on; leave stored rows as they are

- **Choice:** Only raids recorded after the fix get the right map. The 7 stored null-map rows stay "Unknown map".
- **Rejected:** Re-read the logs behind stored null-map transit rows and fill in their map. That needs a one-off repair that re-reads game log files, and it is a lot of change for 7 rows.
- **Reversal cost:** low. A repair could still be added later.
- **Important:** yes. It changes what users see in their stats.
- **Chosen by:** user

### S2: Include Labyrinth

- **Choice:** Add `labyrinth` alongside `terminal`. The scene table already knows it, and the rejoin table has the same gap.
- **Rejected:** Terminal only. That would leave the same bug in place for Labyrinth.
- **Reversal cost:** low.
- **Important:** yes. It changes what users see in their stats.
- **Chosen by:** user

### S3: Confirm the location string with one owner-supplied log line

- **Choice:** Assume the transit line uses `location:terminal` (any case), the same name as the scene, and have the owner confirm it with one real line before merge. That check is a `[user]` task.
- **Rejected:** Ship on the assumption alone. The evidence for it is indirect.
- **Reversal cost:** low.
- **Important:** yes. The string was chosen on weak evidence.
- **Chosen by:** user

## Release Notes

Raids entered on Terminal or Labyrinth by transit or reconnect now count under that map in Stats, not under "Unknown map". Raids counted before this fix keep their "Unknown map" entry.

### Fixed
- Transit and reconnect raids on Terminal and Labyrinth count under their map in Stats, not under "Unknown map" (#129).
