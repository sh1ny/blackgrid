# Proposal

## Why

Milestone **M4 - complete raid-time Scanner slice**, change 6. It serves two exit criteria:

- "Map shows the latest accepted scan in its one decision card, with no separate latest-scan panel, and scanning works with Map open."
- "Latest-wins bursts, late completions, mode or session changes, correction, history selection and catalog/progress refresh cannot ... advance the Map snapshot as a new accepted scan."

Since `add-scan-decisions`, an accepted scan already becomes the shared selection, and the decision card shows it on Map and Scanner. Two gaps remain. The Map rail still has the stub "Latest accepted scan" panel, which reads "No accepted scan this session" even after a scan was accepted, because `SessionScanState` is a constant with no producer (`lib/application/session_scan_state.dart:1-7`). And once a search, a history row or a correction replaces the scan on the card, the session's latest accepted scan cannot be found again. The user decided on 2026-10-18 that two scan cards are redundant. On 2026-10-19 they chose the shared selection card, with a way back to the latest scan, over a Map card pinned to the snapshot.

## What Changes

- `SessionScanState` becomes the session's real latest-accepted-scan record. Only an accepted scan that drives a decision advances it. It advances monotonically, at most once per scan report, and is cleared on a mode or session change. Manual selection, history, a correction, a correction offer, a catalog or progress refresh and the age tick never advance it (ADR-0018's binding rule).
- The shared decision card offers **Back to latest scan** whenever the session has a latest accepted scan that the card is not showing. The action shows that scan again as an accepted scan, with its original acceptance time. It records no history, does not advance the snapshot and resets FIR, like any new selection.
- The Map rail drops the stub "Latest accepted scan" panel. The Active map picker takes its place. The rail's decision card is the one scan card.
- Scanning keeps working while Map is open. Service and widget tests prove it, against the app-scoped scanner and the `IndexedStack` shell.
- `SessionScanState.status` (the stub's text) is removed. `hasAcceptedScan` stays and now reports real state.

## Capabilities

### New Capabilities
- `latest-accepted-scan`: the session-only record of the latest accepted scan, which events advance and clear it, and the card's action that returns to it.

### Modified Capabilities
- None. `scan-decisions` keeps its requirements: returning to the latest scan is a new selection source owned by `latest-accepted-scan`, and it creates no new accepted scan.

## Impact

- `lib/application/session_scan_state.dart`: the stub becomes a `ChangeNotifier` holding an `AcceptedScan?`.
- `lib/application/scan_decision_feed.dart`: advances the snapshot after `selectScan`, and clears it in `epochChanged`.
- `lib/application/selection_controller.dart`: a fenced `showLatestScan` source.
- `lib/application/app_services.dart`: builds the state and passes it to the feed. `scans` is no longer `const`.
- `lib/ui/item_decision_card.dart`: the Back to latest scan action. `lib/ui/map_screen.dart`: the stub panel is removed.
- Tests: `test/application/scan_decision_feed_test.dart`, `selection_controller_test.dart`, `test/ui/map_screen_test.dart` (its stub-text assertion is replaced), and a card widget test. Existing `hasAcceptedScan` assertions after manual and history flows stay, and now prove real behaviour.
  - `test/ui/scanner_screen_test.dart:41` and `test/widget_test.dart:17` assert the removed stub text. Each assertion is replaced, not deleted, by one that no "Latest accepted scan" panel is shown and that the Active map panel and the decision card are.
  - `test/application/scan_correction_test.dart` (`:128`, `:538`) constructs `ScanDecisionFeed` and gains the new `SessionScanState` argument.
- `openspec/architecture.md`: besides the "Not built yet" note, updates the components table (the `ScanDecisionFeed` row, plus `SessionScanState` as the snapshot owner), the state-ownership table, the §9 row (line 140) and line 168, "Planned but not built (the Map snapshot)".
- No storage, schema, native or ABI change. Offline only: no live-game check is needed for the state, and the user's live Map check stays with the milestone.
