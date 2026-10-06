# M3 placement controls and source-parity evidence (U6)

## Scope and status

These records cover the **actual frozen Interchange SVG, Labs tiles and all 16 Icebreaker raster floors**, not the synthetic artwork used by preparation/math unit tests. All three map classes remain in scope. The fixture is `test/fixtures/m3/placement_controls.json`; the executable checks are `test/maps/map_controls_test.dart`. Only Interchange and Labs have valid independent numeric artwork controls. Icebreaker records are kept separately as observed source-parity evidence, frozen marker identities and floor-policy controls.

This correction performed no game/reference/Blackgrid launch, desktop interaction, build, test, lint, formatting run or Git operation. The user's supplied comparisons and confirmations are evidence; no private screenshot/log bytes are committed. Parent integration owns authoritative verification. This document does not claim native rendered-pixel fidelity, packaged operation, a red-before run, or complete independent three-family placement qualification.

**Evidence limit:** The user's side-by-side Blackgrid/tarkov.dev comparison establishes matching C-1 doorway placement, and the user explicitly confirmed Accommodation Lower marker placement is correct. The previous C-1 and three lower CQ artwork labels selected the wrong features; all four numeric assertions are withdrawn, not re-pinned to production output. The upstream Helicopter marker is above the artwork rather than at the drawn landing pad, so its prior landing-pad label is also withdrawn. All five retain original source coordinates and the shared transform. These observations establish source parity, not independent game-coordinate correctness. No independent numeric Icebreaker landmark proof is claimed.

## Portable source identities

The current `assets/maps/active.json` selects preparation-v2 manifest/version **`0e059640559729fcdb8ebac330688d6f40c53a319d02220a5fcfb3b7855fcabf`**, with calibration SHA-256 `5ae8ba1752e63079027e8d01fc9f336dbd3a833bd9245c10be46fc2723c68d3a`. The frozen three-map CLI rebuild completed with `vectorsCompiled: true` in **32.32 seconds**; promotion passed candidate validation in **17.01 seconds**. Generated Flutter declarations cover **105 active asset directories**, including transparent tile witnesses. External source bytes and SHA-256 identities are unchanged. These are preparation receipts, not new native, performance or standalone launch qualification.

Historical inspected manifest SHA-256: `9931c91457f7ddac290d986a18f3f80beb883e4ac847a51e284857f09ae8bb88`. The historical physical-ownership generation is `5d8d74ad211288093815a606d78abd8bbdada580b4a22799b9e384f72e343777`, with calibration SHA-256 `449b8df64e6909476930f9f20e79dadc8f9b3afa0dd1d7a0f8cd0d8a34ea4205`. Its placement/native/performance receipts below remain evidence for that generation, not the current active pack. The loaded-pack tests retain the same frozen source artwork/metadata identities. Current preparation preserves the separately evidenced C-1/Helicopter physical ownership, original Icebreaker coordinates and shared transform.

The historical real-source HTTP-forbidden generation-preservation receipt records two identical rebuilds at **23,468 ms and 21,431 ms**, corrupt-candidate rejection, an unchanged active pointer and **104 discoverable active asset directories**. Its `candidatePromoted: false` describes that experiment, not the current promotion. The current 105-directory declarations include the added witness directory; the historical count is unchanged. See [status](STATUS.md) for the local receipt identities and remaining native/release gates.

| Frozen input | SHA-256 |
| --- | --- |
| `interchange/Interchange.svg` | `31a44112cd5fe33484ce6be7b7dc80d13db6077cba2583a4425ed94c665f47c4` |
| `metadata/maps.json` | `c53a327dcdcff67a49b9fe2d150731edb4c1611dfc2f75db2ce97444dee2ef77` |
| `markers/maps.json` | `62b06a28603ce9091fd57b3fb3e4f9bb1261140843e07cf80767679ad805d99b` |
| `markers/maps_en.json` | `8848c81e16d621be9890b51036b569c2e30432ccc9a9708074cbae06aca0a087` |

Public origins: [Interchange SVG](https://assets.tarkov.dev/maps/svg/Interchange.svg), [immutable SVG revision](https://github.com/the-hideout/tarkov-dev-svg-maps/blob/5a8b6115d1c0cf56f2ebaac1a96fa5ae3074d178/Interchange.svg), [map metadata](https://raw.githubusercontent.com/the-hideout/tarkov-dev/ef62766bbd7ffb294c7184f9b8bfe8ed0f18320e/src/data/maps.json), [game marker snapshot](https://json.tarkov.dev/regular/maps), [name translations](https://json.tarkov.dev/regular/maps_en). Mutable public URLs are provenance, not reproducibility substitutes for the recorded hashes.

### Preparation-v2 candidate validation

The maintenance validator binds each vector component's canonical `sourceSvg`, `compilerSvg` and `.vec` paths to its source identity and order. It re-derives dependency-closed normalized SVGs, compiler SVG/native effects and pinned compiled-payload hashes rather than trusting internally consistent output declarations. The original SVG remains bundled as source evidence.

Raster validation decodes visible source tiles and content-addressed original transparent witnesses under `evidence/tile-alpha/`, checks their frozen source hashes and verifies decoded alpha bounds/emptiness. Transparent witnesses are deduplicated byte-for-byte copies of unchanged original PNGs, not flattened mosaics or new artwork inputs. Candidate crops must be finite, positive and wholly within the original artwork frame. Raster crops remain display-only unions of visible alpha bounds; Interchange retains its full source frame. Neither crop changes persisted pin frames or shared projection.

Preparation-v1 packs lacking transparent witnesses must be rebuilt offline from frozen inputs before this validator can promote them. Preparation is maintenance-only; runtime consumes prepared artwork/marker data and does not invoke acquisition, normalization, compilation or candidate validation. Runtime does not impose a `preparationVersion` gate. The external artwork/source identities, attributions and rights qualifications in [third-party notices](../../../THIRD_PARTY_NOTICES.md) are unchanged; no owner-cleared raster rights or project licence are added.

### Icebreaker semantic identities, not numeric placement oracles

Public pages inspected on 2026-10-06:

- [Exact C-1 key-ID record](https://markschaefer.dev/item_view?id=69bb3f278af9f360ee010a7a): key `69bb3f278af9f360ee010a7a` is **Compartment C-1 keycard**. The frozen public map has exactly one door requiring that key: `locks/3`, X `-5.25`, Z `28.39`, height `35.64`.
- [Boreas public walkthrough](https://tarkov.help/en/quest/boreas): the extraction instructions explicitly put the flare **in the centre of the helipad** and tell the player to wait for the helicopter. Later instructions identify the C-1 door as a **server-room** door.
- [Independent Boreas location description](https://tarkovforge.com/story-guide/boreas): C-1 is on **level 7**, next to the exterior exit, and contains servers, a workstation and shelves. This supports Officers_Deck physical ownership but does not supply an exact numeric doorway point.
- [Exact C-3 key-ID record](https://markschaefer.dev/item_view?id=69bb3f7df94327bc0f0230c9) resolves **Compartment C-3 keycard**, while the walkthrough describes the scientist intercom and medical supplies. This does not identify one exact door among the multiple medical doors in the unlabelled Infirmary artwork.
- [Exact crew-key record](https://markschaefer.dev/item_view?id=69bb3ec9f609db77390b0e1a) resolves **Boreas crew quarters keycard**. Eight frozen doors share it, so the key name alone is insufficient to identify artwork points. Exactly three frozen records have height `27.54`; their IDs, key, coordinates and one-positive-X/two-negative-X source grouping remain useful identity controls. The prior artwork-door matching is withdrawn. Other floors are not qualified by this group.

The fixture records minimal quoted semantic evidence and SHA-256 of each quoted UTF-8 excerpt. These hashes identify the retained excerpts, **not entire mutable web pages or private screenshots**. New public game coordinates were not substituted for the frozen marker snapshot. No reference renderer code was copied.

The fixture also records the exact selected original raster tile paths and SHA-256s. For example, Labs cargo-lift source is [2nd/4/4/11.png](https://assets.tarkov.dev/maps/labs_v4/2nd/4/4/11.png); the retained Icebreaker officers-deck tile is [12_officers_deck/4/8/10.png](https://assets.tarkov.dev/maps/icebreaker/12_officers_deck/4/8/10.png). Source spelling, including the broader Icebreaker `05_storage_ecurity` family, belongs to provenance rather than a new floor identity.

## Independent labelling method

1. Read the original Interchange SVG as an image, with its complete native viewBox `0 0 1127.6852 947.02582`. Recognize rail exits, road/checkpoint approaches and the power-station building/access area from their artwork shapes. These are area controls, not claims that an extraction/switch icon is drawn in the SVG.
2. Independently assemble inspection-only mosaics from original raster tiles. The inspection implementation decoded PNG rows and filters, placed source column/row tiles at `(256 × column, 256 × row)`, and sampled every second original pixel for viewing. It did not import or call production geometry, tile-layout or preparation code. Historical Icebreaker inspection used a horizontal native crop `[1536, 2560)`; its subsequently invalidated numeric labels are no longer retained.
3. Composite transparency over an opaque neutral background **for inspection only**. The image-reading tool's transparent-PNG-to-WebP preview displayed spurious horizontal colour bands; opaque composites removed those preview artefacts. Direct original tiles were also inspected. No flattened mosaic is shipped or used as runtime artwork.
4. For valid Interchange and Labs controls, manually select recognizable artwork locations, record rounded full-frame coordinates and a radial feature-area tolerance, then match semantic identities to frozen public marker entries. Public game coordinates are legitimate inputs, not artwork expectations. These labels were fixed before residual calculations and are unchanged. The five invalid Icebreaker labels are removed rather than replaced by projected points.
5. Convert valid native-image labels to display units only where units differ: Labs uses `175 / 256` because native tiles are 256 pixels and display stride is 175; its full display frame is 2800 rather than 4096. Interchange labels are viewBox units. This conversion is independent of game projection.
6. Calculate residuals against the inspected manifest after valid labels are fixed. The table below records historical metadata-calculated residuals, **not an exercised production test or native screen measurement**. The permanent tests invoke actual shared production geometry and compare Interchange/Labs against those fixed labels when the parent runs them. Icebreaker source-identity checks make no numeric artwork comparison.

The source inspection mosaics stayed under ignored `.dart_tool/` state, with no permanent image/script substitution. The committed fixture contains only public source identities, valid Interchange/Labs numeric labels, textual user-confirmed observations and synthetic adversarial filenames. No raw private screenshot/log bytes or private absolute paths are included.

## Fixed positive placement controls

Coordinates below are **uncropped artwork**. Tolerances are radial distances in the same units as the labels. Labs tolerances convert to display pixels using `175 / 256`. Corner means a recognizable peripheral landmark, not an invented game coordinate for a rectangular image corner.

| Family / landmark | Manual artwork label | Tolerance | Artwork identity / interpretation | Inspected residual (display pixels) |
| --- | --- | --- | --- | --- |
| Interchange Railway Exfil | `(135, 12)` | 35 | Northwest rail exit corridor, Ground_Level | 2.988 |
| Interchange Emercom Checkpoint | `(1005, 775)` | 35 | Southeastern road/checkpoint approach, Ground_Level | 1.907 |
| Interchange Power Station V-Ex | `(985, 82)` | 25 | Northern station access road, Ground_Level | 1.038 |
| Interchange Mall Main Power Switch | `(910, 100)` | 45 | Coarse power-station building-area interior; no drawn switch icon | 36.869 |
| Labs Parking Gate | native `(420, 1420)` | native 90 | Western garage passage, First_Level artwork | 320.785 |
| Labs Hangar Gate | native `(3640, 2240)` | native 90 | Eastern hangar passage, First_Level artwork | 926.204 |
| Labs Main Elevator | native `(2075, 730)` | native 45 | Northern technical lift stub, Technical_Level | 475.112 |
| Labs Medical Block Elevator | native `(1950, 3025)` | native 45 | Southern technical lift stub, Technical_Level | 779.123 |
| Labs Cargo Elevator | native `(1080, 3030)` | native 55 | Southwestern upper-level cargo lift stub, Second_Level | 695.598 |

The nine valid independent controls comprise four Interchange and five Labs records, unchanged in the fixture. It freezes each marker ID, public dataset path, X/Z/height and semantic name. It never uses the production forward/inverse transform to derive expected points. Their tests also compare the shared `gameToScene` result to independently labelled artwork minus the declared crop once, catching missing/double cropping.

### Historical material disagreement: Labs pixel units

All five Labs labels disagreed materially with the historical inspected production geometry; they were not close misses. Its affine results were normalized against native 4096 and then multiplied by display 2800. Manual artwork labels instead show that the frozen affine output is already in the 175-stride display frame. For example, the independently labelled Hangar point is display `(2488.28125, 1531.25)` but the inspected metadata path yields approximately `(1699.13789, 1046.37148)`, a 926.204-pixel radial error.

Preparation now converts the source affine coefficients by `256/175` into native PNG units without changing persisted pin frames/import interpretation. Labels/tolerances were not widened to force a pass. The table's residuals remain historical evidence: the recorded focused parent run on the historical ownership generation passed all five unchanged Labs numeric controls, as well as the four Interchange controls. It does not report new per-landmark residual measurements, so no post-fix residuals are invented here.

## Icebreaker: observed source parity and remaining ambiguity

Earlier source-artwork inspection covered Helipad, Gym_Canteen, Bridge, Control_Room, Officers_Deck, Accommodation_Lower, Storage_Security and Infirmary. That inspection establishes recognizability of those source floors. Parent subsequently visually inspected a native contact sheet of all 16 Icebreaker floors on the historical ownership generation; this establishes historical all-floor render coverage, not current-pack native qualification or independent pixel/fidelity qualification.

The fixture's `observedSourceParity` section retains the five frozen marker identities, original X/Z/height, source paths, key IDs where applicable, source-tile provenance and public semantic evidence. It contains **no artwork coordinate expectations, projected-point labels, residuals or tolerance**. Record IDs are retained as historical identities, not as proof that their former artwork descriptions were correct.

| Frozen source record | Dataset path | X / Z / height | Retained evidence |
| --- | --- | --- | --- |
| Helicopter `extracts:9bf65c4c24d0153f1542a90ddabadb37198ab9ff:0` | `extracts/0` | `0.28 / -66.03 / 22.56` | User's upstream comparison shows the marker above artwork, not on the drawn pad. Public extraction instructions support physical Helipad ownership only. |
| C-1 `locks:f680d37a9e9c4f7b4673a2cd1bedd4a8ed73e104:0` | `locks/3` | `-5.25 / 28.39 / 35.64` | User's side-by-side Blackgrid/tarkov.dev screenshots show the same doorway. Key `69bb3f278af9f360ee010a7a` and level-7 server-room evidence support Officers_Deck ownership. |
| Lower CQ `locks:85d65ba335af0a32a3ce306341ee683ceb62a4a1:0` | `locks/1` | `7.67 / 23.62 / 27.54` | User confirmed Accommodation Lower marker placement correct; frozen CQ-key group identity retained. |
| Lower CQ `locks:d60cab173f0df778af7bfffc834ace99df0a6564:0` | `locks/7` | `-7.67 / 32.63 / 27.54` | Same user confirmation and frozen source group. |
| Lower CQ `locks:21800040e43fff654405f45102118daca363aa90:0` | `locks/0` | `-7.67 / 42.43 / 27.54` | Same user confirmation and frozen source group. |

All three lower CQ records require key `69bb3ec9f609db77390b0e1a`. The existing group regression now uses `observedSourceParity` to check the actual loaded pack's exact three IDs, key/height grouping and one-positive-X/two-negative-X membership. Per-record checks preserve original marker name, source URL/path, X/Z/height and key. None asserts an expected artwork point.

The prior C-1 and lower-CQ manual labels selected the wrong artwork features. Their residuals therefore did not establish a calibration defect. The prior Helicopter label assumed that its original source marker corresponded to the drawn landing-pad centre; the upstream off-artwork observation disproves that assumption. No replacement label is fitted to production output, and no original game coordinates or shared Icebreaker transform are moved to make the discarded labels pass.

**Remaining ambiguity:** C-3's medical door and the different-floor crew record retain null artwork coordinates in `unresolvedMarkerMatches`. Executable tests check their real source identities and prohibit silently promoting them to independent placement expectations. Extraction-volume outline vertices are not artwork points: the activation rectangle is not drawn, and its bottom/top metadata do not independently establish a walk-surface height.

Prepared physical floor ownership is distinct from numeric artwork placement, the raw public dataset's absent floor field and unchanged height bands. The loaded-pack Helicopter test exercises the existing shared `MapFloorSelection.isVisible` paint/hit-eligibility predicate: height-only `22.56` selects Gym_Canteen, but prepared `floorId: Helipad` makes it eligible on Helipad and ineligible on Gym_Canteen. It preserves height `22.56` and activation band `[21.06, 24.06]`. It does not claim an off-artwork marker is currently onscreen or perform a pointer hit against a fictitious landing-pad point. The promoted-pack ownership regressions remain in `test/maps/map_scene_test.dart` and passed in the recorded focused official run on the historical ownership generation.

## Floor truth and uncertainty boundaries

Actual public marker entries have **no explicit floor field** on all three map families. Tests preserve that absence in the original source details. The current pack retains C-1's Officers_Deck and Helicopter's Helipad assignments with independently evidenced physical ownership and adds only the exact Interchange console assignment below. Each retains `source.floorAssignment` provenance; none is a fabricated public floor label. All other prepared source markers remain unassigned. Height-band policy checks use real frozen heights and unchanged bands; neither filenames nor extraction names alone justify physical ownership.

The exact Interchange console is `switches:6b9023f26446d73433823e872e6d69688083beaf:0`, frozen dataset path `5714dbc024597771384a510d/switches/1`. It receives prepared `floorId: Second_Floor` from locked evidence `metadata/maps.json:interchange/interactive/layers/Second_Floor/extents/0` and `markers/maps.json:5714dbc024597771384a510d/switches/1`, bound to the unchanged metadata/marker hashes above. Its position is X `-46.555`, Z `-55.202`, height `37.347`; its full source height volume `[37.187, 37.507]` and outline X `[-46.81, -46.3]`, Z `[-55.517, -54.887]` are contained in the source `Second_Floor` band `[34, 1000]` and mall rectangle. Preparation binds the assignment to that exact identity and complete frozen volume/outline; changed volume evidence is rejected. Original X/Z/height/outline, pins and shared geometry are unchanged. This is reviewed metadata ownership, not an independent numeric artwork control or global floor-inference rule. No ownership is inferred for unreviewed, unknown, out-of-extent or cross-floor records.

- Interchange: heights `23.1857` and `37.347` are real switch inputs but automatic vector floor resolution remains unknown (`null`). The exact console's prepared `Second_Floor` ownership affects its marker visibility, not automatic height selection. Manual `First_Floor` is displayed **2nd Floor**, not Ground_Level; `Second_Floor` is displayed **3rd Floor**. Its conventional-map bands do not enable automatic classification.
- Labs: Main Elevator `-2.81` and Medical Block Elevator `-3.11` are technical-level controls; Cargo Elevator `5.38` is an upper-level control. The first-level transit height `1.18` exercises the base band only: its exact artwork transit location is not separately qualified. Peripheral Parking/Hangar locations are drawn on First_Level artwork even when marker height chooses Second_Level; base-plus-overlay composition preserves that artwork, so artwork ownership is not an explicit marker floor.
- Icebreaker: C-1 door `35.64`, lower crew door `27.54`, Infirmary door `19.46` and Storage/Security door `16.76` exercise the actual local bands and exclusive selection. These height checks prove metadata policy handling. C-1 physical ownership is separately supported by key identity and public level-7 server-room evidence; the user's matching doorway comparison is source parity, not a numeric independent oracle. The medical/security exact door locations remain unqualified.
- The frozen Helicopter height `22.56` still selects **Gym_Canteen** through automatic height policy. Independent extraction instructions nevertheless establish physical **Helipad** ownership. Keep both facts: do not rewrite the public height, widen a band, or claim its physical height is calibrated. Prepared explicit ownership is used for marker visibility and wins over height inference; offline height replay still selects Gym_Canteen at `22.56`.
- Null height is unresolved on every family and can be hidden with the shared unknown-height visibility policy. It is not zero: Icebreaker zero selects Control_Room.

The existing `map_floors_test.dart` owns exhaustive half-open/overlap/gap boundaries. These additional controls attach those rules to the actual loaded pack and real frozen marker heights rather than duplicating synthetic band tests.

## Negative observations and accepted scans

Fixture filenames such as `Labs_Second_Level.png` and `icebreaker_Helipad_22.56.log` are invented adversarial names, **not private evidence files**. They carry null map/floor identity; even an independently known scalar height `35.64` cannot choose a map.

Tests pass those filenames through the real map-controller identity boundary. They must remain unavailable artwork, have no resolved floor or scene, expose no markers and reject offline height application. A separate known-map replay applies Officers_Deck height and then null height while preserving its last known selection.

No accepted-scan assertion is made against a disconnected constant state object. The genuine app/services regressions in `test/ui/map_screen_test.dart` and `test/maps/map_viewport_test.dart` exercise map/pin/navigation operations and assert `h.services.scans.hasAcceptedScan == false`; `test/ui/scanner_screen_test.dart` likewise exercises the connected manual inspection flow. Parent's recorded focused official run on the historical ownership generation passed those regressions. This is not a claim that a live-game scan pipeline was exercised.

## Primary creator calibration avenue

The frozen TarkovBOT creator homepage links to the actual [Icebreaker interactive artwork page](https://tarkovbot.eu/tools/interactive-maps/icebreaker). Its public HTML links to [`interactive_maps_icebreaker.js`](https://tarkovbot.eu/main/js/interactive_maps_icebreaker.js) and [`interactive_maps.css`](https://tarkovbot.eu/main/css/interactive_maps.css).

Those linked assets expose an image-layer viewer, not a game-coordinate map: eleven numbered main-floor images and five engine-room images, opacity selection, screen pan/zoom, and a 1024-square image container with `object-fit: contain`. The script's image roots are `https://tarkovbot.eu/main/img/maps/icebreaker/` and its `engine_room/` child. The inspected creator images contain the same unlabelled ship-floor artwork rather than game-position markers.

No game X/Z transform, game bounds, keyed-marker coordinate dataset or independently labelled calibration anchors are exposed by this reachable creator page and its linked viewer assets. The container's screen matrix and CSS sizing are not an author game-coordinate calibration. No reference code was copied, no guessed endpoints were probed, and no Discord/email contact was attempted. This avenue supplies artwork provenance/layout only; it supplies no independent numeric Icebreaker placement proof and does not justify inventing replacement artwork labels.

## Historical parent verification and remaining qualification

No checks were run by this documentation correction, and no red-before claim is made. The checks, native observations and performance measurements below predate the current preparation-v2 pack. No final current-pack suite counts, native/performance results or standalone launch qualification are recorded here. Parent promoted the historical physical-ownership pack and exercised these ten suites through the official Dart MCP route. The recorded focused result is **122 passed, zero failures, errors or skips**, terminal `success: true`, **167.920 seconds**, in `.dart_tool/owned_verification/m3-final-floor-ownership-regressions-20261006.jsonl`:

- `test/maps/map_controls_test.dart` — unchanged Interchange/Labs independent controls, Icebreaker frozen source identities and ownership-precedence policy.
- `test/maps/map_scene_test.dart` — existing source-height/band and physical-ownership regressions.
- `test/maps/map_geometry_test.dart` — geometry and immutable pin-frame/import-conversion regressions.
- `test/maps/map_floors_test.dart` — exhaustive height-band and floor-selection boundaries.
- `test/maps/map_controller_test.dart` — actual shared controller and pin behavior.
- `test/data/legacy_import_test.dart` — existing legacy import/pin regressions.
- `test/maps/map_preparation_test.dart` — coherent preparation/provenance and promotion regressions.
- `test/maps/map_viewport_test.dart`, `test/ui/map_screen_test.dart` and `test/ui/scanner_screen_test.dart` — native viewport and connected accepted-scan safety regressions.

The tested historical ownership generation is `5d8d74ad211288093815a606d78abd8bbdada580b4a22799b9e384f72e343777`; this focused pass establishes valid Interchange/Labs numeric controls and Icebreaker source-identity/floor-policy behavior for that generation, not current-pack verification, new residual measurements or independent three-family landmark qualification. Use the user's Icebreaker confirmations and upstream Helicopter off-artwork observation as source-parity evidence, not fabricated independent numeric game correctness. Do not move markers or the shared transform to satisfy discarded labels.

**Requirement mismatch retained openly:** the existing plan's U6 approach requires independently labelled placement comparisons across every selected family. Independent numeric Icebreaker artwork controls are currently absent, and C-3/other ambiguous matches remain unresolved. Source parity and physical ownership cannot silently replace that criterion. For U2/U7, parent exercised all 16 Icebreaker floors on the historical ownership generation through native accessibility actions, recorded captures in the ignored `.dart_tool/owned_verification/m3-final-floor-captures-20261006.json` inventory and visually inspected their contact sheet. Historical native all-floor render coverage is observed; current-pack native qualification and independent pixel/fidelity qualification are not established by that receipt. The earlier C-1/Lower disagreement and a required global recalibration are invalidated premises, not current gates.

The historical attributed five-cycle run on that ownership pack, viewport **1097.8 × 496.0** and DPR **1.0** records **1,824 frames**, aggregate build p95 **2.849 ms**, raster p95 **14.181 ms** and warm floor-switch p95 **46.023 ms**. Per-map raster p95 is **14.727 ms Interchange**, **10.326 ms Labs** and **10.335 ms Icebreaker**. All fixed predicates pass in this run. Managed accounting remains stable after warmup at **178,796,824 bytes / 690 resources**, and `acceptedScan: false`. Only timing batching/attribution changed; no rendering fix was made. The historical baseline's build p95 **4.297 ms**, raster p95 **35.646 ms** and warm floor-switch p95 **66.426 ms** remain recorded, including its failure of the unchanged **≤16.7 ms raster budget**. Run-to-run variability is unresolved; no cured cause or stable multi-run performance is claimed. See [status](STATUS.md) for receipt identities and separate process-memory measurements.

Recorded historical Windows screenshots document Interchange semantic **Wooden crate** selection at X **277.738861**, Z **-439.822083**, height **21.689**, then zoom and real pointer pan. The background attempt was a no-op; pointer takeover succeeded. Labs exercised all three floor choices and keyboard selection via **Markers browser → Tab** to focus **Medical Block Elevator → Enter**, yielding X **-112.3**, Z **-344.04**, height **-3.11**. These observations establish bounded native interaction coverage, not new independent placement controls or rendered-pixel fidelity. Accepted scan remained unavailable throughout.

The later historical complete official offline suite passed **518 tests**, with zero failures, errors or skips, and whole-project official analysis reported **No errors**. The production Windows Release build and all **718** packaged active-output hashes passed; the outside-checkout package was staged but not launched. These checks do not establish independent Icebreaker numeric placement or full native qualification.

The user's subsequent instruction, "Pass on all the gates and move on. I can't test, until we have map tracking capabilities. My interactions were good.", explicitly waives the remaining verification gates **for this delivery, not as passed checks**. Independent Icebreaker numeric placement/pixel fidelity, the remaining interaction/resolution/DPI matrix, repeatable performance and retained-memory qualification, and standalone offline launch/cold-restart/import confirmation remain unverified. The source-parity observations and unresolved correspondences above are unchanged; no map tracking is added. Implementation and simplification are complete; the valid complete ce-work return and user waiver allow review/shipping under the [plan's verification exception](../../plans/2026-10-06-1026-feat-m3-native-map-proof-plan.md#user-approved-verification-exception-2026-10-06) and [current status](STATUS.md). Broader M3 review is in progress, followed by any required fixes and private feature-branch PR delivery; the historical simplified Release package was staged and hash-verified, not launched, before the current preparation-v2 promotion. No merge or visibility change is authorized, and no focus-taking UI action or new application launch is required.
