# 0036 - Place labels are pack-owned and floor-assigned at build

- Status: accepted
- Date: 2026-11-07 (change `add-location-labels`)
- Partly supersedes: [ADR-0033](0033-map-packs-proven-by-reproduction.md), preparation version 3 statements (D2, D8) only
- Source: change `add-location-labels` (decisions S5 and D1-D4)

## Context and problem

The native map names markers and extracts but not places (Dorms, Big Red, the mall shops, the Labs rooms). tarkov.dev's interactive metadata already holds 303 place labels on 10 maps, and that file is frozen in the active pack's evidence (`evidence/metadata/maps.json`). The owner chose on 2026-10-30 to use it with a rights note. `add-live-map-data` (ADR-0035) already left location labels in the prepared pack.

Three questions follow. Where do labels live, so that runtime map data and the pack do not both own them? How does a label learn which Blackgrid floors it belongs to, when the manifest's floors carry no height band on most maps? And what does the pack format look like, given that ADR-0033 says only preparation version 3 validates or loads?

## Decision

- **Labels belong to the pack, not to runtime map data (S5).** They come from the frozen interactive metadata through the pack build. Runtime map data (ADR-0035) never touches them: `maps.json` comes from tarkov.dev's site repository, not from the json.tarkov.dev endpoints, and label floors depend on the pack's calibration. Reversal cost: medium.
- **Floor bands come from a reviewed builder table (D1).** `tool/maps/place_labels.dart` holds a const table of map id, Blackgrid floor id and height band, each entry naming the metadata height it is taken from. A fast test resolves every entry against the frozen metadata and fails naming the map, floor and both bands on any difference. The bands do not go into the frozen calibration: check and rebuild read the generation's own frozen calibration, so new calibration could enter only through an artwork refresh that re-downloads sources. Reversal cost: low.
- **Prepared version 4, and only 4 (D2).** The manifest's `preparationVersion` becomes 4 and every map carries a `labels` list, empty when it has none. The builder, `validateCandidate` and the app loader accept only 4, and the validator and loader require the `labels` key on every map: a missing key fails naming the map and is never read as empty. A label is `{text, position: {x, z}, rotation, size, floorIds}` with defaults applied (rotation 0, size 80) and numeric strings converted. Reversal cost: medium.
- **The builder assigns floors; the app tests visibility (D4).** The builder writes `floorIds` for each label: a banded label `[bottom, top]` belongs to every table floor `[min, max)` with `bottom < max && top >= min`, and an unbanded label belongs to the map's base floor. A label that matches no floor fails the build. `validateCandidate` runs the same extraction and assignment on the candidate's own `evidence/metadata/maps.json` and requires equality with each map's manifest `labels`, naming the map on a mismatch, as it does for markers. The app shows a label when any of its floors is visible, and the loader rejects an unknown floor id. Reversal cost: medium.
- **Credit sits in `THIRD_PARTY_NOTICES.md` (D3).** The entry names `the-hideout/tarkov-dev`, `src/data/maps.json`, its MIT licence and copyright line, and the licence text's pack path. The pack's `NOTICE.txt` is unchanged, because check and rebuild copy its bytes verbatim.

## Rejected alternatives

- Downloading labels at runtime: the source is not an endpoint the runtime map data reads, and floors depend on pack calibration.
- Adding the bands to the frozen calibration: it makes the change depend on the network and on unrelated artwork drift.
- Version 3 with an optional `labels` key: a missing key and a map with no labels look the same, so a builder bug could drop every label silently.
- Shipping raw bands to the app and intersecting at runtime: it moves the reviewed table into the runtime format and duplicates the floor model's height logic for a decision that never changes between rebuilds.
- A generated credit section in `NOTICE.txt`: it needs split-and-regenerate logic in three places.

## Consequences

- `maps:check` fails until `maps:rebuild` regenerates the pack, which is the intended ADR-0033 path. No source is re-acquired. The rebuild reports a manifest change for all 13 maps and the owner check applies.
- ADR-0033's statements "the loader checks ... preparation version 3" (D2) and "only preparation version 3 validates or loads" (D8) now read version 4. Everything else in ADR-0033 stays in force: reproduction, exact promotion, the active generation as the only one loaded, no fallback. The ADR-0033 file is left unchanged as the historical record, and this ADR controls only those two statements.
- Older generations do not load. Restoring one means reverting the whole change.
- A changed layer height in the metadata fails the table test, and a label outside every band fails the build, so both stop before publication.
- Metadata-only renewal (ADR-0034) preserves `labels` with the other pack-owned properties. Marker publication (ADR-0035) does not touch them.
- Reversal cost: medium, because the pack format is a contract between builder and app. The app only loads its own bundled pack, so there is no compatibility to keep.

Related: [ADR-0005](0005-native-map-prepared-packs.md), [ADR-0033](0033-map-packs-proven-by-reproduction.md), [ADR-0034](0034-metadata-refresh-preserves-prepared-artwork.md), [ADR-0035](0035-live-map-data.md).
