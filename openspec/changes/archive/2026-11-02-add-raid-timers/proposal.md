# Proposal

## Why

This change serves M7 (raid lifecycle, timers and local stats) and is its second change. It delivers the milestone's second exit criterion: "Time in raid, the run-through countdown and the scav cooldown show in Blackgrid's own window, never on the game screen. Their settings survive restart, and the countdowns are proved by fake-clock tests." It also gives the user-verified criterion ("during real raids, the raid state, timers and stats follow the game") its timers part.

`add-raid-lifecycle` (archived 2026-11-01) made Blackgrid follow the raid phase from the game's logs, but the player still has to keep their own time: when the raid started, whether they are still inside the run-through window, and when their scav is ready again. TarkovMonitor shows these timers; Blackgrid rebuilds them independently, without copying its code and without its bugs:

- **TarkovMonitor counts from when it saw an event, not from the log's time.** A late read or an app restart mid-raid resets or shifts its timers. Blackgrid counts from the raid's log times, so a restart mid-raid shows the same time in raid.
- **TarkovMonitor works out the scav cooldown length once, at the first Tracker progress.** A later change of Fence reputation or a newly built hideout level is ignored until a restart. Blackgrid works it out again whenever an input changes.
- **TarkovMonitor forgets a running cooldown when it closes.** Blackgrid keeps the cooldown's start per game mode, so it survives a restart of Blackgrid or the game.

A read of the user's own logs on 2026-11-01 settled how a scav raid is recognised. The logs never name the raid's side for a solo raid: `groupMatchRaidSettings` carries `"side"` and profiles carry `SavageLockTime`, but only in group play. Blackgrid therefore uses the same rule as TarkovMonitor, chosen by the user: a raid entered from a queue is a scav raid when it had no raid-starting countdown, or when the countdown lasted 3 s or less. In PvE every raid counts. In the user's 300 most recent raids, 210 had a countdown of 10 s or more, 76 had one of 3 s or less or none, and 10 fell between 3 and 10 s and count as PMC. The user's real-raid check (M7 criterion 4) confirms the rule. As in TarkovMonitor, the cooldown starts when the scav raid ends; the user chose this over the raid start.

## What Changes

- **Time in raid.** From the raid's start in the log to now while the raid is current, then frozen at its log end. A reconnect continues the same raid and its time. A transit starts a new raid and so a new count.
- **Run-through countdown.** The run-through length minus the time in raid, counting down to 0:00 while the raid is current. It stops when the raid ends. The length is a setting, 7:10 by default.
- **Scav cooldown countdown.** It starts at the end of a raid recognised as a scav raid, per game mode, and counts down to "Scav ready". Its length is the mode's base cooldown from tarkov.dev's data, times the Fence reputation modifier, less the scav-cooldown bonuses of the hideout levels built according to Tracker progress. The length is recalculated whenever the Fence reputation, the item data or the progress changes. Without Tracker progress the length has no hideout bonus and says so. Without item data the cooldown shows as unknown.
- **The raid records its countdown and its side.** A raid now records the time of its raid-starting event and a guessed side (PMC, scav or unknown), using the rule above.
- **Item data carries the cooldown inputs.** The catalog keeps the mode's base scav cooldown, Fence's reputation levels with their cooldown modifier, and each hideout level's scav-cooldown bonus, which are already in the datasets it downloads. A catalog without them stays valid and usable for everything else.
- **A timer strip in the shell.** A slim strip under the header, visible on both Map and Scanner, shows the timers that are on. It is hidden when every timer is off. Nothing is drawn on the game screen.
- **Settings.** A "Raid timers" section in the Settings dialog: timers on or off, which of the three show, the run-through length, and the Fence reputation for the current mode. Settings and each mode's cooldown start survive restart.
- **Fake-clock tests.** Every countdown, the scav rule and the cooldown length are proved offline with an injected clock and small synthetic inputs.

Out of scope:

- No overlay and no window over the game. The strip lives in Blackgrid's own window (STRATEGY.md non-goals).
- No sounds, notifications or alerts when a timer runs out. They can be a later change.
- No manual start or clear of the scav cooldown. It follows the logs only, as in TarkovMonitor.
- No reading of the Fence reputation from the game or from Tracker. The player types it in.
- No local stats. They come with `add-local-stats`.

## Capabilities

### New Capabilities

- `raid-timers`: time in raid, the run-through countdown and the scav cooldown (when it starts, its length from item data, Fence reputation and hideout progress, its persistence per mode), the timer strip in Blackgrid's window and the timer settings.

### Modified Capabilities

- `raid-lifecycle`: a raid also records the time of its raid-starting event and a guessed side, so the scav cooldown knows which raids count.

## Impact

- **Code:**
  - `lib/domain/raid_lifecycle.dart`: `Raid` gains the raid-starting time and a guessed side.
  - New: `lib/domain/raid_timers.dart` (pure timer projection and cooldown length) and `lib/application/raid_timers_controller.dart` (ticks on an injected clock, starts cooldowns from raid-ended transitions, saves them).
  - `lib/domain/catalog.dart` and `lib/data/catalog_normalizer.dart`: the scav cooldown inputs on the snapshot.
  - `lib/domain/settings.dart` and `lib/application/settings_controller.dart`: timer settings and the per-mode cooldown start in the settings record.
  - `lib/ui/shell.dart`, a new `lib/ui/raid_timer_strip.dart`, and `lib/ui/settings_dialog.dart`.
  - `lib/application/app_services.dart`: builds and disposes the controller.
- **Tests:** new domain and controller tests under `test/domain/` and `test/application/` with a fake clock; normalizer tests for the cooldown inputs; widget tests for the strip and the settings section.
- **Architecture:** a row for `RaidTimersController` and a state-ownership row for the timer settings and cooldown starts.
- **Dependencies:** none new.

## Release Notes

Blackgrid now shows raid timers in its own window: time in raid, the run-through countdown and your scav cooldown, worked out from the game's logs, your Fence reputation and your hideout progress. Nothing is drawn over the game.

### Added
- A timer strip under the header, on both Map and Scanner, shows time in raid, the run-through countdown (7:10 by default) and the scav cooldown, counted from the game's log times so a restart of Blackgrid mid-raid keeps them right.
- The scav cooldown starts when a scav raid ends and uses tarkov.dev's base time, your Fence reputation and the hideout bonuses from your Tracker progress. It is kept per game mode and survives a restart.
- A "Raid timers" section in Settings turns the timers on or off, chooses which show, and sets the run-through length and your Fence reputation.
