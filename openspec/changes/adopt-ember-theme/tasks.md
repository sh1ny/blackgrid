# Tasks

Dart work follows the "Dart and Flutter code" section of `AGENTS.md`. Skills per group: `dart-add-unit-test` and `dart-use-pattern-matching` for the domain groups (2, 3); `flutter-add-widget-test` for the widget groups (4, 5, 6); `dart-write-documentation` for every public API; `dart-run-static-analysis` before each commit. Verify with `mise run analyze` and `mise run test`, and format with `dart format`. Agents never launch the app while Escape from Tarkov may be running; nothing in this change needs the game.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| interface-theme → Two rooms built from the design tokens | Dark room carries the dark token values | test/ui/ember_theme_test.dart | dark room carries the dark token values | green |
| interface-theme → Two rooms built from the design tokens | Light room carries the light token values | test/ui/ember_theme_test.dart | light room carries the light token values | green |
| interface-theme → Two rooms built from the design tokens | The map ground does not follow the room | test/ui/ember_theme_test.dart | map ground is the same in both rooms | green |
| interface-theme → Screens take colours only from the theme | A screen reads its colours from the theme | test/ui/theme_source_test.dart | lib/ui has no colour literals outside lib/ui/ember | green |
| interface-theme → Screens take colours only from the theme | A hard-coded colour is reported | test/ui/theme_source_test.dart | reports file and line of a colour literal | green |
| interface-theme → Saved theme choice | Default follows Windows | test/ui/theme_mode_test.dart | System follows a light Windows setting by default | green |
| interface-theme → Saved theme choice | A chosen room survives a restart | test/application/settings_theme_test.dart | saved Dark choice is restored by load | green |
| interface-theme → Saved theme choice | Windows changes while System is chosen | test/ui/theme_mode_test.dart | System follows a Windows brightness change without restart | green |
| interface-theme → Saved theme choice | An unreadable theme value | test/domain/settings_test.dart | bad themeMode reads as system and keeps other settings | green |
| interface-theme → Saved theme choice | Saving the choice fails | test/application/settings_theme_test.dart | failed theme save keeps the previous choice and shows the error | green |
| interface-theme → Theme switch in Settings | Switching rooms | test/ui/settings_dialog_theme_test.dart | selecting Light switches the room in the next frame | green |
| interface-theme → Theme switch in Settings | Selecting the current option | test/ui/settings_dialog_theme_test.dart | selecting the current option saves nothing | green |
| interface-theme → Bundled fonts with notices | Interface text uses the bundled family | test/ui/ember_theme_test.dart | body text uses Geist and title roles use Literata | green |
| interface-theme → Bundled fonts with notices | Every font file has a notice entry | test/ui/font_notice_test.dart | every declared font file has a matching notice and OFL text | green |
| interface-theme → Bundled fonts with notices | A font file changes without its notice | test/ui/font_notice_test.dart | a hash mismatch names the font file | green |
| interface-theme → Ember surfaces and labels | A docked panel has no shadow | test/ui/ember_surfaces_test.dart | docked panels use panel colour, hairline and no elevation in both rooms | green |
| interface-theme → Ember surfaces and labels | Section labels are sentence case | test/ui/ember_surfaces_test.dart | section labels are sentence case | green |
| interface-theme → Ember surfaces and labels | The brand lockup keeps its capitals | test/ui/ember_surfaces_test.dart | brand lockup keeps its capitals | green |
| verdict-presentation → One plate per verdict | Each verdict has its style | test/ui/verdict_plate_test.dart | each verdict has its plate style in both rooms | green |
| verdict-presentation → One plate per verdict | Verdicts differ without colour | test/ui/verdict_plate_test.dart | Keep, Flea and Price unavailable differ by fill and border | green |
| verdict-presentation → One plate per verdict | No plate is drawn in the accent | test/ui/verdict_plate_test.dart | no plate uses accent or accent-text | green |
| verdict-presentation → Price on the Flea and Trader plates | Flea plate with its price | test/ui/verdict_plate_test.dart | Flea plate shows its gross price in ink | green |
| verdict-presentation → Price on the Flea and Trader plates | A plate whose verdict has no price | test/ui/verdict_plate_test.dart | plates without a price show only the word | green |
| verdict-presentation → One-line verdict reason | Keep names the need that decided it | test/domain/verdict_reason_test.dart | Keep names the first actionable need with its count | green |
| verdict-presentation → One-line verdict reason | Keep with an unknown count | test/domain/verdict_reason_test.dart | Keep with an unknown count has no number | green |
| verdict-presentation → One-line verdict reason | Keep for later names the future need | test/domain/verdict_reason_test.dart | Keep for later names the first future need | green |
| verdict-presentation → One-line verdict reason | Check names the first open question | test/domain/verdict_reason_test.dart | Check with only found in raid open names it | green |
| verdict-presentation → One-line verdict reason | Check picks questions in a fixed order | test/domain/verdict_reason_test.dart | Check names the first open input in the fixed order | green |
| verdict-presentation → One-line verdict reason | Check wording for each open input | test/domain/verdict_reason_test.dart | Check wording for each open input | green |
| verdict-presentation → One-line verdict reason | Found in raid unknown outranks the needs it leaves open | test/domain/verdict_reason_test.dart | found in raid outranks an unresolved found-in-raid need | green |
| verdict-presentation → One-line verdict reason | Flea and Trader compare the prices | test/domain/verdict_reason_test.dart | Flea compares gross prices with the best trader | green |
| verdict-presentation → One-line verdict reason | Trader for each way the engine reaches it | test/domain/verdict_reason_test.dart | Trader wording for each engine path | green |
| verdict-presentation → One-line verdict reason | Flea with no trader offer | test/domain/verdict_reason_test.dart | Flea with no trader offer | green |
| verdict-presentation → One-line verdict reason | Price unavailable | test/domain/verdict_reason_test.dart | Price unavailable wording | green |
| verdict-presentation → One-line verdict reason | A long reason at the narrowest card | test/ui/verdict_plate_test.dart | long reason wraps in the compact Map rail card at 960 px | green |
| verdict-presentation → Price freshness tag | Current prices | test/domain/price_freshness_test.dart + test/ui/freshness_tag_test.dart | price within an hour is fresh / fresh tag reads Prices and time | green |
| verdict-presentation → Price freshness tag | Stale prices | test/domain/price_freshness_test.dart + test/ui/freshness_tag_test.dart | stale age in hours then days / stale tag uses warning style | green |
| verdict-presentation → Price freshness tag | Unknown or future price time | test/domain/price_freshness_test.dart | missing or future price time is unknown | green |
| verdict-presentation → Price freshness tag | The tag turns stale while shown | test/ui/freshness_tag_test.dart | tag turns stale on the age notify with a fake clock | green |
| verdict-presentation → Price freshness tag | No tag when the Flea price cannot matter | test/domain/price_freshness_test.dart + test/ui/freshness_tag_test.dart | hidden when not Flea-sellable / no tag on the price row | green |

## 1. Kit, fonts and ADR

- [x] 1.1 Write ADR-0037 "Interface colours come from the Ember theme" in `docs/adr/0037-interface-colours-come-from-the-ember-theme.md` (MADR-short, `Status: accepted`, today's date) with the content of design D11, and add its row to the in-force index in `openspec/architecture.md`; verify the file exists and the index lists it.
- [x] 1.2 Drop the `import 'dart:ui' show FontFeature;` line from what `brand/tools/build.mjs` emits (owner-approved, design D2), run `node brand/tools/build.mjs`, and check that `git diff brand/` shows only the removed import (token values unchanged).
- [x] 1.3 Download `Geist[wght].ttf` and `Literata[opsz,wght].ttf` from one pinned google/fonts commit (`ofl/geist`, `ofl/literata`) into `assets/fonts/`, add `assets/fonts/** -text` to `.gitattributes`, and declare the `Geist` and `Literata` families in `pubspec.yaml`'s `fonts:` block; check `OFL.txt` at that commit against `brand/fonts/OFL-geist.txt` and `OFL-literata.txt`. Verify `flutter pub get` through mise succeeds.
- [x] 1.4 Write the failing `test/ui/font_notice_test.dart` (rows "Every font file has a notice entry", "A font file changes without its notice", with the hash-mismatch case built from a temporary copy), then add the "Bundled fonts" section to `THIRD_PARTY_NOTICES.md` (file, family, commit, source URL, SHA-256, measured size, the full OFL 1.1 text per family) so it passes; flip both rows green.

## 2. Theme setting

- [x] 2.1 Write failing model tests in `test/domain/settings_test.dart` for `themeMode`: round trip of the three values, a missing, non-string or unknown value reads as `system` without marking settings unreadable and keeps every other key (row "An unreadable theme value"), and `ImportPreview.applyTo` keeps the stored choice. Verify they fail for the missing field.
- [x] 2.2 Add `ThemeChoice { system, dark, light }` and `AppSettings.themeMode` (constructor, `copyWith`, `toJson`, independent decode in `fromJson`, design D4); verify 2.1 passes and flip its row green.
- [x] 2.3 Write failing `test/application/settings_theme_test.dart` (rows "A chosen room survives a restart", "Saving the choice fails") with a hand-written failing database fake, then add `SettingsController.setThemeChoice` over `save`; verify they pass and flip the rows green.

## 3. Decision reason and price freshness (domain)

- [x] 3.1 Write failing tests in `test/domain/decision_engine_test.dart` that the engine records `openInputs` in the order item data, Tracker progress, found in raid, unresolved need, Flea eligibility, stale or unknown price time, and that the recommendation and warning strings are unchanged for the existing fixtures. Then add `OpenInput` and the optional `ItemDecision.openInputs` (design D6) and replace the engine's one-hour literal with the shared `priceFreshnessLimit` (D8); verify that `decision_engine_test.dart` passes.
- [x] 3.2 Write the failing `test/domain/verdict_reason_test.dart` covering every "One-line verdict reason" domain row (Keep, Keep with unknown count, Keep for later with a future need listed before an actionable one, each Check open input and the fixed order, found in raid outranking an unresolved need, Flea, Flea with no trader, the three Trader paths quoting gross prices, Price unavailable, non-empty for every verdict), plus a run of `findBannedTermHits` over `lib/domain/verdict_reason.dart`. Verify the tests fail.
- [x] 3.3 Move the rouble formatter `rub` into `lib/domain/`, and implement `verdictReason` in `lib/domain/verdict_reason.dart` (design D7); verify 3.2 passes and flip its rows green.
- [x] 3.4 Write the failing `test/domain/price_freshness_test.dart` (fresh within the limit, stale whole hours under 48 h and then whole days, unknown for null or future, hidden when `fleaEligible` is false), implement `priceFreshness` (D8), verify the tests pass, and flip the domain halves of the freshness rows green.

## 4. Ember theme in the app

- [x] 4.1 Copy `brand/flutter/ember_tokens.dart` byte for byte to `lib/ui/ember/ember_tokens.dart`, and add `test/ui/ember_theme_test.dart` with the identity check against the brand copy. Adapt `ember_theme.dart` into `lib/ui/ember/ember_theme.dart` as `blackgridTheme(Brightness)`, and add `lib/ui/ember/blackgrid_tokens.dart` (`BlackgridColors` with the DESIGN.md `ok-*` and `map-ground` values, `BlackgridType.verdict`; design D3). Write the room, map-ground and font-family rows first and see them fail, then make them pass and flip them green; `mise run analyze` must be clean.
- [x] 4.2 Write failing `test/ui/theme_mode_test.dart` (rows "Default follows Windows" and "Windows changes while System is chosen", driven through `tester.platformDispatcher.platformBrightnessTestValue`), then wire `BlackgridApp` and the bootstrap screen (design D5: themes built once, `themeMode` from settings, `themeAnimationDuration: Duration.zero`); verify the tests pass and flip the rows green.
- [x] 4.3 Write failing `test/ui/settings_dialog_theme_test.dart` (rows "Switching rooms" and "Selecting the current option"), then add the System/Dark/Light segmented control at the top of the Settings dialog; verify the tests pass and flip the rows green.
- [x] 4.4 Write the failing `test/ui/theme_source_test.dart` (design D10 patterns, comments ignored, file and line in the message, a synthetic offending source for the "reported" row) and see it list today's hits.
- [x] 4.5 Move the map colours still built in `lib/ui` (`map_workspace.dart` player marker fill, place label, extract labels; `marker_popup.dart` leader line) into `lib/maps/map_palette.dart` with unchanged values, and point the painters at it. Verify the existing map painting and marker popup tests (`test/ui/map_marker_painting_test.dart`, `test/ui/map_place_labels_test.dart`, `test/ui/map_zone_labels_test.dart`, `test/maps/marker_popup_layout_test.dart`) still pass unchanged.
- [x] 4.6 Restyle `GridPanel`, `CollapsibleGridPanel` and `DetailsSection` to Ember in place and move them to `lib/ui/panels.dart`, with `modeLabel`, `mapLabel` going to `lib/ui/labels.dart` (design D9). Replace every `GridColors` use and remaining literal in `lib/ui` with theme roles, make the uppercase section labels and the Map panel title sentence case, keep the brand lockup's capitals, and delete `lib/ui/theme.dart`. Write the failing `test/ui/ember_surfaces_test.dart` rows first. Verify `theme_source_test.dart`, `ember_surfaces_test.dart` and the whole `mise run test` pass, update existing tests whose expectations were the old uppercase labels or `GridColors`, and flip those rows green.

## 5. Verdict plates and reason line

- [x] 5.1 Write the failing `test/ui/verdict_plate_test.dart` (every "One plate per verdict" and "Price on the Flea and Trader plates" row in both rooms, the dashed border asserted through `DashedBorderPainter.color`, and "A long reason at the narrowest card" in the compact Map rail at a 960 px window, asserting multiple lines, no ellipsis and no overflow).
- [x] 5.2 Build the verdict plate and the reason line into `ItemDecisionCard` (Scanner and compact Map rail), with `DashedBorderPainter` for Price unavailable; verify 5.1 passes, and that `test/ui/decision_card_text_test.dart` and `test/ui/map_rail_test.dart` still pass. Flip the rows green.

## 6. Freshness tag

- [x] 6.1 Write the failing `test/ui/freshness_tag_test.dart` (fresh, stale, the tag turning stale on `SelectionController`'s age notify with an injected fake clock, and no tag for an item that cannot be sold on the Flea).
- [x] 6.2 Add the `FreshnessTag` widget and put it on the decision card's price row, reading `now` from `SelectionController.clock`; verify 6.1 passes and flip the UI halves of the freshness rows green.

## 7. Integration checks

- [ ] 7.1 Run `mise run analyze` and `mise run test` on the finished branch, and `dart format --set-exit-if-changed lib test`; all must pass. Check that `mise run release-notes -- --check openspec/changes/adopt-ember-theme/proposal.md` exits 0 and that the Release Notes still describe what shipped.
- [ ] 7.2 Check that every Test map row is green, and that `openspec validate adopt-ember-theme --strict` passes.

The user-verified M8.5 criterion (the verdict reads at a glance and the map and dialogs look right, on a second monitor and alt-tabbed) is judged at the milestone close after `add-answer-strip`, `restyle-map-workspace` and `restyle-dialogs`, as the proposal says, so this change has no `[user]` task.

## Workflow follow-up

- Pre-ship review (specwright-review) of the finished branch, then open the PR (specwright-pr ship) with a `feat(ui): ...` title.
- After merge: archive the change and finish (specwright-finish).
