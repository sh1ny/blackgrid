# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** openspec/changes/add-screenshot-cleanup/proposal.md, specs/screenshot-cleanup/spec.md, specs/settings-page/spec.md (against openspec/specs/settings-page/spec.md), design.md; openspec/architecture.md, openspec/roadmap.md (M10), STRATEGY.md, AGENTS.md, docs/adr/0030-game-log-input.md, docs/adr/0046-local-progress-is-the-only-progress-authority.md, docs/adr/0047-alerts-speak-through-a-runner-audio-channel.md; source lib/application/raid_lifecycle_controller.dart, lib/domain/raid_lifecycle.dart, lib/domain/alert_rules.dart, lib/application/alerts_controller.dart, lib/application/map_session_controller.dart, lib/data/screenshot_directory_watcher.dart, lib/domain/screenshot_filename.dart, lib/data/game_paths.dart, lib/domain/settings.dart, lib/application/settings_controller.dart, lib/application/app_services.dart, lib/data/channel_audio_port.dart, windows/runner/audio_channel.h, windows/runner/audio_channel.cpp, windows/runner/flutter_window.cpp; openspec/specs/raid-lifecycle/spec.md. Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis, flutter-add-widget-test.
- **Re-check run:** this is the re-check run of the round 1 Required Changes (M1, M2) only, after the author's edits. It re-read proposal.md (S2), design.md (Flow & State Gaps, D2 "Cancel and lifetime", D8, Resource Bounds, Failure & Visibility, State & Ownership, the recycle-call sequence diagram, the Mechanism Ledger, the Decision summary, Open Questions), specs/screenshot-cleanup/spec.md (the "Only a fresh raid ending starts a cleanup" requirement and its crash scenario, the two recycle-call scenarios, "Blackgrid closes during a cleanup"), and as evidence lib/domain/raid_lifecycle.dart (`_selectProfile`, `_endRaid`, `_queueEntered`, lines 867-997), lib/application/raid_lifecycle_controller.dart (publishing order, line 44), windows/runner/audio_channel.cpp (`Shared`, generation check) and docs/adr/0047-alerts-speak-through-a-runner-audio-channel.md. No new full review was run. M1 option (b) was chosen by the owner ("Clean them"), recorded as `Chosen by: user`.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. A raid ended by a client restart is usually stale when published, so it is never cleaned, and the design says the opposite.**
Flow & State Gaps said: "A raid ended by a client restart carries the restart's time and is fresh when it is read live." The reducer shows otherwise. `_selectProfile` (lib/domain/raid_lifecycle.dart, around line 916) only records `restartProfile` and ends nothing. The ending is published later, from `_queueEntered` (around lines 970-980), at the next queue entry, carrying `restart.time`, the profile-selection time. If more than 30 s pass between the profile selection and the next queue, `isFreshLogTime(transition.time, now)` (lib/domain/alert_rules.dart:19) returns false and the crashed raid's screenshots are never cleaned, with no result line.
Fix: either (a) accept it as a trade-off with a matching scenario, or (b) after the user's decision, judge freshness for `RaidEndCause.clientRestart` by the publishing record and add a scenario that proves a crash raid is cleaned.

**Re-check: applied correctly (option b, chosen by the user).**
- Flow & State Gaps now describes the real path: `_selectProfile` only records `restartProfile`, `_queueEntered` publishes the ending at the next queue entry with the profile-selection time, followed in the same reduction by the `QueueEnteredTransition`. This matches the code: `_queueEntered` returns `[...transitions, QueueEnteredTransition(e.id, e.time)]` (raid_lifecycle.dart:995), `_endRaid` publishes exactly one `RaidEndedTransition` (:887), and the controller adds a batch's transitions in order (raid_lifecycle_controller.dart:44). `clientRestart` is produced only in `_queueEntered` (:976), so the "held ending, judged by the next queue entry" rule in D8 always has its queue entry.
- D8 records the choice, the rejected arrival-clock option (with the correct reason: the start-up replay also arrives "now") and the rejected accept-the-gap option, `Chosen by: user`, and keeps `raid.endTime` as the window end.
- S2 in proposal.md and its summary row state the crash rule; the D8 summary row is added.
- The spec requirement states the rule, and the new scenario (menus 14:40:00, queue 14:45:00, clock 14:45:01, cleanup starts) is assertable with a fake clock. The existing replay scenario keeps a replayed crash raid stale, because its queue entry is old.

**M2. The Dart backstop has no runner-side cancel, so after a timeout the result line can be wrong and later calls hit `busy`. Closing the app has no defined stop point.**
A 60 s backstop for 256 names with no runner cancel let the worker keep recycling after Dart gave up, made the "still in the folder" result line false, sent later batches into `busy`, and left the close path without a stop flag or a defined worker lifetime.
Fix: runner `cancel` with an atomic stop flag in worker-shared state checked before each file; the worker never references the channel object; defined `OnDestroy` behaviour; backstop and dispose call the cancel; after a backstop, no further batch and "not confirmed" reporting (or wait for the late reply); a backstop sized to the batch; matching Resource Bounds, Failure & Visibility and sequence diagram; a spec scenario for a failing or silent recycle call; closing wording to match.

**Re-check: applied correctly.**
- D2 "Cancel and lifetime" adds `recycle` and `cancel`, a `std::shared_ptr<Shared>` holding the `HWND`, a call generation and `std::atomic<bool> stop`, checked before each file, with skipped files reported as `cancelled`. The worker never references `RecycleChannel`. `~RecycleChannel` (from `OnDestroy`) sets `stop`, completes the pending result and detaches the worker; a stale post is ignored by generation. This follows `audio_channel.cpp` (`Shared` at :55, the generation check at :414).
- The window message is named `kRecycleChannelMessage = WM_APP + 2`, distinct from `kAudioChannelMessage` (also closes S4's first half).
- Resource Bounds: batches of 64, sent one after another; backstop of 10 s plus 1 s per name (74 s per full batch); after a backstop the controller calls `cancel` and waits up to 30 s for the late reply before its next call, else marks the port unavailable for the run, so the runner's `busy` is never hit. This follows ADR-0047's "When a backstop expires, Dart calls `stop`".
- Failure & Visibility: the backstop row ends the raid's cleanup with no further batch and reports "could not be confirmed as moved"; the destroyed-mid-call row names the stop flag and the detached worker that finishes at most its current file.
- The sequence diagram shows the 64-name cap, the per-file stop check, the `cancelled` status and the `cancel` path. The Mechanism Ledger row and Open Questions match the new constants.
- Spec: "The recycle call fails" and "The recycle call does not answer" scenarios are added under "Screenshots go to the Recycle Bin, never deleted for good"; "Blackgrid closes during a cleanup" now says the move stops before its next file.

### Suggestions

S1-S5 from round 1 stand as written and are not re-checked here (S4's window-message half is now covered by D2). Three small consistency points came in with the M2 edits; none blocks:

**S6. Name the per-call reset of `stop`.** `Shared` holds one `stop` flag. D2 should say each `recycle` call clears it (or that the flag lives per call, next to the generation). Otherwise, after one backstop and its late reply, every later call would report all its names as `cancelled`. A controller- or qualification-level test of "backstop, late reply, next raid cleans" would catch it.

**S7. One status for a destroyed call.** D2 completes a pending result with `cancelled` on destruction. The State & Ownership row "Pending recycle call" still says "by destruction (`failed`)", and the state diagram labels the backstop exit "result: failed" while the Failure table and spec say "could not be confirmed as moved". Align them on `cancelled` and "not confirmed".

**S8. Put the "not confirmed" count in the result requirement.** The "The last cleanup's result is shown" requirement lists moved, could-not-be-moved and no-screenshots lines. The new "does not answer" scenario adds a "could not be confirmed as moved" line, and the run-unavailable case in Resource Bounds adds another. Add both to that requirement's SHALL so the UI task has one list to build from.

## Verdict

Both Required Changes are applied correctly. M1 was resolved with option (b), and that option is recorded as the owner's decision (D8, S2, `Chosen by: user`). M2's cancel, lifetime, bounds and scenarios match the ADR-0047 pattern and the runner code. No Critical finding is open. S6-S8 are non-blocking consistency notes.

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1) In design.md, replace the Flow & State Gaps sentence with an accurate account of the client-restart ending, and either (a) accept the gap with a Risks entry and a spec scenario, or (b) after asking the user, judge `clientRestart` freshness by the publishing record, update S2, the D-entries and the summary table, and add a scenario that proves a crash raid is cleaned. **Applied (b), re-checked: correct.**
2. (M2) In design.md, add a runner `cancel` with an atomic stop flag in worker-shared state checked before each file. State that the worker never references `RecycleChannel`, and state the `OnDestroy` join or detach behaviour. Make the backstop and dispose cancel the call. After a backstop, end that cleanup, report the names as not confirmed or wait for the late reply, and size the backstop to the batch. Update Resource Bounds, Failure & Visibility and the sequence diagram. In the spec, add a scenario for a recycle call that fails or does not answer, and update "Blackgrid closes during a cleanup". **Applied, re-checked: correct.**

CHANGES_APPLIED: yes

## Rebuttals

- M1: fixed (design.md Flow & State Gaps, D8, Decision summary; proposal.md S2; spec "A raid ended by a client restart"). Re-checked by reviewer.
- M2: fixed (design.md D2 "Cancel and lifetime", Resource Bounds, Failure & Visibility, sequence diagram, Mechanism Ledger, Open Questions; spec "The recycle call fails", "The recycle call does not answer", "Blackgrid closes during a cleanup"). Re-checked by reviewer.
