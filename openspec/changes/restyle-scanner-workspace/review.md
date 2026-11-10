# Review

## Metadata

- **Round:** 3
- **Prior round:** Round 2 REVISE: 2 Critical (settings-diagnostics and scan-decisions unlisted although Sources, needs and card panels are removed; the card's scan age and provenance dropped) and 1 Moderate (the X14 rows dropped the activity source that player-facing-text's "Imported scan in history" needs), plus suggestions S-a to S-f
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:**
  - The change: openspec/changes/restyle-scanner-workspace/proposal.md, design.md and review.md (round 2), and the round 1 record. Every delta under specs/: scanner-workspace, workspace-shell, verdict-presentation, scanner-evidence, catalog-authority, player-facing-text, item-icons, scan-decisions, scan-correction, latest-accepted-scan, settings-diagnostics and settings-page. Each was compared with its openspec/specs/<cap>/spec.md.
  - Main specs grepped for leftover references to the decision card, the Sources, Requirements and Inspection details panels, the inspector and subtitles: requirement-rows, settings-page (Item and map data, Tracker progress), workspace-shell (Status actions) and scanner-evidence (all requirements).
  - Design context: DESIGN.md X10, X11 and X14. The B view in .impeccable/preview/ember-directions.html: ITEMS (`how`), strip(), scannerMain(), scannerInspector(), histRowsB() and toolsB().
  - Source, read at HEAD: lib/ui/answer_strip.dart, lib/ui/shell.dart (accordion flags at :65-67, status bar at :295-383), lib/ui/item_decision_card.dart (subtitle at :58-75, `_trailing`, `_scanAge`, `_correctionAge`), lib/ui/evidence_panels.dart (SourcePanel at :299-339, HistoryPanel at :470-590), lib/ui/settings/settings_page.dart (Item data row at :432-470, Tracker status line at :553-560, `_tokenAction` at :153-176), lib/ui/labels.dart, lib/ui/requirement_rows.dart, lib/domain/verdict_reason.dart, lib/domain/settings.dart (`ActivitySource`) and lib/application/selection_controller.dart (`historyRow` getter, the 30 s tick).
  - `openspec validate restyle-scanner-workspace --strict` was run and passes.
  - Skills loaded: none were named in the request.
  - Test map: not applicable, because tasks.md does not exist yet.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Round 2 status

- **C1: resolved.**
  - A settings-diagnostics delta now keeps catalog and Tracker errors reachable through the status bar's status words, which lead to the Settings sections. The code supports this: `status-item-data` and `status-tracker` open `SettingsSection.itemData` and `SettingsSection.tracker` (shell.dart). Both scenarios no longer depend on the removed accordions, and the new scenario "Tracker error stays reachable" was added.
  - D13's "Tracker problem: <error>" in error ink matches the words of SourcePanel (`evidence_panels.dart:334-338`). It replaces the tertiary-ink `progress.error` line (`settings_page.dart:553-560`).
  - The new wording sits within settings-page's in-force "Item and map data section" ("A failed refresh SHALL show its failure in plain words in this section") and "Tracker progress section" ("the progress status").
  - The scan-decisions delta names the answer strip and the Why and Prices sections. Both capabilities are listed under Modified Capabilities.
- **C2: resolved.**
  - D3 and D12 put a provenance line in the who block, and the workspace-shell requirement states it, with the scenarios "Provenance line" and "Provenance age moves on".
  - scan-decisions ("its provenance line SHALL say how long ago it was scanned"), scan-correction (Picking), latest-accepted-scan (RENAMED, "provenance line gives the age of its original acceptance time") and settings-diagnostics ("Corrected scan subtitle") all name the strip.
  - Every fact the line needs is reachable today: `AcceptedScan.acceptedAt`, `ScanCorrection.correctedAt`, `selection.historyRow` (public, with `observedAt` and `mode`) and `selection.clock`.
  - The line fits D9: a 19px title plus one Label line is shorter than the 48px icon.
- **M1: resolved.** The workspace-shell "History rows show item pictures" requirement adds an "Imported scan" Label tag, with the scenario "Imported scan row" (D13). player-facing-text's "Imported scan in history" scenario ("the row says 'Imported scan'") still holds, so leaving "Shown states" unmodified is sound for that scenario. One leftover in the same requirement is noted in the Suggestions below (S-a).
- **Suggestions from round 2:** all addressed.
  - S-a: Risks now says `Expanded` with no `Spacer`.
  - S-b: D6 makes the caption inline, after the control.
  - S-c: the "Found in raid" label is named in D3 and the spec.
  - S-d: item-icons is RENAMED and "same generic fallback as the answer strip" is fixed. The remaining scenario titles are recorded in Risks.
  - S-e: the player-facing-text sentence is split.
  - S-f: the scenario now says "content edge, after its padding".
  - The T2 citation `shell.dart:65-67` is now correct.
- **Sweep check:** after the RENAMEs, every requirement body in scan-decisions, scan-correction, latest-accepted-scan, item-icons, verdict-presentation and scanner-evidence names the strip or the sections. The unmodified requirements of these capabilities (scan-correction "offer lists the scan's best candidates", "recorded as manual activity" and "Same-name candidates"; verdict-presentation "Price on the Flea and Trader plates"; the other item-icons requirements) do not name the card.

### Critical (blocking)

None.

### Moderate

None.

### Suggestions

- **S-a. One "decision card" scenario body is left in an unmodified requirement.**
  - Where: player-facing-text "Shown states use plain-language labels", scenario "Unknown found-in-raid state": "**WHEN** the decision card shows an item whose found-in-raid state is unknown **THEN** the card says found in raid is unknown in words, and no card text contains `FIR: unknown`".
  - Why it matters: the card is deleted (D4), and `decision_card_text_test.dart` is listed in Risks as moving. The requirement's normative text still holds for the strip, which shows the "Found in raid" label with the Unknown segment and the Check reason. Only the scenario's subject is stale.
  - Unlike the scenario titles in the Risks entry, this is a WHEN/THEN body, which a MODIFIED block can reword.
  - Fix: treat it as a spec clarification when the test moves (naming the answer strip), or add it to the Risks entry's later spec cleanup. It does not change behaviour.
- **S-b. The design's T3 tables still describe a single list-owned tick.** D12 adds a shared age-tick widget that the strip also mounts, so the strip ticks on both areas even with the inspector closed. Four places still describe only the list:
  - the State & Ownership row "Age tick | Recent items list state";
  - the Resource Bounds row "One per mounted list";
  - the T3 sequence diagram, which shows only the Recent items list;
  - the Flow & State Gaps line "Inspector closed at narrow width: … no timer runs".

  Align them with D12 when the design is next touched (at most two timers, each cancelled in `dispose`). This changes no behaviour.
- **S-c. D3 does not place the strip's actions.**
  - Today the close-history `IconButton` and "Back to latest scan" `TextButton` follow the price column in the wide `Row` (`answer_strip.dart`, `parts.skip(5)`).
  - D3 makes the price block `flex: none` "at the right end", and the "Price block with both prices" scenario pins it at the strip's right end. The actions must stay reachable (workspace-shell "Selection semantics", latest-accepted-scan).
  - Say where they go, for example after the price block or under the who block, so that apply does not have to choose against a geometry test. A 40px `TextButton` fits D9's 100px either way.
- **S-d. The manual-selection provenance differs from the B view.** D12 says it follows the B view's `it.how` form. Two of its strings differ from the mockup:
  - a manual pick reads "Chosen by hand" with no age, where the mockup has "Picked by search · just now";
  - a history inspection reads "Current advice · saved …", where the mockup has "History · …".

  Both choices keep wording that in-force specs use, and they have reasons. Record them in D12 as deliberate departures, so that the owner's sign-off against the B view (the `[user]` task) checks them knowingly.
- **S-e. X14 in DESIGN.md does not mention the row tags.** D11 and D13 add mode and "Imported scan" Label tags to the 38px row. The X11 update is already a task; add the tags to X14 in the same edit, so that the design system and the spec agree.

## Verdict

VERDICT: APPROVE

## Required Changes

<!-- APPROVE_WITH_CHANGES only: numbered exact edits. -->

CHANGES_APPLIED: n/a

## Rebuttals
