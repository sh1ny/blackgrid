# Tasks

Dart work follows AGENTS.md "Dart and Flutter code". Skills per group: `dart-use-pattern-matching`, `dart-write-documentation`, `dart-add-unit-test` and `dart-run-static-analysis` for every group that writes Dart; `flutter-add-widget-test` for group 7. Map pack work follows AGENTS.md "Map pack toolchain upgrades" for the rebuild in group 5.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| map-place-labels → Place labels show for the floors they belong to | Ground label stays under an overlay | test/maps/map_controller_test.dart | `place labels: base label stays visible under a selected overlay` | green |
| map-place-labels → Place labels show for the floors they belong to | Overlay adds its labels | test/maps/map_controller_test.dart | `place labels: overlay label shows only while its overlay is selected` | green |
| map-place-labels → Place labels show for the floors they belong to | Label of a hidden exclusive floor | test/maps/map_controller_test.dart | `place labels: exclusive floor hides labels of other floors` | green |
| map-place-labels → Place labels show for the floors they belong to | Map without labels | test/maps/map_controller_test.dart | `place labels: map with an empty label list yields none` | green |
| map-place-labels → Place labels keep a fixed screen size | Zooming keeps the size | test/ui/map_place_labels_test.dart | `place label font size does not change with zoom` | green |
| map-place-labels → Place labels keep a fixed screen size | Relative sizes | test/domain/map_place_labels_test.dart | `font size follows relative size 65, 80, 100` | green |
| map-place-labels → Place labels keep a fixed screen size | Out-of-range size is clamped | test/domain/map_place_labels_test.dart | `font size is clamped to 10..16` | green |
| map-place-labels → Place labels are centred, rotated and haloed | Rotated label | test/ui/map_place_labels_test.dart | `rotated label is drawn rotated about its anchor` | green |
| map-place-labels → Place labels are centred, rotated and haloed | Unrotated label | test/ui/map_place_labels_test.dart | `unrotated label is centred on its anchor` | green |
| map-place-labels → Place labels are centred, rotated and haloed | Colour rule rejects a bad label colour | test/domain/map_zone_style_test.dart | `place label colour differs from faction colours and meets 3:1 blended at 85%` | green |
| map-place-labels → Place labels sit behind every marker drawing | Badge over a label | test/ui/map_place_labels_test.dart | `place labels are drawn before outlines, names and badges` | green |
| map-place-labels → Place labels sit behind every marker drawing | Search does not dim labels | test/ui/map_place_labels_test.dart | `search leaves place label opacity unchanged` | green |
| map-place-labels → Overlapping place labels thin out | Zoomed out | test/domain/map_place_labels_test.dart | `larger overlapping label wins` | green |
| map-place-labels → Overlapping place labels thin out | Zooming in restores the name | test/domain/map_place_labels_test.dart | `separated labels are both placed` | green |
| map-place-labels → Overlapping place labels thin out | Equal sizes | test/domain/map_place_labels_test.dart | `equal sizes: earlier pack index wins` | green |
| map-place-labels → Overlapping place labels thin out | Selected floor wins | test/domain/map_place_labels_test.dart | `selected overlay label wins over a base label of equal size` | green |
| map-place-labels → Overlapping place labels thin out | Off-screen label takes no room | test/domain/map_place_labels_test.dart | `label outside the viewport takes no room` | green |
| map-place-labels → Place labels are not interactive | Click on a label | test/ui/map_place_labels_test.dart | `click on a place label selects nothing` | green |
| map-place-labels → Place labels are not interactive | Click on a label over a badge | test/ui/map_place_labels_test.dart | `click on a badge under a place label selects the marker` | green |
| map-place-labels → Place labels are not interactive | Accessibility targets | test/ui/map_place_labels_test.dart | `place labels add no semantics targets` | green |
| prepared-map-packs → A pack carries each map's place labels | Map with labels | test/maps/place_label_preparation_test.dart | `frozen metadata yields 303 labels on 10 maps in source order` | green |
| prepared-map-packs → A pack carries each map's place labels | Map without labels | test/maps/place_label_preparation_test.dart | `maps without source labels get an empty list` | green |
| prepared-map-packs → A pack carries each map's place labels | Missing optional fields | test/maps/place_label_preparation_test.dart | `missing rotation and size default to 0 and 80` | green |
| prepared-map-packs → A pack carries each map's place labels | Numeric text field | test/maps/place_label_preparation_test.dart | `numeric string rotation is converted` | green |
| prepared-map-packs → A label's floors come from its height band | Upper-floor label | test/maps/place_label_preparation_test.dart | `Interchange IDEA belongs to First_Floor only` | green |
| prepared-map-packs → A label's floors come from its height band | Label spanning floors | test/maps/place_label_preparation_test.dart | `Factory Office Building belongs to base and both upper floors` | green |
| prepared-map-packs → A label's floors come from its height band | Unbanded label | test/maps/place_label_preparation_test.dart | `unbanded Customs label belongs to the base floor` | green |
| prepared-map-packs → A label's floors come from its height band | Label outside every floor | test/maps/place_label_preparation_test.dart | `label overlapping no floor band fails naming map and text` | green |
| prepared-map-packs → A label's floors come from its height band | Band edge | test/maps/place_label_preparation_test.dart | `floor band includes its bottom and excludes its top` | green |
| prepared-map-packs → A label's floors come from its height band | Banded label without floor bands | test/maps/place_label_preparation_test.dart | `banded label on a map without table bands fails` | green |
| prepared-map-packs → A label's floors come from its height band | Table drifts from the metadata | test/maps/place_label_preparation_test.dart | `band table matches frozen metadata heights and floor pairing` | green |
| prepared-map-packs → Malformed labels fail the build | Bad position | test/maps/place_label_preparation_test.dart | `malformed position fails naming map and index` | green |
| prepared-map-packs → Malformed labels fail the build | Empty text | test/maps/place_label_preparation_test.dart | `blank text fails naming map and index` | green |
| prepared-map-packs → The app loads only packs that carry labels | Current pack | test/maps/active_pack_loader_test.dart | `the real loader loads the committed active pack` (extended: label counts) | green |
| prepared-map-packs → The app loads only packs that carry labels | Map without a labels key | test/maps/prepared_map_labels_test.dart | `map without labels key fails in loader and validator` | green |
| prepared-map-packs → The app loads only packs that carry labels | Label names an unknown floor | test/maps/prepared_map_labels_test.dart | `label with an unknown floor fails naming map and floor` | green |
| prepared-map-packs → Validation re-derives labels from the candidate's own metadata | Labels match their evidence | test/maps/map_preparation_test.dart | `validateCandidate accepts labels derived from own metadata` | green |
| prepared-map-packs → Validation re-derives labels from the candidate's own metadata | Labels differ from their evidence | test/maps/map_preparation_test.dart | `validateCandidate rejects labels that differ from own metadata` | green |
| prepared-map-packs → The third-party notices credit the place labels | Credit present | test/maps/place_label_notice_test.dart | `third-party notices credit the place labels` | green |
| prepared-map-packs → The third-party notices credit the place labels | Licence text missing from the pack | test/maps/place_label_notice_test.dart | `missing tarkov-dev licence in the pack fails naming the path` | green |
| prepared-map-packs → Only the active generation is ever used (MODIFIED) | Active generation loads | test/maps/active_pack_loader_test.dart | `the real loader loads the committed active pack` (now v4) | green |
| prepared-map-packs → Only the active generation is ever used (MODIFIED) | Active generation is broken | test/maps/map_controller_test.dart | `broken active pack surfaces as the map load error` | green |
| prepared-map-packs → Only the active generation is ever used (MODIFIED) | Older preparation version | test/maps/prepared_map_labels_test.dart | `preparation version 3 is refused by loader and validator` | green |
| prepared-map-packs → Metadata-only refresh preserves prepared artwork and calibration (MODIFIED) | Metadata changes without artwork changes | test/maps/map_preparation_qualification_test.dart | `refresh reports changed artwork and the owner check` | green |
| prepared-map-packs → Metadata-only refresh preserves prepared artwork and calibration (MODIFIED) | Artwork or calibration drifts | test/maps/map_generation_inputs_test.dart | `metadata preservation rejects forbidden artifact differences` (extended: a changed `labels` entry) | green |
| prepared-map-packs → Metadata-only refresh preserves prepared artwork and calibration (MODIFIED) | Reviewed floor ownership no longer matches | test/maps/map_preparation_qualification_test.dart | `metadata refresh accepts disappeared reviewed markers without restoring their overrides` | green |

## 1. ADR and architecture

- [x] 1.1 Write `docs/adr/0036-place-labels-are-pack-owned.md` (MADR short: Status accepted, Date, "Partly supersedes: ADR-0033, preparation version 3 statements (D2, D8) only", Context, Decision, Consequences) from design.md D1–D4 and S5. Leave `docs/adr/0033-*.md` unchanged. Verify: the file exists and `git diff --stat docs/adr/0033-*` is empty.
- [x] 1.2 Update `openspec/architecture.md`: add the ADR-0036 index row; mark ADR-0033's row "preparation version 3 only" as partly superseded by 0036 (version 4); update the "Prepared map pack" bullet (preparation version 4, per-map `labels`, re-derived at validation), and the Map tooling and `MapController` component rows (band table, `visiblePlaceLabels`). Verify by reading the diff: every "preparation version 3" statement in force now says 4 or cites ADR-0036.

## 2. CI: full-rebuild qualification test timeouts (design D8)

- [x] 2.1 Add a documented constant to `test/support/map_preparation_fixtures.dart`, `fullRebuildTimeout = Timeout(Duration(minutes: 10))`. Its doc comment says these tests run a full staging or `rebuildCandidate`, took about 2 minutes on GitHub runners and timed out at the 2-minute `qualification` tag default in CI runs 42395244727, 42410087351 and 42410085044.
- [x] 2.2 Pass `timeout: fullRebuildTimeout` to every `qualification`-tagged test in `test/maps/artwork_refresh_test.dart` and `test/maps/map_preparation_qualification_test.dart` that runs a full staging or `rebuildCandidate`, at least "staging and frozen reproduction omit stale marker overrides", "staging accepts missing and unsupported metadata maps independently of artwork" and `artworkReproducesWithoutRawStage`. Leave `dart_test.yaml`'s tag default at 2 minutes and every other test unchanged. No assertion changes. Verify: `grep -n fullRebuildTimeout` lists each such test, `git diff dart_test.yaml` is empty, and `flutter test --tags qualification test/maps/artwork_refresh_test.dart test/maps/map_preparation_qualification_test.dart` passes (run through `mise exec --`, with the pinned Flutter).

## 3. Builder label module (not wired yet)

- [x] 3.1 Write the failing tests in `test/maps/place_label_preparation_test.dart` for the rows "Map with labels" through "Empty text" (reading the active pack's `evidence/metadata/maps.json`; synthetic small inputs for the failure rows). Verify they fail because `tool/maps/place_labels.dart` does not exist.
- [x] 3.2 Implement `tool/maps/place_labels.dart`: the band table from design.md D1, each entry naming its metadata source (`heightRange`, Interchange `_heightRange`, or layer name + extent index); `extractPlaceLabels` (validate, apply defaults, convert numeric strings, keep source order, map `the-lab` → `thelab`); `assignLabelFloors` (`bottom < max && top >= min`, unbanded → base, empty → `FormatException` naming map and text); a `checkBandTable` that resolves every entry against the metadata and asserts the band and the floor pairing (the layer's `svgLayer`/`tilePath` identity `reconcileFloors` uses). Doc comments on public members. Verify: `flutter test test/maps/place_label_preparation_test.dart` passes; flip those rows green.

## 4. Placement and style rules (domain)

- [x] 4.1 Write failing tests in `test/domain/map_place_labels_test.dart` (font size and placement rows) and the palette row in `test/domain/map_zone_style_test.dart`. Verify they fail for the missing API.
- [x] 4.2 Implement `lib/domain/map_place_labels.dart`: `placeLabelFontSize(size)` (13 × size / 80, clamped 10–16), the label colour `#C8D0CB` at 85% (in `map_zone_style.dart` next to the faction colours), and `placeLabels(candidates, viewport, selectedOverlayFloorIds)`: selected-overlay labels first, then size descending, then pack index; viewport cull on rotated bounds; skip on overlap of axis-aligned rotated bounds grown by 2 px. Verify the group's tests pass; flip rows green.

## 5. Pack format v4: builder, validator, loader and the rebuilt pack

One group, so the suite is green at its commit: the committed pack and the code that reads it change together.

- [x] 5.1 Write failing tests: `test/maps/prepared_map_labels_test.dart` (missing key, unknown floor, version 3 refused); the two `validateCandidate` rows in `test/maps/map_preparation_test.dart`; extend `metadata preservation rejects forbidden artifact differences` with a changed `labels` entry; extend `the real loader loads the committed active pack` to assert version 4 and the per-map label counts. Verify each fails for the right reason.
- [x] 5.2 Builder: in `rebuildCandidate` (`tool/maps/pack.dart:931-1196`) write `labels` per map from `extractPlaceLabels` + `assignLabelFloors` (run `checkBandTable` first), set `preparationVersion: 4`. `validateCandidate`: accept only 4, require `labels` on every map, re-derive labels from the candidate's own `evidence/metadata/maps.json` and require canonical equality (naming the map), and require `evidence/terms/tarkov-dev-software-LICENSE.txt`. `validateMetadataPreservation`: compare `labels`. Update `tool/maps/prepare.dart` usage text ("Preparation v3" → v4, labels). Verify: the 5.1 builder/validator tests pass.
- [x] 5.3 App: `PreparedMap` parses `labels` into an immutable `placeLabels` list (text, game position, rotation, size, floor ids), validating each and rejecting a missing key or unknown floor with a message naming the map; `prepared_map_loader.dart` accepts only version 4. Update test fixtures that build version 3 manifests (`preparedPackManifest` and friends under `test/support/`, `artwork_compatibility_test.dart`, `map_change_report_test.dart`, `map_generation_inputs_test.dart`, `map_preparation_qualification_test.dart`) to version 4 with `labels`. Verify: the 5.1 loader tests pass.
- [x] 5.4 Rebuild the committed pack: `mise run maps:rebuild`. Expect `<id>: manifest values changed` for all 13 maps, `pack: manifest values changed`, the "Artwork changed: the owner must check…" line and no changed files; a non-empty changed-files list means stop and investigate. Commit the new generation, the deleted old one, `assets/maps/active.json` and `pubspec.yaml`. Verify: `mise run maps:check` prints `Map pack <id> reproduced byte-identically with ...`.
- [x] 5.5 [evidence] Capture the `maps:rebuild` report (per-map lines and the Artwork changed line) → evidence/maps-rebuild.txt
- [x] 5.6 Verify the group: `mise run test` and `mise run test:qualification` pass; flip the group's rows green.

## 6. Controller: visible place labels

- [x] 6.1 Write the failing floor-visibility tests in `test/maps/map_controller_test.dart` (rows "Ground label stays under an overlay" through "Map without labels", using a small synthetic pack). Add a test that `publishMarkers` does not rebuild the label projection. Verify they fail.
- [x] 6.2 Implement `MapController.visiblePlaceLabels()`: labels of the selected map whose `floorIds` include a visible layer, projected with `map.gameToScene` and the view transform, with each label's membership in a selected overlay. Cache them under their own invalidation (map, floor selection, viewport, transform), not `_invalidateMarkers`, so marker publication, search and selection do not clear them. Verify the tests pass; flip rows green.

## 7. Painter

- [x] 7.1 Write failing tests in `test/ui/map_place_labels_test.dart` with `test/support/map_widget_harness.dart`: fixed font size under zoom, rotation and centring, draw order before outlines/names/badges, opacity unchanged by search, click-through and no semantics targets. Verify they fail.
- [x] 7.2 In `_MapPainter.paint` (`lib/ui/map_workspace.dart:709`), after the scene and before outlines: measure each visible label with one fill-style `TextPainter`, call `placeLabels`, then for placed labels draw the halo pass and the fill pass rotated about the anchor (`canvas.rotate(degrees × π / 180)`), at 85% opacity, disposing painters as `_name` does. No hit testing or semantics for labels. Verify the group's tests and `test/ui/map_zone_labels_test.dart` pass; flip rows green.

## 8. Rights note

- [x] 8.1 Write the failing tests in `test/maps/place_label_notice_test.dart` (entry present; licence file present in the active pack). Verify they fail.
- [x] 8.2 Add the place-labels entry to `THIRD_PARTY_NOTICES.md` beside the "Metadata and markers — Tarkov.dev" line, as design.md D3 lists. Leave the pack `NOTICE.txt` unchanged. Verify the tests pass; flip rows green.

## 9. Integration checks

- [ ] 9.1 Run `mise run analyze`, `mise run test`, `mise run maps:check` and `dart format --output=none --set-exit-if-changed lib test tool`; all pass. Confirm every Test map row is green.
- [ ] 9.2 Update the proposal's `## Release Notes` if anything shipped differs from it; verify with `mise run release-notes -- --check openspec/changes/add-location-labels/proposal.md`.

## Workflow follow-up

- The PR summary is marked "artwork changed: owner check" and quotes the per-map summary from evidence/maps-rebuild.txt (AGENTS.md map-pack rules). That owner check is the M8 user-verified criterion ("On real maps the labels, extract names and bubbles read correctly"), judged by the user at the M8 close and recorded as unverified until the user reports it. It also settles D7's rotation inference (Streets road names, Reserve's rotated labels).
- After merge: archive, then `/specwright-roadmap close` for M8.
