# Proposal

## Why

Blackgrid reads the player's position from the screenshots they take in raid, so players who use the Map take many of them, and the game's screenshot folder keeps every one. Over a few evenings that comes to hundreds of files the player never wanted to keep. This is the third change of milestone **M10 - alerts and window behaviour**. It serves M10's second exit criterion: screenshot cleanup is off by default, and when switched on it deletes only that raid's screenshots, only after the raid ends, and never touches other files, proved by offline tests on a temp folder.

It also serves part of M10's user-verified criterion: screenshot cleanup removes a real raid's screenshots. Agents never test against the game (AGENTS.md), so this change carries a `[user]` task in tasks.md for the owner's check after a real raid. It is recorded as unverified until the owner reports it, and is judged again at the M10 close.

## What Changes

- A new setting, **Delete a raid's screenshots after it ends**, off by default. It sits under the screenshot folder in Settings > Game files.
- When it is on and a raid ends while Blackgrid is running, Blackgrid sends that raid's screenshots to the Windows Recycle Bin. A file counts as one of that raid's screenshots only when all of these hold:
  - it sits directly in the screenshot folder Blackgrid watches, not in a subfolder;
  - it is a `.png`, `.jpg` or `.jpeg` file whose name parses as a game screenshot name;
  - its modified time falls between the raid's start and its end.
- Only a fresh raid ending starts a cleanup. Raids that ended while Blackgrid was closed, or that the log replay shows again at start-up, are left alone. A raid is cleaned up at most once.
- One line under the switch shows the last cleanup: how many screenshots it moved to the Recycle Bin, or why it could not, for example a missing folder or files that could not be moved. Nothing is shown before the first cleanup.
- The setting is stored with the other settings and survives a restart.
- Cleanup never deletes permanently, never follows links and never touches a file outside the rules above.

## Capabilities

### New Capabilities
- `screenshot-cleanup`: which raid endings start a cleanup, which files count as that raid's screenshots, how they are removed, the result the player sees, and the setting and its storage.

### Modified Capabilities
- `settings-page`: the Game files section gains the cleanup switch and its last-result line.

## Impact

- **Dart:**
  - `lib/domain/`: the rule that picks a raid's screenshots, and the new setting in `settings.dart`.
  - `lib/application/`: a cleanup controller that listens to raid-ended transitions and uses the same freshness rule as the alerts.
  - `lib/data/`: a recycle port over a runner channel.
  - `lib/ui/settings/`: the switch and result line in Game files.
  - `app_services.dart`: wiring.
- **Native:** a new method channel in the Windows runner (`windows/runner/`) that moves the given files to the Recycle Bin through the Windows shell. It uses an OS component, so no DLL is added and the release bundle inventory is unchanged.
- **Stored data:** a new screenshot cleanup flag in the local settings record. A record without it loads as off.
- **No game interaction.** Blackgrid only reads the logs and moves files in the screenshot folder. It never touches the game process, and it never draws on the game or sends anything to it.
- **Dependencies:** none added.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Which files are a raid's screenshots

- **Choice:** `.png`, `.jpg` or `.jpeg` files directly in the watched screenshot folder, whose name parses as a game screenshot, with a modified time between the raid's start and end.
- **Rejected:** Any image file in the raid window, which could delete a file the player put there. A window that opens at the queue, which takes in loading screenshots and makes the rule harder to reason about.
- **Reversal cost:** high, because a wrong rule removes the player's files.
- **Important:** yes, it changes what happens to the player's files.
- **Chosen by:** user

### S2: Which raid endings start a cleanup

- **Choice:** Only fresh raid endings, under the alerts' freshness rule, while cleanup is on. Replayed endings and raids that ended before cleanup was switched on are left alone. A raid ended by a game crash is published only at the next queue entry, so its freshness is judged by that queue entry. The owner chose to clean crashed raids in design review round 1 (M1).
- **Rejected:** Cleaning every ending the replay shows, which can remove screenshots from earlier raids that the player kept.
- **Reversal cost:** high, because a wrong rule removes the player's files.
- **Important:** yes, it changes what happens to the player's files.
- **Chosen by:** user

### S3: How files are removed

- **Choice:** Moved to the Windows Recycle Bin through a new runner channel, so a mistake can be undone.
- **Rejected:** A permanent delete from Dart. It is simpler, but a mistake cannot be undone.
- **Reversal cost:** medium, because it adds a native channel.
- **Important:** yes, it changes what happens to the player's files and adds a native boundary.
- **Chosen by:** user

### S4: Where the setting lives and what it shows

- **Choice:** A switch under the screenshot folder in Settings > Game files, off by default, with a line under it that shows the last cleanup's result.
- **Rejected:** A switch with no result line, which hides failures. A switch on the Map's inputs section, which is kept free of extra controls.
- **Reversal cost:** low
- **Important:** yes, it changes settings users see.
- **Chosen by:** user

## Release Notes

Blackgrid can now tidy the game's screenshot folder. Switch on "Delete a raid's screenshots after it ends" in Settings > Game files, and after each raid the screenshots taken during it go to the Recycle Bin. It is off by default and never touches other files.

### Added
- Opt-in screenshot cleanup: after a raid ends, the game screenshots taken during it move to the Windows Recycle Bin. Settings > Game files has the switch, shows the last result, and reports when the setting could not be saved.
- Cleanup ignores stale raid endings and duplicate endings, leaves unrelated files alone, and reports files it could not move or confirm as moved. Files that cannot be recycled stay in place; cleanup never deletes them permanently.
