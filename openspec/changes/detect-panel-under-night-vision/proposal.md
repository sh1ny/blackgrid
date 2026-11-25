# Proposal

## Why

In the owner's 2026-11-25 Shoreline screenshot at raid time 12.26, night vision darkened the exfil panel's header below Blackgrid's green brightness cutoff, so Blackgrid reported no panel and matched no exits ([#140](https://github.com/sh1ny/blackgrid/issues/140)). This is an unplanned correction to saved screenshot reading; it advances no M10 exit criterion.

## What Changes

- Detect the observed dim yellow-green header without losing panels detected today.
- Reject night-vision scenery without a panel. Do not lower the green channel threshold on its own; prove the new admission path against saved no-panel scenery and synthetic near-misses.
- Out of scope: crop sizing, OCR, text parsing, matching, capture, and UI. Rebase after #136 merges; do not mix its same-file parser work into this fix.

## Capabilities

### New Capabilities

- `raid-panel-reading`: adds a header-detection requirement to the capability being introduced by #136. This capability is not on the current base; it will exist before this change is archived.

### Modified Capabilities

None on the current base.

## Impact

- `lib/domain/raid_panel_text_parser.dart`: admission in `RaidPanelProfile.detect` only.
- `test/domain/raid_panel_text_parser_test.dart`: deterministic pixel fixtures; no native OCR dependency or game runtime.
- No user setting, API, dependency, or persisted data change.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Repair header detection without admitting night-vision scenery

- **Choice:** Target admission for the observed dim panel, preserve existing behavior outside it, and require hard-negative scenery fixtures.
- **Rejected:** An unconditional brightness reduction admits green-tinted scene pixels; changing parsing or matching cannot fix a panel rejected before OCR.
- **Reversal cost:** low
- **Important:** yes, changes which saved screenshots Blackgrid reads.
- **Chosen by:** user (#140 and the dispatch's hard requirement).

## Release Notes

Blackgrid can read saved exfil panels whose headers are dimmed by night vision.

### Fixed

- Recognize the dim exfil header under night vision without treating the tested no-panel scenery as an exfil panel (#140).
