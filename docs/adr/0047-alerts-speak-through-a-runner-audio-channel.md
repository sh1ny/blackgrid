# 0047 - Alerts speak through a runner audio channel

- Status: accepted
- Date: 2026-11-21 (change `add-audio-alerts`)
- Source: reviewed `add-audio-alerts` design D1, D4, D5 and D11, and review S2 and S3

## Context and problem

Blackgrid is adding spoken and recorded alerts for raid events (match found, raid starting, run-through over, scav ready, and reminders). That needs a way to turn text into speech, play a sound file, list voices and let the player pick a file, all from a Flutter Windows app that uses no plugins (ADR-0007, ADR-0046). The work is light and asynchronous. Alerts must not ship audio assets, and the stored settings must not box in a later recorded voice pack.

## Decision

- **Runner channel (D1).** The runner registers a second method channel, `blackgrid/audio`, in `windows/runner/` beside `local_data_channel.cpp`. Methods:
  - `voices` returns the id and display name of each `Windows.Media.SpeechSynthesis` voice.
  - `speak` takes text, a voice id or null, a speed step and a volume, synthesises to a stream and plays it through `Windows.Media.Playback.MediaPlayer`.
  - `playFile` takes an absolute path and a volume.
  - `stop` stops what is playing.
  - `openVoiceSettings` launches `ms-settings:speech`.
  - `pickSoundFile` opens the Windows Open dialog (`IFileOpenDialog`), owned by Blackgrid's window and filtered to `.wav` and `.mp3`. It returns the absolute path, or null when the player cancels.
  Dart reaches the channel only through an `AudioPort` interface in `lib/application/`, with a `ChannelAudioPort` in `lib/data/`. The runner links `windowsapp.lib`.
- **Threading contract.** WinRT async work and `MediaPlayer` events are marshalled back to the platform thread before any `MethodResult` completes, through a private window message handled by `FlutterWindow::MessageHandler`. Nothing calls a blocking `.get()` on the UI thread.
- **Completion contract.** At most one playback result is pending. It completes exactly once: when playback ends (success), when it fails, when `stop` is called, when the window is destroyed, or when the runner's file timeout expires. A `speak` or `playFile` call that arrives while a result is pending fails at once. The Dart queue never sends one. Every failure is a typed error code, and these are all of them:

  | Code | Meaning |
  |---|---|
  | `voice_missing` | The requested voice id is not installed. |
  | `file_missing` | The sound file does not exist or cannot be opened. |
  | `file_unplayable` | The file exists but Windows cannot play it. |
  | `speech_failed` | Synthesis or playback of speech failed. |
  | `stopped` | `stop` was called, or the window was destroyed, while the call was pending. |
  | `timeout` | The runner's file timeout expired and it stopped the playback. |
  | `busy` | Another playback result was already pending. |

- **File timeout.** Once `MediaPlayer` opens a file, the runner arms a timer for `NaturalDuration` plus 5 s, capped at 120 s, or 30 s when the length is unknown. On expiry it stops playback and completes with `timeout`. The length never crosses the channel. Dart keeps one backstop of 125 s for any `playFile` call and 30 s for any `speak` call. When a backstop expires, Dart calls `stop` and treats the item as failed.
- **Typed sound source (D4).** Each alert's setting is stored as `{on: bool, sound: {kind: "speech"}}` or `{on: bool, sound: {kind: "file", path: "<abs path>"}}`, under `alerts.items.<alertId>`. The voice (an id, or null for the Windows default), speed and volume are stored beside them as `alerts.voice`, `alerts.speed` and `alerts.volume`. In Dart the sound is a sealed `AlertSound` with `SpeechSound` and `FileSound`. Alert ids are stable strings: `matchFound`, `raidStarting`, `runThroughOver`, `scavReady`, `airFilterOn`, `airFilterOff`, `questItems` and `failedTasks`.
- **OS components only, no bundled audio (D11).** Speech and playback use Windows components (`Windows.Media.SpeechSynthesis`, `Windows.Media.Playback`, `IFileOpenDialog`, linked through `windowsapp.lib`). Blackgrid ships no audio file, no voice and no codec. The default sound is runtime speech. Custom files are the player's own `.wav` or `.mp3` and are streamed from disk by the runner, never loaded into Dart.
- **Extension point for recorded packs.** A later recorded pack is a new `kind` (for example `pack`) added to the sound source. An unknown `kind` loads as speech, so older settings and newer builds stay readable and no migration is needed.

## Rejected alternatives

- **A standalone FFI DLL** like `blackgrid_panel_ocr.dll`. It adds a hash-bound file to every release and to the bundle inventory. Completion would need `NativeCallable` callbacks across FFI, which is more machinery for light, async work.
- **Folding this into ADR-0007.** It is accepted and immutable, and the channel it names has since been renamed (ADR-0046).
- **An on/off flag and a nullable path** as the stored format. A recorded pack would need a migration.
- **Bundled recordings or tones** as the default. They add assets and a licence question for a fixed, unlocalised voice.

## Consequences

The runner gains a second channel and a window message, and the Windows build links `windowsapp.lib`. ADR-0007's boundary (runner channel for light work, standalone DLL for heavy work, no plugins) still holds; this record only adds the channel. Audio behaviour is testable offline through hand-written `AudioPort` fakes. Speech quality and the installed voice list depend on the player's Windows install, and the default voice always works. The stored `alerts` block is a data format: changing it later costs a migration, which the typed source keeps small. Reversal cost of the channel is low, because it sits behind `AudioPort`.
