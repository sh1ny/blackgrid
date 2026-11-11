# Review

## Metadata

- **Round:** 1
- **Prior round:** Round 1 APPROVE_WITH_CHANGES; this is the focused M1–M3 required-change recheck, not a new full design round.
- **Reviewer:** fresh-context subagent (omp, openai-codex/gpt-6.1-sol)
- **Reviewed:** Updated `openspec/changes/detect-found-in-raid/specs/scan-decisions/spec.md`; D5 and the relevant Flow & State Gaps additions in the updated `design.md`; supplied review template. Rechecked against the original M1–M3 findings and source/installed-Flutter evidence retained from the initial review.
- **Project skills:** All six project skills were loaded during the initial review; none failed to load.
- **Scope:** Required-change resolution only. No implementation, test, build, lint, formatter, app launch or live-game interaction performed. Automated checks specified by the design remain implementation work; this report accepts the planning edits, not test execution or native qualification.

This verdict retains the initial full review subject to the required changes checked below. Other artifact edits outside those changes or the proposal's Release Notes section require review.

## Findings

### Critical (blocking)

None outstanding within this focused recheck.

### Moderate

M1, M2 and M3 are resolved in the revised planning artifacts. No remaining required-change issue was found.

### Suggestions

None.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M1 — Applied and accepted by reviewer.** `specs/scan-decisions/spec.md:52–61` now includes the complete MODIFIED scan-age requirement and preserves both existing scenario names. The price-age scenario explicitly begins with detected Yes and Flea, then requires current Check while acceptance time, immutable Flea snapshot and recorded Flea history verdict remain unchanged. The mode-retirement scenario is preserved. This removes the old Unknown-only acceptance contradiction.
2. **M2 — Applied and accepted by reviewer.** `specs/scan-decisions/spec.md:8–10` qualifies the generic Keep scenario as a non-FIR need. Lines 28–31 add an explicit active FIR-only need matrix: Yes → actionable Keep; No → irrelevant need and Trader; Unknown → unresolved need and Check, including matching initial acceptance/history verdicts. `design.md:223` assigns these assertions to the real feed/selection boundary rather than the existing non-FIR precedence fixtures or owner sign-off.
3. **M3 — Applied and accepted by reviewer.** `design.md:87` specifies the controlled `emptySelectionAllowed` adapter: the visible selected set remains the singleton effective FIR; an empty callback maps to the value captured for that rendered control; either callback path creates a manual override without publishing an empty selection. This matches the installed Flutter callback behavior inspected in the initial review. `specs/scan-decisions/spec.md:76–82` covers already-selected automatic Yes and Unknown, manual source text/semantics, unchanged detection/input and refresh preservation. D5 explicitly requires actual shared-control taps and semantics checks, not only direct controller calls; `design.md:224` reiterates those cases.

CHANGES_APPLIED: yes

## Rebuttals

- **M1:** Fixed at the cited scan-age requirement; accepted by reviewer.
- **M2:** Fixed at the cited explicit FIR-only outcome matrix and application-layer check requirement; accepted by reviewer.
- **M3:** Fixed at the cited callback adapter, same-value scenarios and shared-control widget-check requirement; accepted by reviewer.
