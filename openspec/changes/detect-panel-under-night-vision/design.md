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

- **Choice:** Keep existing bright admission and add a dim-header test specific to the sampled yellow-green, low-blue colours. Use the existing scan geometry and keep the new test inside admission. Calibrate it on owner-provided screenshots before changing production code. If no-panel samples still qualify, stop and revisit the plan rather than shipping a threshold that admits them.
- **Rejected:** Lower the shared `_headerGreen` floor: this both admits generic green-tinted scenery and changes crop sizing. Do not expand into OCR or matching to handle a detector error.
- **Reversal cost:** low.
- **Important:** yes, changes which raid screenshots are accepted; implements S1 without widening the brief.
- **Chosen by:** user (issue #140 calls for the dim low-blue header and no scenery false positives; exact cutoffs are determined by evidence).

### D2: Keep evidence reproducible at the detector boundary

- **Choice:** Use a compact synthetic RGB strip for the reported dim colour and representative near-misses. Also exercise the full detector against owner-supplied saved day, NV panel, and no-panel images offline. Retain the smallest approved fixture data that preserves the relevant scenery colour distribution and sample geometry; do not check in full owner screenshots.
- **Rejected:** Synthetic positives alone cannot distinguish a wider green rule from one that rejects real NV scenery. OCR end-to-end tests alone conflate the gate with OCR and matching and cannot isolate the false-positive risk.
- **Reversal cost:** low.
- **Important:** no; S1 fixes the outcome and requirement for negatives, and this choice concerns the fixture representation.
- **Chosen by:** agent.

### Decision summary

| # | Decision | Choice | Rejected | Reversal cost | Important | Chosen by |
|---|---|---|---|---|---|
| S1/D1 | Detector scope | Admission-only dim header rule, with no-panel regression checks | Lower shared brightness floor | low | yes | user |
| D2 | Evidence format | Deterministic pixels plus offline saved-image comparison | Synthetic positive alone or OCR-only checks | low | no | agent |

## Assumptions

- **A1:** A colour rule with the current sampling geometry can distinguish the observed dim header from saved no-panel NV scenery. The issue gives one approximate positive colour but no scenery samples. Verify in task 1.1; D1 depends on this. If the evidence does not support it, stop before changing production code.

## Carried constraints

- **C1:** Dim header support must not admit night-vision scenery without a panel. Kind: invariant. Destination: spec: specs/raid-panel-reading/spec.md → Requirement: Detect exfil headers dimmed by night vision.
- **C2:** The dim-header rule is admission-only; the crop must not follow newly admitted dim-green scene content. Kind: invariant. Destination: doc comment: lib/domain/raid_panel_text_parser.dart RaidPanelProfile.detect.
