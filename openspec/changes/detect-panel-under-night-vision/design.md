# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components | no | Admission is a single profile method (`lib/domain/raid_panel_text_parser.dart:121-135`). |
| T2 State | no | The sample counts are local (`lib/domain/raid_panel_text_parser.dart:126-134`). |
| T3 Concurrency | no | The sample loop is synchronous (`lib/domain/raid_panel_text_parser.dart:122-135`). |
| T4 Boundaries | no | No interface, format, native API or storage change. The packed RGB callback remains as called in `lib/data/raid_panel_ocr.dart:397-399`. |
| T5 Volume | no | Reuse the existing image bounds and sampling grid (`lib/data/raid_panel_ocr.dart:389-399`, `lib/domain/raid_panel_text_parser.dart:123-134`). |
| T6 Risk | no | Saved-image admission changes; no writes, security boundary or irreversible operation (`lib/data/raid_panel_ocr.dart:397-409`). |

TIER: LIGHT

## Context

- The detector samples the upper-right band and requires the profile-specific hit fraction (`lib/domain/raid_panel_text_parser.dart:121-135`). `_headerGreen` requires `g >= 150` (`:186-189`); the reported dim header is about RGB `(93,136,7)` ([#140](https://github.com/sh1ny/blackgrid/issues/140)).
- The native adapter returns `missing` when admission fails and only computes the crop and calls OCR after admission (`lib/data/raid_panel_ocr.dart:397-409`). Keep the Map-owned Windows OCR boundary from [ADR-0006](../../../docs/adr/0006-windows-media-ocr-for-raid-panels.md).
- `panelBottom` also uses `_headerGreen` to keep rows in the crop (`lib/domain/raid_panel_text_parser.dart:137-164`). Apply any new colour rule only to admission, leaving this use unchanged.
- The existing profile test supplies RGB through a coordinate callback and covers bright green, dark, and white (`test/domain/raid_panel_text_parser_test.dart:27-38`). It does not provide evidence about the dim header or night-vision scenery.
- Manual branch gate (linked Orca worktree): pinned `sw` 0.39.1/interface 3 reports Git, a clean `bugfix/detect-panel-under-night-vision` tree, not on `main`. The dispatch authorizes retaining this pre-created branch. Git confirmed HEAD matched fetched `origin/main` at `28f6f4d`; no matching archived change on local or remote main. No shared installation or branch changed.

## Decisions

### D1: Narrow dim-header admission; retain the bright path and crop rule

- **Choice:** Keep existing bright admission and the scan grid. Count a dim yellow-green, low-blue sample only inside the existing OCR crop; the unchanged overall hit fraction can use dim evidence only if one row contains an uninterrupted dim run spanning at least a quarter of the crop width. Each saved dim positive has a 114-sample run out of 247 crop samples (46%). The new predicate does not change crop classification.
- **Rejected:** A lower shared floor admits generic green tint and changes crop sizing. A colour-only exception also accepts an in-palette vertical stripe entirely outside the OCR crop. Crop bounds alone still admit a narrow vertical stripe inside them. Do not move the check into OCR or matching.
- **Reversal cost:** low.
- **Important:** yes, changes which raid screenshots are accepted; implements S1 without widening the brief.
- **Chosen by:** user (explicitly approved the panel-local, quarter-width row rule after pre-ship found a colour-only false positive).

### D2: Keep evidence reproducible at the detector boundary

- **Choice:** Reproduce the reported 12.26 RGB with a synthetic strip; the original file is absent. The owner approved using the saved Shoreline 12.02 and 12.44 NV panels as the real regressions, 12.10 as the bright control, and the 11-21 NV no-panel screenshots as real negatives. Keep a compact spatial sampling of their detector grids, not the screenshots, plus synthetic near-misses that challenge an unconditional brightness reduction.
- **Rejected:** Synthetic positives alone cannot distinguish a wider green rule from one that rejects real NV scenery. OCR end-to-end tests alone conflate the gate with OCR and matching and cannot isolate the false-positive risk.
- **Reversal cost:** low.
- **Important:** yes for substituting the saved source images; the exact reported file cannot be used, although the replacements independently reproduce its failure.
- **Chosen by:** user (explicitly approved the substituted captures and synthetic hard negative).

### Decision summary

| # | Decision | Choice | Rejected | Reversal cost | Important | Chosen by |
|---|---|---|---|---|---|
| S1/D1 | Detector scope | Admission-only dim palette inside the crop, with a contiguous quarter-width row | Lower general brightness floor or add colour-only dim coverage | low | yes | user |
| D2 | Evidence | Two alternate saved NV failures, bright control, real no-panel scenes, and synthetic hard negative and issue colour | Synthetic-only evidence or OCR-only checks | low | yes | user |

## Assumptions

- **A1 (settled):** The sampled dim palette separated the six saved frames, but colour alone did not distinguish a constructed in-palette scenery stripe from a header. The two dim positives retain the required run in the crop; group 2 verifies that evidence and rejects in-palette stripes.

## Carried constraints

- **C1:** Dim header support must not admit night-vision scenery without a panel. Kind: invariant. Destination: spec: specs/raid-panel-reading/spec.md → Requirement: Detect exfil headers dimmed by night vision.
- **C2:** The dim-header rule is admission-only; the crop must not follow newly admitted dim-green scene content. Kind: invariant. Destination: doc comment: lib/domain/raid_panel_text_parser.dart RaidPanelProfile.detect.
- **C3:** New dim evidence must belong to the OCR crop and include a horizontal header run; total colour coverage alone is not sufficient. Kind: invariant. Destination: doc comment: lib/domain/raid_panel_text_parser.dart RaidPanelProfile.detect.
