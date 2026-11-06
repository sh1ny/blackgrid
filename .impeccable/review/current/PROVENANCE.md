# Before-redesign screenshots: provenance

The record of how Blackgrid looked before the Ember redesign. Captured on **2026-11-06** by Claude (agent), from a Release build of commit `2343fb2` (the `main` commit the `docs/document-ember-design-context` branch started from), built in this worktree with `mise exec -- flutter build windows --release`.

## How they were taken

- **Game check:** before the launch, no Escape from Tarkov, launcher or BattlEye process was running (`Get-Process`), as AGENTS.md requires.
- **Data:** the app ran against the owner's real local profile (`%LOCALAPPDATA%\Blackgrid`). The app resolves that folder through the Windows known-folder API, so it cannot be redirected without a registry change. Every interaction was read-only:
  - dialogs and sheets were opened and closed without saving;
  - history entries were opened, which reads only;
  - no item was picked by hand, because that writes a history row (`lib/application/selection_controller.dart:144`);
  - no pin, setting or token was changed.
  Live scan was on from the saved settings. With the game closed it captured nothing.
- **Capture:** Win32 `PrintWindow` with `PW_RENDERFULLCONTENT` on the Blackgrid window handle. That is the window only, including the Windows title bar, with nothing else from the desktop. Clicks and scrolls were sent through Orca computer use (Windows UI Automation).
- **Display:** primary display 3440×1440 at 96 DPI (100% scale). Window sizes below are physical pixels, equal to logical pixels at this scale. Text scale was the Windows default.
- **Theme:** Blackgrid has only a dark theme (`lib/ui/theme.dart`), so no light-theme captures exist.
- **Redaction:** `08-map-rail-saved-file-inputs.png` has two local folder paths blacked out (the game log folder and the owner's screenshot folder). No other image was edited.

## Files

| File | Area | Screen and state | Window |
|---|---|---|---|
| `01-map-default.png` | Map | Streets, ground floor, boss markers shown, no item picked ("Find an item" empty card in the rail), raid timer strip visible | 1672×941 |
| `02-map-marker-bubble.png` | Map | A Kollontay boss marker selected: anchored bubble with spawn chance. Shows the float-formatting bug "56.999999999999999%" | 1672×941 |
| `03-map-help-dialog.png` | Map | "Map help" dialog over a scrim | 1672×941 |
| `04-map-markers-browse.png` | Map | "Markers (19)" bottom sheet: visible markers list | 1672×941 |
| `05-map-pins-empty.png` | Map | "0 saved pins" bottom sheet, empty state "No saved pins for this map" | 1672×941 |
| `06-map-rail-marker-tiles.png` | Map | Rail scrolled: marker preference tiles (Bosses shown, others hidden) and the start of Manual item search | 1672×941 |
| `07-map-rail-manual-search.png` | Map | Rail scrolled further: Manual item search panel, collapsed "Map saved-file inputs" | 1672×941 |
| `08-map-rail-saved-file-inputs.png` | Map | "Map saved-file inputs" expanded: detected map, mode, log and screenshot watch state, Follow logs off, Read Latest. **Two paths redacted.** | 1672×941 |
| `09-scanner-default.png` | Scanner | No item: live scan ready (on), manual inspection, "Find an item" empty card, empty requirements, data sources, "No scan published yet", recent item activity | 1672×941 |
| `10-scanner-history-item.png` | Scanner | History inspection of Emergency Water Ration: verdict **Check / May Need**, Flea and trader prices, "Still needed", requirement rows, selected history tile | 1672×941 |
| `11-scanner-history-item-warnings.png` | Scanner | History inspection of Salewa first aid kit: Check / May Need. The warning line ("Flea price time unknown or more than an hour old") exists in the widget tree but is **clipped** by the card's fixed height, and so is the bottom of the "Still needed" tile | 1672×941 |
| `12-settings-dialog.png` | Dialog | Settings, top: game mode, item data refresh, map files, Follow logs, raid timers | 1672×941 |
| `13-settings-dialog-tracker.png` | Dialog | Settings scrolled: raid timer options, Tracker progress (token saved; the token itself is never shown) | 1672×941 |
| `14-stats-dialog.png` | Dialog | Seasonal stats with counted raids and Flea sales | 1672×941 |
| `15-import-dialog.png` | Dialog | Import saved settings and history, before any file is chosen ("Import now" disabled) | 1672×941 |
| `16-scanner-narrow-960.png` | Scanner | Narrow window (below the 1100 px breakpoint): panels stack; the live-scan settings panel comes first and pushes the decision below the fold; the header clips its buttons | 960×941 |
| `17-map-narrow-960.png` | Map | Narrow window: floor buttons wrap, the rail moves below the map | 960×941 |

## States not captured

These exist in code (see `DESIGN.before.md`) but could not be reached read-only with the owner's profile and the game closed:

- the bootstrap screen (loading, "newer version" and "storage could not be opened" errors);
- item data loading, unavailable or failed, and "Choose a game mode" (the profile has data for Seasonal);
- the verdicts **Keep**, **Keep for later**, **Flea**, **Trader** and **Price unavailable** (every history item showed Check / May Need because prices were more than an hour old; picking other items would write history);
- a live scan in progress, a recognised or failed scan, scan evidence and correction offers (these need the game);
- the player position marker and highlighted extracts (these need an in-game screenshot);
- the pin editor and a selected pin (adding a pin writes data);
- an import preview or import errors (these need files chosen and read);
- the compact marker bubble and the Settings validation errors;
- a light theme (none exists).
