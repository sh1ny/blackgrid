# Review

## Metadata

- **Round:** 1
- **Prior round:** Round 1 full review: APPROVE_WITH_CHANGES with three Required Changes (requirement parenthetical, "Map unknown" WHEN, stale tasks.md) and `CHANGES_APPLIED: no`. This run is the re-check of those items only.
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer)
- **Reviewed:** the working-tree diff against HEAD (5adb107) of `openspec/changes/fix-terminal-transit-map/` design.md, specs/raid-lifecycle/spec.md and tasks.md; the full proposal.md, design.md and both delta specs (specs/game-log-input/spec.md, specs/raid-lifecycle/spec.md) to cross-check the test map; the prior review.md. To confirm the test-map anchors I read `test/data/game_log/game_log_parsers_test.dart` and `test/domain/raid_lifecycle_test.dart` (test names, the `raid record` group at line 194), `lib/domain/raid_lifecycle.dart:1005-1045` (`_sceneLoaded`, `_raidRejoined`) and `openspec/architecture.md:139`. All are tracked (`git ls-files`). I also checked the `[evidence]` task marker against `openspec instructions tasks`. No skills were named for this re-check, and none were loaded.

## Findings

### Critical (blocking)

None.

### Moderate

1. **Fixed: the amended requirement text contradicted the design for an unknown rejoin location after a known map.** The parenthetical now reads: "from the last scene loaded or rejoin location since the queue; a rejoin sets the map to its location's map, unknown when the location is not recognised; a scene with no supported map SHALL NOT replace a map already known". This is the wording Required Change 1 asked for. It guards only scenes, which matches D3, the T2 diagram (`Known --> NoMap: rejoin with unknown location`) and `_raidRejoined` writing `pendingMapId: e.mapId` (`lib/domain/raid_lifecycle.dart:1041`).

2. **Fixed: the "Map unknown" scenario contradicted the new queue scenario.** Its WHEN now reads: "a raid starts after a scene-loaded event with no supported map, and no earlier scene or rejoin location since the queue named a supported map". It no longer overlaps "Unsupported scene in a queue after a known scene". The existing test `unsupported scene leaves the map unknown` (`test/domain/raid_lifecycle_test.dart:216`) still fits the narrowed case.

3. **Fixed: tasks.md was stale against the amended proposal and design.** The regenerated tasks.md has:
   - A test-map row for every scenario. That is all 11 game-log-input scenarios, including "Terminal and Labyrinth preset scenes", and all 6 raid-lifecycle scenarios. Every green row names a test that exists: each of the eight parser test names occurs once in `game_log_parsers_test.dart`, and `records map, mode, times, entry and cause` and `unsupported scene leaves the map unknown` are at `raid_lifecycle_test.dart:195` and `:216`.
   - The scene-table entries (`terminal_preset`, `labyrinth_preset`) in 1.3, and the scene coverage check tied to `supportedMaps` (D2) in 1.2(d).
   - The `_sceneLoaded` guard (D3) in 2.2, with its four reducer tests in 2.1. The tests that should fail red-first (the transit-map test and the queue test) fail for the stated reason. Group 2 runs after 1.3, so the Terminal rejoin already resolves and only the unsupported scene erases the map. The rows whose behaviour already holds are named in the note under the map.
   - Task 1.1 as the evidence capture: `[evidence] ... → evidence/owner-log-lines.txt`, in the marker form that the tasks instruction defines. The design's Context pointer now names the same file.
   - No `[user]` task. The owner's Stats/Map check after merge appears under Workflow follow-up as an optional check that does not gate anything, which matches S3.
   - Suggestion 1 is also applied, as task 1.4 (architecture.md line 139).

### Suggestions

1. **Applied:** `terminal_preset` is added to the game-inputs paragraph of `openspec/architecture.md` (task 1.4).
2. **Applied:** D3 now explains why the map-known transition and the raid map differ in a queue whose second scene is unsupported.

Out-of-scope edits checked:
- **D3 rationale note.** It adds two points. The guard covers scenes only, and a rejoin with an unknown location still sets a null map. A queue whose second scene is unsupported reports "no map" while the raid keeps the earlier map. Both restate behaviour that the T2 diagram, the Flow section, C2 and the "Unsupported scene in a queue after a known scene" scenario already define. The Choice, the rejected alternatives, the decision summary row and `Chosen by` are unchanged. The note does not change the design.
- **Context pointer.** "(captured in task 1.1)" became "(captured in task 1.1 as `evidence/owner-log-lines.txt`)". The pointer now names a destination and makes no new claim.

No other line in proposal.md, design.md or the delta specs changed since the reviewed commit, so the verdict still covers the reviewed contents.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. In `specs/raid-lifecycle/spec.md`, replace the requirement's parenthetical with: "its map (from the last scene loaded or rejoin location since the queue; a rejoin sets the map to its location's map, unknown when the location is not recognised; a scene with no supported map SHALL NOT replace a map already known)". **Applied and re-checked.**
2. In `specs/raid-lifecycle/spec.md`, change the "Map unknown" scenario's WHEN to: "a raid starts after a scene-loaded event with no supported map, and no earlier scene or rejoin location since the queue named a supported map". **Applied and re-checked.**
3. Before the tasks precheck, regenerate `tasks.md` from the amended proposal, design and specs. It needs a test-map row for every scenario in both delta specs; tasks for the scene-table entries, the scene coverage test, and the `_sceneLoaded` guard with its raid-lifecycle tests; task 1.1 as the log-evidence capture the design names; and no `[user]` paste task. **Applied and re-checked.**

CHANGES_APPLIED: yes

## Rebuttals

None. The author applied every Required Change and did not rebut any finding.
