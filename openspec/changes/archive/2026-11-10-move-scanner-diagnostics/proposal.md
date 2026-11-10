# Proposal

## Why

The owner's rule of 2026-11-08 says the main windows stay clean for end users. `restyle-map-workspace` applied it to the Map and added a collapsed Diagnostics section at the end of Settings. The Scanner still shows detail that only helps diagnose the app:
- its main column has scan codes, OCR text, title crops, marker and match scores, item IDs, stage timings and scan numbers;
- its inspector's Sources panel shows the data source URL, UTC times, record counts per dataset and the freshness limits.

This change serves milestone **M8.5 - Ember interface** (change 5). It closes the agent-verified exit criterion "Map and Scanner show no debug information in normal use: status lines, file paths, coordinate frames, source names, record counts, OCR text and stage timings are only in Settings under Diagnostics, and problems the player must act on stay visible. Proved by widget tests." The criterion's "OCR text ... only in Settings under Diagnostics" has one owner-agreed exception (S6): the scan correction offer keeps the text the scan read, because the player picks the item from it; the milestone close judges the criterion with that exception. The user-verified criterion (verdict and dialogs read right on a second monitor) is judged at the milestone close, after `restyle-dialogs`, because it covers the whole redesign.

## What Changes

- The Scanner's main column keeps only what a player needs: the scan phase in plain words, the accepted item's name or the plain reason a scan was not accepted (with the best candidate labelled not accepted), and the note for a later unaccepted scan. Its Details section is removed.
- The Scanner's recent scans list moves off the Scanner into Diagnostics. The inspector's "Recent item activity" still lists accepted and picked items.
- Settings' Diagnostics section gains a scan part with the content of today's scan Details: end state, pass, marker score, title crop, OCR text, best and runner-up candidates with scores and margin, item ID, code and wider-scan failure, the note scan's code, OCR text and marker score, the latest scan's stage timings, and the 10 recent scans with their plain row, hotkey label, end state and total. Scan numbers label them there.
- The inspector's Sources panel loses its Details section. The source URL, UTC times, record counts, items source update, cooldown end and freshness limits move to a data sources part of Diagnostics. The open view keeps item data and progress status with local update times, game mode, price time, errors and the Refresh read-only progress button.
- The decision card's corrected-scan subtitle drops the scan number: "Corrected from a scan • 3 min ago • chosen by hand".
- The scan correction offer, shown on Map and Scanner after a rejected scan, drops the scan number ("Last scan not accepted — pick the item") and each candidate's similarity score. It keeps "Read: <text>" and the pre-filled search, because the player picks the item from what was read.
- Problems the player must act on stay on the Scanner: a scan's plain rejection or failure reason, the recording stop note, catalog and Tracker errors, and the live scan state in the status bar.
- Nothing in Diagnostics is mounted, decoded or refreshed while it is collapsed.

## Capabilities

### New Capabilities
- `settings-diagnostics`: what the Diagnostics section of Settings holds for scans and data sources, and that the Map and Scanner keep that detail out of normal use.

### Modified Capabilities
- `scanner-evidence`: the Scanner shows the latest scan's result in plain words only. Details, stage timings and the recent scans list move to Diagnostics, and the later-unaccepted note's code and OCR text move with them.
- `player-facing-text`: Diagnostics replaces the in-panel Details sections as the one place for developer wording and UTC times. The Data sources panel keeps its plain open view, and its source URL, UTC times, freshness limits and cooldown end move to Diagnostics. The "Details sections start collapsed" requirement is removed, because no Details section is left on the Map or the Scanner.
- `scan-correction`: the offer no longer names the scan's id or shows candidate similarity, and the corrected label no longer names the scan's id.
- `interface-theme`: the sentence-case label scenario names the Scanner's sections that still exist, now that the recent scans list has moved.

## Impact

- Code: `lib/ui/scanner_screen.dart`, `lib/ui/scan_evidence_panel.dart` (split into a Scanner summary and a diagnostics view), `lib/ui/evidence_panels.dart` (`SourcePanel`), `lib/ui/settings_dialog.dart` (Diagnostics content), `lib/ui/shell.dart` (Sources details state), `lib/ui/item_decision_card.dart` (subtitle and correction offer).
- Tests: `test/ui/scan_evidence_panel_test.dart`, `test/ui/scanner_screen_test.dart`, `test/ui/scan_correction_card_test.dart`, `test/ui/shell_test.dart`, `test/ui/ember_surfaces_test.dart`, `test/ui/data_sources_panel_test.dart`, `test/ui/details_section_test.dart` (deleted), Settings widget tests, and a new test that Map and Scanner show no debug text in normal use.
- Main spec Purpose lines: `scanner-evidence` and `player-facing-text` describe per-scan timings and Details sections; both are reworded in this change.
- No data, model, service or setting changes. Scan publication, the timing log and frame recording are unchanged.
- Out of scope: the Settings page layout (X12), which `restyle-dialogs` builds, and filling the Scanner main column with requirements and the price breakdown (DESIGN.md X10).

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Recent scans list

- **Choice:** Move the whole recent scans list to Diagnostics, not just its codes and totals.
- **Rejected:** Keeping the plain list on the Scanner. That was the agent's recommendation, because the plain reasons explain failed scans. The owner chose a cleaner Scanner, and the inspector's Recent item activity still lists items.
- **Reversal cost:** low
- **Important:** yes; changes what users see.
- **Chosen by:** user

### S2: Scan numbers on main windows

- **Choice:** Drop scan numbers from the Map and Scanner. The corrected-scan subtitle reads "Corrected from a scan • <age> ago • chosen by hand". Scan numbers stay in Diagnostics, where they tie a scan to its timings, the timing log and recorded frames.
- **Rejected:** Keeping "Corrected from scan #N", which leaves an internal id on a main window.
- **Reversal cost:** low
- **Important:** yes; changes what users see.
- **Chosen by:** user

### S3: Scan detail in Diagnostics

- **Choice:** Move today's scan Details content as it is: the shown scan's full evidence, the note scan's code, OCR text and marker score, the latest timings, and end state with total for each recent scan.
- **Rejected:** Full evidence for every recent scan, which costs more code, tests and memory for decoded crops, and serves no current need.
- **Reversal cost:** low
- **Important:** yes; changes what users see.
- **Chosen by:** user

### S4: Data sources detail goes too

- **Choice:** Move the Sources panel's Details (source URL, UTC times, record counts, items source update, cooldown end, freshness limits) to Diagnostics and keep its plain open view in the inspector.
- **Rejected:** Leaving the Details in the inspector, which keeps source names and record counts on the Scanner against the exit criterion.
- **Reversal cost:** low
- **Important:** no; the roadmap entry already names this move.
- **Chosen by:** agent

### S5: One capability for the Diagnostics contents

- **Choice:** A new `settings-diagnostics` capability owns what Diagnostics shows for scans and data sources, and the rule that main windows keep that detail out. The map input lines stay specified in `map-rail`.
- **Rejected:** Folding the new requirements into `map-rail`, which is about the Map; or into `scanner-evidence` alone, which would leave the data sources detail without an owner.
- **Reversal cost:** low
- **Important:** no
- **Chosen by:** agent

### S6: The scan correction offer

- **Choice:** Drop the scan number and the candidates' similarity scores from the offer. Keep "Read: <text>" and the pre-filled search, as the one stated exception to the clean rule: the player picks the item from what the scan read. Candidates stay in rank order. Found by the design review (round 1).
- **Rejected:** Keeping the scores as a hint between close variants, which leaves match scores on a main window. Dropping the "Read:" line too, which hides the text the player is correcting.
- **Reversal cost:** low
- **Important:** yes; changes what users see.
- **Chosen by:** user

## Release Notes

The Scanner now shows only what you need: the item it read, or why a scan did not work, in plain words. Scan codes, OCR text, title crops, timings, the recent scans list and data source detail are in Settings under Diagnostics.

### Changed
- The Scanner and its inspector no longer show scan codes, OCR text, title crops, scores, stage timings, the recent scans list, source URLs, UTC times or record counts. They are in the collapsed Diagnostics section of Settings.
- A corrected scan's subtitle and the correction offer no longer show the scan number, and the offer no longer shows match scores.
