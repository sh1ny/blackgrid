# Review

## Metadata

- **Round:** 2
- **Prior round:** Round 1 APPROVE_WITH_CHANGES; its required changes were applied and re-checked.
- **Reviewer:** fresh-context subagent (omp)
- **Reviewed:** `openspec/changes/add-task-log-progress/{proposal,design,review,tasks}.md`; its `specs/{game-log-input,raid-lifecycle,settings-page,task-log-progress}/spec.md`; `.dart_tool/add-task-log-progress-{review-instructions,preship-findings}.json`; `AGENTS.md`; ADR-0030, ADR-0041 and ADR-0044; `openspec/architecture.md` ownership/boundary/resource sections; referenced reader, framing, parser, lifecycle, progress-store, wipe-store, event-mapping, controller, AppServices and Local progress Settings sources; referenced task reducer test source and controller test declarations. All four named installed skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test and dart-run-static-analysis. No referenced stores were reported by OpenSpec context.
- **Required-changes recheck:** `.dart_tool/add-task-log-progress-review-instructions.json`; the existing Round 2 `review.md`; amended `design.md`, `tasks.md` and all four change specs named above; ADR-0045; the ADR-0045 architecture index row; ADR-0030 and ADR-0044; referenced controller recovery source at `lib/application/task_log_progress_controller.dart:460-690`. OpenSpec list resolved the planning root to this checkout; OpenSpec context reported no referenced stores. The final M1-only recheck read the amended `design.md:95-96,210,235-236`.

The Reviewed entry preserves the original full Round 2 review's record, including its skill-loading record. These rechecks cover only that round's Required Changes C1/M1; they do not claim to repeat the full review or its skill loading. No installed project-skill paths were named for the rechecks. This is not a new review round. C1's accepted disposition is unchanged; the final recheck assessed only the remaining M1 wording.

This reviews the amended plan, not whether pending implementation corrections already conform. No files other than the requested scratch reviews were changed. No tests, builds, analysis, formatting or application/game interaction were performed.

## Findings

### Critical (blocking)

**C1. Timestamped mode history cannot resolve a preceding mode record that the scan has not read yet. — Addressed in the amended plan; accepted by reviewer.**

The original finding concerned application-first snapshots: a scan could include a task from its later push snapshot but omit the preceding mode change from its earlier application snapshot. Timestamped history alone could then irreversibly record that task in the wrong mode.

Design D3/D6 and Flow & State Gaps now require push-first/application-last snapshots and complete application consumption before task release. Failed, short or partial-line application reads defer live push consumption without advancing its position; one-shot reads report unreadable without partial tasks. The missing-application no-mode case remains explicit, and timestamped same-folder evidence is retained for delayed push recovery.

The `game-log-input` delta makes this an assertable requirement, with scenarios for live inter-snapshot appends, active-folder one-shot reading and incomplete application consumption. The task map has separate live and one-shot rows for both the ordering regression and incomplete-read behavior. D3 and ADR-0045 specify a shared snapshot helper with an injected stat seam, enabling deterministic offline regression tests without sleeps.

ADR-0045 and its architecture index row record the approved correction without rewriting accepted ADR-0030/0044. This satisfies prior Required Changes 1 and 2 at the design gate. The new red test-map rows are planned verification, not evidence of passing implementation tests. This disposition was accepted in the preceding required-changes recheck and is not reopened here. No Critical finding remains open.

### Moderate

**M1. Failure recovery still promises that catch-up resumes an earlier-date replay, although D8 correctly says it cannot. — Addressed in the amended plan; accepted by reviewer.**

Failure & Visibility separates catch-up from replay for transient append failure and app closure. Replay failures expose the original selected date as `retryFrom`; app closure requires another explicit replay. The Settings delta requires a standing closure warning and the original selected retry date for interrupted or failed replay. The task-progress delta and task map include the November 11 watermark / October 20 replay / failure-before-October-21 regression. ADR-0045 consistently records explicit recovery from the original selected date.

The preceding recheck left two contradictory design statements outstanding. Both are now corrected:

- D8 at `design.md:95-96` explicitly exposes the replay's original selected date as `retryFrom` and directs the player to replay from that date. The last stored folder is supplemental progress information only. D8 explains that catch-up cannot resume older work below an existing watermark, and preserves the rejection of hidden pause/resume state.
- The Folders per run row at `design.md:210` limits later catch-up continuation to catch-up itself and requires an interrupted replay to be requested again from its original selected date.

The associated mechanism-ledger wording at `design.md:235-236` is consistent: raid-stopped replay can be requested again from the original date; catch-up recovers from its watermark, while failed replay exposes its original retry date. These amendments remove the remaining conflicting instructions and satisfy M1's original-date recovery policy. No Moderate finding remains open.

### Suggestions

None. The prior round's other findings and dispositions are unchanged; these scoped rechecks make no new full-review assessment.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

All Round 2 Required Changes have been applied to the plan and rechecked by the reviewer. The conditional verdict is now satisfied; there are no remaining required changes. This is design approval, not implementation verification.

## Required Changes

1. **C1 — Complete the attribution contract: satisfied.** Design D3/D6, Flow & State Gaps, the `game-log-input` requirement and ADR-0045 require push-first/application-last snapshots, complete application consumption before task release, live deferral without stale-mode fallback, and unreadable one-shot results without partial tasks. The approved ADR-0045 approach records the correction without editing accepted ADRs.
2. **C1 — Add the missing regression contract and map: satisfied.** The input delta and task map cover live and active-folder one-shot inter-snapshot appends and failed/incomplete application consumption, using the shared helper and injected stat seam specified in the design and ADR-0045. Timestamped same-folder evidence remains in place.
3. **M1 — State and expose manual replay recovery consistently: satisfied.** Failure/closure recovery is split by run kind; interrupted or failed replay identifies its original selected retry date; Settings has the standing closure warning; the specified older-replay failure scenario and offline test-map row are present; ADR-0045 records the policy. The final recheck confirms that D8 and the resource-bound row no longer prescribe a last-folder retry date or promise catch-up resumes earlier replay. The related mechanism-ledger text is consistent.

CHANGES_APPLIED: yes

## Rebuttals

- The previous round's four required changes retain their recorded disposition. Pre-ship F2's in-queue start boundary and F3's captured-frontier watermark rule were not reopened by these scoped rechecks. D3's timestamped evidence remains the approved mechanism for F1's delayed-push example.
- **C1 / prior Required Changes 1–2: fixed in the amended plan; accepted by reviewer.** Evidence: design D3/D6 and Flow & State Gaps; the complete-application-snapshot requirement and its three scenarios; four corresponding live/one-shot test-map rows; ADR-0045 and its architecture index row. The user's approved ADR-0045 approach satisfies the recording requirement without modifying accepted ADRs. This accepted disposition is unchanged.
- **M1 / prior Required Change 3: fixed in the amended plan; accepted by reviewer.** The split failure rows, original-date failure result, standing Settings warning, offline failure scenario and test map, and ADR-0045 recovery policy were accepted in the preceding recheck. The final recheck confirms the remaining corrections at `design.md:95-96,210,235-236`: interrupted replay is explicitly retried from its original selected date, and later catch-up continuation is not promised for earlier replay. No rebuttal or required change remains outstanding.
