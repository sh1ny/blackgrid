# Review

## Metadata

- **Round:** 1 (focused Required Changes re-check)
- **Prior round:** Round 1 APPROVE_WITH_CHANGES; M1 hotkey placement and M2 recording status placement now re-checked by the same reviewer.
- **Reviewer:** fresh-context subagent (Codex)
- **Reviewed:** Updated openspec/changes/add-answer-strip/specs/scanner-evidence/spec.md and the prior canonical review.md. This pass is confined to Required Changes M1/M2; the original review's assessment of the unchanged proposal, design, other delta specs, architecture, in-force ADRs and cited source remains in force.
- **Skills:** The original round loaded .agents/skills/impeccable/SKILL.md and .claude/skills/{dart-use-pattern-matching,dart-write-documentation,dart-add-unit-test,dart-run-static-analysis,flutter-add-widget-test}/SKILL.md. Applied as review guidance only; no named skill failed to load. No app launch, game interaction, tests, analysis, detector or source mutation.
- **Referenced stores:** Original discovery reported none; no store changes are part of this focused pass.

## Findings

### Critical (blocking)

None.

### Moderate

No open findings. M1 and M2 are resolved by the amended Scanner evidence delta, as verified below.

### Suggestions

None.

### Claims

The original round re-read every source anchor in design.md Context using repository-tracked files and found the claims supported, including selection projection before the three activity writes, current-advice recomputation on history inspection, item/mode history uniqueness, transactional revision updates, lazy icon loading and the existing Settings entry point. This focused re-check does not claim a new source review or runtime verification. Those unchanged claims remain covered by the original round.

The amended delta now modifies the exact existing hotkey requirement and preserves all five scenario names. Each hotkey scenario opens Settings' Live scan section. Binding/state, Off/F1–F24, off/ready enablement, starting/rebinding exclusion, unavailable reasons, mouse-scan fallback and active-binding retention after refused or failed rebind remain explicit.

Recording counters and the folder path now belong explicitly to Settings beside the switch. The Recording runs scenario asserts Settings placement. The requirement preserves a visible Scanner stop/error note after Settings closes, and the Write failure scenario explicitly closes Settings, observes that note and reopens Settings to find the failed session folder path. The readiness gate and existing session semantics remain intact.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M1 — applied and re-checked.** The delta includes the MODIFIED hotkey requirement, places the controls in Settings' Live scan section and updates all five scenarios without changing their existing behavioural semantics. The requested offline widget coverage remains an implementation task to generate after this design review, as originally specified.
2. **M2 — applied and re-checked.** The recording requirement and scenarios consistently locate the controls, counters and path in Settings; preserve Scanner's visible stop/error note after closing Settings; and retain access to the failed session folder path on reopening. The requested offline widget coverage remains an implementation task to generate after this design review, as originally specified.

CHANGES_APPLIED: yes

## Rebuttals

- **M1:** Fixed in the scanner-evidence delta's hotkey requirement and its five scenarios; accepted by reviewer on focused re-check.
- **M2:** Fixed in the recording status requirement, Recording runs scenario and Write failure scenario; accepted by reviewer on focused re-check.

Both amendments reconcile the written contract with existing user choices. No decision reversal is required.
