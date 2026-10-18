# Proposal

## Why

An unaccepted scan is a dead end today: Scanner notes "Last scan not accepted" with its best candidate, but the player has to clear the search box and type the item name to get advice. The M2 corpus shows where this hurts. ANA M1 OD Green (best 1.0 against a 0.974 runner-up) and the M855A1 ammo pack (a 0.893 tie after a quantity misread) are rejected `ambiguous` between close-named variants. The right item is one of the first two candidates, so a single click should be enough.

This change serves **M4 - complete raid-time Scanner slice** ([roadmap](../../roadmap.md)) as its change 3, and it needs change 2 (`add-scan-decisions`), which is done. It advances two exit criteria:

- "An accepted scan ... produces one decision from the shared engine ... Unaccepted evidence never yields a recommendation; it offers correction. Fixture tests cover every rule of the precedence table for scan input." This change adds the correction half.
- "Latest-wins bursts, late completions, mode or session changes, correction, history selection and catalog/progress refresh cannot publish a stale decision, record a scan twice or advance the Map snapshot as a new accepted scan." This change covers correction. The Map snapshot itself is change 5. This change guarantees that a correction never looks like an accepted scan to change 5.

ADR-0001 constrains it: one shared decision engine, with `SelectionController` as its only caller. So does ADR-0002: notifiers, the composition root and generation fences. ADR-0012 constrains the matcher's result shape. ADR-0013 keeps the coordinator from referencing selection or history. ADR-0017 constrains the feed, the epoch fence and the activity source.

## What Changes

- **An unaccepted scan with candidates offers a correction.** When a scan is published rejected `ambiguous` or `belowSimilarity` in the current mode and session, the decision card offers its best candidates, up to 5 distinct items with their scores, as one-click picks. It also offers a text field pre-filled with the scan's OCR text, which searches the live catalog, and a Dismiss button. The offer appears in the shared decision card, on Scanner and on Map. It never replaces the item already shown. Unaccepted evidence still yields no recommendation: the offer shows candidates, not decisions.
- **A correction is explicit and transient.** Picking a candidate or a search result makes that item the current selection, with its decision from the shared engine, transient FIR reset to unknown, and the card labelled as corrected from scan #N. History records it as `manual` activity, as the reference companion does. The correction is never stored as correction data, and it never teaches the matcher.
- **A correction is not a new scan.** It does not change the scanner's latest or last accepted report. It does not raise the decision feed's accepted-report high-water mark, and it does not create an accepted-scan record on the selection. So it cannot advance the future Map snapshot, and it cannot be recorded as a `scan`.
- **The offer is fenced and latest-wins.** Each unaccepted report is offered once, by report id. A newer offer replaces the old one. A newer accepted scan, a manual, history or correction selection, Dismiss, and a mode or session change each clear it. A newer scan that has nothing to offer (failed, `noMarker`, UI chrome and the like) leaves it in place. A pick that arrives after its offer was cleared or replaced, or whose item is no longer in the live catalog, changes nothing.
- **The matcher keeps its top candidates.** Besides best and runner-up, every match result carries up to 5 distinct-name candidates in rank order. Best is first and the runner-up second, so the existing gates, margin and acceptance are unchanged. The timing log stays at version 1.

## Capabilities

### New Capabilities
- `scan-correction`: the correction offer an unaccepted scan makes and its lifecycle. It covers which scans offer it, which candidates and search it offers, how a pick becomes the selection and is recorded, the rule that a correction is never a new accepted scan, and the fences and clearing rules.

### Modified Capabilities
- `item-title-matching`: the requirement "Best and runner-up are chosen deterministically" also requires a ranked list of up to 5 distinct-name candidates whose first two entries are the best and runner-up.
- `scan-decisions`: the requirement "FIR resets on every new accepted scan" also covers a correction, and "An accepted scan becomes the current selection" makes the newest-wins order include a correction.

## Impact

- **Code:**
  - `lib/domain/title_matching.dart`: `TitleMatch` gains `candidates`.
  - `lib/application/scan_coordinator.dart`: `AcceptedScanSource` also exposes the latest published report. `ScanCoordinator` already has it.
  - `lib/application/scan_decision_feed.dart`: offers unaccepted reports to selection, with its own high-water mark.
  - `lib/application/selection_controller.dart`: gains the correction offer, `selectCorrection`, `dismissCorrection` and a correction record, and every other selection path clears the offer.
  - New `lib/application/scan_correction.dart`: the offer and correction records.
  - `lib/ui/item_decision_card.dart`: shows the offer and the corrected label on Scanner and Map.
- **Tests:** matcher tests for the candidate list; service tests for the offer, the pick and every fence and clearing rule over the feed and selection state; precedence-table fixtures for a corrected item; a test that a correction leaves the accepted-scan source, `selection.scan` and the feed's high-water mark unchanged; narrow widget tests for the offer in the card, including that editing the offer's text in one mounted card updates the other.
- **Docs:** a new ADR for correction state ownership and the matcher's candidate list, plus the architecture's component rows, index and "Not built yet" line.
- **No new dependencies, no Drift migration, no native or ABI change, no game interaction.** A live correction in raid is a user check.
