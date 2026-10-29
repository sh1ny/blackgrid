# Proposal

## Why

Blackgrid still talks to players in developer terms. Raw enum names reach the screen (`Catalog stale`, `Reason: belowSimilarity`, `Failure: targetNotForeground`, `Logs: watching`, `FIR: unknown`, `importedScan`), along with internal words such as "canonical ID", "durable pin record", "DPAPI" and "M1 • no accepted scan", and UTC ISO timestamps. Scan scores, margins and stage timings sit in the open next to the item decision. This is the last change of milestone **M4.5 - player-facing polish, item icons and own map markers**. It serves the exit criterion "Player-facing strings use plain language: no raw enum names or internal category keys. Developer detail (scan evidence scores and timings, source authority) sits behind a collapsed Details section or a diagnostics setting". The string inventory is agent-verified and the in-raid read is user-verified. With the user's choice (2026-10-29), developer detail goes into collapsed **Details** sections, not a diagnostics setting.

## What Changes

- Every enum value shown to the player goes through an exhaustive label function: catalog and progress status, map input status, raid panel state, scan reject reasons, scan failure codes, scan pass, found-in-raid state and activity source. No UI text interpolates an enum's `.name`.
- A shared collapsed **Details** section. It is collapsed at launch and builds its content only while expanded. Its expanded state lasts for the session, across new scans, tab switches and breakpoint changes, and it is never saved.
- **Scan evidence panel**: the open view shows the scan phase in plain words, the shown scan's outcome (the item's name, or a plain reason it was not accepted), the not-accepted note in plain words, and the recent scans as item or plain reason plus a hotkey label. Pass, marker score, title crop, OCR text, candidates with scores and margin, item ID, the reason code and the stage timings move behind Details. The rules for which scan is shown, the note and the 10-scan list stay as they are.
- **Source authority panel**: the open view says in plain words whether item data and Tracker progress are up to date, with local-time "updated" lines. The source URL, UTC timestamps, freshness limits and cooldown go behind Details.
- **Decision card, shell footer, manual controls, history, Settings, import dialog, pin editor, Map rail and workspace**: the remaining developer wording is rewritten in plain language. Local times replace UTC ISO strings in the open, and the Map rail's saved-file lines use labels instead of `.name`.
- Player-visible error and plan-row messages written in `lib/application` controllers and `lib/data/legacy_import.dart` get the same plain-language rewrite (text only). Messages pinned by an existing spec (`catalog-authority`) keep their wording.
- An offline source check fails the suite when `lib/ui` interpolates `.name` on a status, state, reason, code, pass or FIR value, or when a player-visible literal uses a banned developer term. Label tests cover every enum value.
- Display only. Decision rules, scan acceptance, the timing log and stored values do not change. The timing log and `frames.jsonl` keep the raw reason codes.

## Capabilities

### New Capabilities
- `player-facing-text`: what Blackgrid's screens may say to a player. Every shown enum value goes through a label function, internal keys and IDs stay out of the open view, timestamps are in local time, and developer detail sits behind a collapsed Details section.

### Modified Capabilities
- `scanner-evidence`: the latest-scan evidence, the not-accepted note, and the timings and recent scans requirements. The open view shows plain-language outcomes, and scores, crop, OCR text, codes and timings move behind Details.
- `map-rail`: Map saved-file inputs shows its status lines with labels instead of raw state names. Expanding the section still shows the status lines, the Follow logs switch and the Read Latest button.

## Impact

- `lib/ui/`: `scan_evidence_panel.dart`, `evidence_panels.dart` (Source authority, history), `item_decision_card.dart`, `shell.dart`, `manual_controls.dart`, `live_scan_panel.dart`, `settings_dialog.dart`, `import_dialog.dart`, `pin_editor.dart`, `map_screen.dart`, `map_workspace.dart`, `theme.dart` (shared label functions and the Details section). A new `lib/ui/labels.dart` holds the label functions.
- Tests under `test/ui/` that assert old strings or raw reason names get the new wording, plus a new label test and an offline source check under `test/ui/`.
- Display strings only in `lib/application` (`selection_controller.dart`, `settings_controller.dart`, `progress_controller.dart`, `map_controller.dart`, `history_controller.dart`) and `lib/data/legacy_import.dart` (plan-row reasons, whose ISO times move to local time). No behaviour change in `lib/domain`, `lib/application` or `lib/data`, and none to settings, the Drift schema, persisted wire names, the timing log or the native code. No new dependency.
- ADR-0001 (the decision engine stays the only keep/sell authority, and the evidence panel shows no recommendation) and ADR-0013 and ADR-0020 (failure code names and timing log v3 keep the raw codes) constrain the change. No ADR is amended.
