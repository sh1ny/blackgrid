# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components (new component, or 3+ with directed relationships) | No | No code changes; see proposal.md Impact |
| T2 State (persistent state, caches, 3+ state machine) | No | Only `openspec/roadmap.md` and GitHub issue state change |
| T3 Concurrency (background work, workers/isolates, async, retries) | No | No code changes |
| T4 Boundaries (data format, migration, shared interface, IPC, external) | No | No format or interface changes. GitHub comments, labels and closes are tracker edits, not a contract the app depends on |
| T5 Volume (grows without a fixed bound) | No | Fixed set of 18 issues |
| T6 Risk (security, money, data loss, unrecoverable user data) | No | Closing an issue can be undone (reopen). Only #30 is closed |

TIER: LIGHT

## Context

Eighteen issues are open on `sh1ny/blackgrid`. None is assigned to a milestone: the roadmap mentions #48 only in M4's Done line, as a learning. Each issue was re-checked on 2026-10-30 against `main` at `6df0b17`. Since M4 closed, no commit has touched the scanner, capture or vision code; later work was map, UI and docs.

Verdict rules come from the M4.6 exit criteria in `openspec/roadmap.md`:
- **close:** the issue no longer applies;
- **defer:** it still applies but is too minor or too unlikely to matter before 1.0;
- **fix now:** anything else.

The user agreed every verdict below on 2026-10-30, accepting the proposal as written: "leave everything as is, i have other plans for next."

### Verdicts

| # | Verdict | Current evidence | Reason posted on the issue |
|---|---|---|---|
| 30 | close | `windows/vision/vision.cpp:153,190` reject a flat template; `:160` rejects a non-finite best score; `:199` skips non-finite peaks. Encoding drops are counted and tested (`lib/data/scan_timing_log.dart:171-177`, `test/data/scan_timing_log_test.dart:200`) | Not reachable: native vision rejects non-finite scores before they reach the log, and an encoding drop is already counted and tested. Reopen if a non-finite field ever appears. |
| 17 | fix now | `openspec/specs/release-versioning/spec.md:74` requires a PR title and number on every entry, but the direct-commit scenario (`:84-86`) has no PR. There is no first-release scenario, although `tool/changelog.dart:175-177` already handles one. The spec also predates `pr.merge_method: squash` | Spec-only fix in `fix-changelog-spec`: PR entries vs direct-commit entries, a first-release scenario, and squash-merged PRs. |
| 48 | defer | Band `lib/data/capture/capture_geometry.dart:84-90` unchanged since M4; no "filter by item" chrome entry (`lib/domain/title_matching.dart:269-280`) | Results are correct and M4's latency targets pass. A real fix needs recorded stash frames, which agents cannot capture. |
| 52 | defer | `_readable` ignores the result of `readSync(1)` (`lib/application/item_icon_cache.dart:297-308`). `byteSize` is already stored (`:526`) | Cosmetic, and only damage from outside Blackgrid causes it. The fix is to compare the stored `byteSize`. |
| 55 | defer | No link check on `compiled/` itself when there are no outputs (`tool/markers/compile.dart:128-147`) | Developer tool, and the junction has to be set up by hand. The fix is `unsafeOutputReason` on `compiled/`. |
| 10 | defer | Create at `lib/application/output_path_guard.dart:106`, then reopen at `:107`. Link checks run again first (`:99-100`) | Needs write access to a folder the user chose, plus winning a tiny race. |
| 16 | defer | `tool/release/src/push_identity.dart:41-49` reads URLs without `--all` | Needs push URLs added by hand to the developer's own Git config. Revisit when M6 reworks releases. |
| 19 | defer | `lib/data/capture/input_trigger_source.dart:161-176` | The only subscriber, `ScanCoordinator`, never disposes from `onData`, and it cancels its subscription before disposing. |
| 20 | defer | `lib/data/capture/capture_service.dart:147-150` | Nothing blocks on `workerExit` of a service that never captured. The coordinator's watcher is a no-op once its activation is stale. |
| 21 | defer | `lib/data/capture/input_trigger_source.dart:89-106` | The coordinator cannot call `start` after `dispose`: its stale-activation and `_disposed` guards prevent it. |
| 23 | defer | `lib/data/vision/vision_service.dart:343,664` | Needs the registry factory to fail in the UI isolate after the capture service has already opened the same registry there. |
| 24 | defer | `lib/data/vision/vision_scratch.dart:49-54`, `vision_worker.dart:261` | Only when a 16 MiB allocation fails right after a larger block was freed, which is an out-of-memory condition. |
| 25 | defer | `openspec/specs/vision-worker/spec.md:121-145`; the behaviour is in `vision_service.dart:453-469,625-649` | Behaviour is correct; only a spec scenario and a test are missing. Add them in the next vision-worker spec change. |
| 28 | defer | `lib/ui/scan_evidence_panel.dart:477-482` | Only while the catalog reloads after a mode change, and the panel corrects itself once it loads. |
| 29 | defer | `lib/application/scan_coordinator.dart:2027-2049` does not await `_runningMatch` | At most one diagnostic line lost per exit. |
| 33 | defer | `scan_coordinator.dart:2865-2871`, `3020-3024` | Opt-in recorder only, when the window moves mid-scan. The corpus parser already rejects the case loudly. |
| 34 | defer | `scan_coordinator.dart:2399-2400`, `2900-2902` | Opt-in recorder only. The memory is held only during one slow match and freed afterwards. |
| 38 | defer | `lib/application/recognition_matcher.dart:54-58` drops the reason | Never seen, and results are unchanged. The fix changes two specs for a diagnosis-only gain. |

## Decisions

### D1: The sweep ends with one fix change, `fix-changelog-spec`, for #17

- **Choice:** The M4.6 Changes list gets one fix change, `fix-changelog-spec`, which closes #17. All other issues are deferred or closed now.
- **Rejected:** Bundling the cheap deferred fixes (#19, #20, #21, #52, #55) into an "M4.6 hardening" change. It lost because the user chose to keep scope as proposed, and none of them is reachable or matters before 1.0.
- **Reversal cost:** low. A deferred issue stays open with its label and can be pulled into any later milestone.

### D2: Mark deferred issues with a `post-1.0` label and a comment, and leave them open

- **Choice:** Create the `post-1.0` label if missing, apply it, and post the reason. Issues stay open.
- **Rejected:** Closing deferred issues as `wontfix`. It lost because they still apply and should be visible after 1.0; closing them hides real defects.
- **Reversal cost:** low. Labels and comments are reversible.

### D3: Write verdicts to GitHub as `KintsugiBot`, only after the user has agreed them

- **Choice:** All comments, labels and the close are posted as `KintsugiBot` through the fenced `gh` credential, per the user's account rules. Nothing goes to GitHub before the user has agreed the verdict.
- **Rejected:** Posting as `sh1ny`. It lost because the user's rules reserve `sh1ny` for review requests and explicitly owner-scoped actions.
- **Reversal cost:** low.
