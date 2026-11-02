# Tasks

Skills for every Dart group (AGENTS.md "Dart and Flutter code"): `dart-use-pattern-matching`, `dart-add-unit-test`, `dart-write-documentation` and `dart-run-static-analysis`. Group 3 also uses `flutter-add-widget-test` for the map widget fixtures.

Rules for every group:

**Test layering**
- Pure rules are fast unit tests on small strings or byte buffers: the lock parsing, the payload header, the determinism branch with a fake encoder, the committed-generation closure on a tiny synthetic generation folder, and the pubspec marker block.
- Anything that needs a complete pack build goes into `test/maps/map_preparation_qualification_test.dart` (`@Tags(['qualification'])`). It uses the existing all-map synthetic `MapPreparationFixtures` (`test/support/map_preparation_fixtures.dart`) and never the 67 MB committed pack.
- Only group 6's tests read the committed active generation.

**Fakes and waits**
- Fakes are hand-written and injected through parameters (the `VectorEncoder` seam, the `toolchain` map, the lock text).
- There are no sleeps. There is no network: nothing in this change calls `acquire`.

**Game safety and versions**
- The game is never launched or touched. No task launches the app.
- `BLACKGRID_NO_GAMES_RUNNING` is never set locally.
- Verify with `mise run analyze` and `mise run test`. Run the map qualification file directly with `mise exec -- flutter test --tags qualification test/maps/map_preparation_qualification_test.dart`; it is offline and touches no capture library. CI runs the full `ci:qualification`.

**Review notes (binding, from review.md rounds 1 and 2)**
- **N1.** Only `_expectedVectorHash` (validation, real encoder) writes `_compiledVectorHashes`; `_compile` never does. Both `rebuildCandidate` and `compileCandidate` write `toolchain` and `vectorCodecFormat`. The design's State & Ownership rows that say otherwise are superseded by D1-D3.
- **N2.** The "Mismatched payload header" test rewrites the manifest's output hash for the corrupted `.vec`, as the "Substituted payload" test does, so the header check, not the output-hash closure, is what fails.
- **N3.** The release guard in `gates.yml` gets its own message for a missing `maps:check`: `"$env:RELEASE_TAG predates the map pack check"`. It does not reuse "predates release publishing".
- **N4 (round 2).** `packChangeReport` reports manifest value differences (floor, map, pack groups), not only files. The owner check fires when anything but `toolchain` differs.
- **N5 (round 2).** The leftover precheck runs first in `check` and `refresh`. Pruning deletes only 64-hex generation ids other than the active one.
- **N6 (round 2).** The loader checks in order: schema, preparation version, vector format. A non-int `vectorCodecFormat` counts as not recorded.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| prepared-map-packs → A pack records the toolchain that built it | Build records the installed versions | test/maps/map_preparation_qualification_test.dart | rebuild records the given toolchain and no fixed versions | green |
| prepared-map-packs → A pack records the toolchain that built it | A package is not resolved | test/maps/map_toolchain_test.dart | lock without vector_graphics_codec names the package | green |
| prepared-map-packs → A pack records the toolchain that built it | A package is not resolved | test/maps/map_toolchain_test.dart | prepare refresh with an incomplete lock fails before creating a candidate | green |
| prepared-map-packs → A pack records the toolchain that built it | An older recorded version still validates | test/maps/map_preparation_qualification_test.dart | pack recording compiler 1.3.0 validates when vectors reproduce | green |
| prepared-map-packs → A pack records the toolchain that built it | Separate compile step records the compiling toolchain | test/maps/map_preparation_qualification_test.dart | compile step replaces the normalize-time toolchain | green |
| prepared-map-packs → Compiled vectors are deterministic | Stable compiler | test/maps/map_toolchain_test.dart | stable encoder output is written | green |
| prepared-map-packs → Compiled vectors are deterministic | Unstable compiler output | test/maps/map_toolchain_test.dart | differing second encoding fails naming the vec path | green |
| prepared-map-packs → Compiled vectors are deterministic | Unstable compiler output | test/maps/map_preparation_qualification_test.dart | unstable encoder leaves the candidate without a manifest | green |
| prepared-map-packs → Every compiled vector is bound to its source by recompilation | Unmodified pack | test/maps/map_preparation_qualification_test.dart | two offline all-map rebuilds are byte-identical and keep original crop/frame units (existing, re-run without the hash table) | green |
| prepared-map-packs → Every compiled vector is bound to its source by recompilation | Substituted payload | test/maps/map_preparation_qualification_test.dart | substituted vec with matching output hash fails naming the path | green |
| prepared-map-packs → A pack records and is checked against its vector format | Consistent format | test/maps/map_toolchain_test.dart | payload header returns format byte after the magic number | green |
| prepared-map-packs → A pack records and is checked against its vector format | Consistent format | test/maps/map_preparation_qualification_test.dart | compiled pack records vectorCodecFormat 1 | green |
| prepared-map-packs → A pack records and is checked against its vector format | Mismatched payload header | test/maps/map_preparation_qualification_test.dart | vec header format 2 against record 1 fails naming payload and both formats | green |
| prepared-map-packs → A pack records and is checked against its vector format | Missing format record | test/maps/map_preparation_qualification_test.dart | compiled pack without vectorCodecFormat fails as not recorded | green |
| prepared-map-packs → A pack records and is checked against its vector format | Uncompiled candidate | test/maps/map_preparation_qualification_test.dart | normalized candidate has no format record and cannot be promoted | green |
| prepared-map-packs → The app accepts packs in the vector format it decodes | Supported format with other recorded versions | test/maps/map_scene_test.dart | loader accepts supported format whatever toolchain is recorded | green |
| prepared-map-packs → The app accepts packs in the vector format it decodes | Unsupported format | test/maps/map_scene_test.dart | loader refuses format 2 naming both formats | green |
| prepared-map-packs → The app accepts packs in the vector format it decodes | Unsupported format | test/maps/map_controller_test.dart | unsupported pack format surfaces as the map load error | green |
| prepared-map-packs → The app accepts packs in the vector format it decodes | No format record | test/maps/map_scene_test.dart | loader refuses a manifest without a vector format | green |
| prepared-map-packs → The app's supported vector format matches its vector runtime | Codec unchanged | test/maps/vector_format_test.dart | resolved codec writes and decodes the supported format | green |
| prepared-map-packs → The app's supported vector format matches its vector runtime | Codec format changes | test/maps/vector_format_test.dart | format mismatch message names both formats and maps:rebuild | green |
| prepared-map-packs → The committed pack is checked for reproducibility | Toolchain update with identical output | test/maps/map_change_report_test.dart | success line names the generation and the five versions | green |
| prepared-map-packs → The committed pack is checked for reproducibility | Toolchain update with identical output | test/maps/map_preparation_qualification_test.dart | check passes when only the toolchain record differs and prints the reproduced line | green |
| prepared-map-packs → The committed pack is checked for reproducibility | Toolchain update that changes output | test/maps/map_change_report_test.dart | changed vec is counted under its map and floor | green |
| prepared-map-packs → The committed pack is checked for reproducibility | Toolchain update that changes output | test/maps/map_preparation_qualification_test.dart | check fails with the per-map summary listing a vec built by another compiler and names maps:rebuild | green |
| prepared-map-packs → The committed pack is checked for reproducibility | A needed input is not carried | test/maps/map_generation_inputs_test.dart | reading an uncarried source names its path | green |
| prepared-map-packs → The committed pack is checked for reproducibility | Committed evidence was edited | test/maps/map_generation_inputs_test.dart | edited evidence fails naming the file | green |
| prepared-map-packs → The committed pack is checked for reproducibility | Committed output was edited | test/maps/map_generation_inputs_test.dart | edited or extra generation file fails naming it | green |
| prepared-map-packs → The committed pack is checked for reproducibility | Manifest no longer matches its generation id | test/maps/map_generation_inputs_test.dart | manifest hash differing from the id fails naming the id | green |
| prepared-map-packs → One command rebuilds and promotes the committed pack | Only provenance changes | test/maps/map_change_report_test.dart | toolchain-only difference reports nothing and needs no owner check | green |
| prepared-map-packs → One command rebuilds and promotes the committed pack | Only provenance changes | test/maps/map_preparation_qualification_test.dart | refresh with identical artwork promotes a new generation, rewrites the asset block and prunes the old generation | green |
| prepared-map-packs → One command rebuilds and promotes the committed pack | Manifest values change without a file change | test/maps/map_change_report_test.dart | displayCrop-only difference reports the map and needs the owner check | green |
| prepared-map-packs → One command rebuilds and promotes the committed pack | Manifest values change without a file change | test/maps/map_change_report_test.dart | tile empty flag difference marks its floor; witness paths go to other | green |
| prepared-map-packs → One command rebuilds and promotes the committed pack | Artwork bytes change | test/maps/map_change_report_test.dart | one vec and two tiles print woods Ground_Level 1 and thelab First_Level 2 | green |
| prepared-map-packs → One command rebuilds and promotes the committed pack | Artwork bytes change | test/maps/map_preparation_qualification_test.dart | refresh reports changed artwork and the owner check | green |
| prepared-map-packs → One command rebuilds and promotes the committed pack | Validation fails | test/maps/map_preparation_qualification_test.dart | refresh with an invalid candidate deletes nothing and keeps active, pubspec and the named candidate | green |
| prepared-map-packs → One command rebuilds and promotes the committed pack | Asset declaration markers missing | test/maps/map_pack_assets_block_test.dart | missing duplicated or reversed markers fail naming the marker | green |
| prepared-map-packs → One command rebuilds and promotes the committed pack | Interrupted earlier promotion | test/maps/map_generation_inputs_test.dart | leftover precheck names a staging folder of any id or active.next.json | green |
| prepared-map-packs → One command rebuilds and promotes the committed pack | Interrupted earlier promotion | test/maps/map_preparation_qualification_test.dart | refresh with a leftover fails before rebuilding and changes nothing | green |
| prepared-map-packs → One command rebuilds and promotes the committed pack | Only provenance changes | test/maps/map_generation_inputs_test.dart | pruning deletes only 64-hex non-active generations | green |
| prepared-map-packs → Only the active generation is ever used | Active generation loads | test/maps/map_scene_test.dart | loader reads only active.json and the generation it names | green |
| prepared-map-packs → Only the active generation is ever used | Active generation is broken | test/maps/map_scene_test.dart | broken active manifest is a load error and no other generation is read | green |
| prepared-map-packs → Only the active generation is ever used | Active generation is broken | test/maps/map_controller_test.dart | broken active pack surfaces as the map load error | green |
| prepared-map-packs → Only the active generation is ever used | Older preparation version | test/maps/map_scene_test.dart | loader refuses preparation version 2 naming it | green |
| prepared-map-packs → Only the active generation is ever used | Older preparation version | test/maps/map_preparation_qualification_test.dart | validator refuses preparation version 2 | green |

The committed pack itself (group 6) is also covered by extra tests: `test/maps/active_pack_vectors_test.dart` (recompiles, decodes and checks the header of every committed `.vec`), `test/maps/active_pack_loader_test.dart` (the real loader on the real active pack) and the asset-block test against the active manifest. These are not scenario rows.

## 1. Decision record

- [x] 1.1 Write `docs/adr/0033-map-packs-proven-by-reproduction.md` (MADR short: Status accepted, Date, Context, Decision, Consequences). It covers toolchain provenance from `pubspec.lock`, the `vectorCodecFormat` acceptance contract, recompile-and-compare replacing the frozen hash table, the committed generation as its own input with the closure precheck, the `maps:check` CI gate, and the rule that a bump with identical bytes needs no rebuild. It also covers no fallback generation (only the active generation is loaded or kept; preparation version 3 only; rollback is a git revert) and the upgrade procedure. Its header says `Supersedes: 0005 (…)`, three statements only, following ADR-0029: generation retention, the asset-list source (`prepare.dart assets` → the `refresh`-owned marked block), and the loader's "structure and versions" check. Write it without naming or linking any other companion app. Verify: the file exists and links ADR-0005, ADR-0023 and ADR-0024.
- [x] 1.2 Update `openspec/architecture.md`: the ADR index row for 0033 (Supersedes "0005 (those three statements only)"), and ADR-0005's row ending "Partly superseded by 0033: generation retention, the asset-list source and the loader's version check only"; the prepared-map-pack contract (line 112: `vectorsCompiled` and `vectorCodecFormat == preparedVectorCodecFormat`, no version label); the map tooling row (77: `check`/`refresh`); the active-generation state row (105: `refresh` or `promote`); and the CI gate description (`maps:check`). Verify: `grep -n "1.2.3\|runtimeVectorVersion" openspec/architecture.md` returns nothing.

## 2. Build: provenance, determinism, format record, no hash table

- [x] 2.1 Write failing fast tests in `test/maps/map_toolchain_test.dart` for `toolchainFromLock` (complete lock → five versions; lock without `vector_graphics_codec` → `FormatException` naming it), `vectorPayloadFormat` (magic `62 2d 88 00` + format byte → returns it; wrong magic or under 5 bytes → throws naming the path), and the compile determinism branch (`VectorEncoder` fake stable → bytes written; fake differing on the second call → throws naming the `.vec` path). Verify they fail because the functions do not exist yet.
- [x] 2.2 Implement in `tool/maps/pack.dart`:
  - `toolchainFromLock`, `vectorPayloadFormat`, the `VectorEncoder` typedef and the `encode` parameter on `rebuildCandidate`, `compileCandidate` and `_compile` (defaulting to `_encodeVector`);
  - compile-twice in `_compile`;
  - delete `_pinnedVectorHashes`; only `_expectedVectorHash` fills `_compiledVectorHashes` (N1);
  - a required `toolchain` parameter, written as manifest `toolchain` by `rebuildCandidate` and replaced by `compileCandidate`;
  - `vectorCodecFormat` written by whichever step compiles;
  - remove `dependencies`, `compilerVersion` and `runtimeVectorVersion`;
  - validation order for compiled packs: the record is an int → every header matches it → recompile comparison. Drop the `compilerVersion == '1.3.0'` condition;
  - D8: `validateCandidate` accepts only preparation version 3. Remove the `version == 2` branch (`pack.dart:901-908`) and make the `version == 3` conditionals (`909-927`, `980`, `1005`, `1017`) unconditional.

  Verify the 2.1 tests turn green; flip their rows.
- [x] 2.3 Update `test/support/map_preparation_fixtures.dart` and the existing callers in `test/maps/map_preparation_test.dart` and `test/maps/map_preparation_qualification_test.dart` to pass a fixed `toolchain` map. Then add the qualification tests from the test map's build rows: records the toolchain, older recorded version validates, compile step replaces the toolchain, unstable encoder leaves no manifest, substituted vec (output hash updated), records format 1, header format 2 with the hash updated (N2), missing record, uncompiled candidate not promotable, validator refuses preparation version 2. Rebuild the existing "failed new generation preserves asset discovery for an older frozen floor calibration" test (~748-880) so its older generation is a full preparation-version-3 pack with an altered frozen calibration, keeping its assertions. Verify: the map qualification file passes; flip the rows green.
- [x] 2.4 `tool/maps/prepare.dart`: read `pubspec.lock` once with `toolchainFromLock` before any write, for `rebuild`, `normalize` and `compile`. Update the usage text (lines 46-63): drop "compile is a separate pinned pure-Dart adapter", "Reviewed Interchange compiler/payload identities avoid recompilation", "Existing published preparation-v2 three-map packs remain readable" and "promote retains prior versions"; say validation recompiles every vector, only preparation version 3 with `vectorCodecFormat` validates, and `refresh` keeps only the active generation. Update THIRD_PARTY_NOTICES.md:16 so it says the preparation dependencies are the versions resolved in `pubspec.lock` and recorded in each pack's manifest, and drop "qualified separately before its runtime commitment". Verify: `mise run analyze`; `grep -n "1\.3\.0\|1\.2\.3\|4\.8\.0" tool/maps` returns nothing.

## 3. Runtime: accept by vector format

- [x] 3.1 Write failing tests: `test/maps/vector_format_test.dart` (the resolved compiler's tiny-SVG payload has format `preparedVectorCodecFormat` and `VectorGraphicsCodec().decode(bytes, null)` accepts it; `unsupportedVectorFormatMessage(2, 1)` names 2, 1 and `mise run maps:rebuild`), the loader rows in `test/maps/map_scene_test.dart` (format 1 with toolchain compiler 9.9.9 loads; format 2 refused naming both; missing or non-int record refused; preparation version 2 refused naming it, which replaces the v2 fixture at `map_scene_test.dart:129`; the loader requests only `active.json` and the generation it names; a broken active manifest is a load error with no other generation requested), and the controller rows in `test/maps/map_controller_test.dart` (format 2 and a broken active pack become the map load error text). Verify they fail on the current `runtimeVectorVersion` check.
- [x] 3.2 Implement in `lib/maps/prepared_map_loader.dart`: a documented `const int preparedVectorCodecFormat = 1`, `unsupportedVectorFormatMessage`, and the `vectorsCompiled` + `vectorCodecFormat` check replacing `runtimeVectorVersion == '1.2.3'`, with `///` docs saying why it compares a format rather than a version. D8: remove the lenient non-v3 path (`prepared_map_loader.dart:80`); require `preparationVersion == 3`, failing with `'Unsupported prepared map version <v>.'`; check order per N6. Add one shared test helper (in `test/support/`) that builds a complete v3 manifest: the maps a test cares about, padded with minimal maps for the remaining supported ids, `outputs` derived from asset paths, and `vectorCodecFormat: preparedVectorCodecFormat`. Move the fixtures in `map_controller_test`, `map_controls_test`, `map_scene_test` and `test/support/map_widget_harness.dart` to it. Verify: `mise run test` passes, `grep -rn "runtimeVectorVersion" lib test` returns nothing, and the rows are flipped green.

## 4. Check: committed generation as input, closure precheck, CI gate

- [x] 4.1 Write failing fast tests in `test/maps/map_generation_inputs_test.dart` on a tiny synthetic generation folder (a few small files, a hand-built `sources.json` and manifest, no real maps):
  - `verifyCommittedGeneration`: manifest hash ≠ id → names the id; an edited output, an extra file or a missing file → names the path; a consistent folder passes;
  - `FrozenInputs.fromGeneration`: edited evidence → names the file; a tile source carried only by hash resolves to its artwork or witness bytes; an uncarried tile → `bytes()` names the path and `rebuild --raw`.

  Verify they fail for the missing functions.
- [x] 4.2 Implement in `tool/maps/pack.dart`:
  - extract the output-closure part of `validateCandidate` (`pack.dart:851-885`) into a shared function used by both validation and `verifyCommittedGeneration`;
  - `FrozenInputs.fromGeneration`; `rebuildCandidate` takes `FrozenInputs`, and `rebuild --raw` and the fixtures pass `FrozenInputs.open`;
  - the leftover precheck (N5): any `active.next.json` or `versions/.*.staging` fails with `Interrupted map pack promotion left <path>; inspect and remove it, then rerun.`, before anything else;
  - `packChangeReport(committed, rebuilt)` per D4 (files and manifest values, grouped by map and floor, `other` and `pack` groups, `toolchain` ignored), returning whether anything but `toolchain` differs; and the success line `Map pack <id> reproduced byte-identically with xml <v>, image <v>, vector_graphics_compiler <v>, vector_graphics <v>, vector_graphics_codec <v>.`;
  - `_rebuildActive` and `checkActive`: precheck, rebuild into a system-temp folder, compare canonical manifests without `toolchain`. On success print the success line. On a difference print the report, the differing paths and keys, and end with `Map pack is not reproducible with the installed toolchain. Run: mise run maps:rebuild`. Always delete the temp folder.

  Add `prepare.dart check --packs`. Also write the fast tests in `test/maps/map_change_report_test.dart` (on small hand-built manifests) and the leftover precheck tests in `map_generation_inputs_test.dart` first, red. Verify the 4.1 tests and these turn green.
- [x] 4.3 Add the qualification tests for the check rows, on "committed" fixture generations in a temp packs folder:
  - toolchain-only difference: promote a fixture built with toolchain compiler `1.3.0`, then check with `1.3.4` → passes, prints the reproduced line with `1.3.4`, and leaves the packs folder byte-identical;
  - "built by another compiler": assemble a generation directly, not through `promoteCandidate`, which would recompile and refuse it. Copy a fixture candidate, overwrite one `.vec` with another component's valid `.vec` bytes, update that output hash in the manifest, name the folder by the new manifest hash and point `active.json` at it. The closure precheck passes, and the check fails with that floor's summary line, listing that path and naming `mise run maps:rebuild`.

  Verify: the map qualification file passes; flip the rows green.
- [x] 4.4 Add the `maps:check` task to `mise.toml`. Add the unconditional `Map pack check` step (`mise run maps:check`) to `.github/workflows/gates.yml` after `Test` and before `Build Release`. Add a `maps:check` presence check with its own message to the release guard (N3). Add `mise run maps:check` to the ordered `gates` list and a guard assertion in `test/tool/ci/workflow_test.dart`. Update the README map tools table and the maintenance section. Verify: `mise run test` passes, including the workflow tests.

## 5. Refresh: one command, generated asset block, upgrade procedure

- [x] 5.1 Write failing fast tests in `test/maps/map_pack_assets_block_test.dart` for the marker block: one begin and one end in order → the lines between are replaced exactly and everything else is unchanged; missing, duplicated or reversed markers → an error naming the marker. Verify they fail.
- [x] 5.2 Implement `refresh` in `tool/maps/pack.dart`/`prepare.dart`, in D4's order:
  - the leftover precheck and the marker check, before any write;
  - `verifyCommittedGeneration`, then rebuild into `.dart_tool/maps/refresh-<UTC>/`, then validate;
  - print `packChangeReport`, ending with `Artwork changed: the owner must check the maps listed above in the app before merge.` when anything but `toolchain` differs;
  - `promoteCandidate`, then rewrite the block through a temp file and a rename;
  - prune: delete every `versions/<64-hex>` folder other than the new active id, never a staging folder (a fast test on a temp folder covers the name rule);
  - delete the candidate only after success; on failure keep it and name it.

  Add the `maps:rebuild` task to `mise.toml`. Verify the 5.1 tests turn green.
- [x] 5.3 Add the qualification tests for the refresh rows: identical artwork → a new generation, `active.json` moved, the block rewritten, the old generation deleted, and the report says only provenance changed with no owner check; changed artwork (the 4.3 setup) → the per-floor summary, the path and the owner check; invalid candidate → nothing promoted or deleted, active, pubspec and the kept candidate named; a leftover staging folder of another id or `active.next.json` → fails before rebuilding, nothing changes. Also add a `prepare.dart`-level test that `refresh` with a lock lacking `vector_graphics_codec` fails before `.dart_tool/maps/refresh-*` exists. Verify: the map qualification file passes; flip the rows green.
- [x] 5.4 Write the upgrade procedure in AGENTS.md, in a new "Map pack toolchain upgrades" section the weekly dependency agent reads:
  - after changing `vector_graphics`, `vector_graphics_compiler`, `vector_graphics_codec`, `image` or `xml`, run `mise run test` and `mise run maps:check`;
  - if the check passes, nothing else is needed;
  - if it passes, the PR may quote its `Map pack <id> reproduced byte-identically with …` line as proof;
  - if it fails, run `mise run maps:rebuild` and commit the new generation together with `assets/maps/active.json`, `pubspec.yaml` and the deleted old generation. This is a regeneration step like build_runner, not a code change;
  - if the rebuild prints `Artwork changed`, mark the PR "artwork changed: owner check" in its summary and include the per-map summary, so the owner checks only those maps in the app before merge (recorded as unverified until they report it);
  - a codec-format test failure also needs `preparedVectorCodecFormat` updated in the same change.

  Verify: the section exists and names both mise tasks.

## 6. Run it once on main's toolchain

- [x] 6.1 Wrap the existing map asset lines in `pubspec.yaml` (currently lines 42-247) with the begin/end markers, without changing the lines. Verify: `mise run analyze` passes and `flutter pub get` reports no asset change.
- [x] 6.2 One-time cross-check, local only, while the raw generation exists:
  - run `mise exec -- dart run tool/maps/prepare.dart rebuild --raw .dart_tool/maps/m5-raw-20261007-abstract --candidate .dart_tool/maps/crosscheck-raw-<UTC>`;
  - run the generation-backed rebuild of `d5a0f9ae…` into another scratch folder (`check` keeps nothing, so call `_rebuildActive` through a scratch script under `.dart_tool/`, or use `refresh` on a scratch copy of `assets/maps`);
  - compare the two canonical manifests.

  Record in this task whether they are identical. Expected: identical. If not, stop and report the differing keys to the owner before promoting.

  **Result (2026-11-02):** identical. The raw rebuild and the `d5a0f9ae…`-backed rebuild produced the same canonical manifest with the installed toolchain.
- [x] 6.3 Run `mise run maps:rebuild` on main's toolchain (compiler 1.3.4, image 4.12.0, xml 6.6.1, vector_graphics 1.2.5, codec 1.1.13). Record the new generation id and the report. Expected: only provenance changed, so only `manifest.json` differs from `d5a0f9ae…`. If the report shows anything else, copy its per-map summary here and add a user check: the owner checks those maps in the app before merge. Verify: `mise run maps:check` exits 0 and prints the reproduced line; `git status` shows the new generation folder, `assets/maps/active.json`, the `pubspec.yaml` block, and `d5a0f9ae…` and `0e059640…` deleted; `assets/maps/versions/` holds exactly one folder.

  **Result (2026-11-02):** new generation `ed26414539f458929025f4ef2c3413d3457c7b3e5b9f2e2adfb4dc20c24bba5f`; `d5a0f9ae…` and `0e059640…` deleted. All 1321 output files are byte-identical to `d5a0f9ae…`, and every map and floor value is unchanged. The only differences are top-level manifest keys from this change's format migration: `compilerVersion`, `dependencies` and `runtimeVectorVersion` removed, `toolchain` and `vectorCodecFormat: 1` added. The report printed no map or floor line, only the `pack` group; its `Artwork changed` line fired because pack-level keys count (the conservative rule from review round 2). No artwork changed, so no owner map check is needed. `mise run maps:check` then printed: `Map pack ed26414539f458929025f4ef2c3413d3457c7b3e5b9f2e2adfb4dc20c24bba5f reproduced byte-identically with xml 6.6.1, image 4.12.0, vector_graphics_compiler 1.3.4, vector_graphics 1.2.5, vector_graphics_codec 1.1.13.`
- [x] 6.4 Add the committed-pack fast tests:
  - `test/maps/active_pack_vectors_test.dart`: every committed `.vec` recompiles byte-identical from its `.compiler.svg`, decodes with `VectorGraphicsCodec().decode(bytes, null)`, and has a header matching `vectorCodecFormat`; failure reasons name the path and `mise run maps:rebuild`;
  - `test/maps/active_pack_loader_test.dart`: `PreparedMapPackLoader` with a file-backed `loadBytes` loads the real active pack with 13 maps;
  - the asset-block test: the `pubspec.yaml` block equals the directories derived from the active manifest's `outputs`.
  - remove the temporary `vectorCodecFormat` shim in `test/maps/map_controls_test.dart` `_loader()` (added in group 3 because the pre-6.3 committed manifest has no format record), so that test loads the real pack unmodified.

  Verify: `mise run test` passes and the new tests take under 2 s together (otherwise follow the design's ledger rule and tag the vector test `qualification`).

## 7. Integration

- [x] 7.1 Run `mise run analyze`, `mise run test`, `mise exec -- flutter test --tags qualification test/maps/map_preparation_qualification_test.dart` and `mise run maps:check`, and `dart format` the changed Dart. Confirm every test-map row is green, `grep -rn "preparationVersion.*== 2\|version == 2" lib tool test` finds no v2 acceptance path, and roadmap entries `add-artwork-refresh` and `add-live-map-data` exist with no other companion app named in any changed file. Verify: all four commands exit 0.
- [x] 7.2 Run `openspec validate unpin-map-toolchain --strict` and `mise run release-notes -- --check openspec/changes/unpin-map-toolchain/proposal.md`. If 6.3 reported changed artwork, update the proposal's Release Notes to say so. Verify: both exit 0.

## Workflow follow-up

- Pre-ship review, then PR (`finish: pr`), then the CI `Map pack check` step runs on the PR.
- User check only if 6.3 reports anything beyond provenance: the owner checks the listed maps in the app before merge. Otherwise there are no user checks.
- After merge: archive, which creates `openspec/specs/prepared-map-packs/spec.md`. Then `add-extract-labels` is next.
