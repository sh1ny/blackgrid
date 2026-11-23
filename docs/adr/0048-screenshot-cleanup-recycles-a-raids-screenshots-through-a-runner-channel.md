# 0048 - Screenshot cleanup recycles a raid's screenshots through a runner channel

- Status: accepted
- Date: 2026-11-22 (change `add-screenshot-cleanup`)
- Source: `add-screenshot-cleanup` design D1, D2, D5 and D8

## Context and problem

The player can opt in to cleaning up screenshots from a finished raid. These are user files, so cleanup must select only that raid's game screenshots and must never permanently delete them. The game log input remains read-only under ADR-0030; this decision does not supersede it. ADR-0007 reserves runner channels for light Windows services and standalone FFI DLLs for heavy native work; ADR-0047 establishes the asynchronous runner-channel and platform-thread completion pattern.

## Decision

- **Dart selects; the runner rechecks (D1).** A lister uses asynchronous directory IO with `followLinks: false`; a pure Dart picker uses the existing `parseScreenshotFilename` to select only direct regular non-link files with game screenshot names and `.png`, `.jpg` or `.jpeg` extensions. Their modified times must lie in the inclusive local wall-clock interval from raid start to raid end. The folder is captured when cleanup starts. The runner receives the folder and selected names, rejects names containing path separators or `..`, and checks file attributes to reject directories and reparse points before recycling each file.
- **Recycle Bin only (D2).** For each file, a dedicated STA worker performs one `IFileOperation` with `FOFX_RECYCLEONDELETE | FOF_ALLOWUNDO | FOF_NO_UI`. Its progress sink vetoes `PreDeleteItem` with `E_ABORT` unless `TSF_DELETE_RECYCLE_IF_POSSIBLE` is set; the file stays and is reported `notRecyclable`. A veto or failure for one file does not stop the others. This is a light per-file shell OS call on a worker, not the heavy computation that ADR-0007 puts in an FFI DLL.
- **Channel lifetime and cancellation (D2).** `blackgrid/recycle` exposes `recycle` and `cancel`, with at most one recycle call pending. The channel and worker share an `HWND`, call generation and atomic stop flag in shared state that never refers back to the channel. Each new call resets stop; `cancel` sets it, and the worker checks it before each file, reporting skipped files as `cancelled`. On destruction the channel sets stop, completes the pending result as `cancelled`, and detaches the worker; it can finish at most its current file. The worker posts completion to the platform thread, and a stale-generation post is ignored; a post to a destroyed window fails harmlessly. The recycle window message is distinct from the audio channel's.
- **One screenshot write path (D5).** The cleanup controller's runner channel is Blackgrid's sole write path into the screenshot folder, and it only moves selected files to the Recycle Bin. An offline audit bans `delete`, `rename`, `openWrite`, `writeAs*`, `Process.*` and `dart:ffi` in the screenshot watcher and cleanup Dart sources. Game log sources remain read-only under ADR-0030.
- **Fresh endings only (D8).** While the setting is enabled, normal raid endings use the existing alerts freshness rule: their log time is at most 30 seconds old. A `clientRestart` ending is held for the immediately following transition; only a `QueueEnteredTransition` admits it, and its queue timestamp is used for freshness. Any other next transition drops the held ending. The raid's end time remains the profile-selection time for file selection. A replayed ending no more than 30 seconds before startup can still be fresh; this edge is accepted.

## Rejected alternatives

- **Select files in the runner.** It would duplicate the game filename and time rules in C++ instead of using the existing Dart parser and a testable pure picker.
- **Check the drive then use a batch delete operation.** A drive-level Recycle Bin check does not guarantee that each particular file can be recycled; Windows may permanently delete an ineligible file. A per-file veto protects it without stopping the rest.
- **Judge crash endings by arrival time or their own end time.** Arrival time admits startup replay; the profile-selection time can be stale by the next live queue entry.
- **A standalone FFI DLL or a plugin.** Shell operations are light OS services; either choice adds machinery to the runner-channel pattern of ADR-0007 and ADR-0047.

## Consequences

The opt-in cleanup is the narrow exception to read-only screenshot access; logs remain read-only. The Recycle Bin provides the player's undo, and files that cannot be confirmed recyclable remain in place. The app-scoped controller keeps a bounded, memory-only set of cleaned raid identities, so a restart near an ending can still admit a fresh replay. The no-permanent-delete guarantee depends on the Windows shell's `PreDeleteItem` flag semantics; qualification and owner checks of real Recycle Bin behavior remain necessary. Reversal cost is medium for the channel contract and high for changing the selected raid interval, because both determine which user files move.
