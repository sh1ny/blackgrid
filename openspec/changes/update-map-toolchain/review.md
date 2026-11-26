# Review

## Metadata

- **Round:** 2
- **Prior round:** REVISE — split-publication recovery and seven moderate findings.
- **Reviewer:** fresh-context subagent (omp)
- **Reviewed:** `proposal.md`, `.openspec.yaml`, `design.md`, prior `review.md`, `openspec/architecture.md`, `openspec/roadmap.md`, the three carried-constraint main specs, ADRs 0005/0023/0024/0027/0028/0033/0050, `AGENTS.md`, the named `dart-add-unit-test` and `dart-run-static-analysis` skills, and the cited tracked task, workflow, dependency, notice, map, icon, marker, and test evidence. Also read the cited Git history and base refs. No referenced store or spec delta; no builds, tests, analyzer, or map commands ran.
- **Required-changes recheck:** Fresh-context subagent (omp); read the current proposal and design, the round 2 review, the named skills and the tracked source ranges relevant to the three required changes. No builds, tests, analyzer, or map commands ran.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Critical (blocking)

None. The revised design no longer treats the absence of leftovers or a passing reproduction check as proof of a complete publication.

### Moderate

1. **M3 — Make a passing codec test a precondition for publication.** `design.md:87-89,97,113` names the fast gates and tells the operator what to do *if* the codec test finds a mismatch, but the rebuild path has no explicit condition that the test has passed first. The pack builder records the format it emitted, and validation checks the payload against that record and recompilation, not the app's supported format or decoder (`tool/maps/pack.dart:1231-1241,1495-1508,1920-1931`). The loader separately rejects a different format (`lib/maps/prepared_map_loader.dart:134-145`), and `refreshActive` publishes after its report (`tool/maps/pack.dart:3434-3454`). Running the codec test only with the final CI gates could therefore discover an incompatible generation after the operator has changed the pointer, declarations and generation inventory. Gate `maps:rebuild` on the existing header-and-decode test with the resolved pair, not on the difference report alone. Neither a header mismatch nor a decode failure permits publication within the approved scope.
2. **M8 — The XML migration cites the old calls, not the replacement API.** `design.md:18,113` presents the XML 7 namespace change as established. The tracked tests show only `namespace: '*'` and `namespace: 'http://www.w3.org/1999/xlink'` (`test/maps/map_preparation_test.dart:1340-1347`; `test/maps/map_preparation_qualification_test.dart:559-565`). The proposed keyword and preserved lookup semantics are assumptions about the resolved `xml` version. Without explicit verification of both cases, a green fast gate alone could miss the exact-URI regression, since `mise run test` excludes qualification (`mise.toml:8-13`). Keep the expected values and require both the fast and hosted qualification assertions to pass with the resolved package.
3. **M9 — The publication and temporary-directory citations omit the deciding steps.** At `design.md:99`, the cited promotion range ends immediately before `next.rename(pointer.path)` (`tool/maps/pack.dart:2182`), the operation that removes `active.next.json` before the separate pubspec rename (`3041`). Include the pointer rename in the citation so an operator following the recovery rationale sees the actual split boundary. At `design.md:93`, `checkActive` creates *at most* one temporary directory, not one on every invocation: it can fail the leftover guard before allocating any (`tool/maps/pack.dart:2750-2753`). A guard refusal calls for inspecting the named pack leftover, not looking for a new check directory.

### Suggestions

None. FULL remains warranted for the frozen-pack and vector-runtime boundaries. The existing transaction, validation and CI gates are sufficient without a new mechanism or spec delta. The only owner-only acceptance step is the visual check when the rebuild reports non-provenance differences.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. In Flow & State Gaps or Risks / Trade-offs, require a pass of `test/maps/vector_format_test.dart` with the resolved pair before any `maps:rebuild` publication, whether the test runs on its own or in the pinned fast gate. Stop on either a header mismatch or a decode failure; retain the owner scope decision for a genuine format change and do not change the constant to mask a decode failure.
2. Add an assumption for the `namespaceUri:` migration with XML 7.0.1, and describe the Context edit as a migration to verify rather than a tracked fact about XML 7. Keep the wildcard, exact URI and expected values; verify the former in the fast test and the latter in hosted qualification.
3. Extend the Flow & State Gaps promotion citation through `tool/maps/pack.dart:2182`. In Resource Bounds, say `checkActive` allocates at most one temporary directory, after its leftover guard passes, and extend that citation to start at line 2750. Keep the cleanup warning and result semantics as written.

**Required-changes recheck (round 2):**

1. **M3 — Applied.** Risks / Trade-offs requires `test/maps/vector_format_test.dart` to pass with the resolved pair, alone or in the pinned fast suite, before any `maps:rebuild` publication. It requires a stop on either failure, keeps the owner scope decision for a genuine format change, and bars changing the constant to address a decode failure. The cited test checks the header against `preparedVectorCodecFormat` and calls the decoder (`test/maps/vector_format_test.dart:19-37`).
2. **M8 — Applied.** Context describes a migration to verify, and A2 identifies namespace matching under `xml` 7.0.1 as an assumption. The design preserves the existing wildcard and exact URI and their expected values (`['#kept']` and `'#base'`, respectively), and assigns verification to the pinned fast suite and hosted qualification, respectively (`test/maps/map_preparation_test.dart:1340-1347`; `test/maps/map_preparation_qualification_test.dart:559-565`; `mise.toml:8-17`). This confirms the verification plan, not the resolved API's behavior.
3. **M9 — Applied.** Flow & State Gaps now cites promotion through the pointer rename at `tool/maps/pack.dart:2182`, before the separate pubspec rename and pruning (`3034-3053`). Resource Bounds cites `2750-2775` and states that `checkActive` allocates at most one temporary directory after the leftover guard passes. The code corroborates the named-leftover diagnostic (`2224-2248`) and the unchanged `finally` cleanup warning and comparison result.

CHANGES_APPLIED: yes

## Rebuttals

- **C1 — Fixed.** The design separates pointer, pubspec and pruning writes, requires inspection after failure or interruption, and preserves the original baseline-to-candidate report and owner requirement even when recovery prints that no review is needed. M9 is an evidence-anchor correction, not a reopening of the split-publication blocker.
- **M1 — Fixed.** A1 replaces the external source citation with an explicit assumption and requires real compiler rejection in the normal-source, small-source and sheet cases before accepting the fixture. Filename, pre-render failure and output protections remain; the fixture's result is not yet verified.
- **M2 — Fixed.** Proposal and design include both version/link rows and comparison against the existing licences; unrelated resolution and historical pack provenance remain out of scope.
- **M3 — Partially fixed; see M3 above.** The pinned gates, retained namespace assertions, final hosted check and scope stops for icon/marker drift are in place. Make the runtime codec proof an explicit precondition of publication.
- **M4 — Fixed.** The flow distinguishes reproduction, a completed comparison with differences and operational failure. It identifies the exact PR notice and requires the original report and owner check for manifest-only differences as well as changed files.
- **M5 — Fixed.** Five discrete constraints now each have one matching destination: app-icon checks, reproduction provenance, the marker filter ban, serialized publication and the owner gate.
- **M6 — Fixed as a recorded exception.** The branch-gate section records the dispatch authorization and failed `on_main` condition explicitly. Git supports the recorded branch/base/roadmap-commit shape and lack of a same-name archive; it does not independently establish the historical clean state or fetch, which are recorded as pre-scaffold observations.
- **M7 — Fixed.** `finally` attempts cleanup; failure can report a leftover even on a successful comparison and is not evidence of drift. M9 separately corrects when a temporary directory is allocated.
