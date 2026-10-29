# Review

## Metadata

- **Round:** 4
- **Prior rounds:** 1 (APPROVE_WITH_CHANGES, M1-M4, re-check CHANGES_APPLIED: yes), 2 (APPROVE_WITH_CHANGES, M5-M6, re-check CHANGES_APPLIED: yes) and 3 (APPROVE_WITH_CHANGES, M7-M8, re-check CHANGES_APPLIED: yes). Their findings and rebuttals are kept below as history.
- **Trigger:** a behaviour-change spec amendment from the pre-ship review (finding F1, P1; user decision, 2026-10-29). `lib/application/progress_controller.dart:72` already says "Tracker token unavailable", and `test/application/app_services_refresh_test.dart:593` asserts it. The main spec `progress-authority` still pinned "Protected credential unavailable". The amendment adds a MODIFIED delta `specs/progress-authority/spec.md` and a `progress-authority` entry under the proposal's Modified Capabilities.
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed (round 4):**
  - `git diff HEAD -- openspec/changes/plain-language-pass/`, which is the proposal.md hunk, and the untracked `specs/progress-authority/spec.md`.
  - The requirement "Selecting a known mode with a saved credential starts one progress refresh" in `openspec/specs/progress-authority/spec.md` (:10-40), diffed line by line against the delta.
  - The output of `openspec validate plain-language-pass --strict`.
  - Every string literal removed in `git diff main...HEAD -- lib` that is not re-added, each grepped against `openspec/specs/`.
  - `lib/application/progress_controller.dart:69-116` (branch diff) and `test/application/app_services_refresh_test.dart:585-594`.
  - proposal.md, design.md (:12, :83, :86, :92), tasks.md (6.1) and review.md (rounds 1-3).
- **Re-check run (round 4):** the current proposal.md (What Changes :14, Impact :32), design.md D7 note (:92), `specs/progress-authority/spec.md`, and the author's Round 4 rebuttals in review.md, via `git diff HEAD -- openspec/changes/plain-language-pass/`. I diffed the delta against the main requirement again and re-ran `openspec validate plain-language-pass --strict`.
- **Skills loaded:** none (the request names none beyond AGENTS.md, which I read).
- **Scope:** the amendment only. Earlier rounds' decisions are not reopened.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Round 4

Checked and clean, so no finding:
- **The delta copies the main requirement verbatim except for the one message.** A line diff of the requirement block against `openspec/specs/progress-authority/spec.md` covers the header, the normative paragraph and all seven scenarios: launch with a saved credential, no saved credential, unreadable credential, integration disabled, unknown mode, selection superseded, and saving does not refresh. It shows one changed line. Main :23 has `failed` with "Protected credential unavailable", and the delta :18 has `failed` with "Tracker token unavailable". The only other difference is the trailing blank line before the next main requirement. The requirement header matches exactly, so the MODIFIED delta replaces the right requirement at archive, and no scenario is dropped.
- **`openspec validate plain-language-pass --strict`** prints "Change 'plain-language-pass' is valid".
- **The delta matches the code and its test.** `progress_controller.dart:72` sets `error = 'Tracker token unavailable'` in the credential-read `catch`. `app_services_refresh_test.dart:593` asserts that string next to `trackerRequests == 0` and `ProgressStatus.failed`. The refresh rules (no request, status `failed`) are untouched, as the proposal entry says.
- **No other main spec pins a string this change rewords.** I took every quoted literal of 4 or more characters that the branch removes from `lib` and does not re-add, and dropped the interpolated ones. I then grepped `openspec/specs/` for each one of 6 or more characters. The only hit is `progress-authority/spec.md:23`, which this delta handles. The other progress-controller rewordings ("Credential prefix does not match selected mode", "Protected credential save failed" and the removal message) appear in no main spec. `catalog-authority` and `requirement-rows` keep their pinned strings, as rounds 1 and 3 established. Limit: this grep matches whole literals, so it would miss a spec that quotes only part of an interpolated message. Round 3's grep of the decision-engine strings covers the main case of that kind.
- **design.md is consistent.** D7's controller row (:86) already maps "Protected credential unavailable" to "Tracker token unavailable", so the design always planned this rewording. T6 (:12, "No credential, storage or decision path changes") still holds, because only the message text changes. D7's note (:92) names the strings that keep their wording because `catalog-authority` pins them. It does not claim those are the only pinned strings.
- **tasks.md needs no new task.** Task 6.1 already rewrote `progress_controller.dart` and the tests that pinned old text. The amendment changes only the spec, which it brings in line with code already on the branch.

#### Critical (blocking)

None.

#### Moderate

None.

#### Minor

**M9. The proposal's rule for spec-pinned messages now contradicts its own new Modified Capabilities entry.**
The What Changes bullet (proposal.md:12) still says: "Messages pinned by an existing spec (`catalog-authority`, `requirement-rows`) keep their wording." "Protected credential unavailable" is a message pinned by an existing spec (`progress-authority`), yet this change rewords it to "Tracker token unavailable". The new entry at :26 records that as a user decision, but the What Changes rule reads as covering every pinned message and gives no exception. Impact (:33) also says "No behaviour change in … `lib/application`", while the change now carries a behaviour-change delta for a message written there.

Consequence: the proposal states a rule and then breaks it. A later reader who checks this rewording against the What Changes rule may treat the delta as a mistake, or raise F1 again at the pre-ship re-review. The fix is one sentence.

#### Suggestions

- **S11.** In design.md's D7 note (:92), after the `catalog-authority` sentence, add that `progress_controller.dart:72`'s "Tracker token unavailable" rewords a message that `progress-authority` pinned, through the delta in `specs/progress-authority/spec.md` (user decision, 2026-10-29). The design would then name every spec-pinned string the change touches: the ones it keeps and the one it changes. This is optional, because D7's row (:86) already lists the new text.

### Round 3 (history)

Checked and clean, so no finding:
- **No reworded string is persisted, compared or used as a key.** `ItemDecision.warnings`, `NeedReason.message` and `NeedReason.detail` are read only in `lib/domain` and `lib/ui` (`item_decision_card.dart:284-295`, `requirement_rows.dart:90`, `evidence_panels.dart`). Nothing in `lib/data` or `lib/application` reads them, the timing log does not, and `ItemDecision` has no `==`. No control flow branches on the text. The m0 fixtures assert `decision.warnings` as the symbolic code `stale_progress`, not as engine text, so a reword is display-only.
- **No main spec pins a reworded string.** `requirement-rows` pins only `station module status unknown` (:136-137) and `optional use, not an automatic obligation` (:141). Both stay, as D7 says. Its "Unknown progress" scenario (:86-88) asserts the tag and state label, not the reason text. The other matches under `openspec/specs/` (`FIR unknown` in scan-decisions, latest-accepted-scan and scan-correction) describe the input state, not shown text. The only other occurrences are in archived changes and a 2026-10-06 plan, which are history.
- **Tests to update.** Only `test/domain/decision_engine_test.dart:59` (`'Instance FIR unknown'`) and `test/application/scan_decision_precedence_test.dart:235` (`'Progress authority missing or stale'`) pin reworded text. No widget test does. Task 7.3 names both.
- **ADR-0001 is respected.** The amendment changes only literals. Task 7.3 says "no state, rule or order change", and the engine's branch conditions do not read the text.
- **Scanning every literal of `decision_engine.dart` is sound.** The non-player literals are the import URIs (:1-4), `'RUB'` (:72), `'Any'` (:288), `'complete'`/`'failed'` (:321-335) and two interpolated module keys (:342, :352), whose `${…}` code is removed. None matches a banned stem. `'RUB'` alone does not match `gross RUB`. `authoritativeAt` is an identifier, not a literal. Every new string in the D7 row is free of banned terms. So is every reason that keeps its wording (`prerequisite, player, trader, skill or station gate unknown`, `actionable unmet need`, and the rest), so Check B passes once 7.3 is done, with no allow-list entry.
- **The rewordings match their conditions,** with the one exception below (M7). "Item data missing or out of date" covers `catalogKnown` false, including an item missing from the catalog. "Tracker progress or item data unknown" matches `p == null` (:158-162), which happens when either source is unknown. The three FIR reasons (:239-259) map one to one.

#### Critical (blocking)

None.

#### Moderate

**M7. "Flea price missing or older than one hour" misstates when the warning fires, and it can contradict the card.**
The warning (`decision_engine.dart:93-100`) depends only on the item's quote time (`item.quoteAt`, read from tarkov.dev's `lastScan` at `catalog_normalizer.dart:126`). It fires when that time is missing, in the future, or more than an hour old, and the flea is not ruled out. It does not check the flea price itself, `item.fleaPrice`.
- If `quoteAt` is missing and `fleaPrice` is present, the card shows "Flea price" with a value (`item_decision_card.dart:200-201`). The same card then warns "Flea price missing".
- If `quoteAt` is in the future (a clock or feed skew), the new text says the price is missing or old, and neither is true. The old text named this case ("future"). The new text drops it.
- The Data sources panel already speaks of this same timestamp as the price time ("Prices: price time unknown", `evidence_panels.dart:241-270`).

Consequence: the warning explains why the card says Check instead of Flea. In both cases above, it gives the player a false reason.

#### Minor

**M8. Task 7.3's keep-rule contradicts the D7 row it points to.**
Task 7.3 says "Reword … per the D7 decision row" and then "Strings with no banned term and the ones `requirement-rows` pins keep their wording." `FIR` is not a banned term (spec: `canonical`, `identity`, `durable`, `DPAPI`, `authority`, `authorized`, `normalized`, `M1`, `gross RUB`, `session-only`). So six of the ten strings in the D7 row contain no banned term: `Instance FIR unknown`, the flea eligibility warning, the market quote warning, and the three FIR reasons. Under the second sentence they keep their wording. Under the first they change. D7's own note is consistent, because it says "the decision engine's *other* reasons". Only the task is ambiguous.

Consequence: an implementer who follows 7.3 literally rewords four strings and leaves the FIR jargon that the amendment was raised to remove, and Check B cannot catch it because FIR is not banned. The two decision-card warnings would be the most visible leftovers.

#### Suggestions

- **S9.** D7 gives this reason for keeping the other reasons' wording: "since `requirement-rows` pins some of them". That holds for only two of them, `station module status unknown` and `optional use, not an automatic obligation`, and the second is never shown on a row anyway (spec :141). The rest are kept because they contain no banned term, but several still read as developer wording in the open view. `actionable unmet need` and `known future unmet need` appear next to the state labels "Needed now" and "Needed later". `prerequisite, player, trader, skill or station gate unknown`, `observed remainder unknown` and `task status invalid` are the others. This is a scope choice, and the user's read under the Risks entry "Wording is subjective" can adjust it without a spec change. Either state it as a scope choice in D7, or add these reasons to the D7 row. Neither is pinned by a spec.
- **S10.** Task 7.3 changes test expectations instead of adding a red step. That is fine for a text-only change, since Check B (7.4) protects the banned terms. To meet AGENTS.md's "cheapest layer", the updated assertions should stay in `decision_engine_test.dart`, which is the domain layer. They should also cover the two reworded warnings that no test pins today, the catalog warning and the flea eligibility warning, so a later accidental reword shows up there and not only in a widget test.

### Round 2 (history)

#### Critical (blocking)

None.

#### Moderate

**M5. As written, the `legacy_import.dart` scope misses import-dialog text that players see, including plan-row reasons.**
The amended D6 says Check B reads "only the literals of the plan rows' `reason:` arguments, which are what the import dialog shows." That description of the dialog is wrong in two ways:
- **Some reason text is not a literal argument.** Activity rows pass `reason: winner != i ? sourceReason : …` (`legacy_import.dart:345-346`). The three literals that reach the dialog by this route are assigned to the local `sourceReason` at `:330-334`, so they are not literals of a `reason:` argument. An extractor that follows the wording (the span of the `reason:` argument, like `_maskKeyArguments` spans) never reads them. These are plan-row reasons, which the spec scenario "Term check over the UI sources" covers by name ("the legacy import plan").
- **The dialog shows more of the plan row than `reason`.** `import_dialog.dart:167` shows `'${row.kind} #${row.inputOrder} • ${row.key} • ${row.disposition}'` in the open view. That covers the `kind:`, `key:` and `disposition:` literals of every `ImportAccounting(` call (`'supported preferences'`, `'destination conflict'`, `'source collision loser'`, `'add'`).
- **Error messages are also shown.** `import_dialog.dart:46-48` shows `'${failure.message} Nothing was changed.'` in red, outside any Details section. `_parseLegacyOffRender` rethrows every `FormatException` (`legacy_import.dart:363-364`), so all about 25 `FormatException(` messages in the file are open-view text (for example `:31`, `:128`, `:258`, `:275`, `:367`, `:410-452`). Before the amendment Check B covered them. Now it does not, and D6 wrongly calls them part of the parser text that is "never shown". The spec requirement "Developer wording stays out of the open view" covers all text outside a Details section.

Consequence: none of these strings contains a banned term today (checked). The gap is in regression protection. A later edit that writes, for example, `sourceReason = '… canonical item …'` or `FormatException('Unknown item identity')` passes Check B and reaches the player's open view. The check also misstates what it guards.

The fix keeps the user's decision. The input-format keys (`'normalizedX'`, `'normalizedY'`, `'CanonicalItemId'`) appear only as `root['…']`/`raw['…']` index operands, in `containsKey(`, `_alias(` and `_version(` arguments, and in the allowed-key lists at `:233-241` and `:296-301`. None of them falls inside an `ImportAccounting(` call, a `FormatException(` call or the `sourceReason` initializer. A scope built from those three regions therefore skips every wire key and covers every shown literal. That scope passes today without any rewording.

**M6. Removing whole `${…}` interpolations also removes player text nested inside them.**
D6 says "A `${…}` interpolation inside a literal is code, not text, so it is removed before matching." In this codebase, interpolations often hold string literals that are shown to the player:
- `map_screen.dart:100`: `'${state.followGameLogs ? (… ? 'Follow logs (manual fallback)' : 'Detected map') : 'Manual map'} · …'`
- `map_screen.dart:106` and `:109`: `'manual fallback'`, `'detected from logs'`, `'unavailable'`
- `import_dialog.dart:154` and `:180`: `'yes'`/`'no'`, `'nothing'`
- `live_scan_panel.dart:161`: `'unknown reason'`
- `item_decision_card.dart:211-212`: `'Unknown'`

If the whole `${…}` span is removed, any banned term written in such a nested literal passes Check B. For example, `'${fir ? 'Found in raid' : 'canonical state unknown'}'` would not be caught, although it is player text in the open view. That breaks the spec scenario's promise that "no string literal other than a widget key contains a listed term". The rule is right to treat identifiers and member chains as code: `${relevantProgress?.authorityVersion}` at `selection_controller.dart:402` is the hit that motivated it. The literals inside an interpolation are still text, though.

The current engine adds an implementation trap. `_literal` in `test/ui/support/plain_language_check.dart:30-32` is a non-nesting regex. On line 402 it ends the first literal at the inner `''`, so the `authorityVersion` interpolation lands in the next "literal" only by accident. Where a nested literal contains a quote character, code text can be read as a literal. A correct rule needs a small scanner that tracks `${` depth and quotes, not another regex pass.

#### Suggestions

- **S7.** A short-form interpolation `$name` (no braces) is code too. As written, the rule removes only `${…}`, so a future `'$authorityVersion'` would be a false positive. Remove `$identifier` alongside `${…}`. Leave raw strings (`r'…'`) and escaped `\$` alone, because in those `$` is literal text.
- **S8.** design.md Risks (:167) and Resource Bounds (:141) still describe Check B over "`lib/data/legacy_import.dart`" as a whole file. Once M5's scope is written into D6, make these two entries say "the import plan and error messages in `legacy_import.dart`" so the three places agree.

### Round 1 (history)

#### Critical (blocking)

None.

#### Moderate

**M1. Player-visible strings that live outside `lib/ui` break the new spec, and nothing in the design catches them.** The open-view strings in `lib/application` controllers and the `legacy_import.dart` plan-row reasons contained banned terms and ISO times, and Check B scanned only `lib/ui`. (Full text in round 1.)

**M2. Check A's regex misses most of the `.name` sites the design itself cites.** The leading-`.` pattern missed bare and destructured receivers (`${reason.name}`, `${pass.name}`, `catalogStatus.name`, `source.name`).

**M3. Check B as specified hits persisted data values; "fix by rewording" would break saved pins.** `pin_editor.dart:81` frame literals `'labs-native-normalized'` and `'legacy-normalized'`.

**M4. The proposal contradicts the spec and design on when Details collapses.**

#### Suggestions

- **S1.** Match word stems (`identit`, `authori[sz]`, `normali[sz]`, `durabl`).
- **S2.** Drop the `normalizedName` fallback subtitle.
- **S3.** Scope or explain dialog-scoped Details.
- **S4.** Assert map-rail status lines against the label function.
- **S5.** Keep time-label assertions clock-safe.
- **S6.** Cite ADR-0020 (timing log v3).


## Verdict

VERDICT: APPROVE_WITH_CHANGES

The amendment is correct. The delta copies the main requirement and all seven scenarios word for word and changes only the unreadable-credential message. The new message matches `progress_controller.dart:72` and its test, and strict validation passes. No other main spec pins a string the branch rewords. One wording fix remains: the proposal's rule that pinned messages keep their wording needs to name this deliberate exception (M9).

## Required Changes

1. **(M9)** In proposal.md What Changes (:12), replace "Messages pinned by an existing spec (`catalog-authority`, `requirement-rows`) keep their wording." with "Messages pinned by an existing spec (`catalog-authority`, `requirement-rows`) keep their wording. The exception is the unreadable-credential message that `progress-authority` pins, which becomes "Tracker token unavailable" through a spec delta (user decision, 2026-10-29)." In Impact (:33), qualify "No behaviour change in `lib/domain`, `lib/application` or `lib/data`" so it excludes that message, for example by adding "other than the `progress-authority` message above".

Re-check result: Required Change 1 (M9) and suggestion S11 are applied in the current artifacts, and the diff since HEAD contains no other edit to proposal.md or design.md. The delta is unchanged and strict validation still passes. Details are under each item in Rebuttals.

CHANGES_APPLIED: yes

## Rebuttals

### Round 4

- **M9:** fixed. What Changes now names the `progress-authority` unreadable-credential message as the one exception to the pinned-wording rule, with the user decision of 2026-10-29. Impact excludes that message from "No behaviour change in `lib/domain`, `lib/application` or `lib/data`".
  - **Accepted by reviewer.** Verified at proposal.md:14 and :32. The What Changes bullet keeps the `catalog-authority` and `requirement-rows` rule and names the `progress-authority` message, its new text, the spec delta and the user decision as the one exception. The wording matches Required Change 1. Impact now says "No behaviour change in `lib/domain`, `lib/application` or `lib/data` other than the `progress-authority` message above", which agrees with the Modified Capabilities entry at :26. The proposal no longer states a rule and then breaks it.
- **S11:** applied. The D7 note in design.md now names `progress_controller.dart:72`, the old and new text and the delta, so the design lists every spec-pinned string the change touches.
  - **Accepted by reviewer.** Verified at design.md:92. The note names `progress_controller.dart:72`, the old and new text, the delta file and the user decision. That agrees with D7's controller row (:86), the proposal and the delta. `specs/progress-authority/spec.md` is unchanged since round 4: it still differs from the main requirement only in the unreadable-credential message (plus the trailing blank line), and `openspec validate plain-language-pass --strict` reports the change valid.

### Round 3 (history)

- **M7:** fixed. The D7 decision row now rewords the market warning as "Flea price time unknown or more than an hour old", which matches the `quoteAt` condition (missing, in the future, or older than an hour) and no longer claims the price is missing.
  - **Accepted by reviewer.** Verified at design.md:90. This is one of the two options in Required Change 1. It no longer says the price is missing when the card shows one. A future timestamp falls under "time unknown", which is a fair way to tell the player about a time that can't be trusted. It contains no banned term.
- **M8:** fixed. Task 7.3 now says "Strings not in the D7 decision row keep their wording, including the ones `requirement-rows` pins", so every string in the row, including both FIR warnings, is reworded.
  - **Accepted by reviewer.** Verified at tasks.md:100. The keep-rule and the D7 row no longer conflict.
- **S9:** applied. The D7 decision row also rewords `not applicable to player`, `requirement progress or quantity unknown`, `observed remainder unknown`, `prerequisite, player, trader, skill or station gate unknown`, `known future unmet need` and `actionable unmet need`. The D7 note names the reasons that stay ("station module status unknown", "optional use, not an automatic obligation", "task completed", "quantity satisfied" and the like), which are already plain.
  - **Accepted by reviewer.** I checked each new wording against the condition that emits it, at design.md:90 and :92:
    - "does not apply to you" fits `_gate` returning irrelevant: a faction or edition mismatch, or a failed prerequisite task where completion was required (:166).
    - "progress or amount needed is unknown" fits a missing or invalid progress entry, or a missing, non-finite or negative required count (:219-224).
    - "how many you still need is unknown" fits an observed count that is missing or invalid (:230-233).
    - "not known yet whether you can do this (level, trader, skill or another requirement)" fits `_gate` returning unresolved. That covers an incomplete gate, an unknown trader or skill, an unknown faction, edition, level or task status, and a missing station module (:262-266). "Another requirement" covers the faction, edition, task and station cases.
    - "needed later" and "needed now" fit the future and actionable gates (:269-273).

    None contains a banned term. No test, main spec or `lib/` reader outside the engine pins the six old strings, so 7.3 has nothing more to update for them. The D7 note's reason has been corrected: `requirement-rows` pins only the first two. Two non-blocking notes for apply and the user's read:
    - "needed now" and "needed later" repeat the row's state label ("Needed now", "Needed later"). That is harmless, but a row then shows the same words twice.
    - The kept `task status invalid`, `task status unknown or invalid` and `task failed; no active obligation` fall under "and the like", although they are less plain than "task completed". The user's read can adjust them under Risks without a spec change.
- **S10:** applied. Task 7.3 keeps the updated assertions in the domain test and pins the catalog and flea-eligibility warnings there too.
  - **Accepted by reviewer.** Verified at tasks.md:100.

### Round 2 (history)

- **M5:** fixed. D6 now scopes Check B in `legacy_import.dart` to everything the import dialog shows: every literal inside an `ImportAccounting(` call (`kind:`, `key:`, `disposition:`, `reason:`), the `sourceReason` initializer literals and every `FormatException(` message. The "never shown" claim is gone, and the input-format keys (`normalizedX`, `normalizedY`, `CanonicalItemId`) stay unscanned. Task 7.3's parenthetical matches.
  - **Accepted by reviewer.** Verified at design.md:63 and tasks.md 7.3. The three regions match what `import_dialog.dart` shows: `:167` shows kind, key and disposition, `:171` shows the reason, and `:48` shows the failure message. They also include the `sourceReason` literals at `legacy_import.dart:330-334`. None of the input-format keys falls inside these regions: they appear only as index operands, in `containsKey(`/`_alias(`/`_version(` arguments and in the key lists at `:233-241` and `:296-301`. The scope therefore does not conflict with the user's decision. No literal in the three regions contains a banned term today, so 7.3 needs no rewording here.
- **M6:** fixed. D6 says interpolation code (`${…}` and `$name`) is removed before matching while string literals nested inside an interpolation are still extracted and matched, through a quote- and brace-aware scanner. The sample tests `'${a ? 'canonical item' : ''}'` (hit) and `'${p?.authorityVersion}:'` (no hit) are named in D6 and task 7.3.
  - **Accepted by reviewer.** Verified at design.md:63. Task 7.3 now also says to replace the non-nesting `_literal` regex in `test/ui/support/plain_language_check.dart` with that scanner and to add the samples. That covers the nested player text at `map_screen.dart:100,106,109`, `import_dialog.dart:154,180`, `live_scan_panel.dart:161` and `item_decision_card.dart:211-212`, and it still ignores `authorityVersion` at `selection_controller.dart:402`.
- **S7:** applied. The `$name` short form is covered by the same rule in D6.
  - **Accepted by reviewer.** Non-blocking note for apply: D6 does not say that raw strings (`r'...'`) and escaped `\$` keep their `$` text. The scanner should not strip there. A sample test such as `r'canonical ${x}'` (hit) would pin this down. No current source line depends on it.
- **S8:** applied. Resource Bounds and Risks now describe the `legacy_import.dart` regions.
  - **Accepted by reviewer.** Verified at design.md:141 and :167. Both now refer to the D6 regions.

### Round 1 (history)

- **M1:** fixed. proposal.md What Changes and Impact include the display strings in the `lib/application` controllers and `lib/data/legacy_import.dart` (text only). D6 Check B scans those files, D7 rewrites them, and Resource Bounds lists them. `catalog_controller.dart:68,124` keep their wording because `catalog-authority` pins them and they contain no banned term.
  - **Accepted by reviewer (round 1).** Two non-blocking stale phrases (design.md Risks and Failure & Visibility) were to be aligned with D6.
- **M2:** fixed. Check A uses `\b\w*(?:[sS]tatus|[sS]tate|[rR]eason|[cC]ode|[pP]ass|[fF]ir|[sS]ource)\??\.name\b` with Key arguments excluded, and the spec adds "A destructured regression" and "Keys are not text".
  - **Accepted by reviewer (round 1).**
- **M3:** fixed. `pin_editor.dart:81` uses `MapCoordinateFrame.*.wireName`, and persisted wire names are never reworded.
  - **Accepted by reviewer (round 1).**
- **M4:** fixed. The proposal's Details bullet matches the spec.
  - **Accepted by reviewer (round 1).**
- **S1, S2, S3, S5, S6:** applied in round 1.
