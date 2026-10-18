# Tasks

## Test map

Paths are relative to the repo. Short names in the table:

- `authority`: the new `test/domain/catalog_authority_test.dart`, pure `CatalogSnapshot` tests built through `decisionCatalog`.
- `normalizer`: `test/data/catalog_normalizer_test.dart`.
- `controller`: `test/application/catalog_controller_test.dart`, with a fake clock and `testWidgets` fake time for timers, no sleeps.
- `label`: the new `test/ui/evidence_source_time_label_test.dart`, a unit test of a pure label function.

Every row is new or changed behaviour, so every row starts red. The cached-snapshot row is an existing passing behaviour and starts green; its test is rerun.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Catalog authority is measured from download time | Live wire shape becomes current | normalizer; controller | live wire shape without dataset timestamps is authoritative at observation; refresh of the live wire shape publishes current || green |
| Catalog authority is measured from download time | No source timestamp anywhere | authority | no source times: authoritative through 24 h, not at 24 h + 1 ms || green |
| Catalog authority is measured from download time | Old source timestamp does not revoke authority | authority | items source time 30 days old does not revoke authority || green |
| Catalog authority is measured from download time | Observation in the future | authority | future observation is not authoritative || green |
| Catalog authority is measured from download time | Unsupported source or unknown mode | authority | unsupported source or unknown mode is not authoritative || green |
| Current catalog status expires 24 h after observation | Expiry at the observation limit | controller | catalog local/source expiry timer notifies without scheduling requests | red |
| Current catalog status expires 24 h after observation | Old items update time does not shorten the window | controller | old items source time does not shorten the current window | red |
| Current catalog status expires 24 h after observation | Cached snapshot at startup | controller | cached startup stale; candidate invisible until durable commit then current | green |
| Source-time evidence reflects what the source provides | Newest item update recorded | normalizer | items source time is the newest per-item updated; other datasets absent || green |
| Source-time evidence reflects what the source provides | Items without update times | normalizer | items without updated leave every source time absent and stay authoritative || green |
| Source-time evidence reflects what the source provides | Malformed item update time | normalizer; controller | malformed item updated fails validation; refresh failure retains last-good || green |
| Source-time evidence reflects what the source provides | Dataset-level update field is ignored | normalizer | dataset-level updated is ignored || green |
| Source-time evidence reflects what the source provides | Evidence view with no items update time | label | absent items source time reads unknown | red |

"Red" for the controller expiry row means the test is rewritten: today it passes only because the fixture carries dataset-level times, and it must keep passing with `decisionCatalog`'s new items-only default. The malformed-time row is red for the normalizer part, which is a new assertion; the controller part reuses the existing last-good path.

## 1. Fixtures match the live wire shape

- [x] 1.1 Edit `test/fixtures/m1/catalog/six_datasets.json`: remove every dataset-level `updated`, add `"translations": []` to each of the six dataset envelopes, and give `item-a` `updated` `2026-10-05T10:00:00Z` and `item-b` `2026-10-05T23:00:00Z` (both before `fixtureNow`). In `fixture.dart`, update the `sharedObjectiveWireFixture` comment and drop its now-redundant `remove('updated')`/`translations` lines; change the `decisionCatalog` default `times` to `{'items': fixtureNow, others: null}`. Verify with `mise exec -- flutter test test/data/catalog_normalizer_test.dart test/data/catalog_client_test.dart`. Expected result: the tests that relied on dataset-level times (for example the `current` assertions in the controller tests) now fail, which proves the fixture previously hid the bug. Record which tests fail.

## 2. Authority from observation time (D1, D3)

- [x] 2.1 Write the red tests: the `authority` file (rows 2–5), the normalizer live-shape test (row 1), and the controller "refresh of the live wire shape publishes current" test (row 1), which runs `CatalogClient` over a `MockClient` serving `wireFixture()`. Rewrite the existing assertions that encoded the bug: `catalog_normalizer_test.dart:125-127` and `catalog_client_test.dart:109-110` must now expect authority, and replace the "missing and mixed source times stay unknown" test with the row 12 test. Run them and record that they fail because authority is false (the source-time clause).
- [x] 2.2 In `lib/domain/catalog.dart`, delete `sourceFreshAt` and its clause in `authoritativeAt`. Keep `schemaVersion`/`normalizerVersion` at 1. Add `///` docs to `authoritativeAt` and `sourceTimestamps` stating the rule (dartdoc per `dart-write-documentation`). In `lib/domain/decision_engine.dart:27-29`, change the warning to `Catalog authority missing or stale`. Update `decision_engine_test.dart:364`: a catalog with no source times now follows observation age only, so assert that it is not forced to Check by the catalog (state the expected recommendation for that fixture). Run `test/domain/` plus the rows from 2.1 to green, and flip rows 1 (normalizer part) to 5.

## 3. Source-time evidence (D2)

- [x] 3.1 Write the red normalizer tests for rows 9–12. Row 11 uses the string `yesterday` and expects a `FormatException`. Row 12 puts dataset-level `updated: 2020-01-01T00:00:00Z` on `items` and `traders` and expects the items time to come from the items only and traders to be null. Run them and record the failures.
- [x] 3.2 In `lib/data/catalog_normalizer.dart:383-385`, build `times` as `items` = max of the normalised items' `updatedAt` (null when none), the other five null, and stop reading `roots[key]['updated']`. Run the normalizer, client and database tests to green (`CatalogSnapshot.fromJson` round trip included), and flip rows 9–12.

## 4. Expiry from observation only (D4)

- [ ] 4.1 Write the red controller test for row 7 with `testWidgets` fake time. A `ControlledCatalogClient` returns `decisionCatalog(times: {'items': T - 23 h, ...})` observed at T. Assert `current` after refresh, still `current` after pumping to T + 2 h, and `stale` after pumping to T + 24 h + 1 ms without calling `updateAge`, with `client.calls == 1`. Run it and record the failure. On the current code the timer fires at T + 1 h and nothing demotes at T + 24 h. Run it after 2.2, so the failure is caused by the timer and not by authority.
- [ ] 4.2 In `lib/application/catalog_controller.dart:109-121`, arm the timer at `observedAt + 24 h` only and remove the source-time loop. Rerun the whole controller file to green (rows 1, 6, 7, and row 8 rerun as the green check), and flip rows 1 (controller part), 6, 7 and 8.

## 5. Evidence panel text

- [ ] 5.1 Write the red `label` test (row 13) for a new top-level pure function in `lib/ui/evidence_panels.dart` (or a small sibling file). It returns `Items source update: <ISO-8601 UTC>` when the items source time exists and `Items source update: unknown` when it is absent. Run it red.
- [ ] 5.2 Implement the function and use it in place of the `Source freshness:` line (`evidence_panels.dart:120-123`). Change the subtitle at `evidence_panels.dart:103` from `Observation is not source freshness` to `Catalog age is measured from download`. Run the label test and `test/ui/` to green, and flip row 13.

## 6. Documentation

- [ ] 6.1 Update `README.md:181` (freshness column: `24 h from download`) and remove the stale sentence at `README.md:185` that says a successful refresh still shows stale. Update `openspec/architecture.md:90` so `current` means a fresh fetch observed under 24 h ago, with source times as evidence only, and fix the cited line range. Verify with `git diff --check` and by rereading the changed lines.

## 7. Integration checks

- [ ] 7.1 Run `mise run analyze` and `mise run test`, and format every changed Dart file with pinned `dart format` (`mise exec -- dart format <files>`). Fix failures without weakening any authority, ownership or validation check. Record both results.
- [ ] 7.2 Run `openspec validate fix-catalog-freshness --strict` and confirm every test-map row is green.

## Workflow follow-up

- Live check (user only, never an agent): with the game not running, refresh the catalog for each mode in the app and confirm the status reads `current`. Record it as unverified until the user reports it.
- Pre-ship review (specwright-review), then PR only when the user asks; archive and finish per `finish: pr`.
