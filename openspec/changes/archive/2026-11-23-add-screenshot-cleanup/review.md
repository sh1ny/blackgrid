# Review

## Metadata

- **Round:** 4
- **Prior round:** Round 3 required reader-side replay provenance. The owner chose per-log byte positions; this round reviews that design, not the earlier timestamp-only approach.
- **Reviewer:** fresh-context subagent (omp)
- **Reviewed:** `add-screenshot-cleanup` proposal, design, tasks, prior review, both delta specs and runner smoke evidence; ADRs 0007, 0030 and 0045–0049; relevant architecture and raid-lifecycle contracts; the cited log selection/tail, lifecycle, settings, cleanup, composition, folder and Windows runner source. Loaded all four named Dart skills. No tests, builds, analysis, formatting, game or Blackgrid runs.

## Findings

### Critical (blocking)

**C1. A byte boundary is valid only for the log incarnation it measured.** D4 (`design.md:58–59`) says to retain the boundary across an I/O error at the same path and treats first appearance of a newer folder as proof that all its bytes are live. Neither a pathname nor a place in the folder sort order establishes that continuity. For example, bind sees a short application file and snapshots its size, but opening it fails before any bytes are consumed. An archived file with a recent start and menu ending is then restored at the same pathname. Its records can both start above the old boundary. The reader's replacement check compares path, folder and size versus consumed offset, and the tail has no consumed window to compare after the failed open (`lib/data/session_log_reader.dart:341–382`; `lib/data/game_log/log_file_tail.dart:160–187`). Carrying the old boundary forward as specified admits both replay records and can move a kept raid's screenshots. Likewise, a populated archive folder renamed into the watched root after a successful listing will be newer than the mark even though its bytes predate observation. A missing root is an additional false-zero risk: `listSessionFolders` returns the same `[]` as for a genuinely empty listing (`lib/data/game_log/session_folders.dart:74–87`).

Keep byte positions, but require evidence of the same log incarnation before reusing a boundary, and evidence of genuinely new input before using zero. Baseline populated or replaced input of unproven origin; don't turn missing or unavailable input into positive absence evidence. Define this in D4/ADR-0049 and add reader-to-cleanup cases in 7.1 for delayed read of the same file, same-path replacement before the first successful open, and a pre-populated session arriving in the root. Assert no claim or recycle for the replay and preserve a genuine append positive control. This concerns log provenance, not locking screenshot files against replacement.

**C2. A live byte is not proof that the switch was on when the raid ended.** D4 requires opt-in at actual end and D8 explicitly uses the restart profile's wall-clock timestamp for that decision (`design.md:60,97–100`), but neither establishes how to prove the end occurred after the saved toggle. Example: the original start is observed live while cleanup is off; the end is appended at 14:00:20 but delivery is deferred. The player winds the clock back and successfully enables cleanup at 14:00:11. The end is delivered when the clock again reads 14:00:22. Its byte is correctly marked live and it is fresh, but it sorts after the saved-enable time despite actually occurring before the toggle. `SettingsController` publishes the switch only after the save, and the delayed record carries a local wall-clock time, not a causal position relative to that save (`lib/application/settings_controller.dart:112–139`; `lib/domain/raid_lifecycle.dart:50–69`; `lib/domain/alert_rules.dart:14–20`). This can move files for the exact raid the spec says to leave alone (`specs/screenshot-cleanup/spec.md:25,43–45`).

Define a fail-closed opt-in boundary tied to the successful enable, so an already appended or ambiguous end cannot be authorized by its timestamp. For a crash, apply that boundary to the actual `ProfileSelected` end, not the queue that publishes it; keep queue freshness unchanged. Make the delayed pre-opt-in test in 7.1 exercise a live-but-unread end across clock rollback, with a fresh post-enable end as the positive control.

### Moderate

**M1. Remember new-session evidence while the application log is not yet selectable.** D4 describes a high-water folder name and boundaries for selected roles (`design.md:59,186`), but it does not give new-session evidence a lifetime independent of selection. The reader lists the root before selecting files and returns `null` when the newest folder has no application file; it deliberately preserves the interrupted raid across that wait (`lib/data/session_log_reader.dart:248–271,320–337`). If the mark advances when the new folder is first listed, the next successful selection is at that same mark, not newer. Treating it as an existing first selection baselines the crash profile and queue already written there, so D8 drops a valid ending. Tie any positive birth evidence to that folder across the wait for its first readable file; also specify when such evidence is lost or superseded. Add a split-scan regression with a new folder initially lacking application, then a genuine live crash-ending sequence; contrast with a pre-existing folder initially lacking application. See `specs/screenshot-cleanup/spec.md:31–33` and the raid-lifecycle restart contract.

**M2. Stalled preparation can stop cleanups and hide queue skips.** The queue's progress assumes an active run finishes, but folder preparation has no deadline (`design.md:196–211`). An ordinary configured UNC path is supported (`windows/runner/recycle_channel.cpp:94–103`), and directory iteration or per-file `stat` can stall before the native backstop starts (`lib/data/screenshot_folder_lister.dart:34–42`; `lib/application/screenshot_cleanup_controller.dart:173–210`). Waiting raids can be dropped without any result ever publishing the skip count. Bound or visibly suspend preparation, fence late results from dispatch, and don't accumulate abandoned I/O. Test with a held listing. Also have 7.2 explicitly remove 5.4's pre-log-bind screenshot resolution dependency: that await currently precedes `_logs.bind` (`lib/application/map_session_controller.dart:262–299`) and can keep Blackgrid from observing live starts at all.

**M3. The native no-recycle branch has no required negative check.** The no-bin scenario maps to a controller fake, the native smoke verified only a recycle-capable system drive, and 6.2 makes the real no-bin check conditional on the owner having such a drive (`tasks.md:26,98,105`; `evidence/runner-smoke.md:37–39`). None exercises the native veto on an actual nonrecyclable source (`windows/runner/recycle_channel.cpp:137–151,185–200`). Add a required offline Windows qualification/evidence case using an isolated nonrecyclable source; assert the source remains unchanged and is reported not moved. Keep the real raid check with the owner.

**M4. An open file is not necessarily locked against a move.** The locked-file scenario promises that one file stays merely because another program has it open (`specs/screenshot-cleanup/spec.md:101–103`). A Windows handle opened with delete sharing does not prevent the move; the runner delegates to the Shell rather than treating every open handle as an error (`windows/runner/recycle_channel.cpp:172–200`). Describe a handle that denies delete sharing. The fake `failed` in 3.4 covers the controller's counting, not that Windows condition.

### Suggestions

None.

## Verdict

VERDICT: USER_OVERRIDE

The reviewer returned REVISE. After escalation, the owner directed: “DO NOT keep chasing unlikely scenarios. Who's gonna replace the log file ? Also who will change their clock to fuck with our program, specifically?” Proceed with per-log byte positions and the saved-enable time. C1 (concurrent log replacement/import) and C2 (clock rollback across an unread ending and opt-in) remain open as accepted limitations; this is not a reviewer approval.

## Required Changes

Not applicable as a separate list for this verdict; the blocking findings above specify the changes and regression coverage.

CHANGES_APPLIED: n/a

## Rebuttals

None in this round.
