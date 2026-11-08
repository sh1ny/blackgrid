# Review

## Metadata

- **Round:** 3
- **Prior round:** 2
- **Mode:** required-changes re-check. Only the two remaining Round 2 Required Changes and Note N1 were checked, plus contradictions or false code claims introduced by those fixes.
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer)
- **Reviewed:** `openspec/changes/restyle-map-workspace/` review.md (round 2), proposal.md, design.md, `specs/map-controls`; `lib/data/screenshot_directory_watcher.dart`, `lib/application/map_session_controller.dart`. Project skills: none named in the request.

## Findings

### Round 1 Required Changes

1. **(C1) Applied** (confirmed round 2).
2. **(M1) Applied** (confirmed round 2).
3. **(M2) Applied** (confirmed round 2).
4. **(M3) Applied** (confirmed round 2).
5. **(M4) Applied** (confirmed round 2).
6. **(M5) Applied** (confirmed round 3). D8 replaces the nullable return with a sealed result (found, empty, unavailable, discarded) and maps it to the session outcomes. Proposal Impact names `lib/data/screenshot_directory_watcher.dart`. `map-controls` has "Screenshot folder is unavailable", and its notice matches D8's unavailable outcome. Each path that yields `null` today:

   | Path today | Condition | D8 result | Session outcome |
   |---|---|---|---|
   | `screenshot_directory_watcher.dart:289` | Watcher closed | discarded | superseded |
   | `:134` to `:299` | Folder missing | unavailable | unavailable |
   | `:170` to `:299` | `FileSystemException` while listing | unavailable | unavailable |
   | `:162` to `:299` | Folder exists, no png or jpeg | empty | no screenshot |
   | `:178` | Newest entry is zero bytes or not a file | unavailable (unreadable) | unavailable |
   | `:185` | Over `maxBytes` | unavailable (oversized) | unavailable |
   | `:188` | Closed or generation moved after the delay | discarded | superseded |
   | `:191` | Size or time changed | unavailable (still changing) | unavailable |
   | `:200` | Closed or generation moved | discarded | superseded |
   | `:200` | Length, size or time mismatch | unavailable (still changing) | unavailable |
   | `:216` | `FileSystemException` during the read | unavailable | unavailable |
   | `:127` to `:299` | No folder bound | not named in D8; see N2 | see N2 |
   | `map_session_controller.dart:351` | `_closed`, or `order` or `context` moved | any result is overridden | superseded; see N3 |

   The one conjunct of `:351` that the sealed result removes is `saved == null`. The `:200` condition mixes two results, so the implementation has to test closed and generation first, as D8's definitions require.

7. **(M6) Applied** (confirmed round 2).

### Introduced by the C1 fix

- **Diagram label: Applied** (confirmed round 3). The component diagram reads `Raid -->|revealMarker| Maps[MapController]` (design.md:134), and no `setSelectedMarker` label remains in design.md.

### Introduced by these fixes

None. No contradiction or false claim about the code was found.

### Notes (non-blocking)

- **N1: Applied.** The State & Ownership row for Raid match time says it is unchanged by the re-match at `:339` and cleared in `_invalidate`. Both references fit the code: `_refreshEvidenceForMap` writes highlights at `map_session_controller.dart:339` and reads no new screenshot, and `_invalidate` (`:155`-`:169`) clears the highlights at `:166`. The row's `:477` is the actual highlight write in the screenshot path.
- **N2.** `_list` also returns `[]` when the watcher has no folder bound (`:127`), and D8's four definitions do not name that case. The picker item is disabled with no folder, and clearing the setting invalidates the context, so it can only be reached in the short window while a bind is settling. Treat it as unavailable when writing the exhaustive switch.
- **N3.** D8 says a "context change" makes the read superseded, but `:351` also checks `order`, which a watched screenshot advances without changing the context (`:140`). Keep the `order` check and report superseded for it. The later watched screenshot then wins, and no notice is shown.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

All Required Changes are applied. None remain.

CHANGES_APPLIED: yes

## Rebuttals
