# Proposal

## Why

M4.5 (player-facing polish, item icons and own map markers), change 2 of 7. The decision card and the history rows show a generic Material box for every item, and the wide Scanner card even says `Identity only • no artwork`. In a raid, the item's own picture tells the player at a glance that the scan picked the right item, the way the reference companion shows it. This change serves the M4.5 exit criterion:

> The decision card and history rows show the item's icon, downloaded from tarkov.dev once and kept in a local cache. The previous item's icon never sits next to a new item, and the generic icon shows while loading, offline or when the item has no picture. Service tests prove one download per item, no time-based expiry, revalidation at most every 30 days, and no retry storm after a failure.

It needs `polish-map-rail` (change 1), which is done. The user asked for the icons on 2026-10-18. The icons are Battlestate game renders hosted by tarkov.dev, so the M1 plan's "no item artwork" rule (KTD8) is amended: Blackgrid downloads them at the user's direction and never ships them.

## What Changes

- The catalog keeps each item's `iconLink` from `json.tarkov.dev`. A link is accepted only if it is HTTPS on `assets.tarkov.dev`, with no query, no fragment, no port and no user info. tarkov.dev's shared `unknown-item-icon` placeholder counts as "no picture". The field is optional and needs no catalog version bump, so stored catalogs from before this change still load (with no icon until the next refresh).
- A new item-icon cache keeps downloaded icons under `%LOCALAPPDATA%\Blackgrid\item-icons\`, with their metadata in the existing SQLite database (one new table, database schema 2 → 3):
  - It downloads an icon only when an item is shown. There is no bulk prefetch.
  - Downloads go through the existing HTTP client with a timeout, no redirects, a size limit, an image-format check, at most one download per item at a time and a small concurrency cap.
  - An icon stays until its `iconLink` changes. Nothing expires by age.
  - A shown icon is revalidated with its ETag at most once every 30 days. An unchanged icon costs a `304`.
  - A failed download or revalidation is not retried for that item for 24 hours, even across restarts.
  - Least-recently-shown eviction starts only above 64 MB.
- When the shown item changes, a download nothing shows any more is cancelled. A newer scan therefore cancels the older scan's download.
- The decision card shows the item's icon on Scanner (wide and narrow layouts) and on Map (compact layout, which has no image slot today). Recent item activity rows show it in place of the generic leading icon. While the icon is loading, when it fails, offline, or when the item has no picture, the generic icon shows. An icon is bound to its item, so the previous item's icon is never drawn for a new item. The `Identity only • no artwork` label is removed.
- Docs:
  - A new ADR records the runtime icon download and cache.
  - The M1 plan's KTD8 gets a dated amendment note that points to the ADR.
  - `THIRD_PARTY_NOTICES.md` gains an item-icon entry: Battlestate game renders hosted by tarkov.dev, downloaded at the user's direction, not shipped.
  - `openspec/architecture.md` gains the cache's resource bounds.

## Capabilities

### New Capabilities

- `item-icons`: where an item's icon comes from, how Blackgrid downloads, caches, revalidates and evicts it, and how the decision card and history rows show it, with the generic fallback.

### Modified Capabilities

None. The catalog's integrity and authority rules (`catalog-authority`) do not change. Keeping `iconLink` is specified under `item-icons`.

## Impact

- **Code:**
  - `lib/domain/catalog.dart` (`CatalogItem.iconLink`)
  - `lib/data/catalog_normalizer.dart`
  - `lib/data/database.dart` (new table, migration 2 → 3)
  - `lib/data/local_paths.dart` (`itemIcons` folder)
  - a new icon client and cache service under `lib/data/` and `lib/application/`
  - `lib/application/app_services.dart` (wiring and dispose)
  - `lib/ui/item_decision_card.dart`
  - `lib/ui/evidence_panels.dart` (`HistoryPanel`)
  - a small shared item-icon widget
- **Network:** new GETs to `assets.tarkov.dev`, one per shown item, cached on disk. The catalog request is unchanged.
- **Storage:**
  - A new database table. A database written by this version is refused by older builds, which is the existing downgrade rule.
  - Icon files of about 2-3 KB each. All 5,480 items together are about 15 MB, under the 64 MB budget.
- **Docs:**
  - a new ADR (next free number, 0022)
  - the KTD8 note in `docs/plans/2026-10-06-0242-feat-m1-manual-item-decisions-plan.md`
  - `THIRD_PARTY_NOTICES.md`
  - `openspec/architecture.md`
- **Out of scope:**
  - map marker icons (changes 3-5)
  - any bundled item artwork
  - icons for history rows whose item is not in the current catalog (they keep the generic icon, as their name already falls back to the id)
