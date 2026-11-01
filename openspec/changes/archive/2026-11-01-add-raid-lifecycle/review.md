# Review

## Metadata

- **Round:** 2
- **Prior round:** Round 1 VERDICT: REVISE. C1 (replay order changed raid endings), C2 (three file statuses folded into the Map's log state), M1 (transit rule too broad), M2 (client restart split one raid), M3 (unspecified ending paths from queue, match found and raid starting), S1-S5.
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** openspec/changes/add-raid-lifecycle/proposal.md, design.md (TIER: FULL), specs/game-log-input/spec.md, specs/raid-lifecycle/spec.md, review.md (round 1); openspec/roadmap.md (M7), openspec/architecture.md (Game inputs, components, Resource bounds), openspec/specs/map-rail/spec.md, AGENTS.md, docs/adr/0002-sdk-notifiers-and-composition-root.md; lib/data/session_log_reader.dart, lib/application/map_session_controller.dart, lib/application/app_services.dart, lib/domain/map_session.dart, lib/ui/map_screen.dart, test/data/session_log_reader_test.dart (test list). Plain read-only file reads in D:/Battlestate Games/EFT/Logs: the lifecycle lines around every `Transit reconnect` in the 2026-10 folders; a scan of all folders for a `Transit reconnect` before the folder's first `GameStarted`; the last lifecycle event and the last `userMatchOver` of each folder from 2026-10-10 to 2026-11-01; the type 10/11/12 counts and empty `templateId`s in the 1.3.0 push logs. Skills loaded: dart-use-pattern-matching, dart-add-unit-test, dart-write-documentation, flutter-add-widget-test. The "Dart and Flutter code" section of AGENTS.md was read.
- **Required Changes re-check:** fresh-context subagent (Claude Code specwright-reviewer), 2026-11-01. Re-read the current specs/raid-lifecycle/spec.md and design.md against Required Changes 1-3 and S1. A read-only grep of the 2026-10-15 application log confirmed the `Transit reconnect status:MatchWait ... location:laboratory` lines at 23:15:30.103 and 23:40:36.658 in folder `log_2026.10.15_20-50-43_1.2.0.0.47965`, which started at 20:50:43, so the corrected D6 citation is accurate. No skills were named for the re-check, so none were loaded.

Round-1 findings, re-checked:
- **C1: resolved.** D3 reduces each scan's events in (log time, file rank, offset) order, and bind-time replay is one such scan. The spec requirement "Events read together are reduced in log-time order" has a replay scenario taken from the real 22:09:04 / 22:17:49 case, and "Re-read after restart" now asserts identity, time and cause for raid-ended. The remaining per-poll gap is stated as a known limit, with its own scenario.
- **C2: resolved.** D7 keeps `SessionLogState.status`, `incarnation`, map, mode and message on the application log alone. Backend and push problems go to `raidLogsMessage` and a separate "Raid logs:" line. The new requirement "Backend and push-notification problems never change the Map's log state" has scenarios for a missing push log, a rejected push record and a backend rewrite. This matches `_waitingForLogContext` and `_onLog` (`map_session_controller.dart:82-85,244-266`).
- **M1: resolved.** D6 now requires no queue entered or aborted since the last raid ended, and the spec has the "Queue between the raid and the rejoin" scenario. The logs agree: every mid-folder `Transit reconnect` from 2026-10-06 to 2026-10-24 (19 cases) follows `userMatchOver`, then one `PrepareSelectedProfileLocally` 2-3 s before it, with no queue between.
- **M2: partly resolved.** D8 decides that a restart continues the raid, and there are spec scenarios for it. The new rule has a visible gap, see M1 below.
- **M3: resolved.** The diagram has the ending edges from in queue, match found and raid starting. The spec has "A queue that ends without a raid is aborted", with a "Back to menus while loading" scenario.
- **S1-S5: resolved.** The wording is now assertable ("SHALL NOT end or change any raid and SHALL publish no transition"). The event presets are in scope. The audit's files and banned list are in the Mechanism Ledger. The line citations match the current source (`:94`, `:173`, `:213`, `:244`, `:264`, `:307-313`, `:402`; `app_services.dart:88,377`; `map_session_controller.dart:24,30,82,124,153`). D4 states the constructor subscription and the disposal order.

## Findings

### Critical (blocking)

None.

### Moderate

**M1. D8 keeps an interrupted raid "in raid" while the player is in the menus, and the restart-and-reconnect sequence it is built for does not appear anywhere in the user's logs.**
- **The phase is wrong after a restart without a rejoin.** The spec says that when a new folder is read during a raid, "its phase SHALL stay", and the new folder's profile selected "SHALL NOT end an interrupted raid". Only a later rejoin or queue entered moves it on. After a crash in raid where the player does not reconnect, the "Raid:" line reads "in raid on <map>" for as long as the player stays in the menus, the hideout or the flea market. `add-raid-timers` would also see a running raid. That fails the user-verified M7 check ("the raid state … follow[s] the game"). The scenario "Restart without reconnecting" asserts only the end at queue time, not the phase in between.
- **The design contradicts itself.** Flow & State Gaps says that after a crash in raid "the phase stays in raid until a new folder appears (D8)". D8 and the spec keep it in raid after the new folder appears.
- **The evidence is missing.** No folder in the user's whole log history has a `Transit reconnect` before its first `GameStarted`. From 2026-10-10 to 2026-11-01, no folder ends in a raid without a later `userMatchOver`. The two folders whose last application event is `GameStarted` (2026-10-19 21:36, 2026-10-29 18:26) both log the raid exit afterwards. So the sequence D8's continuation depends on ("session mode, profile selected, rejoin, raid started" in the new folder) has never been observed. The same goes for D6's rejection claim that the logs show "both `Busy` and `MatchWait` at the start of a new folder". Fixtures for D8 would encode an assumed format. The "client restart" end cause would then be stored by `add-local-stats`, a reversal the design itself rates medium.

### Suggestions

**S1.** The spec's "Rewritten bytes" scenario restarts the application tail from offset 0, but the design does not say what the reducer does then. D7 resets only that file's tail for backend and push, and the State table resets the reducer only on `LogInputReset` (log-root rebind). If only the application tail restarts mid-session, its old queue, profile-select and raid-started events reach a reducer that already holds later state. The backend tail is not re-read, so replayed raids end "from the menus" with application identities instead of their earlier raid-exit identities. That is the C1 inconsistency through another path. The fix is one line in D7/State & Ownership: an application restart emits `LogInputReset` and restarts all three tails, so the folder replays as one scan, as at bind.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **design.md D8 and specs/raid-lifecycle/spec.md, requirement "A client restart during a raid continues that raid":**
   - The new folder's profile selected sets the phase to in menus. The raid stays open as interrupted, and no raid-ended transition is published.
   - A rejoin that follows continues the same raid, as now.
   - A queue entered first ends it with cause client restart at that profile-select time, as now.
   - Add to the "Restart without reconnecting" scenario's THEN: "after the profile selected and before the queue entered, the phase is in menus".
   - In the state diagram, replace `inRaid --> inRaid: folder changed (...)` with an interrupted raid going to `inMenus` on the new folder's profile selected. Keep the rejoin and queue edges from that state.
2. **design.md Flow & State Gaps, "Game crashed or closed in raid" bullet:** say that the phase stays in raid until the new folder's profile selected, then shows in menus with the raid interrupted.
3. **design.md Risks:**
   - Add a risk: no folder in the user's logs has a raid rejoin before its first raid start, so the line a restart-reconnect writes is unverified. D8's rejoin handling rests on assumed fixtures until the user observes one.
   - In D6's rejection, remove or correct the claim that the logs show `Busy` and `MatchWait` "at the start of a new folder".

CHANGES_APPLIED: yes

## Rebuttals

- **M1 (round 2): fixed.** Required change 1: spec "A client restart during a raid continues that raid" now sets the phase to in menus on the new folder's profile selected without ending the raid or publishing; the "Restart without reconnecting" THEN asserts the in-menus phase before the queue; design D8 says the same, and the state diagram has `inRaid --> interrupted --> inMenus` with the rejoin and queue edges kept. Required change 2: Flow & State Gaps "Game crashed or closed in raid" now says the phase stays in raid until the new folder's profile select, then shows in menus with the raid interrupted. Required change 3: Risks gains "[The restart-and-reconnect line is unverified]", and D6's rejection now cites `MatchWait` for a rejoin later in a folder (2026-10-15 23:15:30) instead of "at the start of a new folder".
  - **Accepted by reviewer.**
    - RC1: spec.md:103-112 sets the phase to in menus on the new folder's profile selected without ending the raid or publishing. The rejoin and queue rules are unchanged. The "Restart without reconnecting" THEN now asserts in menus with no transition before the queue, then the end at 23:15:20 with cause client restart. D8 (design.md:76) matches. The diagram (design.md:121-124) replaces the self-loop with `inRaid --> interrupted --> inMenus` and keeps the rejoin edge and the queue (client restart) edge.
    - RC2: design.md:179 is fixed as required.
    - RC3: design.md:206 adds the unverified-line risk. D6 (design.md:65) now cites a real mid-folder `MatchWait` rejoin. The re-check confirmed that line in the user's 2026-10-15 log (23:15:30.103, folder started 20:50:43).
    - Non-blocking note: the diagram draws `interrupted` as a state, but the spec's phase list (spec.md:10) and D4 treat interrupted as a flag on the raid, not an eighth phase. An implementer should read the node as "in raid with the interrupted flag set", not add a `RaidPhase` value. Also, "The first ending of a raid wins" (spec.md:55) says the next profile selected ends the current raid. The client-restart requirement is the specific exception for a new folder's profile selected. Reducer tests should cover that precedence explicitly.
- **S1 (round 2): fixed.** Flow & State Gaps gains "Only the application log is replaced or rewritten": all three tails restart, `LogInputReset` is emitted and the folder is replayed in one scan, as at startup.
  - **Accepted by reviewer.** design.md:182 states the full restart and replay. The State & Ownership row for `RaidLifecycleState` (design.md:149) still names only log-root rebind as the reset trigger. That row is optional to update, because the Flow & State Gaps bullet is unambiguous.
