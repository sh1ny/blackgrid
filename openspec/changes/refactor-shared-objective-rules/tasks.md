# Tasks

## Test map

This change has no spec scenarios (`skip_specs: true`, behaviour unchanged). The rows below map the design's invariants (D1-D3) to the tests that prove them. Existing behaviour tests (`test/domain/raid_timers_test.dart`, `test/domain/alert_rules_test.dart`, the quest checklist tests, `test/application/alerts_controller_*_test.dart`, `test/application/raid_timers_controller_test.dart`, `test/application/manual_progress_controller_test.dart`) start and stay `green`, unchanged.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| D1 objective rule | A counter target is a whole-number count over 1 | `test/domain/objective_progress_test.dart` | `objectiveCounterTarget` group (table) | green |
| D1 objective rule | Done by completion, or by a counter reaching its target | `test/domain/objective_progress_test.dart` | `objectiveDone` group (table) | green |
| D2 deadlines | Run-through ends its length after the current raid's start; none without a current raid | `test/domain/raid_timers_test.dart` | `deadlines` group: run-through cases | green |
| D2 deadlines | Scav ready is start plus length; no ready time without a start; nothing for an unknown mode or missing inputs | `test/domain/raid_timers_test.dart` | `deadlines` group: scav cases | green |
| D3 strip agreement | The strip shows `0:01` 1 µs before the run-through end and `done` at it, `0:01` 1 ms before scav ready and `ready` at it | `test/domain/raid_timers_test.dart` | `the strip flips exactly at the deadlines` | green |
| D3 rounding | A raid starting 10 s after now shows the full `7:10` (430 s run-through) | `test/domain/raid_timers_test.dart` | `a raid that starts after now shows the full run-through` | green (pins today's value; must stay green through the rewrite) |
| D3 rounding | 120.5 s into the raid shows `5:10` (430 s run-through) | `test/domain/raid_timers_test.dart` | `a fractional elapsed time rounds the run-through up` | green (pins today's value; must stay green through the rewrite) |

## 1. One objective rule in the domain

- [x] 1.1 Write `test/domain/objective_progress_test.dart` with the `objectiveCounterTarget` and `objectiveDone` tables (counts null, 0, 1, 1.0, 2.5, 2, 3.0, 40; completion alone, counter below, at and past its target, a count on a non-counter, a fractional count). Verify it fails because `package:blackgrid/domain/objective_progress.dart` does not exist yet (`flutter test test/domain/objective_progress_test.dart` through mise).
- [x] 1.2 Add `lib/domain/objective_progress.dart` with `objectiveCounterTarget` (moved from `lib/application/quest_checklist.dart`) and `objectiveDone(objective, complete:, count:)`, with `///` docs. Point the checklist row, the marker filter (`complete: done.contains(id)`), `ManualProgressController` and `questItemsCheck` at it. Delete the application copy and `_objectiveDone`, with no re-export. Verify that the 1.1 tests pass (flip rows 1-2 green), that the checklist, alert rules and manual progress tests pass unchanged, and that `rg "_objectiveDone|count != count.truncate|target != target.truncate" lib` finds only `lib/domain/objective_progress.dart`.
- [x] 1.3 Update `openspec/architecture.md`: the `AlertsController` row and the component that owns the checklist name `lib/domain/objective_progress.dart` as the one objective rule. Verify by reading the diff.

## 2. One timer-deadline function

- [x] 2.1 Add to `test/domain/raid_timers_test.dart`:
  - the two rounding cases, rows 6-7: a raid starting 10 s after now shows `Run-through 7:10`, and 120.5 s into the raid shows `Run-through 5:10`. Verify they pass on today's code, since they pin current behaviour.
  - the `deadlines` group: run-through end, no end for an ended raid or no raid, scav ready, a mode without a start, an unknown mode or missing inputs.
  - the agreement test, asserting only at whole milliseconds.

  Verify that the new `deadlines` group and the agreement test fail to compile because `raidTimerDeadlines` and `RaidTimerDeadlines` do not exist.
- [x] 2.2 Add `RaidTimerDeadlines` and `raidTimerDeadlines` to `lib/domain/raid_timers.dart` as D2 describes (no clock argument; it ignores `enabled` and the show flags), with `///` docs. Rewrite `raidTimersView` and `_scavEntry` to format from it with D3's arithmetic. Verify that rows 3-5 turn green, that rows 6-7 stay green, and that every existing `raid_timers_test.dart` and `raid_timers_controller_test.dart` case passes unchanged.
- [x] 2.3 Point `AlertsController._deadlines` at `raidTimerDeadlines`. Keep its mode-gated inputs and progress, its PMC and not-a-reconnect run-through rule, the `(mode, start)` scav key and the list order. Update its doc comment and the `AlertsController` and `RaidTimersController` rows of `openspec/architecture.md` to name `raidTimerDeadlines`. Verify that every `test/application/alerts_controller_*_test.dart` passes unchanged.

## 3. Integration checks

- [x] 3.1 Format with `dart format` (pinned toolchain through mise), then run `mise run analyze` and `mise run test` (never the qualification tier). Verify both exit 0.
- [x] 3.2 Run `mise run release-notes -- --check openspec/changes/refactor-shared-objective-rules/proposal.md`. Verify it exits 0.

## Workflow follow-up

- Pre-ship review (`specwright-review`), then `specwright-pr` ship and watch on PR `refactor(progress): share the objective and timer-deadline rules`, with `Refs #121` in the body.
- `/opsx:archive` with `specwright-finish` once the PR is ready.
