# Proposal

## Why

Two rules that the new audio alerts (#121) depend on are written more than once, so they can drift apart without any test noticing:

- **"Is this objective done?"** An objective is done when it is recorded complete, or when it is a counter (a whole-number catalog count over 1) whose recorded count reached that target. The quest checklist writes it twice (`lib/application/quest_checklist.dart`: the checklist row and the quest marker filter), and `lib/domain/alert_rules.dart` has a third, private copy (`_objectiveDone`) that duplicates `objectiveCounterTarget`, because the domain layer cannot import `lib/application`.
- **"When is the run-through over, and when is the scav ready?"** The timer strip (`raidTimersView` in `lib/domain/raid_timers.dart`) and the alerts controller (`_deadlines` in `lib/application/alerts_controller.dart`) each do this arithmetic themselves. The `add-audio-alerts` design (D7) says they use "the same pure functions", but only `scavCooldownLength` is shared. A later change to one side could make the strip say "ready" at a different moment than the spoken alert.

The weekly architecture review of 2026-11-21 (candidates 2 and 3) found both. The owner answered on 2026-11-21: do only the narrow part of each, as a change of its own in M10 before `add-screenshot-cleanup`.

This change serves milestone **M10 - alerts and window behaviour**. It advances the agent-verified exit criterion that each alert "fires once from its raid lifecycle, timer or progress event ... proved by fake-clock and fixture tests": once one function gives the deadlines, a test can show that the strip and the alerts agree. It also keeps the owner's play-test result for that milestone's user-verified criterion (the alerts "fire at the right moments in play", checked in `add-audio-alerts` 6.3) valid for later changes, because the strip and the alert can no longer disagree. That user-verified criterion is judged at the milestone close; this change adds no `[user]` task, because behaviour does not change.

## What Changes

- **One objective rule in `lib/domain`.** `objectiveCounterTarget` moves from `lib/application/quest_checklist.dart` into a small domain module next to `ProgressFacts`, beside a single `objectiveDone`. The quest checklist row, the quest marker filter, the manual progress controller and `questItemsCheck` in `alert_rules.dart` all use it. The application copy and the private `_objectiveDone` are deleted.
- **One pure timer-deadline function in `domain/raid_timers.dart`.** It works out the current raid's run-through end and the active mode's scav-ready time (with the cooldown length behind it) from the lifecycle, settings, active mode, cooldown starts, cooldown inputs and progress facts. The timer strip formats its countdowns from it, and the alerts controller arms its run-through-over and scav-ready deadlines on it.
- **Tests** for both: table tests of the objective rule, deadline cases, and a test that the strip shows "done" and "ready" at exactly the deadlines the function gives.
- **Behaviour is unchanged.** Every strip value, tooltip, alert and checklist tick stays as it is. The alert-only rule that only a PMC raid that was not a reconnect gets a run-through warning stays in the alerts controller.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This is a refactor with no spec-level behaviour change, so `.openspec.yaml` sets `skip_specs: true`.

## Impact

- Code: a new `lib/domain/objective_progress.dart`; `lib/domain/raid_timers.dart`, `lib/domain/alert_rules.dart`, `lib/application/quest_checklist.dart`, `lib/application/manual_progress_controller.dart`, `lib/application/alerts_controller.dart`.
- Tests: a new `test/domain/objective_progress_test.dart`, new cases in `test/domain/raid_timers_test.dart`. Existing checklist, alert and timer tests must pass unchanged.
- No public API, stored data, settings, UI or dependency change. No ADR is affected (ADR-0031: timers stay projections of log times and one clock reading).
- `openspec/roadmap.md`: this change is listed in M10 before `add-screenshot-cleanup`.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Share only the "objective done" rule

- **Choice:** Move `objectiveCounterTarget` and one `objectiveDone` into `lib/domain` next to `ProgressFacts`, and point the checklist and `alert_rules.dart` at them.
- **Rejected:** The rest of the review's candidate 2: one decoder of stored winners for `ProgressFacts`, the checklist and the Your progress panel, and making the decision engine call the rules package's `evaluateTasks`. Larger, and the owner deferred it: the winners decoder waits for the next progress change (after M10), and `evaluateTasks` waits for M11 planning.
- **Reversal cost:** low
- **Important:** yes: it sets the boundary of the change.
- **Chosen by:** user (owner, 2026-11-21: "only that narrow part, the single winners decoder waits")

### S2: Share only the deadline arithmetic

- **Choice:** One pure deadline function in `domain/raid_timers.dart`, used by the timer strip and the alerts controller.
- **Rejected:** The rest of candidate 3: one shared "active-mode inputs" interface in place of the three mode-gated sources, and one set of test fakes in `test/support`. The owner kept them out of this change.
- **Reversal cost:** low
- **Important:** yes: it sets the boundary of the change.
- **Chosen by:** user (owner, 2026-11-21: "not the shared active-mode interface")

### S3: A change of its own in M10, before `add-screenshot-cleanup`

- **Choice:** A separate OpenSpec change, listed in M10's Changes before `add-screenshot-cleanup`.
- **Rejected:** A plain refactor PR without a change (the first plan), and folding the work into `add-screenshot-cleanup` (unrelated scope).
- **Reversal cost:** low
- **Important:** yes: it changes the agreed M10 split.
- **Chosen by:** user (owner, 2026-11-21)

### S4: No spec change

- **Choice:** `skip_specs: true`; no requirement or scenario changes, because behaviour does not change.
- **Rejected:** A new requirement saying the strip and the alerts share one deadline function: that is an implementation constraint, not behaviour a user can see, and it belongs in the design and tests.
- **Reversal cost:** low
- **Important:** no: it only follows from S1 and S2 keeping behaviour unchanged.
- **Chosen by:** agent

### S5: The stale "quest items reminder waits for data" note stays out

- **Choice:** Not in this change; it is tracked as #123.
- **Rejected:** Fixing it here: it changes behaviour (the note clears when map data loads) and needs a MapController query, outside S1 and S2.
- **Reversal cost:** low
- **Important:** no: the owner already decided it (not a blocker, file an issue).
- **Chosen by:** user (owner, 2026-11-21)

## Release Notes

Internal clean-up: the quest checklist and the alerts now share one rule for when a quest objective is done, and the timer strip and the timer alerts share one calculation of when the run-through ends and the scav is ready. Nothing in the app changes.

### Changed

- The quest checklist, the Map's quest filter and the quest-items reminder use one shared "objective done" rule, and the timer strip and the run-through over and scav ready alerts use one shared deadline calculation, so they cannot drift apart (follow-up to #121). Nothing you see changes.
