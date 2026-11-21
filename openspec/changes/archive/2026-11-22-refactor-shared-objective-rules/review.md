# Review

## Metadata

- **Round:** 1
- **Prior round:** none. This is the re-check of round 1's APPROVE_WITH_CHANGES. Only Required Change 1, S1, S2 and the S3 rebuttal were re-checked, against the edited design.md (D2, D3, Risks / Trade-offs) and the Rebuttals section of review.md.
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:** openspec/changes/refactor-shared-objective-rules/proposal.md, design.md, .openspec.yaml (skip_specs: true), review.md (Rebuttals); openspec/architecture.md (RaidTimersController, AlertsController, ProgressFacts rows); docs/adr/0031, 0046, 0047; lib/domain/raid_timers.dart; lib/domain/alert_rules.dart; lib/domain/settings.dart (RaidTimerSettings); lib/application/alerts_controller.dart (`_deadlines`, `_plan`); lib/application/raid_timers_controller.dart (`_project`); lib/application/quest_checklist.dart; lib/application/manual_progress_controller.dart (imports and `objectiveCounterTarget` uses); lib/ui/settings/settings_page.dart (run-through field); test/domain/raid_timers_test.dart, test/application/quest_checklist_test.dart, test/application/alerts_controller_timers_test.dart (test names). Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis. No tests, analyzer or builds were run (owner request).

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

Checked and holding:

- **D3 run-through arithmetic.**
  - Today: `left = R - max(0, d.inSeconds)`, with `d = now - start` (`raid_timers.dart:207-210,239`). `Duration.inSeconds` truncates toward zero, so it is `floor(d)` for `d >= 0`, and the clamp gives 0 for `d < 0`.
  - Proposed: `min(R, ceil((end - now)µs / 1e6))`, with `end = start + R`, so `end - now = R - d`. For integer `R`, `ceil(R - d) = R - floor(d)`.
  - `d >= 0`: equals today's value.
  - `d < 0`: `floor(d) <= -1`, so the ceil exceeds `R` and the cap gives `R`, as today.
  - `R = 0`: the constructor allows it, although `fromJson` clamps to 60..1800 and the UI allows 1:00 to 30:00. Both forms are always `<= 0`, so done.
  - `left <= 0` iff `now >= end`, which is exactly when `_plan` stops treating the deadline as ahead (`!deadline.at.isAfter(now)`). The `moving` flag (`!done`) is unchanged.
- **Alert deadlines.**
  - Run-through: the key `raid.startId`, the PMC and not-a-reconnect filter (kept in the controller) and the time `startTime + runThroughSeconds` are all unchanged.
  - Scav: the key `(mode, start)` and the time `start + length.seconds` are unchanged. The deadline exists only when the mode is known, the inputs belong to `catalog.mode`, a start exists and the length is countable, which is exactly when D2's `scavReady` is non-null.
  - The progress gate is the same in both callers.
  - The order is preserved.
  - No ADR conflict (0031, 0046, 0047).
- **Objective rule.** `_objectiveDone` (`alert_rules.dart:121-128`) and the checklist row (`quest_checklist.dart:242-254`) are the same predicate as `objectiveDone` over `objectiveCounterTarget`. No test or other file references `objectiveCounterTarget`, so dropping it without a re-export breaks no import.

### Critical (blocking)

None.

### Moderate

- **M1: The `min(R, …)` cap in D3 was not tested, so the behaviour-unchanged claim did not hold there.**
  - No existing run-through test starts the raid after `now`: `raid_timers_test.dart:109` asserts only the In raid entry.
  - Without the cap, a raid that starts 10 s ahead of the clock with `R = 430` would show `7:20` instead of `7:10`, and every listed test would still pass.
  - **Resolved:** see Required Change 1 and its rebuttal.

### Suggestions

- **S1: Scav agreement holds to the millisecond, not "exactly".** For `0 < ready - now < 1 ms`, the strip's `inMilliseconds` truncation already reads `ready` before the alert fires. **Resolved** in D3.
- **S2: D2 should say that `raidTimerDeadlines` ignores `enabled` and the show flags**, because the alerts fire with the strip off (`alerts_controller_timers_test.dart:43`). **Resolved** in D2.
- **S3: Consider carrying the scav start in `RaidTimerDeadlines`**, so the alerts' `(mode, start)` key and the time come from one source. Rebutted; the rebuttal is accepted, see below.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. In design.md, `## Risks / Trade-offs`, first bullet: add a pinned run-through case for a raid whose log start is after `now`, which shows the full length, and one fractional-elapsed case. Name both as new cases in `test/domain/raid_timers_test.dart`. **Applied and re-checked.**

CHANGES_APPLIED: yes

## Rebuttals

- **Required change 1:** fixed, accepted by reviewer.
  - Risks / Trade-offs, first bullet, now names both cases as new tests in `test/domain/raid_timers_test.dart`.
  - Start `now + 10 s` with `R = 430` expects `7:10`, the capped value; without the cap it would be `7:20`.
  - 120.5 s elapsed expects `5:10` (430 - floor(120.5) = 310). Flooring the remaining time instead would give `5:09`.
  - Together with the existing 1 µs-before-end case (`0:01`, where floor or round would give `done`), the rounding is pinned on every side.
- **S1:** fixed, accepted by reviewer. D3 now says that scav agreement holds to the millisecond, that the strip reads `ready` with less than 1 ms left (as today), and that the agreement test asserts at whole milliseconds only.
- **S2:** fixed, accepted by reviewer. D2 now says that `raidTimerDeadlines` ignores `enabled` and the show flags, and that `raidTimersView` checks them itself.
- **S3:** rebutted, accepted by reviewer. It was a Suggestion with no behavioural consequence: the second synchronous read gives the same start. Keeping the owner-chosen D2 shape is a sound reason not to reopen the decision.
