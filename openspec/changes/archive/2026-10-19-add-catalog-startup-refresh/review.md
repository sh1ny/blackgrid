# Review

## Metadata

- **Round:** 1 (re-check run)
- **Prior round:** round 1 APPROVE_WITH_CHANGES with Required Changes 1-4; this run re-checks them and the applied suggestions S1-S6
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:** proposal.md, design.md, specs/catalog-authority/spec.md (delta, against openspec/specs/catalog-authority/spec.md), specs/progress-authority/spec.md; openspec/architecture.md, openspec/roadmap.md (M4 exit criteria, change 4), docs/IMPLEMENTATION_STRATEGY.md (refresh lines), docs/adr/0002; source: lib/application/app_services.dart, catalog_controller.dart, progress_controller.dart, map_session_controller.dart (effectiveMode), lib/data/catalog_client.dart, lib/data/tracker_client.dart, lib/domain/catalog.dart (GameMode), lib/ui/manual_controls.dart, lib/application/scan_coordinator.dart (`_syncIndex`); tests: test/support/m1_harness.dart, test/support/m1_widget_harness.dart, test/application/app_services_test.dart, test/application/m1_flow_test.dart, test/widget_test.dart. Drift 2.35.1 engine close semantics (closed executor throws `StateError`, so a commit after `dispose` is caught by the controller). `openspec validate --strict` passes. Skills loaded: dart-add-unit-test, dart-write-documentation, dart-run-static-analysis.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None. The core wiring holds against the code: `_modeTransition` (app_services.dart:235) is a sound pre-start fence; after the start, the catalog generation/per-mode join (catalog_controller.dart:73-127) and the progress session check (progress_controller.dart:157-182) already drop superseded results; both `setMode` methods catch every error, so a chained `.then` never sees a rejected future; both clients have 30 s timeouts (catalog_client.dart:33, tracker_client.dart:83); detected mode is sticky (`mode ?? _state.detectedMode`, session_log_reader.dart:119), so session evidence does not flap the trigger.

### Moderate

**M1. Three spec THENs contradict the controllers they describe, so a test written to the spec fails or pushes the implementer into an unscoped controller change.**
- catalog-authority, "Launch with no cache": "the status is `missing` until the fetch returns". The automatic `refresh()` enters `_refresh`, which publishes `loading` before its first await (catalog_controller.dart:95-97). So the status is `missing` only between the cached read and the refresh start, then `loading` until the fetch returns.
- catalog-authority, "Unreadable cache still refreshes": "the status is `failed` with "Stored catalog unavailable", one fetch is still made". The refresh immediately clears `error` and publishes `loading` (catalog_controller.dart:95-97). The `failed` state is only a transient published state, but the THEN reads as the state while the fetch runs.
- progress-authority, "Tracker unavailable at launch": "the progress status is `failed` with "Tracker unavailable"". An unreachable tracker surfaces as `TrackerException(TrackerFailure.unavailable)` (tracker_client.dart:90-91), and the controller sets `error = failure.toString()` = "Tracker transport unavailable" (progress_controller.dart:163-165, tracker_client.dart:29). "Tracker unavailable" comes only from the non-`TrackerException` branch (progress_controller.dart:179-181).

**M2. An existing "no HTTP" guard silently stops guarding, and the design's test-update rule will not catch it.** In `app_services_test.dart:64-70` ("saved log context outranks fallback…") the client throws `StateError('Saved Map inputs must not request HTTP')`. After this change the effective mode `pve` starts a catalog refresh. `CatalogClient._get` turns the throw into a `CatalogException` (catalog_client.dart:46-48) and the controller swallows it (catalog_controller.dart:119-125). The test keeps passing, but it no longer proves what its message claims, and the catalog ends `failed` for a reason the test never states. The design's risk row ("Update each failing assertion only where it states the old behaviour") only covers tests that fail.

### Suggestions

- **S1. D3: say what the getter returns, so the "switch during refresh" tests need no poll.** For "Switch during the automatic refresh" and "Failure after a switch", a test must await A's refresh (fetch, `Isolate.run` normalise, drift commit) after B is selected, but D3 exposes only the latest selection's refreshes. That works only if `automaticRefreshes` returns a fixed future object that the test captures before switching, not a live view. Also say that it covers the `setMode` phase too, so a read before the cached load ends does not complete "immediately because none were started".
- **S2. Resource Bounds says "2 known modes".** `GameMode` has three known values: `pvp`, `pve`, `seasonal` (catalog.dart:3-8). The bound is 3 concurrent catalog fetches. That is still constant, so only the table needs fixing.
- **S3. Redundant fetch after a manual refresh during the cached read can downgrade a just-`current` catalog.** If the manual fetch commits during the cached read, the automatic refresh starts a second fetch, which publishes `loading` and, if it fails, ends `stale` with an error over a snapshot that was `current` moments before. A one-line skip in the D1 callback (`catalog.status == CatalogStatus.current`) removes both the extra fetch and the downgrade. Otherwise, add the failure case to the "Suppress the redundant fetch" ledger row.
- **S4. Proposal wording on cooldown.** "A progress cooldown is respected" overstates it: `_invalidate` clears `cooldownUntil` on every selection (progress_controller.dart:52), so A -> B -> A during a cooldown sends a tracker request. The ledger and spec describe this correctly ("manual refresh during a cooldown"). Align the proposal bullet with them.
- **S5. progress-authority Purpose says it decides "when its result may back item decisions"**, but the spec has no requirement about that. Narrow the Purpose to refresh timing, or leave it and accept that the archived spec over-promises until a later change adds those requirements.
- **S6. Test seams.** The "superseded during the cached load" catalog scenario needs a held `loadCatalog`. `AppServices` takes a concrete `BlackgridDatabase`, so the test needs a hand-written subclass overriding `loadCatalog` with a `Completer`. The generative `BlackgridDatabase(QueryExecutor)` constructor allows this. Counting "one fetch" means counting requests to one dataset path, because a catalog fetch issues ~10 HTTP requests (catalog_client_test.dart:76). Naming both in the tasks prevents a sleep or poll creeping in (AGENTS.md).

## Verdict

Round 1 verdict (superseded by round 2 below): APPROVE_WITH_CHANGES

## Required Changes

1. catalog-authority delta, scenario "Launch with no cache": replace the THEN with "the status is `missing` after the cached read, then `loading` while the fetch runs; exactly one fetch is made, and the status then becomes `current`" (or equivalent wording that matches catalog_controller.dart:95-97).
2. catalog-authority delta, scenario "Unreadable cache still refreshes": make the THEN ordered: "the status is first published `failed` with "Stored catalog unavailable", then one fetch is made, and a valid result makes the status `current`".
3. progress-authority delta, scenario "Tracker unavailable at launch": change the expected error to "Tracker transport unavailable", or state the status only (`failed`) without the message.
4. design.md, Risks / Trade-offs: add that `app_services_test.dart` "saved log context outranks fallback…" uses a throwing client as a no-HTTP guard that this change silently disables. Require the task to replace it with a request-recording client that answers the catalog requests, and to assert that every request goes to the catalog source (`json.tarkov.dev`) for a mode the test selects and none goes to the tracker (no credential is saved), with the assertion made after awaiting the last selection's `automaticRefreshes` future. (Amended in the re-check run: the original wording "only catalog-source requests for `pve`" was wrong; see Re-check, item 4. Amended again in the third run: the allowed routes must also include `regular`, for the saved `pvp` selection made before the log is read; see the third run.)

Round 1 changes applied (re-checked in the fourth run): yes

## Re-check (round 1, second run)

Reviewer: fresh-context subagent (specwright-reviewer, Claude Code). Read: the current proposal.md, design.md, both spec deltas; lib/application/app_services.dart, catalog_controller.dart, progress_controller.dart, map_session_controller.dart (`effectiveMode`), lib/data/catalog_client.dart, tracker_client.dart, database.dart (`loadCatalog`), lib/domain/catalog.dart (`GameMode`), test/application/app_services_test.dart. `openspec validate add-catalog-startup-refresh --strict` passes. Skills loaded: dart-add-unit-test, dart-write-documentation, dart-run-static-analysis.

Required Changes:

1. **"Launch with no cache": PASS.** The THEN reads "`missing` once the cached load ends, then `loading` while the fetch is in flight". That matches `setMode` publishing `missing` (catalog_controller.dart:60,70) followed by `_refresh` publishing `loading` (:95-97).
2. **"Unreadable cache still refreshes": PASS.** The THEN is now ordered ("first `failed` with "Stored catalog unavailable", then exactly one fetch"). That matches :67-70, then :95-97.
3. **"Tracker unavailable at launch": PASS.** The expected error is "Tracker transport unavailable", which `TrackerException(TrackerFailure.unavailable).toString()` returns (tracker_client.dart:29, 90-91; progress_controller.dart:165).
4. **Silenced no-HTTP guard: FAIL.** The risk row was added as required, but the assertion it requires ("every recorded request is a catalog request for `pve`") is wrong for this test, and the error goes back to my round-1 wording. Later in the same test, the effective mode becomes `seasonal` (app_services_test.dart:113-119 asserts `catalog.mode == GameMode.seasonal`). Under D1 that selection starts an unawaited catalog refresh on route `pvp-season`. If its requests are recorded before the assertion runs, the assertion fails; if not, it passes. Written as specified, the test therefore either fails or is order-dependent (flaky). Exact fix in design.md, Risks / Trade-offs, first bullet: replace "asserts that every recorded request is a catalog request for `pve`" with "awaits the last selection's `automaticRefreshes` future, then asserts that every recorded request goes to `json.tarkov.dev` on a route of a mode the test selects (`pve`, then `pvp-season` for `seasonal`) and none goes to `api.tarkovtracker.org`". Required Change 4 above has been amended to match.

Applied suggestions (content outside the required items, checked for correctness):

- **S1 / S6 (D3 test future and seams): PASS.** The future is fixed per selection and can be captured before `setMode`. The field is replaced inside `_syncMapSession`, which `AppServices.setMode` runs only after `settings.setMode` (app_services.dart:250-252), so a value captured before the call belongs to the previous selection. The future cannot reject: both `setMode` methods and both `_refresh` methods catch every error. `BlackgridDatabase(super.executor)` is generative and `loadCatalog` is an overridable instance method (database.dart:78,105), so the held-load subclass works. Counting one dataset path per fetch matches `CatalogClient.fetch`, which sends one request per dataset plus one per translation (catalog_client.dart:57-72).
- **S2 (three modes): PASS.** The modes are `pvp`, `pve` and `seasonal` (catalog.dart:3-8).
- **S3 (skip when already `current`): PASS. It cannot skip a fresh selection wrongly.** `CatalogController.setMode` resets `status` to `loading` synchronously for a known mode (catalog_controller.dart:46-49), so no earlier mode's `current` survives into the new selection. After the cached read, `setMode` publishes `stale`, `missing` or `failed` (:59-70), unless `_refreshPublication` moved. Only a successful `_refresh` moves it, and only when `mode == key` and `_refreshGenerations[key] == _generation` (:101-104). That generation is stamped only by a `refresh()` call made after this selection's `setMode` bumped `_generation` (:77), so an in-flight fetch from an earlier selection of the same mode cannot publish unless this selection joined it. `current` at the end of the cached load therefore means a fetch joined or started by this very selection has already published `current`. The D1 check is also ANDed with the `_modeTransition` fence, so a superseded selection is never judged by the newer one's status. A manual refresh that fails during the cached load does not move `_refreshPublication`, so the cached result still publishes and the automatic fetch runs, as the Flow & State Gaps row states. A candidate that is not authoritative publishes `stale` and does not trigger the skip, which matches the spec clause ("already `current`").
- **S4 (proposal cooldown wording): PASS.** "A new mode selection clears the cooldown, as it does today" matches `_invalidate` (progress_controller.dart:52).
- **S5 (progress-authority Purpose): PASS.** "When fetched … and which fetch results may be published" is now covered by the third requirement ("never publishes into another selection").

Result: items 1-3 and S1-S6 hold. Item 4 is still wrong, as stated above. `CHANGES_APPLIED` stays `no` until design.md carries the corrected assertion.

## Re-check (round 1, third run)

Reviewer: fresh-context subagent (specwright-reviewer, Claude Code). Scope: Required Change 4 only, against the edited first bullet of design.md "Risks / Trade-offs". Read: design.md (that bullet, D1-D3), test/application/app_services_test.dart, lib/data/catalog_client.dart, lib/data/tracker_client.dart, lib/domain/catalog.dart (`catalogRoute`), and, to trace the selections the test makes, lib/application/app_services.dart (`initialize`, `_syncMapSession`) and map_session_controller.dart (`effectiveMode`, `updateMapContext`, `_onPreferences`). Skills loaded: dart-add-unit-test, dart-write-documentation, dart-run-static-analysis.

4. **Silenced no-HTTP guard: FAIL.** The bullet now names the request-recording client, awaits the last selection's `automaticRefreshes`, forbids tracker requests, and adds `pvp-season`. Those parts are right: the hosts are `json.tarkov.dev` (catalog_client.dart:25) and `api.tarkovtracker.org` (tracker_client.dart:69), and the routes are `pve` and `pvp-season` (catalog.dart:11-13). But the list of allowed routes is still incomplete, so the test it describes would still fail or flake. My earlier amendment missed this too. The test saves `mode: GameMode.pvp` (app_services_test.dart:76-82) before `initialize()`. In `initialize`, `_syncMapContext()` (app_services.dart:191) runs before `mapSession.initialize()` (:193). Because `_mapContentGeneration` starts at -1 (:142), it always calls `updateMapContext`, which notifies (map_session_controller.dart:294-295). The listener `_syncMapSession` then sees `effectiveMode == pvp`, because no log has been read yet (:77-79), and `_appliedMode` is still null (app_services.dart:145, 233). So it selects `pvp` and calls `catalog.setMode(pvp)`. Under D1 that selection starts a catalog refresh on route `regular` if its in-memory cached load finishes before the log bind moves the mode to `pve`. That is a race between drift and file I/O, and drift will usually win. The assertion as written ("`pve`, then `pvp-season`") then fails on `regular` requests, or passes only when the log bind wins. Awaiting the last selection's future does not help, because those requests belong to an earlier selection. Exact fix in the same bullet: change the parenthetical to "(`regular` for the saved `pvp` mode before the log is read, `pve` once the log is read, then `pvp-season` after the later switch to `seasonal`, `app_services_test.dart:76-82, 113-119`)". Equivalently, assert only that every recorded request has host `json.tarkov.dev` and none has host `api.tarkovtracker.org`. Required Change 4 stands with this correction. No other new defect was found in the edit.

Result: `CHANGES_APPLIED` stays `no` until the allowed routes in that bullet include `regular`, or the route check is dropped in favour of the host check.

## Re-check (round 1, fourth run)

Reviewer: fresh-context subagent (specwright-reviewer, Claude Code). Scope: Required Change 4 only, against the edited first bullet of design.md "Risks / Trade-offs". Read: that bullet, test/application/app_services_test.dart, lib/application/app_services.dart, lib/data/catalog_client.dart, lib/data/tracker_client.dart. Skills loaded: dart-add-unit-test, dart-write-documentation, dart-run-static-analysis.

4. **Silenced no-HTTP guard: PASS.** The author took the second fix the third run offered: the bullet drops the route check and asserts hosts only. Every recorded request must go to `json.tarkov.dev` (catalog_client.dart:25) and none to `api.tarkovtracker.org` (tracker_client.dart:69). It does this after awaiting the last selection's `automaticRefreshes`. Every selection the test can make (`regular`, `pve`, `pvp-season`) fetches from the catalog host, so the order of the cached load and the log read no longer changes the result. Requests from an earlier selection that arrive after the assertion also go to the catalog host, so they cannot falsify it. The bullet explains the race correctly (app_services_test.dart:76-82, app_services.dart:191-193). The edit adds no new defect. Required Change 4 is applied.

Result: Required Changes 1-4 and S1-S6 hold. Round 1 changes applied: yes.

---

# Review (round 2: behaviour-change amendment 0a88b8f)

## Metadata

- **Round:** 2
- **Prior round:** round 1 APPROVE_WITH_CHANGES. Required Changes 1-4 were applied and re-checked in the fourth run. Commit 0a88b8f then amended the specs as a behaviour change (PR #44 Codex P1): the automatic progress refresh makes no tracker request while the read-only Tracker integration (`AppSettings.trackerEnabled`, default false) is off, and enabling it starts no refresh. This voided the round 1 verdict, so this round reviews the amended contents in full.
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:** `git show 0a88b8f`; current proposal.md, design.md (D1, T4 diagram, Risks), tasks.md (test map, 2.5), specs/progress-authority/spec.md, specs/catalog-authority/spec.md (checked for any tracker or progress coupling: none). Main specs under openspec/specs (no existing progress or tracker capability, so nothing conflicts) and openspec/architecture.md. Source: lib/application/app_services.dart (`initialize` :195-215, `_syncMapSession` :230-285, `_refreshAfter` :290-304), progress_controller.dart (`setMode` :58-75, `refresh` :124-139, `_refresh` session fence :157,164,180), settings_controller.dart (`save` :25-42), lib/domain/settings.dart (`trackerEnabled = false` :47), lib/ui/settings_dialog.dart (switch :179-200, Refresh progress :242-252), lib/ui/evidence_panels.dart:173-177, map_session_controller.dart (`_onPreferences` :168-180), test/application/app_services_refresh_test.dart (rig `launch`, `progress: saving a credential does not refresh` :643-649). The working tree also holds uncommitted task 2.5 work: the gate at app_services.dart:260-267, the rig's `trackerEnabled` parameter, the new test, and README and architecture.md edits. I read it only as evidence that the design can be implemented. This verdict does not cover it. `openspec validate add-catalog-startup-refresh --strict` passes. Skills loaded: dart-add-unit-test, dart-write-documentation, dart-run-static-analysis.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None. The amendment holds against the code on the points the request asked me to check:

- **Ordering of the settings read vs. the credential read.** The gate is a `when` predicate that `_refreshAfter` evaluates inside `ready.then`, that is, after `progress.setMode` has finished its credential read (app_services.dart:296-300). It is not captured when the selection starts. `initialize` awaits `settings.load()` before any `_syncMapSession` can act, because `_syncMapSession` returns early until `_mapsInitialized` is set (:196-210, :231). So a launch never reads the default `false` before the saved value loads. The same holds on `reloadAfterImport`, which reloads settings first.
- **Switching off mid-session.** The dialog saves the setting and then calls `services.progress.setMode(services.catalog.mode)` directly (settings_dialog.dart:189-199). That call goes around `_syncMapSession`. It does not bump `_modeTransition` and never reaches `_refreshAfter`, so it starts no automatic refresh. `_invalidate` bumps `_session` (progress_controller.dart:47-56), so an automatic fetch already in flight is dropped by the session fence (:157,164,180), and the progress snapshot is cleared. If the switch is turned off while a selection's credential read is still running, the read's result is dropped (session mismatch, :66). When that selection's `ready` then completes, the `_refreshAfter` callback sees `trackerEnabled == false` and starts nothing. No request is made after the switch goes off. A request already sent before then is not cancelled, and the spec does not require that.
- **Settings save does not create a selection.** A preference save notifies `MapSessionController._onPreferences`, which reacts only to map, log and screenshot fields (map_session_controller.dart:168-180). Toggling `trackerEnabled` does not change `effectiveMode`, so `_syncMapSession` opens no transition. Enabling the switch therefore starts no refresh, as the amended scenario requires.
- **Manual parity.** Both manual progress Refresh buttons are already disabled while the switch is off (settings_dialog.dart:244-247, evidence_panels.dart:173-177). D1 keeps the check out of `ProgressController.refresh()`, which matches the existing UI-level gate, and the controller's unit tests stay independent of settings.

### Moderate

**M1. The scenarios that expect a tracker request no longer state their precondition, and with the default settings they are false.** The requirement now says a refresh starts only "while the read-only Tracker integration is enabled", and `trackerEnabled` defaults to `false` (settings.dart:47). The scenarios that assert a request were not amended. These are "Launch with a saved credential" ("exactly one tracker fetch is made"), "Selection superseded during the credential read" ("exactly one is made for B"), "Tracker unavailable at launch", "Tracker answers with a cooldown", "Rejected credential", "Switch during the automatic refresh" and "Switch back before the old fetch returns". Read on its own, each of them describes a fresh install or a default-settings launch, where the code makes no request. The rig in task 2.5 hides this by defaulting to `trackerEnabled: true`, but the archived capability spec would state behaviour that the default configuration does not have. A later test written from the archived spec would fail. Fix: state the precondition once (Required Change 1).

**M2. The new WHEN branch "or enables the Tracker integration" has no test.** The amendment widened the scenario "Saving a credential does not refresh" to "the user saves a valid credential for the selected mode, or enables the Tracker integration". But the test-map row and the existing test (app_services_refresh_test.dart:643-649) cover only saving a credential, and task 2.5 adds no step for enabling. Today the code is correct, because toggling the setting creates no selection. But that branch is exactly the regression a later "refresh when the user turns the integration on" convenience would introduce, for example a `settings` listener in `AppServices`, and nothing would catch it. Fix: Required Change 2.

### Suggestions

- **S1. Say when the gate is read.** The code reads `trackerEnabled` when the credential read ends, not when the selection starts. So a user who enables the switch during a selection's credential read, a window of milliseconds at launch or a mode switch, gets that selection's refresh. That fits the requirement wording ("reads a saved tracker credential for it while ... enabled"), and I see no practical harm. One clause in D1 ("evaluated when `progress.setMode` completes") would stop a later reader from treating this as a contradiction of the "enables the Tracker integration" scenario, or from "fixing" it by capturing the value at selection start. Capturing it at selection start would let a selection whose credential read started before the user switched the integration off still send a request.
- **S2. The proposal's last bullet ("Saving a credential does not trigger an automatic progress refresh") could add "or enabling the Tracker integration"**, so the proposal matches the amended scenario. The scenario title could also become "Saving a credential or enabling the integration does not refresh". If the title changes, rename the test and the test-map row to match.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. specs/progress-authority/spec.md, requirement "Selecting a known mode with a saved credential starts one progress refresh": state the precondition for every scenario that expects a tracker request. Either append to the requirement body: "Unless a scenario says otherwise, the scenarios in this capability assume the read-only Tracker integration is enabled." Or add "with the Tracker integration enabled" to the WHEN of "Launch with a saved credential" and "Selection superseded during the credential read". The scenarios in the other two requirements of the same file also need covering, so the first option is the smaller edit. If the sentence goes into one requirement only, place it under the spec's `## Purpose` or repeat it in each requirement.
2. tasks.md, task 2.5 and the test map: add a guard step for the "enables the Tracker integration" branch. Launch with a saved credential and `trackerEnabled: false`, await `automaticRefreshes`, then save the settings with `trackerEnabled: true` and assert that `net.trackerRequests` is still 0. Put it either as a second case inside `progress: saving a credential does not refresh`, or as a new row `progress: enabling the integration does not refresh` (state `green`). Also confirm that it fails when a refresh is wired to the settings change.

CHANGES_APPLIED: yes

## Re-check (round 2, second run)

Reviewer: fresh-context subagent (specwright-reviewer, Claude Code). Scope: round 2 Required Changes 1-2 and suggestions S1-S2 only, against the uncommitted `git diff` of proposal.md, design.md, tasks.md and specs/progress-authority/spec.md, and the new test in test/application/app_services_refresh_test.dart:607-627. `openspec validate add-catalog-startup-refresh --strict` passes. Skills loaded: dart-add-unit-test, dart-write-documentation, dart-run-static-analysis.

1. **Spec precondition: PASS.** The sentence sits under `## Purpose`, so it covers all three requirements. The two scenarios that do not assume the integration is on, "Tracker integration disabled" and "... or enables the Tracker integration", say so in their own WHEN, so "unless a scenario says otherwise" fits both.
2. **Guard for enabling the integration: PASS.** The test-map row (`green`) and the step in task 2.5 are present. The test is sound without a sleep. `ProgressController._refresh` publishes `loading` before its first await (progress_controller.dart:147-149), and `SettingsController.save` notifies only after `_settings` holds the new value (settings_controller.dart:32,40). So any refresh wired to the settings change is caught by the `loading` listener even before its request is sent, and the `net.trackerRequests == 0` check backs that up. The coordinator reports that the mutation check failed as expected. I did not run it again.

Suggestions: **S1 PASS.** D1 now says the gate is evaluated when `progress.setMode` completes, which matches `_refreshAfter` (app_services.dart:296-300). **S2 PASS.** The proposal bullet now covers enabling the integration.

Result: round 2 Required Changes 1-2 hold. CHANGES_APPLIED is set to yes on the single line above.

## Rebuttals
