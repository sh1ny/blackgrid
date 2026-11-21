# Review

## Metadata

- **Round:** 1 (second re-check of the Required Changes)
- **Prior round:** The first re-check found M1 to M5 applied and verified. It left APPROVE_WITH_CHANGES with two new Required Changes open: N1, the file playback timeout had no channel contract, and N2, map-known was published for a scene after a rejoin. CHANGES_APPLIED was `no`.
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:** openspec/changes/add-audio-alerts/{design.md, specs/raid-lifecycle/spec.md, specs/audio-alerts/spec.md, review.md}. Source: lib/domain/raid_lifecycle.dart (`reduce`, `_isLoading`, `_folderChanged`, `_endRaid`, `_abortQueue`, `_selectProfile`, `_queueEntered`, `_sceneLoaded`, `_raidRejoined`, `_raidStarted`).
- Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis, flutter-add-widget-test (all loaded).

This re-check covers only N1 and N2, the folded-in N3, N4 and the D11 scope note, and whether those edits introduced a new contradiction.

## Findings

### Critical (blocking)

None.

### Moderate

**Resolution of the open Required Changes**

- **N1: resolved.** The runner now owns the file timeout. design.md D1 ("File timeout (review N1)") says:
  - After `MediaPlayer` opens the file, the runner arms a timer for `NaturalDuration` plus 5 s, capped at 120 s, or 30 s when the length is unknown.
  - When the timer expires, the runner stops playback and completes with `timeout`.
  - Dart keeps a backstop of 125 s for `playFile` and 30 s for `speak`. The length never crosses the channel, so Dart needs no duration.
  - The single-pending-result rule lists `timeout` among its exactly-once completions.
  - The two tables now agree with D1. Resource Bounds "Playback queue" reads "15 s waiting; playing: 30 s speech, runner file timeout up to 120 s, Dart backstop 125 s". The "Custom sound file" row reads "Runner: length plus 5 s, at most 120 s (30 s unknown); Dart backstop 125 s".
  - Failure & Visibility "Channel call never completes" names the same backstops. A new row, "File plays past its timeout", covers the runner's `timeout`.
  - There is no contradiction left among D1, Failure & Visibility and Resource Bounds.
- **N2: resolved.**
  - **Spec.** The raid-lifecycle requirement now limits map-known to scene loaded events "read while the phase is in queue, match found or raid starting, after a queue entered and before any raid rejoined since". It adds the scenario "Scene after a rejoin": WHEN a raid rejoined event for a transit is followed by a scene loaded event while the phase is raid starting, THEN no map-known transition is published.
  - **Design.** Flow & State Gaps "Rejoin" now says that a scene loaded after a rejoin publishes no map-known either. Map-known is published only "while the pending entry is a queue".
  - **Code check.** `_queueEntered` sets `pendingEntry: RaidEntry.queue`. The non-interrupted branch of `_raidRejoined` sets it to `transit` or `reconnect`. `_raidStarted`, `_endRaid` and `_abortQueue` clear it. So on every normal trace (queue, a transit after `_raidExit`, a reconnect, a rejoin of an interrupted raid after a profile selection), the spec's predicate and the design's `pendingEntry == queue` give the same answer.
  - **One gap.** D6 itself still lists `MapKnownTransition(mapId?)` without the condition. The condition is stated once in the design, in Flow & State Gaps, and nothing contradicts it, so the required change is met. See S1 for the one trace where the two wordings differ.

**Folded-in suggestions**

- **N3: resolved.** D10 now says that after a client restart without a rejoin, the interrupted raid ends only when the next queue is entered. The reminder therefore plays after that next raid, back in the menus. D10 also says the tests and the owner's in-play check expect this timing. This matches `_queueEntered`: it ends an interrupted raid with `clientRestart` and sets `phase: RaidPhase.inQueue`. It also matches the spec scenario "Client restart mid-raid".
- **N4: resolved.** The Failure & Visibility row "File plays past its timeout" says the item is dropped and does not fall back to speech. D5 still falls back only on `file_missing` or `file_unplayable`. The two agree.
- **D11 scope note: applied.** ADR-0047 is now said to include D1's threading and completion contract.

**New contradictions introduced by the edits:** none found. The suggestions below are clarifications with no blocking consequence.

### Suggestions

**S1. Use one predicate for map-known in the spec and the design.**
- The spec says "after a queue entered and before any raid rejoined since". The design says "while the pending entry is a queue".
- The two differ on one trace. The log folder changes mid-raid, so `_folderChanged` marks the raid interrupted with `restartProfile: null`. If a queue entered arrives before any profile selection, `_queueEntered` does not end the raid (it requires `restart != null`) and sets `pendingEntry: queue`.
- If a raid rejoined event then arrives, the interrupted branch of `_raidRejoined` leaves `pendingEntry` unchanged.
- A scene loaded event after that publishes map-known under the design's rule and none under the spec's.
- The game normally selects a profile before it queues, so this order is unlikely. Still, stating the rule in D6 with the spec's wording, or as `pendingEntry == queue`, would remove the ambiguity for whoever writes the reducer and its tests.

**S2. List every completion code in one place in D1.** The paragraph after the contract still lists only `voice_missing`, `file_missing`, `file_unplayable` and `speech_failed`. `stopped`, `timeout` and `busy` appear only in the contract bullets above it. One complete list would keep the `ChannelAudioPort` mapping and the ADR text from missing one.

**S3. Settle in the spec whether a timeout counts as a file that "fails to play".**
- The audio-alerts requirement "Each alert plays speech or the player's sound file" says that when a chosen file "fails to play", the alert says its line instead.
- The design (N4) says that a file that hit its timeout did play, so there is no speech fallback.
- The design's reading is reasonable. A scenario such as "File longer than its timeout: THEN playback stops, no speech plays, and the playback failure line names the alert" would make the spec say so too.
- The same question applies to the Dart backstop row ("treats the item as failed"). One sentence would settle whether that falls back.

**S4. D11 wording.** "record ADR-0047, which includes D1's threading and completion contract, 'Alerts speak through a runner audio channel'" puts the title where it reads as the contract's name. Put the title right after the ADR number.

## Verdict

N1 and N2 are applied and verified against the design, the specs and `lib/domain/raid_lifecycle.dart`. N3, N4 and the D11 note are folded in consistently. M1 to M5 stay verified from the previous re-check. No Critical or Moderate finding remains open. S1 to S4 are optional clarifications.

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1) Applied and verified.
2. (M2) Applied and verified.
3. (M3) Applied and verified.
4. (M4) Applied and verified (Option A, user's choice).
5. (M5) Applied and verified.
6. (N1) Applied and verified: the runner enforces the file timeout with a `timeout` code, Dart backstops are 125 s for files and 30 s for speech, and the Resource Bounds cells match.
7. (N2) Applied and verified: the spec limits map-known to scenes after a queue entered with no rejoin since, the "Scene after a rejoin" scenario is added, and Flow & State Gaps agrees.

CHANGES_APPLIED: yes

## Rebuttals
