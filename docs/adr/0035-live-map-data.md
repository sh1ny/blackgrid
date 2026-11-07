# 0035 - Live map metadata over prepared artwork

- Status: accepted
- Date: 2026-11-06 (change `add-live-map-data`)
- Partly supersedes: [ADR-0005](0005-native-map-prepared-packs.md), bundled-marker-only boundary; [ADR-0034](0034-metadata-refresh-preserves-prepared-artwork.md), runtime metadata prohibition and historical marker-preservation requirements only
- Source: change `add-live-map-data` (decisions S1-S7 and D1-D5; S7 and D5 revised 2026-11-07)

## Context and problem

Bundled marker facts become stale independently of prepared artwork. Requiring new content to retain historical marker identities, coordinates or floor assignments rejects legitimate upstream corrections. Runtime metadata must be refreshable without acquiring artwork, changing calibration, admitting new selectable maps or hiding a broken active pack.

## Decision

- **Keep artwork prepared.** The active bundled pack owns selectable maps, artwork, geometry, calibration, floors and location labels. ADR-0033's immutable generations, exact-candidate promotion, frozen integrity, byte-identical reproduction and active-generation-only loading remain in force. Cached metadata cannot mask a pack-loading failure.
- **Follow the effective mode.** Acquire maps, tasks, traders and their English dictionaries from `https://json.tarkov.dev/{regular|pve|pvp-season}/` as one complete candidate. Unknown mode makes no request. Each mode has an independent last-good snapshot regardless of age; without one, identify the active pack's regular-mode markers honestly as bundled fallback.
- **Share normalization and admit content evolution.** Runtime and offline preparation use the same pure normalization and existing category, label, identity and duplicate-position rules. Validate required parser structure and consumed record types, not historical counts, identities, coordinates or source hashes. Empty collections and missing optional references are valid. Missing supported metadata maps have empty markers; unsupported metadata maps do not become selectable.
- **Apply floor overrides conditionally.** Retain an override only when the present marker matches its reviewed identity and placement assumptions. Interchange requires the complete reviewed volume/outline; Icebreaker Helicopter and C-1 require their reviewed identity, position/height and source/key evidence. Stale overrides neither reject valid changes nor restore removed markers. Artwork calibration and its evidence remain unchanged.
- **Persist sources atomically in Drift.** Store the six exact raw bodies, their validators and the check time per mode in one transaction. Store no normalized form: markers are re-derived from the bodies by the current normalizer and active pack on every load, so normalizer or calibration changes need no fingerprint. An incomplete or unparsable cache is not shown. Migration touches only the cache tables and preserves existing user records.
- **Bound conditional acquisition.** Prefer ETag, otherwise Last-Modified, otherwise unconditional acquisition. A 200 replaces or clears validators; a 304 reuses only the cached body and keeps or updates validators. No redirects or automatic retries. Bound decoded acquisition to 30 seconds/16 MiB per request and 120 seconds/64 MiB overall. Normalize and parse markers in one `Isolate.run`, sharing frozen facts between markers by identity; there is no separate materialization budget, because the result has the shape the bundled manifest already loads.
- **Own lifecycle in AppServices.** Refresh in the background at startup and mode changes, with a separate Settings action/status. Same-mode triggers join; each mode has at most one refresh. Fence cache reads and publication by selection, await any started atomic transaction, and abort downloads and stop notifying before dependencies on disposal.
- **Publish one coherent generation.** Rendering, browsing, filtering, hit tests, accessibility and summaries switch together without artwork reload. Preserve map, view, floor, pins and filters. Changed content clears selection, bubble and linked highlights; unchanged content updates check status without clearing selection. Status exposes selected mode, actual source, last check and failure independently of item data. No polling or new toggle.
- **Retain offline preservation.** Metadata renewal still verifies the active baseline, replaces exactly six sources, proves candidate-own-source fidelity and frozen hashes, and preserves nonmetadata bytes/properties and independent artwork admission. Changed-map reports and the existing owner check remain required. Only historical marker equality/ownership vetoes are removed; promotion and recovery are unchanged.

## Rejected alternatives

- Runtime artwork or new-map admission: crosses the reviewed artwork/calibration boundary.
- Separate runtime parser or cache files: duplicates normalization or transactional storage conventions.
- Historical content gates or unconditional stale floor assignments: reject legitimate source evolution or misplace changed markers.
- Expiring last-good data, retries, polling or combined item/map refresh: loses usable offline facts or conflates independent authority and failures.
- Compact fact pool with 256 MiB materialization and 64 MiB serialization budgets (the first S7/D5): its conservative accounting rejected the complete baseline dataset on repeat refreshes, while the bundled manifest already loads the same expanded markers.
- Storing normalized markers with a compatibility fingerprint: re-deriving from the cached sources is simpler and cannot go stale.

## Consequences

- Upstream content may be structurally valid but inaccurate; source and check status are visible rather than claiming historical equality proves correctness.
- Valid old caches remain useful offline; failed acquisition, parsing or persistence changes status, not last-good authority.
- Frozen offline output retains its representation and reproducibility. Artwork, calibration, integrity and independent admission requirements are not relaxed.
- Accepted ADRs remain historical records; this ADR controls only the explicitly superseded marker-data portions. Reversal cost is medium because cache, normalization and publication form one cross-layer contract.

Related: ADR-0002 (composition and fences), ADR-0003 (transactional Drift), ADR-0004 (bulk parsing off UI), [ADR-0033](0033-map-packs-proven-by-reproduction.md).
