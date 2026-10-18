# Proposal

## Why

The catalog can never become `current`. Authority requires six top-level `updated` source timestamps that agree and are under 24 h old (`catalog.dart:298-316`, read at `catalog_normalizer.dart:383-385`). The live `json.tarkov.dev` responses for `regular`, `pve` and `pvp-season` carry only `data` and `translations` at top level, so all six timestamps are null. After every refresh the catalog stays `stale` in every mode and every decision drops to Check. The bug dates from M1 (8e6f767). The test fixtures carry a top-level `updated` that the real API never sends, so the tests pass. The README even records the symptom ("a successful refresh is still shown as stale").

This change is a prerequisite of M4 (complete raid-time Scanner slice). `add-scan-decisions` feeds accepted scans into the shared decision engine, and that engine can only give Check while catalog authority is unreachable.

On 2026-10-18 the live sources were probed:

- Only `items` has per-entry timestamps (`data.items.<id>.updated`). They range from about a year old up to a few minutes old.
- `traders`, `tasks`, `hideout`, `crafts` and `barters` carry no time fields at all.
- Each dataset's HTTP `Last-Modified` changes only when its content changes. `hideout` was 40 days old, so no rule that every dataset be under 24 h old can pass on any source timestamp.

The user chose to measure catalog freshness from download time.

## What Changes

- Catalog authority no longer depends on source timestamps. A snapshot is authoritative when it comes from a supported source, schema and normalizer, its mode is known, and it was validated and observed (downloaded) under 24 h ago and not in the future. The 1 h `lastScanISO` market-quote rule is unchanged and still forces Check on stale quotes.
- Source timestamps become evidence only. `items` records the newest valid per-item `updated`. The other five datasets record none, because the source has none. The non-existent top-level `updated` is no longer read.
- The `current` expiry timer runs from observation time only. A source timestamp can no longer shorten it.
- `CatalogSnapshot.sourceFreshAt` is removed. The evidence panel shows the items source update time as information. The decision warning no longer names source freshness.
- Fixtures match the real wire shape: no top-level `updated`, a `translations` key, and per-item `updated` on items. A regression test normalises the live shape and requires authority; it fails on the current code.
- README and `openspec/architecture.md` describe the new rule.

## Capabilities

### New Capabilities

- `catalog-authority`: when a validated catalog snapshot may back decisions (`current`), when it expires, and which source-time evidence it keeps.

### Modified Capabilities

None. The M1 catalog rules predate OpenSpec and have no spec in `openspec/specs/`.

## Impact

- `lib/domain/catalog.dart` (authority, `sourceFreshAt` removed), `lib/data/catalog_normalizer.dart` (source-time evidence), `lib/application/catalog_controller.dart` (expiry), `lib/ui/evidence_panels.dart` and `lib/domain/decision_engine.dart` (text).
- Fixtures and tests under `test/fixtures/m1/catalog/`, `test/data/`, `test/domain/` and `test/application/`.
- No persistence change. `schemaVersion` and `normalizerVersion` stay 1, so cached snapshots keep loading, and a cached snapshot still opens as `stale` until a refresh. No new dependencies or network requests.
- This reverses the M1 plan's rule that a missing source timestamp keeps freshness unknown (`docs/plans/2026-10-06-0242-…`, KTD3). That plan is CE-era history and is left unchanged.
