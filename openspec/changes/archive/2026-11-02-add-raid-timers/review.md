# Review

## Metadata

- **Round:** 2
- **Prior round:** round 1 APPROVE_WITH_CHANGES with Required Changes C1 (active mode), M1 (bonus sign), M2 (starts never moved back, pending kept after a failed save) and M3 (no automatic save over an unreadable record); suggestions S1 and S2.
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer)
- **Reviewed:** re-check of the Required Changes only. Read openspec/changes/add-raid-timers/specs/raid-timers/spec.md and design.md: D3, D4, D6, D7, the diagrams, the State & Ownership and Failure & Visibility tables, Flow & State Gaps and the Mechanism Ledger. Checked against lib/application/map_session_controller.dart:77-79, lib/application/app_services.dart:93,248,261,299-308, lib/application/settings_controller.dart:25-71, lib/data/database.dart:205-210 and lib/ui/settings_dialog.dart:97-98, all read in round 1. Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis, flutter-add-widget-test.

## Findings

### Critical (blocking)

None open.

- **C1 (active mode): applied.**
  - D6 now uses the effective mode (`MapSessionController.effectiveMode`), which it reads as `catalog.mode`. `_syncMapSession` sets that synchronously (`app_services.dart:299-308`). D6 uses the catalog and progress snapshots only when their `mode` equals `catalog.mode`, and it rejects `settings.mode` with the reason.
  - The spec defines the active mode in "The scav cooldown counts down to ready". It adds "Mode from the logs" and "Reputation for the detected mode", and narrows both "No mode known" scenarios to the case where the logs detect no mode and none is chosen in Settings.
  - The Fence reputation field edits the active mode's value, consistent with the dialog's dropdown (`settings_dialog.dart:97-98`).
  - The Flow gap "Mode switch while a cooldown runs" covers the window before the new mode's catalog loads.

### Moderate

None open.

- **M1 (bonus sign): applied.** The requirement now reads "times one plus the sum of the scav-cooldown bonuses of the hideout levels built (each a negative fraction)". 1500 × 0.8 × (1 − 0.35) = 780 s, which matches the 13:00 scenario and the negative values in the catalog block.
- **M2 (starts never moved back; failed save): applied.**
  - D4 now max-merges `scavCooldownStarts` in every `save(value)` against the stored starts and the pending starts.
  - A pending start is removed only when a save that contained it succeeds, and it is kept after a failed save.
  - `RaidTimersController` reads `effectiveScavCooldownStarts` (stored merged with pending), so the "Save fails" scenario is now achievable.
  - The new scenario "Settings saved from older values" makes the invariant assertable.
  - The State table (both the start and pending rows), the Failure table, the Flow gap "Settings-dialog save racing a recorded start" and the Ledger row agree.
- **M3 (unreadable record): applied.**
  - While `_settingsUnreadable` is set, `recordScavCooldownStart` only fills the pending map and never saves. The user's first save writes the pending starts and clears the notice.
  - The sequence diagram, the Failure table row, the Flow gap and the Ledger row agree with D4.
  - The new scenario "Stored settings unreadable" asserts that the cooldown runs, nothing is saved and the notice stays. That matches `readSettings` never writing (`database.dart:205-210`) and `loadNotice` (`settings_controller.dart:25-33`).

Suggestions S1 and S2 are also applied:
- **S1:** D3 now states reputation is a JSON number rounded to two decimals, which matches the example.
- **S2:** D7 builds the controller right after `raidLifecycle` (`app_services.dart:93`), subscribing in its constructor before the bind at `:261`.

### Suggestions

- **S3 (new, wording only; no behavioural consequence).** Two places still say "selected mode" where they mean the active mode: D6's heading ("Only the selected mode's cooldown is shown and computed") and D7's arming rule ("the selected mode's scav cooldown counting and shown"). Elsewhere the design and spec now use "active mode" for `catalog.mode`. Consider renaming both to "active mode", so that an implementer does not arm the timer from `settings.mode`.

The edits introduced no new problem with a concrete consequence.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (C1) Use the effective mode as the active mode for the view, the snapshots and the Fence reputation field, with the spec scenarios for log-detected and unknown modes. Status: applied and re-checked.
2. (M1) "One plus the sum" of the negative hideout bonuses. Status: applied and re-checked.
3. (M2) Max-merge cooldown starts in every save, keep pending starts after a failed save, make the view read stored starts merged with pending ones, and add the "Settings saved from older values" scenario. Status: applied and re-checked.
4. (M3) No automatic cooldown save while the stored record is unreadable, and add the "Stored settings unreadable" scenario. Status: applied and re-checked.

CHANGES_APPLIED: yes

## Rebuttals

None needed: every round-1 finding was fixed as required.
