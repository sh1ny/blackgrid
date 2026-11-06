# Spec Delta

## Purpose

Provide mode-specific, refreshable marker facts over the existing prepared artwork, with durable last-good data and a truthful offline fallback.

## ADDED Requirements

### Requirement: Mode-specific complete snapshots
The system SHALL acquire maps, tasks and traders and their English dictionaries for the effective regular, PvE or seasonal PvP mode as one candidate. It SHALL validate parser-required JSON roots, keys, types and needed records before accepting the whole candidate. A malformed needed record SHALL fail the candidate rather than be silently discarded.

#### Scenario: Complete structurally valid candidate
- **WHEN** all six sources provide the required roots and well-formed consumed records
- **THEN** the system can normalize the complete candidate for the selected mode

#### Scenario: Required input is malformed
- **WHEN** a required root or key is missing or a consumed record has a malformed type or position
- **THEN** the candidate fails with a source-specific error and no partial snapshot is published

### Requirement: Upstream content can evolve
The system SHALL accept valid additions, removals, empty collections and changes to maps, quests, names, coordinates and boss chances without comparison to historical content, marker counts, identities, placements or hashes. Existing marker categories, label rules and source-position multiplicity SHALL apply.

#### Scenario: Valid changed content
- **WHEN** a complete structurally valid snapshot removes a quest and a supported source map, adds an unsupported map and changes a boss position or chance
- **THEN** it is accepted, the removed quest is absent, the removed map has an empty marker inventory over its still-selectable prepared artwork, and the unsupported map does not become selectable

#### Scenario: Empty is not malformed
- **WHEN** a required collection is present with the correct type but empty
- **THEN** its empty content is accepted without inventing markers

#### Scenario: Removed reference or translation
- **WHEN** valid collections or dictionaries omit a previously referenced quest, trader, item or translation ID
- **THEN** the candidate is accepted without a historical referential-completeness gate, unavailable names or optional facts are omitted or reported unavailable under existing presentation rules, and no facts are invented

### Requirement: Conditional acquisition and atomic persistence
Each mode SHALL retain a validated last-good snapshot with the six exact source bodies and per-source validators. Refresh SHALL prefer ETag, then Last-Modified, otherwise an unconditional request. A 304 SHALL reuse only the exact usable cached body for that source; without it, refresh SHALL fail without retry. Bodies, validators and normalized inventory SHALL become durable and active together only after complete validation and successful storage.

#### Scenario: Mixed revalidation
- **WHEN** some sources return 304 with usable cached bodies and others return new valid bodies
- **THEN** one candidate is normalized from those exact six bodies and committed atomically

#### Scenario: Partial failure
- **WHEN** any source fails, exceeds a limit, redirects, returns unusable 304, fails structural validation or storage fails
- **THEN** no partial candidate or validator replaces the last-good snapshot, and the failure is reported

### Requirement: Acquisition is resource bounded
Acquisition SHALL reject redirects and bound each request to 30 seconds and 16 MiB and the whole refresh to 120 seconds and 64 MiB. There SHALL be no automatic retries.

#### Scenario: Acquisition within limits
- **WHEN** all six requests complete within their limits without redirects and provide usable bodies
- **THEN** acquisition passes those bodies to candidate validation

#### Scenario: Acquisition limit is exceeded
- **WHEN** a source exceeds a byte or time limit or redirects
- **THEN** acquisition fails, preserves the last-good snapshot and reports the failure without an automatic retry

### Requirement: Compact runtime facts remain complete and local
Runtime snapshots SHALL normalize directly into shared immutable facts and lightweight marker references, retaining that representation through serialization, cache loading and publication. They SHALL preserve complete logical facts, optional absence and business identities, with local reads and no network detail requests. The shared parser and frozen offline bytes SHALL remain unchanged. Quest tracking is outside this change.

#### Scenario: Shared facts remain local and complete
- **WHEN** many markers refer to the same task, objective or location with nested facts
- **THEN** the compact snapshot retains complete source and derived facts once with per-marker references, preserving optional-field absence, logical marker/source identities and quest/objective/item relationships; pool references do not replace business identities, and popup, search, filters and identity reads resolve the same logical values locally without per-marker recursive copies or network requests

#### Scenario: Shared searchable facts remain compact
- **WHEN** many marker positions reference one task containing a large searchable nested fact
- **THEN** real publication and local search retain a shared or non-expanding search representation within the injected materialization budget, preserving searchable fields, geometry exclusions, case-insensitive substring/phrase and comma-separated OR behavior without a flattened full-fact string per marker

#### Scenario: Malformed compact reference is rejected
- **WHEN** a compact payload contains a missing, out-of-range, cyclic or malformed fact reference
- **THEN** it is rejected before persistence or publication without changing existing durable or active authority

#### Scenario: Complete frozen runtime qualification
- **WHEN** the active pack's complete carried six-source closure is acquired and revalidated through the runtime pipeline
- **THEN** it publishes and reloads complete marker facts within the unchanged default budgets, while the offline pack still reproduces byte-identically

### Requirement: Expanded marker data is resource bounded
Runtime data SHALL stay within 256 MiB materialized and 64 MiB serialized. Reserve conservative charges before allocation across decoding/handoff, construction, encoding, cache/storage and publication, including derived state, transient buffers and overlapping generations. Charge shared owned facts plus references once, copies in full. Search SHALL remain non-expanding with unchanged semantics, retire with its inventory and retain no past-query cache.

#### Scenario: Expanded candidate fits
- **WHEN** a complete valid candidate's incremental normalization and serialization remain within both budgets
- **THEN** it can proceed to atomic persistence and publication

#### Scenario: Nested marker expansion exceeds a budget
- **WHEN** genuinely oversized distinct facts, reference/marker collections, derived search/projection/metadata state, transient buffers or any expanded intermediate would make a structurally valid candidate exceed either runtime-data budget
- **THEN** normalization stops before the oversized allocation, copy or serialization and before persistence/publication, reports a resource failure, and preserves the prior durable and active snapshot or bundled fallback

### Requirement: Last-good data and honest fallback
For the selected mode, the system SHALL use its compatible validated last-good snapshot regardless of age, including after a failed refresh. Without one, it SHALL use the active bundled pack's regular-mode marker inventory and identify it as a regular-mode bundled fallback, not as selected-mode live data. Cached metadata SHALL NOT hide a failure to load the active bundled artwork pack.

#### Scenario: Old cache and failure
- **WHEN** a compatible mode snapshot was checked long ago and a new refresh fails
- **THEN** that snapshot remains available with its source, last check and current failure visible, without age-based expiry

#### Scenario: Cache unavailable
- **WHEN** no valid compatible snapshot exists for PvE
- **THEN** the app displays the bundled regular-mode markers as a labelled fallback while preserving the selected PvE mode

#### Scenario: Broken bundle
- **WHEN** the active prepared pack cannot load even though cached metadata exists
- **THEN** the map reports the pack load failure instead of masking it with cached metadata

### Requirement: Cache compatibility is checked
Cache compatibility SHALL cover stored format, normalizer and relevant map calibration and mapping; corrupt or incompatible data SHALL NOT be used.

#### Scenario: Compatible cache
- **WHEN** a complete intact cache matches the current format, normalizer and relevant map calibration and mapping
- **THEN** it is available as the selected mode's last-good snapshot regardless of age

#### Scenario: Incompatible cache
- **WHEN** stored metadata is corrupt or incompatible with the current normalizer or relevant map calibration
- **THEN** that cache is not used and the labelled bundled fallback is displayed

### Requirement: Refresh scheduling and status are separate
The system SHALL start refresh in the background at startup and when the effective mode changes, without blocking startup or navigation, and SHALL provide a separate Settings action to refresh map data. Settings SHALL expose the selected mode, actual source, last check and refresh failure independently of item-data status. No polling, automatic retry or new refresh toggle SHALL be introduced.

#### Scenario: Independent map refresh status
- **WHEN** startup begins or the effective mode changes and map-data refresh is pending or fails
- **THEN** navigation remains usable and Settings shows map-data mode, actual source, last check and failure independently of item-data status

#### Scenario: Manual refresh
- **WHEN** the player invokes Refresh map data in Settings
- **THEN** the selected mode is refreshed without initiating an item-data refresh

### Requirement: Concurrent refreshes preserve selected-mode authority
Same-mode concurrent triggers SHALL join one operation. An obsolete mode result SHALL NOT replace the selected mode's display.

#### Scenario: Mode changes during refresh
- **WHEN** the selected mode changes while a previous mode's refresh is in flight
- **THEN** only the new mode's compatible cache or labelled fallback is displayed and a late prior-mode completion cannot replace it

#### Scenario: Manual refresh joins startup
- **WHEN** the player requests map refresh while that mode's automatic refresh is in flight
- **THEN** the existing operation is joined and map status reports its outcome

### Requirement: Coherent marker activation
On successful complete publication the map SHALL immediately use one coherent marker generation for rendering, browsing, filtering, hit testing, accessibility and summaries. It SHALL preserve selected map, view, floor, pins and user filters; content replacement SHALL clear marker selection, its bubble and linked highlights. Artwork, geometry, calibration and location labels remain pack-owned.

#### Scenario: Active map changes
- **WHEN** a new marker snapshot is published while the player has navigated and selected a marker
- **THEN** all marker consumers see the new generation, the marker selection clears, and navigation, floor, pins and filter preferences remain unchanged

#### Scenario: Unchanged content is checked
- **WHEN** a successful refresh confirms the same marker content
- **THEN** its check status updates without unnecessarily clearing the marker selection

### Requirement: Historical floor overrides are conditional
Historical floor overrides SHALL apply only to existing markers whose identity and placement assumptions still match; otherwise they SHALL be omitted and the existing floor policy used, without blocking publication or restoring removed markers.

#### Scenario: Reviewed floor assumptions still match
- **WHEN** a present marker retains its reviewed identity and placement assumptions
- **THEN** its applicable historical floor override remains attached

#### Scenario: Stale floor override
- **WHEN** a historically overridden marker is removed or its identity or assumed placement changes
- **THEN** it is not resurrected or forced to its old floor, and the valid snapshot remains acceptable
