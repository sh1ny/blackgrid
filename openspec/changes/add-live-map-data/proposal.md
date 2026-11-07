# Proposal

## Why

M8's map labels and popups currently depend on frozen regular-mode marker facts, so upstream corrections require a pack rebuild and release. `add-live-map-data` makes those facts refreshable while preserving the prepared artwork and calibration; it advances M8's readable map/popup outcome, with the real-map readability criterion judged at milestone close after location labels land rather than blocking this data-only change on live-game testing.

## What Changes

- Refresh map markers from json.tarkov.dev at startup, on effective game-mode selection and through a separate **Refresh map data** Settings action, without waiting for network work during startup.
- Keep independent regular, PvE and seasonal PvP snapshots, using conditional HTTP requests and a persistent validated last-good cache.
- Validate downloaded format and parser-required structure before saving and activating a complete candidate. Accept valid content changes, including removed quests/markers/maps, empty collections, changed coordinates, names and spawn rates. Keep compatible last-good data only after acquisition, structural/parsing or storage failure, otherwise use the active bundled pack's regular-mode markers with honest fallback/source labelling.
- Immediately replace marker facts on success while preserving the map view, floor, saved pins and user filters; clear marker selection and its bubble when content changes.
- Show map-data source, mode, last check and failure independently of item-data status.
- Keep runtime marker data compact through normalization, caching and publication: markers reference shared immutable facts locally, preserving complete quest/objective/item identities and facts without adding quest tracking or changing frozen offline output or the approved resource caps.
- Keep selectable artwork inventory, geometry, calibration and future location labels pack-owned. Historical marker-floor overrides apply only while their identity and placement assumptions still match; disappeared or changed markers cannot block refresh or be resurrected by an override.
- Amend offline metadata renewal's content-freezing gates too: verify candidate structure and derivation from its own source, not equality with historical marker content. Preserve non-metadata artwork/calibration integrity separately. Do not add runtime artwork, automatic artwork admission for new maps, polling, automatic retries, a new settings toggle or an Ember redesign.

## Capabilities

### New Capabilities

- `runtime-map-data`: mode-scoped acquisition, conditional cache, validation, fallback and coherent marker publication over the bundled map inventory.

### Modified Capabilities

- `map-marker-popups`: player-facing summaries consume the active validated marker facts, whether downloaded, cached or bundled, without initiating requests.
- `prepared-map-packs`: offline metadata renewal accepts structurally valid upstream additions, removals and edits; historical marker ownership and source content do not veto renewal, while artwork/calibration preservation and frozen-candidate reproducibility remain enforced.

## Impact

- `lib/application/app_services.dart`, map ownership in `map_controller.dart`, a dedicated map-data controller, HTTP/normalization adapters and the Drift cache.
- Shared marker normalization extracted from `tool/maps/pack.dart` without a second parsing convention; replace historical-content admission checks in runtime and offline metadata renewal with parser-structure checks and conditional floor overrides. Source hashes still verify acquired/cached bytes and frozen reproduction, never require future upstream bytes to match old ones.
- Settings/data-source presentation and targeted model, store, controller and widget tests. Existing HTTP/Drift dependencies suffice.
- A new ADR records runtime metadata ownership and upstream content authority, partly superseding ADR-0005's bundled-marker boundary and ADR-0034's historical marker-preservation requirements. Accepted ADR files remain unchanged; update the architecture index and affected contracts during apply. ADR-0002/0003/0004 and ADR-0033 constrain lifecycle, storage, bulk parsing and bundle loading.

## Decision Making

DECISION_MAKING: important
Source: setting

| ID | Choice | Rejected | Reversal cost | Important | Chosen by |
|---|---|---|---|---|---|
| S1 | Follow the selected game mode with independent snapshots; label regular-mode bundled fallback honestly | Regular metadata for every mode | Medium: cache and publication contract | yes: user-visible behaviour, binds future changes | user |
| S2 | Keep compatible validated last-good data regardless of age, then bundled markers; no item-style authority expiry | Revert to bundle on every failure | Low: fallback policy | yes: user-visible behaviour | user |
| S3 | Activate complete validated metadata immediately, preserving navigation/pins/filters and clearing marker selection | Activate only on restart | Medium: content-generation contract | yes: user-visible behaviour, binds future changes | user |
| S4 | Separate Settings refresh/status, automatic background refresh at startup/mode selection, no polling/retry/toggle | Combined item/map refresh | Low: UI and scheduling | yes: user-visible behaviour | user |
| S5 | Runtime metadata only; artwork, calibration and labels remain prepared | Runtime artwork or additional map admission | High: rendering/calibration boundary | yes: binds future changes | user |
| S6 | Upstream owns content: validate format/parser-required structure, accept valid additions/removals/edits/empty collections in runtime and offline renewal; stale floor overrides never veto refresh | Historical marker identity/count/coordinate/hash equality as an admission gate | Medium: normalization, offline gates and ADR contract | yes: binds future changes, user-visible behaviour | user |
| S7 | Store shared runtime facts once with lightweight marker references; preserve all facts, source identities and unchanged resource caps and frozen output | Expanded per-marker copies, raising the cap or rejecting the baseline dataset | Medium: runtime encoding and local fact resolution | yes: binds future changes, including later quest work | user |

## Release Notes

Map markers can receive upstream corrections without rebuilding the artwork or installing a new release.

### Added

- Mode-specific map-data refresh at startup and from Settings, with conditional downloads, a local last-good cache and a labelled bundled fallback.

### Changed

- Successful map-data updates replace marker facts immediately while retaining map navigation, floors, filters and saved pins; marker selection closes when content changes.
- Shared runtime and offline normalization accepts valid upstream additions, removals, edits and empty collections. Historical floor overrides apply only while reviewed identity and placement assumptions match; artwork, calibration and frozen-source integrity remain separately protected.
- Runtime snapshots share complete facts between markers instead of expanding them repeatedly, keeping local marker details available within the existing resource limits.
- Normalization releases temporary budget reservations when marker delivery fails.
- Refresh progress stays visible during startup cache reads; extreme offscreen geometry no longer interrupts rendering, and shared facts stay bounded during publication.
- Non-empty marker searches reuse exact shared-fact query summaries while preserving complete phrase matching.
- Map-data availability reflects prepared-pack load failures, and malformed exit aliases are rejected before activation.
- Shared long scalar text is folded once per generation under admission accounting, including boundary searches.
