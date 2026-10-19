# Tasks

## Test map

Native logic is proven in a new ungated native unit-test executable, `windows/capture/unittest.cpp`, run by `mise run capture:unittest`.
- It exercises only pure cores (`hotkey_core`, the ring, the rebind swap) through injected environments and a fake hotkey registrar.
- It installs no hook, registers no hotkey, queries no real window and captures nothing, so it needs no game check. An audit test enforces that (task 2.1).

Real OS behaviour (registration conflicts between threads, `MOD_NOREPEAT`) goes in the gated `windows/capture/selftest.cpp`.
- That test needs `BLACKGRID_NO_GAMES_RUNNING=1`, so **the user runs it**, and its rows stay unverified until the user reports them.
- Agents never set that flag.

Dart rows use the hand-written fakes:
- `test/data/capture/support/fake_hook_platform.dart`;
- `test/application/support/fake_scan_ports.dart`, with `FakeScanClock` for waits;
- no sleeps.

A test name is the scenario name, prefixed by its group where the file has several groups.

`green` marks a scenario carried unchanged inside a MODIFIED requirement whose existing test already passes; its task re-runs it.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| scan-triggers → Hotkey trigger records the same target facts | Press over the target window | `windows/capture/unittest.cpp` | `hotkey: press over the target window` | red |
| scan-triggers → Hotkey trigger records the same target facts | Press over another window | `windows/capture/unittest.cpp` | `hotkey: press over another window` | red |
| scan-triggers → Hotkey trigger records the same target facts | Press over Blackgrid | `windows/capture/unittest.cpp` | `hotkey: press over blackgrid` | red |
| scan-triggers → Hotkey trigger records the same target facts | Mouse release keeps its source | `windows/capture/unittest.cpp` | `hook: mouse release keeps its source` | red |
| scan-triggers → Hotkey trigger records the same target facts | Press over the target window (Dart decode) | `test/data/capture/trigger_source_test.dart` | `drained events carry their trigger source` | red |
| scan-triggers → Holding the hotkey does not repeat | Key held down | `windows/capture/unittest.cpp` | `swap: registers with MOD_NOREPEAT and no modifier` (+ user-run `selftest.cpp` `hotkey: registered with norepeat`) | red |
| scan-triggers → Holding the hotkey does not repeat | Two separate presses | `windows/capture/unittest.cpp` | `hotkey: two presses append two events in order` | red |
| scan-triggers → Hotkey triggers share the bounded queue | Mixed sources in order | `windows/capture/unittest.cpp` | `ring: mixed sources drain in append order` | red |
| scan-triggers → Hotkey triggers share the bounded queue | Dart isolate is busy | `windows/capture/unittest.cpp` | `hotkey: press appends and signals without waiting` | red |
| scan-triggers → Hotkey triggers share the bounded queue | Overflow across sources | `windows/capture/unittest.cpp` | `ring: overflow across sources keeps newest 16 and counts 4` | red |
| scan-triggers → Hotkey registration is explicit and reports conflicts | Register a free key | `windows/capture/unittest.cpp` | `swap: register a free key` | red |
| scan-triggers → Hotkey registration is explicit and reports conflicts | Key held by another application | `windows/capture/unittest.cpp` | `swap: key held elsewhere returns unavailable with the os code` (+ user-run `selftest.cpp` `hotkey: second registration from another thread conflicts`) | red |
| scan-triggers → Hotkey registration is explicit and reports conflicts | Request while stopped | `windows/capture/unittest.cpp` | `api: hotkey set while stopped returns not started` | red |
| scan-triggers → Hotkey registration is explicit and reports conflicts | Unsupported key | `windows/capture/unittest.cpp` | `api: unsupported key returns invalid argument` | red |
| scan-triggers → Hotkey registration is explicit and reports conflicts | Turned off | `windows/capture/unittest.cpp` | `swap: off unregisters` | red |
| scan-triggers → Hotkey registration is explicit and reports conflicts | Key held by another application (Dart mapping) | `test/data/capture/trigger_source_test.dart` | `setHotkey maps every native status to a typed result` | red |
| scan-triggers → Rebinding keeps the previous key on failure | Rebind to a free key | `windows/capture/unittest.cpp` | `swap: rebind registers new before releasing old` | red |
| scan-triggers → Rebinding keeps the previous key on failure | Rebind to a held key | `windows/capture/unittest.cpp` | `swap: refused rebind keeps the old key` | red |
| scan-triggers → Rebinding keeps the previous key on failure | Same key again | `windows/capture/unittest.cpp` | `swap: same key is a no-op` | red |
| scan-triggers → Rebinding keeps the previous key on failure | Input thread does not answer | `windows/capture/unittest.cpp` | `request: timeout reserves the slot until answered` | red |
| scan-triggers → Rebinding keeps the previous key on failure | Late answer after a timeout | `windows/capture/unittest.cpp` | `request: abandoned swap releases only the new key` | red |
| scan-triggers → Hook lifecycle is explicit | Start then stop | `test/data/capture/trigger_source_test.dart` | `stop closes the listener and ignores later signals` | green |
| scan-triggers → Hook lifecycle is explicit | Stop with a hotkey registered | `windows/capture/unittest.cpp` | `thread exit unregisters every hotkey id and completes a pending request` | red |
| scan-triggers → Hook lifecycle is explicit | Second start | `test/data/capture/trigger_source_test.dart` | `a second start returns alreadyStarted` | green |
| scan-triggers → Hook lifecycle is explicit | Installation refused by the OS | `test/data/capture/trigger_source_test.dart` | `an OS refusal returns unavailable with the win32 code` | green |
| scan-triggers → Hook lifecycle is explicit | Hook thread does not end in time | `test/data/capture/trigger_source_test.dart` | `stopTimedOut keeps the listener open and blocks restart` | green |
| scan-triggers → Hook lifecycle is explicit | Normal startup | `test/application/scan_coordinator_lifecycle_test.dart` | `launch with live scan off starts no worker, hook or vision runtime` (gains: no hotkey set) | red |
| scan-pipeline → The scan hotkey is a persisted setting | No saved value | `test/domain/settings_test.dart` | `scanHotkey: no saved value` | red |
| scan-pipeline → The scan hotkey is a persisted setting | Saved off | `test/domain/settings_test.dart` | `scanHotkey: saved off` | red |
| scan-pipeline → The scan hotkey is a persisted setting | Malformed value | `test/domain/settings_test.dart` | `scanHotkey: malformed value` | red |
| scan-pipeline → The pipeline publishes the hotkey state | Ready with a free key | `test/application/scan_coordinator_hotkey_test.dart` | `state: ready with a free key` | red |
| scan-pipeline → The pipeline publishes the hotkey state | Binding off | `test/application/scan_coordinator_hotkey_test.dart` | `state: binding off` | red |
| scan-pipeline → The pipeline publishes the hotkey state | Live scan off | `test/application/scan_coordinator_hotkey_test.dart` | `state: live scan off` | red |
| scan-pipeline → The pipeline publishes the hotkey state | Worker loss | `test/application/scan_coordinator_hotkey_test.dart` | `state: worker loss` | red |
| scan-pipeline → The pipeline publishes the hotkey state | Registration does not answer at activation | `test/application/scan_coordinator_hotkey_test.dart` | `state: registration does not answer at activation` | red |
| scan-pipeline → Rebinding the hotkey | Rebind while ready | `test/application/scan_coordinator_hotkey_test.dart` | `rebind: rebind while ready` | red |
| scan-pipeline → Rebinding the hotkey | Rebind to a held key | `test/application/scan_coordinator_hotkey_test.dart` | `rebind: rebind to a held key` | red |
| scan-pipeline → Rebinding the hotkey | Save fails after registration | `test/application/scan_coordinator_hotkey_test.dart` | `rebind: save fails after registration` | red |
| scan-pipeline → Rebinding the hotkey | Save fails after leaving an unavailable key | `test/application/scan_coordinator_hotkey_test.dart` | `rebind: save fails after leaving an unavailable key` | red |
| scan-pipeline → Rebinding the hotkey | Old key taken during a failed save | `test/application/scan_coordinator_hotkey_test.dart` | `rebind: old key taken during a failed save` | red |
| scan-pipeline → Rebinding the hotkey | Live scan switched off while a rebind saves | `test/application/scan_coordinator_hotkey_test.dart` | `rebind: live scan switched off while a rebind saves` | red |
| scan-pipeline → Rebinding the hotkey | Rebind while off | `test/application/scan_coordinator_hotkey_test.dart` | `rebind: rebind while off` | red |
| scan-pipeline → Rebinding the hotkey | Rebind during another rebind | `test/application/scan_coordinator_hotkey_test.dart` | `rebind: rebind during another rebind` | red |
| scan-pipeline → Rebinding the hotkey | Rebind out of an unavailable state | `test/application/scan_coordinator_hotkey_test.dart` | `rebind: rebind out of an unavailable state` | red |
| scan-pipeline → Live scan starts only when enabled | Launch with live scan off | `test/application/scan_coordinator_lifecycle_test.dart` | `launch with live scan off starts no worker, hook or vision runtime` (gains: no hotkey set) | red |
| scan-pipeline → Live scan starts only when enabled | Switching live scan on | `test/application/scan_coordinator_lifecycle_test.dart` | `switch-on saves, then template, vision ready, then hook` (gains: then hotkey) | red |
| scan-pipeline → Live scan starts only when enabled | Hotkey held by another application | `test/application/scan_coordinator_hotkey_test.dart` | `activation: hotkey held by another application` | red |
| scan-pipeline → Live scan starts only when enabled | Launch with live scan saved on | `test/application/scan_coordinator_lifecycle_test.dart` | `launch with live scan saved on starts exactly one vision service` | green |
| scan-pipeline → Live scan starts only when enabled | Vision runtime cannot start | `test/application/scan_coordinator_lifecycle_test.dart` | `vision start failure is unavailable without a hook` (gains: no hotkey set) | red |
| scan-pipeline → Live scan starts only when enabled | Marker template is invalid | `test/application/scan_coordinator_lifecycle_test.dart` | `invalid marker template is unavailable before any worker` | green |
| scan-pipeline → Live scan starts only when enabled | Hook installation refused | `test/application/scan_coordinator_lifecycle_test.dart` | `refused hook is unavailable with OS code and closes vision` (gains: no hotkey set) | red |
| scan-pipeline → Live scan stops cleanly | Switching live scan off while idle | `test/application/scan_coordinator_lifecycle_test.dart` | `switch-off removes hook and closes both workers` (gains: hotkey state inactive) | red |
| scan-pipeline → Live scan stops cleanly | Setting cannot be saved when switching off | `test/application/scan_coordinator_lifecycle_test.dart` | `failed switch-off save still stops the pipeline` (gains: hotkey state inactive) | red |
| scan-pipeline → Live scan stops cleanly | A later save does not reinstall the hook | `test/application/scan_coordinator_lifecycle_test.dart` | `unrelated save after failed switch-off keeps live scan off` (gains: no hotkey set) | red |
| scan-pipeline → Live scan stops cleanly | Switching off during start | `test/application/scan_coordinator_lifecycle_test.dart` | `switch-off during a hung start is bounded by the close drain` (gains: no hotkey set) | red |
| scan-pipeline → Live scan stops cleanly | Switching off with a scan in flight | `test/application/scan_coordinator_flow_test.dart` | `switch-off during vision stage publishes nothing and releases the frame` | green |
| scan-pipeline → Live scan stops cleanly | Switching off during a rebind | `test/application/scan_coordinator_hotkey_test.dart` | `stop: switching off during a rebind` | red |
| scan-pipeline → Live scan stops cleanly | Hook thread does not stop | `test/application/scan_coordinator_lifecycle_test.dart` | `stopTimedOut is a visible warning and the next start retries stop` (gains: warning names the hotkey) | red |
| scan-pipeline → Live scan stops cleanly | Worker drain incomplete at shutdown | `test/application/scan_pipeline_isolate_test.dart` | `dispose with a held native call completes after the drain and ...` | green |
| scan-pipeline → Each finished scan is logged as one JSON line | Accepted scan line | `test/application/scan_report_test.dart` | `accepted fallback report encodes a v2 line with trigger and per-pass ms` (renamed from the v1 test) | red |
| scan-pipeline → Each finished scan is logged as one JSON line | Hotkey scan line | `test/application/scan_report_test.dart` | `hotkey report encodes trigger hotkey` | red |
| scan-pipeline → Each finished scan is logged as one JSON line | Superseded scan line | `test/application/scan_report_test.dart` | `superseded report encodes only the stages reached` | green |
| scan-pipeline → Targeted capture waits for the inspect window to settle | Fresh trigger | `test/application/scan_coordinator_wait_test.dart` | `fresh trigger waits the remaining 49 ms before the targeted capture` | green |
| scan-pipeline → Targeted capture waits for the inspect window to settle | Trigger already old | `test/application/scan_coordinator_wait_test.dart` | `a trigger already 120 ms old captures without waiting` | green |
| scan-pipeline → Targeted capture waits for the inspect window to settle | Hotkey trigger | `test/application/scan_coordinator_wait_test.dart` | `hotkey trigger captures without the settle wait` | red |
| scan-pipeline → Targeted capture waits for the inspect window to settle | Switched off while waiting | `test/application/scan_coordinator_wait_test.dart` | `switch-off during the settle wait requests no capture and publishes nothing` | green |
| scan-pipeline → Fallback capture waits until 200 ms after the trigger | Quick targeted rejection | `test/application/scan_coordinator_wait_test.dart` | `quick noMarker publishes fallback phase, then waits to trigger + 200 ms` | green |
| scan-pipeline → Fallback capture waits until 200 ms after the trigger | Slow targeted rejection | `test/application/scan_coordinator_wait_test.dart` | `targeted rejection after 260 ms falls back without waiting` | green |
| scan-pipeline → Fallback capture waits until 200 ms after the trigger | Quick hotkey rejection | `test/application/scan_coordinator_wait_test.dart` | `quick hotkey noMarker falls back at once` | red |
| scan-pipeline → A trigger during a wait supersedes the scan at once | Second click during the settle wait | `test/application/scan_coordinator_wait_test.dart` | `second click during the settle wait supersedes at once` | green |
| scan-pipeline → A trigger during a wait supersedes the scan at once | Hotkey during the settle wait | `test/application/scan_coordinator_wait_test.dart` | `hotkey during the settle wait supersedes and captures at once` | red |
| scan-pipeline → A trigger during a wait supersedes the scan at once | Click during the fallback wait | `test/application/scan_coordinator_wait_test.dart` | `click during the fallback wait supersedes at once` | green |
| scanner-evidence → Scanner shows the scan hotkey and lets the user rebind it | Registered hotkey | `test/ui/live_scan_panel_test.dart` | `hotkey: registered hotkey` | red |
| scanner-evidence → Scanner shows the scan hotkey and lets the user rebind it | Hotkey held by another application | `test/ui/live_scan_panel_test.dart` | `hotkey: hotkey held by another application` | red |
| scanner-evidence → Scanner shows the scan hotkey and lets the user rebind it | Rebind refused | `test/ui/live_scan_panel_test.dart` | `hotkey: rebind refused` | red |
| scanner-evidence → Scanner shows the scan hotkey and lets the user rebind it | Live scan off | `test/ui/live_scan_panel_test.dart` | `hotkey: live scan off` | red |
| scanner-evidence → Scanner shows the scan hotkey and lets the user rebind it | Live scan starting | `test/ui/live_scan_panel_test.dart` | `hotkey: live scan starting` | red |
| scanner-evidence → Scanner shows stage timings and recent scans | Timings of an accepted scan | `test/ui/scan_evidence_panel_test.dart` | `timings show stage and total ms` | green |
| scanner-evidence → Scanner shows stage timings and recent scans | Early failure | `test/ui/scan_evidence_panel_test.dart` | `absent stages are shown as absent, not 0` | green |
| scanner-evidence → Scanner shows stage timings and recent scans | Recent list bound | `test/ui/scan_evidence_panel_test.dart` | `recent list shows the 10 newest scans, newest first` | green |
| scanner-evidence → Scanner shows stage timings and recent scans | Hotkey scan in the list | `test/ui/scan_evidence_panel_test.dart` | `recent list labels hotkey scans` | red |

## 1. ADR and architecture

- [x] 1.1 Write `docs/adr/0019-scan-hotkey-on-the-capture-input-thread.md` in MADR-short form (Status: accepted, today's date, Supersedes: none). Record design D1, D3, D4, D5, D7 and D10, capture ABI v2 and timing log v2. Note that it settles the hotkey-wait question ADR-0014 and ADR-0016 deferred to M4, and carries out ADR-0010's planned reuse of the input thread. Add its row to the in-force index in `openspec/architecture.md`, and update `docs/adr/README.md` if it lists ADRs. Verify: the file exists, the index row links it, and `openspec validate add-scan-hotkey-trigger --strict` passes.
- [x] 1.2 Update `openspec/architecture.md` for the built state this change delivers:
  - the Capture DLL row: ABI v2, the hotkey on the input thread, the shared ring;
  - the capture worker and trigger source row: `InputTriggerSource`;
  - the `ScanCoordinator` row: hotkey state, rebind, waits by trigger source, log v2;
  - the Scan flow bounds row: hotkey waits are 0; rebind request 1 in flight, 1 s;
  - the "Not built yet" paragraph and the strategy row that say hotkeys do not exist.

  Verify by reading the diff: no remaining claim that hotkeys do not exist.

## 2. Native ABI v2 and the hotkey on the input thread

Skills: dart-run-static-analysis does not apply. This group is C++ plus one Dart audit test (dart-add-unit-test).

- [ ] 2.1 Add the ungated native unit-test target and its guards:
  - `windows/capture/unittest.cpp`, an `EXCLUDE_FROM_ALL` CMake target `blackgrid_capture_unittest` in `windows/capture/CMakeLists.txt` built from the same sources;
  - `windows/capture/unittest.ps1`, mirroring `selftest.ps1` but without the game gate;
  - a `mise.toml` task `capture:unittest`.

  Extend `test/data/capture/capture_source_audit_test.dart` with:
  - the D10 bans: `WH_KEYBOARD_LL`, `WH_KEYBOARD`, `GetAsyncKeyState`, `GetKeyState`, `GetKeyboardState`, `keybd_event`, `RegisterRawInputDevices`, `GetRawInputData`, `GetRawInputBuffer`;
  - a non-vacuous case asserting that a source containing `SetWindowsHookExW(WH_KEYBOARD_LL, ...)` is reported;
  - a check that `unittest.cpp` mentions none of `hook_real_installer`, `bgc_hook_start`, `RegisterHotKey`, `SetWindowsHookEx`, `BitBlt` or `GetForegroundWindow`, so it can never touch a real window or input.

  Verify: `mise run test` runs the audit test and it passes, with the new non-vacuous case red before the bans are added. `mise run capture:unittest` builds and runs an empty suite (after `flutter build windows --release`, which only builds).
- [ ] 2.2 Write the failing `unittest.cpp` cases from the test map rows for `scan-triggers`:
  - hotkey target facts (4 rows);
  - no repeat (2);
  - shared queue (3);
  - registration (5);
  - rebinding (5);
  - "Stop with a hotkey registered".

  They use injected environments (foreground, pid/tid, title, cursor, qpc, signal) and a fake hotkey registrar recording calls and returning scripted results. Verify: `mise run capture:unittest` fails on each new case, for missing symbols or a wrong result.
- [ ] 2.3 Implement ABI v2 in `windows/capture/`:
  - `capture.h`:
    - `BGC_ABI_VERSION 2`;
    - `bgc_trigger_event` gains `uint32_t source` (`BGC_TRIGGER_MOUSE 0`, `BGC_TRIGGER_HOTKEY 1`) and `uint32_t reserved`, so the struct is 40 bytes;
    - status codes `BGC_HOTKEY_UNAVAILABLE 11` and `BGC_HOTKEY_TIMED_OUT 12`;
    - `int32_t bgc_hotkey_set(uint32_t vk, uint32_t* win32_error)`.
  - `hook.cpp`:
    - the mouse core stamps `source`;
    - `hotkey_core` (D2) runs on the `WM_HOTKEY` branch;
    - the static request slot and the `WM_APP + 1` rebind branch use the two-id swap with the abandoned-flag order (D5). Per the review's implementation note, the caller's timeout and the thread's final flag check take the same lock over the slot, so a timeout never reports `hotkeyTimedOut` for a swap the thread kept;
    - `MOD_NOREPEAT`;
    - at loop exit, unregister every id and complete a pending request with `BGC_NOT_STARTED`, before unhooking.
  - The hotkey registrar is injectable, like `HookInstaller`.

  Verify: every 2.2 case passes under `mise run capture:unittest`, `flutter build windows --release` builds, and the audit test still passes. Flip those rows green.
- [ ] 2.4 Add user-run real-OS cases to the gated `windows/capture/selftest.cpp`:
  - `hotkey: registered with norepeat` (register F24 on its own thread and check that registration succeeds);
  - `hotkey: second registration from another thread conflicts` (expect `ERROR_HOTKEY_ALREADY_REGISTERED`);
  - unregistration at stop.

  Verify: it compiles under `flutter build windows --release` (the target builds through `selftest.ps1` only). **Running it is user-only**: record the rows' `selftest.cpp` parts as unverified until the user reports `mise run capture:selftest`.

## 3. Dart capture layer: bindings, event source and `InputTriggerSource`

Skills: dart-use-pattern-matching (sealed `HotkeyResult`), dart-write-documentation, dart-add-unit-test, dart-run-static-analysis.

- [ ] 3.1 Write failing tests in `test/data/capture/trigger_source_test.dart`:
  - `drained events carry their trigger source`;
  - `setHotkey maps every native status to a typed result`, which covers OK for a key and for off, `HOTKEY_UNAVAILABLE` with win32, `HOTKEY_TIMED_OUT`, `NOT_STARTED` and `INVALID_ARGUMENT`;
  - a layout test, `BgcTriggerEvent is 40 bytes with source at offset 32`, using `sizeOf`/field offsets with no DLL.

  Extend `FakeHookPlatform` with `hotkeySet` (scripted results and a call log). Verify: the tests fail because the API is missing.
- [ ] 3.2 Implement:
  - in `lib/data/capture/capture_native.dart`: `bgcAbiVersion = 2`, the event struct's `source` and `reserved` fields, the `bgc_hotkey_set` lookup, and `CapturePlatform.hotkeySet`;
  - `TriggerEvent.source` (`TriggerSource { mouse, hotkey }`), defaulting nowhere and decoded from the struct;
  - the rename of `MouseReleaseTriggerSource` to `InputTriggerSource` in `input_trigger_source.dart` (D6), with `Future<HotkeyResult> setHotkey(ScanHotkey key)` and the sealed `HotkeyResult`;
  - `TriggerFailure` messages that say "input hook".

  Update every importer, plus `reachesCaptureLayer` in the audit test. Verify: 3.1 passes, `mise run analyze` is clean, and `mise run test` passes, including the existing green trigger-source rows. Flip the rows green.

## 4. The `scanHotkey` setting

Skills: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test.

- [ ] 4.1 Write the failing `test/domain/settings_test.dart` cases `scanHotkey: no saved value`, `scanHotkey: saved off` and `scanHotkey: malformed value`. The malformed case uses `"Ctrl+Q"` and `9`, and asserts that the other settings keep their values. Verify: the cases fail.
- [ ] 4.2 Add `enum ScanHotkey { off, f1, …, f24 }` with `vk` and `label` (D7), the `AppSettings.scanHotkey` field (default `f9`), `copyWith`, and a `toJson`/`fromJson` that never throws on this key. Verify: 4.1 passes and `mise run test` passes. Flip the rows green.

## 5. Coordinator: hotkey state, activation, rebind, waits, report and log

Skills: dart-use-pattern-matching (hotkey state sealed type), dart-write-documentation, dart-add-unit-test, dart-run-static-analysis.

- [ ] 5.1 Extend the fakes in `test/application/support/fake_scan_ports.dart`:
  - `FakeScanTrigger` gains `setHotkey`, with scripted results, a call log, and an optional `Completer` hold;
  - `emit` takes a source.

  `FakeSettingsStore` or the existing settings fake must be able to hold or fail saves; reuse what `scan_coordinator_lifecycle_test.dart` uses. Write the failing `test/application/scan_coordinator_hotkey_test.dart` cases for every `state:`, `rebind:`, `activation:` and `stop:` row. Also add the "gains" assertions to the listed lifecycle tests, and the new rows in the wait test (three) and the report test (two). Verify: the new and extended tests fail for the right reason.
- [ ] 5.2 Implement in `lib/application/scan_coordinator.dart`:
  - the published hotkey state (`inactive` / `disabled` / `registered(key)` / `unavailable(key, reason)`);
  - activation, which registers after `trigger.start()` reading `scanHotkey` after pending saves land, and maps a non-success result to `unavailable`;
  - the transitions to `inactive` on stop, loss and dispose;
  - the `stopTimedOut` warning text that names the hotkey;
  - `setHotkey` (D5): one rebind at a time, registration before the save, the save on the tracked `_saving`/`_savesLanded` path, the restore of the previous *registration* (with `setHotkey(off)` and `unavailable(old, reason)` when the restore is refused), the activation-token fence after each `await`, and save-only when not `ready`;
  - zero settle and fallback waits for `TriggerSource.hotkey` (D4);
  - `ScanReport.trigger`;
  - the log line `"v":2` with `"trigger"` (D9).

  Keep `scan_coordinator.dart` the only `lib/` file that reaches `data/capture/`. Verify: 5.1 passes, the green wait, flow, lifecycle and report rows still pass, and `mise run analyze` and `mise run test` pass. Flip the rows green.

## 6. Scanner UI and README

Skills: flutter-add-widget-test, dart-write-documentation, dart-run-static-analysis.

- [ ] 6.1 Write failing widget tests in `test/ui/live_scan_panel_test.dart` (five `hotkey:` rows), driving the hotkey state and rebind results through the existing scan UI support fakes (`test/ui/support/scan_ui_support.dart`). Also write `recent list labels hotkey scans` in `test/ui/scan_evidence_panel_test.dart`. Verify: the tests fail.
- [ ] 6.2 Implement:
  - the `LiveScanPanel` hotkey row (D8): `scan-hotkey-status` text, and a `scan-hotkey-picker` `DropdownButton<ScanHotkey>` with Off and F1-F24, enabled while live scan is `off` or `ready` and no rebind runs;
  - the unavailable text that says mouse scans still work;
  - the rebind error text;
  - the hotkey label in the recent scans list.

  Update the README Scanner section: the default F9, the F1-F24 range, Off, that the hotkey is held only while live scan is on, and that it scans the open inspect window at the cursor. Verify: 6.1 passes, the green evidence-panel rows still pass, and `mise run analyze`, `mise run test` and `dart format` (via `mise exec -- dart format --output=none --set-exit-if-changed lib test`) pass. Flip the rows green.

## 7. Integration checks

- [ ] 7.1 Run `mise run analyze`, `mise run test`, `mise exec -- dart format --output=none --set-exit-if-changed lib test`, `flutter build windows --release` (build only, never launched) and `mise run capture:unittest`, and confirm that every test-map row is green. The `selftest.cpp` parts of rows (2.4) are listed as user-run and unverified. Run `openspec validate add-scan-hotkey-trigger --strict`.

## Workflow follow-up

- User-only, unverified until reported:
  - `mise run capture:selftest` with no game running (the 2.4 real-OS hotkey cases);
  - the live check: switch live scan on, open an inspect window in the game, and press F9. One hotkey scan should be accepted, labelled as a hotkey scan, with `"trigger":"hotkey"` in `scan-timings.jsonl`;
  - an F9 conflict check: with another app holding F9, Scanner shows the hotkey as unavailable while mouse scans still work.
- Then use the pre-ship review, the PR and the archive, per `finish: pr`.
