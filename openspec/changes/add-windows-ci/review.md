# Review

## Metadata

- **Round:** 2
- **Prior round:** Round 1 APPROVE_WITH_CHANGES: M1 main concurrency group, M2 local ci:qualification behaviour
- **Reviewer:** fresh-context subagent (Claude Code)
- **Reviewed:** Re-check of round 1's Required Changes only. Read openspec/changes/add-windows-ci/review.md (round 1 and its Rebuttals), openspec/changes/add-windows-ci/design.md (Triage, D3, D4, D5, D7, the run-lifecycle diagram, Failure & Visibility, Resource Bounds, Flow & State Gaps), openspec/changes/add-windows-ci/proposal.md (What Changes, Impact) and openspec/changes/add-windows-ci/specs/continuous-integration/spec.md (requirement "CI runs on every pull request and push to main"); evidence: test/data/capture/support/native_guard.dart, AGENTS.md. Skills loaded: dart-add-unit-test, dart-use-pattern-matching, dart-write-documentation, dart-run-static-analysis (all loaded).

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. The `main` concurrency group cancels queued `main` runs, contradicting the spec and D5.** (Round 1.) **Resolved in round 2.**
D5 (design.md:87-89) now uses `group: ${{ github.event_name == 'pull_request' && format('ci-pr-{0}', github.event.pull_request.number) || format('ci-push-{0}', github.sha) }}` with `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`, which is the round 1 example. It also explains the one-running-one-pending behaviour that made the shared group unsafe. Each push to `main` now has its own group, so a later push cannot cancel a pending one. PR runs keep per-PR groups with cancellation, which still satisfies the scenario "A newer commit supersedes a running pull request run". The Resource Bounds row "Concurrent runs on `main`" (design.md:203) now says one group per pushed SHA, with none cancelled or replaced. The state diagram limits `running --> cancelled` to "PR runs only" (design.md:147). The D4 offline workflow test asserts that the push group contains `github.sha` (design.md:76). The spec adds the scenario "Pushes to main in quick succession" (spec.md:20-22): A, B and C each complete and none is cancelled or replaced. All four parts of Required Change 1 are applied.

**M2. `mise run ci:qualification` cannot pass on a developer machine without setting the no-games flag, so "run the same command locally" pushes towards the exact behaviour the safety rule forbids agents to do.** (Round 1.) **Resolved in round 2 with option (a).**
D3 (design.md:58) marks the task CI-only, with no local mode or option. It says the task fails the audit locally by design, because the capture test's "set BLACKGRID_NO_GAMES_RUNNING=1 ..." skip reason (`native_guard.dart:19-21`) is not on the allowlist. Only the user may set the flag for a local run, an agent never does, never to turn the task green, and developers use `mise run test:qualification`. D7 (design.md:107-108) puts the same statement in the README and AGENTS.md, including "Agents never set it on a developer machine, including to make a local `ci:qualification` run pass". The proposal's Impact bullets for `mise.toml` and AGENTS.md (proposal.md:28, :30) say the same. Option (a) does not need a new spec scenario because there is no local option, so nothing is missing. Required Change 2 is applied.

Non-blocking residue from the edits. Each item is wording only and changes no decision:
- D4 still introduces its offline test with "checks three things" (design.md:72) but now lists four bullets.
- The proposal's What Changes still names the CI step `mise run test:qualification` (proposal.md:9) and says the README covers "how to reproduce a CI step locally" (proposal.md:15). D3/D7 and the Impact section are authoritative and say `ci:qualification` is CI-only. The README text written during apply should follow D7.
- D3's "fails locally ... unless the user confirms" is a little generous. Locally, even with the flag set, the task also needs `BLACKGRID_RELEASE_BUNDLE` (otherwise it exits 2), `BLACKGRID_PANEL_OCR_RUNTIME` and `BLACKGRID_CMAKE`, because their skip reasons are unlisted. This makes the task stricter, not looser, so it has no safety consequence.
- Triage T3 (design.md:9) still says "Concurrent runs for the same PR or `main`, with cancellation". Cancellation now applies to PR runs only.

### Suggestions

**S1. Key the allowlist's file on the suite path, not the test `url`.** In the `flutter test` JSON protocol, `testStart.test.url` is where the test was *declared*, which is a helper file when a test is registered through a support function, and it can be null. `suite.path` (from the `suite` event, joined by `suiteID`) is always the test file. The audit fails closed either way, so nothing passes by mistake. The risk is a false red after a refactor that moves `test(...)` calls into `test/qualification/support/`. Also state that `hidden: true` entries (the `loading <file>` test and `(setUpAll)`/`(tearDownAll)`) are excluded from both the skip audit and the "at least one test ran unskipped" count.

**S2. The vision-input cache is only saved after a green job.** `actions/cache` saves in its post step with `post-if: success()`. If the first runs are red, which the design expects as a possible outcome for the capture test on the hosted desktop (Risks), every run downloads the OpenCV source, Tesseract and model again. Caches saved on PR runs are also scoped to that PR's ref. Using `actions/cache/restore` before `build:release` plus `actions/cache/save` right after it (keyed on the lock file) would make the cache independent of the later qualification result. This only affects speed. It never affects correctness, so D6's argument still holds.

**S3. Add the hosted-image OCR dependency to the risks.** The unskipped `m5_panel_ocr_test.dart` cases load `blackgrid_panel_ocr.dll` (Windows.Media.Ocr, ADR-0006) on `windows-2025`, a Server image whose OCR language availability the design does not check. Give it the same handling as the capture-desktop risk: it fails visibly, and the user decides about any allowlist entry.

**S4. Say that ADR-0024 amends ADR-0009's "Local release tasks, no CI" bullet** (`docs/adr/0009-release-versioning.md:18`). Without that, the architecture index shows two in-force ADRs that read as contradictory.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1) In design.md D5, change the concurrency group so pushes to `main` never share a group with each other. For example, `group: ${{ github.event_name == 'pull_request' && format('ci-pr-{0}', github.event.pull_request.number) || format('ci-push-{0}', github.sha) }}` with `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`. Alternatively, have no concurrency group for push events. Correct the "Concurrent runs on `main`" row in Resource Bounds and the state-diagram note to match. Extend D4's offline workflow test, or the spec scenario "A push to main", so a `main` push can never be cancelled by a later push. For example, the push group must contain `github.sha` or `github.run_id`.
   **Applied (round 2 re-check):** D5 group and cancel expression (design.md:87-89), Resource Bounds row (design.md:203), state diagram "PR runs only" (design.md:147), D4 test asserts `github.sha` in the push group (design.md:76), and the new spec scenario "Pushes to main in quick succession" (spec.md:20-22).
2. (M2) In design.md (D3 and D7) and the proposal's mise.toml/README bullets, state the local behaviour of `mise run ci:qualification` explicitly. Choose one of:
   - (a) It is CI-only. The README directs developers to `mise run test:qualification` with the inputs they have, and says the CI task fails locally by design unless the *user* confirms no game is running.
   - (b) An explicit command-line option (for example `--local`), never inferred from the environment, additionally accepts the capture test's "not confirmed" skip reason and the private-input reasons, and reports them as unverified.
   Whichever is chosen, AGENTS.md (D7) must say that an agent never sets the flag to turn a local `ci:qualification` run green. If (b) is chosen, add a spec scenario showing that the workflow never passes that option, covered by the D4 offline workflow test.
   **Applied (round 2 re-check), option (a):** D3 CI-only paragraph (design.md:58), D7 README and AGENTS.md bullets (design.md:107-108), and the proposal's Impact `mise.toml` and AGENTS.md bullets (proposal.md:28, :30).

CHANGES_APPLIED: yes

## Rebuttals

- **M1:** fixed. D5 now uses one concurrency group per pushed SHA (`ci-push-${{ github.sha }}`) and keeps `ci-pr-<number>` with cancellation for PRs. The Resource Bounds row is corrected. D4's offline workflow test asserts that the push group contains `github.sha`, and the spec adds the scenario "Pushes to main in quick succession".
- **M2:** fixed with option (a). D3 makes `ci:qualification` CI-only, with no local mode, and says it fails locally by design unless the user confirms that no game is running. D7 (README, AGENTS.md) and the proposal's Impact say the same, including that an agent never sets the flag to make a local run pass.
- **S1-S4:** deferred to apply, with no design edit. These tasks carry them:
  - S1: the audit matches on `suite.path`.
  - S2: separate `actions/cache/restore` and `actions/cache/save` steps around `build:release`.
  - S3: the panel OCR test on the Server image fails visibly, and any allowlist entry is the user's call.
  - S4: ADR-0024 states that it amends ADR-0009's "no CI" bullet, and its index row says so.
