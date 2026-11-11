# Review

## Metadata

- **Round:** 2 (targeted recheck)
- **Prior round:** Round 1 APPROVE_WITH_CHANGES; M1 required snapshot-consistent pages, M2 required compensation encoding headroom; S1 suggested an explicit composite parent key.
- **Reviewer:** fresh-context subagent (OMP, ProgressDesignReview), rechecking its round 1 findings.
- **Reviewed:** Amended `openspec/changes/add-progress-store/design.md` and `openspec/changes/add-progress-store/specs/local-progress/spec.md`, limited to M1, M2 and S1. The round 1 source/ADR context and supplied project-skill guidance remain the review baseline. No named skill was unavailable.
- **Instructions/template:** Same review artifact instructions/template obtained in round 1 with `openspec instructions review --change add-progress-store --json`.
- **Scope:** Planning amendments only, not implementation verification. Tasks follow this gate by schema ordering. No tests, builds, lint, formatting, app launches, game interaction or authoring-transcript access occurred. Only this external scratch file was written.

## Findings

### Critical (blocking)

None within the recheck scope.

### Moderate

No outstanding findings within the recheck scope.

- **M1 — Resolved.** `design.md:228,233` now puts the revision check, cursor/validation-token decision, any required validation/rebuild and returned decoded rows in one transaction/snapshot. The token is installed only after commit, and no transaction persists between page calls. The explicitly permitted concurrent-commit outcomes exclude newer successful rows under the old revision, including on the final page. `specs/local-progress/spec.md:87-96` makes this assertable with stable-continuation and final-page race scenarios. D3 and its summary reflect the same contract.
- **M2 — Resolved.** `specs/local-progress/spec.md:31-40` fixes the owner-selected limits at 256 canonical JSON UTF-8 bytes per identity token and 1024 per edition token, including quotes and escaping. It requires compensation headroom, atomic over-budget rejection and correct repeated undo at the limits. `design.md:194-198` applies the budgets to incoming and generated events, including request IDs and `undoOf`, specifies timestamp/numeric widths, and reserves five identity tokens, one edition token and 512 fixed-envelope bytes: `5 × 256 + 1024 + 512 = 2816`, below 4096. A compensation names one target rather than embedding prior events, so repeated undo does not accumulate envelope size. The design requires codec boundary coverage of the fixed allowance, escaping and supported shapes; D2/D5/D7 and their summary rows reflect the amendment.

### Suggestions

- **S1 — Resolved.** `design.md:176` explicitly adds `UNIQUE(mode, cycleId)` as the parent candidate key for the composite event foreign key, while retaining globally unique cycle IDs.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

All round 1 Required Changes are satisfied in the amended planning artifacts; S1 is also addressed. This verdict retains the requested form and records the reviewer recheck, not executed implementation coverage. Explicit-barrier multi-instance/final-page coverage and codec/undo boundary coverage belong in the tasks authored after this gate; their execution is not claimed here.

## Required Changes

None outstanding from round 1 M1/M2.

CHANGES_APPLIED: yes

## Rebuttals

- **M1:** Fixed by the snapshot contract in `design.md:228,233` and scenarios in `specs/local-progress/spec.md:87-96`; accepted by reviewer.
- **M2:** Fixed by the encoding budgets/headroom in `design.md:194-198` and requirements/scenarios in `specs/local-progress/spec.md:31-40`; accepted by reviewer.
- **S1:** Fixed by the composite parent candidate key in `design.md:176`; accepted by reviewer.
