# Review

## Metadata

- **Round:** 1 (re-check)
- **Prior round:** Round 1 returned APPROVE_WITH_CHANGES with CHANGES_APPLIED: no. It raised C1 (the reconnect rule was not idempotent under replay once a later raid was stored) and M1 (the single `error` field let a reload or a mode change erase the write and clear failure messages). S1 (construction and disposal order) and S2 (dialog with an unknown mode) were suggestions.
- **Reviewer:** fresh-context subagent (Claude Code). Project skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis, flutter-add-widget-test.
- **Reviewed:** openspec/changes/add-local-stats/review.md (round 1 and the author's Rebuttals), openspec/changes/add-local-stats/specs/local-stats/spec.md, openspec/changes/add-local-stats/design.md. This re-check covers only Required Changes 1 and 2.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Critical (blocking)

**C1 (round 1). The reconnect rule was not idempotent under replay: a skipped reconnect was counted on a later replay once any newer raid was stored.** Resolved.

Round 1 found this:
- D5 and the spec compared a reconnect against "the newest stored raid of the same mode, by start time".
- A skipped reconnect leaves no row, so a replay after a later raid (for example Woods at 21:00) was stored compared the 20:25 Customs reconnect against Woods and counted it.
- The cause in the code: after a replay or a `LogInputReset` the reducer starts from `RaidLifecycleState.initial`, so the rejoin is published as `RaidEntry.reconnect` under its own record identity.

Re-check: fixed with option (a).
- **Spec.** Local-stats spec line 29 now compares only against "the newest stored raid of the same mode that started strictly before it". It adds: "Raids stored with a later start SHALL NOT affect the decision, so a replay decides the same way."
- **Scenario.** "Replay of a skipped reconnect after a later raid" (spec lines 47-49) matches Required Change 1 word for word: Customs keeps 1, Woods 1.
- **Design D5** (line 54) states the strictly-before comparison and explains why a replay repeats the original decision. It names both test layers: the `countsReconnect` domain test, and a database ledger test for the replay-after-a-later-raid case.
- **Rejected alternative.** D5 line 55 records option (b), the "not counted" row, as rejected, with a reason.
- **Diagram and gaps.** The sequence diagram (line 84) reads "newest raid of mode starting before it". Flow & State Gaps (line 139) repeats the rule.

I traced the round-1 sequence against the new rule. On replay, the newest PvP raid that started strictly before 20:25 is still Customs at 20:00, so the reconnect is skipped again.

I also traced it with a clear between the raids, at 20:10:
- The clear deletes the 20:00 raid.
- The 20:25 reconnect is after the watermark and finds no earlier row, so it counts.
- A live run and a replay decide the same way, so the rule stays deterministic.

### Moderate

**M1 (round 1). One `error` field had rules that conflicted, so the write-failure message the spec requires could disappear before anyone saw it.** Resolved.

Re-check: fixed.

The spec requirement "Stats failures are visible and contained" (line 142) gives each failure its own message and clearing rule:
- read: until the next successful read;
- write: until the next successful write;
- clear: until the next successful clear or the dialog closes.

It also states: "One kind's success SHALL NOT remove another kind's message."

The new scenarios cover the failure mode round 1 found:
- "Write message survives a reload" (152-154);
- "Write message clears on the next write" (156-158);
- "Clear message survives a reload" (160-162).

"Read fails" (144-146) and "Clear fails" (103-105) remain.

The design's State & Ownership table (lines 107-109) replaces `error` with `readError`, `writeError` and `clearError`. Each states its sole writer and the exact event that clears it:
- `writeError` "reloads never touch it";
- `clearError` is cleared by `dismissClearError()` when the dialog closes, which matches the spec's "or the dialog closes".

The Failure & Visibility table names the same three messages.

### Suggestions

**S1 (round 1, construction and disposal order).** Taken. D4 (line 48) builds the controller in the `AppServices` constructor beside `RaidTimersController`, before the reader binds. It is disposed before the database closes.

**S2 (round 1, unknown mode).** Taken. Spec scenario "Mode not known yet" (118-120) and the Flow & State Gaps line 138.

**S3 (new, wording only). D6 still says the dialog listens to `(totals, since, error)`** (design line 60). After the M1 fix, the controller has no single `error`, so an implementer reading D6 alone could rebuild the one-field shape that M1 removed. During apply, read D6 as listening to `readError`, `writeError` and `clearError` (State & Ownership, lines 107-109), and call `dismissClearError()` on close. This does not block: the State & Ownership table and the spec already decide the behaviour, and Required Change 2 named those tables. Fixing the word in D6 would be a new design edit, which voids this verdict unless the change is re-reviewed. So carry the correction into the implementation and its tests rather than editing design.md now.

**S4 (new, optional test coverage).** No scenario checks that a read failure's message survives a successful write, or that a failed clear's message goes when the dialog closes. Both behaviours are stated in the requirement text on line 142. Cover them in the controller's unit tests (service layer, per AGENTS.md) next to the three new scenarios.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **C1 (design D5, local-stats spec "A reconnect continuing a counted raid does not count again"):** make the reconnect decision deterministic across replays. Either:
   - (a) compare only against the newest stored raid of the same mode whose start time is strictly before the candidate's; or
   - (b) store a skipped reconnect as a row under its record identity, flagged as not counted and excluded from totals, so that insert-or-ignore makes a replay a no-op.

   Update D5 and the sequence diagram to match.

   Add the scenario "Replay of a skipped reconnect after a later raid": WHEN a PvP Customs raid at 20:00 is stored, a reconnect on Customs at 20:25 is skipped, a PvP Woods raid at 21:00 is stored, and the folder is replayed, THEN Customs keeps 1 raid and Woods 1.

   Cover it in the domain test of `countsReconnect` (option a) or in the database ledger test (option b).

   **Re-check: applied (option a).** Spec line 29, scenario at lines 47-49, design D5 at lines 54-55, sequence diagram at line 84, and Flow & State Gaps at line 139.

2. **M1 (design State & Ownership and Failure tables):** replace the single `error` with separate read, write and clear failure states, or with one explicitly ordered rule. Each must state exactly what clears it:
   - read: the next successful read;
   - write: the next successful write;
   - clear: the next successful clear, or closing the dialog.

   A successful reload must not erase the write or clear message. Add a spec scenario for each case: a write fails, then the next reload succeeds, and the dialog still shows "Some raids or sales could not be saved."

   **Re-check: applied.** Spec requirement at line 142, with scenarios at lines 152-162. Design State & Ownership at lines 107-109.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

- **C1:** fixed with option (a). Spec requirement "A reconnect continuing a counted raid does not count again" now compares only against the newest stored raid of the same mode that started strictly before the reconnect, and adds the scenario "Replay of a skipped reconnect after a later raid". Design D5 and the sequence diagram are updated; the case is covered by the `countsReconnect` domain test and a database ledger test. **Accepted by reviewer:** verified at spec lines 29 and 47-49, and design lines 54-55, 84 and 139.
- **M1:** fixed. Spec requirement "Stats failures are visible and contained" gives read, write and clear failures their own messages and clearing rules, with the scenarios "Write message survives a reload", "Write message clears on the next write" and "Clear message survives a reload". The design's State & Ownership table replaces `error` with `readError`, `writeError` and `clearError`. **Accepted by reviewer:** verified at spec lines 142-162 and design lines 107-109. The leftover `error` in D6 is wording only (S3).
- **S1 (construction order):** taken. D4 says `AppServices` builds the controller before the reader binds and disposes it before the database closes. **Accepted by reviewer** (design line 48).
- **S2 (unknown mode):** taken. Spec scenario "Mode not known yet" and a Flow & State Gaps line. **Accepted by reviewer** (spec lines 118-120, design line 138).
