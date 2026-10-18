# Proposal

## Why

Live scan recognises items but stops at evidence. ADR-0013 keeps every scan away from selection, history and the decision card ("no decisions from scans before M4"), so a player who scans an item in raid still has to search for it by hand to get keep/sell advice. This change serves **M4 - complete raid-time Scanner slice** ([roadmap](../../roadmap.md)) as its change 2. It advances two exit criteria:

- An accepted scan, automatic or manual, produces one decision from the shared engine against the mode-correct catalog and session progress. Unaccepted evidence never yields a recommendation. Fixture tests cover every rule of the precedence table for scan input.
- Latest-wins bursts, late completions, mode or session changes, history selection and catalog/progress refresh cannot publish a stale decision or record a scan twice. Service tests over the scan and selection state prove it. Correction belongs to change 3 and the Map snapshot to change 5; this change leaves them the seams they need.

It is constrained by ADR-0001 (one shared decision engine; `SelectionController` its only caller), ADR-0002 (notifiers, composition root, generation fences), ADR-0003 (one Drift store, history one row per item and mode) and ADR-0013, whose last decision this change replaces.

## What Changes

- **An accepted scan becomes the current selection.** It selects its item through the mode-correct catalog and the session's progress and feeds the same `DecisionEngine` call that manual selection uses. The decision card, needs and sources panels on Scanner and Map show it. The latest intent wins: a newer accepted scan, manual selection or history selection replaces it, in the order they happened.
- **Each accepted scan is consumed exactly once.** A new app-layer feed takes each accepted report from `ScanCoordinator` by its monotonic report id. It is fenced by the scan's mode and session epoch, captured when the scan started. A scan whose mode or session changed before publication, or whose item is not in the current catalog, drives no decision. Its evidence is still shown. `ScanCoordinator` itself still never calls selection or history.
- **Accepted scans are recorded in activity history** as a new `scan` source, one row per (item, mode), revised on each accepted scan. Opening a history row, a catalog or progress refresh and the 30 s age tick change the shown decision but never record a scan or count as a new one.
- **Transient FIR resets to unknown on every new accepted scan**, even for the same item, and on mode or session change.
- **Scan advice ages safely.** The accepted scan keeps its identity, acceptance time, mode, catalog revision and the decision at acceptance, all immutable. The card shows the current projection through the shared engine, with stale facts downgrading to Check by the existing rules. It shows how old the scan is. On a mode or session change the scan stops being current advice.
- **Unaccepted evidence never yields a recommendation.** Rejected and failed scans leave the selection, decision and history untouched, as before.
- **ADR-0013's "no decisions from scans before M4" is superseded** by a new ADR that records the feed, the fences and the history source. The rest of ADR-0013 stays in force.

## Capabilities

### New Capabilities
- `scan-decisions`: how an accepted scan becomes the current selection and decision. It covers the mode and session fences, exactly-once consumption, history recording, transient FIR reset, advice aging, and the rule that history selection and refresh are never new scans.

### Modified Capabilities
- `scanner-evidence`: the requirement "Scan evidence never produces a recommendation" is removed, because its accepted-scan scenario no longer holds. It is replaced by "Unaccepted scan evidence never produces a recommendation": unaccepted evidence still never changes selection, decision or history, and an accepted scan now does, through `scan-decisions`.

## Impact

- **Code:** `lib/application/selection_controller.dart` gains a scan selection with its own generation, FIR reset and accepted-scan record. A new feed (`lib/application/scan_decision_feed.dart`) is wired in `AppServices`. `ScanCoordinator` stamps each report with the mode and session epoch captured at trigger time, read through an injected reader. `HistoryController` and `BlackgridDatabase.recordActivity` take an activity source. `ActivitySource` gains `scan`; it is stored as its name in an existing text column, so there is no Drift migration. The decision card and history panel label scan-sourced items and show the scan's age.
- **Tests:** service tests for the feed and selection over every fence, fixture tests over the precedence table with scan input, a history test for the new source, and a narrow widget test for the card. The ADR-0013 widget test "decision card unchanged after accepted scan" (`test/ui/scanner_screen_test.dart`) is replaced by one where the accepted scan drives the card. The coordinator-level unit tests stay: the bare coordinator still never touches selection or history.
- **Docs:** a new ADR superseding the last decision of ADR-0013, plus the architecture's index and "Not built yet" line.
- **No new dependencies, no native or ABI change, no game interaction.** Live verification of a real accepted scan driving advice belongs to the user.
