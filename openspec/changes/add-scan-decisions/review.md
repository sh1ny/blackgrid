# Review

## Metadata

- **Round:** 2
- **Prior round:** Round 1 returned APPROVE_WITH_CHANGES with 2 Moderates: the decision at acceptance is always Keep, Keep for later or Check, because FIR resets at acceptance (spec scenarios, D5 and the ledger), and `selectScan` did not clear `loadingHistory`. Both were fixed and re-checked (`CHANGES_APPLIED: yes`). Later edits voided that verdict.
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:** proposal.md, design.md, specs/scan-decisions/spec.md, specs/scanner-evidence/spec.md (checked against openspec/specs/scanner-evidence/spec.md; `openspec validate add-scan-decisions --strict` passes), the round 1 review.md, and the docs/adr/ index (0001-0016, so 0017 is free). Source: lib/application/selection_controller.dart (whole file), history_controller.dart (whole file), app_services.dart (constructor, initialize, _syncMapSession, setMode, reloadAfterImport, dispose), scan_coordinator.dart (ScanReport, _notify, _dispose, _onTrigger, _begin, _retire, _publish, lastAccepted, the `utc:` stamp at :2674), catalog_controller.dart (setMode), map_session_controller.dart (epoch bumps at :187 and :253), lib/data/database.dart (ActivityRecords, readActivity, recordActivity, _writeActivity), lib/domain/settings.dart (ActivitySource, ItemActivity), lib/domain/decision_engine.dart (precedence block), lib/ui/item_decision_card.dart (title, subtitle, empty state). Tests: test/ui/scanner_screen_test.dart (:88), test/application/scan_coordinator_flow_test.dart (the "evidence never produces a recommendation" group, which uses its own `_Rig` coordinator), test/support/m1_harness.dart (:40), test/fixtures/m1/catalog/fixture.dart (:8). Project skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, flutter-add-widget-test.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

1. **The acceptance time and the age shown on the card come from two different clocks.** D4 takes the acceptance time from `report.utc`. `ScanCoordinator` sets that field from the wall clock: `utc: DateTime.now().toUtc()` (`scan_coordinator.dart:2674`). The coordinator gets no clock from `AppServices` (`app_services.dart:95-108`). D5 computes "Scanned <age> ago" on each projection with `SelectionController.clock`. `AppServices` injects that clock (`:69-75`), and `M1Harness` fixes it at `fixtureNow = 2026-10-06` (`m1_harness.dart:40`, `fixture.dart:8`). The history row's `observedAt` also comes from `report.utc`, while manual rows use `clock()` (`selection_controller.dart:84`).

   In production both clocks are the wall clock, so nothing shows. Every AppServices-level test uses `M1Harness`, and so will the replacement for `scanner_screen_test.dart:88` and the proposal's "narrow widget test for the card". In those tests the scan's age is negative by the distance between today and the fixture date, and it depends on the day the test runs. The history order of a scan row next to manual rows depends on the wall clock too. The spec scenario "Two scans of the same item" ("observed at the second acceptance time") and the age display then cannot be asserted deterministically above the unit layer. AGENTS.md requires fake clocks instead. Change 3 and change 5 code against `AcceptedScan.acceptedAt`, so the time base should be settled now.

### Suggestions

1. **`retireScan` bumps the generation even when the source is not a scan.** As D4 reads, the bump is unconditional ("`retireScan()` bumps `_generation` ... It resets FIR for every source. When the source is a scan, it clears it ..."). D5 calls it on every mode or session change. Suppose a session change (`map_session_controller.dart:253`) lands while `openHistory` is awaiting `loadCatalog`. Then `openHistory` returns at `selection_controller.dart:101` or `:109`, `loadingHistory` stays `true` and `_historyCatalog` stays null. The card stays on "Opening stored-mode catalog…" (`item_decision_card.dart:57-58`) until the user acts. This is round 1's Moderate 2 bug again, reached through a different path. It is rare, because the window is one local read and session changes are game restarts or new log sessions. Two one-line fixes would work: bump the generation only when the source is a scan (the only pending result the bump has to drop is that scan's history-write error), or clear `loadingHistory` in `retireScan` as `closeHistory` does (`:120`).
2. **The disposal guard has a ledger row but no Failure row.** The ledger marks the `HistoryController` disposal guard as built. The Failure & Visibility row "App disposed during a history write" names only the selection guard. Add the history side to that row, so the task that adds the guard has a failure case to test against.
3. **Line references have drifted.** The design cites `app_services.dart:207-217` and `:192-218` for `_syncMapSession`. The method is at `:195-220`, with the mode block at `:212-219`. It cites `selection_controller.dart:68-82` for `selectManual`, which is at `:73-88`. This does not change any decision, but fixing the references helps the implementer find the code.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. In `design.md` D4, say which clock gives `AcceptedScan.acceptedAt`, which is also the history `observedAt` and the base for the card's age. Either (a) the feed or `selectScan` stamps it from `SelectionController.clock` when the scan is consumed, and `report.utc` is not used for it, or (b) `AppServices` passes its `clock` to `ScanCoordinator`, which uses it for `ScanReport.utc`. Add a Flow & State Gaps line saying that with this choice, AppServices-level tests on a fixed clock see a deterministic acceptance time and age.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals
- **Round 2 Moderate (clock):** fixed. Accepted by reviewer (round 2 re-check: design.md D4 and the Flow & State Gaps line "Acceptance time under a fixed clock"). Applied Required Change 1 with option (a). In D4, `selectScan` stamps the acceptance time from `SelectionController.clock` when the scan is consumed, never from `report.utc`, and that clock gives `acceptedAt`, `observedAt` and the card's age. Flow & State Gaps has a line on deterministic times under a fixed clock.
- **Round 2 Suggestions 1-3:** not edited into the design. Tasks carry them: `retireScan` bumps the generation only when it retires a scan source, so a history load in flight is not stranded; a test covers the disposal guard; implementers use current line numbers.
