# Blackgrid

![version](https://img.shields.io/badge/version-0.5.0-blue) ![Flutter](https://img.shields.io/badge/Flutter-3.47.6-02569B) ![platform](https://img.shields.io/badge/platform-Windows%20x64-555)

**A helper app for Escape from Tarkov that runs next to the game on Windows.** It shows you where you are on the map, which extracts you have this raid, and whether the item in your hands is worth keeping or selling.

| Map | Scanner |
|---|---|
| ![Map area: Reserve with extracts, transits, locks and loot markers, and floor buttons](docs/screenshots/map.png) | ![Scanner area: advice for a Graphics card, with prices, the quests that need it, and recent items](docs/screenshots/scanner.png) |

## 🎯 What Blackgrid does for you

Blackgrid has two areas. You switch between them at the top of the window.

**🗺️ Map.** Interactive maps of all 13 locations (Factory, Customs, Woods, Shoreline, Interchange, The Lab, Reserve, Lighthouse, Streets, Ground Zero, Terminal, Icebreaker and Labyrinth). Turn on the markers you care about: PMC, Scav and shared extracts, transits, quest items and objectives, bosses, cultists, spawns, hazards, loot containers, locks, switches, BTR stops and stationary weapons. Right-click to drop your own pins; they are saved per map.

**🔍 Scanner.** Search any item with **Ctrl K** and Blackgrid tells you, in plain words, what to do with it: **Keep** (a quest or hideout upgrade needs it now), **Keep for later** (needed further down the line), **Flea** (sell it on the Flea Market) or **Trader** (sell it to the trader who pays most), with the price. When it is not sure, because prices are old, you have not said whether the item is found in raid, or it does not know your progress, it says **Check / May Need** instead of guessing. A wrong "sell" costs you an item; a "check" costs you a second look.

### 📍 How it knows where you are

Blackgrid never asks the game where you are. It uses two things the game already writes to your disk:

1. **The game's log files.** When you load into a raid, Escape from Tarkov writes the map name and the game mode (PvP or PvE) to its log. Blackgrid reads that log and opens the right map by itself. Turn this off with **Follow logs** if you prefer to pick the map by hand.
2. **Your screenshots.** When you take a screenshot in game (**Print Screen** by default), the game names the file after your position and the direction you are facing. Blackgrid watches your screenshot folder and puts a marker on the map where you stood and the way you faced.

Your position updates **only when you take a screenshot**. It is a snapshot, not live tracking.

**Which extracts do I have?** In raid, press **O** to open the list of your extracts and transits, then take a screenshot. Blackgrid reads the names from that picture with the text recognition built into Windows and highlights exactly those extracts on the map.

### 🧪 Item scanning is optional

You do not need the scanner to use the map, and you do not need the map to use the scanner. Searching items by name works without any scanning.

**Live scan** is off until you switch it on in the Scanner area. When it is on, and you inspect an item in game, Blackgrid takes a small picture of the screen around your mouse, reads the item's name and shows the advice. A scan starts when you release the mouse button over the game window, or when you press the scan key (**F9** by default; pick any of F1 to F24, or none). Switch live scan off and Blackgrid stops listening for clicks and gives the key back.

### 🛡️ Blackgrid does not touch the game

Blackgrid **never** connects to the game, reads or changes its memory, injects anything into it, or sends it key presses or clicks. It only reads:

- the **log files** the game writes to disk;
- the **screenshots** you take;
- with live scan on, a **small picture of your screen**, the way a screen-capture tool takes one. To know that your click landed on the game, it checks the title of the window under your mouse, which Windows shares with any program.

That is all. It does not modify any game file. A test in this repository fails if the capture code ever calls a Windows function that could open or control another program.

> **Note:** Blackgrid is a fan-made tool, not affiliated with Battlestate Games. Only Battlestate Games decides what its anti-cheat allows. Blackgrid is built to stay well away from the game, but no third-party tool can promise how anti-cheat will treat it.

### 🔗 What it connects to

| Service | What Blackgrid gets from it | Needed? |
|---|---|---|
| [tarkov.dev](https://tarkov.dev) | Items, prices, traders, quests, hideout, crafts and barters, refreshed at start and when you change game mode | Yes, for item advice |
| [TarkovTracker](https://tarkovtracker.org) | Your quest and hideout progress, read only, so **Keep** means *you* still need it | No. Off until you paste a token in **Settings** |
| Windows text recognition | Reads the extract names from your **O** screenshots, on your PC | Built into Windows |

Blackgrid only downloads; it never uploads your data. There is no Blackgrid account, server or telemetry. Your settings, pins and history stay on your PC in `%LOCALAPPDATA%\Blackgrid\`, and a TarkovTracker token is encrypted for your Windows user. The maps ship inside the app; see [Data sources and credits](#-data-sources-and-credits) for where they come from.

---

## 🛠️ For developers

The rest of this page is for building and working on Blackgrid. It is a Dart/Flutter desktop app. Maps render natively from a bundled, hash-addressed pack, and one conservative decision engine drives every recommendation: an unknown or stale input gives **Check / May Need**, never a confident Sell.

## ✨ What it adds

- 🛡️ **Conservative keep/sell advice.** One pure-Dart [`DecisionEngine`](lib/domain/decision_engine.dart) ranks **Keep → Keep for later → Check / May Need → Flea → Trader → Price unavailable**. Missing catalog or progress authority, unknown FIR, an unresolved requirement or a quote older than one hour all fall to Check.
- 🗺️ **Native map, no WebView.** All 13 maps render from a prepared pack in [`assets/maps/`](assets/maps/active.json). SVG is compiled to `vector_graphics` at preparation time, and the [scene](lib/maps/native_map_scene.dart) keeps decoded tiles and pictures in a 192 MiB LRU.
- 📍 **Session evidence from files only.** [`SessionLogReader`](lib/data/session_log_reader.dart) polls the newest game log every 250 ms for map and mode. [Screenshot filenames](lib/domain/screenshot_filename.dart) give position and heading. Saved exit panels are read with Windows `Windows.Media.Ocr` through a hash-bound DLL ([`panel_ocr.cpp`](windows/ocr/panel_ocr.cpp)).
- 🔐 **Read-only progress with protected tokens.** [`TrackerClient`](lib/data/tracker_client.dart) only sends GET requests to `api.tarkovtracker.org`, with a 30 s timeout. Tokens are mode-scoped (`PVP_`, `PVE_`, `SZN_`) and stored as current-user DPAPI ciphertext by the [Windows runner](windows/runner/credential_protector.cpp), never in SQLite.
- 💾 **One local store.** A single Drift SQLite file ([`database.dart`](lib/data/database.dart)) holds settings, pins, item history and one catalog snapshot per mode. The schema is versioned in [`drift_schemas/`](drift_schemas/drift_schema_v2.json), and a newer on-disk version is refused, not reset.
- 📦 **Hash-bound native code.** At install, CMake writes the panel OCR DLL's SHA-256 and a manifest of every vision file; the app refuses to load a mismatch. Third-party vision inputs (OpenCV 4.13, Tesseract engine 5.0.0, Leptonica 1.82.0, `eng.traineddata`) are pinned in [`third_party.lock.json`](windows/vision/third_party.lock.json) and checked offline by [`check_bundle.dart`](tool/vision/check_bundle.dart).
- 📥 **Explicit legacy import.** [`LegacyImport`](lib/data/legacy_import.dart) reads only the settings and history JSON files you name. It shows a preview with every collision. Accepting it commits everything in one transaction, and the same files cannot be imported twice.

## 🔄 How it fits together

```mermaid
flowchart LR
    Cat(["json.tarkov.dev"]) -->|GET| C[CatalogController]
    Trk(["api.tarkovtracker.org"]) -->|GET| P[ProgressController]
    C --> S[SelectionController]
    P --> S
    S --> E[DecisionEngine] --> UI["Shell<br/>Map | Scanner"]
    Logs[/"game logs + saved screenshots"/] --> MS[MapSessionController]
    MS --> OCR["panel OCR worker<br/>Windows.Media.Ocr"]
    Pack[["prepared map pack"]] --> M[MapController]
    MS --> UI
    M --> UI
    C <--> DB[("SQLite<br/>%LOCALAPPDATA%\Blackgrid")]
```

| Part | Owned by | What happens |
|---|---|---|
| Startup | [`AppServices`](lib/application/app_services.dart) | Opens storage, credentials and the HTTP client, builds the controllers, disposes them in order |
| Catalog | [`CatalogController`](lib/application/catalog_controller.dart) + [`CatalogClient`](lib/data/catalog_client.dart) | Downloads 6 required and 4 optional English datasets for the chosen mode, normalises them off the UI isolate, swaps the snapshot in one transaction |
| Progress | [`ProgressController`](lib/application/progress_controller.dart) + [`TrackerClient`](lib/data/tracker_client.dart) | Reads `/token` and `/progress`, keeps them in memory only, treats them as current for 15 minutes |
| Decision | [`SelectionController`](lib/application/selection_controller.dart) + [`DecisionEngine`](lib/domain/decision_engine.dart) | One decision for the selected item, shown in both Map and Scanner |
| Map | [`MapController`](lib/application/map_controller.dart) + [`lib/maps/`](lib/maps/prepared_map_loader.dart) | Loads the active pack, floors, markers and pins; owns pan/zoom and hit testing |
| Session | [`MapSessionController`](lib/application/map_session_controller.dart) | Detected map/mode, player samples and exit highlights; one active plus one pending request |
| Storage | [`BlackgridDatabase`](lib/data/database.dart) | Settings, pins, history, catalog cache and import ledger |

---

## ⚡ Install / Update

> **Prerequisites:** Windows 11 x64, Git, and [mise](https://mise.jdx.dev/). Visual Studio with **Desktop development with C++**, its CMake tools and a Windows SDK ([Flutter's Windows setup](https://docs.flutter.dev/platform-integration/windows/setup)). Windows Developer Mode if a native build needs symlinks. Flutter 3.47.6 comes from [`mise.toml`](mise.toml); no global Flutter install is needed.

Install and update use the same commands:

```text
git pull
mise trust mise.toml
mise install
mise exec -- flutter pub get
mise run vision:fetch
```

`vision:fetch` downloads the pinned OpenCV, Tesseract, Leptonica and model inputs into `.dart_tool/blackgrid_vision_inputs/`. The Windows build stops with an error if any input is missing or changed. Run it again after `flutter clean`.

Check the toolchain with `mise exec -- flutter doctor -v`. Warnings about Android or web tooling do not block a Windows build.

## ⚡ First steps

1. **Close Escape from Tarkov**, then run `mise exec -- flutter run -d windows`.
2. Open **Settings** and choose the **Live game mode** (PvP, PvE or Seasonal; it starts as Unknown). Choosing a mode refreshes the catalog automatically; use **Refresh complete catalog** to retry by hand.
3. Search items with **Ctrl K**. The Scanner area shows the decision, requirements, sources and history.
4. Optional: in **Settings**, save a Tracker token for the mode, and set the game log and screenshot directories (empty = auto-detect).
5. On **Map**, use **Read Latest** after saving a screenshot in game, or **Follow logs** to switch maps automatically. A mode found in the game log replaces the Settings mode while it is detected.

Build a Release bundle with `mise exec -- flutter build windows`. Ship the whole `build/windows/x64/runner/Release/` directory, not just `blackgrid.exe`.

---

## 🧩 What's inside

### Application (`lib/`)

| Layer | Files | Role |
|---|---|---|
| Domain | [`decision_engine.dart`](lib/domain/decision_engine.dart), [`catalog.dart`](lib/domain/catalog.dart), [`progress.dart`](lib/domain/progress.dart), [`settings.dart`](lib/domain/settings.dart), [`map_geometry.dart`](lib/domain/map_geometry.dart), [`map_floors.dart`](lib/domain/map_floors.dart), [`raid_panel_text_parser.dart`](lib/domain/raid_panel_text_parser.dart), [`raid_exfil_matcher.dart`](lib/domain/raid_exfil_matcher.dart) | Pure Dart rules: decisions, freshness, settings, map math, panel text matching |
| Application | [`app_services.dart`](lib/application/app_services.dart), [`catalog_controller.dart`](lib/application/catalog_controller.dart), [`progress_controller.dart`](lib/application/progress_controller.dart), [`selection_controller.dart`](lib/application/selection_controller.dart), [`settings_controller.dart`](lib/application/settings_controller.dart), [`history_controller.dart`](lib/application/history_controller.dart), [`map_controller.dart`](lib/application/map_controller.dart), [`map_session_controller.dart`](lib/application/map_session_controller.dart) | `ChangeNotifier` controllers built by one composition root |
| Data | [`database.dart`](lib/data/database.dart), [`catalog_client.dart`](lib/data/catalog_client.dart), [`tracker_client.dart`](lib/data/tracker_client.dart), [`credential_store.dart`](lib/data/credential_store.dart), [`session_log_reader.dart`](lib/data/session_log_reader.dart), [`screenshot_directory_watcher.dart`](lib/data/screenshot_directory_watcher.dart), [`game_paths.dart`](lib/data/game_paths.dart), [`raid_panel_ocr.dart`](lib/data/raid_panel_ocr.dart), [`legacy_import.dart`](lib/data/legacy_import.dart) | HTTP, SQLite, DPAPI, game files and OCR adapters |
| Vision | [`vision_runtime.dart`](lib/data/vision/vision_runtime.dart), [`vision_primitives.dart`](lib/data/vision/vision_primitives.dart), [`tesseract_binding.dart`](lib/data/vision/tesseract_binding.dart), [`vision_self_check.dart`](lib/application/vision_self_check.dart) | Item vision runtime; used only by `--vision-self-check` and tests so far |
| Maps | [`prepared_map_loader.dart`](lib/maps/prepared_map_loader.dart), [`prepared_map.dart`](lib/maps/prepared_map.dart), [`native_map_scene.dart`](lib/maps/native_map_scene.dart) | Pack loading and native rendering |
| UI | [`shell.dart`](lib/ui/shell.dart), [`map_screen.dart`](lib/ui/map_screen.dart), [`map_workspace.dart`](lib/ui/map_workspace.dart), [`scanner_screen.dart`](lib/ui/scanner_screen.dart), [`item_decision_card.dart`](lib/ui/item_decision_card.dart), [`settings_dialog.dart`](lib/ui/settings_dialog.dart), [`import_dialog.dart`](lib/ui/import_dialog.dart), [`theme.dart`](lib/ui/theme.dart) | Two-area shell; both areas stay mounted |

Scanner has a manual catalog inspection and an opt-in **live scan** switch. With it on, a mouse release over the game window, or the scan hotkey, scans the open inspect window at the cursor and shows the evidence it found. The hotkey is **F9** by default; pick any of F1–F24, or Off, next to the switch. Blackgrid holds the key only while live scan is on, and if another application already holds it, mouse scans still work. An accepted scan selects its item and is recorded in history; see the [roadmap](openspec/roadmap.md) for what comes next.

### Native Windows code (`windows/`)

| Part | File | Does |
|---|---|---|
| Credentials channel | [`credential_protector.cpp`](windows/runner/credential_protector.cpp) | `blackgrid/credentials`: LocalAppData path, atomic replace, DPAPI protect/unprotect |
| Panel OCR DLL | [`panel_ocr.cpp`](windows/ocr/panel_ocr.cpp) | `blackgrid_panel_ocr.dll` over `Windows.Media.Ocr` |
| Vision DLL | [`vision.cpp`](windows/vision/vision.cpp), [`vision.h`](windows/vision/vision.h) | `blackgrid_vision.dll`: `bgv_*` C ABI over static OpenCV `core` + `imgproc` |
| Vision build | [`CMakeLists.txt`](windows/vision/CMakeLists.txt), [`verify_inputs.cmake`](windows/vision/verify_inputs.cmake), [`write_manifest.cmake`](windows/vision/write_manifest.cmake) | Refuses unpinned inputs; writes `data/vision/runtime.manifest.json` at install |

### mise tasks ([`mise.toml`](mise.toml))

| Task | Runs |
|---|---|
| `analyze` | `flutter analyze` |
| `test` | Fast suite, excludes the `qualification` tag |
| `test:qualification` | Expensive offline qualification tier only |
| `ci:qualification` | CI-only qualification run with a skip audit. Fails locally by design unless you confirm that no game is running; developers use `test:qualification` |
| `test:all` | Every test |
| `format` / `format:check` | `dart format`, or check without writing |
| `release-notes` | [`tool/changelog.dart`](tool/changelog.dart): preview the next release's notes from archived proposals, or `-- --check <proposal.md>` to validate one proposal's `## Release Notes` section |
| `release:prepare` / `release:tag` / `build:release` | [`tool/release/release.dart`](tool/release/release.dart): prepare a release commit, tag the merged release, build a versioned Release bundle (see **Releases and changelog**) |
| `vision:fetch` | [`fetch_runtime.dart`](tool/vision/fetch_runtime.dart): download and verify pinned vision inputs |
| `bundle:check` | [`check_bundle.dart`](tool/vision/check_bundle.dart): offline check of a built Release bundle |
| `capture:selftest` | Native capture self-test ([`selftest.ps1`](windows/capture/selftest.ps1)). Refuses unless `BLACKGRID_NO_GAMES_RUNNING=1` confirms no game is running |
| `qualification:freeze` / `:validate` / `:report` | M0 reference evidence tools in [`tool/qualification/`](tool/qualification/m0.dart) |

### Tools (`tool/`)

| Tool | Does |
|---|---|
| [`maps/prepare.dart`](tool/maps/prepare.dart) | Offline map pack pipeline: `acquire`, `rebuild`, `normalize`, `compile`, `validate`, `promote`, `assets` |
| [`ocr/read_saved_panel.dart`](tool/ocr/read_saved_panel.dart) | Reads one saved screenshot with the built panel OCR DLL |
| [`m1/catalog_smoke.dart`](tool/m1/catalog_smoke.dart) | Real catalog download for all three modes into a temporary SQLite file, with reopen check |
| [`vision/make_self_check_sample.dart`](tool/vision/make_self_check_sample.dart) | Regenerates the deterministic [self-check sample](assets/vision/self_check/title.json) |

### Agent tooling

| Path | Holds |
|---|---|
| [`.mcp.json`](.mcp.json) | Official Dart MCP server, launched through mise with the pinned SDKs |
| [`.claude/skills/`](.claude/skills/UPSTREAM.json) | First-party Flutter and Dart skills (sources and hashes in `UPSTREAM.json`), plus OpenSpec and Specwright skills |
| [`.claude/agents/`](.claude/agents/specwright-implementer.md), [`.omp/agents/`](.omp/agents/specwright-implementer.md) | Specwright implementer and reviewer agents |
| [`openspec/`](openspec/config.yaml) | Specwright change workflow, [architecture](openspec/architecture.md), [roadmap](openspec/roadmap.md), [ADRs](docs/adr/README.md) |

---

## ⚙️ Settings

There is no config file. The **Settings** dialog and the Map area save one JSON row (`Preferences`, id 1) in `%LOCALAPPDATA%\Blackgrid\blackgrid.sqlite`. The fields come from [`AppSettings`](lib/domain/settings.dart):

```jsonc
{
  "mode": "unknown",            // unknown | pvp | pve | seasonal; set in Settings. A mode found in the game log wins at runtime
  "selectedMap": "shoreline",   // one of the 13 supported map IDs
  "saveMarkerFilters": false,   // true = remember marker category filters
  "markerFilters": {},          // category -> visible, e.g. "PmcExtracts": true
  "trackerEnabled": false,      // read-only Tracker progress for the current mode
  "gameLogDirectory": "",       // empty = detect from the registry or Steam libraries
  "screenshotDirectory": "",    // empty = Documents\Escape from Tarkov\Screenshots
  "liveScan": false,            // true = live scan on at start
  "scanHotkey": "F9",           // off | F1 .. F24; set in Scanner, held only while live scan is on
  "followGameLogs": true        // switch the map from the logs; selectedMap is kept as the fallback
}
```

Tracker tokens are not part of this row. They live in `%LOCALAPPDATA%\Blackgrid\credentials\<mode>.dpapi`.

---

## 📖 Reference

<details>
<summary><b>Decision order</b> — how the recommendation is picked</summary>

The first row that matches wins ([`decision_engine.dart`](lib/domain/decision_engine.dart)).

| Recommendation | When |
|---|---|
| Keep | A requirement is actionable now |
| Keep for later | A requirement is a known future need |
| Check / May Need | Catalog or progress authority missing or stale, FIR unknown, a requirement unresolved, Flea eligibility unknown, or the Flea quote missing, in the future or older than one hour (unless the item cannot be sold on Flea) |
| Flea | Eligible, and the gross Flea price is **greater than** the best named-trader RUB cash offer (or there is none) |
| Trader | A usable trader cash offer exists. Equal Flea and trader prices choose the trader; equal trader offers use trader ID order |
| Price unavailable | None of the above |

Prices are gross RUB, not fee-adjusted. FIR is set per inspection and resets when the item, mode or authority context changes.
</details>

<details>
<summary><b>Data sources and freshness</b></summary>

| Source | Endpoint | Fresh for | On failure |
|---|---|---|---|
| Catalog | `json.tarkov.dev/{regular\|pve\|pvp-season}/{items,traders,tasks,hideout,crafts,barters}` plus optional `*_en` translations | 24 h from download; source times are shown as evidence only | Last good snapshot kept, status `stale` or `failed` |
| Flea quote | Inside the catalog | 1 h | Decision falls to Check |
| Tracker | `api.tarkovtracker.org/token`, `/progress` | 15 min, memory only | Auth or mode errors clear progress; transport errors keep it as stale. `Retry-After` is honoured; missing or bad values use 60 s |

Every request is a GET with a 30 s deadline and no redirects. The catalog refreshes once at launch and on each mode switch, and progress does too when a Tracker token is saved for the mode and the Tracker integration is enabled. A failed refresh is not retried automatically; use Refresh or select a mode again.
</details>

<details>
<summary><b>Local files</b></summary>

| Path | Holds |
|---|---|
| `%LOCALAPPDATA%\Blackgrid\blackgrid.sqlite` | Settings, pins, one history row per item and mode, catalog snapshots, import ledger |
| `%LOCALAPPDATA%\Blackgrid\credentials\<mode>.dpapi` | Tracker token, current-user DPAPI ciphertext; not portable to another Windows user |

History stores item ID, mode, source, UTC time and revision only. No telemetry, account or backend exists.
</details>

<details>
<summary><b>Map controls</b></summary>

| Input | Action |
|---|---|
| Drag / mouse wheel | Pan / zoom at the cursor |
| Arrow keys | Pan |
| Home | Fit map |
| `+` `=` numpad `+` / `-` numpad `-` | Zoom in / out |
| C | Center on the sampled player |
| N | Add a pin at the view center |
| Right-click | Add a pin at the cursor |
| Enter | Browse visible markers and pins |
| Delete | Remove the selected pin |
| Escape | Clear the selection |

Supported maps, as labelled in the UI: Factory, Customs, Woods, Shoreline, Interchange, The Lab, Reserve, Lighthouse, Streets, Ground Zero, Terminal, Icebreaker, Labyrinth (IDs in [`settings.dart`](lib/domain/settings.dart), labels in [`theme.dart`](lib/ui/theme.dart)).
</details>

<details>
<summary><b>Session inputs</b></summary>

| Input | Bound | Reads |
|---|---|---|
| Game log | 250 ms poll, 64 KiB max line | `scene preset path:` for map, `Session mode:` for mode, in the newest `log_*` folder |
| Screenshot folder | 1 s poll, 80 ms stability, 64 MiB per file | Position (XYZ) and heading (quaternion) from the filename |
| Saved panel OCR | 64 MiB, ≤ 8192 px per side, ≤ 24 × 1024² pixels, one request at a time | Exfil and transit names; a busy worker returns `unavailable` |

Evidence without a confirmed raid or map is shown as assumed. Missing or unreadable evidence is never shown as an empty panel. Check one image offline with `mise exec -- dart run tool/ocr/read_saved_panel.dart <image>`.
</details>

<details>
<summary><b>Map pack preparation</b></summary>

Runtime only loads the active pack. These commands are maintenance tools ([`prepare.dart`](tool/maps/prepare.dart)); see `--help` for details.

| Command | Does |
|---|---|
| `acquire --raw <dir>` | The only network step: freezes artwork, metadata and terms into a fresh hash-locked directory |
| `rebuild --raw <dir> --candidate <dir>` | `normalize` + `compile`, offline |
| `validate --candidate <dir>` | Checks every hash, vector payload and tile witness |
| `promote --candidate <dir> --packs <root>` | Adds an immutable `versions/<sha256>/` and swaps [`active.json`](assets/maps/active.json) atomically |
| `assets --packs <root>` | Prints the `pubspec.yaml` asset list; Flutter does not include nested tile folders by itself |

`<use>` references to symbols the publisher deleted (Customs `path493`, Streets stairs) are dropped, as a browser does. Any other missing symbol fails preparation.
</details>

<details>
<summary><b>Vision self-check</b></summary>

`blackgrid.exe --vision-self-check <report.json>` verifies and loads the bundled vision runtime, runs a template match and OCR on the bundled sample, and writes a JSON report. It shows no window and opens no database. The report directory must exist.

| Exit code | Means |
|---|---|
| 0 | Pass |
| 1 | A step failed, or the report could not be written |
| 2 | Usage error |
| 3 | A step did not return within 60 s |

`blackgrid.exe` is a GUI-subsystem app, so wait for it: `start /wait` (cmd) or `Start-Process -Wait -PassThru` (PowerShell). Check a built bundle offline with `mise run bundle:check -- build/windows/x64/runner/Release`.
</details>

<details>
<summary><b>Legacy import</b></summary>

| Rule | Detail |
|---|---|
| Inputs | Settings and/or history JSON paths you type; no directory scan |
| Supported revisions | Settings 0–3, scanner preferences 0–1, history 0–1 |
| Pins | Known map IDs and frame revisions; Labs revision 0 is converted to revision 1 |
| Never imported | Tracker keys, progress, computed advice, FIR, prices, overlay and old capture settings |
| Collisions | Source: revision, then latest UTC time, then file order. Existing records win unless you choose to replace |
| Commit | **Accept preview and import** writes all records and the digest ledger in one transaction; source files are not changed |
</details>

<details>
<summary><b>Database schema changes</b></summary>

```text
mise exec -- dart run build_runner build
mise exec -- dart run drift_dev schema dump lib/data/database.dart drift_schemas/
mise exec -- dart run drift_dev schema generate drift_schemas test/data/generated
```

Version 1 holds settings, pins, activity and catalog tables; version 2 adds the import ledger.
</details>

<details>
<summary><b>Releases and changelog</b></summary>

Versions follow [SemVer 2.0.0](https://semver.org/) with `v`-prefixed tags ([ADR-0009](docs/adr/0009-release-versioning.md)). Each milestone close bumps the minor version (M2 → `0.2.0`), fixes between milestones bump the patch, and a build handed out for user-only checks is a prerelease (`0.2.0-beta.1`). Only a release commit changes `version:` in `pubspec.yaml`. The build number is the commit count of the built `HEAD`.

| Step | Command | Does |
|---|---|---|
| Preview | `mise run release-notes` | Prints the grouped items the next release will list, warnings for changes without valid release notes, and the commits on `main` that no change covers. Changes no file. Write the release summary from it |
| Prepare | `mise run release:prepare -- <version> --summary-file <file>` (or `--summary "<text>"`) | Refuses without a summary of at most 600 characters (collapsed to one line); keep the file outside the checkout. On a clean `main` equal to `origin/main`, with a version above every release tag, it builds the notes and refuses when no change was archived since the last final release, runs `analyze`, `format:check` and `test:all`, then commits `chore(release): v<version>` (pubspec version and the new `CHANGELOG.md` section) on `release/v<version>`. It does not push; it prints the push and PR commands |
| Merge | Push the branch, open the PR titled `chore(release): v<version>` and merge it | |
| Tag | `mise run release:tag` | On `main` right after the release merge (a merge commit, or a squash commit titled `chore(release): v<version> (#N)` that the PR API confirms): checks the merge and the pubspec version, then creates annotated tag `v<version>` and pushes only that tag as `github.login` from [`openspec/specwright.yaml`](openspec/specwright.yaml); it then prints the link to the Publish run |
| Publish | Automatic on the tag push ([`release.yml`](.github/workflows/release.yml)) | Checks the tag and that it has no release, runs the same gates as CI on the tag, then publishes the zip, the installer and `SHA256SUMS.txt` as one GitHub release |
| Check a build (optional) | `mise run build:release`, `mise run package:release` | Before tagging: `vision:fetch`, `flutter build windows --release` with the version, the build number and `BLACKGRID_VERSION=<version>+<count>`, `bundle:check` on `build/windows/x64/runner/Release`, then the zip, the installer and `SHA256SUMS.txt` in `build/release/`. CI does not use these outputs; it builds again on the tag |

**Retry or backfill.** Start a manual run of [`release.yml`](.github/workflows/release.yml) from `main` (Actions, Release, Run workflow) and enter a tag that has no release. A manual run from another branch is refused, and so is a tag from before release publishing such as `v0.4.0` or `v0.5.0`: they cannot be backfilled. A failed publish can leave a draft release; the preflight and the publish job refuse a tag while any release for it exists, so delete the draft on the Releases page first, then start the manual run.

Pass `--trailer "<line>"` to `release:prepare` to add commit trailers; the commit and tag use Git's identity from the environment (`GIT_AUTHOR_*`, `GIT_COMMITTER_*`). `release:tag` refuses when another PR merged between `prepare` and the release merge: delete `release/v<version>` locally and on `origin`, then prepare again.

The version shows in the **Settings** dialog and in the `appVersion` field of the **Vision self-check** report. A build without the define (`flutter run`) shows `dev`. The executable's file version is `<major>.<minor>.<patch>.<count>`.

Release notes come from each change's proposal ([ADR-0029](docs/adr/0029-release-notes-come-from-each-proposal.md)). Every `proposal.md` has a `## Release Notes` section: a summary, then `### Added`, `### Changed`, `### Fixed` and `### Removed` lists. `release:prepare` reads the sections of the proposals archived on `main`'s first-parent line since the last final release, groups their items as `Added:`, `Changed:`, `Fixed:` and `Removed:` with each change's PR number, puts the release summary first, and inserts that section above the newest one in `CHANGELOG.md`. Earlier sections are never regenerated. A final release drops the sections of its own prereleases and lists everything since the previous final release. A change without a valid section is listed under `Changes:` with the first sentence of its Why, and a warning names it.

```text
mise run release-notes
mise run release-notes -- --check openspec/changes/<change>/proposal.md
mise run release:prepare -- 0.7.0 --summary-file ../release-summary.txt
```
</details>

---

## 🧪 Tests

| Command | Covers |
|---|---|
| `mise run test` | Domain, data, controllers, widgets, map logic and the untagged M0 contract, statistics, comparison, export and CLI tests; offline. Use during development |
| `mise run test:qualification` | Tag `qualification` ([`dart_test.yaml`](dart_test.yaml)): map pack preparation, M0 collector and fixture integrity, panel OCR, vision runtime, CMake and bundle checks. The native capture test skips unless `BLACKGRID_NO_GAMES_RUNNING=1` confirms no game is running |
| `mise run test:all` | Both; run before merging |
| [`m1_windows_smoke_test.dart`](integration_test/m1_windows_smoke_test.dart) | Real DPAPI, real catalog, SQLite reopen on Windows |

Tests live in [`test/`](test/). **Agents and live-game checks:** no agent may launch or drive Blackgrid while Escape from Tarkov is running, and checks that need the game belong to the user. See [AGENTS.md](AGENTS.md).

## 🚦 Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every pull request and every push to `main`. It only calls the shared [`.github/workflows/gates.yml`](.github/workflows/gates.yml), which holds the gates below so that release publishing runs the same ones. The pull request check is named `ci / Analyze, test, build and qualify`; a branch protection rule that requires it must use that name. The gates run on a GitHub-hosted `windows-2025` runner ([installed software](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md)). They install the tools pinned in [`mise.toml`](mise.toml), then run these gates in order and stop at the first failure:

1. `mise run analyze`
2. `mise run test`
3. `mise run build:release` (full-history checkout, with the offline bundle check)
4. `mise run ci:qualification`, the qualification tier against that bundle

The qualification tier cannot run every test on a hosted runner. The committed allowlist, [`tool/ci/qualification_skips.yaml`](tool/ci/qualification_skips.yaml), accepts two kinds of skip, and any other skip fails the run:

- **Private input** (`private_input`): three tests need private inputs that are not committed: the inspection corpus, the targeted-region replay and the supplied panel image.
- **Host platform** (`host_platform`): a skip caused by a host setting that a hosted runner cannot provide, and only when a test that runs on CI covers the same behaviour (`covered_by`). The one such entry is the in-process Cyrillic-path vision runtime test. It needs a UTF-8 system code page, and the runner uses 1252. The `blackgrid.exe` self-check under a Cyrillic path covers it.

`mise run ci:qualification` is meant for CI. Locally it fails by design unless you confirm that no game is running, so developers use `mise run test:qualification`. Making the check required before merging is the repository owner's branch protection setting on GitHub.

## 🗑️ Uninstall

1. Delete the Release directory.
2. Delete `%LOCALAPPDATA%\Blackgrid\` to remove settings, pins, history, the catalog cache and saved tokens.

## 💡 Data sources and credits

Blackgrid is a fan-made companion tool. It is **not affiliated with, endorsed by or sponsored by Battlestate Games**. It is made for personal, non-commercial use.

### tarkov.dev

Blackgrid relies heavily on the [tarkov.dev](https://tarkov.dev) project and its community data:

| Used from tarkov.dev | Purpose |
|---|---|
| SVG map graphics ([tarkov-dev-svg-maps](https://github.com/the-hideout/tarkov-dev-svg-maps), by Shebuka and contributors) | Map backgrounds for most locations |
| Interactive map tiles | Map backgrounds for The Lab and Labyrinth; Icebreaker's tiles are by [TarkovBOT.eu](https://tarkovbot.eu/), hosted by tarkov.dev |
| Map metadata and coordinates | Bounds, transforms and floor definitions |
| Game data ([json.tarkov.dev](https://json.tarkov.dev)) | Items, prices, traders, quests, hideout, crafts and barters; extracts, transits, spawns, bosses, hazards, switches, locks and loot positions |
| Item icons ([assets.tarkov.dev](https://assets.tarkov.dev)) | Item pictures on the decision card and in history, downloaded when an item is shown |

Thank you to the tarkov.dev team and contributors for maintaining the maps and open game data.

The map marker icons (extracts, quests, spawns, bosses, hazards and the rest) are Blackgrid's own, drawn for this project ([ADR-0023](docs/adr/0023-project-authored-map-marker-icons.md)).

### TarkovTracker

Optional quest and hideout progress comes from the read-only [TarkovTracker](https://tarkovtracker.org) API ([tarkovtracker-org](https://github.com/tarkovtracker-org)).

### Escape from Tarkov

Escape from Tarkov is a trademark of Battlestate Games Limited. Game names, item names, item images and map content belong to Battlestate Games. This project is unofficial.

### Other

- Inspired by [TarkovTracker](https://github.com/sayser/TarkovTracker), a C# desktop companion. Blackgrid is an independent Dart/Flutter implementation and contains no code from it.
- Map artwork and metadata: the tarkov-dev SVG maps project, Tarkov.dev and TarkovBOT.eu, under the terms recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and in each pack's evidence.
- Item vision: OpenCV, Tesseract, Leptonica and tessdata, pinned in [`third_party.lock.json`](windows/vision/third_party.lock.json).
- Project direction: [STRATEGY.md](STRATEGY.md), [architecture](openspec/architecture.md), [decisions](docs/adr/README.md).
- Blackgrid's source code is released under the [MIT License](LICENSE). Bundled third-party code, models and map artwork keep their own licenses, listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The map artwork is **not** MIT: most of it is CC BY-NC-SA 4.0, which forbids commercial use and asks that changes be shared under the same terms.
