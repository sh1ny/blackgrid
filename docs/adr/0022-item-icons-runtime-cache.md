# 0022 - Item icons are downloaded from tarkov.dev at runtime into a bounded local cache

- Status: accepted
- Date: 2026-10-21 (M4.5 change `add-item-icons`)
- Amends: the M1 plan's KTD8 "no item artwork" rule ([plan](../plans/2026-10-06-0242-feat-m1-manual-item-decisions-plan.md)), for item icons only.
- Source: change `add-item-icons` (design D1-D7)

## Context and problem

The decision card and the history rows show a generic Material box for every item. In a raid the item's own picture confirms at a glance that the scan picked the right item. tarkov.dev hosts an icon for almost every catalog item, and the catalog (`json.tarkov.dev`) already carries each item's `iconLink`. The icons are Battlestate Games renders, so Blackgrid must not ship them, and tarkov.dev is a third-party host that must not see a request storm.

## Decision

- **Only `assets.tarkov.dev` (D1).** The catalog keeps an item's `iconLink` only when it is `https`, on host `assets.tarkov.dev`, with no port, user info, query or fragment, and not the shared `/unknown-item-icon.jpg` placeholder. Anything else drops the field, never the item or the catalog. `CatalogItem.fromJson` applies the same check, so a tampered stored projection cannot add another host. The catalog's `schemaVersion` and `normalizerVersion` stay 1: the field is optional, and old projections load without icons until the next refresh.
- **Folder, table and names (D2).** Icon bytes are files in `%LOCALAPPDATA%\Blackgrid\item-icons\`. Each name is `<first 16 hex of sha256(itemId)>-<first 16 hex of sha256(bytes)>.<webp|png|jpg>`, so no path derives from the raw item id and a replaced icon gets a new path. Metadata lives in the Drift table `ItemIconRecords` (schema 3): `itemId`, `iconLink`, `fileName?`, `byteSize`, `etag?`, `validatedAt?`, `lastShownAt`, `failedUntil?`, `failedLink?`. Writes go temp file, flush, rename, upsert; a superseded file is deleted only when its name differs. At start the cache deletes `*.tmp` files and files no row names before it admits any request.
- **One owner with leases (D3, D4).** `ItemIconCache` is the only writer of the folder and the table and the only caller of `ItemIconClient`. Widgets acquire a lease per shown item; one request per item is shared by every lease, and the request is aborted when the last lease drops. The `ItemIcon` widget binds an icon to its item and shows the generic icon until that item's own file is decoded.
- **Downloads only for shown items.** No bulk prefetch, no request for an item without a link.
- **No time-based expiry; 30-day revalidation (D6).** A cached icon stays until its link changes, its file is missing, or it is evicted. A shown icon whose last validation is 30 days old or older gets one conditional GET with `If-None-Match`; a `304` refreshes the validation time only.
- **24 h failure wait per link (D6).** After any failed request the item gets `failedUntil = now + 24 h` for that `failedLink`, persisted so it survives a restart and kept in memory even if the database write fails. A new link clears it. A cancel sets no wait.
- **Bounds (D5, D6).** 256 KiB per body (by `Content-Length`, then by counting while streaming), 15 s per request, no redirects, at most 4 requests in flight in a FIFO queue, and a 64 MB disk budget enforced after each stored icon by evicting the least recently shown icons, never the one just stored. A body is stored only when it starts with a WebP, PNG or JPEG signature; `Content-Type` is not trusted.
- **Rights.** The icons are downloaded at runtime, at the user's direction, into the user's local cache. They are never committed, bundled or covered by Blackgrid's licence. `THIRD_PARTY_NOTICES.md` records them.
- **ADR-0005 is not affected.** Its "no runtime network dependency" rule is about the map artwork and stays in force for maps. This ADR adds runtime network for item icons only, and an offline app still works with generic icons.

## Rejected alternatives

- **Bundling item icons:** they are Battlestate renders, and the release bundle must not carry undeclared game artwork (ADR-0012, `bundle:check`).
- **`Image.network`:** no disk cache, no ETag, no failure wait and no size cap.
- **A separate icon-link index (GraphQL `items { id iconLink }`):** a second network authority and refresh cycle for data the catalog already carries.
- **An in-memory failure wait only:** a crash-and-relaunch loop would re-request every failing icon.
- **A JSON index file or SQLite blobs:** ADR-0003 rejected hand-written JSON stores, and blobs would route every decode through the Drift isolate.

## Consequences

- New GETs to `assets.tarkov.dev`: about one per item ever shown, at most one per shown item per 30 days, and at most one per failing item and link per 24 h.
- A database written by this version (schema 3) is refused by older builds, under the existing downgrade rule.
- Untrusted bytes are written to disk; the signature check, size cap and content-addressed names bound the harm, and an undecodable file shows the generic icon.
- **Reversal cost:** medium. The schema step is permanent, but the table and folder hold only re-downloadable cache data: a later version can drop the table and empty the folder.
