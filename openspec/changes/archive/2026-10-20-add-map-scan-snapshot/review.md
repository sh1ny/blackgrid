# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Re-check:** a new run on 2026-10-19 checked only Required Changes 1 and 2. Both are applied as written: proposal.md's Impact Tests bullet now names `test/ui/scanner_screen_test.dart:41`, `test/widget_test.dart:17` (replaced, not deleted) and `test/application/scan_correction_test.dart` (`:128`, `:538`). The architecture.md bullet and the last sentence of design.md's ADRs section now name the components table, the state-ownership table, the §9 row (line 140) and line 168.
- **Reviewed:** proposal.md, specs/latest-accepted-scan/spec.md, design.md (TIER: FULL); openspec/roadmap.md (M4 change 6 and exit criteria), openspec/architecture.md; docs/adr/0017, docs/adr/0018 (0001 and 0013 through their references in 0017/0018 and architecture.md); lib/application/session_scan_state.dart, scan_decision_feed.dart, selection_controller.dart, accepted_scan.dart, scan_epoch.dart, app_services.dart, scan_coordinator.dart (report id assignment, `AcceptedScanSource`); lib/ui/item_decision_card.dart, map_screen.dart, shell.dart, theme.dart (`GridPanel`); test/application/scan_decision_feed_test.dart, app_services_scan_test.dart, test/ui/scanner_screen_test.dart, test/widget_test.dart, test/support/m1_widget_harness.dart, and a grep of every `services.scans`, `ScanDecisionFeed(` and "No accepted scan this session" use under lib/ and test/. Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, flutter-add-widget-test.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None.

The core design holds against the code:
- D1's ordering is sound: `selectScan` sets `_scan` before its only `await` (`selection_controller.dart:180-191`), so the feed can read `selection.scan` synchronously after the unawaited call. The `reportId` equality check correctly declines to advance when `selectScan` returned early or produced no record, since report ids rise strictly per app-scoped coordinator (`scan_coordinator.dart:1643`, `:2352`).
- `selectScan`'s internal `notifyListeners()` fires before `advance`, but the only selection listeners are `ListenableBuilder`s, which defer to the next frame. No listener can see the in-between state.
- `epochChanged` runs synchronously inside `_syncMapSession` (`app_services.dart:284`), so clearing the snapshot there covers the stale-button case the design describes. Report ids never reset within an `AppServices` lifetime, so keeping the high-water mark across `clear()` cannot block a later valid advance.
- The return path (`showScan`) sets `selection.scan` without going through the feed, but it never touches `SessionScanState`. It therefore keeps ADR-0018's binding rule, and the spec's "Return after a manual selection" and "no history entry" scenarios can be asserted.
- Scanning with Map open needs only proof, as claimed. `IndexedStack` keeps both screens mounted (`shell.dart:161-172`), and the widget harness already drives real accepted scans through `publishTargetedScan` (`test/ui/scanner_screen_test.dart:92-166`).

### Moderate

1. **The Impact list misses tests the change breaks, including two that guard the stub text the change deletes.** Removing `SessionScanState.status` and the Map stub panel breaks these assertions, beyond the `map_screen_test.dart:260` the proposal names:
   - `test/ui/scanner_screen_test.dart:41` checks `find.text('No accepted scan this session')` after switching to Map.
   - `test/widget_test.dart:17` checks the same text in the first-run "exactly two primary surfaces" test.

   The design also makes the snapshot a constructor parameter of `ScanDecisionFeed` (D1). That breaks every direct construction outside `app_services.dart`: `test/application/scan_correction_test.dart:128` and `:538`, besides `scan_decision_feed_test.dart:30`. Tasks are derived from Impact, so these will show up only as red tests during apply. For the two UI tests, the replacement assertion matters too: deleting the line silently drops a first-run "Map is honest" check instead of replacing it with "no Latest accepted scan panel, Active map and the decision card are shown" (the spec's "No separate panel" scenario).

   In architecture.md, the design names the "Not built yet" note, the state-ownership table and the §9 row. It leaves out line 168 ("Planned but not built (the Map snapshot) live in the roadmap") and the components table, which has no row for `SessionScanState` and whose `ScanDecisionFeed` row (line 65) should gain "advances and clears `SessionScanState`".

### Suggestions

1. **State exactly what `showScan` restores.** `selectedId` resolves through `_scanItemId`, not `_scan` (`selection_controller.dart:62-63`). D2 should say that `showScan` sets both `_scanItemId = scan.itemId` and `_scan = scan`, and resets `_authority = _fingerprint()` before `_project()`, like every other source (`:140`, `:176`, `:297`). An implementation that sets only `_scan` would label the card "Accepted scan" while `item` resolves to null or to a stale manual id.
2. **"Sole writer" is by convention only.** `AppServices.scans` is public, and `advance`/`clear` will be public on it, so any holder of `services` (the card, for one) can write. Consider giving the card and screens a read-only view (for example, expose `latest`/`hasAcceptedScan` through a `ValueListenable<AcceptedScan?>` or a read-only interface on `AppServices`), or say in the State & Ownership table that the single writer is enforced by review and tests, not by types.
3. **Add a spec scenario for the high-water mark across a clear.** Requirement 2 says an older report never replaces the latest, but no scenario covers the case that motivates keeping the mark after `clear()`. The mechanism ledger calls that case the one the exit criterion names. A `SessionScanState` unit scenario would close the gap: "advance #7, clear, advance #5 → empty".
4. **Header width on the Map rail.** `GridPanel` puts `trailing` beside an `Expanded` title column (`theme.dart:105-124`). At the 1100 px wide-layout threshold, the rail is about 30% of the width (`map_screen.dart:513-531`). A labelled `TextButton.icon` plus the history close `IconButton` then leaves only a few dozen pixels for the title and subtitle, which wrap heavily inside the 300 px card. An icon-only `IconButton` with the tooltip in compact mode, or a widget test at 1100 px at text scale 1, would settle it. This is outside the declined small-window plus large-text configuration, but it is borderline, so take it as a suggestion only.
5. **Note the new scan-source entry point in architecture.md.** ADR-0017 and ADR-0018 describe `selection.scan` as set by the feed's `selectScan`. After this change, `showScan` also sets it, and the record is not newly accepted. That needs no new ADR, but the architecture text that lists selection sources should say that `selection.scan` can be a returned record, so that later consumers (M6) do not treat a change of `selection.scan` as a new accepted scan.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. In proposal.md, under Impact, extend the Tests bullet with:
   - `test/ui/scanner_screen_test.dart:41` and `test/widget_test.dart:17` assert the removed stub text. Each is replaced, not deleted, by an assertion that no "Latest accepted scan" panel is shown and that the Active map panel and the decision card are.
   - `test/application/scan_correction_test.dart` (`:128`, `:538`) constructs `ScanDecisionFeed` and gains the new `SessionScanState` argument.
2. In proposal.md, under Impact, extend the `openspec/architecture.md` bullet. Besides the "Not built yet" note, it updates the components table (the `ScanDecisionFeed` row, plus `SessionScanState` as the snapshot owner), the state-ownership table, the §9 row (line 140) and line 168, "Planned but not built (the Map snapshot)". Make the matching edit to the last sentence of design.md's ADRs section.

CHANGES_APPLIED: yes

## Rebuttals

- **Moderate 1 (Impact list):** fixed. See proposal.md Impact (Tests sub-bullets and the `openspec/architecture.md` bullet) and design.md ADRs, "To record during apply". Re-checked by the reviewer, as recorded above.
- **Suggestion 1 (what `showScan` restores):** carried into tasks.md, not the specs or design. `showScan` sets `_scanItemId` and re-projects.
- **Suggestion 2 (a read-only view of the snapshot):** declined. Public mutators on app-scoped controllers are the existing convention, the feed is the only caller, and the tests check that.
- **Suggestion 3 (a high-water mark scenario):** carried into tasks.md, not the specs. A test advances #7, clears, then advances #5 and expects the snapshot to be empty.
- **Suggestion 4 (the header width on the Map rail):** declined. Layout at small widths is out of scope.
- **Suggestion 5 (the returned record in architecture.md):** declined for the design. The architecture text for the returned record is added during apply.
