# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Codex)
- **Reviewed:** `proposal.md`, `evidence.md`, `design.md` and `specs/inspection-recognition/spec.md` in this change; authoritative `openspec/specs/inspection-recognition/spec.md`; `openspec/architecture.md`; accepted ADRs 0008, 0011 and 0012; `lib/data/vision/inspection_recognition.dart`, `inspection_geometry.dart`, `inspection_evidence.dart`, `vision_image.dart`, `tesseract_binding.dart` and `vision_runtime.dart`; `test/data/vision/inspection_job_test.dart` and `support/holdable_vision_native.dart`; `test/qualification/inspection_corpus_test.dart` and `support/inspection_corpus.dart`; `docs/qualification/m2/CORPUS.md`; `AGENTS.md` and the installed reviewer role.
- **Skills:** Read the installed `dart-use-pattern-matching`, `dart-write-documentation`, `dart-add-unit-test` and `dart-run-static-analysis` SKILL.md files directly. No Skill tool was available; no named file was missing. Applied them as review guidance, with the project's hand-written-fake and pinned-command rules taking precedence over generic examples. No workflow skill was invoked.
- **Verification boundary:** Static design/source review only. No tests, native libraries, app launches, screenshots or game interactions. The supplied offline evidence was reviewed as recorded evidence, not independently rerun.

This verdict covers only the contents reviewed. Editing proposal, specs or design afterward, other than applying Required Changes, voids it.

## Findings

### Critical (blocking)

None.

### Moderate

None. The design gives an exact, assertable crop rule; preserves every logical foreground pixel and excludes stride padding; distinguishes blank content from empty geometry; and retains whole-request typed native failure handling. The helper stays synchronous within the existing sole-owner worker, adds no publication or admission state, and allocates at most a smaller crop. Existing runtime threshold outputs are tightly packed (`vision_runtime.dart:305`), and evidence remains a detached copy (`inspection_recognition.dart:240`). The unchanged frame-space title rectangle and potentially narrowed/downscaled preview have distinct documented meanings. These choices preserve ADR-0008, ADR-0011 and ADR-0012.

### Suggestions

1. **Carry D4's strict comparison into the implementation/qualification tasks explicitly.** The existing runner reads only the optional reference `baseline.json` (`test/qualification/inspection_corpus_test.dart:69`) and otherwise merely reports. Even with a baseline, `BaselineComparison.passed` checks aggregate counts (`test/qualification/support/inspection_corpus.dart:572`), so an improvement can hide loss of a previously correct case. Its new-false-positive list also ignores changing one existing wrong accepted ID into another (`:604-608`). D4 already closes these gaps in the design. When implementing its comparison against the separately preserved before report, assert matching case IDs and expected labels, more than 26 correct items, retention of each previously correct item, rejection of every negative, no newly wrong acceptance, and no changed wrong ID on an already wrong case. A successful existing corpus test alone cannot establish those conditions; retain the per-case comparison result alongside the report. This is task/verification follow-through on D4, not a requested design change.

## Verdict

VERDICT: APPROVE

## Required Changes

None.

CHANGES_APPLIED: n/a

## Rebuttals

None.
