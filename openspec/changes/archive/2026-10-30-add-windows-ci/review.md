# Review

## Metadata

- **Round:** 3
- **Prior round:** Round 2 APPROVE_WITH_CHANGES. M1 (main concurrency group) and M2 (local `ci:qualification` behaviour) were both resolved and applied; S1-S4 were deferred to apply. The pre-ship amendment e832e54 (host-platform allowlist entry) voids that verdict, so this round reviews the amended change as a whole.
- **Reviewer:** fresh-context subagent (Claude Code)
- **Reviewed:** `git show e832e54`; openspec/changes/add-windows-ci/proposal.md, design.md, specs/continuous-integration/spec.md, tasks.md (test map and tasks), review.md (round 2). Evidence: test/qualification/m2_vision_runtime_test.dart, test/qualification/m2_vision_self_check_test.dart, test/data/capture/support/native_guard.dart, tool/ci/qualification_skips.yaml, tool/ci/src/audit.dart, test/tool/ci/qualification_audit_test.dart, windows/runner/runner.exe.manifest, lib/application/vision_self_check.dart (runtime directory default), README.md:338, docs/adr/0024-hosted-ci-runs-every-offline-gate.md:15, openspec/architecture.md:71,177, AGENTS.md. Skills loaded: dart-add-unit-test, dart-use-pattern-matching, dart-write-documentation, dart-run-static-analysis (all four loaded).

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Critical (blocking)

None.

### Is the covering-test claim real?

Yes. The claim holds, with one gap (M2 below):
- `m2_vision_runtime_test.dart:235-256` skips "bundle copied under Cyrillic path opens ready" only when the bundle is set and `GetACP() != 65001`. The reason string is built from the live code page, so the allowlisted text `ANSI code page 1252 is not UTF-8; covered by ...` matches only on code page 1252 and only in that file (the audit matches the exact `(file, reason)` pair: `qualification_audit_test.dart` "an allowlisted reason in another file fails", "an allowlisted file skipping for another reason fails"). The bundle-missing reason in the same file is a different string, so the entry cannot accept it.
- `m2_vision_self_check_test.dart:108-116` "self-check from bundle copied under Cyrillic path exits 0" copies the whole bundle under `Блэкгрид тест`, starts `blackgrid.exe --vision-self-check` there, and requires exit 0 with a pass report and every step ok. Self-check opens the runtime from `File(Platform.resolvedExecutable).parent` (`lib/application/vision_self_check.dart:176`), which is the Cyrillic directory. `windows/runner/runner.exe.manifest:7` sets `activeCodePage` to UTF-8. So it exercises the same behaviour (vision runtime opens ready from a Cyrillic path) on the path the product actually uses. The in-process variant tests a configuration that the product never runs (a process without the manifest).
- Its only skip conditions are a missing `BLACKGRID_RELEASE_BUNDLE` or the `tasklist` check for EscapeFromTarkov.exe (`:16-21`, `:120-136`). It has no code-page condition. On CI the bundle is set and no game is listed, so it runs. If it does skip, both of its reasons are unlisted, so the audit fails. If it fails, the test exit code fails the run.

### Is the "host-platform skip" kind tight enough?

Today's entry is tight: exact reason, exact file, a single code page. The *kind*, though, is defined only in prose ("such as a UTF-8 system code page"). The spec's guard sentence ("A skip caused by a missing environment variable or by the capture guard is never a host-platform skip") has no test that reads the committed allowlist. Details in M2.

### Moderate

**M1. tasks.md has no open work for the amendment, and the change's own artifacts and docs still say "three private-input entries".**
- The new test map row "the host-platform entry names a covering self-check test that has no platform skip" is `red`, but every task is `[x]`. No task adds the fourth entry to `tool/ci/qualification_skips.yaml`, writes that test or updates the docs. Task 4.1 ("Confirm every Test map row reads green") cannot be satisfied as written.
- Without the fourth entry the shipped YAML still fails every hosted run. That was the pre-ship P1, so the fix exists only on paper.
- These places still describe a private-input-only allowlist with three entries, and they now contradict the amended spec:
  - `tool/ci/qualification_skips.yaml:1-3`: "Only tests that need private input belong here; bundle-based tests must run, never skip". The Cyrillic test is bundle-based.
  - README.md:338: "Three tests ... The committed allowlist accepts exactly those skips".
  - docs/adr/0024-hosted-ci-runs-every-offline-gate.md:15: "The allowlist names only tests that need private, uncommitted inputs".
  - openspec/architecture.md:177 index row: "allowlist of private-input tests".
  - design.md D7: "the three local-only qualification tests". design.md ADRs section: "a committed allowlist of private-input tests".
  - tasks.md 2.2 ("with the three entries"), 3.3 ("the three allowlisted local-only qualification tests") and Workflow follow-up ("the audit's accepted skips, exactly the three allowlisted tests"). The follow-up is a live-evidence check, and it would record the first CI run as a mismatch.
- ADR-0024 is an in-force ADR written by this change. If it is left as is, a later reviewer would treat the fourth entry as a violation of it.

**M2. The guard against the loophole is prose only. The audit tests never read the committed allowlist, and nothing ties the entry to its covering test.**
- `test/tool/ci/qualification_audit_test.dart:26-30` audits against an inline three-entry `_allowlist`. The row "the capture guard's refused and unconfirmed reasons are not allowlisted" (`:190-222`) therefore proves only that an *unlisted* reason fails. It does not prove that the committed `qualification_skips.yaml` omits those reasons. Its "unconfirmed" string is also not the verbatim `native_guard.dart:20-21` text.
- A later edit could add the capture guard's reason, or `Requires BLACKGRID_RELEASE_BUNDLE (a built Release bundle).`, to the YAML with a plausible `why`, and every offline test would stay green. That is the loophole the amendment's guard sentence forbids, and the new "kind" makes such an edit look legitimate. Since the YAML has no kind field, a reviewer cannot tell a private-input entry from a host-platform one.
- `why` is free text, so "the entry's `why` names that covering test" cannot be checked by a machine. If the self-check test is renamed or deleted, the host-platform entry still accepts the runtime skip, and the Cyrillic path is then unverified on CI with the run still green.
- The red row's test name ("names a covering self-check test that has no platform skip") states the intent but not how it is checked.

Make the property testable at the fast layer:
- give entries a structured `kind` (`private_input` or `host_platform`);
- give `host_platform` entries a structured `covered_by: {file, test}`;
- add tests over the committed YAML (see Required Changes).

### Low

- design.md D3 still says the allowlist "is matched on the file path decoded from the test `url`". The implementation and task 2.2 match on `suite.path` (round-2 S1). Wording only.
- The proposal's What Changes says "The allowlist holds only the tests that need private, uncommitted inputs" and then "One host-platform skip is allowlisted as well". It reads as self-contradictory. Say "two kinds" as the spec does. Round-2 residue is also still present: the CI step is named `mise run test:qualification` (proposal.md:9) where D3/Impact use `ci:qualification`.
- The spec's "Bundle-based tests run" exception ("except a test with an allowlisted host-platform skip") is acceptable only because the allowlist requirement bounds it. M2's tests are what make that bound real.

### Suggestions

**S1. Optionally have the audit enforce the coverage at runtime as well.** When a `host_platform` entry is accepted, the audit could require its `covered_by` test to appear in the same report as run, unskipped and successful, and otherwise emit a new `AuditFinding` (for example `UncoveredHostSkip`). This closes the rename gap end-to-end. It costs one sealed subtype and one audit test. The static test in Required Change 2 is sufficient if you prefer not to.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1) Add open tasks to tasks.md for the amendment, and update the stale text:
   - **New tasks.**
     - Add the fourth `qualification_skips.yaml` entry, with the exact reason from `m2_vision_runtime_test.dart:254-255` on code page 1252, and rewrite the file's header comment to describe the two kinds.
     - Write the red test-map row's test and flip it green.
     - Update README.md:338, ADR-0024:15 and the architecture.md:177 index row to describe two kinds: private-input entries, and the one host-platform entry with its covering test.
   - **Text to correct.**
     - design.md D7 and the ADRs section (drop "three"/"private-input only").
     - tasks.md 2.2, 3.3 and the Workflow follow-up (expected accepted skips: the three private-input tests plus the Cyrillic runtime test, and record that the self-check Cyrillic test ran unskipped).
     - design.md D3 "`url`" → `suite.path`.
2. (M2) Make the host-platform guard machine-checked over the committed allowlist:
   - Add `kind: private_input | host_platform` to every entry, and `covered_by: {file, test}` to every `host_platform` entry. `parseAllowlist` rejects a `host_platform` entry without `covered_by`.
   - Add tests in `test/tool/ci/qualification_audit_test.dart` (fast loop, untagged) that load `tool/ci/qualification_skips.yaml` itself and assert:
     - (a) no entry's reason equals any capture-guard reason. Produce these with `nativeCaptureSkipReason` from `test/data/capture/support/native_guard.dart` with fake inputs (unconfirmed, tasklist failed, each refused game), plus the self-check test's "Escape from Tarkov is running ..." reason.
     - (b) no entry's reason starts with `Requires BLACKGRID_RELEASE_BUNDLE`, `Requires BLACKGRID_PANEL_OCR_RUNTIME` or `Requires BLACKGRID_CMAKE` (or names those variables).
     - (c) every `covered_by.file` exists and declares a test with exactly the name `covered_by.test`.
   - Give these assertions a test map row under "A host-platform skip is covered on CI", and one under "A game executable is listed" in place of, or next to, the current synthetic-allowlist row. Then update the spec scenario text only if its wording changes. The behaviour it states already requires this.

CHANGES_APPLIED: yes

## Rebuttals

- **M1:** fixed.
  - **New tasks.** tasks.md has a new group 5 for the amendment:
    - 5.1 adds failing tests for the red rows;
    - 5.2 adds `kind`/`covered_by`, the fourth entry and the new header comment;
    - 5.3 updates README, ADR-0024 and the architecture index row;
    - 5.4 re-runs the offline loop.
  - **Workflow follow-up.** It now expects the three private-input skips plus the 1252 Cyrillic runtime skip, and records that the self-check Cyrillic test ran unskipped and passed. A note says group 5 supersedes the three-entry wording of tasks 2.2 and 3.3.
  - **design.md.** D7 and the ADRs section describe the two kinds. D3 matches on `suite.path`.
  - **Proposal.** It names `ci:qualification` and describes the two kinds without "only".
- **M2:** fixed in the design (D3 allowlist format), with tasks 5.1/5.2 and two new Test map rows. The changes:
  - `kind: private_input | host_platform` on every entry;
  - `covered_by: {file, test}` required on `host_platform` and refused on `private_input`;
  - fast-loop tests over the committed YAML: no capture-guard reason generated through `nativeCaptureSkipReason` or the self-check reason, no reason naming the bundle, OCR runtime, CMake or no-games variables, and every `covered_by` resolves to an existing test name.

  The spec scenario wording already requires this behaviour and is unchanged.
- **Low findings:** the D3 `url` wording and the proposal's "only" and `test:qualification` are fixed. The optional suggestion, a run-time check that the covering test passed in the same report, is not adopted. A skipped covering test already fails the audit as an unlisted skip, a failed one fails the run, and a renamed one fails the static `covered_by` test.

