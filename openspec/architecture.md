# Blackgrid Architecture

The system as the code stands on `main` after M5 (2026-10-07). Change designs read this first. It is derived from [docs/IMPLEMENTATION_STRATEGY.md](../docs/IMPLEMENTATION_STRATEGY.md), which stays the historical source; the section links below point there for detail and rationale. Every claim here was checked against `lib/` and `windows/`. Where the strategy and the code disagree, the [Strategy vs. code](#strategy-vs-code) table says so, and this file describes the code.

## System triage

All six triggers apply to the system as a whole:

- **T1 Components:** Map, Scanner (manual decisions only so far), catalog, progress, persistence, session inputs and native OCR, wired through one composition root (`lib/application/app_services.dart:27-72`).
- **T2 State:** durable SQLite user records and the catalog cache (`lib/data/database.dart:15-75`), plus memory-only progress and session evidence.
- **T3 Concurrency:** the Drift background isolate, `Isolate.run` decode/normalise work, a long-lived OCR worker isolate, file watchers and polling timers. Generation fences protect catalog, progress, selection, map and session publication; `SettingsController` and `HistoryController` have no generation or disposal guards (`settings_controller.dart:16-40`; `history_controller.dart:13-31`).
- **T4 Boundaries:** json.tarkov.dev and tarkovtracker.org HTTP, the game's log and screenshot files, the DPAPI method channel, the FFI OCR DLL, and the prepared map-pack format.
- **T5 Volume:** map artwork (1,331 hashed outputs in the active pack), the screenshot directory, the log stream and history rows.
- **T6 Risk:** a wrong Sell loses a player's needed item, credentials are protected secrets, and users' pins and history are unrecoverable if lost. The agent/game boundary in [AGENTS.md](../AGENTS.md) is a hard safety rule.

## Components

```mermaid
flowchart TB
  subgraph UI["UI isolate"]
    Shell["Shell (IndexedStack: Map | Scanner)<br/>lib/ui/shell.dart"]
    Ctl["ChangeNotifier controllers<br/>lib/application/*"]
    Dec["DecisionEngine (pure Dart)<br/>lib/domain/decision_engine.dart"]
    Scene["Native map scene + LRU<br/>lib/maps/"]
  end
  DB[("SQLite via Drift<br/>background isolate")]
  OCRW["Panel OCR worker isolate"]
  DLL["blackgrid_panel_ocr.dll<br/>Windows.Media.Ocr"]
  Runner["Windows runner<br/>blackgrid/credentials channel (DPAPI)"]
  Pack[["Prepared map pack<br/>assets/maps/active.json"]]
  Cat(["json.tarkov.dev"])
  Trk(["api.tarkovtracker.org"])
  Game[/"Game log + screenshot files<br/>(read-only)"/]

  Shell --> Ctl
  Ctl --> Dec
  Ctl --> Scene --> Pack
  Ctl -->|Drift queries| DB
  Ctl -->|HTTP GET| Cat
  Ctl -->|HTTP GET| Trk
  Ctl -->|MethodChannel| Runner
  Ctl -->|poll + Directory.watch| Game
  Ctl -->|SendPort| OCRW -->|dart:ffi| DLL
```

| Component | Responsibility | Owns (state) | Talks to via (contract) |
|---|---|---|---|
| `AppServices` (`lib/application/app_services.dart`) | Composition root: opens storage, credentials and the HTTP client, builds the controllers, then disposes them in order (`:181-199`) | Long-lived service graph, mode-transition and map-content generations (`:79,91`) | Constructor injection, `addListener` (`:69-71`) |
| Shell / UI (`lib/ui/`) | Two-area shell; both screens stay mounted in an `IndexedStack` (`shell.dart:160-171`) | Widget-local view state only | `ListenableBuilder` on controllers |
| `CatalogController` + `CatalogClient` | Mode-scoped catalog refresh, validation and publication | Published `CatalogSnapshot`, `CatalogStatus` (`catalog_controller.dart:9`) | HTTP GET of 6 required + 4 optional datasets (`catalog_client.dart:23-72`); Drift |
| `ProgressController` + `TrackerClient` | Read-only Tracker progress per mode and session | Memory-only progress snapshot and session authority (`progress_controller.dart:27,47-56`) | GET `/token`, `/progress` (`tracker_client.dart:43-198`) |
| `SelectionController` + `DecisionEngine` | The one decision projection that Map and Scanner both show | Current selection, transient FIR context, generation (`selection_controller.dart:58`) | Pure domain call (`selection_controller.dart:36,155`) |
| `SettingsController`, `HistoryController` | Durable preferences, pins and activity | Nothing beyond the DB rows | Drift |
| `MapController` + `lib/maps/` | Load the prepared pack, floors, markers, viewport transform, hit testing | Selected map, view transform, scene generations (`map_controller.dart:45-47`), 192 MiB native resource LRU (`native_map_scene.dart:23-35`) | Asset bundle; `vg.loadPicture` on precompiled `.vec` (`native_map_scene.dart:127-133`) |
| `MapSessionController` | Map-owned session evidence: detected map/mode, player samples, raid-exit highlights. No Scanner collaborator (`:18`) | Session epoch, one active and one pending request (`:56,319-364`) | `SessionLogReader`, `ScreenshotDirectoryWatcher` streams; `RaidPanelOcr` |
| `RaidPanelOcr` (`lib/data/raid_panel_ocr.dart`) | OCR of saved raid-exit panels | One worker isolate; single admission (`:90,116-121`) | `SendPort` → `dart:ffi` into `blackgrid_panel_ocr.dll` (`windows/ocr/panel_ocr.cpp`) |
| Windows runner (`windows/runner/`) | DPAPI protect/unprotect, atomic replace, LocalAppData path | Nothing | `MethodChannel('blackgrid/credentials')` (`credential_protector.cpp:32-107`) |
| Vision runtime (`lib/data/vision/`, `windows/vision/`) | Item vision primitives and OCR engine, verified against `data/vision/runtime.manifest.json` and loaded only from the bundle (ADR-0008). Loaded only by `--vision-self-check` and tests; the warm worker comes in M2 change 3 | Runtime status `ready`/`unavailable`/`disposed`, engine handle, opened libraries | `dart:ffi` into `blackgrid_vision.dll` (`bgv_*` ABI, OpenCV 4.13 `core`+`imgproc` static) and `tesseract50.dll` → `leptonica-1.82.0.dll` |
| Capture DLL (`windows/capture/`) | Global `WH_MOUSE_LL` hook thread with a bounded trigger ring, window snapshots, BitBlt capture into generation-checked DIB frame slots. Facts only, no policy (ADR-0010) | Hook installation, 16-event ring, 4 frame slots | `dart:ffi` into `blackgrid_capture.dll` (`bgc_*` ABI v1), hash-bound by `blackgrid_capture.dll.sha256` |
| Capture worker + `CaptureService`, `MouseReleaseTriggerSource` (`lib/data/capture/`) | Dart policy (validate, ROI plan, coherence, blank) in a dedicated capture worker isolate with single admission; the trigger source drains the ring on a coalesced signal. **Not wired into app startup or UI yet; M2 change 5 wires them** | Service admission/overrun/closing state, one-entry exe-name cache, hook lifecycle | `SendPort` to the worker, then `dart:ffi` into `blackgrid_capture.dll`; frames cross isolates as `CaptureFrameTicket` |
| Vision tooling (`tool/vision/`) | Pinned input fetch (`vision:fetch`) and the offline Release bundle integrity check (`bundle:check`) | Content-addressed input cache `.dart_tool/blackgrid_vision_inputs/` | `windows/vision/third_party.lock.json`; `tool/vision/bundle_inventory.json` |
| Map tooling (`tool/maps/prepare.dart`) | Offline acquire, normalise, compile, validate and promote of map packs | Immutable `assets/maps/versions/<sha256>/` generations | Build-time `vector_graphics_compiler` |

**Not built yet:** the Scanner wiring (M2 change 5), the recognition pipeline (M2 changes 3-4) and hotkeys (M4). `SessionScanState` is a constant stub with no producer (`lib/application/session_scan_state.dart:1-7`). The mouse-release hook and ROI capture boundary exist (`windows/capture/`, `lib/data/capture/`, ADR-0010) but nothing in app startup or the UI starts them, and there is no hotkey code. The vision runtime (OpenCV primitives and Tesseract) exists, but no recognition pipeline or worker isolate calls it yet.

## State ownership

| State | Writer(s) | Lifetime | Invalidation / rebuild | Authoritative copy |
|---|---|---|---|---|
| Settings (mode, map, saved filters, Tracker enablement, game directories) | `SettingsController`; `LegacyImport` via `BlackgridDatabase.commitImport` (`legacy_import.dart:62-63`; `database.dart:265-289`), after which `AppServices.reloadAfterImport` reloads the controllers (`app_services.dart:176`; `import_dialog.dart:74`) | Durable | A failed save keeps the previous value (`settings_controller.dart:35-36`) | SQLite `Preferences` row id=1, JSON payload (`database.dart:157-175`) |
| Custom pins | `SettingsController`; `LegacyImport` via `commitImport` | Durable | Database load deserialises pins without validation (`database.dart:176-182`; `settings.dart:160-169`); frame and revision are validated on save, on import and when pins are projected (`map_coordinates.dart:118-125`). The manifest's pin frame is validated separately (`prepared_map.dart:124-131`) | SQLite `PinRecords` |
| Activity history | `HistoryController` via `recordActivity`; `LegacyImport` via `commitImport` | Durable; one row per (item, mode) with a revision (`database.dart:30-38,218-240`) | Reopening re-resolves current facts | SQLite `ActivityRecords` |
| Catalog snapshot | `CatalogController` | Durable cache, one per mode | Atomic swap in one transaction (`database.dart:126-154`); last-good kept on failure (`catalog_controller.dart:127-128`) | SQLite `CatalogRecords` + `ActiveCatalogs`, normalised JSON |
| Legacy-import ledger | `LegacyImport` commit | Durable | Digest rejects re-import (`database.dart:258-302`) | SQLite `ImportRecords` |
| Tracker token | `DpapiCredentialStore` | Durable, per mode | Temp file then `MoveFileExW` (`credential_store.dart:101-105`) | `%LOCALAPPDATA%\Blackgrid\credentials\<mode>.dpapi` |
| Tracker progress | `ProgressController` | Memory, current session; 15 min (`progress.dart:42`) | Cleared on mode or credential change; transport failure keeps it as stale (`progress_controller.dart:166-182`) | None durable (by design) |
| Selection and transient FIR | `SelectionController` | Memory | Reset on selection, mode and generation changes | None durable |
| Map view transform and scene | `MapController` | Memory, per map (`_views`) | Content generation fences late loads (`map_controller.dart:430-455`) | Prepared pack (immutable) |
| Session evidence (map/mode, player sample, exit highlights) | `MapSessionController` | Memory, per epoch | Epoch bumps on log directory, session or incarnation change (`:185-188,253`); last-good kept on same-context transient error (`:254-264`) | Game files (read-only) |
| Active map generation | `tool/maps/prepare.dart promote` (offline) | Repository | Atomic `active.json` swap (`pack.dart:1452-1484`) | `assets/maps/active.json` |

## Boundaries and contracts

- **Catalog:** GET only, no redirects, 30 s timeout, at `https://json.tarkov.dev/{regular|pve|pvp-season}/<dataset>` (`catalog_client.dart:23-39`; `catalog.dart:7-12`). Normalised into a canonical `CatalogSnapshot` off the UI isolate (`catalog_client.dart:91`). The cache key is `json.tarkov.dev:<mode>`, with no locale (`database.dart:103`). The snapshot is `current` only after a fresh fetch whose six source timestamps agree and are under 24 h old (`catalog.dart:297-316`).
- **Tracker:** GET only, Bearer token, ETag, no redirects, 30 s timeout. 401/403/429 map to typed failures, and Retry-After defaults to 60 s (`tracker_client.dart:84-121`). Token prefix, GP permission, mode and owner are verified. It never writes.
- **SQLite schema:** Drift `schemaVersion` 2, with snapshots in `drift_schemas/`. Only the 1→2 upgrade is supported, and a newer on-disk version is refused (`database.dart:82-100`). The file is `%LOCALAPPDATA%\Blackgrid\blackgrid.sqlite` (`local_paths.dart:8-25`).
- **Prepared map pack:** `active.json` (`schemaVersion` 1) points at a sha256-named immutable generation. Its manifest must declare `vectorsCompiled` and `runtimeVectorVersion == '1.2.3'`, and v3 packs must cover the full map set (`prepared_map_loader.dart:46-121`). Content hashes are checked by the tooling, not at runtime.
- **Credentials channel:** `blackgrid/credentials` with `localDataPath`, `atomicReplace`, `protect` and `unprotect`. DPAPI runs in current-user scope with `CRYPTPROTECT_UI_FORBIDDEN` (`credential_protector.cpp:92-98`).
- **Panel OCR ABI:** a `dart:ffi` C ABI with a version check. The DLL must match the `blackgrid_panel_ocr.dll.sha256` that CMake writes at install (`windows/CMakeLists.txt:90-98`; `raid_panel_ocr.dart:188-206`). This proves the DLL matches its build; it is not tamper-proof.
- **Vision runtime ABI:** `bgv_*` C ABI over caller-owned buffers with a `bgv_abi()` version check, plus a minimal Tesseract C-API binding whose `TessVersion()` must equal the manifest's `engineVersion`. Every vision file must match `data/vision/runtime.manifest.json`, written by CMake at install, before any library opens; third-party files are pinned in `windows/vision/third_party.lock.json` (ADR-0008). Like the panel binding, this is not tamper-proof.
- **Capture ABI:** `bgc_*` C ABI over caller-owned buffers (`bgc_abi`, `bgc_hook_start/stop/drain`, `bgc_snapshot`, `bgc_process_name`, `bgc_capture`, `bgc_frame_info/release/live_count/finalize`, `bgc_qpc_now/frequency`; `windows/capture/capture.h`) with a `bgc_abi()` version check. The DLL must match the `blackgrid_capture.dll.sha256` that CMake writes at install, as with panel OCR; this is not tamper-proof (ADR-0010). Native returns facts; validation and planning are Dart. Frames cross isolates only as `CaptureFrameTicket`. The code opens no handle to, reads no memory of and sends no input to the target process; an offline audit test enforces this.
- **Game inputs:** read-only. The newest `log_*` folder's `application*.log` is polled every 250 ms with a recursive watch. The parser reads `scene preset path:` for the map and `Session mode:` for the mode (`session_log_reader.dart:13-15,173-211,322-379`). Screenshot filenames carry XYZ plus a quaternion (`screenshot_filename.dart:23-76`). Paths come from registry uninstall keys or the Steam library (`game_paths.dart`). The app never touches game memory or processes.
- **Legacy import:** a one-time, read-only parse of user-chosen files in an isolate, committed atomically. Labs revision 0→1 pin conversion happens only here (`legacy_import.dart:74,161-201,371`).

## Resource bounds and failure visibility

| Flow / store | Bound | At the bound | On failure | Who finds out |
|---|---|---|---|---|
| Catalog refresh | 30 s per request; one in flight per mode (`catalog_controller.dart:20,76-91`) | Request aborted | Last-good kept, status `failed`/`stale` | Status bar `Catalog <status>` (`shell.dart:207-223`) |
| Tracker progress | 30 s per request; two sequential requests (`/token`, `/progress`) plus parsing, with no overall deadline (`tracker_client.dart:84,138,179`); 15 min age; 429 cooldown | Snapshot goes stale; cooldown shown | Auth/mode/identity failure clears authority; transport failure keeps stale | Status bar `Progress <status>`; decisions fall to Check |
| HTTP response bodies (catalog, Tracker) | **No byte cap**; whole bodies are buffered (`catalog_client.dart:30-43`; `tracker_client.dart:80-89`) | — | Timeout or parse failure | Status bar |
| Legacy import | **No byte or record cap**; whole files are read and the preview materialised (`legacy_import.dart:22-49`; `import_preview.dart:26-30`) | — | A failed commit is rolled back (one transaction, `database.dart:258-302`). If the commit succeeds but the controller reload fails, the dialog still reports failure while the imported data stays committed (`import_dialog.dart:70-84`; `app_services.dart:176-179`) | User, in the import dialog |
| Map native resources | 192 MiB of accounted decoded raster and approximate picture bytes, excluding GPU copies (`native_map_scene.dart:14-50`); 256×256 tiles enforced (`:167-171`) | Evict unleased resources; scene load fails if active leased demand prevents admission (`:221-233`) | Load error text over the canvas (`map_workspace.dart:422-427`) | User, on the Map canvas |
| Log tail | 250 ms poll, 8 KiB chunks, 64 KiB max line | Over-long line → error status | Error status; detected map/mode retained (`session_log_reader.dart:264-303`) | Map session status text (`map_screen.dart:88-118`) |
| Screenshot watch | 1 s poll, 80 ms stability, 64 MiB per file; newest changed file only | Larger files skipped | Error evidence | Map session status text |
| Screenshot directory bookkeeping | **No count cap.** `_seen` and `_fileStamps` track present files; content hashes (`_knownContentIds`) and unmatched dirty paths persist until rebinding (`screenshot_directory_watcher.dart:49-52,100-102,251-266`) | Can grow with distinct screenshot contents and unmatched paths seen this binding, independent of the current folder size | — | Nobody (unbounded) |
| Panel OCR | 64 MiB input; ≤8192 px per side, ≤24 MPix; one admission (`raid_panel_ocr.dart:110-121,390-396`) | Busy → `unavailable`, not queued | Error/unavailable/missing evidence | Map session status; highlights change only on recognised/empty results |
| Vision primitives and item OCR | Each side 1-8192 px, ≤24 MPix, channels 1/3/4, `stride >= w*channels`; checked in Dart and again natively; OCR text decoding capped at 64 KiB | `invalidImage`, no native call | Typed `VisionFailure`, never thrown | Caller; the self-check report |
| Vision call duration | **None** until the warm worker (M2 change 3). The only caller in this change, `--vision-self-check`, runs under a 60 s watchdog and exits 3 | — | A hang is reported as `timeout(step)` by the self-check | User running the self-check |
| Panel OCR duration | **None.** `RecognizeAsync().get()` blocks the worker (`panel_ocr.cpp:205`) | — | A hung call leaves Map processing active, later requests pending or replaced (`map_session_controller.dart:333-361`), and service disposal waiting indefinitely (`:449-453`). Concurrent direct adapter calls return `unavailable` | Nobody; status stays in progress |
| Capture trigger ring | 16 events in the native hook (`windows/capture/`); ≤1 pending Dart signal (coalesced) | Drop oldest, counted, reported on drain | Hook stop: 1 s join | `stopTimedOut`; the listener is kept alive | Caller (not yet wired; change 5 surfaces it) |
| Capture frames | 4 live slots; side ≤8192 and ≤25,165,824 px | `frameBudgetExceeded` / `captureTooLarge` before acquisition | — | Typed `CaptureFailure`, never thrown; unreleased frames are freed by the finalizer | Caller |
| Capture requests | 1 active, 0 queued; 500 ms deadline from admission | `captureBusy`; at the deadline `captureTimeout` and the service stays `overrun` until the worker replies, then the late frame is released | Service close: 2 s drain | `shutdownIncomplete`; worker error → `unavailable`, no respawn | Caller (not yet wired) |
| Map session requests | One active plus one replaceable pending (`map_session_controller.dart:319-364`) | Pending replaced | Stale results dropped by epoch/context | — |
| History | One row per (item, mode); no row limit (`database.dart:198-216`) | — | A load failure retains prior rows, and the panel shows the error only when empty (`history_controller.dart:13-31`; `evidence_panels.dart:193-199`). Manual record failures appear in the decision card (`selection_controller.dart:84-86`; `item_decision_card.dart:198-205`) | User, only partly |
| App storage open | — | — | Bootstrap error with Retry; data not reset (`lib/ui/app.dart:78-84`) | User |

## Strategy vs. code

| Strategy says | Code does | Where |
|---|---|---|
| Use `InteractiveViewer` / `TransformationController` / `toScene` ([§5](../docs/IMPLEMENTATION_STRATEGY.md#native-rendering-and-asset-preparation)) | A custom `Listener` + `GestureDetector` over `CustomPaint`, with the domain `MapViewTransform` | `map_workspace.dart:349-392`; `map_geometry.dart:267` |
| Keep pan/zoom out of application broadcasts ([§5](../docs/IMPLEMENTATION_STRATEGY.md#native-rendering-and-asset-preparation), [§9](../docs/IMPLEMENTATION_STRATEGY.md#9-state-management-strategy)) | Every pan/zoom calls `notifyListeners()` on `MapController`, and the workspace rebuilds | `map_controller.dart:336-367,413-453`; `map_workspace.dart:245` |
| Qualify `flutter_svg` with `vector_graphics` ([§5](../docs/IMPLEMENTATION_STRATEGY.md#native-rendering-and-asset-preparation)) | No `flutter_svg`; SVG is compiled at build time and only the `vector_graphics` runtime ships | `pubspec.yaml:15,25`; `tool/maps/pack.dart:75-81` |
| Key compiled scenes by content/version ([§5](../docs/IMPLEMENTATION_STRATEGY.md#native-rendering-and-asset-preparation)) | Content-addressed generation directories; no runtime hash verification | `prepared_map_loader.dart:44-124` |
| A small Windows plugin for input, capture, hotkeys and credentials ([§7](../docs/IMPLEMENTATION_STRATEGY.md#7-windows-integration-strategy)) | No plugins. Runner-embedded DPAPI channel plus standalone hash-bound FFI DLLs (panel OCR, vision runtime, capture) with an app-local Visual C++ runtime; input and capture are built as `blackgrid_capture.dll` (ADR-0010) but not yet wired into the app; hotkeys do not exist | `windows/runner/credential_protector.cpp`; `windows/ocr/`; `windows/vision/`; `windows/capture/` |
| Catalog Ready/Stale/Incomplete/Unavailable, keyed by mode/locale/source ([§8](../docs/IMPLEMENTATION_STRATEGY.md#8-data-and-persistence-strategy)) | `missing/loading/current/stale/failed`; "incomplete" only per requirement; key has no locale; English translations only | `catalog_controller.dart:9`; `catalog.dart:133,150`; `database.dart:103` |
| `ValueNotifier` for small values; async states carry their source generation ([§9](../docs/IMPLEMENTATION_STRATEGY.md#9-state-management-strategy)) | `ChangeNotifier` only; generations are mostly private counters; `authorityVersion`, the map `contentGeneration` (`map_controller.dart:67`) and session epochs are exposed | `catalog_controller.dart:26`; `progress_controller.dart:26` |
| Scanner coordinator and services survive navigation ([§6](../docs/IMPLEMENTATION_STRATEGY.md#6-scanner-strategy), [§9](../docs/IMPLEMENTATION_STRATEGY.md#9-state-management-strategy)) | No scanner service exists; the stub has no producer | `session_scan_state.dart` |
| Exit-panel OCR backend open; Tesseract considered ([§12](../docs/IMPLEMENTATION_STRATEGY.md#12-risks-and-prototypes)) | Decided (2026-10-07): Windows.Media.Ocr, unpackaged ([§5](../docs/IMPLEMENTATION_STRATEGY.md#session-evidence-and-saved-pins), ADR-0006) | `raid_panel_ocr.dart`; `panel_ocr.cpp` |
| Noncancellable native calls must be bounded ([§6](../docs/IMPLEMENTATION_STRATEGY.md#6-scanner-strategy)) | Panel OCR has no duration bound (item OCR does not exist yet) | `panel_ocr.cpp:205` |

## In-force ADRs

| ADR | Decision | Supersedes |
|---|---|---|
| [0001](../docs/adr/0001-shared-conservative-decision-engine.md) | One pure-Dart conservative decision engine is the only keep/sell authority for Map and Scanner | — |
| [0002](../docs/adr/0002-sdk-notifiers-and-composition-root.md) | SDK `ChangeNotifier` controllers built by a hand-written composition root; generation counters fence stale results | — |
| [0003](../docs/adr/0003-single-drift-sqlite-store.md) | One Drift SQLite database in LocalAppData holds settings, pins, history and the catalog cache, with versioned migrations | — |
| [0004](../docs/adr/0004-isolate-model.md) | Single process: UI isolate, Drift background isolate, `Isolate.run` for bulk decode, a long-lived worker isolate for blocking native OCR | — |
| [0005](../docs/adr/0005-native-map-prepared-packs.md) | Native Flutter map rendering from offline-prepared, content-addressed packs with build-time vector compilation | — |
| [0006](../docs/adr/0006-windows-media-ocr-for-raid-panels.md) | Map-owned raid-panel OCR uses Windows.Media.Ocr through a hash-bound FFI DLL, separate from future item OCR | — |
| [0007](../docs/adr/0007-runner-channel-and-ffi-dll-windows-boundary.md) | Implemented Windows integration (credentials, panel OCR) is a runner-embedded method channel plus a standalone FFI DLL, not Flutter plugins; DPAPI current-user for tokens | — |
| [0008](../docs/adr/0008-item-vision-runtime.md) | Item vision runtime: owned OpenCV primitives DLL, pinned charlesw Tesseract 5.2.0 package binaries (engine 5.0.0, Leptonica 1.82.0), lock plus install-manifest binding, bundle-only load order, app-local Visual C++ runtime, UTF-8 active code page | — |
| [0009](../docs/adr/0009-release-versioning.md) | Release versioning: SemVer milestone versions set only by release commits, commit-count build numbers, a first-parent per-PR changelog, local `release:prepare`/`release:tag`/`build:release` tasks with a fenced tag push, and a `BLACKGRID_VERSION` define shown by the app | — |
| [0010](../docs/adr/0010-windows-input-and-capture-boundary.md) | Windows input and capture: standalone hash-bound `blackgrid_capture.dll`, native `WH_MOUSE_LL` hook thread with a 16-event ring and coalesced signal, DPI-independent physical-pixel ROI, clip-not-pad, 4 generation-checked frame slots with ticket hand-off, native facts with Dart policy, a capture worker isolate (500 ms deadline), and no handle to, memory access of or input to the target process | — |

Planned but not built (item recognition pipeline, Scanner wiring, hotkeys) live in the [roadmap](roadmap.md), not here.
