# Tasks

Implementation notes carried from the review's suggestions (S1-S7, non-blocking):

- **S1:** watch `CaptureService.workerExit` and `VisionService.workerExit`, so a worker that dies while no scan runs still makes live scan `unavailable`.
- **S2:** `bgc_hook_stop` can block the UI isolate for up to 1 s. Call stop only on switch-off or dispose. After a `stopTimedOut`, check the stuck hook (retry `stop`) before reopening the vision runtime on the next switch-on.
- **S3:** build the title index only while live scan is on.
- **S4:** the recent list keeps summaries only. Crop bytes are kept for the latest report only.
- **S5:** a pass with no marker has no `marker`…`ocr` stamps; they are absent, not zero.
- **S6:** a save refused as busy shows the same error as a failed save.
- **S7:**
  - The runtime directory is `File(Platform.resolvedExecutable).parent.path`, injectable for tests.
  - A UI-side capture platform that fails to open at switch-on ends `unavailable` with that reason.

Test conventions (AGENTS.md):

- Use hand-written fakes injected through constructors or factories.
- Never use sleeps. Use completers, fake clocks, and short injected deadlines and drains.
- Build cross-isolate fakes from top-level factories over shared native control memory (`test/data/capture/support/holdable_capture_platform.dart`, `test/data/vision/support/holdable_vision_native.dart`).
- Prove each invariant at the cheapest layer: coordinator rules in coordinator tests, not widget tests.
- Agents never launch the app while Escape from Tarkov runs, and never run live-game checks.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| inspection-capture → Frames carry their provenance | Frame provenance | test/data/capture/capture_policy_test.dart | existing provenance test (request id 42) | green |
| inspection-capture → Frames carry their provenance | Clipped provenance | test/data/capture/capture_policy_test.dart | existing clipped provenance test | green |
| inspection-capture → Frames carry their provenance | Client size of a targeted frame | test/data/capture/capture_policy_test.dart | targeted frame reports the validated client size | green |
| inspection-capture → Frames carry their provenance | Client size of a clipped fallback frame | test/data/capture/capture_policy_test.dart | clipped fallback frame reports full client width | green |
| inspection-recognition → Recognition runs only as a vision-worker job | Job runs against a fake runtime | test/data/vision/inspection_job_test.dart | job runs through VisionService over a fake native without loading a library (existing) | green |
| inspection-recognition → Recognition runs only as a vision-worker job | Normal launch | test/data/vision/vision_worker_audit_test.dart | only the scan coordinator references the service or recognition job | red |
| vision-worker → Normal launch does not start the vision worker | No startup path starts the worker | test/data/vision/vision_worker_audit_test.dart | only the scan coordinator references the service or recognition job | red |
| vision-worker → Normal launch does not start the vision worker | Normal launch loads no vision library | test/application/app_services_scan_test.dart | launch with live scan off starts no worker, hook or vision runtime | red |
| vision-worker → Normal launch does not start the vision worker | Live scanning starts the worker | test/application/app_services_scan_test.dart | launch with live scan saved on starts exactly one vision service | red |
| vision-runtime → Normal app launch does not load the vision runtime | Normal launch | test/app/launch_mode_test.dart | no arguments selects UI mode and never constructs runtime (existing) | green |
| vision-runtime → Normal app launch does not load the vision runtime | Unknown argument | test/app/launch_mode_test.dart | existing unknown-argument test | green |
| vision-runtime → Normal app launch does not load the vision runtime | Live scanning on at launch | test/application/app_services_scan_test.dart | live scan on opens the runtime only through the vision service opener | red |
| scan-pipeline → Live scan starts only when enabled | Launch with live scan off | test/application/app_services_scan_test.dart | launch with live scan off starts no worker, hook or vision runtime | red |
| scan-pipeline → Live scan starts only when enabled | Switching live scan on | test/application/scan_coordinator_lifecycle_test.dart | switch-on saves, then template, vision ready, then hook | red |
| scan-pipeline → Live scan starts only when enabled | Launch with live scan saved on | test/application/app_services_scan_test.dart | launch with live scan saved on starts exactly one vision service | red |
| scan-pipeline → Live scan starts only when enabled | Vision runtime cannot start | test/application/scan_coordinator_lifecycle_test.dart | vision start failure is unavailable without a hook | red |
| scan-pipeline → Live scan starts only when enabled | Marker template is invalid | test/application/scan_coordinator_lifecycle_test.dart | invalid marker template is unavailable before any worker | red |
| scan-pipeline → Live scan starts only when enabled | Hook installation refused | test/application/scan_coordinator_lifecycle_test.dart | refused hook is unavailable with OS code and closes vision | red |
| scan-pipeline → Live scan stops cleanly | Switching live scan off while idle | test/application/scan_coordinator_lifecycle_test.dart | switch-off removes hook and closes both workers | red |
| scan-pipeline → Live scan stops cleanly | Setting cannot be saved when switching off | test/application/scan_coordinator_lifecycle_test.dart | failed switch-off save still stops the pipeline | red |
| scan-pipeline → Live scan stops cleanly | A later save does not reinstall the hook | test/application/scan_coordinator_lifecycle_test.dart | unrelated save after failed switch-off keeps live scan off | red |
| scan-pipeline → Live scan stops cleanly | Switching off during start | test/application/scan_coordinator_lifecycle_test.dart | switch-off during a hung start is bounded by the close drain | red |
| scan-pipeline → Live scan stops cleanly | Switching off with a scan in flight | test/application/scan_coordinator_flow_test.dart | switch-off during vision stage publishes nothing and releases the frame | red |
| scan-pipeline → Live scan stops cleanly | Hook thread does not stop | test/application/scan_coordinator_lifecycle_test.dart | stopTimedOut is a visible warning and the next start retries stop | red |
| scan-pipeline → Live scan stops cleanly | Worker drain incomplete at shutdown | test/application/scan_pipeline_isolate_test.dart | dispose with a held native call completes after the drain and publishes nothing | red |
| scan-pipeline → Worker loss makes live scan unavailable | Vision worker exits mid-session | test/application/scan_coordinator_lifecycle_test.dart | vision worker exit removes hook and is unavailable | red |
| scan-pipeline → Worker loss makes live scan unavailable | Restart after loss | test/application/scan_coordinator_lifecycle_test.dart | off then on after loss creates fresh services | red |
| scan-pipeline → Targeted pass runs first | Accepted targeted scan | test/application/scan_coordinator_flow_test.dart | accepted targeted scan requests no fallback | red |
| scan-pipeline → Targeted pass runs first | Targeted capture fails on identity | test/application/scan_coordinator_flow_test.dart | targetNotForeground ends failed without fallback | red |
| scan-pipeline → Fallback pass runs when the targeted pass is not accepted | Targeted pass finds no marker | test/application/scan_coordinator_flow_test.dart | noMarker publishes fallback phase then accepts from fallback | red |
| scan-pipeline → Fallback pass runs when the targeted pass is not accepted | Fallback also rejected | test/application/scan_coordinator_flow_test.dart | both passes rejected keeps both evidences | red |
| scan-pipeline → Fallback pass runs when the targeted pass is not accepted | Targeted vision answer not delivered | test/application/scan_coordinator_flow_test.dart | visionTimeout ends failed without fallback | red |
| scan-pipeline → Fallback pass runs when the targeted pass is not accepted | Fallback capture fails | test/application/scan_coordinator_flow_test.dart | fallback targetGone keeps the targeted rejection | red |
| scan-pipeline → Fallback pass runs when the targeted pass is not accepted | Both passes fail to capture | test/application/scan_coordinator_flow_test.dart | blankCapture twice ends failed with both failures | red |
| scan-pipeline → Fallback pass runs when the targeted pass is not accepted | Catalog-only rejection | test/application/scan_coordinator_flow_test.dart | catalogModeMismatch requests no fallback | red |
| scan-pipeline → One scan in flight, latest trigger wins | Burst during capture | test/application/scan_coordinator_flow_test.dart | burst during capture keeps only the newest trigger | red |
| scan-pipeline → One scan in flight, latest trigger wins | Pending trigger meets an overrun capture | test/application/scan_coordinator_flow_test.dart | pending trigger after captureTimeout fails captureBusy and is logged | red |
| scan-pipeline → One scan in flight, latest trigger wins | Trigger during the vision stage | test/application/scan_pipeline_isolate_test.dart | trigger during vision invalidates, never overlaps native calls, never publishes the old result | red |
| scan-pipeline → One scan in flight, latest trigger wins | Trigger during matching | test/application/scan_coordinator_flow_test.dart | trigger during matching discards the old match | red |
| scan-pipeline → One scan in flight, latest trigger wins | Triggers dropped by the native queue | test/application/scan_coordinator_flow_test.dart | droppedBefore is recorded on the scan | red |
| scan-pipeline → Results publish only while current | Switched off during matching | test/application/scan_coordinator_flow_test.dart | switch-off during matching discards the result | red |
| scan-pipeline → Results publish only while current | Late result after dispose | test/application/scan_coordinator_flow_test.dart | capture success after dispose is released without notification | red |
| scan-pipeline → Matching uses the current catalog index | Catalog loaded | test/application/scan_coordinator_flow_test.dart | outcome records mode and revision of the current snapshot | red |
| scan-pipeline → Matching uses the current catalog index | Catalog replaced mid-scan | test/application/scan_coordinator_flow_test.dart | snapshot change mid-scan keeps the old index for that scan | red |
| scan-pipeline → Matching uses the current catalog index | No catalog | test/application/scan_coordinator_flow_test.dart | no snapshot rejects catalogUnavailable without fallback | red |
| scan-pipeline → Matching uses the current catalog index | Index build fails | test/application/scan_coordinator_flow_test.dart | failed index build rejects and retries on next snapshot | red |
| scan-pipeline → Every scan records stage timings | Accepted targeted scan timings | test/application/scan_coordinator_flow_test.dart | accepted targeted timeline is complete and ordered | red |
| scan-pipeline → Every scan records stage timings | Fallback wins | test/application/scan_coordinator_flow_test.dart | fallback win keeps the targeted pass's own job stamps | red |
| scan-pipeline → Every scan records stage timings | Scan ended early | test/application/scan_coordinator_flow_test.dart | early capture failure leaves later stages absent | red |
| scan-pipeline → Each finished scan is logged as one JSON line | Accepted scan line | test/application/scan_report_test.dart | accepted fallback report encodes a v1 line with per-pass ms | green |
| scan-pipeline → Each finished scan is logged as one JSON line | Superseded scan line | test/application/scan_report_test.dart | superseded report encodes only the stages reached | green |
| scan-pipeline → Timing log is bounded and never blocks scanning | Rotation | test/data/scan_timing_log_test.dart | rotates before passing 1 MiB | green |
| scan-pipeline → Timing log is bounded and never blocks scanning | Disk stalled | test/data/scan_timing_log_test.dart | stalled write queues 32 and counts drops | green |
| scan-pipeline → Timing log is bounded and never blocks scanning | Log folder not writable | test/data/scan_timing_log_test.dart | open failure sets unavailable and later appends retry | green |
| scanner-evidence → Scanner shows the live scan switch and status | Switching on from Scanner | test/ui/live_scan_panel_test.dart | switch on shows ready status | red |
| scanner-evidence → Scanner shows the live scan switch and status | Unavailable runtime | test/ui/live_scan_panel_test.dart | unavailable status names the missing file | red |
| scanner-evidence → Scanner shows the live scan switch and status | Setting cannot be saved | test/ui/live_scan_panel_test.dart | failed switch-on save reverts and shows an error | red |
| scanner-evidence → Scanner shows the live scan switch and status | Setting cannot be saved when switching off | test/ui/live_scan_panel_test.dart | failed switch-off save stays off and shows an error | red |
| scanner-evidence → Scan phase is visible, including fallback | Fallback becomes visible | test/ui/scan_evidence_panel_test.dart | fallback phase shows fallback underway | red |
| scanner-evidence → Scan phase is visible, including fallback | Superseded scan | test/ui/scan_evidence_panel_test.dart | superseded scan shows only the newer phase | red |
| scanner-evidence → Scanner shows the latest scan's evidence | Accepted scan | test/ui/scan_evidence_panel_test.dart | accepted report shows item, pass, score, crop and text | red |
| scanner-evidence → Scanner shows the latest scan's evidence | Rejected scan | test/ui/scan_evidence_panel_test.dart | rejected report labels best candidate not accepted | red |
| scanner-evidence → Scanner shows the latest scan's evidence | Failed scan | test/ui/scan_evidence_panel_test.dart | failed report shows failure and no candidate | red |
| scanner-evidence → Scanner shows the latest scan's evidence | Navigation keeps evidence | test/ui/shell_test.dart | scan evidence survives Map and back | red |
| scanner-evidence → Scan evidence never produces a recommendation | Accepted scan leaves the decision card alone | test/application/scan_coordinator_flow_test.dart; test/ui/scanner_screen_test.dart | accepted scan changes no selection or history; decision card unchanged after accepted scan | red |
| scanner-evidence → Scan evidence never produces a recommendation | Rejected scan with a best candidate | test/application/scan_coordinator_flow_test.dart | rejected scan changes no selection or history | red |
| scanner-evidence → Scanner shows stage timings and recent scans | Timings of an accepted scan | test/ui/scan_evidence_panel_test.dart | timings show stage and total ms | red |
| scanner-evidence → Scanner shows stage timings and recent scans | Early failure | test/ui/scan_evidence_panel_test.dart | absent stages are shown as absent, not 0 | red |
| scanner-evidence → Scanner shows stage timings and recent scans | Recent list bound | test/application/scan_coordinator_flow_test.dart | recent list keeps the 10 newest | red |

## 1. ADR and architecture

- [x] 1.1 Write `docs/adr/0013-scan-pipeline-coordination.md` in MADR-short form (Status accepted, Date, Supersedes none, Context, Decision, Rejected alternatives, Consequences). It records design D1-D10:
  - one app-scoped coordinator;
  - start order template → vision → hook;
  - session intent owned by the coordinator;
  - latest-wins with stage-specific supersession and the `captureTimeout` → `captureBusy` case;
  - fallback eligibility;
  - client size in frame provenance;
  - JSONL timing log v1 schema, 1 MiB rotation and 32-line queue;
  - failure values mapped in the coordinator;
  - no decisions from scans before M4.

  Verify: the file exists, and `docs/adr/README.md` lists it if it keeps an index.
- [x] 1.2 Update `openspec/architecture.md`:
  - add `ScanCoordinator`, `ScanTimingLog` and the Scanner evidence panel rows;
  - remove the "Not wired" notes on capture, vision, job and matcher;
  - rewrite the "Not built yet" paragraph (hotkeys and decisions remain M4);
  - change the "Caller (not yet wired)" resource-bound cells to the coordinator and Scanner;
  - add log rows to resource bounds;
  - add ADR-0013 to the index.

  Verify: `rg -n "not yet wired|change 5 wires|Not wired" openspec/architecture.md` returns nothing stale.

## 2. Frame provenance gains the client size

- [x] 2.1 In `test/data/capture/capture_policy_test.dart`, add failing tests "targeted frame reports the validated client size" (2560×1440 client) and "clipped fallback frame reports full client width" (1920 client, captured 1800). Run `mise run test -- test/data/capture/capture_policy_test.dart` and confirm they fail because `clientWidth`/`clientHeight` do not exist.
- [x] 2.2 Add `clientWidth`/`clientHeight` to `CaptureFrameMetadata` (`lib/data/capture/capture_frame.dart`), fill them from `s0.client` in `CapturePolicy` (`capture_policy.dart:88-104`), and update every constructor call in lib and test fakes. Verify: the 2.1 tests and the existing provenance and clipped tests pass; flip their rows green.

## 3. Settings key and log location

- [x] 3.1 Add failing tests in the existing settings tests (or `test/domain/settings_test.dart` if none):
  - `AppSettings` defaults `liveScan` to false;
  - it round-trips through `toJson`/`fromJson`;
  - a payload without `liveScan` reads as false.

  Then add `liveScan` to `AppSettings` (constructor, `copyWith`, `toJson`, `fromJson` with `?? false`), and add `LocalPaths.logs` (`<root>/logs`, created on resolve). Verify: tests pass, and no Drift schema version change (`schemaVersion` stays 2).

## 4. Timing log writer

- [x] 4.1 Write failing tests in `test/data/scan_timing_log_test.dart` against a temp directory, with a fake file sink injected through the constructor to hold or fail writes (no sleeps; completers gate the held write):
  - "rotates before passing 1 MiB": use a small injected `maxBytes` to prove the rule cheaply, plus one test at the default 1 MiB constant value only;
  - "stalled write queues 32 and counts drops";
  - "open failure sets unavailable and later appends retry";
  - lines are written in order.
- [x] 4.2 Implement `lib/data/scan_timing_log.dart` (`ScanTimingLog` with `append`, `status` as a `ChangeNotifier` or listenable, and `close()` that flushes within 1 s, then drops). Verify: 4.1 passes; flip the Rotation, Disk stalled and Log folder not writable rows green.

## 5. Scan report values and log line

- [x] 5.1 Write failing tests in `test/application/scan_report_test.dart`:
  - "accepted fallback report encodes a v1 line with per-pass ms": `v`, `utc`, `end`, `item`, `pass`, `ms.trigger` 0, `ms.published`, `ms.targeted.{…}`, `ms.fallback.{…}`, with QPC to ms conversion at a fake frequency;
  - "superseded report encodes only the stages reached": absent keys omitted;
  - no key holds crop bytes.
- [x] 5.2 In `lib/application/scan_coordinator.dart`, define the UI-facing values:
  - `LiveScanState`, `ScanFailureCode` plus message (mapped from every `CaptureFailure`, `TriggerFailure`, `VisionAnswer` non-delivery and `VisionStartFailure`);
  - `ScanPhase`, `ScanTimeline`/`PassTimeline` (nullable QPC);
  - the sealed `ScanEnd` (`ScanAccepted`, `ScanRejected`, `ScanFailed`), `ScanReport` and `toLogLine(qpcFrequency)`.

  Use exhaustive switches for the mappings (dart-use-pattern-matching) and `///` docs on public API (dart-write-documentation). Verify: 5.1 passes; flip the two log-line rows green.

## 6. Coordinator lifecycle

- [ ] 6.1 Define small ports in `scan_coordinator.dart` so the lifecycle and flow tests use hand-written fakes:
  - a capture port over `CaptureService.capture/close/workerExit`;
  - a vision port over `start/submitFrame/invalidate/close/workerExit/state`;
  - a trigger port over `start/stop/dispose/triggers`;
  - a marker loader, an index builder and a matcher (defaults: `buildTitleMatchIndexOffUi`, `matchRecognitionOffUi`);
  - a clock (`qpcNow`/`qpcFrequency`).

  The default factories wrap the real services and use `inspectionRecognitionJobFactory` and the runtime directory (S7). Write failing tests in `test/application/scan_coordinator_lifecycle_test.dart` for every lifecycle row of the test map (switch-on order, three start failures, idle switch-off, failed switch-off save, later save does not reinstall, switch-off during a hung start bounded by an injected short close drain, stopTimedOut warning and retry, vision worker exit, restart after loss). Use completers to hold `start()` and `close()`.
- [ ] 6.2 Implement activation in `ScanCoordinator`:
  - `setLiveScan`, the only writer of session intent, with save semantics per D2;
  - `startFromSettings()`, which reads `liveScan` once;
  - an activation token and a lifecycle chain;
  - immediate service close on switch-off during start;
  - `workerExit` watching (S1) and stuck-hook handling (S2).

  Verify: 6.1 passes; flip those rows green.

## 7. Coordinator scan flow

- [ ] 7.1 Write failing tests in `test/application/scan_coordinator_flow_test.dart` for every flow row of the test map. Cover:
  - targeted accept;
  - identity failure;
  - fallback paths (noMarker, both rejected, vision timeout, fallback capture fails, both blank, catalog-only);
  - burst during capture, overrun capture then `captureBusy`, trigger during matching, `droppedBefore`;
  - publication fences (switch-off during matching, late result after dispose);
  - catalog index (loaded, replaced mid-scan, none, build fails);
  - timings (complete, fallback wins, early failure);
  - recent list bound of 10;
  - no change to `SelectionController` or `HistoryController` for accepted and rejected scans (the coordinator receives neither; assert on real controllers built from the M1 harness);
  - a switch-off with a scan in flight releases its frame (fake frame registry counts releases).

  Use fake ports and gate every stage with completers.
- [ ] 7.2 Implement the flow per D3-D7:
  - one active scan and one pending trigger, with `scanGeneration`;
  - stage-specific supersession (wait for capture, `invalidate()` in vision, discard in matching);
  - serialised matching runs (ledger);
  - the closed fallback eligibility list;
  - the client size taken from the frame before `submitFrame`;
  - the one-entry index cache keyed by snapshot identity, built only while live scan is on (S3);
  - per-pass timelines;
  - exactly one `ScanTimingLog.append` per ended scan;
  - phase, latest and recent publication with fences;
  - crop bytes kept only on `latest` (S4).

  Verify: 7.1 passes; flip those rows green.

## 8. Cross-isolate proof with real services

- [ ] 8.1 Write `test/application/scan_pipeline_isolate_test.dart` using the real `CaptureService` and `VisionService`. Build them over the holdable capture platform, the holdable vision native, the shared frame registry and the fake clock (`test/data/capture/support/`, `test/data/vision/support/`), with the real recognition job factory replaced by a holdable test job where needed. Cover:
  - "trigger during vision invalidates, never overlaps native calls, never publishes the old result": assert the native control memory's concurrent-call count never exceeds 1, and every frame slot is released;
  - "dispose with a held native call completes after the drain and publishes nothing", with injected short drains.

  Keep it in the fast loop if it runs in well under a few seconds; otherwise tag it `@Tags(['qualification'])`, and tag any test that needs native DLLs. Verify: both pass; flip their rows green.

## 9. Composition root and audits

- [ ] 9.1 Write failing tests in `test/application/app_services_scan_test.dart` with fake factories (no native DLLs):
  - "launch with live scan off starts no worker, hook or vision runtime" (the factories record zero calls);
  - "launch with live scan saved on starts exactly one vision service";
  - "live scan on opens the runtime only through the vision service opener".
- [ ] 9.2 Wire `ScanCoordinator` and `ScanTimingLog` into `AppServices`:
  - construct both with injectable factories;
  - call `startFromSettings()` after `initialize()`;
  - dispose the coordinator first and the log after it, inside the existing `try`/`finally`.

  Leave `SessionScanState` untouched (M4). Verify: 9.1 passes and `test/application/app_services_test.dart` still passes; flip the rows green.
- [ ] 9.3 Narrow the audits:
  - `test/data/vision/vision_worker_audit_test.dart`: allow exactly `lib/application/scan_coordinator.dart`.
  - `test/data/capture/capture_source_audit_test.dart`: the trigger-source and `lib/ui` `data/capture/` import audits allow exactly that file; every process-access and input API ban stays unchanged.
  - Add matcher cases proving that a second file is still flagged.

  Verify: the audits pass and fail when a reference is added to `lib/ui/scanner_screen.dart` in a scratch run (reverted). Flip the audit rows green.

## 10. Scanner UI

- [ ] 10.1 Write failing widget tests:
  - `test/ui/live_scan_panel_test.dart`: switch on → ready; unavailable reason names the file; failed switch-on save reverts with an error; failed switch-off save stays off with an error. A fake coordinator or fake ports drive the states.
  - `test/ui/scan_evidence_panel_test.dart`: fallback underway; superseded shows only the newer phase; accepted, rejected and failed reports; timings and absent stages. The crop is a tiny synthetic gray buffer.
  - `test/ui/scanner_screen_test.dart`: the decision card is unchanged after an accepted scan.
  - `test/ui/shell_test.dart`: evidence survives Map and back.
- [ ] 10.2 Implement `lib/ui/live_scan_panel.dart` and `lib/ui/scan_evidence_panel.dart`:
  - use `ListenableBuilder` on the coordinator;
  - decode the crop once per report id with `ui.decodeImageFromPixels` and dispose it on replacement;
  - item name from `catalog.snapshot`;
  - no `data/capture/` import and no `VisionService*` name;
  - place them in `ScannerScreen`'s left column, keeping the compact `ListView` layout below 1100 px.

  Verify: 10.1 passes, and the existing `scanner_screen_test.dart` and `m1_flow_test.dart` still pass; flip the rows green.

## 11. Integration checks

- [ ] 11.1 Run `dart format` on changed files, then `mise run analyze` and `mise run test`. All must pass with zero analyzer issues. Confirm every test-map row is green.
- [ ] 11.2 Confirm Escape from Tarkov is not running. If that cannot be confirmed, skip this task and record it as unverified. Then build the Release bundle (`mise run build:release`, which runs the offline `bundle:check`). Confirm the bundle check passes and that the vision files, marker template and capture DLL are present and hash-bound. Do not launch the app.
- [ ] 11.3 `openspec validate add-scanner-evidence-slice --strict` passes.

## Workflow follow-up

- **User-verified (agents must not perform):**
  - Turn on live scan in a Release build, then click over real item inspections in Escape from Tarkov at the user's resolution and DPI.
  - Confirm that evidence appears, that fallback shows visibly when a targeted pass misses, and that the UI stays responsive.
  - Confirm that `logs/scan-timings.jsonl` records stage timings.

  This is the M2 exit criterion "Live cursor-triggered capture over the game…". Until the user reports it, it stays unverified.
- **Clean-machine check:** launching the same bundle on a clean Windows machine is user-verified, as an M2 exit criterion.
- **After the PR merges:** archive the change (`/opsx:archive` → specwright-finish), then `/specwright-roadmap close` for M2, with `release:prepare -- 0.2.0-beta.N` while user checks are open.
