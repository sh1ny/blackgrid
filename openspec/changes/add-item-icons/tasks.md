# Tasks

Dart work follows AGENTS.md, section "Dart and Flutter code".
- Skills per group: `dart-use-pattern-matching` (sealed results, groups 4-5), `dart-write-documentation` (all public APIs), `dart-add-unit-test` (groups 2-6), `dart-run-static-analysis` (every group), `flutter-add-widget-test` (group 7).
- Fakes are hand-written and injected through constructors: a fake `http.Client` (`MockClient` or `test/support/stalling_http_client.dart`), a mutable clock (`var now = fixtureNow; clock: () => now`), an in-memory `BlackgridDatabase`, and a temp folder.
- Timeouts are injected as short durations. No arbitrary sleeps.
- Image fixtures are tiny synthetic WebP, PNG and JPEG byte arrays.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Icon links come only from the catalog and only from assets.tarkov.dev | A valid asset link is kept | test/data/catalog_normalizer_test.dart | keeps an https assets.tarkov.dev icon link | red |
| Icon links come only from the catalog and only from assets.tarkov.dev | A link on another host, scheme or with a query is dropped | test/data/catalog_normalizer_test.dart | drops icon links on another scheme, host, port, query or fragment | red |
| Icon links come only from the catalog and only from assets.tarkov.dev | The unknown-item placeholder means no picture | test/data/catalog_normalizer_test.dart | treats the unknown-item-icon placeholder as no picture | red |
| Icon links come only from the catalog and only from assets.tarkov.dev | An item id that is unsafe in a file name writes nothing outside the cache folder | test/application/item_icon_cache_test.dart | names files from hashes so unsafe item ids stay inside the folder | red |
| Icon links come only from the catalog and only from assets.tarkov.dev | A malformed link value is dropped | test/data/catalog_normalizer_test.dart | drops non-string, empty or unparseable icon links without rejecting the catalog | red |
| Stored catalogs from before icon links still load | An older projection loads without icons | test/data/catalog_normalizer_test.dart | a stored projection without iconLink keys still loads | red |
| Stored catalogs from before icon links still load | The next refresh adds icon links | test/data/database_test.dart | committing the same revision again replaces an icon-less projection | red |
| Icons download only for shown items | Showing an uncached item downloads its icon once | test/application/item_icon_cache_test.dart | first acquire of an uncached item sends one GET and becomes ready | red |
| Icons download only for shown items | A catalog refresh downloads nothing | test/application/app_services_item_icons_test.dart | committing a catalog with icon links sends no icon request | red |
| Icons download only for shown items | An item without a picture sends no request | test/application/item_icon_cache_test.dart | an item with no icon link stays generic and sends nothing | red |
| One download per item at a time | The card and a history row share one download | test/application/item_icon_cache_test.dart | two leases on one item share one request | red |
| One download per item at a time | Showing the item again during a download starts no second one | test/application/item_icon_cache_test.dart | re-acquiring during a held download sends no second request | red |
| Cached icons have no time-based expiry | An old icon is used without a download | test/application/item_icon_cache_test.dart | a 400-day-old icon validated 10 days ago is used without a request | red |
| Cached icons have no time-based expiry | A changed icon link replaces the cached icon | test/application/item_icon_cache_test.dart | a new icon link downloads once and removes the old file unless it is the same file | red |
| Cached icons have no time-based expiry | A missing icon file is downloaded again | test/application/item_icon_cache_test.dart | a recorded icon whose file is gone downloads again | red |
| Shown icons are revalidated at most every 30 days | Revalidation inside 30 days sends nothing | test/application/item_icon_cache_test.dart | an icon validated 29 days ago is not revalidated | red |
| Shown icons are revalidated at most every 30 days | An unchanged icon costs a 304 | test/application/item_icon_cache_test.dart | a 30-day-old icon revalidates with If-None-Match and a 304 keeps the file | red |
| Shown icons are revalidated at most every 30 days | A changed icon replaces the cached one | test/application/item_icon_cache_test.dart | a 200 revalidation replaces the icon and stores the new etag | red |
| Shown icons are revalidated at most every 30 days | A 200 with identical bytes keeps the cached file | test/application/item_icon_cache_test.dart | a 200 revalidation with identical bytes keeps the file and sends nothing next time | red |
| Shown icons are revalidated at most every 30 days | A failed revalidation keeps the cached icon | test/application/item_icon_cache_test.dart | a failed revalidation keeps the cached icon ready | red |
| A failed icon request is not retried for 24 hours | Showing a failed item again sends nothing | test/application/item_icon_cache_test.dart | a 404 item shown 50 times in 23 hours sends one request | red |
| A failed icon request is not retried for 24 hours | The wait survives a restart | test/application/item_icon_cache_test.dart | a reopened cache keeps the failure wait | red |
| A failed icon request is not retried for 24 hours | After 24 hours one new attempt is made | test/application/item_icon_cache_test.dart | after 24 hours a failed item gets exactly one new request | red |
| A failed icon request is not retried for 24 hours | A new icon link clears the wait | test/application/item_icon_cache_test.dart | a new icon link inside the wait sends one request to the new link | red |
| A failed icon request is not retried for 24 hours | A failure for one item does not block another | test/application/item_icon_cache_test.dart | one item's failure wait does not block another item | red |
| Icon downloads are bounded | A redirect is a failure | test/data/item_icon_client_test.dart; test/application/item_icon_cache_test.dart | a 302 is IconFailed and not followed; client failures start the wait | red |
| Icon downloads are bounded | An oversized body is a failure | test/data/item_icon_client_test.dart | a body over 256 KiB aborts as IconFailed (by Content-Length and by streaming) | red |
| Icon downloads are bounded | A body that is not an image is a failure | test/data/item_icon_client_test.dart | a 200 HTML body is IconFailed | red |
| Icon downloads are bounded | A hung request times out | test/data/item_icon_client_test.dart | a stalled request aborts at the injected timeout as IconFailed | red |
| Icon downloads are bounded | More than four shown items wait their turn | test/application/item_icon_cache_test.dart | six shown items run at most four requests at once and download each once | red |
| A download nothing shows any more is cancelled | A newer scan cancels the older scan's download | test/application/item_icon_cache_test.dart; test/ui/item_icon_test.dart | releasing the last lease aborts without a wait; switching the widget's item releases the old lease | red |
| A download nothing shows any more is cancelled | A cancelled item downloads when shown again | test/application/item_icon_cache_test.dart | a cancelled item sends one new request when acquired again | red |
| A download nothing shows any more is cancelled | A download still shown elsewhere is not cancelled | test/application/item_icon_cache_test.dart | releasing one of two leases keeps the download | red |
| The icon cache stays within 64 MB | Below the budget nothing is evicted | test/application/item_icon_cache_test.dart | storing under the injected budget evicts nothing | red |
| The icon cache stays within 64 MB | Above the budget the least recently shown icons go first | test/application/item_icon_cache_test.dart | over budget evicts least recently shown and keeps the new icon | red |
| An interrupted icon write leaves no partial icon | A crash mid-write leaves nothing shown | test/application/item_icon_cache_test.dart | open removes a leftover tmp file and the item downloads when shown | red |
| An interrupted icon write leaves no partial icon | Stray files are removed at start | test/application/item_icon_cache_test.dart | open removes files no row names before any acquire is admitted | red |
| The decision card shows the item's icon | Scanner shows the icon | test/ui/item_icon_surfaces_test.dart | Scanner decision card shows the cached item icon in wide and narrow layouts | red |
| The decision card shows the item's icon | Map's compact card shows the icon | test/ui/item_icon_surfaces_test.dart | Map compact decision card shows the cached item icon | red |
| The decision card shows the item's icon | The generic icon shows while loading or offline | test/ui/item_icon_test.dart | shows the generic icon while loading and after a failure | red |
| The decision card shows the item's icon | An undecodable icon falls back | test/ui/item_icon_test.dart | an undecodable file shows the generic icon without an error | red |
| The previous item's icon is never shown for a new item | A new scan shows the generic icon until its own icon is ready | test/ui/item_icon_test.dart | switching item shows generic until the new icon is ready | red |
| The previous item's icon is never shown for a new item | A late download for the old item does not reach the new one | test/ui/item_icon_test.dart | a late completion for the old item never draws on the new one | red |
| History rows show the item's icon | A row shows its item's icon | test/ui/item_icon_surfaces_test.dart | a history row shows its item's cached icon | red |
| History rows show the item's icon | A row from another mode stays generic | test/ui/item_icon_surfaces_test.dart | a history row from another mode stays generic and acquires nothing | red |

## 1. ADR, notices and plan amendment

- [x] 1.1 Write `docs/adr/0022-item-icons-runtime-cache.md` (MADR-short, `Status: accepted`, today's date). It records what design.md's ADRs section lists:
  - the host allow-list;
  - the folder, the table and the hashed, content-addressed names;
  - the 30-day revalidation, the per-link 24 h failure wait, the 64 MB budget, the 256 KiB / 15 s / 4-in-flight bounds;
  - the rights position;
  - that ADR-0005's no-runtime-network rule covers maps only;
  - a rejected alternative and the reversal cost.

  Verify: the file exists and `docs/adr/README.md` lists it, if that README indexes ADRs.
- [x] 1.2 Update `openspec/architecture.md`. Verify: `grep -n 0022 openspec/architecture.md` shows the row.
  - Add ADR-0022 to the in-force index.
  - Change the HTTP response bodies row in Resource bounds to say icon bodies are capped at 256 KiB.
  - Add an item-icon cache row (64 MB, LRU).
  - Mention `ItemIconCache` where components and state ownership are listed.
- [x] 1.3 Add a dated amendment note under KTD8 in `docs/plans/2026-10-06-0242-feat-m1-manual-item-decisions-plan.md`. It says item icons are now downloaded at runtime per ADR-0022 and that the plan's other rules stand. Verify: the note is directly under the KTD8 line and links ADR-0022.
- [ ] 1.4 Add an item-icon entry to `THIRD_PARTY_NOTICES.md`, beside the Remote data paragraph:
  - item icons are Battlestate Games renders hosted by tarkov.dev (`assets.tarkov.dev`);
  - they are downloaded at runtime at the user's direction into the user's local cache;
  - they are not shipped with Blackgrid or covered by its licence.

  Verify: `mise run bundle:check` is not required (nothing bundled). `rg -n "assets.tarkov.dev" THIRD_PARTY_NOTICES.md` shows the new entry.

## 2. Catalog keeps the icon link

- [ ] 2.1 Write failing tests in `test/data/catalog_normalizer_test.dart` for the five link and projection rows of the test map: valid kept; scheme, host, port, query and fragment dropped; placeholder dropped; malformed dropped without rejecting the catalog; old projection loads. Verify they fail on the missing field, not on a fixture error.
- [ ] 2.2 Add `String? iconLink` to `CatalogItem` (`lib/domain/catalog.dart`, constructor, `toJson`, `fromJson`) and one shared validator used by the normalizer and `fromJson` (D1). Read `iconLink` in `normalizeCatalog` (`lib/data/catalog_normalizer.dart`) without changing `schemaVersion` or `normalizerVersion`. Add `iconLink` to a few items in `test/fixtures/m1/catalog/six_datasets.json`. Verify: the group 2 tests pass, the existing `schemaVersion = 2` rejection test still passes, and the rows go green.
- [ ] 2.3 Write a test in `test/data/database_test.dart` that commits an icon-less projection, then commits the same revision with icon links, and checks that `loadCatalog` returns the links. Verify it passes (the behaviour exists at `lib/data/database.dart:129-148`) and flip the row green.

## 3. Database schema 3

- [ ] 3.1 Write failing migration tests in `test/data/migration_test.dart`: 2→3 and 1→3, each keeping preferences, activity and the active catalog and creating `item_icon_records`. Keep the existing v1→v2 test passing. Verify they fail because schema 3 is missing.
- [ ] 3.2 Add the `ItemIconRecords` table (D2 columns), set `schemaVersion` to 3, and chain `onUpgrade` 1→2→3 with any other range still throwing. Regenerate with `dart run build_runner build`, dump `drift_schemas/drift_schema_v3.json` and generate `test/data/generated/schema_v3.dart` with `drift_dev`. Verify: the group 3 tests pass and `mise run analyze` is clean.
- [ ] 3.3 Add `BlackgridDatabase` methods for the cache: read all icon rows, upsert one, delete some, and update `lastShownAt`. Each write is a transaction (ADR-0003). Verify with a round-trip test in `test/data/database_test.dart`.

## 4. Bounded icon client

- [ ] 4.1 Write failing tests in `test/data/item_icon_client_test.dart` for the client rows:
  - redirect `302` is `IconFailed` and is not followed;
  - oversize by `Content-Length` and by a streamed body over 256 KiB;
  - a `200` HTML body;
  - a stalled request at an injected short timeout (`StallingHttpClient`, `aborts == 1`);
  - plus extra tests: a `200` WebP, PNG and JPEG gives `IconFetched` with the etag; a `304` with `If-None-Match` sent gives `IconNotModified`; an external cancel gives `IconCancelled`; the `User-Agent` header is set.
- [ ] 4.2 Implement `ItemIconClient` in `lib/data/item_icon_client.dart` with the sealed `ItemIconFetchResult` (D5): `AbortableRequest`, `followRedirects = false`, an injected timeout (default 15 s), the 256 KiB cap, signature sniffing, an optional etag and a cancel signal. Verify: the group 4 tests pass and the client rows go green.

## 5. Icon cache service

- [ ] 5.1 Write failing tests in `test/application/item_icon_cache_test.dart` for every cache row of the test map. Use a fake client that records calls and completes them on demand (completers), a mutable clock, an in-memory database, a temp folder, and an injected budget small enough for tiny fixtures. Restart tests reopen a new cache on the same database and folder. Verify each fails for the missing cache.
- [ ] 5.2 Implement `ItemIconCache` in `lib/application/item_icon_cache.dart` per D3 and D6:
  - `open()` loads the index and runs the sweep (`*.tmp` files and files no row names) before it returns, and earlier `acquire`s give `generic`;
  - leases expose `ValueListenable<ItemIconView>`, with per-item reference counts and shared in-flight work;
  - a FIFO queue with 4 slots;
  - abort when the last lease drops, with no wait;
  - writes go temp file → flush → rename → upsert, and the superseded file is deleted only when its name differs;
  - a per-link persisted 24 h wait, recorded in memory first;
  - 30-day revalidation;
  - 1 h `lastShownAt` throttle;
  - eviction above the budget, never the new icon;
  - `ItemIconCache.disabled()`;
  - `dispose()` aborts every request and awaits the write queue.

  Verify: every group 5 test passes and the rows go green.

## 6. Wiring

- [ ] 6.1 Write failing tests in `test/application/app_services_item_icons_test.dart`. Verify they fail before wiring:
  - committing a catalog with icon links sends no icon request;
  - `AppServices` without `itemIcons` uses the disabled cache and sends no icon GET;
  - `dispose()` aborts an in-flight icon request before the client closes.
- [ ] 6.2 Add `LocalPaths.itemIcons`. Make `AppServices` take an optional `ItemIconCache? itemIcons` (default disabled), with `open()` building the real cache on `paths.itemIcons` and degrading to disabled if the folder cannot be created (one `debugPrint`). `initialize()` awaits `itemIcons.open()`, and `dispose()` disposes the cache before `_client.close()`. Verify: the group 6 tests pass, and `test/data/local_paths_test.dart` covers the new path.

## 7. UI

- [ ] 7.1 Write failing widget tests in `test/ui/item_icon_test.dart` for the widget rows: generic while loading and after a failure; generic on an undecodable file; generic then the new icon when switching item; a late completion for the old item never drawn; switching item releases the old lease. Use a fake cache with controllable leases and a tiny real WebP fixture written to a temp file. Run file I/O and decoding in `tester.runAsync` where needed.
- [ ] 7.2 Implement the `ItemIcon` widget in `lib/ui/item_icon.dart` per D4. Verify: the group 7.1 tests pass and the rows go green.
- [ ] 7.3 Write failing tests in `test/ui/item_icon_surfaces_test.dart`:
  - the Scanner card shows the icon in wide and narrow layouts, without `Identity only • no artwork`;
  - the Map compact card shows the icon next to the name;
  - a history row shows its icon;
  - a row from another mode stays generic and acquires nothing.
- [ ] 7.4 Use `ItemIcon` keyed by item id in `ItemDecisionCard`: the wide image box (in place of the Material icon, with the label removed), and a small icon beside the name in the compact and narrow detail. Use it in `HistoryPanel` rows when the row's mode equals the catalog mode and the item resolves, otherwise keep the generic icon. Verify: the 7.3 tests pass, the rows go green, and the existing `scanner_screen_test.dart`, `map_screen_test.dart` and `latest_scan_card_test.dart` still pass.

## 8. Integration check

- [ ] 8.1 Run `dart format .`, `mise run analyze` and `mise run test`. Verify all three are clean, every test map row is green, and `openspec validate add-item-icons --strict` passes.

## Workflow follow-up

- The live look of the icons (Scanner and Map cards, history rows, with the game running) is a user-verified M4.5 exit criterion. It stays unverified until the user reports it. Agents do not run it (AGENTS.md).
- After the PR merges, `specwright-roadmap next` continues with `design-map-marker-icons` (M4.5 change 3).
