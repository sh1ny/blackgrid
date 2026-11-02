# Proposal

## Why

This change serves M8 (map labels and popups) as its first change, ahead of `add-extract-labels`. It advances no exit criterion by itself. It unblocks the third criterion: "The new pack version carries tarkov.dev's place labels…, proved by pack and painter tests". `add-location-labels` must build that new pack version, and today a pack cannot be built honestly with the toolchain that is on main.

PR #83 (weekly dependency update, merged 2026-11-02) moved `vector_graphics` 1.2.3 → 1.2.5, `vector_graphics_compiler` 1.3.0 → 1.3.4 and `image` 4.8.0 → 4.12.0. Analyze, the fast tests and CI all passed, because nothing re-runs map preparation. The map-pack machinery treats the old exact versions as gates, so main now states things that are no longer true:

- `tool/maps/pack.dart:51-73` keeps `_pinnedVectorHashes`, a hand-frozen source → `.vec` hash table for compiler 1.3.0. It came from M3 review fix 72b8c0b, which bound each compiled payload to its source. Any compiler bump invalidates it by design.
- `tool/maps/pack.dart:547-554` writes the literals xml 6.6.1, image 4.8.0, compiler 1.3.0 and runtime 1.2.3 into every manifest, whatever is installed.
- `tool/maps/pack.dart:1112` rejects any compiled pack whose manifest does not say `compilerVersion == '1.3.0'`.
- `lib/maps/prepared_map_loader.dart:65-70` refuses any pack whose manifest does not say `runtimeVectorVersion == '1.2.3'`. That compares a label; it does not check that the runtime can decode the file. `openspec/architecture.md:112` documents the same rule, and six test fixtures hard-code it.

The reasons behind these gates still hold. The compiler does not support all SVG, so the M3 and M5 qualifications checked the artwork itself. Recording which tools built a pack is good provenance. The problem is that the record became an exact-version gate, and the hash table only works for one compiler version, so a routine patch release cannot land. The real threat, a `.vec` that does not match its source, is better answered by recompiling the source and comparing, and that is cheap. A probe on 2026-11-02 compiled all 40 committed vector components twice with compiler 1.3.4: 40 of 40 were byte-identical to the committed files, both runs agreed, and both runs took 0.4 s in total.

## What Changes

- **Provenance, not gates.** At build time the manifest records the resolved versions of `xml`, `image`, `vector_graphics_compiler`, `vector_graphics` and `vector_graphics_codec`, read from `pubspec.lock`. No version is written from a string literal, and no validator or loader compares a recorded version.
- **The runtime accepts what it can decode.** The manifest records the vector codec's binary format number, read from the header of the compiled payloads. The loader accepts a pack whose format equals the one the app decodes, and refuses any other format with a message that names both formats. **BREAKING (pack format):** a manifest without that field is refused; only the newly promoted generation ships.
- **Reproduction replaces the hash table.** `_pinnedVectorHashes` is removed. Validation recompiles every vector component from the source the pack carries and compares bytes. Compilation runs twice and the build fails if the two runs differ.
- **The committed pack is rebuilt from itself.** The active generation already carries every input the rebuild reads: the hash-locked source index, the evidence files, and every raster tile it uses, as artwork or as an empty-tile witness. Only 477 tiles under Customs and Reserve SVG floors are missing, and the rebuild never reads them. A rebuild can therefore run from the repository alone, in CI, without the `.dart_tool/maps/m5-raw-20261007-abstract` folder that exists only on the owner's PC.
- **No fallback generation.** The app only ever loads the generation `active.json` names, and that stays so. The old generations `d5a0f9ae…` and `0e059640…` are deleted (git history keeps them), `maps:rebuild` keeps only the active generation from now on, and the validator's and loader's preparation-version-2 paths, which existed only for older generations, are removed. A failed promotion still leaves the current generation untouched.
- **Two commands.**
  - `mise run maps:check` rebuilds the active generation in a temporary folder with the installed toolchain and compares the result with the committed one, ignoring only the recorded toolchain versions. On success it prints `Map pack <id> reproduced byte-identically with <the five versions>`, which a dependency PR can quote. On a difference it fails with a per-map summary and the changed files, and names `mise run maps:rebuild`.
  - `mise run maps:rebuild` does the same rebuild, validates the result, promotes it, rewrites the generated map asset block in `pubspec.yaml`, deletes the superseded generation, and prints a per-map, per-floor summary of changed files so the owner's check of the maps is targeted.
  - A CI step runs `maps:check`. A fast test recompiles the committed vectors, so a compiler change fails `mise run test` as well.
- **Documented upgrade procedure** in AGENTS.md. If `maps:check` fails after a bump, the weekly dependency agent runs `mise run maps:rebuild`, commits the new generation, and marks the PR "artwork changed: owner check". That is a regeneration step like build_runner, not a code change.
- **Executed once now.** `maps:rebuild` runs with compiler 1.3.4, image 4.12.0 and xml 6.6.1, and the result is promoted. The probe predicts identical artwork: only the manifest changes, so the generation gets a new id. If any artwork byte changes, the owner checks the maps in the app before merge.
- **Kept:** frozen artwork inputs, calibration evidence, content-addressed immutable generations, validate-before-promote (a failed promotion keeps the current generation), the atomic `active.json` swap, `acquire`/`rebuild --raw` for future re-acquisition, and the marker icon sync test (`tool/markers/icon_set.dart`), which already follows this pattern.

Out of scope: new artwork or tarkov.dev re-acquisition; location labels (`add-location-labels` builds its pack on top of this); a release. v0.7.0 shipped on Flutter 3.47.6 without the GHSA-frr6 TLS fix (#78); whether to cut 0.7.1 is the owner's call.

## Capabilities

### New Capabilities

- `prepared-map-packs`: how a map pack records the toolchain that built it, how its compiled vectors stay bound to their sources by reproduction, the check that the committed pack is reproducible with the installed toolchain, the one rebuild-and-promote command, and which packs the app accepts at runtime.

### Modified Capabilities

None. No existing spec covers map packs; `map-marker-icons` already requires its own regenerate-and-compare check and is unchanged.

## Impact

- **Code:**
  - `tool/maps/pack.dart`: remove `_pinnedVectorHashes` (keep the in-process cache, filled only by real compilations); compile twice; read toolchain versions from `pubspec.lock`; record and validate the vector codec format; add a source view over a committed generation; add check and refresh operations.
  - `tool/maps/prepare.dart`: `check` and `refresh` operations. Its usage text (lines 46-63) loses "compile is a separate pinned pure-Dart adapter", "Reviewed Interchange compiler/payload identities avoid recompilation", "Existing published preparation-v2 three-map packs remain readable" and "promote retains prior versions".
  - `lib/maps/prepared_map_loader.dart`: the codec-format check and a documented supported-format constant.
  - `mise.toml`: the `maps:check` and `maps:rebuild` tasks.
  - `.github/workflows/gates.yml`: the map pack check step, and `maps:check` in the old-tag release guard; `test/tool/ci/workflow_test.dart` lists the new gate.
  - `pubspec.yaml`: begin/end markers around the generated map asset block, and the new generation's directories.
- **Assets:** a new generation under `assets/maps/versions/<id>/`, and `assets/maps/active.json`. `d5a0f9ae…` and `0e059640…` are deleted. Git stores only the new manifest and tree objects for byte-identical files.
- **Tests:**
  - New fast tests: toolchain provenance, vector determinism, the substituted-payload rejection, the committed-generation precheck, the codec-format constant against the resolved codec, the loader against the real active pack, the pubspec asset block, and recompiling and decoding the committed vectors.
  - The full check runs as its own CI step (`mise run maps:check`), not as a test.
  - Fixtures in `map_controller_test`, `map_controls_test`, `map_scene_test` (x3) and `support/map_widget_harness` become complete preparation-version-3 manifests with `vectorCodecFormat: preparedVectorCodecFormat`, through one shared test helper. The v2 loader fixture becomes a refusal test.
- **Docs:**
  - A new ADR-0033 for reproduction and provenance. It partly supersedes ADR-0005: generation retention, the asset-list source and the loader's version check.
  - `openspec/architecture.md:112` and the ADR index.
  - AGENTS.md: the upgrade procedure.
  - README: the map tools table and the maintenance section.
  - THIRD_PARTY_NOTICES.md:16: drop "pinned" and "qualified separately".
  - `openspec/roadmap.md`: this change becomes M8's first change, and two unplanned entries are added before `add-location-labels`: an artwork refresh command, and live map data from json.tarkov.dev.
- **Dependencies:** none new (`yaml` is already a dev dependency).

## Release Notes

Map packs now record the exact tools that built them, and the app accepts any pack whose vector format it can read instead of one fixed library version. Library updates no longer block map rebuilds. The maps look the same.

### Changed
- Blackgrid loads a map pack when it can decode the pack's vector format, instead of requiring one exact vector_graphics version, so routine library updates (#83) keep maps working. The bundled maps are rebuilt with the current tools and look the same.
