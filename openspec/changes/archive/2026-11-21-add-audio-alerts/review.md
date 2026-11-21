# Review

## Metadata

- **Round:** FULL tier re-check after a behaviour-change spec amendment (commit 9eeecb9 "amend specs", implemented in 16d23e6).
- **Prior rounds:** Round 1 and its two re-checks left APPROVE_WITH_CHANGES; M1 to M5, N1 and N2 were applied and verified, and S1 to S4 were optional. This round covers only the four owner-approved behaviour changes and whether they contradict the rest of the change or the main specs.
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:** openspec/changes/add-audio-alerts/{proposal.md, design.md, review.md}, specs/{audio-alerts, raid-lifecycle, game-log-input}/spec.md; main specs openspec/specs/raid-lifecycle/spec.md and openspec/specs/game-log-input/spec.md. Source on feat/add-audio-alerts: lib/domain/raid_lifecycle.dart (`reduce`, `_queueEntered`, `_serverJoined`, `_sceneLoaded`, `_raidRejoined`, `_raidStarted`, `_guessSide`), lib/data/game_log/game_log_parsers.dart, lib/application/alerts_controller.dart (`_onTransition`, `_deadlines`, `_plan`, `_speaksNow`), and the test diff of 16d23e6. `openspec validate add-audio-alerts --strict` passes.
- **Skills:** the Dart skills named in AGENTS.md were not loaded. This round reviews spec coherence and reads code as evidence only; no Dart was written.
- **Decided, not re-litigated:** (1) match found on the first server-joined line after matching completed in a queue; (2) "Raid starting" on raid started for a queued raid with no countdown; (3) run-through over only for guessed side PMC and not entered by reconnect; (4) scav ready dropped when it comes due in raid.

## Findings

### Critical (blocking)

None.

### Moderate

**A1. Two audio-alerts scenarios now contradict the server-joined rule, because "match found" means two different things.**
- The game-log-input delta still calls the `MatchingCompleted` record a "match found" event. The new raid-lifecycle requirement "A match is found once the raid's server is joined" says that event alone publishes no match-found transition.
- The audio-alerts scenario "Cancelled match" uses "match found" in the event sense: queue entered, match found and matching aborted, so no alert plays.
- Two scenarios in the same requirement use the same words for events but only work if "match found" means the transition:
  - "A queue to a raid": WHEN queue entered, match found, raid starting and raid started are read live, THEN "Match found" plays once. No server joined is listed, so under the new rule no match-found transition is published and "Match found" would not play.
  - "Raid with no countdown": WHEN queue entered and match found are followed directly by raid started, THEN "Match found" plays, then "Raid starting". Same problem.
- The code and tests agree with the transition reading. The test helper `FakeAlertLifecycle.matchFound` feeds `MatchFound` and then `ServerJoined` (test/support/alerts_support.dart), and `_serverJoined` publishes only on the joined record. Read literally, the two scenarios describe behaviour the code correctly does not have. Someone who writes a test from the spec text would expect a transition that the reducer never publishes.
- **Fix:** add "server joined" after "match found" in both scenarios, the way the raid-lifecycle "Queue to raid" scenario was updated. An alternative is to rename the event "matching completed" in the game-log-input delta and in the raid-lifecycle "Cancelled match" scenario, so "match found" means only the transition. See S4.

**A2. It is unclear whether a raid continued after a client restart counts as "entered by a reconnect", and the design's edge case contradicts itself.**
- **Spec.** The run-through requirement excludes a raid "that was entered by a reconnect". The main raid-lifecycle spec uses "reconnect" for two situations:
  - "Rejoining a raid is a transit or a reconnect" calls any rejoin that is not a transit a reconnect. That includes the rejoin of an interrupted raid.
  - "Reconnect keeps the side" describes a PMC raid "interrupted by a client restart and continued by a reconnect".
- **Design.** Flow & State Gaps "Reconnect" says: "the raid keeps its identity and start. A raid entered by a reconnect has no run-through over alert, since its start time is the rejoin, not the raid's own start." The first sentence describes the continued raid, whose start is the original start. The second gives a reason that is true only for a new raid with entry reconnect, whose `startTime` is the rejoin record (`_raidStarted` uses `pendingStart`). The two sentences point opposite ways for the continued raid.
- **Code.** The interrupted branch of `_raidRejoined`, followed by `_raidStarted`'s `current.interrupted` branch, keeps the same `Raid` with `entry: queue` and its side. So `_deadlines` keeps the run-through deadline for a continued PMC raid, and "Run-through over" still plays at the original start plus the length. A raid with `entry == reconnect` gets `RaidSide.unknown` from `_guessSide`, so the `raid.entry != RaidEntry.reconnect` clause never changes the result (see S2).
- **Consequence.** A reader of the spec or the design could expect silence after a client restart and rejoin while Blackgrid runs, but the code plays the alert. The owner's in-play check then cannot tell whether that is a bug.
- **Options:**
  - **A (recommended):** "Entered by a reconnect" means the raid's recorded entry is reconnect. A raid continued after a client restart keeps its queue entry, its start and its alert. Rewrite the design line along those lines: the continued raid keeps its identity, start and run-through alert; a raid that Blackgrid first sees through a reconnect starts at the rejoin, so it has no run-through alert. Add a spec scenario: WHEN a PMC raid is interrupted by a client restart and continued by a rejoin while Blackgrid runs, THEN run-through over still plays once, 7:10 after the raid's original start. This matches the code and the design's own reason (the start time is accurate).
  - **B:** Also silence the continued raid. That needs a code change, such as a resumed flag on `Raid`, and it drops an alert whose timing is correct.

**A3. The proposal no longer matches the change.**
- Capabilities, Modified: the list names `raid-lifecycle` and `settings-page`. The change now carries a `game-log-input` delta (new server joined event, modified "A full raid" scenario), which archive will sync into the main spec.
- What Changes still says run-through over fires "when the countdown reaches 0:00 during a raid" and scav ready "when the active mode's scav cooldown reaches ready". Neither mentions the PMC/not-reconnect restriction or the mid-raid drop. Match found is not said to wait for the server join. The release notes say the same and will mislead scav players who expect a run-through alert.
- Impact `lib/data/` names only the audio adapter, not the parser change in `game_log_parsers.dart`.
- **Fix:** add `game-log-input` to Modified Capabilities. In What Changes and the release notes, state the PMC-only and no-mid-raid conditions and the server-join trigger. Add the parser to Impact.

### Suggestions

**S1. D6 should say which record a match-found transition carries.** D6 says each new transition carries "the event's record identity and time". For match found, that record is now the server joined record, not the matching-completed record. Its Rejected paragraph also refers to "match found followed by raid starting". One clause in D6 would keep the de-duplication and re-read reasoning exact.

**S2. The reconnect clause in `_deadlines` changes nothing, and its test passes without it.** `_guessSide` returns `unknown` for every `RaidEntry.reconnect` raid, so `raid.side == RaidSide.pmc` already excludes those raids. The test "a reconnected raid has no run-through alert" (alerts_controller_timers_test.dart) feeds a reconnect with side unknown, so it passes because of the side check alone. This is harmless as a defence, but the test does not prove the reconnect rule. Say so in a comment, or drop the claim that the test covers it.

**S3. Name the side in the run-through scenarios.** "Countdown reaches zero", "Raid ends first" and "Already over at startup" say only "a raid is current". Now that the rule is PMC-only, "a PMC raid" would make each scenario state its preconditions. The run-through tests already use a PMC `startRaid` by default.

**S4. Consider renaming the `MatchingCompleted` event in the specs.** The game-log-input delta's event list and its "A full raid" scenario, the raid-lifecycle "Cancelled match" and "Second server joined" scenarios, and the main "Raid phases" requirement all call the record "match found", while the transition of the same name now means something else. Renaming the event "matching completed" in the deltas, and noting that it still sets the match found phase, would remove the cause of A1 everywhere. The Dart class `MatchFound` already has a doc comment that explains this.

**S5. Scav ready phase test.** "Ready during a raid" is covered by "a cooldown that ends mid-raid plays nothing". The requirement also implies that a cooldown coming due while the phase is raid starting or match found still plays. A one-line case would pin down that `_speaksNow` tests only `inRaid`.

**No contradiction found in:**
- The main "Raid phases" requirement. Server joined changes no phase, and match found still sets the match found phase.
- The main "No countdown" side scenario. A queued raid with no countdown is scav, and it now gets "Raid starting" at its start, as decision 2 intends.
- The transit edge case. A transit raid takes the side of the raid it left, so a PMC transit gets a new run-through count.
- The "Rejoined raid" scenario. `_onTransition` fires raid starting on raid started only for `entry == queue` with no `raidStartingTime`.
- Map-known gating. It still uses `pendingEntry == queue`, as does `_serverJoined`.
- Scav ready "then or later". `_plan` marks the deadline seen even when `_speaksNow` refuses it, so it does not play at the raid's end.

## Verdict

The four behaviour changes are coded as decided and the strict validation passes. A1 and A2 are spec and design wording that a test author or the owner's in-play check would read differently from the code. A3 is stale proposal text. None of them needs a code change under the recommended options.

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1 to M5, N1, N2) Applied and verified in earlier rounds; unchanged by this amendment.
2. (A1) In audio-alerts "A queue to a raid" and "Raid with no countdown", list server joined after match found (or rename the event per S4), so that the scenarios agree with "A match is found once the raid's server is joined".
3. (A2) Settle what "entered by a reconnect" means for a raid continued after a client restart. Recommended: option A. Rewrite the design's "Reconnect" edge case and add a run-through scenario for a continued PMC raid.
4. (A3) Add `game-log-input` to the proposal's Modified Capabilities. Update What Changes, the release notes and Impact for the server-join trigger, the PMC-only run-through and the mid-raid scav drop.

CHANGES_APPLIED: yes

## Rebuttals
