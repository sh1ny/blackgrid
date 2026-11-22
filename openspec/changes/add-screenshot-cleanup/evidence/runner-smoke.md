# Runner recycle smoke — 2026-11-22

## Safety and setup

- After the owner closed the game, process-name checks found no `EscapeFromTarkov`, `EscapeFromTarkov_BE` or `BEService`. No game was launched, inspected, captured or controlled.
- Ran an isolated Debug Blackgrid harness with the real `AppServices`, `ScreenshotFolderLister`, `ChannelRecyclePort`, native runner and Settings page. Settings used an in-memory database and temporary log/screenshot folders on C:, not the owner's settings or game files. HTTP was answered offline.
- Enabled **Delete a raid's screenshots after it ends** through the actual Settings control using Flutter Driver. Appended synthetic queue, raid-start and backend raid-exit records to the watched fixture logs.
- Fixture root: `%TEMP%/blackgrid-cleanup-smoke-d2bb4840`. The screenshot path deliberately mixed Windows and forward separators.
- Synthetic raid interval: `2026-11-22T17:53:00.585+02:00` through `2026-11-22T17:53:04.585+02:00`. Matching files were modified at `17:53:02.585`.

## Observed files

The filename prefix below is `2026-11-22[14-05]_-120.5, 2.1, 33.4_0, 0.70711, 0, 0.70711`.

| File | Observed outcome |
|---|---|
| `<prefix>_12.34.png` | Real runner returned `moved`; absent from the folder; Windows Shell Recycle Bin enumeration found its original name and original screenshot folder. |
| `<prefix>_12.35.JPG` | Real runner returned `moved`; absent from the folder; Windows Shell Recycle Bin enumeration found its original name and original screenshot folder. |
| `<prefix>_10.png`, modified two seconds before the raid | Still in the screenshot folder. |
| `<prefix>_11.png`, modified two seconds after the raid | Still in the screenshot folder. |
| `<prefix>_13.bmp` | Still in the screenshot folder. |
| `2026-11-22[14-05]_renamed.png` | Still in the screenshot folder. |
| `notes.png` | Still in the screenshot folder. |
| `subfolder/<prefix>_14.png` | Still in its subfolder. |

The rendered Settings result was exactly:

> Moved 2 screenshots from the last raid to the Recycle Bin.

A Blackgrid-only window capture confirmed that the switch follows the screenshot folder, the result is visible below it, and Follow logs remains below. Runtime-error retrieval after the successful smoke returned **No runtime errors found**. A hot reload and hot restart also succeeded during verification.

## Defects found and resolved

- The startup replay regression initially failed because `MapSessionController` published the screenshot directory after binding and replaying logs. The approved fix publishes the resolved directory first while retaining the watcher binding after log binding. The regression and full offline suite passed afterward.
- The first native smoke returned two `failed` statuses and preserved all files. A read-only `SHCreateItemFromParsingName` probe returned `0x80070057` for a mixed-separator existing path and `0x00000000` for the same path normalized to backslashes. The runner now normalizes the folder once before Shell parsing. The successful smoke above exercised this fix.

## Limits

No live-game test was performed. The owner-only real-raid and optional no-Recycle-Bin-drive checks remain unverified under task 6.2. This smoke proves recycling on the system drive; the no-permanent-delete veto remains enforced in the runner and its alternative-drive behavior is not claimed verified here.
