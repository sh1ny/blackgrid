# Tasks

## Test map

All rows are service tests in `test/application/app_services_refresh_test.dart` over a real `AppServices`, built with:

- a recording `MockClient` whose catalog and tracker responses can be held on `Completer`s;
- an in-memory `BlackgridDatabase` subclass whose `loadCatalog` can be held;
- a credential-store fake whose reads can be held or made to throw;
- awaits on the `automaticRefreshes` future from design D3, with no sleeps.

One catalog fetch is counted as the requests to one dataset path (`/<route>/items`). A test name is the scenario name prefixed by its group (`catalog:` or `progress:`).

`green` marks a guard scenario. It asserts something the code already does (no request), so it passes before the implementation. Its task runs it before and after the change, and, where noted, shows that it fails once the guard it protects is removed.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| catalog-authority → Selecting a known mode starts one catalog refresh | Launch with a cached snapshot | `test/application/app_services_refresh_test.dart` | `catalog: launch with a cached snapshot` | green |
| catalog-authority → Selecting a known mode starts one catalog refresh | Launch with no cache | same | `catalog: launch with no cache` | green |
| catalog-authority → Selecting a known mode starts one catalog refresh | Unreadable cache still refreshes | same | `catalog: unreadable cache still refreshes` | green |
| catalog-authority → Selecting a known mode starts one catalog refresh | Unknown mode makes no request | same | `catalog: unknown mode makes no request` | green |
| catalog-authority → Selecting a known mode starts one catalog refresh | Selection superseded during the cached load | same | `catalog: selection superseded during the cached load` | green |
| catalog-authority → Selecting a known mode starts one catalog refresh | Manual refresh already succeeded during the cached load | same | `catalog: manual refresh already succeeded during the cached load` | green |
| catalog-authority → Selecting a known mode starts one catalog refresh | Manual refresh during the automatic one | same | `catalog: manual refresh during the automatic one` | green |
| catalog-authority → A failed automatic catalog refresh is not retried | Startup fetch fails with a cached snapshot | same | `catalog: startup fetch fails with a cached snapshot` | green |
| catalog-authority → A failed automatic catalog refresh is not retried | Startup fetch fails with no cache | same | `catalog: startup fetch fails with no cache` | green |
| catalog-authority → A failed automatic catalog refresh is not retried | Manual refresh after a failure | same | `catalog: manual refresh after a failure` | green |
| catalog-authority → An automatic refresh never publishes into another mode | Switch during the automatic refresh | same | `catalog: switch during the automatic refresh` | green |
| catalog-authority → An automatic refresh never publishes into another mode | Failure after a switch | same | `catalog: failure after a switch` | green |
| catalog-authority → An automatic refresh never publishes into another mode | Switch back while the refresh is still in flight | same | `catalog: switch back while the refresh is still in flight` | green |
| progress-authority → Selecting a known mode with a saved credential starts one progress refresh | Launch with a saved credential | same | `progress: launch with a saved credential` | red |
| progress-authority → Selecting a known mode with a saved credential starts one progress refresh | No saved credential | same | `progress: no saved credential` | green |
| progress-authority → Selecting a known mode with a saved credential starts one progress refresh | Unreadable credential | same | `progress: unreadable credential` | green |
| progress-authority → Selecting a known mode with a saved credential starts one progress refresh | Unknown mode makes no request | same | `progress: unknown mode makes no request` | green |
| progress-authority → Selecting a known mode with a saved credential starts one progress refresh | Selection superseded during the credential read | same | `progress: selection superseded during the credential read` | red |
| progress-authority → Selecting a known mode with a saved credential starts one progress refresh | Saving a credential does not refresh | same | `progress: saving a credential does not refresh` | green |
| progress-authority → A failed automatic progress refresh is not retried | Tracker unavailable at launch | same | `progress: tracker unavailable at launch` | red |
| progress-authority → A failed automatic progress refresh is not retried | Tracker answers with a cooldown | same | `progress: tracker answers with a cooldown` | red |
| progress-authority → A failed automatic progress refresh is not retried | Rejected credential | same | `progress: rejected credential` | red |
| progress-authority → An automatic progress refresh never publishes into another selection | Switch during the automatic refresh | same | `progress: switch during the automatic refresh` | red |
| progress-authority → An automatic progress refresh never publishes into another selection | Switch back before the old fetch returns | same | `progress: switch back before the old fetch returns` | red |

## 1. Automatic catalog refresh

Skills: `dart-add-unit-test`, `dart-write-documentation`, `dart-run-static-analysis` (AGENTS.md "Dart and Flutter code").

- [x] 1.1 Create `test/application/app_services_refresh_test.dart` with the shared rig from the test map: a recording `MockClient` that answers catalog datasets from `test/fixtures/m1/catalog` and tracker routes from `tokenWire`, with optional held responses; the held-`loadCatalog` database subclass; the holdable credential fake. Verify that the file compiles and an empty `group` runs under `mise run test -- test/application/app_services_refresh_test.dart`.
- [x] 1.2 Write the catalog red tests (rows `catalog:` marked red). Each test that waits on background work awaits `automaticRefreshes`, captured before a mode switch where the scenario switches. Verify each fails for the right reason: no automatic fetch, so the fetch count is 0 and the status stays `stale`, `missing` or `failed`.
- [x] 1.3 Write the catalog guard tests (`catalog: unknown mode makes no request`, `catalog: manual refresh already succeeded during the cached load`). Verify they pass before the implementation.
- [x] 1.4 Implement D1, D2 and D3 for the catalog in `lib/application/app_services.dart`. In `_syncMapSession`, chain onto `catalog.setMode(mode)`. Start `unawaited(catalog.refresh())` only while `!_disposed`, the captured `_modeTransition` is unchanged, `mode != GameMode.unknown` and `catalog.status != CatalogStatus.current`. Keep `_modeChange` as the `Future.wait` of the `setMode` calls only. Add the `@visibleForTesting automaticRefreshes` getter (one fixed future per selection, covering `setMode` and any started refresh) with a `///` doc comment. Verify that every `catalog:` row passes, then flip the red rows to green. Remove the `current` check, confirm `catalog: manual refresh already succeeded during the cached load` fails, then restore it.
- [x] 1.5 Fix `test/application/app_services_test.dart:64-70`, whose throwing client the automatic refresh now silences (design Risks, first bullet). Replace it with a recording client that answers catalog datasets. Await the last selection's `automaticRefreshes`, then assert that every recorded request goes to `json.tarkov.dev` and none to `api.tarkovtracker.org`, with no route assertion. Verify that the test passes, and that it fails when a tracker request is injected.
- [ ] 1.6 Run `mise run test`. For every other failure, update the assertion only where it encodes the old "no automatic refresh" behaviour, list each such update in the task's commit message, and leave unknown-mode "no request" tests (`test/application/m1_flow_test.dart:21`, `catalog_controller_test.dart:83`) unchanged. Verify that `mise run test` passes.

## 2. Automatic progress refresh

Skills: `dart-add-unit-test`, `dart-write-documentation`, `dart-run-static-analysis`.

- [ ] 2.1 Write the progress red tests (rows `progress:` marked red) on the rig from 1.1. For the cooldown row, answer `429` with a `Retry-After`, assert the `cooldown` status and a fixed request count, then call `progress.refresh()` before the deadline and assert no new request. Verify each fails because no automatic tracker request is made.
- [ ] 2.2 Write the progress guard tests (no saved credential, unreadable credential, unknown mode, saving a credential does not refresh). Verify they pass before the implementation.
- [ ] 2.3 Implement the progress chain in `_syncMapSession`. When `progress.setMode(mode)` completes and the same transition, disposal and unknown-mode fence holds, call `unawaited(progress.refresh())`, included in that selection's `automaticRefreshes`. There is no status check (design D1). Verify that every `progress:` row passes and flip the red rows to green. Then make the fence always pass, confirm `progress: selection superseded during the credential read` fails, and restore the fence.
- [ ] 2.4 Run `mise run test` and fix any remaining fallout under the rule in 1.6. Verify that it passes.

## 3. Documentation

- [ ] 3.1 Update `README.md`:
  - "First steps" step 2: choosing a mode refreshes the catalog automatically, and **Refresh complete catalog** is for a manual retry.
  - "Data sources and freshness" (line 185): replace "refresh is manual" with launch and mode-switch refreshes of the catalog, and of progress when a token is saved, with no automatic retries.

  Verify with `grep -n "refresh is manual" README.md`, which must return nothing.
- [ ] 3.2 Update `openspec/architecture.md`:
  - `AppServices` row: it starts the catalog and progress refresh after each mode selection.
  - Resource bounds "Catalog refresh" row (line 106): automatic on selection, no retry.

  Do not touch the ADR index (design: no new ADR). Verify that `openspec validate add-catalog-startup-refresh --strict` passes and that the diff touches only those rows.

## 4. Integration checks

- [ ] 4.1 Run `mise run analyze`, `mise run test` and `dart format --output=none --set-exit-if-changed lib test`. Verify that all three pass and that every test-map row is green.

## Workflow follow-up

- The PR title is `feat(catalog): refresh catalog and progress on mode selection`, and its body says `Closes #41`.
- User check, not run by agents: after launch with a cached catalog and a saved token, the status bar shows the catalog and progress as `current` without pressing Refresh. Record it as unverified until the user reports it.
