# Review

## Metadata

- **Round:** 3
- **Prior round:** APPROVE_WITH_CHANGES — codec precondition, XML verification, and publication/cleanup citations; all three applied and rechecked.
- **Reviewer:** fresh-context subagent (omp)
- **Reviewed:** `proposal.md`, `design.md`, `.openspec.yaml`, prior `review.md`, pre-ship findings, and the named `dart-add-unit-test`, `dart-run-static-analysis`, and `flutter-add-widget-test` skills. Re-read the design’s tracked citations: the app-icon, marker, and pack specs; ADRs 0005/0023/0024/0027/0028/0033/0050; map CLI, parser, publication and tests; icon compilation, rendering, fixtures and checks; bundle check, notices, mise and hosted gates. Compared the baseline constraints, dependency files and affected XML/fixture claims against the design’s recorded base. Read the relevant `AGENTS.md` and roadmap passages. No referenced stores or spec delta. No build, test, analyzer, or map command ran.
- **Required-changes recheck:** Re-read the prior `review.md`, revised `design.md` and `proposal.md`, and the narrow tracked compiler, fixture, XML migration and gate citations for both items. Both match. This was a document and source recheck only; no verification commands ran.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Critical (blocking)

None. FULL remains appropriate: the dependency pair crosses both the frozen-generation and vector-runtime boundaries without introducing new ownership, publication mechanisms, or product rules.

### Moderate

1. **F6 — Make the real-render regression part of the pinned fast gate.** D1 (`design.md:24-27`) now calls for actual compile, rasterization, and a pixel assertion, not just successful decoding. But “an offline test” does not require the app-icon compiler path or discovery by `mise run test`. The real host already is an offline test outside `test/` (`tool/app_icon/render_host_test.dart:1-9,61-85`), while the success test in `test/` uses an unfiltered rectangle and a rasterizer that ignores the compiled bytes (`test/tool/app_icon/build_test.dart:107-124`; `test/tool/app_icon/support/icon_fixture.dart:7-10,22-36`). The map codec smoke test is also unfiltered (`test/maps/vector_format_test.dart:13-37`). The hosted Test step calls `mise run test` (`.github/workflows/gates.yml:77-81`; `mise.toml:8-13`), so the amended text still permits the same green gate without coverage for silently dropped blur.
2. **Claims — Distinguish the pre-upgrade baseline from the applied migration.** `design.md:20` says the shared fixture currently uses `<filter>`, and `design.md:52` says the tracked tests still use `namespace:`. Those statements are true at the recorded base, not in the cited current files: the fixture now uses `<foreignObject>` (`test/tool/app_icon/support/icon_fixture.dart:12-15`), and both assertions now use `namespaceUri:` with their original values (`test/maps/map_preparation_test.dart:1340-1347`; `test/maps/map_preparation_qualification_test.dart:559-565`). The XML migration also changes `XmlName` construction in production SVG normalization and a qualification fixture (`tool/maps/svg.dart:253-259`; `test/maps/map_preparation_qualification_test.dart:820-826`), which the proposal’s Impact and design Context omit. Without the distinction, the review record misstates what was changed and what still needs proof, and makes the XML migration appear test-only.

### Suggestions

None.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. In D1’s Proof, require a small, untagged offline Flutter test under `test/` that runs in the pinned `mise run test` gate. Compile the synthetic Gaussian-blur SVG through the production app-icon compiler entry (`compileIconSvg`, directly or through `compileSources`) and rasterize those bytes with the resolved Flutter vector runtime. Require nonzero alpha in a margin beyond the unfiltered shape’s antialiasing edge, where the same unfiltered shape is transparent. A fake rasterizer, a decode-only check, or an invocation outside the gate is not proof. Keep committed artwork, admission rules, and package scope unchanged.
2. In design Context and A2, label `<filter>` and `namespace:` as pre-upgrade behavior at the recorded base and describe the current fixture/keyword changes using the tracked citations. Keep A1 and A2 as outcome checks, not claims that the tests have passed. In design Context and proposal Impact, record the `XmlName.parts` changes in SVG normalization and the qualification fixture as mechanical XML API migration; keep the existing test expectations and gate assignments.

CHANGES_APPLIED: yes

## Rebuttals

- **F1–F5 — Fixed in the design.** `Carried constraints: None` and the separate Existing constraints section correctly describe unchanged rules. F1: compiler and render admission already follow from `openspec/specs/app-icon/spec.md:82-91` and ADRs 0027/0028. F2: ADR-0033 already retains the generation and its build provenance on reproduction (`18-23`). F3: the marker spec already forbids filters separately (`27-28`), consistent with ADR-0023. F4: the prepared-pack spec already places serialization of all writers on the operator (`295-297`). F5: it already requires the owner’s before-merge check for non-provenance differences, including manifest-only changes (`128-142`). The three specs and ADR-0033 are unchanged from the recorded base; no artificial spec/ADR delta is needed. S1, D1, D2, and `skip_specs: true` remain consistent with the two-package upgrade and unchanged rules.
- **F6 — Partly fixed at the original review.** D1 now calls for real pixels beyond the original shape. The gate, production compile path, and blur-discriminating assertion need to be explicit as above. This is a design assessment, not evidence that any rendering test passed. F7 is a separate pre-ship roadmap item, not a change to this design verdict.
- **Earlier blockers remain resolved.** C1 and M9: the split pointer/pubspec/pruning sequence, phase-specific recovery, and at-most-one temp directory are accurately recorded. M3: the resolved codec test must pass before rebuild publication. M4 and M7: a successful reproduction, reported differences, operational failure, and cleanup warnings stay distinct; recovery preserves the first report and owner gate. M1 and M8: compiler rejection and XML namespace behavior remain explicit verification obligations with existing assertions preserved; the current-source wording is addressed above. M2: both version rows and license comparison stay in scope. M5: the earlier destination mapping is superseded by the baseline classification above. M6: the prior review’s recorded branch-gate exception is not reopened.
- **Required change 1 (F6) — Applied and rechecked.** D1’s Proof (`design.md:27`) requires a small, untagged offline Flutter test under `test/` in `mise run test`, compilation through `compileIconSvg` or `compileSources`, rasterization with the resolved Flutter vector runtime, and a nonzero-alpha margin beyond the antialiasing edge that stays transparent without blur. The tracked wrapper confirms the compiler entry, and the fast gate excludes qualification rather than untagged tests. D1 and the proposal keep the existing admission policy, artwork and two-package scope. This confirms the proof requirement, not a passing test result.
- **Required change 2 (Claims) — Applied and rechecked.** Context (`design.md:18,20`) and A2 (`design.md:52`) distinguish the baseline `<filter>` fixture and `namespace:` calls from the tracked `<foreignObject>` fixture and `namespaceUri:` assertions. The base comparison confirms the wildcard still expects `#kept` and the exact xlink URI still expects `#base`. Context and Impact (`proposal.md:19`) record `XmlName.parts` in SVG normalization and the qualification fixture. A1 and A2 (`design.md:51-52`) remain outcome checks; the wildcard stays in the pinned fast suite and the exact URI stays in hosted qualification.
