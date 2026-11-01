# Tasks

Skills for every Dart group (AGENTS.md "Dart and Flutter code"): `dart-use-pattern-matching`, `dart-add-unit-test`, `dart-write-documentation` and `dart-run-static-analysis`. Group 7 also uses `flutter-add-widget-test`.

Rules for every group:
- Clocks are injected (`DateTime Function()`) and periodic ticks are driven with `fake_async` from `flutter_test`, as `test/data/catalog_client_test.dart` does. No arbitrary sleeps.
- Inputs are small synthetic values: made-up IDs, 2-3 Fence levels, 1-2 hideout bonuses.
- The game is never launched or touched.
- "Active mode" always means the app's effective mode (`MapSessionController.effectiveMode`, read as `catalog.mode`, design D6), never `settings.mode`. Design D6's heading and D7's arming rule say "selected mode" for this.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| raid-lifecycle → A raid records its countdown and a guessed side | PMC countdown | test/domain/raid_lifecycle_side_test.dart | countdown over 3 s records raid starting and side PMC | red |
| raid-lifecycle → A raid records its countdown and a guessed side | No countdown | test/domain/raid_lifecycle_side_test.dart | no raid starting gives side scav | red |
| raid-lifecycle → A raid records its countdown and a guessed side | Short countdown | test/domain/raid_lifecycle_side_test.dart | 2 s countdown gives side scav | red |
| raid-lifecycle → A raid records its countdown and a guessed side | Countdown exactly 3 s | test/domain/raid_lifecycle_side_test.dart | exactly 3 s countdown gives side scav | red |
| raid-lifecycle → A raid records its countdown and a guessed side | Raid starting from an aborted queue | test/domain/raid_lifecycle_side_test.dart | raid starting of an aborted queue is forgotten | red |
| raid-lifecycle → A raid records its countdown and a guessed side | Transit keeps the side | test/domain/raid_lifecycle_side_test.dart | transit raid takes the previous raid's side | red |
| raid-lifecycle → A raid records its countdown and a guessed side | Reconnect keeps the side | test/domain/raid_lifecycle_side_test.dart | continued reconnect keeps side PMC | red |
| raid-lifecycle → A raid records its countdown and a guessed side | No queue | test/domain/raid_lifecycle_side_test.dart | raid without a queue has side unknown | red |
| raid-lifecycle → A raid records its countdown and a guessed side | Reconnect after Blackgrid starts | test/domain/raid_lifecycle_side_test.dart | new reconnect raid has side unknown | red |
| raid-timers → Time in raid counts from the raid's log start | Raid in progress | test/domain/raid_timers_test.dart | time in raid is now minus the log start | red |
| raid-timers → Time in raid counts from the raid's log start | Blackgrid restarted mid-raid | test/application/raid_timers_controller_test.dart | replayed current raid shows elapsed time before any tick | red |
| raid-timers → Time in raid counts from the raid's log start | Raid ended | test/domain/raid_timers_test.dart | ended raid freezes as last raid | red |
| raid-timers → Time in raid counts from the raid's log start | Reconnect continues the count | test/domain/raid_timers_test.dart | continued reconnect keeps the original start | red |
| raid-timers → Time in raid counts from the raid's log start | Log time ahead of the clock | test/domain/raid_timers_test.dart | start after now clamps to zero | red |
| raid-timers → Time in raid counts from the raid's log start | No raid known | test/domain/raid_timers_test.dart | no raid gives a dash | red |
| raid-timers → The run-through countdown runs while the raid is current | Counting down | test/domain/raid_timers_test.dart | run-through is length minus time in raid | red |
| raid-timers → The run-through countdown runs while the raid is current | Past the run-through length | test/domain/raid_timers_test.dart | run-through past the length is done | red |
| raid-timers → The run-through countdown runs while the raid is current | Raid ended before the length | test/domain/raid_timers_test.dart | no run-through after the raid ends | red |
| raid-timers → The run-through countdown runs while the raid is current | Length changed mid-raid | test/application/raid_timers_controller_test.dart | run-through length change applies at once | red |
| raid-timers → A scav raid's end starts that mode's scav cooldown | Scav raid ends | test/application/raid_timers_controller_test.dart | scav raid ending records its mode's start | red |
| raid-timers → A scav raid's end starts that mode's scav cooldown | PMC raid ends | test/application/raid_timers_controller_test.dart | PMC raid ending records nothing | red |
| raid-timers → A scav raid's end starts that mode's scav cooldown | PvE raid ends | test/application/raid_timers_controller_test.dart | any PvE raid ending records a PvE start | red |
| raid-timers → A scav raid's end starts that mode's scav cooldown | Unknown mode | test/application/raid_timers_controller_test.dart | raid with unknown mode records nothing | red |
| raid-timers → A scav raid's end starts that mode's scav cooldown | Ended by client restart | test/application/raid_timers_controller_test.dart | client-restart ending records its end time | red |
| raid-timers → A cooldown start is never moved back or started twice | Replay after restart | test/application/settings_raid_timers_test.dart | recording the stored start again saves nothing | red |
| raid-timers → A cooldown start is never moved back or started twice | Older folder replayed | test/application/settings_raid_timers_test.dart | older start never replaces a later one | red |
| raid-timers → A cooldown start is never moved back or started twice | Settings saved from older values | test/application/settings_raid_timers_test.dart | save built from older settings keeps the newer start | red |
| raid-timers → A cooldown start is never moved back or started twice | Newer scav raid | test/application/settings_raid_timers_test.dart | later start replaces the stored one | red |
| raid-timers → The scav cooldown length comes from item data, Fence reputation and hideout progress | Neutral reputation, no bonus | test/domain/raid_timers_test.dart | neutral reputation and no bonus give the base | red |
| raid-timers → The scav cooldown length comes from item data, Fence reputation and hideout progress | Reputation and hideout bonuses | test/domain/raid_timers_test.dart | reputation 2.50 and two bonuses give 780 s | red |
| raid-timers → The scav cooldown length comes from item data, Fence reputation and hideout progress | Reputation below every level | test/domain/raid_timers_test.dart | reputation below every level uses the lowest | red |
| raid-timers → The scav cooldown length comes from item data, Fence reputation and hideout progress | Item data has no cooldown inputs | test/domain/raid_timers_test.dart | missing cooldown inputs give unknown with a reason | red |
| raid-timers → Built hideout levels come from Tracker progress for the same mode | Progress for the mode | test/domain/raid_timers_test.dart | complete module of the same mode adds its bonus | red |
| raid-timers → Built hideout levels come from Tracker progress for the same mode | Progress for another mode | test/domain/raid_timers_test.dart | progress of another mode adds no bonus and says so | red |
| raid-timers → Built hideout levels come from Tracker progress for the same mode | Stale progress | test/domain/raid_timers_test.dart | stale progress still counts | red |
| raid-timers → The scav cooldown counts down to ready | Counting down | test/domain/raid_timers_test.dart | cooldown remaining is start plus length minus now | red |
| raid-timers → The scav cooldown counts down to ready | Ready | test/domain/raid_timers_test.dart | cooldown past its end is ready | red |
| raid-timers → The scav cooldown counts down to ready | Reputation changed while counting | test/application/raid_timers_controller_test.dart | reputation change recomputes the remaining time | red |
| raid-timers → The scav cooldown counts down to ready | Mode switched | test/application/raid_timers_controller_test.dart | switching mode shows that mode's cooldown and keeps the other | red |
| raid-timers → The scav cooldown counts down to ready | Mode from the logs | test/application/raid_timers_controller_test.dart | log-detected mode drives the scav entry | red |
| raid-timers → The scav cooldown counts down to ready | No mode known | test/domain/raid_timers_test.dart | unknown active mode gives unknown with a reason | red |
| raid-timers → Timer displays follow the clock, not a tick count | Missed ticks | test/application/raid_timers_controller_test.dart | missed ticks do not drift | red |
| raid-timers → Timer displays follow the clock, not a tick count | Nothing moving | test/application/raid_timers_controller_test.dart | no periodic timer while nothing moves | red |
| raid-timers → Timers show in a strip in Blackgrid's window only | All timers on in a raid | test/ui/raid_timer_strip_test.dart | strip shows all three entries on Map and Scanner | red |
| raid-timers → Timers show in a strip in Blackgrid's window only | Long raid | test/domain/raid_timers_test.dart | durations from an hour use h:mm:ss | red |
| raid-timers → Timers show in a strip in Blackgrid's window only | Timers off | test/ui/raid_timer_strip_test.dart | timers off hides the strip | red |
| raid-timers → Timers show in a strip in Blackgrid's window only | Only the scav cooldown chosen | test/ui/raid_timer_strip_test.dart | only the chosen entry shows | red |
| raid-timers → Timer settings live in the Settings dialog | Valid run-through length | test/ui/settings_dialog_raid_timers_test.dart | valid run-through length is saved | red |
| raid-timers → Timer settings live in the Settings dialog | Invalid run-through length | test/ui/settings_dialog_raid_timers_test.dart | invalid run-through lengths are refused | red |
| raid-timers → Timer settings live in the Settings dialog | Fence reputation out of range | test/ui/settings_dialog_raid_timers_test.dart | out-of-range reputation is refused | red |
| raid-timers → Timer settings live in the Settings dialog | Reputation for the detected mode | test/ui/settings_dialog_raid_timers_test.dart | reputation edits the active mode's value | red |
| raid-timers → Timer settings live in the Settings dialog | No mode known | test/ui/settings_dialog_raid_timers_test.dart | reputation field disabled without a mode | red |
| raid-timers → Timer settings and cooldown starts survive restart | Restart restores everything | test/data/durability_restart_test.dart | raid timer settings and starts survive a reopen | red |
| raid-timers → Timer settings and cooldown starts survive restart | Record from an older version | test/domain/raid_timer_settings_test.dart | record without raidTimers decodes to defaults | red |
| raid-timers → Timer settings and cooldown starts survive restart | Save fails | test/application/settings_raid_timers_test.dart | failed save keeps the start pending and effective | red |
| raid-timers → Timer settings and cooldown starts survive restart | Stored settings unreadable | test/application/settings_raid_timers_test.dart | unreadable record is never saved by a recorded start | red |

## 1. ADR and architecture

- [x] 1.1 Write `docs/adr/0031-raid-timers-are-projections-of-log-times.md` (MADR-short, `Status: accepted`, date of writing), recording the decisions listed under design.md "ADRs → To record during apply":
  - timers computed from log times and the clock, never accumulated ticks;
  - per-mode cooldown starts and timer settings in a separately decoded `raidTimers` settings block, moved only later, max-merged in every save, never saved automatically while the record is unreadable;
  - cooldown inputs as an optional catalog block from json.tarkov.dev's REST datasets, with no GraphQL and no version bump;
  - the active mode is the effective mode.

  Verify: the file exists and `rg -n "0031" openspec/architecture.md` finds its index row.
- [x] 1.2 In `openspec/architecture.md`:
  - add the `RaidTimersController` component row and the state rows from design.md "State & Ownership";
  - add `Raid.raidStartingTime`/`side` to the raid lifecycle row;
  - add `scavCooldown` to the catalog snapshot row;
  - add the ADR-0031 index row.

  Verify: `openspec validate add-raid-timers --strict` passes, and the rows name the files that group 6 creates.

## 2. Raid side in the lifecycle (raid-lifecycle delta)

- [ ] 2.1 Write the failing tests in `test/domain/raid_lifecycle_side_test.dart` for the 9 raid-lifecycle rows of the test map. They drive the pure `reduce` with synthetic events and made-up `LogRecordId`s. Verify they fail because `Raid` has no `side` or `raidStartingTime`.
- [ ] 2.2 Implement the side guess (design D2) in `lib/domain/raid_lifecycle.dart`:
  - add `enum RaidSide { pmc, scav, unknown }`, plus `Raid.raidStartingTime` and `Raid.side`, carried by `ended`/`withInterrupted`;
  - add `RaidLifecycleState.pendingCountdown`, set by `RaidStarting` and cleared by queue entered, matching aborted, profile selected and raid started;
  - classify in `_raidStarted`: gap > 3 s → PMC, else scav, for a queue entry; transit → previous raid's side; continued reconnect → unchanged; new reconnect or no queue → unknown.

  Doc-comment the new public members. Verify: the 9 rows are green, `test/domain/raid_lifecycle_test.dart` and `test/application/raid_lifecycle_controller_test.dart` still pass, and the rows are flipped green.

## 3. Cooldown inputs on the catalog

- [ ] 3.1 Write failing tests in `test/data/catalog_normalizer_test.dart` (extra tests, no map rows):
  - fills `scavCooldown` from minimal synthetic `items.data.settings.scavCooldownSeconds`, the Fence trader's `reputationLevels`, and a hideout level's `ScavCooldownTimer` bonus;
  - a missing or malformed part (no settings, no Fence, a non-number modifier, more than 64 levels or 256 bonuses) gives `scavCooldown == null` while the catalog stays valid with the same items;
  - a snapshot JSON round-trip keeps the block, and a stored snapshot JSON without the key loads with `null`.
- [ ] 3.2 Implement `ScavCooldownInputs` in `lib/domain/catalog.dart`: `baseSeconds`, Fence levels sorted by minimum, and `bonuses` keyed `<stationId>-<level>`. Also add the optional `scavCooldown` key in `CatalogSnapshot.toJson`/`fromJson` and extraction in `lib/data/catalog_normalizer.dart` (design D5). `schemaVersion` and `normalizerVersion` stay 1. Verify: the 3.1 tests pass, `test/domain/catalog_authority_test.dart` passes unchanged, and `mise run analyze` is clean.

## 4. Pure timer projection

- [ ] 4.1 Write the failing tests in `test/domain/raid_timers_test.dart` for every test-map row naming that file. Each test calls the pure view function with an explicit `now`, a synthetic `RaidLifecycleState`/`Raid`, `RaidTimerSettings`, `ScavCooldownInputs?` and a `ProgressSnapshot?`. Verify they fail because the library does not exist.
- [ ] 4.2 Implement `lib/domain/raid_timers.dart` (design D1, D6):
  - the view with its entries (In raid / Last raid / Run-through / Scav, each with text and tooltip);
  - `countsAsScavRaid(Raid)` (PvE, or side scav);
  - `scavCooldownLength(inputs, reputation, progress, activeMode)`: base × Fence modifier × (1 + sum of built bonuses), rounded and floored at zero;
  - the reasons for unknown (no mode known, no item data) and the "no hideout bonuses" tooltip;
  - m:ss and h:mm:ss formatting.

  Use switch expressions over `RaidPhase`/`RaidSide`. Verify: the `raid_timers_test.dart` rows are green and flipped.

## 5. Timer settings and cooldown-start persistence

- [ ] 5.1 Write the failing tests in `test/domain/raid_timer_settings_test.dart`:
  - "Record from an older version";
  - extra tests: a malformed `raidTimers` block gives timer defaults and keeps every other setting; an unknown mode key or an out-of-range reputation or length drops only that entry; a JSON round-trip.
- [ ] 5.2 Implement `RaidTimerSettings` in `lib/domain/settings.dart` (design D3): `enabled`, the three show flags, `runThroughSeconds` (60..1800, default 430), `fenceReputation` per `GameMode` (−7.00..6.00, two decimals, default 0) and `scavCooldownStarts` per mode (UTC ISO). Add `AppSettings.raidTimers` with `copyWith`, and decode the block in its own `try`. Verify: the 5.1 tests pass, `test/application/settings_load_test.dart` and `test/data/legacy_import_test.dart` pass unchanged, and the row is flipped.
- [ ] 5.3 Write the failing tests in `test/application/settings_raid_timers_test.dart` for the 6 test-map rows naming that file. They use the in-memory database pattern of the existing settings tests and a fake database that fails or blocks saves on demand, released by a `Completer`. Also add an extra test: `recordScavCooldownStart` during an in-flight user save is written right after that save ends.
- [ ] 5.4 Implement the D4 behaviour in `lib/application/settings_controller.dart`:
  - `recordScavCooldownStart`, with the pending map and the flush after an in-flight save;
  - the max-merge of starts inside every `save`;
  - pending kept after a failed save;
  - `effectiveScavCooldownStarts`;
  - no save while `_settingsUnreadable`;
  - setters `setRaidTimers` and `setFenceReputation(mode, value)`.

  Verify: the 5.3 rows are green and flipped, and `test/application/map_input_settings_test.dart` still passes.
- [ ] 5.5 Add the "Restart restores everything" test to `test/data/durability_restart_test.dart`: save timer settings and a seasonal start, reopen the database, reload. Verify it passes and flip the row.

## 6. RaidTimersController

- [ ] 6.1 Write the failing tests in `test/application/raid_timers_controller_test.dart` for every test-map row naming that file, under `fake_async`:
  - they use a real `RaidLifecycleController` fed by a fake event source, or transitions published through a test seam;
  - they use hand-written fakes of the settings, catalog and progress controllers' listenable surfaces, injected through the constructor;
  - the clock reads the fake time.

  Include "Mode from the logs" (`settings.mode` unknown, `catalog.mode` PvP) and "no periodic timer while nothing moves" (`FakeAsync.periodicTimerCount == 0`).
- [ ] 6.2 Implement `lib/application/raid_timers_controller.dart` (design D6, D7):
  - it subscribes to `transitions` in the constructor, and records the start for a `RaidEndedTransition` whose raid `countsAsScavRaid` and has a known mode;
  - it listens to lifecycle, settings, catalog and progress, and recomputes on each;
  - it reads the active mode as `catalog.mode`, and uses a catalog or progress snapshot only when its mode matches;
  - it arms one `Timer.periodic(tick)` only while a shown value moves;
  - dispose cancels the timer and the subscription.

  Verify: the 6.1 rows are green and flipped.
- [ ] 6.3 Wire it in `lib/application/app_services.dart`: build it right after `raidLifecycle` (`:93`), before `mapSession.initialize()`, and dispose it before `raidLifecycle`. Add an extra test to `test/application/app_services_test.dart` with a synthetic log folder holding a finished scav raid: after `initialize()`, the active mode's cooldown start equals the raid's end. This proves the replay is not missed. Verify it passes.

## 7. Timer strip and settings UI

- [ ] 7.1 Write the failing widget tests:
  - `test/ui/raid_timer_strip_test.dart`, for its 3 rows. The strip is pumped in the shell, the test switches between Map and Scanner, and asserts that the entries' text and tooltips are found and that the strip is absent when off.
  - `test/ui/settings_dialog_raid_timers_test.dart`, for its 5 rows.

  Use the existing harnesses under `test/support/`.
- [ ] 7.2 Implement `lib/ui/raid_timer_strip.dart` and insert it in `lib/ui/shell.dart` between the header and the `Expanded` (design D8). Use a `SizedBox.shrink()` when there are no entries, and a `Tooltip` per entry. Verify: the strip rows are green and flipped, and `test/ui/shell_test.dart` and `test/ui/app_test.dart` still pass.
- [ ] 7.3 Add the "Raid timers" section to `lib/ui/settings_dialog.dart`:
  - an on/off switch and three show checkboxes;
  - a run-through m:ss field that refuses values outside 1:00–30:00 with the spec's message;
  - a Fence reputation field for the active mode (`catalog.mode`), refusing values outside −7.00–6.00, disabled with the note when no mode is known;
  - every change saved through the 5.4 setters.

  Verify: the dialog rows are green and flipped, and `test/ui/settings_dialog_test.dart` still passes.

## 8. Integration checks

- [ ] 8.1 Run `mise run analyze` and `mise run test`. Both pass, and `dart format --set-exit-if-changed lib test` reports no changes.
- [ ] 8.2 Check that every test-map row is green and that `mise run release-notes -- --check openspec/changes/add-raid-timers/proposal.md` exits 0. Update the proposal's `## Release Notes` if what ships changed.
- [ ] 8.3 Run `openspec validate add-raid-timers --strict`, which passes.

## Workflow follow-up

- User-verified (M7 criterion 4, never by an agent): during real raids the strip's time in raid, run-through and scav cooldown follow the game. The scav guess matches the user's scav and PMC raids, and the cooldown matches the game's. Until the user reports it, it is recorded as unverified.
- Then pre-ship review, PR, archive and `/specwright-roadmap next` for `add-local-stats`.
