# Review

## Metadata

- **Round:** 1 re-check of Required Changes
- **Prior round:** round 1 APPROVE_WITH_CHANGES, 7 Moderate
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** Read again: openspec/changes/adopt-ember-theme/proposal.md (What Changes, Impact, S6), specs/interface-theme/spec.md ("Screens take colours only from the theme"), specs/verdict-presentation/spec.md ("One-line verdict reason", "Price freshness tag"), design.md (D2, D6, D7, D8, D10, summary table), and the author's Rebuttals in openspec/changes/adopt-ember-theme/review.md. Checked against the code: lib/ui/map_workspace.dart (:753, :851, :912), lib/ui/marker_popup.dart:342, lib/domain/map_zone_style.dart:50, lib/domain/decision_engine.dart (:97-123), lib/maps/ (which files already import Flutter). Only the seven Required Changes were re-checked; nothing else was reviewed again.

## Findings

### Critical (blocking)

None.

### Moderate

The seven round 1 findings, M1 to M7, are all resolved (see Rebuttals). No new Moderate finding.

### Suggestions

None new. The round 1 suggestions S-a to S-h are recorded as applied in the author's notes. They were not re-reviewed.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **(M1)** In spec `interface-theme`, "Screens take colours only from the theme", and in design D10, deal with `lib/ui/map_workspace.dart`. Either (a) move the map painter's colour construction (`Colors.white` for the player marker, `Color(placeLabelColour)`, `Color(labelColourFor(…))`) into `lib/maps/`/`lib/domain/` as `Color` values with unchanged values, and list those three sites in D10 next to `marker_popup.dart` and `shell.dart`; or (b) add the map canvas painter in `lib/ui/map_workspace.dart` to the requirement's named exception, and say so in D10 and in ADR-0037's planned text. State which, and keep S6's "values unchanged" true.
2. **(M2)** In D2, state how `lib/ui/ember/ember_tokens.dart` passes `mise run analyze` while staying byte-identical. The options are (a) an owner-approved fix in `brand/tools/build.mjs` that drops the redundant `dart:ui` import, then a regeneration, or (b) an `analysis_options.yaml` exclusion for that one generated file, with the proposal's "analyze checks them now" narrowed to `ember_theme.dart` and the Blackgrid files. I recommend (a). D2 is user-chosen, so put this to the user.
3. **(M3)** In spec `verdict-presentation`, "One-line verdict reason", add the exact line for each Check open input: item data, Tracker progress, unresolved need with its source shown, Flea eligibility, price time. Also add the Trader lines for "Flea-eligible, no Flea price" and "trader pays at least the Flea price", each as a scenario. S3 is user-chosen, so the wording goes to the user under `DECISION_MAKING: important`.
4. **(M4)** State in the spec (in the Flea/Trader reason scenario) and in D7 that the reason quotes the gross prices the engine compares (`fleaGross`, `traderGross`), and change the proposal's "per-slot price comparison" to match. If per-slot is what the user wants, say so instead and explain how it squares with the plate's gross price.
5. **(M5)** In D7, replace "the first need … whose state is actionable or future" with: Keep takes the first need whose state is actionable, and Keep for later takes the first need whose state is future.
6. **(M6)** In spec `verdict-presentation`, "Price freshness tag", add a scenario for a decision whose `fleaEligible` is `false`, giving the tag's text and style (for example the plain style, or no tag). Mirror it in D8's `priceFreshness` inputs. This is user-visible, so follow the decision mode.
7. **(M7)** Make S6 and D10 agree on the marker bubble leader line: either S6 lists it as changed to `inkSecondary`, or D10 keeps its value and moves the literal into an allowed place (see item 1).

CHANGES_APPLIED: yes

## Rebuttals

- **M1:** fixed (option a). D10 moves the player marker fill (`map_workspace.dart:753`), the place label colour (`:851`, from `placeLabelColour` at `lib/domain/map_zone_style.dart:50`), the extract label colours (`:912`) and the leader line (`marker_popup.dart:342`) into `lib/maps/map_palette.dart` as `Color` constants with unchanged values. `lib/maps/` already imports Flutter (for example `map_marker_icons.dart`), so no new layering is needed. The spec's exemption now says that map painting code in `lib/ui` reads the palette from `lib/maps`/`lib/domain`, and S6 says the moved literals keep their values. The "reports no hits" scenario is now reachable without recolouring the map. **Accepted by reviewer.**
- **M2:** fixed with the owner's choice (a). D2 records the `build.mjs` import fix, the regeneration of `brand/flutter/ember_tokens.dart` (and `tokens.css`) with token values unchanged, the identity test against the regenerated file, and analysis of the `lib/` copy. The proposal's What Changes names the owner-approved fix and says Mythspine's copy is not changed. Excluding the file from analysis is now listed as rejected. **Accepted by reviewer.**
- **M3:** fixed. The scenario "Check wording for each open input" gives exact lines for item data, Tracker progress, an unresolved need with its source, Flea eligibility, a price time over an hour old, and a price time that is missing or in the future. D6 splits price time into `priceTimeStale` and `priceTimeUnknown` to match. "Trader for each way the engine reaches it" covers all three Trader paths in `decision_engine.dart:115-123`. The owner accepted the wording, as the author's note records. **Accepted by reviewer.**
- **M4:** fixed. The Flea/Trader scenario states gross prices "as the engine compares them". D7 quotes `fleaGross`/`traderGross`, "never the per-slot values". The proposal now says "the gross price comparison the engine makes". **Accepted by reviewer.**
- **M5:** fixed. D7: "Keep takes the first need, in engine order, whose state is actionable. Keep for later takes the first need whose state is future." This matches the spec. **Accepted by reviewer.**
- **M6:** fixed with the owner's choice (hide). The tag requirement adds "unless the item cannot be sold on the Flea". The new scenario "No tag when the Flea price cannot matter" asserts no tag and no warning style. D8 takes `fleaEligible` and returns hidden on `false`, citing the engine's own exemption (`:105-107`). When `fleaEligible` is null, the verdict is Check and the tag still shows, which is consistent. **Accepted by reviewer.**
- **M7:** fixed. S6 keeps the leader line's value, and D10 moves it into `lib/maps/map_palette.dart` unchanged instead of recolouring it. S6, D10 and the proposal's out-of-scope marker bubble now agree. **Accepted by reviewer.**
- Suggestions S-a to S-h are recorded as applied by the author (S-d by the owner's choice: found in raid now comes before unresolved need in the spec, D6 and D7, with its own scenario). They were not re-reviewed in this re-check.
