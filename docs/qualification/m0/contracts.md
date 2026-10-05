# M0 evidence contracts (schema version 1)

These developer-only records describe evidence, not implemented product behavior. They never authorize a reference/game launch, establish reuse permission, or turn planned coverage into an observation. Ordinary tests use synthetic JSON and temporary synthetic files; they need no reference checkout, .NET, capture, network, or running application.

## Compatibility and exported Dart API

`tool/qualification/contracts.dart` exports:

- `validateRecord(Map<String, dynamic> record, {String? expectedFreezeId})`: throws `ContractException` on a malformed or dishonest version-1 record. An expected freeze must exactly equal the record's top-level `freeze_id`; an intake/unattempted record cannot satisfy it.
- `canonicalJson(Object?)`: UTF-8-ready JSON text, recursively sorted object keys (Dart ordinal string order), array order preserved, no whitespace. Keys must be strings; numbers must be finite. This is the repository's canonicalizer, not a claim of RFC 8785 compatibility.
- `sha256Json(Object?)`: lowercase SHA-256 of the UTF-8 canonical text, no trailing newline.
- `sourceFreezeId(Map<String, dynamic> lock)`: hashes a `source_lock` payload without top-level `freeze_id`, `collected_at`, or `local_locators`. It computes an identity, not validation or permission. The caller must validate the completed lock. Every other field, including the ordered closure, configuration and instrumentation identities, participates.
- `qualificationStatus(List<Map<String, dynamic>> gates)`: `not_qualified` for any required failure; otherwise `incomplete` for a required unverified gate or an empty required-gate set; otherwise `qualified`. Optional failures do not classify unrelated required uses as failed.
- `verifySourceIntegrity(Map<String, dynamic> record, String sourceRoot)`: validates a source record, then checks only its declared files' byte hashes and sizes. Missing files, linked roots/ancestors/children, and changed bytes throw. It invokes no process. Git revision/dirty integrity is additionally checked by the PowerShell collector.
- `ContractException`, with `message` and `toString()`.

Every record has `schema_version: 1`, `record_type`, and nonempty `id`. Unknown versions and record types are rejected. Additive descriptive fields are allowed but cannot replace required fields; new incompatible meanings require a schema-version change. Array rows carrying `id` must have unique IDs where indicated below.

Unavailable fields are **explicitly null**, with a nonempty sibling `<field>_reason`. A reason-suffixed field is allowed only beside its corresponding null. Null array entries are not allowed: use an object containing the unavailable field and reason. A measured zero is not an unavailable value. Optional fields may be omitted where the shape below explicitly says optional; an applicable unknown must not be omitted. Profile payloads preserve unavailable fields rather than inventing zeros or default identities.

SHA-256 values are exactly 64 lowercase hexadecimal characters. Portable payload paths use `/`, are relative, and contain no drive, backslash, empty segment, `.` or `..`. Collector closure paths additionally exclude `.git`, build/bin/obj trees, caches, logs, personal settings/credentials/secrets, app-data, development caches and key/private credential files. The include list contains **files**, never directory/glob directives. Personal settings are not a substitute for independently declared synthetic effective settings.

## Collector and CLI

PowerShell 7, Git, and the project's Dart/crypto dependency are needed for the collector. It accepts mandatory `-SourceRoot`, `-OutputPath` and `-InputManifestPath`, with an explicit JSON include manifest. It never scans app-data, starts a reference, or copies source in default `Intake` mode. Git metadata commands are read-only. The only content operations are hashing the explicit files and, after clearance and explicit materialization selection, copying those same files.

Input manifest shape:

```json
{
  "schema_version": 1,
  "id": "reference-intake-v1",
  "files": [
    {"path": "Config/maps.json", "role": "map-config"},
    {"path": "TarkovTracker.csproj", "role": "build"}
  ],
  "submodules": [],
  "closure_complete": false,
  "closure_declaration": "Explicit metadata intake; native/model/catalog/archive/adapter identities are not established.",
  "effective_inputs": {
    "config": [
      {"id": "maps-config", "path": "Config/maps.json", "version": "working-tree", "locator": "reference/Config/maps.json"}
    ],
    "model": null,
    "model_reason": "Not yet inventoried for a permitted run."
  }
}
```

This is an illustrative manifest, not a complete source closure or reuse grant. Parent tooling prepares the actual explicit include set. Missing effective-input categories become null with a reason, never guessed identities. For an input with `path`, the collector fills its SHA-256 from that named closure file; a supplied mismatching hash is rejected. A non-file identity requires a declared `sha256`, `version`, `id` and portable durable `locator`. No external/private directory discovery is performed to fill missing identities.

Modes:

- `Intake` (default): emits `source_intake`, always `freeze_id: null` with reason. An actual metadata intake is useful without native/model/catalog/build/archive clearance or complete closure.
- `Lock`: requires `closure_complete: true`, all effective identity categories, and reviewed `private_reference` clearance covering every file. It emits a validated final `source_lock`, but copies nothing.
- `Verify`: also requires `-LockPath`. Verifies the manifest's include set equals the record's closure, rehashes the explicit files, re-attests main/submodule commits and dirty facts, and validates source integrity. Accepts an intake or lock, but never upgrades an intake. `OutputPath` is required by the common invocation interface but no output record is written in this mode.
- `Materialize`: requires all final-lock requirements plus **both** `-AllowMaterialization` and `-MaterializePath`. Refuses an existing target, a target inside the source, links, or uncovered permission scope. Copies only declared files and checks source pre/post hashes/revisions plus copied byte integrity. A failed operation has no successful final lock output. A partial newly created materialization is retained for its owner's investigation; no user/private tree is deleted automatically.

`OutputPath` must be outside `SourceRoot`. Portable JSON is separate from `<OutputPath>.local.json`, which contains private `source_root`, `input_manifest_path` and, when used, `materialized_root` locators. Keep both outputs in ignored `.qualification/` or another owner-controlled private location; never export the sidecar. The source tree is never modified. Final locks are content identities, not the sole durable archive: archive entries must identify an owner-controlled retained archive/build recipe, not merely a temporary workspace.

Example commands (explicit inputs; no native/application invocation):

```powershell
mise run qualification:freeze -- -SourceRoot F:/private/reference -OutputPath .qualification/m0/source-intake.json -InputManifestPath .qualification/m0/intake-inputs.json
mise run qualification:validate -- .qualification/m0/source-intake.json
mise run qualification:freeze -- -SourceRoot F:/private/reference -OutputPath .qualification/m0/verify-unused.json -InputManifestPath .qualification/m0/intake-inputs.json -Mode Verify -LockPath .qualification/m0/source-intake.json
mise run qualification:freeze -- -SourceRoot F:/private/reference -OutputPath .qualification/m0/source-lock.json -InputManifestPath .qualification/m0/cleared-complete-inputs.json -Mode Materialize -AllowMaterialization -MaterializePath .qualification/m0/reference-snapshot
mise exec -- dart run tool/qualification/m0.dart hash-lock .qualification/m0/source-lock.json
mise run qualification:validate -- .qualification/m0/source-lock.json --freeze-id <sha256> --source-root .qualification/m0/reference-snapshot
```

`m0.dart validate RECORD [--freeze-id SHA256] [--source-root ROOT]` emits a small validation JSON result. `hash-lock LOCK` prints the computed identity; `hash-lock LOCK --write` computes, validates and writes the final record. JSON/contract/file failures exit nonzero. A hash alone is not successful evidence validation. U1 does not implement aggregation; `qualification:report` routes to `m0.dart report` for the report unit to implement and is nonzero until that real command is integrated, never a successful no-op.

## Source intake and final source lock

Both types require:

- `reference: {commit, dirty, closure_status: [{path, status}]}`. Commit is a 40–64-character lowercase Git identity; `dirty` is Boolean. Intake may have null commit/dirty with reasons when Git metadata is unavailable. Only explicitly included closure paths' status text is retained; unrelated paths are not exported. `dirty` still describes the whole working tree.
- `submodules: [{path, commit, dirty, closure_status}]`, explicitly declared relative roots, same revision fields as `reference`. Empty is allowed when none are relevant. Their content files are separately included in the main file closure.
- `files: [{path, sha256, size_bytes, role}]`, unique case-insensitively and strictly sorted by ordinal path. Hashes bind exact bytes. Final locks require nonempty closure.
- `effective_inputs`: the categories `config`, `native`, `model`, `catalog`, `build`, `archive`, `adapter`, `instrumentation`, `packages`, `maps`. Each is a nonempty array of `{id, sha256, version, locator, path?}` or, in intake only, null with `<category>_reason`. `path`, if supplied, must match a closure file and hash. IDs are unique within each category. Use descriptive additional fields for settings/modes/locales/catalog status/source timestamp and snapshot identities; those values are part of the freeze, unlike collection time.
- `closure_complete` Boolean and nonempty `closure_declaration`.
- Optional `collected_at` is collection metadata, not effective processing/capture/catalog time. Optional `local_locators` is excluded from identity but must not enter exported evidence; the collector uses a separate sidecar instead.

`source_intake` explicitly requires `freeze_id: null` and `freeze_id_reason`. It does not attest complete reproducibility even if some/all hashes are known. `source_lock` requires `closure_complete: true`, every nonempty effective category, a matching `freeze_id`, and:

```json
{
  "permission": {
    "use": "private_reference",
    "status": "cleared",
    "reviewer": "designated-reviewer-id",
    "reviewed_at": "review-date",
    "evidence_ids": ["grant-record-id"],
    "scope_paths": ["every/declared/file"]
  }
}
```

A reviewer record is necessary, not permission inferred from public availability. Separate native/model/catalog/archive/adapter/build identities remain required even when reference HEAD is unchanged. Altered map/config/patch/model bytes create a new freeze; results bound to the old one cannot validate against the new freeze.

## Environment

`record_type: environment` requires `setup_alias`, and explicit object-or-null fields `hardware`, `windows`, `runtime`, `app_build`, `viewport`, `display`, `observer`; text-or-null `locale`, `display_mode`, `warm_state`. Preserve unavailable fields with reasons. Objects carry actual CPU/GPU/RAM, Windows build/architecture, SDK/runtime, app identity, actual viewport/UI settings, pixel dimensions/scaling/monitor topology, and observer/trace configuration. Alias rather than personal machine/account names. Metadata does not establish live display behavior.

## Provenance

`record_type: provenance`, `artifacts: [...]`; artifact IDs unique. Each artifact requires:

- `id`, `kind`, `purpose`, `source` object, `sha256` or null with reason.
- `declared_terms` object (source text locator/hash, declared license expression or unresolved reason); declaration is separate from assessed clearance.
- String-ID arrays `depends_on`, `derived_from`, `build_inputs`; text/ID arrays `notices`, `modifications`.
- `uses`, with exactly the applicable stored use rows `private_reference`, `repository_fixture`, `report_export`, `release`. Each row requires `status: cleared|unresolved|excluded`, `scope`, `reason`, `evidence_ids`; cleared requires nonempty evidence and `reviewer`, `reviewed_at`. Unknown review fields are null with reasons.

No automatic permission inheritance from parent artifacts, derivation, package metadata or availability. A release blocker can stay inventoried without invalidating an unrelated cleared offline use. Standard SPDX identifiers apply only to matching standard text; retain custom exact terms as `LicenseRef` when needed.

## Fixture manifest

`record_type: fixture_manifest` requires `corpus_version`, `annotation_version`, `catalog_version`, `config_version`, `cases: [...]` (unique IDs). Each case has `id`, `source_id`, `display_cell_id`, `role: reference_characterization|expectation_only|both`, nonempty `provenance_ids`, nonempty `adjudication_ids`, and independently authored `truth` object.

- `expectation_only`: requires `initial_context` object, nonempty `ordered_inputs` array, `expected_effects` object. Encode expected effects and non-effects, session/correction/import/catalog/policy sequences here. It does not require fake pixels, an oracle profile, a freeze, or a placeholder input hash.
- Reference-bearing roles: require `profile` from the observation profiles below, nonempty `seam`, `input: {path, sha256, width, height}` (positive integer dimensions), and `acquisition: actual|derived|synthetic`. Derived cases additionally require `parent_id` and `transform` recipe object. Store actual-vs-derived display metadata, cursor/ROI, and independent labeling/review references as descriptive additional fields.

A missing real screenshot/control point belongs in `planned_checks`, not an empty byte payload masquerading as a real fixture. Empty `cases` or controls are permitted as honest inventory states, not qualified coverage.

## Map controls and display matrix

`record_type: map_controls`, `controls: [...]` (unique IDs). Each real control requires `id`, `map_id`, `source_key`, `frame_revision`, `artwork_sha256`, `config_sha256`, `game_xyz: {x, y, z}`, `artwork_pixel: {x,y}`, `normalized: {x,y}`, `floor_group_id`, `heading_convention`, nonnegative finite `tolerance`, `uncertainty`, nonempty `source_ids`, `review_ids`. Coordinates must be finite; `game_xyz.y` may be null with reason. Never fill missing independently grounded landmarks by reading reference predictions.

`record_type: display_matrix`, `cells: [...]` (unique IDs and dimension/scaling combinations). Cell fields: `id`, positive integer `width`, `height`, `os_scale_percent`, `evidence_class: planned|synthetic|derived|offline|live_user`, `case_ids`, `evidence_ids`, nonempty `limitations`. Offline/live classes require actual evidence IDs; planned cells cannot carry observation evidence. Derived cells cannot establish capture, DPI or live behavior. Qualification reports retain all 16 cells, with their actual evidence class; a report with planned cells cannot be `qualified`.

## Oracle results

`record_type: oracle_results` requires `freeze_id`, `run_id`, `environment_id`, `fixture_manifest_sha256`, nonempty `observations`. A `(case_id, profile)` pair is unique. Observation fields:

- `case_id`, `input_sha256`, `profile`, `status: observed|unverified|error`.
- `result`, `comparison`, `stage_timings` array, `errors` array.
- Unverified observations require null `result` and `comparison`, each with reason. Error observations require recorded errors. Observed observations require object `result` and object `comparison`.

Observed profile payloads require all the listed keys; applicable-but-unavailable values are null with reasons, not omitted:

| Profile | Required result keys |
| --- | --- |
| `engine_inspection` | `marker`, `title_roi`, `ocr_text`, `candidates`, `outcome` |
| `engine_multi` | `detections`, `unmatched`, `duplicates` |
| `host_resolution` | `selected_evidence_ids`, `outcome`, `decision`, `reasons`, `facts`, `snapshot_ids`, `target_policy_id` |
| `map_geometry` | `frame_revision`, `artwork_pixel`, `normalized`, `game_xyz`, `floor_group_id`, `heading` |
| `exfil_panel` | `disposition`, `extract_text`, `transit_text`, `matched_ids`, `ocr_spans` |

These payloads preserve marker scores/geometry, title ROI diagnostics, OCR/candidates/scores, identity/rejection/error, per-detection independent geometry associations, host policy facts, applicable map projection/inverse/floor/heading, or panel absence/unreadable/ambiguity. Comparison objects identify independent truth/control versions and preserve known safety divergences. U1 validates presence/linkage/unavailability; profile-specific comparison and detailed timing semantics belong to their owning later units.

## Attempt bundle

`record_type: attempt_bundle` requires `freeze_id`, `run_id`, `environment_id`, `attempts` (unique IDs). Each row requires:

- `id`, `request_id`, `generation`, positive integer `ordinal`, `executor`, `evidence_mode`, `intended_path`, `actual_path`, `terminal_outcome`, `trigger_kind`, `clock_domain`.
- `stages: [{name, start_tick, end_tick}]`: nonnegative integer ticks with end >= start. `qpc_frequency` is a positive integer, or null with reason if no tick stages exist.
- `missing_stage_reasons` object; explicit `endpoint`, `trigger`, `observer`, `external_data_age_ms`, each null with reason when unavailable.

Preserve all attempts, including reject/error/supersede/cancel/incomplete. Additional endpoint/trigger/video interval objects carry recording identity, frame bounds, observer clock, and uncertainty; UTC metadata is not a substitute for a shared interval clock. U1 does not derive or claim visible latency from internal ticks.

## Planned checks

`record_type: planned_checks`, `checks: [...]` (unique IDs). Each row requires `id`, Boolean `required`, `applicable`, `attempted`; `owner`, `scope`, `stratum_id`, `reason`; `case_ids`, nonnegative integer `allocation`, `evidence_ids`; `disposition: planned|observed|blocked|missing|skipped|excluded`; and explicit `freeze_id` (null with reason when unavailable).

Required scope cannot be made inapplicable to hide missing evidence. Unattempted rows have no freeze or evidence, and cannot be `observed`. Observed attempted rows require evidence IDs. Skipped rows require `skip_decision_id`, identifying the actual user decision; skips remain unverified. This is the durable roster for missing real fixture families, independent map controls, or native/live measurements.

## Qualification report and gates

`record_type: qualification_report` requires:

- `inputs: [{id, version, sha256}]`, nonempty actual input-manifest identities.
- `planned_checks_id`; `coverage`, `denominators`, `timing` objects; `strata`, `divergences` arrays.
- `display_matrix: {cells: [...]}` with all 16 cells and the display shape above.
- `exports: [{path, sha256, provenance_ids}]`, portable allowlisted payload identities with nonempty provenance linkage.
- `gates: [{id, required, status, owner, evidence_ids, reason}]` and `status` exactly matching `qualificationStatus`.

Gate statuses are `pass`, `fail`, `unverified`, `not_applicable`; a pass requires evidence IDs. A required gate cannot be `not_applicable`. Keep evidence-validity gates separate from faithfully measured reference defects. Planned/actual denominators, expectation-only/observed coverage, missing/skipped attempts and uncertainty stay explicit. U1 validates the mechanical report shape; the report unit owns aggregation, recorded comparison semantics, export clearance and required-gate inventory. A schema-valid partial record is not a completed M0 qualification.

## Authoring evidence and verification ownership

U1 deliberately has no observed red run: this is a new implementation and shared-checkout verification is host-owned. Permanent Flutter tests cover stable canonical identity, changed config with unchanged HEAD, stale freeze linkage, missing source/model/catalog hashes, forged locks, unknown versions, null-reason honesty, incomplete intake, required-gate classification, unattempted checks, unsafe paths and copied-byte drift. The existing compact-window widget test was inspected and is unrelated/unchanged. No install, formatter, analyzer, test, collector, native replay or application launch was run by the U1 author.

The host should resolve the declared `crypto` dev dependency, run focused `test/qualification/m0_contracts_test.dart` and existing tests with the project runner, run static analysis/format checks once after integration, and smoke the collector on a synthetic Git source with explicit files: unchanged hash, changed config/same HEAD, missing native/model identity, permission-denied materialization, cleared explicit materialization, tampered copy refusal, source pre/post integrity and local sidecar separation. Only then collect authorized actual metadata intake; no source copying or full-lock claim without reviewed permission and declared complete inputs.
