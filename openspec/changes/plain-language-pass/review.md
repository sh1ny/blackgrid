# Review

## Metadata

- **Round:** 1
- **Prior round:** none. This file is the re-check run of round 1 (APPROVE_WITH_CHANGES, 4 Required Changes, CHANGES_APPLIED: no). It covers only Required Changes 1-4.
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:** Original round: openspec/changes/plain-language-pass/proposal.md, design.md, specs/player-facing-text/spec.md, specs/scanner-evidence/spec.md, specs/map-rail/spec.md; main specs openspec/specs/scanner-evidence/spec.md and openspec/specs/map-rail/spec.md; openspec/roadmap.md (M4.5); openspec/architecture.md (ADR index). Source: lib/ui/scanner_screen.dart, lib/ui/shell.dart, lib/ui/live_scan_panel.dart, lib/ui/pin_editor.dart, plus grep over lib/ui/*.dart for `.name`, `toIso8601String` and the banned terms; lib/application/{selection,settings,progress,catalog,map}_controller.dart error strings; lib/data/legacy_import.dart (plan reasons); lib/domain/settings.dart (pin frame validation); lib/domain/map_coordinates.dart; enum definitions for every labelled kind. Re-check run: the current proposal.md, design.md and specs/player-facing-text/spec.md, plus the cited source lines: lib/application/selection_controller.dart:365-374, settings_controller.dart:34-37,94-97, progress_controller.dart:72,84,97,116,181, catalog_controller.dart:66-69,122-125, map_controller.dart:125,457, history_controller.dart:33-36, lib/data/legacy_import.dart:340-350 and its `reason:` sites, lib/ui/pin_editor.dart:79-83, lib/domain/map_coordinates.dart:94-97, openspec/specs/catalog-authority/spec.md:82,105. Skills loaded: dart-add-unit-test, flutter-add-widget-test.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. Player-visible strings that live outside `lib/ui` break the new spec, and nothing in the design catches them.**
The `player-facing-text` requirement "Developer wording stays out of the open view" covers all *text shown outside a Details section*. The proposal says there is "No change to `lib/domain`, `lib/application` or `lib/data` behaviour", and Check B (D6) scans only `lib/ui`. But several open-view strings are written in those layers and shown as they are:
- `lib/application/selection_controller.dart:369`: "Stored identity is not present in this mode's current catalog. The activity row is retained." The decision card shows it in red (`item_decision_card.dart:90-95,123,274-279`). It contains the banned word `identity`.
- `lib/application/settings_controller.dart:36` ("previous durable settings remain") and `:96` ("the durable record remains"). These appear on Map and in manual controls (`map_screen.dart:231-234,343-346`, `manual_controls.dart:88-91`, `pin_editor.dart:96`). Both contain the banned word `durable`.
- `lib/application/progress_controller.dart:72,84,97,116` ("Protected credential ..."), `catalog_controller.dart:124` ("last-good data retained") and `map_controller.dart:125,457` ("Prepared map inventory ..."). These are developer wording of exactly the kind D7 rewrites in Settings.
- `lib/data/legacy_import.dart:347-348`: the import plan row reasons, shown at `import_dialog.dart:174`. They carry "identity retained even if catalog identity is unavailable" and raw `toIso8601String()` times in the open view. That breaks both the banned-term rule and the "Times are shown in local time" requirement.

Consequence: the agent-verified "string inventory" for the M4.5 exit criterion would pass while the shipped app still shows `identity`, `durable` and ISO times. The spec requirement is not met, and no test notices.

**M2. Check A's regex misses most of the `.name` sites the design itself cites.**
D6 Check A matches `\.(status|state|reason|code|pass|fir|logStatus|screenshotStatus|source)\.name\b`, which requires a leading `.`. These current sites do not match it, because each uses a local or destructured variable:
- `scan_evidence_panel.dart:184` (`${pass.name}`)
- `:206`, `:238` and `:374` (`${reason.name}`, `reason.name`; `reason` comes from the Dart 3 pattern `ScanRejected(:final reason)`)
- `evidence_panels.dart:228` (`${catalogStatus.name}`)
- `evidence_panels.dart:302` (`source.name`)

This change fixes those sites, so "Clean sources" passes. But the regression requirement ("fails when UI text interpolates `.name` of a status, state, reason, code, pass or found-in-raid value") stays unenforced for the destructuring pattern that this codebase's own pattern-matching style produces. The spec's regression scenario happens to use the one shape the regex does catch.

**M3. Check B as specified hits persisted data values. "Fix by rewording" would then break saved pins.**
`lib/ui/pin_editor.dart:81` has the literals `'labs-native-normalized'` and `'legacy-normalized'`. They are not passed to `Key(`, so a whole-word, case-insensitive match on `normalized` fails Check B. The design's Risks section says such a hit "is fixed by rewording" and that no allow-list entry is added. Rewording these wire names would make `CustomPin.validate()` (`lib/domain/settings.dart:206-211`) throw `FormatException` for every newly saved pin, and it would contradict the proposal's statement that stored values do not change. The design must say how this hit is resolved.

**M4. The proposal contradicts the spec and design on when Details collapses.**
The proposal's second "What Changes" bullet says the Details section "is collapsed for each newly shown subject". The spec ("Its expanded state SHALL last for the app session") and design (Flow & State Gaps: "Details stays expanded and shows the new scan's detail. The flag tracks the user's choice, not the subject") say the opposite. An implementer or pre-ship reviewer reading the proposal would reset Details on every scan. That breaks the "Survives a tab switch" scenario's intent and makes watching scans live impractical.

### Suggestions

- **S1.** Check B's whole-word matching misses inflected forms. Today `item_decision_card.dart:123` reads "Search real item identities, then select one. Requirements, gross values and uncertainty appear here." `identities` does not match `\bidentity\b`, and D7 does not list this string. Matching stems (`identit\w*`, `authori[sz]\w*`, `normali[sz]\w*`, `durabl\w*`) closes the gap at no cost.
- **S2.** `item.normalizedName` is shown as the fallback subtitle when `shortName` is null (`manual_controls.dart:151`, `item_decision_card.dart:254`). It is a tarkov.dev slug: an internal key shown when a name resolves. Neither check covers it. Consider dropping the subtitle when `shortName` is null.
- **S3.** The import-dialog digest Details flag (State & Ownership table: "Reset when the dialog closes") does not fit the spec's general rule "A Details section ... expanded state SHALL last for the app session". Scope that requirement to the Scanner Details sections, or add a sentence for dialog-scoped Details.
- **S4.** map-rail delta, scenario "Status lines use labels": "neither line contains `watching` ... as a bare state name" is hard to assert, given that D7's own label is "Logs: watching folder". Assert instead that the line equals `'Logs: ${mapInputStatusLabel(MapInputStatus.watching)}'` and is not `Logs: watching`.
- **S5.** D5 has widgets call `DateTime.now()` directly. The widget scenario "History row time ... shows `14:32`" can then flake across midnight unless the test builds the observed time from `DateTime.now()`. Consider passing an existing clock (for example `selection.clock`), or keep those assertions at the `localTimeLabel` unit-test layer, as AGENTS.md prefers.
- **S6.** The design cites "ADR-0013 (timing log v1)". The architecture index shows the timing log is now v3 (ADR-0020). Cite ADR-0020 for "timing log keeps the raw codes".

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **(M1)** In proposal.md `## Impact` and design.md D7, add the player-visible display strings in `lib/application` and `lib/data` to the rewrite. Change only the text, no behaviour: `selection_controller.dart:369,372`, `settings_controller.dart:36,96`, `progress_controller.dart:72,84,97,116,181`, `catalog_controller.dart:68,124`, `map_controller.dart:125,457`, `history_controller.dart:35`, and the `legacy_import.dart` plan-row `reason` strings (banned terms and the ISO times at `:347-348`, which move to local time or behind the import dialog's Details). Replace "No change to `lib/domain`, `lib/application` or `lib/data` behaviour" with wording that permits display-string edits. In D6, extend Check B to scan those files too, or to scan every `lib/**` literal assigned to an `error`, `warning` or `reason` field. List the extra files in the design's Resource Bounds row.
2. **(M2)** In design.md D6, change Check A's pattern so that it also matches bare and nullable receivers whose name ends in a listed kind. For example `\b\w*(?:[sS]tatus|[sS]tate|[rR]eason|[cC]ode|[pP]ass|[fF]ir|[sS]ource)\??\.name\b`, applied to non-comment lines with Key/ValueKey arguments excluded (`manual_controls.dart:31` uses `mode.name` inside a `ValueKey`). Add a label-test-style regression case that uses `${reason.name}` alongside the existing `catalog.status.name` one. The spec's "A regression" scenario may add a second WHEN for a destructured `reason`.
3. **(M3)** In design.md D6 or D7, state that `pin_editor.dart:81` replaces the two frame literals with `MapCoordinateFrame.labsNativeNormalized.wireName` and `MapCoordinateFrame.legacyNormalized.wireName` (`lib/domain/map_coordinates.dart:96-97`), and that persisted wire names are never reworded to satisfy Check B.
4. **(M4)** In proposal.md `## What Changes`, replace "It is collapsed for each newly shown subject" with wording that matches the spec: collapsed at launch, the expanded state lasts for the session across new scans, tab switches and breakpoint changes, and it is never saved.

Re-check result: all four Required Changes are applied in the current artifacts (details per item under Rebuttals).

CHANGES_APPLIED: yes

## Rebuttals
- **M1:** fixed. proposal.md What Changes and Impact now include the display strings in the `lib/application` controllers and `lib/data/legacy_import.dart` (text only). design.md D6 Check B scans those files, D7 has rows for the controller messages and the import plan rows (ISO times move to `localTimeLabel`), and Resource Bounds lists the extra files. The `catalog_controller.dart:68,124` strings keep their wording because `catalog-authority` pins them and they contain no banned term (D7 note).
  - **Accepted by reviewer.** Verified: proposal.md:14 and :31 permit display-string edits only and drop the old "No change ... behaviour" wording; design.md:63 (Check B) scans `lib/ui` plus the six controller files and `legacy_import.dart`; design.md:85-86 rewrite every cited string (selection :369, settings :36/:96, progress :72/:84/:97/:116, map :125/:457, history :35, legacy_import :347-348 with `localTimeLabel`); design.md:141 lists the extra files. The catalog exemption holds: `openspec/specs/catalog-authority/spec.md:82,105` pin "Stored catalog unavailable" and "Catalog refresh failed; last-good data retained", and neither contains a banned term. `selection_controller.dart:372` ("Stored-mode catalog could not be opened.") and `progress_controller.dart:181` ("Tracker unavailable") are not in the D7 table, but contain no banned term and are covered by Check B and the D7 "lines not listed follow the spec rules" sentence. Non-blocking leftover for the author to tidy: two sentences still describe the old scope. design.md:167 (Risks) says Check B "is scoped to `lib/ui`", and design.md:131 (Failure & Visibility) says a banned term "in `lib/ui`" fails the suite. D6 and the spec scenario at spec.md:43-45 are authoritative and correct; changing those two phrases to match D6 counts as applying this Required Change and does not void the verdict.
- **M2:** fixed. D6 Check A uses `\b\w*(?:[sS]tatus|[sS]tate|[rR]eason|[cC]ode|[pP]ass|[fF]ir|[sS]ource)\??\.name\b` on non-comment lines, with Key/ValueKey/PageStorageKey arguments excluded. Its sample tests cover `${reason.name}` alongside `${catalog.status.name}`, plus the negatives `ValueKey` and `item.name`. The spec adds the scenarios "A destructured regression" and "Keys are not text".
  - **Accepted by reviewer.** Verified at design.md:62 and spec.md:111-117. The pattern matches every site listed in M2 (`pass.name`, `reason.name`, `catalogStatus.name`, `source.name`) and the member chain `catalog.status.name`; it does not match `item.name` or `mode.name`.
- **M3:** fixed. D6 "Wire names stay as they are": `pin_editor.dart:81` uses `MapCoordinateFrame.*.wireName`, and persisted wire names are never reworded.
  - **Accepted by reviewer.** Verified at design.md:64. `lib/domain/map_coordinates.dart:96-97` defines `legacyNormalized('legacy-normalized', ...)` and `labsNativeNormalized('labs-native-normalized', ...)`, so the replacement keeps the exact wire strings that `lib/ui/pin_editor.dart:81` writes today.
- **M4:** fixed. The proposal's Details bullet now matches the spec: collapsed at launch, kept for the session across new scans, tab switches and breakpoint changes, never saved.
  - **Accepted by reviewer.** Verified at proposal.md:10, which agrees with spec.md:63 and design.md:145.
- **S1:** applied. Check B matches word stems (`identit`, `normali[sz]`).
- **S2:** applied. The `normalizedName` fallback subtitle is dropped (D7 note).
- **S3:** applied. The import dialog Details is dropped, and the digest is shown as "File fingerprint".
- **S5:** applied. Flow & State Gaps says how widget tests build time labels.
- **S6:** applied. ADR-0020 (timing log v3) is cited.
