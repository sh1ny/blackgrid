# Tasks

## Test map

Tests that drive the controller use `test/support/fake_recycle_port.dart`, a fake clock and a fake lifecycle source. Tests that drive the lister and the pick use a temp folder with small synthetic files and set modified times. The real runner channel is covered by the 5.5 evidence check and the 6.2 owner check.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| screenshot-cleanup → Screenshot cleanup is an opt-in setting | Off by default | `test/application/settings_screenshot_cleanup_test.dart` | `screenshot-cleanup: Off by default` | green |
| screenshot-cleanup → Screenshot cleanup is an opt-in setting | The setting survives a restart | `test/application/settings_screenshot_cleanup_test.dart` | `screenshot-cleanup: The setting survives a restart` | green |
| screenshot-cleanup → Screenshot cleanup is an opt-in setting | Save fails | `test/ui/settings_page_test.dart` | `screenshot-cleanup: Save fails` | green |
| screenshot-cleanup → Only a fresh raid ending starts a cleanup | A live raid ends | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: A live raid ends` | green |
| screenshot-cleanup → Only a fresh raid ending starts a cleanup | A raid ended by a client restart | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: A raid ended by a client restart` | green |
| screenshot-cleanup → Only a fresh raid ending starts a cleanup | Replay at start-up | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: Replay at start-up` | green |
| screenshot-cleanup → Only a fresh raid ending starts a cleanup | Switched on after the raid ended | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: Switched on after the raid ended` | green |
| screenshot-cleanup → Only a fresh raid ending starts a cleanup | Matching aborted | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: Matching aborted` | green |
| screenshot-cleanup → Only a fresh raid ending starts a cleanup | The same raid ends again | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: The same raid ends again` | green |
| screenshot-cleanup → A raid's screenshots are picked by folder, name and time | A screenshot from the raid | `test/domain/screenshot_cleanup_test.dart` | `screenshot-cleanup: A screenshot from the raid` | green |
| screenshot-cleanup → A raid's screenshots are picked by folder, name and time | Screenshots outside the raid window | `test/domain/screenshot_cleanup_test.dart` | `screenshot-cleanup: Screenshots outside the raid window` | green |
| screenshot-cleanup → A raid's screenshots are picked by folder, name and time | Files that are not game screenshots | `test/data/screenshot_folder_lister_test.dart` | `screenshot-cleanup: Files that are not game screenshots` | green |
| screenshot-cleanup → A raid's screenshots are picked by folder, name and time | A link to a file elsewhere | `test/data/screenshot_folder_lister_test.dart` | `screenshot-cleanup: A link to a file elsewhere` | green |
| screenshot-cleanup → A raid's screenshots are picked by folder, name and time | The folder changed during the raid | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: The folder changed during the raid` | green |
| screenshot-cleanup → Screenshots go to the Recycle Bin, never deleted for good | Every file moves | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: Every file moves` | green |
| screenshot-cleanup → Screenshots go to the Recycle Bin, never deleted for good | The Recycle Bin cannot take a file | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: The Recycle Bin cannot take a file` | green |
| screenshot-cleanup → Screenshots go to the Recycle Bin, never deleted for good | The recycle call fails | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: The recycle call fails` | green |
| screenshot-cleanup → Screenshots go to the Recycle Bin, never deleted for good | The recycle call does not answer | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: The recycle call does not answer` | green |
| screenshot-cleanup → Screenshots go to the Recycle Bin, never deleted for good | One file is locked | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: One file is locked` | green |
| screenshot-cleanup → Screenshots go to the Recycle Bin, never deleted for good | A file vanished before the move | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: A file vanished before the move` | green |
| screenshot-cleanup → Cleanups run one at a time | Two raids end close together | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: Two raids end close together` | green |
| screenshot-cleanup → Cleanups run one at a time | Switched off while a cleanup waits | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: Switched off while a cleanup waits` | green |
| screenshot-cleanup → Cleanups run one at a time | Blackgrid closes during a cleanup | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: Blackgrid closes during a cleanup` | green |
| screenshot-cleanup → Cleanups run one at a time | Too many cleanups waiting | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: Too many cleanups waiting` | green |
| screenshot-cleanup → The last cleanup's result is shown | Screenshots moved | `test/ui/settings_page_test.dart` | `screenshot-cleanup: Screenshots moved` | green |
| screenshot-cleanup → The last cleanup's result is shown | Some could not be moved | `test/ui/settings_page_test.dart` | `screenshot-cleanup: Some could not be moved` | green |
| screenshot-cleanup → The last cleanup's result is shown | No screenshots in the raid | `test/ui/settings_page_test.dart` | `screenshot-cleanup: No screenshots in the raid` | green |
| screenshot-cleanup → The last cleanup's result is shown | The folder is missing | `test/application/screenshot_cleanup_controller_test.dart` | `screenshot-cleanup: The folder is missing` | green |
| screenshot-cleanup → The last cleanup's result is shown | Nothing yet | `test/ui/settings_page_test.dart` | `screenshot-cleanup: Nothing yet` | green |
| settings-page → Game files section | Save a folder on Enter | `test/ui/settings_page_test.dart` | `settings-page: Save a folder on Enter` | green |
| settings-page → Game files section | Save on leaving | `test/ui/settings_page_test.dart` | `settings-page: Save on leaving` | green |
| settings-page → Game files section | Save fails | `test/ui/settings_page_test.dart` | `settings-page: Save fails` | green |
| settings-page → Game files section | The cleanup switch sits under the screenshot folder | `test/ui/settings_page_test.dart` | `settings-page: The cleanup switch sits under the screenshot folder` | green |
| settings-page → Game files section | Switching cleanup on | `test/ui/settings_page_test.dart` | `settings-page: Switching cleanup on` | green |

## 1. ADR and architecture

Skills: none (documentation only).

- [x] 1.1 Write ADR-0048, "Screenshot cleanup recycles a raid's screenshots through a runner channel", in `docs/adr/`. It records D1, D2 with the cancel and lifetime contract, D5 and D8. It states that the screenshot folder is written only through this channel and only by moves to the Recycle Bin. It cites ADR-0007 and ADR-0047, and says why per-file shell recycling on a runner worker thread still counts as light runner work (review S3). It records the accepted edge that a raid which ended up to 30 s before start-up is fresh in the replay (review S1). Add its row to the in-force index in `openspec/architecture.md`. In the same file update the diagram's "(read-only)" label, the T4/T6 triage lines, the Windows runner row (`blackgrid/recycle`: `recycle`, `cancel`), the state rows (the setting, the cleaned raids, the last result) and the bounds rows (cleanup queue 4, names per call 64, the backstop). Verify the index lists 0048, `docs/adr/README.md` still points to the index, and `openspec validate add-screenshot-cleanup --strict` exits 0.

## 2. Pick rule, lister and setting

Skills: `dart-use-pattern-matching`, `dart-write-documentation`, `dart-add-unit-test`, `dart-run-static-analysis` (`.claude/skills/<name>/SKILL.md`), and AGENTS.md "Dart and Flutter code".

- [x] 2.1 Write failing tests in `test/domain/screenshot_cleanup_test.dart` for the "A screenshot from the raid" and "Screenshots outside the raid window" rows. Use a pure listing of entries: inclusive bounds at exactly the start and the end, 13:59:59 and 14:30:01 left out, a valid unit-quaternion name. Verify they fail because `pickRaidScreenshots` does not exist.
- [x] 2.2 Implement `pickRaidScreenshots(entries, raid)` and its entry type in `lib/domain/screenshot_cleanup.dart` (D1, D7). Reuse `parseScreenshotFilename`. Entries that are links, directories or have the wrong extension are dropped. Verify the 2.1 tests pass and flip their rows green.
- [x] 2.3 Write failing tests in `test/data/screenshot_folder_lister_test.dart` for "Files that are not game screenshots" and "A link to a file elsewhere". Use a temp folder holding `notes.png`, a renamed game name, `shot.bmp`, a subfolder with a game-named file, and a file symlink. Skip the link case with a reason when the OS refuses to create a symlink without the privilege. Then implement `ScreenshotFolderLister` in `lib/data/` with `Directory.list(followLinks: false)` and `stat`, reporting `listed`, `missing` or `unreadable`. Verify the tests pass and flip their rows green.
- [x] 2.4 Write failing tests in `test/application/settings_screenshot_cleanup_test.dart` for "Off by default" (no key, and a non-bool value, both read false) and "The setting survives a restart". Then add `AppSettings.cleanUpRaidScreenshots` with the `cleanUpRaidScreenshots` JSON key and `SettingsController.setCleanUpRaidScreenshots` (D3). Verify they pass, flip the rows green, and re-run `test/application/settings_load_test.dart` (still green).

## 3. Cleanup controller

Skills: `dart-use-pattern-matching`, `dart-write-documentation`, `dart-add-unit-test`, `dart-run-static-analysis`, and AGENTS.md "Dart and Flutter code" (no sleeps: completers, a fake clock, and short durations injected through the constructor).

- [x] 3.1 Define `RecyclePort` in `lib/application/` with `recycle(folder, names)` and `cancel()`, a per-name sealed status (`moved`, `missing`, `notRecyclable`, `rejected`, `failed`, `cancelled`), and a call failure. Add `test/support/fake_recycle_port.dart`. It is a hand-written fake whose calls complete through completers, with per-name scripted statuses. Verify with `mise run analyze`.
- [x] 3.2 Write failing tests in `test/application/screenshot_cleanup_controller_test.dart` for the freshness rows: "A live raid ends", "A raid ended by a client restart" (D8, with a replayed crash raid and its old queue entry still stale), "Replay at start-up", "Switched on after the raid ended", "Matching aborted" and "The same raid ends again". Also cover a reconnect after a client restart, which keeps the same `startId` and is cleaned once (review S5). Verify they fail because the controller does not exist.
- [x] 3.3 Implement `ScreenshotCleanupController` in `lib/application/screenshot_cleanup_controller.dart` (D4, D6, D7, D8). It takes the lifecycle source, the settings, a folder getter, the lister, the port, the clock and the injected backstop and cancel-wait durations. It keeps a FIFO of at most 4, the last 16 cleaned `startId`s and `lastResult`. Verify the 3.2 tests pass and flip their rows green.
- [x] 3.4 Write failing tests for the move and queue rows: "Every file moves", "The Recycle Bin cannot take a file" (`notRecyclable`), "The recycle call fails", "The recycle call does not answer" (backstop, then `cancel`, no further batch, unanswered names "not confirmed", and the next call held until the late reply or the cancel wait ends, then the port marked unavailable for the run; review M2, S8), "One file is locked" (a fake `failed` for one name; review S2), "A file vanished before the move", "The folder changed during the raid", "Two raids end close together", "Switched off while a cleanup waits", "Blackgrid closes during a cleanup" (dispose calls `cancel` and starts nothing new), "Too many cleanups waiting" and "The folder is missing". Also cover batching into calls of 64. Implement until they pass, then flip their rows green.
- [x] 3.5 Add the audit test `test/data/screenshot_write_audit_test.dart` (D5). It bans `.delete(`, `.rename(`, `openWrite`, `writeAsBytes`, `writeAsString`, `FileMode.write`, `FileMode.append`, `Process.` and `dart:ffi` in `lib/data/screenshot_directory_watcher.dart`, `lib/data/screenshot_folder_lister.dart`, `lib/domain/screenshot_cleanup.dart` and `lib/application/screenshot_cleanup_controller.dart`, following `test/data/game_log/log_input_audit_test.dart`. Verify it passes, and that it fails when a banned call is added to one of those files temporarily.

## 4. Settings Game files row

Skills: `flutter-add-widget-test`, `dart-write-documentation`, `dart-run-static-analysis`, and AGENTS.md "Dart and Flutter code".

- [x] 4.1 Write failing widget tests in `test/ui/settings_page_test.dart` for "The cleanup switch sits under the screenshot folder", "Switching cleanup on", "screenshot-cleanup: Save fails", "Screenshots moved", "Some could not be moved", "No screenshots in the raid" and "Nothing yet". Drive the result lines from a controller over the fake port. Also check the "could not be confirmed" and "cleanup unavailable for this run" lines (review S8). Verify they fail.
- [x] 4.2 Build the switch "Delete a raid's screenshots after it ends" (a DESIGN.md X13 switch) under the screenshot folder in Game files, with its result line. Verify the 4.1 tests pass, flip their rows green, and re-run `settings-page: Save a folder on Enter`, `settings-page: Save on leaving` and `settings-page: Save fails` (still green).

## 5. Runner recycle channel

Skills: `dart-write-documentation`, `dart-add-unit-test`, `dart-run-static-analysis` for the Dart port; the C++ follows `windows/runner/audio_channel.cpp`.

- [ ] 5.1 Write a failing test in `test/data/channel_recycle_port_test.dart` with a mock method-call handler on `blackgrid/recycle`. It checks the `recycle` arguments (`folder`, `names` of at most 64) and `cancel`, the mapping of each status string, a malformed reply giving a call failure, and the port making no call outside those two methods.
- [ ] 5.2 Implement `ChannelRecyclePort` in `lib/data/channel_recycle_port.dart`. Verify the 5.1 test passes.
- [ ] 5.3 Implement `windows/runner/recycle_channel.{h,cpp}` and register it in `flutter_window.cpp` beside the audio channel, with `kRecycleChannelMessage = WM_APP + 2` (review S4). Add it to `windows/runner/CMakeLists.txt`. The channel works as follows (D1, D2):
  - each name is checked again: no separator and no `..`, not a directory and not a reparse point;
  - each file gets its own `IFileOperation`, with `FOFX_RECYCLEONDELETE | FOF_ALLOWUNDO | FOF_NO_UI`, on an STA worker thread, with a `PreDeleteItem` veto when `TSF_DELETE_RECYCLE_IF_POSSIBLE` is missing;
  - the worker shares a `Shared` (HWND, generation, `std::atomic<bool> stop`) and never refers back to the channel. `stop` is reset for each new call (review S6);
  - `cancel` sets `stop`;
  - destroying the channel sets `stop`, completes the pending call with `cancelled` and detaches the worker. Use `cancelled` for this case everywhere; ADR-0048 states it, which settles the design's `failed` wording (review S7);
  - a second call while one is pending gets `busy`.

  Verify that `mise run build:release` compiles cleanly.
- [ ] 5.4 Build `ScreenshotCleanupController` in `AppServices` right after `RaidLifecycleController`, before the reader binds. Feed it `SettingsController`, `mapSession.state.screenshotDirectory`, `ScreenshotFolderLister`, `ChannelRecyclePort` and `DateTime.now`. In `AppServices.dispose`, dispose it before `mapSession.close()` and `raidLifecycle.dispose()` (review S4). Verify with a `test/application/app_services_test.dart` case that it is built before bind and disposed first, and with `mise run test` and `mise run analyze`, both clean.
- [ ] 5.5 [evidence] Run an offline smoke check of the real channel, only after confirming Escape from Tarkov is not running (AGENTS.md). Point Blackgrid's game log folder at a temp fixture session folder and its screenshot folder at a temp folder on the system drive holding game-named and other files. Switch cleanup on, append fresh queue, raid-start and raid-exit lines to the fixture logs, and record which files went to the Recycle Bin, which stayed, and the result line → evidence/runner-smoke.md

## 6. Wiring and integration

Skills: `dart-add-unit-test`, `dart-run-static-analysis`, and AGENTS.md "Dart and Flutter code".

- [ ] 6.1 Run `openspec validate add-screenshot-cleanup --strict` and `mise run release-notes -- --check openspec/changes/add-screenshot-cleanup/proposal.md`. Verify both exit 0.
- [ ] 6.2 [user] The owner switches cleanup on and plays a real raid that includes screenshots. Check that the raid's screenshots are in the Recycle Bin afterwards, that screenshots from before the raid and any other files in the folder are still there, and that the result line matches. If the owner has a screenshot folder on a drive with no Recycle Bin, also check that cleanup leaves the files there and says they could not be moved. This is the M10 user criterion "screenshot cleanup removes a real raid's screenshots".

## Workflow follow-up

- Pre-ship review, then `specwright-pr` ship, as `finish: pr`.
- Archive after the PR merges and 6.2 is ticked.
