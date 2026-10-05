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

`OutputPath` must be outside `SourceRoot`; both it and `<OutputPath>.local.json` must have no linked/reparse-point destination or existing ancestor. In `Materialize` mode, both outputs must also be outside `MaterializePath`, so the snapshot remains exactly the declared files with no metadata or private locators added. Invalid output placement is refused before source writes or snapshot creation. Record and sidecar writes replace their directory entries from temporary siblings rather than truncating existing files, preserving any hardlinked source bytes; failed replacement preserves the destination and removes only the collector's temporary sibling. Portable JSON is separate from `<OutputPath>.local.json`, which contains private `source_root`, `input_manifest_path` and, when used, `materialized_root` locators. Keep both outputs in ignored `.qualification/` or another owner-controlled private location; never export the sidecar. The source tree is never modified. Final locks are content identities, not the sole durable archive: archive entries must identify an owner-controlled retained archive/build recipe, not merely a temporary workspace.

Example commands (explicit inputs; no native/application invocation):

```powershell
mise run qualification:freeze -- -SourceRoot F:/private/reference -OutputPath .qualification/m0/source-intake.json -InputManifestPath .qualification/m0/intake-inputs.json
mise run qualification:validate -- .qualification/m0/source-intake.json
mise run qualification:freeze -- -SourceRoot F:/private/reference -OutputPath .qualification/m0/verify-unused.json -InputManifestPath .qualification/m0/intake-inputs.json -Mode Verify -LockPath .qualification/m0/source-intake.json
mise run qualification:freeze -- -SourceRoot F:/private/reference -OutputPath .qualification/m0/source-lock.json -InputManifestPath .qualification/m0/cleared-complete-inputs.json -Mode Materialize -AllowMaterialization -MaterializePath .qualification/m0/reference-snapshot
mise exec -- dart run tool/qualification/m0.dart hash-lock .qualification/m0/source-lock.json
mise run qualification:validate -- .qualification/m0/source-lock.json --freeze-id <sha256> --source-root .qualification/m0/reference-snapshot
```

`m0.dart validate RECORD [--freeze-id SHA256] [--source-root ROOT]` emits a small validation JSON result. `hash-lock LOCK` prints the computed identity; `hash-lock LOCK --write` computes and validates the final record, flushes a unique same-volume temporary sibling, then replaces the original with `File.rename`. It refuses a non-file target or linked ancestry; failed replacement preserves the original bytes and removes its own temporary directory. These checks are not a sandbox against hostile same-user directory replacement. JSON/contract/file failures exit nonzero. A hash alone is not successful evidence validation.

### Report request, API and output

```powershell
mise exec -- dart run tool/qualification/m0.dart report .qualification/m0/request.json --input-root . --output-root .qualification/m0/dossier-new
```

Both root options are required exactly once. `REQUEST` resolves from the caller's working directory and must name a file inside `--input-root`; it is not a discovery directory. The output must be a **new directory**: an existing file, directory or link is refused, never overwritten. Input/output ancestry must be real directories, not links. Unsafe inputs, fixture-byte drift or denied required summary exports are refused before output creation; a later I/O failure may leave a partial new output, not successful evidence.

A version-1 request is:

```json
{
  "schema_version": 1,
  "record_type": "dossier_request",
  "id": "m0-report-request",
  "run_id": "m0-evidence-run",
  "records": {
    "source_intake": ".qualification/m0/source-intake.json",
    "provenance": "docs/qualification/m0/provenance.json",
    "fixture_manifest": "test/fixtures/m0/manifest.json",
    "map_controls": "test/fixtures/m0/map/control_points.json",
    "display_matrix": "docs/qualification/m0/display-matrix.json",
    "planned_checks": "docs/qualification/m0/planned-checks.json",
    "environment": ".qualification/m0/environment.json"
  },
  "oracle_results": null,
  "oracle_results_reason": "Permitted native replay is not available.",
  "attempt_bundle": null,
  "attempt_bundle_reason": "No actual measurements have been collected."
}
```

`records` requires those six metadata roles and exactly one `source_intake` or `source_lock`. Optional measured roles are `oracle_results` and `attempt_bundle`; supply their explicit file paths in `records`, **or** top-level null plus a nonempty reason, never both. Unknown request fields/roles are refused. Every record path, manifest `files[].path` and reference case `input.path` is relative to **input root**, not the request/manifest directory. Source closure paths describe old artifacts only; they do not instruct the reporter to open an old checkout.

The generator uses the same canonical `validateRecord` request contract as the validate command; omitted optional availability fields are not implicit nulls. Each consumed role's original-byte hash and parsed JSON come from one byte read, not two potentially different file versions. Manifest payload hash/size and JSON parsing likewise use the same read.

`tool/qualification/report.dart` exports:

- `buildDossier(Map<String, Map<String, dynamic>> records, {required String runId})`: pure serialized-evidence aggregation; role keys must match record types. Returns `qualification`, `baseline_summary`, `divergence_register`, `evidence_index`. Gates are recomputed, not trusted from asserted statuses. Invalid supplied measurements become evidence-linkage failures; missing measurements remain unverified, not fabricated failed attempts.
- `generateDossier(String requestPath, {required String inputRoot, required String outputRoot})`: reads explicit local records/payloads, verifies declared raw hashes/sizes and case roster equality, enforces sanitized export, then writes the new dossier.

Outputs are `qualification.json`, `baseline-summary.json`, `divergences.json`, `README.md`, cleared metadata under `inputs/<role>.json`, and `reference-results.json` only when a supplied reference record is exportable. No fake Oracle/native wrapper/result file or attempt-bundle attachment is generated. `qualification.exports` names only actual cleared sibling JSON payloads and their canonical byte hashes; denied attachments remain indexed with reasons and their bytes absent. The qualification record does not hash itself; the generated README names its hash externally. `inputs` also retains consumed original JSON byte identities separately from canonical record identities. Report generation performs no collection, launch, network fetch or source materialization.

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

`record_type: environment` requires `setup_alias`, and explicit object-or-null fields `hardware`, `windows`, `runtime`, `app_build`, `viewport`, `display`, `observer`; text-or-null `locale`, `display_mode`, `warm_state`. Preserve unavailable fields with reasons. The named native baseline requires concrete fields:

- `hardware: {cpu, gpu, ram_bytes}`, `windows: {version, architecture}`, `runtime: {sdk}`, `app_build: {id, version}`.
- `display: {width, height, os_scale_percent, origin: {x,y}, topology}`; origin is signed, finite physical coordinates.
- `viewport: {width, height, client_width, client_height, ui_scale}`; dimensions are positive integer physical pixels, UI scale is positive.
- `observer: {method, recording_id, clock_domain, uncertainty_ms}`; uncertainty is finite and nonnegative.
- Nonempty `locale`, `display_mode`, `warm_state`.

Supplied known fields are validated; absent/null nested setup fields do not establish a native baseline. Each warm/cold live attempt's concrete display cell and viewport must match the setup; supplied contradictions and observer recording/clock conflicts are invalid evidence, while missing fields keep gates unverified. Name-only maps are descriptive metadata, not measured setup proof. Alias rather than personal machine/account names. Metadata does not establish live display behavior.

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

Optional `anchors` has unique rows binding `id`, `kind: floor_artwork|tile_seam|raster_extent`, `map_id`, `source_key`, text `frame_revision`, exact portable `artwork_path`, `artwork_sha256`, `config_sha256`, explicit `floor_group_id` (null+reason only for non-floor anchors), positive integer `width`/`height`, finite nonnegative `uncertainty`, Boolean `independent_of_reference_output`, and nonempty `source_ids`, `review_ids`, `points: [{x,y}]`. Floor artwork requires at least one independently grounded point and an exact configured floor identity; seam/extent requires at least two. Points must lie within declared artwork dimensions to count as independent report evidence. Anchor `uncertainty` is annotation uncertainty, **not** a new tolerance field; control `tolerance` and comparator truth `tolerances` are separate.

Report linkage matches map/source/frame to `expected_roster`, exact artwork path/hash to effective `maps`, and configuration hash to effective `config`. A floor's explicit planned `image_path` binds that exact floor image rather than an arbitrary same-hash artwork. Real coverage requires non-synthetic, non-derived evidence independent of reference output and at least two distinct review IDs; minimum three distinct noncollinear controls per configured map, plus all configured floor/seam/raster anchors. Synthetic transforms/config inventory do not establish real control truth.

`record_type: display_matrix`, `cells: [...]` (unique IDs and dimension/scaling combinations). Cell fields: `id`, positive integer `width`, `height`, `os_scale_percent`, `evidence_class: planned|synthetic|derived|offline|live_user`, `case_ids`, `evidence_ids`, nonempty `limitations`. Offline/live classes require actual evidence IDs; planned cells cannot carry observation evidence. Derived cells cannot establish capture, DPI or live behavior. Qualification reports retain all 16 cells, with their actual evidence class; a report with planned cells cannot be `qualified`.

## Oracle results

The observation artifact's own reviewed `report_export` use and every root/nested dependency/derived/build relationship must clear independently of authored report metadata. Valid private replay linkage does not grant public observation export. A denied observation remains indexed by ID/consumed-record hash with an unverified decision; scoped refusals remain in `rights_blockers`, not as payload provenance grants on the unverified index row. Raw result attachments and observation-derived payloads/metrics are absent. Cleared observed derivatives retain complete provenance linkage. Invalid-attempt count salvage additionally requires the original recursive privacy checks to pass; stripping forbidden rows cannot authorize their counts or detailed diagnostics.

`record_type: oracle_results` requires `freeze_id`, `run_id`, `environment_id`, `fixture_manifest_sha256`, nonempty root `provenance_ids` naming the observation artifact(s), and nonempty `observations`. A `(case_id, profile)` pair is unique. Observation fields:

`fixture_manifest_sha256` is `sha256Json(manifest)`, the canonical logical record identity—not SHA-256 of pretty-printed input bytes. Frozen `files[].sha256`/sizes and actual generator evidence-index hashes bind original consumed bytes independently. Canonical public role records can therefore be reconsumed beside identical frozen payloads without changing the oracle's manifest identity.

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

These payloads preserve marker scores/geometry, title ROI diagnostics, OCR/candidates/scores, identity/rejection/error, per-detection independent geometry associations, host policy facts, applicable map projection/inverse/floor/heading, or panel absence/unreadable/ambiguity. Comparison objects preserve submitted diagnostics, not independent truth. The comparator below computes comparisons from manifest truth rather than trusting observation `comparison`.

### Independent comparison API

`tool/qualification/compare.dart` exports `compareReferenceResults(manifest, results, {sourceLock})`. It consumes serialized `fixture_manifest`/`oracle_results`; an optional source lock must be final, valid and match the freeze. Results require `comparison_basis` exactly matching manifest `corpus_version`, `annotation_version`, `catalog_version`, `config_version`, `mode`, `freeze_id`, plus the canonical manifest hash. Changed case/observation basis, run/setup linkage, profile, input hash or observations outside the eligible roster are refused.

Expectation-only cases are reported separately, never eligible reference observations. Every reference-bearing case declares Boolean `reference_eligible`; false requires `eligibility_rationale`. Eligible truth is profile-specific and independent of reference predictions. Missing rows, `unverified` rows and `error` rows stay explicit. Denominators include `eligible_cases`, `attempted_rows`, `observed`, `missing_rows`, `errors`, `unverified`, `complete_comparisons`, `expectation_only_cases`, `ineligible_cases`, globally and by profile. All eligible cases must have complete comparisons and the eligible roster must be nonempty for comparison `evidence_validity: pass`. Faithfully recorded wrong behavior can have valid evidence.

Metrics are counts, **not a pooled accuracy percentage**:

- `correct_positive_ids`: readable-positive truth with the independently correct selected identity; `wrong_positive_ids`: selected wrong identity on readable-positive truth. Positive rejection/abstention increments `readable_positive_misses`; errors retain `outcome_errors` and prevent complete comparison.
- `accepted_negatives`: host accepts a unique identity despite rejection/chrome/ambiguous/occluded truth. Engine selection on that truth increments separate `recognized_negatives`. Both, and wrong-positive selection, increment `wrong_identities`; do not hide them in a successes-only denominator.
- Engine outcome vocabulary is `recognized|rejected|abstained|error`; host uses `accepted|rejected|abstained|error`. Host `host_accepted_identities` and `actionable_advice` count observed acceptance/advice, not safety or correctness. Engine output cannot increment actionable advice. No positive-only denominator or percentage is emitted: interpret metric counts alongside the full per-profile case roster; multi counts can be per detection rather than per case.

Inspection compares labeled title ROI axes under finite nonnegative `geometry_tolerance` and preserves marker/OCR/candidate diagnostics. Multi truth is `inspections: [{id,label,item_id,title_roi}]`; actual detections carry distinct IDs and full engine payloads. Association uses independently labeled geometry, not detection order or predicted identity. Missing, unmatched and duplicate detections remain defects; multiple matches receive no correct-positive credit.

Host truth adds `target_policy: {id,decision,inputs,rationale,intentional_divergence}`. Decisions are `Keep|Sell|Check`, or honest null where advice is inapplicable. Policy-ID mismatch is invalid linkage; an explicitly intentional target/reference decision difference remains a separate divergence, not a target policy defect.

Map truth binds `frame_revision`, `artwork_pixel`, `normalized`, `game_xyz`, `floor_group_id`, `heading: {degrees,convention}`, and `tolerances: {artwork_pixel,normalized,game_xyz,heading}`. Axis comparisons use the declared absolute tolerance; heading uses wrapped angular distance and exact convention. Unknown game Y is not zero. Panel truth/result bind `map_id`; dispositions are `absent|present_empty|matched|no_match|ambiguous|unreadable`, with exact applicable extract/transit text and map-local `matched_ids` set, plus retained OCR spans. A matched panel requires IDs; absent/empty/no-match/unreadable cannot claim them.

The returned comparison summary includes `cases`, `profiles`, `metrics`, `denominators`, `expectation_only`, `ineligible`, `divergences`, `evidence_validity` and `reference_behavior`. It is computed comparison data, not an observation record or full qualification.

## Attempt bundle

`record_type: attempt_bundle` requires `freeze_id`, `run_id`, `environment_id`, nonempty root `provenance_ids` naming the actual measurement observation artifact(s), and `attempts` (unique IDs). Each row requires:

- `id`, `request_id`, `generation`, positive integer `ordinal`, `executor`, `evidence_mode`, `intended_path`, `actual_path`, `terminal_outcome`, `trigger_kind`, `clock_domain`.
- `stages: [{name, start_tick, end_tick}]`: nonnegative integer ticks with end >= start. `qpc_frequency` is a positive integer, or null with reason if no tick stages exist.
- `missing_stage_reasons` object; explicit `endpoint`, `trigger`, `observer`, `external_data_age_ms`, each null with reason when unavailable.

Preserve all attempted dispositions. The established measurement vocabulary is `correct`, `wrong_id`, `rejected`, `error`, `canceled`, `superseded`, `incomplete`; the base record validator accepts nonempty outcome text, while actionable statistics accept **only** `correct`. Do not invent outcome aliases or replace unsuccessful attempts. Warm-live handoff additionally records integer `batch_ordinal` 1..3, `scope: live-warm`, matching planned `stratum_id`, and canonical `intended_path: intended-targeted|fallback-required`; `actual_path` describes what actually ran. `case_id`/`input_sha256` bind the declared actual input in report aggregation. Preserve `master_case_id`, `source_id`, `warm_state`, `profile`, `sampling_profile`, `display_cell`, `acquisition_class` and their honest availability.

A valid private measurement bundle is not automatically cleared for public reporting. Its own reviewed `report_export` uses and dependency/derivation/build closure authorize timing/resource summaries and other measured derivatives. Denied measurement observations remain indexed by ID/hash with blocked-use and unverified gates; their raw or derived values, counts and attempt payloads are not exported. Allowed summaries retain the bundle's `provenance_ids` and each supplied attempt's scope-specific `measurements`, including explicit null reasons.

Optional `measurements` is an object or explicit null with reason. Its supported fields are `initialization_ms`; `startup` and `first_scan` elapsed observations; `map_load_ms`, `map_switch_ms`, `pan_ms`, `zoom_ms`, `floor_switch_ms`, `process_cpu_ms`, `process_memory_bytes`, `interaction_path_id`. Applicable missing fields remain null with reasons, never measured zero or successful no-op. Durations/resources are finite nonnegative numbers (memory is integer bytes), and the interaction path names the preregistered fixed path. Elapsed observations have `start`/`end` video boundaries using the stamp/linkage vocabulary below; startup runs from `process_launch` to visible `first_usable`, first scan from `physical_actuation` to independently correct visible `actionable_visible` for correct outcomes (or an observed `terminal_visible` unsuccessful completion), with same-recording/clock frame uncertainty and attempt linkage.

Allocation execution is separate from measurement completeness. Offline warm requires actual QPC stage observations; offline cold also requires initialization elapsed evidence. Live cold requires user-attributed startup/first-scan boundaries and named setup linkage. Live bursts require user-attributed correlated physical actuation, named setup linkage, and eligible visible endpoints for correct outcomes, without a pooled burst p95 or a success replacement quota. Map/startup/resource allocation requires actual fixed-path load/switch/pan/zoom/floor observations plus process CPU/memory. These gates require `collection_status: observed`, actual acquisition, the scope's warm/cold state, and `executor: developer`/`evidence_mode: offline` for offline/map or `executor: user`/`evidence_mode: live_user` for live. Failed/rejected/canceled/error attempts remain in every denominator without success replacements; missing applicable observations keep the measurement gate unverified even when allocation counts are fulfilled.

### Statistics API and clocks

`tool/qualification/statistics.dart` exports `nearestRankQuantile(List<num> samples, {double quantile = 0.95})` and `summarizeAttempts(Map<String, dynamic> bundle)`. The latter collects nothing and returns a version-1 `baseline_summary`.

Raw tick stages inherit the attempt's `clock_domain` and `qpc_frequency`; duration is `(end_tick-start_tick)*1000/frequency`. Expanded stage `start` and `end` must both be `{tick,frequency,domain,name}`, match their raw tick values, and share the attempt frequency/domain. Optional `qpc_events` uses that same stamp shape with unique event names. `fallback_start` or `fallback_work` proves worker start; `fallback_deadline` does not. Retain original stamps in the attempt input: a duration or UTC metadata cannot replace raw clock evidence.

Video `trigger`, `endpoint`, optional `fallback_endpoint` use `{type:"video", name, recording_id, clock_domain, lower_ms, upper_ms, request_id, generation, ordinal, case_id, observable, linkage_valid}`. Both boundaries must be observed, linked to the same attempt and share recording and video clock. Trigger name is `physical_actuation`. Actionable endpoint name is `actionable_visible`, with `visibility: visible`, `correctness: identified_correct` and outcome `correct`; an honest Check may qualify, rejection does not. Fallback endpoint name is `fallback_visible`, with `visibility: visible`, `phase: fallback_running`, and actual worker-start evidence; it may be observed on unsuccessful attempts.

No video/QPC subtraction is allowed. Visible elapsed lower is `max(0, endpoint.lower_ms-trigger.upper_ms)` and upper is `endpoint.upper_ms-trigger.lower_ms`; the clamp represents overlapping annotation uncertainty, not measured zero. Occlusion, wrong identity, missing boundary/linkage or noneligible outcome yields null interval with reason. Publication, UI assignment and DwmFlush are not visible proof.

Strata keep environment, warm state, profile, evidence mode, display cell, acquisition class, intended path, actual path, terminal outcome and trigger kind separate; no pooled-route/setup p95 is emitted. Nearest-rank p95 is sorted sample at one-based `ceil(0.95*N)`, not interpolated. Every stage/video metric retains `n`, `missing_n`, counted `missing_reasons`; `n+missing_n` equals its attempted denominator. Zero eligible samples produce null p95 with reason. Optional `targets_ms` yields `pass` when upper <= target, `fail` when lower > target, `indeterminate` when bounds cross, otherwise `unverified`.

External age retains each attempt's original value/reason and counts `measured|absent|future|unsupported`. A nonnegative numeric age is measured; negative is future, not fresh. Object form is `{status:"measured",age_ms}` or `{status:"absent|future|unsupported",reason}`. Unsupported representations do not invent an age. Measured-age p95 excludes unavailable/future values while preserving them in missing counts; it does not by itself authorize market advice.

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

Gate statuses are `pass`, `fail`, `unverified`, `not_applicable`; a pass requires evidence IDs. A required gate cannot be `not_applicable`. Keep evidence-validity gates separate from faithfully measured reference defects. Planned/actual denominators, expectation-only/observed coverage, missing/skipped attempts and uncertainty stay explicit. `validateRecord` checks the mechanical shape; `buildDossier` computes coverage, comparison linkage, export decisions and required gates. A schema-valid partial record is not completed M0 qualification.

## Baseline summary and divergence register

`baseline_summary` binds `attempt_bundle_id`, canonical `attempt_bundle_sha256`, `freeze_id`, `run_id`, `environment_id`, nearest-rank p95 method, `attempt_n`, unique `attempt_ids`, full `outcome_counts`, `actionable_sample_n`, `fallback_visible_sample_n`, `coverage`, `external_data_ages`, `strata`, `attempt_summaries` and explicit collection disposition. Strata partition attempted IDs without pooling. Coverage counts distinct master/source IDs and missing identities; repeated variants/replays do not increase independent coverage. `status: descriptive` means eligible visible samples exist, not qualification; zero actionable samples are `incomplete`/`unverified`. Absent measurement inputs have null bundle/hash/freeze with reasons and zero actual attempts; invalid supplied evidence retains recoverable attempted IDs/outcomes but cannot establish eligible samples.

`divergence_register` contains `run_id`, `observed` and `expectation_only`. Observed recognition/geometry/policy/panel rows bind actual `case_id`, `profile`, status, defects/errors, expected and observed payload (or null with reason). A `kind: reference_speed` row instead binds actual `case_ids`, stratum and evidence IDs, `expected: {target_ms}` and `observed: {name,n,p95_ms}` or interval p95 bounds; it has **no fabricated singular `case_id` or profile**. Synthetic policy expectations stay `expectation_only` with adjudication evidence and reason, never observed Sell/reference divergences. Faithfully measured slow/wrong reference behavior is a reference defect, not invalid evidence linkage and not an automatic required evidence-gate failure.

An actually observed `intentional_target_policy` row retains case/profile/status, independent expected policy, actual reference payload, rationale and evidence IDs separately, with no fabricated defect. That case is not also `expectation_only`; this bucket is reserved for policies without corresponding observed divergence. Observation-bearing derived reports/registers retain the observation `provenance_ids`, and sibling export entries bind them alongside authored metadata clearance.

## Verification boundary

The parent exercised **112 full offline tests**, and tooling/tests analysis was clean. The real fixture checker exercised **193 cases / 11 payloads / 16 synthetic geometry cells**. The actual CLI generated the incomplete dossier at [`reports/2026-10-05-m0-intake/README.md`](reports/2026-10-05-m0-intake/README.md): **262 gates, 4 pass and 258 unverified**, with **9 exported sibling hashes matching**. There were **0 attempts, 0 real scanner masters and 0 independent real controls**. The generated dossier is the actual public entrypoint; it is not completed qualification. A disposable v3 `core.autocrlf=true` Git commit and clone preserved all **23 exact JSON byte files** (12 manifest/payload files, provenance and 10 dossier JSON files); the cloned final-v3 checker passed **193 cases / 11 payloads / 16 synthetic geometry cells**. The owned repositories were removed and user Git configuration was unchanged. No native/game launch or user skip occurred. Rights closure, native evidence, real corpus/control truth and user baseline remain explicit blockers.

Committed manifest files bind exact raw on-disk payload bytes. Generated exported input records use canonical JSON for their record identities; canonical serialization alone is not tampering. An explicitly consumed exported record must be semantically identical to its matching verified frozen record, while every declared frozen payload still verifies against its exact raw-byte hash. A changed logical field must fail. The actual isolated CLI first exposed a `m0-display-matrix` reconsume mismatch. After separating semantic record linkage from raw payload verification, the isolated CLI consumed the seven public canonical records and 12 original manifest/payload files successfully, reproducing all 262 gate statuses, coverage and denominators. No old checkout, native oracle, companion or network was used; the owned workspace was removed.
