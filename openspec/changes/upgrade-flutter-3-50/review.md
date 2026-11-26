# Review

## Metadata

- **Round:** 3
- **Prior round:** REVISE; the owner then approved changing only the generated Ember import and refreshing its two copies.
- **Reviewer:** fresh-context subagent (OMP)
- **Reviewed:** Amended `proposal.md`, `design.md`, `tasks.md`, and round 2 `review.md`; the cited tracked Ember generator, inputs, outputs, copy test, analyzer exclusions and ADR-0037, plus the kit README and byte-handling attributes. Reused the applicable project skills and previously reviewed tracked workspace and gate sources. Rechecked only the two round 3 required changes against the amended planning text. No dependency installation, generation, analysis, tests, builds or app execution ran for this review.

## Findings

### Critical (blocking)

None. The owner-approved change resolves the round 2 conflict without weakening either gate. `proposal.md:73–79`, D4 and C10 (`design.md:56–62,94`), and task 1.3 (`tasks.md:11`) consistently keep both outputs byte-identical, retain the existing equality test and limit the kit source edit to the emitted import.

### Moderate

1. **The plan copies raw generator output, but the checked-in baseline is formatted.** `tasks.md:11` says to run `node brand/tools/build.mjs`, copy its Dart output, and prove that only the import changed, as D4 requires. The generator emits each `TextStyle` on one line and writes the raw string (`brand/tools/build.mjs:73–80,150–152`); the committed `body` declaration is multiline with a trailing comma (`brand/flutter/ember_tokens.dart:321–327` and the identical app copy). Following the current sequence makes the copies equal to each other but fails the baseline comparison even if all values are identical. The script also writes `brand/tokens.css` unconditionally (`brand/tools/build.mjs:59`), so equality of the two Dart files does not prove the run stayed inside the authorized change.
2. **The standalone kit's documented copy-and-analyze path acquires a dependency.** `brand/README.md:16–24` tells consumers to copy the kit, then run `flutter analyze`, and names an SDK floor without a package prerequisite. The approved generated import requires `material_ui` in the consuming project; Blackgrid gets it in its root manifest, but a copied kit does not get that manifest. Record the new prerequisite in the reviewed proposal or design. Do not infer permission from D4 to change the kit's other source, preserve compatibility with its old SDK floor, or edit the kit README without explicit approval.

### Suggestions

None.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

The previous diagnostic finding is resolved: `design.md:26` attributes the deprecation to the apply run and no longer states an unsupported count or asserts that the rendering import is redundant. D3 still requires post-migration analysis before removing an import. The new generator plan can preserve the source of truth and existing gates once it accounts for the formatting of the committed outputs. Verification remains with the worker and hosted CI; installation remains owner-only.

## Required Changes

1. Amend D4 and task 1.3 to regenerate, format only the generated kit Dart file with the pinned Dart formatter, then copy the formatted bytes to the app. Verify that each committed Dart output differs from its baseline only by the import, that the copies match each other byte-for-byte, and that `brand/tokens.css` and the token inputs remain unchanged. If normalization cannot meet those checks, stop and report the additional diff rather than broadening the kit change or relaxing the test.
2. Add to `proposal.md` Impact or D4 that a downstream copy of the kit now requires `material_ui` in its consumer manifest; Blackgrid supplies it at the root. Keep this as a planning clarification, not a new compatibility or kit-edit task.

CHANGES_APPLIED: yes

## Rebuttals

- **Round 2 critical — fixed, accepted by reviewer.** `proposal.md:73–79`, `design.md:28,56–62,94,174` and `tasks.md:11` record the owner's decision, preserve ADR-0037 and the equality gate, and migrate through the generator rather than hand-editing the app copy.
- **Round 2 moderate — fixed, accepted by reviewer.** `design.md:26,48–51` removes the unsupported exact diagnostic claims and attributes the actual failure to the apply run; import cleanup remains conditional on the post-migration analyzer.
- **Round 3 finding 1 — fixed, accepted by reviewer.** `design.md:58` and `tasks.md:11` put the pinned formatter after generation and before the copy, limited to the kit Dart file. They require byte equality, an import-only delta against each baseline, unchanged CSS and token inputs, and stopping on any other generated change rather than weakening the equality test.
- **Round 3 finding 2 — fixed, accepted by reviewer.** `proposal.md:30` records that downstream projects must declare `material_ui` and that Blackgrid supplies it at the root; the amended D4/task do not broaden kit or compatibility scope.
