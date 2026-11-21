# Runner audio channel smoke check (task 4.4)

- **When:** 2026-11-21 03:39 local (UTC+2), by the agent, offline.
- **Game check:** right before launch, the process list showed no `EscapeFromTarkov*` process (`EscapeFromTarkov not running at 2026-11-21T03:39:19`). The BSG launcher was open; the game was not.
- **Machine:** the owner's Windows 11 Pro development machine.

## How it ran, and how it differs from the task text

The task says to launch Blackgrid and press each alert's test button and the voice preview. The owner's own Blackgrid instance was running from `build\windows\x64\runner\Release` at the time. Blackgrid has no single-instance guard, and its data folder comes from `FOLDERID_LocalAppData` with no override. A second full instance would have shared the owner's live database and log state, so the agent did not launch one.

Instead, the agent built the branch's runner (`windows/runner/audio_channel.cpp` and the rest of the change at that point) in a temporary worktree, with a throwaway Dart entry point (`lib/audio_smoke_main.dart`, never committed). The entry point drives the real `ChannelAudioPort` over the real `blackgrid/audio` channel, writes each call's result to a JSON file and exits. So this checks the same channel calls that the test buttons and the preview make (`speak` with each alert's line, at volume 15 so the check stayed quiet at night), but not the Settings widgets. The widgets are covered by `test/ui/settings_page_alerts_test.dart` with the fake port.

Command: `flutter build windows --release -t lib/audio_smoke_main.dart` in the temporary worktree, then the built `blackgrid.exe <out.json>`. The process exited with code 0.

## Voices listed

`voices` returned three OneCore voices in 177 ms:

| Name | Language | Id |
|---|---|---|
| Microsoft David | en-US | `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\MSTTS_V110_enUS_DavidM` |
| Microsoft Zira | en-US | `...\MSTTS_V110_enUS_ZiraM` |
| Microsoft Mark | en-US | `...\MSTTS_V110_enUS_MarkM` |

## Call results

| Call | Result | Time to complete |
|---|---|---|
| speak "Match found" (default voice, speed 0) | ok | 1935 ms |
| speak "Raid starting" | ok | 1989 ms |
| speak "Run-through over" | ok | 2068 ms |
| speak "Scav ready" | ok | 1942 ms |
| speak "Air filter on" | ok | 2140 ms |
| speak "Air filter off" | ok | 2141 ms |
| speak "Check your quest items" | ok | 2536 ms |
| speak "Restart failed tasks" | ok | 2876 ms |
| speak the voice preview line | ok | 2273 ms |
| speak "Scav ready" with Microsoft Mark, speed 5 | ok | 868 ms |
| speak "Scav ready" with Microsoft Mark, speed −5 | ok | 3394 ms |
| speak with an unknown voice id | `voice_missing` | 35 ms |
| playFile `C:\Windows\Media\chimes.wav` | ok | 1568 ms |
| playFile a path that does not exist | `file_missing` | 0 ms |
| playFile a text file named `.mp3` | `file_unplayable` | 431 ms |
| a second speak while one is pending | `busy` | 30 ms |
| stop while speaking | returned | 0 ms |
| the pending speak after that stop | `stopped` | 0 ms |
| stop while idle | returned | 0 ms |

The completion times match the length of each line, so `speak` and `playFile` complete when playback ends, not when it starts. The speed steps change the speaking rate as intended.

## Not exercised here (unverified)

- `pickSoundFile`: it opens a modal Windows dialog that needs a person to choose or cancel.
- `openVoiceSettings`: it opens the Windows Settings app in the owner's session; it was left for the owner.
- The runner's file `timeout`: it needs a file over 120 s long, or one whose playback stalls.
- Completion with `stopped` when the window is destroyed mid-playback.
- How loud the alerts are next to game audio. That is the owner's in-play check (task 6.3).

The fake-port tests cover the Dart handling of each of these codes.

## Re-run after the pre-ship fixes

- **When:** 2026-11-21 03:55 local, by the agent, offline, with the same harness. `EscapeFromTarkov not running at 2026-11-21T03:55:52` right before launch.
- **What changed:** speech volume is now applied once, by the player, and a late synthesis result can no longer replace a newer one (pre-ship round 1).
- **Result:** exit code 0. Every call returned the same result as the first run: all speak calls `ok` (Mark at speed 5 in 902 ms, at speed −5 in 3432 ms), `voice_missing`, `file_missing`, `file_unplayable`, `busy` and `stopped` as before, and `chimes.wav` `ok` in 1553 ms.
