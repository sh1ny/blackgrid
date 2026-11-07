# Review

## Metadata

- **Round:** 1 (re-check)
- **Prior round:** Round 1: APPROVE_WITH_CHANGES with 7 Required Changes (C1, M1-M6), CHANGES_APPLIED: no. This run re-checks only those 7 items.
- **Reviewer:** fresh-context subagent (Claude Code)
- **Reviewed:** openspec/changes/add-location-labels/{proposal.md, design.md, specs/prepared-map-packs/spec.md, specs/map-place-labels/spec.md, review.md (round 1)}; main spec openspec/specs/prepared-map-packs/spec.md ("Only the active generation is ever used", lines 156-170); lib/domain/map_floors.dart (Labs policy 91-106, `isLayerVisible` 259-268) to confirm that Labs Second Level is a selectable overlay, so the new "Selected floor wins" scenario can be tested. Round 1 read: openspec/changes/add-location-labels/{proposal.md, design.md, specs/map-place-labels/spec.md, specs/prepared-map-packs/spec.md}; main specs openspec/specs/{prepared-map-packs, map-zone-labels, runtime-map-data}/spec.md; openspec/architecture.md; docs/adr/0005, 0023, 0033, 0034, 0035; tool/maps/pack.dart; tool/maps/calibration.dart; lib/maps/prepared_map.dart; lib/maps/prepared_map_loader.dart; lib/application/map_controller.dart; lib/domain/map_floors.dart; lib/domain/map_zone_style.dart; lib/domain/settings.dart; lib/domain/marker_categories.dart; lib/ui/map_workspace.dart; THIRD_PARTY_NOTICES.md; the frozen assets/maps/versions/cefe97a6.../ evidence files. Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis, flutter-add-widget-test.

Round 1 also checked these against the frozen data and found them correct: the per-map label counts (303 across 10 maps, Interchange 77, Customs 24, Labs 31); the `[x, z]` axis order (Customs "Dorms" [200,150] and "Old Gas" [331,-173] match the dorm and Old Gas marker positions); the three string rotations on Customs; every D1 floor-to-layer pairing (each matches the layer's `svgLayer`/`tilePath`, the identity `reconcileFloors` uses); and the D4 overlap rule. Under that rule every banded label gets at least one floor: Interchange 25–33 goes to `First_Floor` only, Factory "Office Building" to Ground, Second and Third, and the Shoreline −4..−2 labels to Ground only. The Ground Zero and Reserve exclusions in D1 also hold.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Critical (blocking)

**C1. The delta leaves the main spec requiring preparation version 3.** (Resolved by Required Change 1.) The main `prepared-map-packs` requirement "Only the active generation is ever used" (openspec/specs/prepared-map-packs/spec.md:158-170) says: "Packs SHALL use preparation version 3 … and the app and the validator SHALL refuse any other preparation version". Its scenario "Active generation loads" also names a version 3 generation. The delta only ADDed "The app loads only packs that carry labels" (version 4 only) and did not modify that requirement. After archive, the main spec would have required the app both to refuse version 4 and to accept only version 4. No implementation can satisfy both, and the verify step would have flagged whichever requirement it checked second.

### Moderate

**M1. The design's expected rebuild output contradicts the code and the main spec.** (Resolved by Required Change 2.) Risks said: "no artwork bytes change, so the rebuild report shows a manifest-only change, no `Artwork changed` line. If it does print `Artwork changed`, stop and investigate". In the code, `packChangeReport` reports every differing map-level key (pack.dart:2203-2215). Adding `labels` to all 13 maps therefore yields `<id>: manifest values changed` for every map, and the `preparationVersion` change yields `pack: manifest values changed` (2263-2269). `refresh` then always prints "Artwork changed: the owner must check the maps listed above…" (3266-3276). The main spec requires the same ("SHALL require the owner's check when anything but the toolchain record changed", spec.md:130, and the "Manifest values change without a file change" scenario). An implementer following the design would have stopped on the expected output. AGENTS.md's map-pack rule also requires the PR to be marked "artwork changed: owner check", which the design did not plan for.

**M2. The design contradicts the in-force ADR-0033.** (Resolved by Required Change 3.) ADR-0033 D2 says the loader checks "preparation version 3", and D8 says "Only preparation version 3 validates or loads" (docs/adr/0033…md:15, 22). Its index row in architecture.md:200 says "preparation version 3 only". D2 here moves to version 4, yet the ADRs section said the new ADR-0036 "supersedes nothing". Left as it was, the ADR record would say that version 4 cannot load.

**M3. `validateCandidate` does not check labels against the candidate's own evidence.** (Resolved by Required Change 4.) Today `validateCandidate` checks a candidate's markers and floors against the candidate's own evidence: markers at pack.dart:1670-1676, floors at 1686-1720 ("candidate-own-source fidelity", ADR-0035). It is the only gate on `promote` (prepare.dart:234), on staged-candidate publication (pack.dart:2780) and on committed-generation verification (1971, 2024-2027). The design said only "v4 only, labels valid". A candidate whose `labels` disagreed with its own `evidence/metadata/maps.json` would therefore have passed validation and been promoted. Only `maps:check` in CI would have caught it, after the fact.

**M4. Thinning lets labels of the floor the user did not pick hide the floor they picked.** (Resolved by Required Change 5, user chose Option A on 2026-11-07.) The Labs and Interchange floors are non-exclusive (manifest `exclusive: false`), so `isLayerVisible` keeps the base visible under any overlay (map_floors.dart:262-272). S2 placed labels by size, then pack order, and the base labels come first in the source:
- Labs: all 31 labels are size 90, and the First Level labels (indices 0–18) come before the Second Level labels (19–30).
- Interchange: the mall shops are mostly size 65. The ground-band "Garage A–D" labels (size 80, band −1000..24) sit inside the mall footprint, e.g. "Garage B" [47,-112] next to "EMERCOM" [18,-103], "Mode7" [69.5,-134] and "Dino Clothes" [91,-119].

With that order, selecting Labs Second Level or the Interchange 2nd Floor let overlapping base names win, so the selected floor's own names were skipped at the zooms where the user is reading that floor.

**M5. The spec contradicts D6 on label opacity.** (Resolved by Required Change 6.) The spec scenario "Search does not dim labels" required that "place labels are drawn at full opacity", while D6 draws them at 85% opacity at all times. The spec's colour rule also left out D6's "judged on the colour blended at 85% opacity".

**M6. No scenario requires a map without a `labels` key to fail.** (Resolved by Required Change 7.) D2 justifies the version bump with "A missing key and a map with no labels would look the same". No scenario required that a version 4 map lacking the key fails, so `json['labels'] ?? const []` would have passed every listed scenario.

### Suggestions

These are carried over from round 1 and were not re-checked. They are not required.

**S-a. Make the drift test check the floor pairing, and run the check in the builder too.** The drift test compares each table band with "a layer name and extent index". A mispaired entry (for example `Second_Floor ← "3rd Floor"#0`) still matches its named layer and passes. Each metadata layer already names its Blackgrid floor through `svgLayer`/`tilePath`, the identity `reconcileFloors` uses (calibration.dart:360-383). Asserting that identity would make the pairing checked, not only reviewed. Running the same check inside `rebuildCandidate` (it already reads `metadata/maps.json`, pack.dart:950) would also make the Flow & State Gaps claim true that a changed layer height fails "before publication".

**S-b. The label cache's invalidation is described two ways.** The State & Ownership table says "Cleared with `_invalidateMarkers`"; Flow & State Gaps says "the label cache is not cleared by marker publication". `_invalidateMarkers` runs in `publishMarkers` (map_controller.dart:281), as well as in `setSearch`, `setQuestFilters`, `setSelectedMarker` and `setRaidHighlights`. Either give labels their own invalidation (map, floors, viewport, transform) or drop the claim. (Still present in the current design.md, lines 147 and 174.)

**S-c.** The pack spec says a label records "its source position projected like a marker position". D2 stores the raw game position `{x, z}`, and the app does the projection. Reword the spec so builder tests do not expect scene coordinates.

**S-d.** Applied: "Label names an unknown floor" now says the pack fails to load, naming the map and the floor.

**S-e.** A persisted legacy `Labels` category already exists (settings.dart:19, legacy_import.dart:134) and nothing reads it. Record that an imported `Labels: false` stays ignored.

**S-f.** Measure with one fill-style layout per eligible label, and lay out the halo only for labels that are placed. Also consider adding `required('evidence/terms/tarkov-dev-software-LICENSE.txt')` to `validateCandidate` (pack.dart:1543-1550).

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (C1) **Applied.** In `specs/prepared-map-packs/spec.md`, add a `## MODIFIED Requirements` entry for "Only the active generation is ever used" with the full requirement text, with "preparation version 3" replaced by "preparation version 4"; change "Active generation loads" to a valid preparation version 4 generation; change "Older preparation version" to version 3; remove the version sentence and the "Older pack version" scenario from the ADDED "The app loads only packs that carry labels". Re-check: the MODIFIED entry (spec delta lines 105-119) matches the main text (main spec 156-170) word for word except 3 → 4. "Active generation loads" names version 4. "Older preparation version" names version 3 with the required THEN. The ADDED requirement (66-79) no longer states a version rule and has no "Older pack version" scenario.
2. (M1) **Applied.** Replace the Risks bullet with the expected rebuild output. Re-check: design.md:196 lists `<id>: manifest values changed` for all 13 maps (`labels`), `pack: manifest values changed` (`preparationVersion`) and the "Artwork changed…" line, cites pack.dart:2203-2215, 2263-2269 and 3266-3276, states that it lists no changed files and that a non-empty changed-files list is the stop signal, and requires the AGENTS.md "artwork changed: owner check" PR marking with the per-map summary, recorded as unverified until the user reports the M8-close check.
3. (M2) **Applied.** State in the ADRs section that ADR-0036 partly supersedes ADR-0033 and plan the architecture.md edits. Re-check: design.md:202 says that ADR-0036 partly supersedes ADR-0033's "preparation version 3" statements (D2 loader order, D8), that ADR-0033's file stays unchanged, and that the same task updates the ADR-0033 row ("preparation version 3 only"), its superseded-by column, the ADR-0036 row and the "Prepared map pack" bullet.
4. (M3) **Applied.** Have `validateCandidate` re-derive labels from the candidate's own metadata and add the scenario. Re-check: D4 (design.md:64) states the re-extraction and assignment with canonical equality, naming the map, citing pack.dart:1670-1676, and names it as the gate for promote, staged publication and committed-generation verification. The data-flow diagram has the "re-derive and compare" edge into `validateCandidate`, and the Failure table row (156) lists the mismatch. The spec delta has the requirement "Validation re-derives labels from the candidate's own metadata" with the scenario "Labels differ from their evidence" (81-90), including "nothing is promoted".
5. (M4) **Applied (user chose Option A on 2026-11-07).** Record the answer in S2, its summary row and the thinning requirement, and add the Labs scenario. Re-check: proposal S2 places labels of a selected overlay floor first, then by size, then source order, and records the date and reason; it stays `Chosen by: user`. The design summary row S2 (design.md:99) reads "selected floor first, then larger, then pack order". D5 (72) sorts the same way. The spec's "Overlapping place labels thin out" requirement (70) states the order, and the scenario "Selected floor wins" (84-86) is the required Labs case. The scenario can be tested: in map_floors.dart:91-106 `Second_Level` is a Labs overlay, and `selectedOverlayIds` gives the selection. The proposal's What Changes bullet matches.
6. (M5) **Applied.** Fix the opacity wording and the contrast rule. Re-check: "Search does not dim labels" now says "drawn at their normal opacity, the same as with no search" (spec 65-67). The "centred, rotated and haloed" requirement (44) states 85% opacity and judges the 3:1 contrast on the colour blended at 85% over `#090F0D`. The palette scenario (54-56) uses the same blended rule. This matches D6 (design.md:80).
7. (M6) **Applied.** Add the missing-key scenario and state the rule in D2. Re-check: the spec delta's "Map without a labels key" scenario (73-75) matches the required text, and the requirement (67) states that the key is required. D2 (design.md:48) says that the validator and loader require the key on every map and never read a missing key as empty. The Failure table (156) lists "a map without `labels`".

CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->
