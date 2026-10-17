# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer). Skills loaded: dart-use-pattern-matching, dart-add-unit-test, dart-write-documentation, dart-run-static-analysis; AGENTS.md "Dart and Flutter code" section read.
- **Reviewed:** proposal.md, design.md, specs/inspection-capture, specs/inspection-recognition, specs/item-title-matching, specs/scan-frame-recording (deltas), the matching main specs plus scan-pipeline/spec.md, `git diff main -- openspec/specs` (Purpose line of inspection-recognition), openspec/roadmap.md (M4), openspec/architecture.md, ADRs 0010-0015; source: lib/data/capture/capture_geometry.dart, capture_policy.dart, lib/data/vision/inspection_recognition.dart, inspection_geometry.dart, inspection_evidence.dart, lib/domain/title_matching.dart (`rankOutcome`, `_outranks`), lib/application/scan_coordinator.dart (`_pickEntry`, `_winningPass`, `_fallsBackAfter*`, `_passLine`), lib/ui/scan_evidence_panel.dart (`_firstEntry`), test/qualification/support/inspection_corpus.dart, docs/qualification/m2/CORPUS.md, AGENTS.md. Evidence: both `frames.jsonl` files (70 lines), PNGs `20261017-130909-0019-full`, `-0003-targeted`, `-0006-targeted`, `20261014-122522-0024-full`, and `logs/scan-timings.jsonl` (226 lines). `openspec validate fix-targeted-scan-region --strict` passes. No game process was touched.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

I checked the spec arithmetic for every scenario and found no errors. The cases checked are 1920×1080, 2560×1440, 3440×1440, 3840×2160, 1920×1200, 1366×768 (s = 32/45), the negative origin, and the right-edge, top-left and off-screen clips. The claim that the band never leaves the client also holds: f(440) ≤ 0.23w, f(700) ≤ 0.37w and f(540) ≤ floor(h/2). The recorded geometry agrees with the band. In `-0024` the centred window spans x 1187-2253 with its marker at about x 1209, and the band's left edge is 1134. In `-0019` all four container markers lie in the band; THICC is at about x 1144. The ranking change in D3 is sound. "Best-ranked targeted entry accepted" holds exactly when "any targeted entry accepted", so the coordinator's fallback eligibility and its single-outcome handling are unaffected. `_pickEntry`, `_winningPass`, `_passLine` and the evidence panel's `_firstEntry` already handle any number of entries.

### Critical (blocking)

None.

### Moderate

**M1. The band does not start at the client top on clients taller than 16:9, although the proposal and D1 say it does.** The proposal says the band "runs from the top of the client to just below its vertical centre". D1 says it covers "every title height from the top of the client". The formula's top is `cy - f(540)`. That equals 0 only when the client is 16:9 or wider: s = h/1080 gives f(540) = floor(h/2) = cy. On taller clients s = w/1920, and the top moves down. The spec's own 1920×1200 scenario gives y = 60. At 1920×1440 (4:3) the band starts at y = 180. The tall-window case in D1 has a title close to the client top: `-0019` has its title at y ≈ 141 at s = 4/3, which is about 106 at s = 1. A tall window clamped to the client top on a 4:3 or 5:4 client would put its title above the band. Every such scan would then pay the fallback, which is the cost this change exists to remove. Starting the band at 0 costs little (1140×780 instead of 1140×600 at 1920×1440). It leaves every 16:9-or-wider scenario unchanged and matches the stated intent. The design lists non-16:9 behaviour as unverified assumption (a), but this gap is a mismatch between the formula and the stated intent, not an untested assumption.

**M2. The proposal and the design disagree on what ADR-0016 supersedes.** The proposal says ADR-0016 supersedes "ADR-0010's region formula only … and the part of ADR-0012 that has the targeted pass take a single best match". D6 and the ADRs section say ADR-0012 is not superseded, and they give `Supersedes: 0010` only. The ADR and the in-force index in `openspec/architecture.md` are written during apply. An implementer following the proposal would mark the 0012 row as partly superseded, and one following the design would not, so the permanent ADR record would depend on which file was read. D6 is correct: ADR-0012's decision bullets do not fix single-best targeted search, and its "8 kept inspections per full-client frame" bound still holds.

### Suggestions

**S1. The evidence figures in the proposal and design do not match the recorded data.** These figures will be copied into ADR-0016.
- The timing log shows 30 accepts on 2026-10-14, not 33, and 6 on 2026-10-17, not 7. The recordings also hold 30 and 6.
- The ledger's "0 of 40 recorded accepts" does not match either source: there are 36 recorded accepts and 49 accepts in the log.
- "The targeted pass has never accepted a scan" is contradicted by two targeted-pass accepts in the log on 2026-10-10 (13:40:27 "Grenade case", 13:40:36 "SVD 7.62x54R magazine"). Both came before the settle wait existed.

The conclusion still holds (2 of 49), but the figures should be corrected. Note also that "Grenade case" is a container's name accepted as an item, which supports D2/D3's concern about container titles.

**S2. The capture-size bound in the Resource Bounds table is wrong.** The table says `captureTooLarge` occurs only "over 13,800 px wide". The pixel cap (25,165,824) binds first: 684,000·s² exceeds it at s > 6.07, which is about 11,650 px wide at 16:9. The fallback already fails at 7680×4320, so this has no practical effect. Fix the number for accuracy.

**S3. D5 does not say what the replay does with `frames.jsonl` lines of kind `fullClient`.** ADR-0015 omits `cursor` on those lines, yet `planTargeted` needs a point for its in-client guard. D5 should say whether such lines are skipped (with a reason in the summary) or use the client centre. Otherwise the parser's behaviour is left to the implementer. All 70 current lines are `targeted`, so the gap only bites on future recordings.

**S4. The main inspection-capture spec keeps an old strip size.** Its "Blank captures are reported" scenario still says "a 650×50 region". The scenario stays true, but it is the last reference to the strip size in that spec. Updating it to 1140×600 is optional.

**S5. D4's settle evidence is thin.** The two strips show the window body drawn at 50 ms; `-0003` shows the item image. They do not show the title bar. The design already names the live-log signal that would reverse D4, so no change is required.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **(M1)** In `specs/inspection-capture/spec.md`, requirement "Targeted region is planned in physical client pixels", change the region to `(cx - f(440), 0, f(440) + f(700), cy + f(60))`. Change the "Client taller than 16:9" scenario's THEN to `(520, 0, 1140, 660)`. All other scenarios stay unchanged, because cy = f(540) whenever the client is 16:9 or wider. Update D1's formula and its band-inside-client argument in design.md to match (`cy + f(60) ≤ h`). Alternatively, keep the formula and correct the proposal and D1 wording ("from `cy - 540·s`", not "from the top of the client"), and add the clamped-tall-window-on-4:3 risk to the unverified assumptions and the Mechanism Ledger. Pick one.
2. **(M2)** In proposal.md, under What Changes, ADR-0016 bullet, remove "and the part of ADR-0012 that has the targeted pass take a single best match", so that it agrees with D6 (`Supersedes: 0010`, region formula only).
3. **(S1)** Correct the counts in proposal.md (Why), design.md (Mechanism Ledger "0 of 40") and wherever "never accepted" appears, to match the timing log: 30 of 30 fallback accepts on 2026-10-14, 6 of 6 on 2026-10-17, and 2 targeted-pass accepts on 2026-10-10 before the settle wait.

## Re-check of Required Changes (round 1, same reviewer)

I checked the current proposal.md, design.md and specs/inspection-capture/spec.md. `openspec validate fix-targeted-scan-region --strict` passes.

1. **(M1) Applied.** The spec region is now `(cx - f(440), 0, f(440) + f(700), cy + f(60))`. The 1920×1200 scenario is `(520, 0, 1140, 660)`. The other scenarios stay the same, and they still hold, because cy = f(540) on 16:9 and wider clients. D1 now states the formula and the bound `cy + f(60) ≤ h` (`f(60) ≤ h/18`), and explains why the band starts at the top.
2. **(M2) Not fully applied.** The ADR-0016 bullet under What Changes is fixed. However, proposal.md line 40 (Impact, **Docs:**) still says "the architecture's in-force ADR index (0010 and 0012 rows marked as partly superseded)". D6 says only the 0010 row notes the partial supersession, plus a new 0016 row. This is the contradiction M2 described, now in the Impact section: whoever edits `openspec/architecture.md` during apply still gets two different instructions. **Still needed:** change that parenthetical to "(0016 row added, 0010 row marked as partly superseded)".
3. **(S1) Applied.** The Why paragraph now gives 30 (2026-10-14), 6 of 6 (2026-10-17), and the two targeted-pass accepts on 2026-10-10 before the settle wait, including "Grenade case". D1 rejected (a) says "accepted nothing since the settle wait". The ledger gives "none of the 36 recorded accepts since the settle wait (30 + 6)". No "never accepted", "33", "7 of 7" or "0 of 40" remains.

The changes-applied flag stays `no` until the item 2 edit is made and re-checked.

Second re-check: item 2 is resolved. proposal.md line 40 now reads "(0016 row added, 0010 row marked as partly superseded)", proposal.md no longer mentions ADR-0012, and strict validation passes. All three Required Changes are applied.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

- **M1:** fixed (option 1). Spec region is now `(cx - f(440), 0, f(440) + f(700), cy + f(60))`, 1920×1200 scenario `(520, 0, 1140, 660)`; design D1 formula and the inside-client argument updated.
- **M2:** fixed. The proposal's ADR-0016 bullet no longer claims a partial supersession of ADR-0012.
- **S1:** fixed. Proposal Why and design D1 rejected (a) and Mechanism Ledger now give 30 (2026-10-14) and 6 (2026-10-17) fallback accepts since the settle wait, and the two pre-settle targeted accepts on 2026-10-10 (one a container, "Grenade case").
- **S2:** deferred, to keep this verdict's scope to the required changes. ADR-0016 (written during apply) will state the corrected bound (pixel cap binds first, about 11,650 px wide at 16:9).
- **S3:** handled in tasks: the replay parser skips `fullClient` lines and counts them in the summary with that reason.
- **S4:** handled in tasks: the main spec's blank-capture example is updated with the archive sync (a MODIFIED block here would only change an example).
- **S5:** acknowledged; the live check (user) covers the title bar timing, and D4 names the signal that would call for a longer settle.

Reviewer on the author's handling of the suggestions:
- **S2:** accepted. The fix is deferred to ADR-0016 with the corrected bound (about 11,650 px wide at 16:9). The number in the design table has no practical effect.
- **S3:** accepted, provided the tasks contain the explicit item: skip `fullClient` lines and count them in the replay summary with that reason.
- **S4:** accepted as optional. Archive sync applies only this change's delta blocks; it does not touch the unmodified "Blank captures are reported" requirement. So this needs an explicit task, or it can be left as is (the scenario stays true either way).
- **S5:** accepted.
