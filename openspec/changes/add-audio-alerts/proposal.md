# Proposal

## Why

Players alt-tab away while they queue and wait out timers, and miss the moment a match is found, a raid starts, the run-through ends or their scav is ready. Blackgrid already follows the raid lifecycle and the timers (M7), but it can only show them in its window. This is the first change of milestone **M10 - alerts and window behaviour**. It serves M10's first exit criterion: each alert fires once from its raid lifecycle, timer or progress event, has its own switch, plays the default or the player's custom sound, and has a test button, proved by fake-clock and fixture tests with a fake audio port.

It also serves M10's user-verified criterion that the alerts sound right and fire at the right moments in play. Agents never test against the game (AGENTS.md), so this change carries a `[user]` task in tasks.md for the owner's in-play check. It is recorded as unverified until the owner reports it, and is judged again at the M10 close.

## What Changes

- Eight spoken alerts: match found, raid starting, run-through over, scav ready, air filter on, air filter off, check your quest items, and restart failed tasks. Each one fires once from its own event:
  - **Match found** and **raid starting** fire from the raid lifecycle.
  - **Run-through over** fires when the countdown reaches 0:00 during a raid.
  - **Scav ready** fires when the active mode's scav cooldown reaches ready.
  - **Air filter on** fires when the player enters the queue, and **air filter off** when the raid ends. Both are reminders: they fire only when local progress says the Air Filtering Unit is built.
  - **Check your quest items** fires once per queue, as soon as the log names the map. It fires only when a started task has an unfinished plant, mark or quest-item hand-over objective on that map. It never checks the inventory.
  - **Restart failed tasks** fires once when the player is back in the menus after a task failed that the quest data marks restartable.
- The default sound is Windows speech, generated at runtime. Blackgrid bundles no audio.
- One voice setting applies to every alert. It lists the voices installed in Windows, with "Windows default" first, and has a preview button, speed and volume sliders, and a "Get more voices" link that opens Windows' speech settings. If the saved voice has been uninstalled, Blackgrid falls back to the default voice and says so under the voice row.
- Each alert has its own switch, a test button, and a sound that is either Windows speech or the player's own WAV or MP3 file. A custom file that is missing or will not play falls back to speech, and the problem shows under that alert's row.
- Alerts play one after another and never overlap. An alert that has waited more than 15 s is dropped.
- When Blackgrid starts and reads the logs again, only fresh events trigger alerts. Timer alerts fire only when the timer reaches zero while Blackgrid is open.
- A new **Alerts** section on the Settings page, between Raid timers and Map.
- The raid lifecycle publishes four more transitions once each: queue entered, map known, match found and raid starting.
- Alert settings are stored with the other settings and survive a restart.

## Capabilities

### New Capabilities
- `audio-alerts`: the alerts, when each one fires, how it plays (speech or a custom file, in a queue), the voice setting, and the Alerts settings with their storage.

### Modified Capabilities
- `raid-lifecycle`: adds the queue-entered, map-known, match-found and raid-starting transitions, each published once with its record identity.
- `settings-page`: adds the Alerts section to the list and order of sections.

## Impact

- **Dart:**
  - `lib/domain/`: new alert trigger rules and alert settings; new transition variants in `raid_lifecycle.dart`.
  - `lib/application/`: a new alerts controller and an audio port.
  - `lib/data/`: an audio adapter over the runner channel.
  - `lib/ui/`: the Settings Alerts section.
  - `app_services.dart`: wiring.
  - Existing exhaustive switches over `RaidTransition`, for example `raid_timers_controller.dart`, gain the new variants.
- **Native:** a new `blackgrid/audio` method channel in the Windows runner (`windows/runner/`). It uses `Windows.Media.SpeechSynthesis` and `Windows.Media.Playback`, which are OS components, so nothing is redistributed. No new DLL is added and the release bundle inventory is unchanged.
- **Stored data:** a new `alerts` block in the local settings record. A record without it loads the defaults.
- **No game interaction.** Alerts play through Blackgrid's own audio output, and nothing is drawn on or sent to the game.
- **Dependencies:** none added.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Default sound

- **Choice:** Windows speech generated at runtime. No audio is bundled.
- **Rejected:** Generated tones, owner recordings and a CC0 library. They need bundled assets and the licences that come with them, and tones are hard to tell apart.
- **Reversal cost:** medium
- **Important:** yes, it changes what users hear.
- **Chosen by:** user

### S2: Voice choice

- **Choice:** One voice setting for all alerts: a list of the installed voices with "Windows default" first, a preview button, speed and volume sliders, and a "Get more voices" link. A missing voice falls back to the default.
- **Rejected:** A voice for each alert. It crowds the screen, which would need eight pickers.
- **Reversal cost:** low
- **Important:** yes, it changes settings users see.
- **Chosen by:** user

### S3: Recorded sound packs left for later

- **Choice:** Each alert's sound is stored as a typed source, either speech or a custom file, so a bundled recorded pack can be added later as one more source. Recorded packs are out of scope for now.
- **Rejected:** Storing an on/off flag plus a file path. A later pack would then need a settings migration.
- **Reversal cost:** medium, because it is the stored data format.
- **Important:** yes, it binds future changes through the data format.
- **Chosen by:** user

### S4: Air filter alerts are reminders

- **Choice:** "Air filter on" plays when the player enters the queue and "Air filter off" plays when the raid ends, only when local progress for the mode records the Air Filtering Unit as built. Blackgrid does not see the switch in the hideout. Detecting when the player toggles the unit is later work.
- **Rejected:** Detecting the switch now, which Blackgrid has no input for. A reminder only after the raid ends.
- **Reversal cost:** low
- **Important:** yes, it changes what users hear.
- **Chosen by:** user. The owner said "until then, we can have a reminder - just like the quest items". The condition that the unit is built is the agent's reading of "just like the quest items", where the reminder fires only when it is relevant.

### S5: Quest-items reminder trigger

- **Choice:** It fires once per queue, when the log names the map, if a started task has an unfinished plant, mark or quest-item hand-over objective on that map. It never checks the inventory.
- **Rejected:** Firing on every queue. Firing at match found, which is too late to back out.
- **Reversal cost:** low
- **Important:** yes, it changes what users hear.
- **Chosen by:** user

### S6: Restart-failed-tasks trigger

- **Choice:** It fires once when the player is back in the menus after a task failed that the quest data marks restartable. It never fires mid-raid.
- **Rejected:** Firing at once, even mid-raid. Including tasks that cannot be restarted.
- **Reversal cost:** low
- **Important:** yes, it changes what users hear.
- **Chosen by:** user

### S7: Alerts on by default

- **Choice:** Match found, raid starting, run-through over and scav ready are on. Air filter, quest items and failed tasks are off.
- **Rejected:** All on. All off.
- **Reversal cost:** low
- **Important:** yes, it changes settings users see.
- **Chosen by:** user

## Release Notes

Blackgrid can now speak alerts for match found, raid starting, run-through over and scav ready, with optional reminders for the air filter, quest items and restartable failed tasks. Each alert has its own switch, a test button and a choice of Windows voice or your own sound file.

### Added
- Spoken alerts for match found, raid starting, run-through over and scav ready, on by default, each with a switch and a test button in the new Alerts section of Settings.
- Optional reminders: air filter on and off, check your quest items when the map you queue for has item objectives, and restart failed tasks when you are back in the menus.
- Voice settings: pick any installed Windows voice, preview it, set speed and volume, or play your own WAV or MP3 file for any alert.
