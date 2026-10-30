# Blackgrid Roadmap

Strategy: [STRATEGY.md](../STRATEGY.md) · Architecture: [architecture.md](architecture.md) · Historical source: [implementation strategy §11–§12](../docs/IMPLEMENTATION_STRATEGY.md#11-migration-plan)

<!-- Status is derived: a change is done when archived; a milestone is done when its changes are done and its exit criteria pass. Do not add status checkboxes for changes. -->

Milestone IDs keep the implementation strategy's numbering (M0–M6), so they match the CE-era plans and qualification evidence. M2 and M3 were planned as independent after M1; M5 was explicitly authorized before the Scanner milestones ([§11](../docs/IMPLEMENTATION_STRATEGY.md#11-migration-plan)). "(user)" marks a criterion only the user can verify: anything that needs the game running, a real saved game screenshot, or a clean Windows machine. Agents never run those checks ([AGENTS.md](../AGENTS.md)). Until the user reports a result, it is unverified, never passed.

A change that names a GitHub issue resolves it through its PR: the PR description links the issue with a closing keyword (`Closes #41`), so merging the PR closes the issue, and the PR's body says what of the issue it delivers. If the PR delivers only part of the issue, it links it with `Refs #N` instead, and the issue says what is left.

## Now: M4.6 - open-issue sweep

Runs after M4.5 and before M6, so every open GitHub issue is judged before a release. Decided with the user on 2026-10-19. No issue is accepted in advance: each is judged when the sweep starts, against `main` at that time, not against the review that filed it. Issues a milestone already names (such as #41 and #43) stay with that milestone.

**Exit criteria:**
- Every open issue not already assigned to a milestone has a verdict agreed with the user, recorded on the issue with its reason: fix now, defer to after 1.0, or close. (agent proposes; user decides)
- An issue that no longer applies (already fixed, code rewritten, premise wrong or superseded by a later decision) is closed with the evidence. (agent)
- An issue that still applies but is too minor or too unlikely to matter before 1.0 is deferred to after 1.0, not fixed. (agent)
- Each "fix now" issue is closed by the PR of the change that fixes it, with a regression test at the lowest layer that reproduces it. No fix weakens an integrity, ownership or safety check. (agent)

**Changes** (in order):
1. `sweep-open-issues` - lists the open issues, re-checks each against current `main` (does the cited code still behave that way, is it reachable, how likely and how bad is it) and proposes a verdict for each. The user decides. The agreed fixes are then added to this list as small changes, grouped by area, each naming the issues its PR closes. A roadmap edit, not a code change.
2. `fix-changelog-spec` - closes #17. Spec-only fix to the release-versioning changelog rule: split the entry rule into PR entries (title and number) and direct-commit entries, add a first-release scenario (which `tool/changelog.dart` already handles), and describe squash-merged PRs. The sweep closed #30 and deferred the other 16 open issues to after 1.0 with the `post-1.0` label.

## Next: M6 - Windows CI and releases

Rescoped with the user on 2026-10-30; more work will be added before M6 starts. M6 opens with full CI on GitHub's Windows runners and GitHub Releases in two formats, a zip of the Release bundle and an installer, so a version is built and published without the developer's machine. The installer format (MSIX or Inno Setup) and code signing are decided in M6; until then versions are tags with local builds only ([Release versioning](#release-versioning-add-release-versioning)). Offline, refresh and auth failures and restart, import and history correctness (risks 3 and 7) stay in M6, after CI and releases. The user may move them out once M6's scope is settled. The clean-machine, display-matrix and pending user checks moved to Later.

## Later

- After 1.0: the issues the M4.6 sweep defers to after 1.0.
- Needs testers besides the user (moved out of M6 on 2026-10-30):
  - Clean-machine qualification of the release bundle: packaged DLLs, models, artwork and notices on a fresh Windows machine.
  - The full display and mixed-monitor matrix. The M2 corpus covers 3440×1440 only.
  - The user-only checks M3 waived and M5 left pending: real saved panels, extract and transit highlights, and automatic floors.
  - The [§14](../docs/IMPLEMENTATION_STRATEGY.md#14-definition-of-done) definition of done, which depends on the checks above.

## Release versioning (`add-release-versioning`)

Decided with the user on 2026-10-08 and recorded in [ADR-0009](../docs/adr/0009-release-versioning.md): SemVer `v` tags, one minor version per milestone close (M2 → `0.2.0`), `-beta.N` prereleases for user-only checks, a commit-count build number, and a changelog with one entry per merged PR.

Release flow (local, no CI; details in the [README](../README.md)):

- `mise run release:prepare -- <version>` - checks a clean, current `main`, runs the offline gates, then commits `chore(release): v<version>` on `release/v<version>`.
- `mise run release:tag` - after the release PR merges, tags the merge `v<version>` and pushes the tag as the configured GitHub login.
- `mise run build:release` - builds the Windows Release bundle with the version and build number, then runs `bundle:check`.
- `mise run release-notes -- --unreleased` - previews the next release's entries.

Installers, GitHub Releases, code signing and CI builds belong to M6.

## Done

- M0 - reference qualification and provenance - 2026-10-06 ([PR #1](https://github.com/sh1ny/blackgrid/pull/1), [PR #2](https://github.com/sh1ny/blackgrid/pull/2)) - [plan](../docs/plans/2026-10-05-1006-test-m0-reference-qualification-plan.md), [evidence](../docs/qualification/m0/) - Delivered the rights-gated dossier, protocol and validators. The reference baseline, labelled corpus and display matrix remain unverified or blocked; that did not block authoring new code, and the remaining checks now sit in M2, M4 and M6.
- M1 - shared shell and decision foundation - 2026-10-06 ([PR #3](https://github.com/sh1ny/blackgrid/pull/3)) - [plan](../docs/plans/2026-10-06-0242-feat-m1-manual-item-decisions-plan.md), evidence: no `docs/qualification/` record; offline tests and [`integration_test/m1_windows_smoke_test.dart`](../integration_test/m1_windows_smoke_test.dart) - The conservative decision engine, mode-scoped catalog, read-only Tracker and DPAPI credentials landed as pure, testable layers that Scanner can reuse.
- M3 - native map proof - 2026-10-06 ([PR #4](https://github.com/sh1ny/blackgrid/pull/4)) - [plan](../docs/plans/2026-10-06-1026-feat-m3-native-map-proof-plan.md), [evidence](../docs/qualification/m3/STATUS.md) - The native renderer was proven on Interchange, Labs and Icebreaker and chosen over a WebView. Delivered under the user's explicit verification waiver: full qualification is not claimed.
- M5 - complete useful native Map - 2026-10-07 ([PR #7](https://github.com/sh1ny/blackgrid/pull/7)) - [plan](../docs/plans/2026-10-07-0050-feat-m5-independent-useful-map-plan.md), [evidence](../docs/qualification/m5/STATUS.md) - All 13 maps were promoted and the user's live map/position check passed. Functional parity with the user's reference companion replaced stricter blocking gates (publisher-deleted `<use>` ids, Windows.Media.Ocr for raid panels). The real saved-panel check is still pending. (user)
- M2 - capture/recognition proof - 2026-10-17 ([PR #9](https://github.com/sh1ny/blackgrid/pull/9), [PR #18](https://github.com/sh1ny/blackgrid/pull/18), [PR #22](https://github.com/sh1ny/blackgrid/pull/22), [PR #26](https://github.com/sh1ny/blackgrid/pull/26), [PR #27](https://github.com/sh1ny/blackgrid/pull/27), [PR #31](https://github.com/sh1ny/blackgrid/pull/31), [PR #32](https://github.com/sh1ny/blackgrid/pull/32), [PR #35](https://github.com/sh1ny/blackgrid/pull/35)) - [corpus runner](../docs/qualification/m2/CORPUS.md), evidence in the archived [`fix-title-crop`](changes/archive/2026-10-17-fix-title-crop/evidence.md) - Agent checks passed on `0.1.0+301` (bundle check, native barrier and capture-geometry fixtures, notices). The user passed the clean-machine check, the independently labelled 50-case 3440×1440 corpus and the live retest (session `20261017-130909`: 7 live accepts, no false positives, no dropped triggers). Corpus result: 31/35 items, 2 false positives, 15/15 rejects; the user waived the reference comparison because no reference baseline exists. Learned: recording live scans finds failures that hand screenshots missed (it exposed the trigger timing and title crop bugs), and every accept still comes from the full-client fallback, so placing the targeted region is M4's first change.
- M4 - complete raid-time Scanner slice - 2026-10-20 ([PR #37](https://github.com/sh1ny/blackgrid/pull/37), [PR #39](https://github.com/sh1ny/blackgrid/pull/39), [PR #42](https://github.com/sh1ny/blackgrid/pull/42), [PR #44](https://github.com/sh1ny/blackgrid/pull/44), [PR #45](https://github.com/sh1ny/blackgrid/pull/45), [PR #46](https://github.com/sh1ny/blackgrid/pull/46), [PR #47](https://github.com/sh1ny/blackgrid/pull/47)) - [evidence](../docs/qualification/m4/EVIDENCE.md) - Agent checks passed. The user's live session on `0.1.0+323` passed the targeted-share, latency, live hotkey and Map checks: with the mouse, 74.6% of accepts came from the targeted pass, targeted trigger to decision was 139.6 ms p95 and the total was 572.4 ms p95. The hotkey figures were below 20 samples and the user accepted them. The user waived the reference timing baseline and the reference corpus comparison: Blackgrid feels responsive and uses less CPU and memory than the reference companion, which they no longer run. Learned: centring the targeted region on the inspect window made the targeted pass the common path, and shared display names now end `ambiguous` instead of being false positives (ADR-0021). Some targeted passes still read the stash's filter button ([#48](https://github.com/sh1ny/blackgrid/issues/48)).
- M4.5 - player-facing polish, item icons and own map markers - 2026-10-29 ([PR #50](https://github.com/sh1ny/blackgrid/pull/50), [PR #51](https://github.com/sh1ny/blackgrid/pull/51), [PR #53](https://github.com/sh1ny/blackgrid/pull/53), [PR #54](https://github.com/sh1ny/blackgrid/pull/54), [PR #56](https://github.com/sh1ny/blackgrid/pull/56), [PR #57](https://github.com/sh1ny/blackgrid/pull/57), [PR #58](https://github.com/sh1ny/blackgrid/pull/58), [PR #59](https://github.com/sh1ny/blackgrid/pull/59)) - Agent checks passed on `main` `da08fdd` (marker provenance check: 19 icons valid; full offline suite and analyze). The user passed the map rail, item icon, requirements & uses and plain-language reads, and the Marker preferences look on re-check after `fix-marker-tile-centering`. Learned: tests that pinned tile size but not position let an off-centre layout through until the user looked, so layout criteria marked "user for the look" also get a geometry widget test where one can prove the invariant.
