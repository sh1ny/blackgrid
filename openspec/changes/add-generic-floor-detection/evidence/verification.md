# Verification

## Offline

The prescribed gaming check returned `NOT GAMING` before the rebuild, full offline checks, and focused qualification. No game or Blackgrid app was launched.

- Test first: Reserve did not follow a position into the bunker, a marker assigned by a rectangle remained visible on base, and preparation did not enforce linked, valid, normalized extents. The regression tests failed before implementation on those consumer-visible outcomes.
- Focused qualification: a rehashed candidate whose extents differ from its evidence, or whose v5 calibration retains a direct `heightBand`, is rejected. A verified synthetic v4 pack rebuilds to v5 with only those direct floor bands removed; nested marker evidence survives, the exact artwork calibration gate still rejects other edits, and the migrated generation reproduces.
- Exact transition regression (`test/maps/active_pack_loader_test.dart`): against the frozen baseline, 10,990 of 15,974 markers change effective floor across 33 transition groups on eight maps. All remaining marker assignments are unchanged. Three direct marker/floor pairs are pinned; explicit ownership takes precedence over the spatial result. The before/after replay and frozen ID groups were reproduced independently in design review.
- `mise run analyze`: no issues.
- `mise run test`: 3,610 offline tests passed after the second pre-ship fixes.
- `mise run maps:check`: `Map pack 2cc3a1cf4ab49250e9df8aa67438cbf3a3fcb53cb34288bf9a41c789f99b5bb5 reproduced byte-identically with xml 6.6.1, image 4.13.1, vector_graphics_compiler 1.3.4, vector_graphics 1.3.1, vector_graphics_codec 1.2.0.`
- `openspec validate add-generic-floor-detection --strict` and the proposal's `mise run release-notes -- --check` both passed.
- Pre-ship round 1: the mixed vector map regression first failed because an empty SVG ID hid a valid tile identity. It passed after the fix, together with strengthened checks for diagnostic precedence, resolved base eligibility under exclusive floors, and competing extents on one floor.
- Pre-ship round 2: the synthetic wide-versus-tied selection and the shipped Icebreaker Infirmary/Storage Security overlap passed in the focused suite.
- Pre-ship round 3: the unnamed tile-layer regression first failed on a blank diagnostic, then passed with the tile rendition named; the CLI help now distinguishes v5 validation from offline v4 migration.

## Active pack rebuild

`mise run maps:rebuild` promoted v5 generation `2cc3a1cf4ab49250e9df8aa67438cbf3a3fcb53cb34288bf9a41c789f99b5bb5` from verified, frozen v4 generation `d0f76ede3fcd0b66b52fcd55abbca2465b278e1ade34966bdea5649f4559ce9a`. The rebuild flagged **artwork changed: owner check** because floor manifest values changed; it reported zero changed artwork files on every map. The only changed payload files were `evidence/calibration.json` and `evidence/sources.json`.

| Map | Floor manifest entries changed | Artwork files changed |
| --- | ---: | ---: |
| Factory | 4 | 0 |
| Customs | 5 | 0 |
| Woods | 1 | 0 |
| Shoreline | 4 | 0 |
| Interchange | 3 | 0 |
| The Lab | 3 | 0 |
| Reserve | 6 | 0 |
| Lighthouse | 1 | 0 |
| Streets of Tarkov | 6 | 0 |
| Ground Zero | 4 | 0 |
| Terminal | 1 | 0 |
| Icebreaker | 16 | 0 |
| Labyrinth | 1 | 0 |

## Owner-only checks — unverified

In-raid floor following in Reserve bunkers and the dome, Streets underground and upper floors, Labs, and Icebreaker. Confirm affected marker visibility, including Labs Hangar Gate and Parking Gate. The rebuild's reported maps still require the owner's app check before merge. Offline fixtures do not substitute for these checks.
