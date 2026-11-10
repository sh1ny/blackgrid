# Review

## Metadata

- **Round:** 2
- **Prior round:** This re-checks round 2's Required Changes (APPROVE_WITH_CHANGES, CHANGES_APPLIED: no). Required Change 1 (M1): add "Same-name candidates are told apart in the offer" as MODIFIED in specs/scan-correction/spec.md, with the similarity removed from two scenarios. The author also applied round 2's suggestions S-a to S-d. Round 1 was REVISE (C1, C2, M1, M2, S-a to S-c), and round 2 recorded all of those as fixed.
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** openspec/changes/move-scanner-diagnostics/proposal.md, design.md, review.md (round 2), specs/scan-correction/spec.md, specs/settings-diagnostics/spec.md (`openspec validate move-scanner-diagnostics --strict`: valid). Main specs: openspec/specs/scan-correction/spec.md (to compare the modified requirement with the original), plus a search of openspec/specs for other offer, similarity or scan-id wording. Source: lib/application/selection_controller.dart (`inspectionCatalog`, `openHistory`), lib/ui/evidence_panels.dart (`SourcePanel`). Project skills: none were named in the request, so none were loaded.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

Round 2 items, checked against the files:

- **M1 (Required Change 1): fixed.**
  - `specs/scan-correction/spec.md:51-72` adds "Same-name candidates are told apart in the offer" under `## MODIFIED Requirements`.
  - The requirement text is the same as the main spec's (`openspec/specs/scan-correction/spec.md:187`).
  - "Weapon case variants" THEN now reads "... shows neither `1.00` nor `0.91`, and shows no recommendation" (`:56`).
  - "Only one listed same-name item" THEN now reads "both rows show only their names" (`:60`).
  - "Unknown flea status", "Variant found through the search" and "Picking a variant" match the main spec word for word.
  - Every main-spec similarity reference in the offer (`:36`, `:40`, `:191`, `:195`) is now covered by a MODIFIED requirement. No other main spec mentions offer scores or the scan id.
- **S-a: applied, and sound.** The exception in the guard requirement now says same-name offer rows keep their 6-character ID suffix (`specs/settings-diagnostics/spec.md:10`). This matches the scan-correction requirement above. The guard scenarios do not conflict with it: "Accepted scan on the Scanner" forbids only the full ID, and "Rejected scan with a correction offer" uses candidates with different names, so no suffix is shown.
- **S-b: applied, and sound.** The proposal's Why (`proposal.md:9`) names the S6 exception, which the owner agreed, for the M8.5 criterion's "OCR text ... only in Settings under Diagnostics", and says the milestone close judges the criterion with that exception. This matches S6 (`Chosen by: user`).
- **S-c: applied, and sound in intent.** "Diagnostics shows data source detail" now says it describes "the item data behind the item shown (a history item's saved data, else the live catalog)" (`specs/settings-diagnostics/spec.md:93`). This matches D3 and the design's Flow-gaps line, which build it from `selection.inspectionCatalog`. One small wording gap is noted as S-e below.
- **S-d: applied, and sound.** The WHEN of "Errors the player must act on stay visible" now opens the inspector with its Sources section expanded (`specs/settings-diagnostics/spec.md:32`). The scenario can now be asserted against `SourcePanel`.

### Critical (blocking)

None.

### Moderate

None open. M1 is fixed (see above).

### Suggestions

**S-e (optional, does not block). The parenthetical in S-c is slightly broader than the code.** `inspectionCatalog` uses the live catalog for any history row from the live game mode. It falls back to the saved catalog only when no live snapshot exists. Only a history row from another mode reads that mode's saved catalog (`lib/application/selection_controller.dart:57-60`, `:378`).

The spec's "a history item's saved data" could be read as "always the saved catalog for history rows". In practice the live mode's saved catalog is the persisted live snapshot, so the only consequence is that a test written literally from the spec would set up a case that cannot differ. A clearer wording would be "(for a history item from another game mode, that mode's saved item data; else the live catalog)". This does not affect the verdict.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. In `openspec/changes/move-scanner-diagnostics/specs/scan-correction/spec.md`, add under `## MODIFIED Requirements` the full requirement "Same-name candidates are told apart in the offer", copied from the main spec with only these edits:
   - Scenario "Weapon case variants", THEN: "the offer lists "Weapon case · flea · 4b423c" first and "Weapon case · no flea · 045d88" second, shows neither `1.00` nor `0.91`, and shows no recommendation".
   - Scenario "Only one listed same-name item", THEN: "both rows show only their names".
   - Keep the requirement text and the other three scenarios ("Unknown flea status", "Variant found through the search", "Picking a variant") unchanged.

   Status: applied and re-checked (`specs/scan-correction/spec.md:51-72`).

CHANGES_APPLIED: yes

## Rebuttals

None.
