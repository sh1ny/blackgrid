# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| audio-alerts → The alerts and their spoken lines | Spoken line of an alert | test/domain/alerts_test.dart | `each alert has its fixed spoken line` | green |
| audio-alerts → The alerts and their spoken lines | Unknown alert in stored settings | test/domain/alert_settings_test.dart | `unknown alert id in stored settings is ignored` | green |
| audio-alerts → Match found and raid starting fire from the raid lifecycle | A queue to a raid | test/application/alerts_controller_test.dart | `match found then raid starting each play once` | green |
| audio-alerts → Match found and raid starting fire from the raid lifecycle | Raid with no countdown | test/application/alerts_controller_test.dart | `raid starting plays at raid start when no countdown was logged` | green |
| audio-alerts → Match found and raid starting fire from the raid lifecycle | Rejoined raid | test/application/alerts_controller_test.dart | `a rejoined raid plays no raid starting` | green |
| audio-alerts → Match found and raid starting fire from the raid lifecycle | Cancelled match | test/application/alerts_controller_test.dart | `matching completed without joining a server plays nothing` | green |
| audio-alerts → Match found and raid starting fire from the raid lifecycle | Same transition delivered twice | test/application/alerts_controller_test.dart | `a transition identity fires at most once` | green |
| audio-alerts → Run-through over fires when the countdown reaches zero | Countdown reaches zero | test/application/alerts_controller_timers_test.dart | `run-through over plays once when the countdown reaches zero` | green |
| audio-alerts → Run-through over fires when the countdown reaches zero | Raid ends first | test/application/alerts_controller_timers_test.dart | `raid ending before the run-through plays nothing` | green |
| audio-alerts → Run-through over fires when the countdown reaches zero | Already over at startup | test/application/alerts_controller_timers_test.dart | `run-through already over at startup plays nothing` | green |
| audio-alerts → Run-through over fires when the countdown reaches zero | Raid continued after a client restart | test/application/alerts_controller_timers_test.dart | `a raid continued after a client restart keeps its alert` | green |
| audio-alerts → Run-through over fires when the countdown reaches zero | Scav or reconnected raid | test/application/alerts_controller_timers_test.dart | `a scav raid has no run-through alert` | green |
| audio-alerts → Run-through over fires when the countdown reaches zero | Scav or reconnected raid | test/application/alerts_controller_timers_test.dart | `a reconnected raid has no run-through alert` | green |
| audio-alerts → Scav ready fires when the active mode's cooldown reaches ready | Cooldown runs out | test/application/alerts_controller_timers_test.dart | `scav ready plays once when the cooldown runs out` | green |
| audio-alerts → Scav ready fires when the active mode's cooldown reaches ready | Ready during a raid | test/application/alerts_controller_timers_test.dart | `a cooldown that ends mid-raid plays nothing` | green |
| audio-alerts → Scav ready fires when the active mode's cooldown reaches ready | Ready at startup | test/application/alerts_controller_timers_test.dart | `scav already ready at startup plays nothing` | green |
| audio-alerts → Scav ready fires when the active mode's cooldown reaches ready | Mode switch to a ready mode | test/application/alerts_controller_timers_test.dart | `switching to a ready mode plays nothing` | green |
| audio-alerts → Scav ready fires when the active mode's cooldown reaches ready | Progress loads after startup | test/application/alerts_controller_timers_test.dart | `progress loading that makes the cooldown ready plays nothing` | green |
| audio-alerts → Air filter reminders follow the queue and the raid's end | Unit built | test/application/alerts_controller_reminders_test.dart | `air filter on at queue and off at raid end when built` | green |
| audio-alerts → Air filter reminders follow the queue and the raid's end | Raid ended by a client restart | test/application/alerts_controller_reminders_test.dart | `client-restart ending skips air filter off` | green |
| audio-alerts → Air filter reminders follow the queue and the raid's end | Unit not built | test/application/alerts_controller_reminders_test.dart | `air filter reminders silent when the unit is not built` | green |
| audio-alerts → Air filter reminders follow the queue and the raid's end | Progress unavailable | test/application/alerts_controller_reminders_test.dart | `air filter reminders wait for local progress` | green |
| audio-alerts → Quest items reminder fires once per queue for item objectives on the map | A plant objective on the queued map | test/domain/alert_rules_test.dart | `quest items fires for an unfinished plant objective on the map` | green |
| audio-alerts → Quest items reminder fires once per queue for item objectives on the map | Objective already done | test/domain/alert_rules_test.dart | `quest items silent when the objective is done` | green |
| audio-alerts → Quest items reminder fires once per queue for item objectives on the map | Map changes in the same queue | test/application/alerts_controller_reminders_test.dart | `quest items plays at most once per queue` | green |
| audio-alerts → Quest items reminder fires once per queue for item objectives on the map | Unknown map | test/domain/alert_rules_test.dart | `quest items silent for an unknown map` | green |
| audio-alerts → Quest items reminder fires once per queue for item objectives on the map | Map or quest data unavailable | test/application/alerts_controller_reminders_test.dart | `quest items waits for map, quest or progress data` | green |
| audio-alerts → Failed tasks reminder waits for the menus | Failure mid-raid | test/application/alerts_controller_reminders_test.dart | `failed tasks plays on return to menus, not mid-raid` | green |
| audio-alerts → Failed tasks reminder waits for the menus | Failure that cannot be restarted | test/domain/alert_rules_test.dart | `failed tasks ignores tasks not marked restartable` | green |
| audio-alerts → Failed tasks reminder waits for the menus | Two failures in one raid | test/application/alerts_controller_reminders_test.dart | `two failures play one reminder` | green |
| audio-alerts → Failed tasks reminder waits for the menus | Failure read while in menus | test/application/alerts_controller_reminders_test.dart | `failure read in menus plays at once` | green |
| audio-alerts → Failed tasks reminder waits for the menus | Client restart mid-raid | test/application/alerts_controller_reminders_test.dart | `failed tasks waits through a client restart until the raid ends` | green |
| audio-alerts → Only fresh log events fire alerts | Live event | test/application/alerts_controller_test.dart | `a transition logged 2 s ago plays` | green |
| audio-alerts → Only fresh log events fire alerts | Replay at startup | test/application/alerts_controller_test.dart | `a replayed transition logged 20 minutes ago plays nothing` | green |
| audio-alerts → Only fresh log events fire alerts | Log time in the future | test/application/alerts_controller_test.dart | `a transition with a future log time counts as fresh` | green |
| audio-alerts → Each alert has a switch | Defaults | test/domain/alert_settings_test.dart | `default switches: raid four on, reminders off` | green |
| audio-alerts → Each alert has a switch | Alert off | test/application/alerts_controller_test.dart | `an alert switched off does not play` | green |
| audio-alerts → Each alert plays speech or the player's sound file | Custom file | test/application/alerts_controller_playback_test.dart | `custom file plays in place of speech` | green |
| audio-alerts → Each alert plays speech or the player's sound file | File removed | test/application/alerts_controller_playback_test.dart | `missing file falls back to speech and flags the row` | green |
| audio-alerts → Each alert plays speech or the player's sound file | Unsupported file chosen | test/ui/settings_page_alerts_test.dart | `choosing a non-WAV/MP3 file is refused` | green |
| audio-alerts → Each alert plays speech or the player's sound file | File choice cancelled | test/ui/settings_page_alerts_test.dart | `cancelling the file dialog keeps the sound` | green |
| audio-alerts → Alerts play one at a time | Two alerts close together | test/application/alerts_controller_playback_test.dart | `alerts play in order without overlap` | green |
| audio-alerts → Alerts play one at a time | Stale alert | test/application/alerts_controller_playback_test.dart | `an alert waiting over 15 s is dropped` | green |
| audio-alerts → Playback failures stay visible and never stop the alerts | Speech unavailable | test/application/alerts_controller_playback_test.dart | `speech failure is shown and the next alert plays` | green |
| audio-alerts → Playback failures stay visible and never stop the alerts | Recovery | test/application/alerts_controller_playback_test.dart | `a later success clears the failure` | green |
| audio-alerts → One voice for all spoken alerts | Voice list | test/ui/settings_page_alerts_test.dart | `voice list starts with Windows default` | green |
| audio-alerts → One voice for all spoken alerts | Saved voice uninstalled | test/application/alerts_controller_playback_test.dart | `uninstalled voice falls back to default and is reported` | green |
| audio-alerts → One voice for all spoken alerts | No voices listed | test/ui/settings_page_alerts_test.dart | `unreadable voice list offers only Windows default` | green |
| audio-alerts → Speed and volume stay in range | Volume applies to files | test/application/alerts_controller_playback_test.dart | `volume is passed to file playback` | green |
| audio-alerts → Speed and volume stay in range | Out-of-range stored value | test/domain/alert_settings_test.dart | `stored speed 9 loads as 5` | green |
| audio-alerts → Each alert has a test button | Test an alert that is off | test/ui/settings_page_alerts_test.dart | `test button plays an alert that is off` | green |
| audio-alerts → Each alert has a test button | Test while another alert plays | test/application/alerts_controller_playback_test.dart | `a test waits behind the playing alert` | green |
| audio-alerts → Alert settings survive restart | Restart keeps choices | test/application/settings_alerts_test.dart | `alert settings survive a restart` | green |
| audio-alerts → Alert settings survive restart | Older record | test/application/settings_alerts_test.dart | `a record without alerts loads the defaults` | green |
| audio-alerts → Alert settings survive restart | Save fails | test/application/settings_alerts_test.dart | `a failed volume save keeps the previous value` | green |
| audio-alerts → Alerts never touch the game | Alerts use only the audio channel | test/data/channel_audio_port_test.dart | `alerts call only the audio channel's methods` | green |
| audio-alerts → Alerts never touch the game | An alert while the game has focus | tasks.md 6.4 | user task 6.4 | user |
| raid-lifecycle → Queue progress transitions are published once | Queue to raid | test/domain/raid_lifecycle_queue_test.dart | `queue to raid publishes queue progress in order` | green |
| raid-lifecycle → Queue progress transitions are published once | Scene outside a queue | test/domain/raid_lifecycle_queue_test.dart | `scene in menus publishes no map-known` | green |
| raid-lifecycle → Queue progress transitions are published once | Rejoin publishes no map-known | test/domain/raid_lifecycle_queue_test.dart | `rejoin publishes no map-known` | green |
| raid-lifecycle → Queue progress transitions are published once | Scene after a rejoin | test/domain/raid_lifecycle_queue_test.dart | `scene after a transit rejoin publishes no map-known` | green |
| raid-lifecycle → Queue progress transitions are published once | Unsupported scene | test/domain/raid_lifecycle_queue_test.dart | `unsupported scene in queue publishes map-known with no map` | green |
| raid-lifecycle → Queue progress transitions are published once | Re-read after restart | test/application/raid_lifecycle_controller_test.dart | `re-reading a folder republishes queue progress with the same identities` | green |
| raid-lifecycle → A match is found once the raid's server is joined | Cancelled match | test/domain/raid_lifecycle_queue_test.dart | `matching completed alone publishes no match found` | green |
| raid-lifecycle → A match is found once the raid's server is joined | Server joined outside a matched queue | test/domain/raid_lifecycle_queue_test.dart | `a server joined outside a matched queue publishes nothing` | green |
| raid-lifecycle → A match is found once the raid's server is joined | Second server joined in one queue | test/domain/raid_lifecycle_queue_test.dart | `a second server joined in one queue publishes once` | green |
| raid-lifecycle → Each lifecycle transition is published once | One transition per event | test/domain/raid_lifecycle_test.dart | `a whole raid publishes one start and one end` | green |
| raid-lifecycle → Each lifecycle transition is published once | Re-read after restart | test/application/raid_lifecycle_controller_test.dart | `re-reading a folder republishes the same transitions` | green |
| raid-lifecycle → Each lifecycle transition is published once | Queue progress does not change the raid transitions | test/domain/raid_lifecycle_queue_test.dart | `queue progress leaves raid start and end identities unchanged` | green |
| settings-page → Settings sections and their order | Sidebar order | test/ui/settings_page_test.dart | `sidebar lists the sections in order` | green |
| settings-page → Settings sections and their order | Jump to a section | test/ui/settings_page_test.dart | `settings-page: Jump to a section` | green |
| settings-page → Settings sections and their order | Jump to Alerts | test/ui/settings_page_test.dart | `settings-page: Jump to Alerts` | green |
| settings-page → Settings sections and their order | Jump to Diagnostics | test/ui/settings_page_test.dart | `settings-page: Jump to Diagnostics` | green |

## 1. ADR and lifecycle queue transitions

Skills: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis.

- [x] 1.1 Write ADR-0047, "Alerts speak through a runner audio channel", in `docs/adr/` (D1 with its threading and completion contract, D4, D11: OS components only, no bundled audio, the typed sound source and the recorded-pack extension point). Add its row to the in-force index and the Windows runner row of the components table in `openspec/architecture.md`. Verify the index lists 0047 and `docs/adr/README.md` still points to the index.
- [x] 1.2 Write the failing tests in `test/domain/raid_lifecycle_queue_test.dart` for the queue-progress rows (Queue to raid, Scene outside a queue, Rejoin publishes no map-known, Scene after a transit rejoin, Unsupported scene, raid identities unchanged), and the re-read row in `test/application/raid_lifecycle_controller_test.dart`. Verify they fail because the transitions do not exist.
- [x] 1.3 Add `QueueEnteredTransition`, `MapKnownTransition`, `MatchFoundTransition` and `RaidStartingTransition` to `lib/domain/raid_lifecycle.dart`. Publish them from `reduce`, with map-known only for scenes after a queue entered while the pending entry is a queue (D6, review N2). Add no-op arms to every exhaustive `RaidTransition` switch, including `raid_timers_controller.dart` and the task-log controller. Verify the 1.2 tests pass, flip their rows green, and re-run `a whole raid publishes one start and one end` and `re-reading a folder republishes the same transitions` (still green). Run `mise run analyze`.

## 2. Alert model, settings and rules

Skills: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test.

- [x] 2.1 Write failing tests in `test/domain/alerts_test.dart` and `test/domain/alert_settings_test.dart` for these rows: spoken lines, unknown alert id ignored, default switches, speed 9 loads as 5. Add JSON round-trip tests for the sealed `AlertSound` (speech, file, unknown kind loads as speech) and for a malformed `alerts` block giving the defaults while other settings stay.
- [x] 2.2 Implement the `AlertKind` ids and lines, the sealed `AlertSound` (`SpeechSound`, `FileSound`) and `AlertSettings` (voice, speed −5..5, volume 0..100, items) in `lib/domain/`. Store them in `AppSettings` under the `alerts` key, decoded in their own `try` (D4). Verify the 2.1 tests pass and flip their rows green.
- [x] 2.3 Write failing tests in `test/domain/alert_rules_test.dart` for the pure rules: the freshness check (30 s, future counts as fresh), quest items over a marker list, `ProgressFacts` and the progress catalog (plant item, plant quest item, mark and give quest item; done and unknown-map cases), the air filter built check by `normalizedName`, and whether a failed task is restartable.
- [x] 2.4 Implement the rules in `lib/domain/alert_rules.dart` (D2, D8, D9, D10). Verify the 2.3 tests pass and flip their rows green.
- [x] 2.5 Add the alert setters to `SettingsController`, with clamping, the WAV/MP3 check on a file sound and a save failure that keeps the previous value. Write the `test/application/settings_alerts_test.dart` rows first (restart keeps choices, older record, save fails), then implement. Verify they pass and flip the rows green.

## 3. Alerts controller and playback queue

Skills: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test. Use a hand-written `FakeAudioPort` with completers, plus an injected clock and timer factory. No sleeps (AGENTS.md).

- [x] 3.1 Define the `AudioPort` interface (`voices`, `speak`, `playFile`, `stop`, `openVoiceSettings`, `pickSoundFile`) and a sealed `AudioResult`: ok, or a failure with the codes `voice_missing`, `file_missing`, `file_unplayable`, `speech_failed`, `stopped`, `timeout` and `busy`. Add `test/support/fake_audio_port.dart`. Verify with `mise run analyze`.
- [x] 3.2 Write failing tests in `test/application/alerts_controller_playback_test.dart` for the queue and playback rows: custom file, missing-file fallback, order without overlap, the 15 s drop, the cap of 8 waiting, speech failure and recovery, voice fallback, volume passed to files, a test waiting behind the playing alert, and a file `timeout` dropped without falling back to speech. Write them with the fake port and fake clock.
- [x] 3.3 Implement the queue in `lib/application/alerts_controller.dart` (D3, D5, the Failure & Visibility rows, the Dart backstops of 30 s for speech and 125 s for files) and its view of row problems, the last failure and waiting notes. Verify the 3.2 tests pass and flip their rows green.
- [x] 3.4 Write failing tests in `test/application/alerts_controller_test.dart` for the lifecycle and freshness rows: match found then raid starting, no countdown, identity de-duplication, live, replay and future times, and an alert switched off. Implement the transition handling. Verify they pass and flip the rows green.
- [x] 3.5 Write failing tests in `test/application/alerts_controller_timers_test.dart` for the run-through and scav rows. Include progress loading after startup and a mode switch (D7, review M2). Implement the one-shot deadline planner. Verify they pass and flip the rows green.
- [x] 3.6 Add `MapController.markersFor(settingsMapId)`, returning live markers, else the bundled ones, or null with no pack, with its own test in `test/application/map_controller_test.dart`. Then write failing tests in `test/application/alerts_controller_reminders_test.dart` for the air filter, quest items and failed tasks rows: once per queue, the waiting notes, release in menus with no current raid, waiting through a client restart (review M1, N3), and a client-restart ending skipping air filter off. Implement them. Verify they pass and flip the rows green.

## 4. Runner audio channel

Skills: dart-write-documentation, dart-add-unit-test, dart-run-static-analysis.

- [x] 4.1 Write a failing test in `test/data/channel_audio_port_test.dart` that uses a mock method-call handler on `blackgrid/audio`. It checks that each `AudioPort` call maps to its channel method and arguments, that each error code maps to its `AudioResult`, and that firing every alert and test makes no call outside that channel's methods. That last check is the "Alerts use only the audio channel" row.
- [x] 4.2 Implement `ChannelAudioPort` in `lib/data/`. Verify the 4.1 test passes and flip its row green.
- [x] 4.3 Implement `windows/runner/audio_channel.cpp/.h` and register it in `flutter_window.cpp` beside `local_data_channel`:
  - `voices` (OneCore `SpeechSynthesizer::AllVoices`), `speak` (synthesise to a stream, play through `MediaPlayer`), `playFile` (with the runner's own timeout), `stop`, `openVoiceSettings` (`ms-settings:speech`) and `pickSoundFile` (`IFileOpenDialog`, WAV/MP3 filter, owned by the Blackgrid window).
  - Completions are marshalled through a private window message, with no `.get()` on the UI thread. One pending result is completed exactly once, including `stopped` on window destroy and `busy`.
  - Link `windowsapp.lib`.

  Verify that `mise run build:release` compiles with no new warnings at /W4, that `mise run bundle:check` passes with the bundle inventory unchanged, and that `mise run analyze` is clean.
- [x] 4.4 [evidence] Run an offline smoke check of the runner channel on this machine, only after confirming Escape from Tarkov is not running (AGENTS.md). Launch Blackgrid, press each alert's test button and the voice preview, and record the voices listed and each call's result → evidence/runner-smoke.md

## 5. Settings Alerts section

Skills: flutter-add-widget-test, dart-write-documentation. Colours come from the Ember theme (ADR-0037).

- [x] 5.1 Write failing widget tests in `test/ui/settings_page_alerts_test.dart`, plus the sidebar order and Jump to Alerts rows in `test/ui/settings_page_test.dart`. Cover: the voice list starting with Windows default, an unreadable voice list, the test button on an alert that is off, a refused non-WAV/MP3 file, a cancelled dialog, and the row problems and waiting notes shown. Use the fake port.
- [x] 5.2 Build the Alerts section between Raid timers and Map. It has the voice row (dropdown, preview, Get more voices), the speed and volume sliders, the last playback failure line, and eight alert rows, each with a switch (DESIGN.md X13), a sound choice (speech, or a file through the Windows dialog), a test button and its problem line. Verify the 5.1 tests pass, flip their rows green, and re-run `settings-page: Jump to a section` and `settings-page: Jump to Diagnostics` (still green).

## 6. Wiring and integration

- [x] 6.1 Build `AlertsController` in `AppServices` right after `RaidLifecycleController`, before the reader binds. Feed it the settings, catalog, `ProgressAuthority`, `MapController` and `ChannelAudioPort`, and dispose it in order (stopping playback). Verify with an `app_services` test that the controller is built before bind and disposed, and with `mise run test` and `mise run analyze`, both clean.
- [x] 6.2 Run `openspec validate add-audio-alerts --strict` and `mise run release-notes -- --check openspec/changes/add-audio-alerts/proposal.md`. Verify both exit 0.
- [x] 6.3 [user] The owner plays raids with the alerts on and checks the M10 user criterion for alerts. Each alert must sound right and fire at the right moment: match found, raid starting, run-through over and scav ready; the air filter and quest items reminders at queue time; restart failed tasks back in the menus. Passed (owner, 2026-11-21). In online raids every line plays at the right moment, raid starting included, at the start of the countdown. Only offline raids are off: there "Raid starting" plays at the end of the countdown. The owner accepts this.
- [x] 6.4 [user] The owner checks that an alert playing while the game window has focus leaves the game focused and undisturbed. This is the "An alert while the game has focus" row. Passed (owner, 2026-11-21).

## Workflow follow-up

- After apply: pre-ship review, then `specwright-pr` ship (finish: pr), then archive on the branch.
- Later (not this change): detect the Air Filtering Unit toggle from the game's logs when a signal is found, and recorded sound packs as a new `AlertSound` kind.
