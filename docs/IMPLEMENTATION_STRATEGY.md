# Blackgrid Implementation Strategy

Companion to [the product strategy](../STRATEGY.md). This document defines the replacement and its qualification sequence, not a schedule or authorization to implement.

**Evidence labels:** **Existing fact** describes inspected reference code or documentation; **Decision already made** records the user's direction; **Recommendation** is the proposed technical choice; **Open question** is a remaining prototype or qualification question, not permission to change product scope.

## 1. Executive Summary

**Decision already made:** Blackgrid is an independent Windows desktop tactical companion whose primary job is helping a player looting during a raid decide **Keep**, **Keep for later**, **Check / May Need**, **Sell on Flea**, or **Sell to a trader**. Quest/hideout relevance, FIR rules, and eventual sale value support the immediate “is this worth keeping in my bag?” decision.

The rewrite preserves useful Map and Scanner behavior and correctness, not WPF, C#, WebView2, visuals, architecture, or known defects. Flutter/Dart owns presentation, state, orchestration, matching, data resolution, progression decisions, and map rendering. Native libraries supply CV/OCR primitives; a narrow Windows boundary supplies OS events, geometry, capture, hotkeys, and credential protection. The old application is an inspection and qualification oracle, never a shipped dependency.

**Decision already made:** Initial primary navigation is **Map and Scanner only**. Required configuration belongs in supporting controls/dialogs. Retain read-only tarkovtracker.org progression retrieval; defer full progression overview, quest updates, and Database browsing. Remove the overlay entirely. No Blackgrid backend, cloud sync, account system, telemetry, or other-platform release work in this phase.

Advice must preserve player options: unknown FIR, progression relevance, or market freshness cannot produce a confident Sell. The implementation will deliberately improve this safety boundary rather than reproduce unsafe old decisions.

**Recommendation:** Establish reference fixtures and timing first, prove the recognition/capture and map-rendering risks early, then deliver a working scanner vertical slice and full native map before calling Blackgrid a replacement. Prototypes and milestones below are proposed work; none has been executed in this strategy run.

## 2. Current System Assessment

### Inspection basis

**Existing fact:** The reference is the separate local `TarkovTracker` checkout; the observed HEAD is `04cf9e4b618d4921cd4d125753ece255d3e37eb0`. Findings describe the working files inspected, not a claim that the checkout is clean. Blackgrid currently contains a minimal Windows Flutter placeholder, Flutter-only application dependencies, and two visual mockups; it has no product implementation or commits. Its toolchain is pinned to Flutter 3.47.6 / Dart 3.13.5.

Inspection covered map assets/configuration/geometry/JS, log and screenshot inputs, Windows trigger/capture, RatEye recognition, scanner orchestration/matching/publication, catalog/value/progression, persistence, and their available tests. No reference application, tests, or benchmarks were run; baseline quality and timing remain to be measured.

### Implemented architecture and useful behavior

- WPF `MainWindow` owns substantial composition and map/session/scanner wiring; local HTML/SVG/CSS/JavaScript rendered by WebView2 owns map interaction. Scanner services already separate recognition evidence, matching, market facts, progression, shared decisions, state, and history more cleanly than the UI composition suggests.
- The map loads 13 configured artworks and JSON marker sources. Geometry includes rotation, affine transforms, tile pixel frames, nullable height, and bearing conversion. Browser groups implement floors, category/search/quest filtering, selectable details, fixed-screen-size markers, pins, player samples, and raid-available exits. Labs uses raster tiles; Icebreaker raster floors; Labyrinth a raster image wrapped in SVG.
- Logs provide map and PvP/PvE/Seasonal session mode. Screenshot filenames provide sampled XYZ/quaternion context; screenshot-panel OCR supplies raid exfil/transit names. This is not continuous player telemetry. Automatic floor bands are configured for Labs and Icebreaker, not every multilevel map. BTR stop markers are present; route polylines were not established.
- Automatic mouse-release and manual-hotkey triggers feed one active scan worker with one replaceable pending request. Generation fences prevent stale publication even when a dependency ignores cancellation. Current Scanner result, transient correction, durable history, and the accepted Map snapshot are separate contracts.
- Production capture uses `Graphics.CopyFromScreen` of visible client pixels. Despite a `PrintWindow` method name, native `PrintWindow` is unused. The targeted path captures the full client bitmap before cropping; it does not acquire a small rectangle directly. Full-viewport multi-inspection fallback is actively called after targeted matching fails; automatic fallback waits until approximately 200 ms after enqueue.
- RatEye performs OpenCV marker correlation and title extraction, then Tesseract OCR; host matching applies normalization, similarity/ambiguity thresholds, quantity safeguards, and UI-chrome rejection. Production item OCR is English; multilingual library fixtures do not prove multilingual host support. No instance-FIR detector or persistent correction learning was established.
- Catalog access is **JSON-first**, not GraphQL: `json.tarkov.dev` datasets keyed by mode/locale/source. Validated immutable snapshots distinguish Ready/Stale/Incomplete/Unavailable; failed refresh retains last good data. Personal progression is a read-only `api.tarkovtracker.org` token/progress integration, with per-mode protected keys and current-session authority.
- Values are gross Avg24h Flea versus the named best positive cash RUB trader; no fee/net calculation. Needs distinguish active/available/future/conditional and nullable FIR/non-FIR counts. The old sale resolver does not gate on instance FIR or market age; Blackgrid's stronger safety policy is an intentional divergence.
- User settings are versioned JSON beside the executable; catalogs and identity/activity-only history live under local app data; progress and corrections are transient. Pins carry coordinate-frame revisions, including a Labs migration. Tested behavior is valuable, but existing tests do not qualify the real display/DPI matrix, native map rendering, or end-to-end recognition quality.

Recent reference commits address startup CPU, screenshot-OCR lag, conservative needs, and map-log reliability. That supports early performance/session qualification; it does not define Blackgrid priorities.

### Evidence locators

Links below target the inspected sibling checkout; they are development evidence, not a runtime dependency. Line ranges name the relevant code, independent of editor link-fragment support. `SCANNING.md` contains historical prior art; its final **TarkovTracker scanner implementation authority** section supersedes conflicting earlier advice.

| Evidence | Reference locations |
| --- | --- |
| Product/composition | [README](../../../DotNet/TarkovTracker/README.md), [MainWindow](../../../DotNet/TarkovTracker/MainWindow.xaml.cs) 57–126, 213–300 |
| Map frames/floors | [MapGeometryService](../../../DotNet/TarkovTracker/Services/MapGeometryService.cs) 6–251; [maps.json](../../../DotNet/TarkovTracker/Config/maps.json), [map_levels.json](../../../DotNet/TarkovTracker/Config/map_levels.json) |
| Marker/render behavior | [MapDataService](../../../DotNet/TarkovTracker/Services/MapDataService.cs); [map-view.js](../../../DotNet/TarkovTracker/Assets/map-view.js) 99–805; MainWindow 2675–3038 |
| Actual capture/fallback | [InspectionCaptureService](../../../DotNet/TarkovTracker/Services/InspectionCaptureService.cs) 26–158, 230–259; MainWindow 700–805 |
| Vision and OCR | [RatEye Inspection](../../../DotNet/TarkovTracker/External/RatEye/RatEye/Processing/Inspection.cs) 228–555; [MultiInspection](../../../DotNet/TarkovTracker/External/RatEye/RatEye/Processing/MultiInspection.cs) 69–238; [host recognizer](../../../DotNet/TarkovTracker/Services/RatEyeInspectionRecognizer.cs) 38–151 |
| Matching/publication | [ScannerItemMatcher](../../../DotNet/TarkovTracker/Services/ScannerItemMatcher.cs) 13–301; [ScannerOrchestrator](../../../DotNet/TarkovTracker/Services/ScannerOrchestrator.cs); [LatestScanSnapshotReducer](../../../DotNet/TarkovTracker/Services/LatestScanSnapshotReducer.cs) |
| Data/decision/progress | [ScannerDataService](../../../DotNet/TarkovTracker/Services/ScannerDataService.cs); [ScannerDecisionResolver](../../../DotNet/TarkovTracker/Services/ScannerDecisionResolver.cs); [ScannerProgressService](../../../DotNet/TarkovTracker/Services/ScannerProgressService.cs); [Tracker progress service](../../../DotNet/TarkovTracker/Services/TarkovTrackerProgressService.cs) |
| Session/screenshot inputs | [TarkovLogMonitor](../../../DotNet/TarkovTracker/Services/TarkovLogMonitor.cs) 129–685; [ScreenshotExfilParser](../../../DotNet/TarkovTracker/Services/ScreenshotExfilParser.cs) 42–530; MainWindow 3480–3788 |
| User data/privacy | [UserSettingsStore](../../../DotNet/TarkovTracker/Services/UserSettingsStore.cs), [ScannerHistoryStore](../../../DotNet/TarkovTracker/Services/ScannerHistoryStore.cs), [MapPinMigrationService](../../../DotNet/TarkovTracker/Services/MapPinMigrationService.cs), [ProtectedTrackerKeyStore](../../../DotNet/TarkovTracker/Services/ProtectedTrackerKeyStore.cs) |
| Behavioral tests | [Host tests](../../../DotNet/TarkovTracker/tests/TarkovTracker.Tests), [RatEye tests/fixtures](../../../DotNet/TarkovTracker/External/RatEye/RatEyeTest), [current scanner authority](../../../DotNet/TarkovTracker/SCANNING.md) 1080–1222 |
| Provenance | [RatEye LICENSE](../../../DotNet/TarkovTracker/External/RatEye/LICENSE), [third-party notices](../../../DotNet/TarkovTracker/THIRD-PARTY-NOTICES.txt), [asset-tool provenance](../../../DotNet/TarkovTracker/tools/README.md) |

## 3. Target Architecture

**Recommendation:** Organize code around owned capabilities, not a stack of universal interfaces:

```text
Flutter shell / shared Material components
    Map view model                 Scanner view model
          ↓                              ↓
Dart map scene + session inputs    Dart scanner coordinator
          ↓                              ↓
geometry / floors / markers        vision worker → identity evidence
          ↘                            ↙
      catalog + progression + shared item-decision domain
                         ↓
          repositories: API adapters / SQLite / assets
                         ↓
       narrow Windows OS services + CV/OCR FFI libraries
```

- **Presentation:** widgets, screen composition, focused view models, formatting, accessible controls; no separate sale/needs logic in Map cards.
- **Application/state:** scanner lifecycle, session epochs/mode, map load generations, catalog/progress refresh, commands and immutable snapshots. The app composition root owns long-lived services; routes do not own scanning.
- **Domain:** pure Dart coordinates/floors, canonical item identity/matching, market facts, requirements and uncertainty-aware decisions. No Flutter widgets, Win32 handles, HTTP DTOs, or SQL in these rules.
- **Data:** explicit adapters for external JSON and Tracker contracts, local persistence and bundled assets. Validate a complete candidate before publishing; a failed refresh cannot replace working data with partial state.
- **Scanner/map:** capability modules with direct collaborators; isolate only expensive processing. Share item-decision projections and session context, not each other's UI state.
- **Platform:** input, foreground/geometry/DPI, pixels, hotkeys, protected credentials; generic CV/OCR primitives through FFI. Windows code does not decide which item was recognized or whether to keep it.

Interfaces are justified at replaceable boundaries and deterministic-test seams. Do not introduce a generic event bus, service locator, repository-per-table hierarchy, or abstractions for hypothetical platforms. Keep native handles and image buffers out of domain/UI models. Pure Dart domain portability is useful; non-Windows implementation is not phase scope.

## 4. Feature Migration Matrix

**Decision already made:** classification applies to useful behavior, not source-code copying. **Preserve** means reuse conceptually; **Reimplement** means retain behavior in Blackgrid; **Replace** discards the existing mechanism; **Remove** has no target implementation; **Defer** remains outside initial scope without weakening required Map/Scanner parity.

| Functionality | Classification | Blackgrid treatment |
| --- | --- | --- |
| Canonical item IDs, conservative needs, immutable snapshots, last-good refresh | Preserve | Retain semantics and testable invariants, with explicit uncertainty reasons |
| Coordinate conversion, heading, marker projection, pin frames | Reimplement | Pure Dart math and versioned frame contracts, verified against fixtures |
| Pan/zoom/reset/center, marker size/selection/details/categories/search/quest filters | Reimplement | Native Flutter scene and controls; no visual or gesture-code parity requirement |
| Extracts/transits/spawns/bosses/cultists/labels/hazards/polygons/switch links/BTR stops | Reimplement | Preserve real data and useful visibility/detail behavior; routes are not an established legacy feature |
| Manual/exclusive/combined floors and supported auto-floor bands | Reimplement | Typed floor state and compiled native artwork, including raster-backed maps |
| Custom pins, screenshot player position/direction, log map/mode selection, raid exfil highlights | Reimplement | Dart inputs and scene state with session/map generation guards; no continuous-position promise |
| WebView HTML/DOM/JavaScript/CSS bridge and duplicate document synchronization | Replace | Flutter rendering and Dart-owned scene state; delete bridge architecture from target |
| Mouse/hotkey, foreground/client/DPI/capture | Reimplement | Thin OS boundary, direct targeted pixels instead of full-client-then-crop fast path |
| OpenCV marker/title extraction, Tesseract OCR, normalization/fuzzy matching | Reimplement | Blackgrid-owned Dart pipeline using native primitives; same recognition approach until parity |
| C# RatEye/RatStash/OpenCvSharp runtime and assets staging | Replace | Qualified Dart CV bindings and own Tesseract FFI packaging; no old runtime shipped |
| Latest-wins, correction/search, recent history, accepted Map snapshot | Preserve / Reimplement | Keep distinct lifecycles and useful behavior; no unbounded OCR queue or fake new-scan events |
| Mode-scoped catalog, trader/pricing, quest/hideout/FIR needs, acquisition hints | Reimplement | Shared domain decision engine; facts stay distinct from advisory recommendation |
| tarkovtracker.org progression retrieval/protected per-mode token | Reimplement | Independent read-only connector; no Blackgrid account system or new backend |
| JSON source/coordinate contracts and cleared map art | Preserve selectively | Retain good semantics and legitimately reusable assets, not undocumented provenance assumptions |
| Legacy settings/pins/history files | Replace storage; migrate valuable records | Versioned SQLite/local preferences; explicit one-time importer, not ongoing old-app dependency |
| Overlay window/rendering/follow/opacity/hotkey/synchronization | Remove | No overlay or overlay-specific state, control, dependency, or acceptance work |
| Database browsing; full Progression overview/quest writes | Defer | No initial primary area; Scanner still shows item information and read-only need details |
| Mobile/web/macOS/Linux releases, Blackgrid accounts/backend/cloud sync/telemetry | Defer platforms; remove from this phase | No infrastructure or adapters built for hypothetical expansion |
| Unused inventory/icon recognition, automatic correction learning, new BTR routes | Defer unless separately requested | Library capability or mockup appearance is not established production parity scope |

## 5. Map Strategy

**Decision already made.** Preserve useful Map behavior in an independent Flutter/Dart implementation. Remove WebView/WebView2, the overlay, and overlay-only hotkeys/follow state. Inspected C# and JavaScript are prior art and a behavioral oracle, not release dependencies or a template to translate mechanically.

### Coordinates and floors

**Existing fact.** Projection has distinct frames: rotate game X/Z, apply the configured four-coefficient affine mapping with vertical-axis inversion, then normalize either the native-zoom/pixel-size tile frame or the projected artwork bounds. The bounds branch projects all four corners; `svgBounds` and game `bounds` are not interchangeable. Bounds-only maps have separate legacy rotation conventions. Off-artwork points are not clamped. Height Y is nullable; zero is known height. Quaternion-derived heading includes map rotation and a legacy chevron drawing offset. **Recommendation.** Give Dart explicit game, normalized-artwork, scene and viewport coordinate types; preserve position and displayed-heading outcomes without inheriting split host/JavaScript drawing offsets. Use the same forward/inverse geometry for artwork, markers, hazard polygons and pins. [M1]

**Existing fact.** Manual floors use actual direct SVG `<g id>` identifiers, not the root SVG ID or displayed floor number: examples include `Ground_Level`, Factory’s `Ground_Floor`/`Basement`, Reserve’s `Bunkers`, and Interchange’s `First_Floor` for its displayed second floor. Labs has `First_Level`, `Second_Level`, `Technical_Level`; Icebreaker’s root `svg1` is not a floor, and its 16 floor groups include default `Infirmary`. Only Labs and Icebreaker have configured automatic height bands. Preserve half-open intervals and overlap ordering by higher minimum/narrower upper boundary/source order. Unknown/invalid player height does not drive auto-selection; a known height in a gap selects no overlay and restores the base for exclusive maps. Marker height filtering separately leaves unknown/out-of-band heights under category control. Do not invent a universal floor classifier. Other maps allow base plus multiple overlays, with base dimming; Icebreaker allows at most one overlay and hides the base when that overlay is selected. [M1–M2]

**Existing test anchor:** rotation 90°, affine `[2,100,3,200]`, zoom 4 and pixel size 4096 project game `(X,Z)=(10,20)` to normalized `(0.234375,0.6640625)`. Use that independently expressed fixture alongside real map control points; normalizing against game bounds would produce the wrong tile result.
### Useful UI parity

**Decision already made, grounded in existing behavior.** Preserve these outcomes rather than the old layout or numerical zoom limits:

- Manual map selection; current-session log-driven map/mode selection; screenshot watch and **Read Latest**; visible status; pan, cursor-anchored zoom and reset-to-fit. **Recommendation:** expose an explicit center-on-player action that preserves zoom, using the latest valid player sample; do not recreate overlay-follow behavior.
- Marker selection and details: name/type, applicable faction, zone, categories, conditions and world coordinates; quest reference links; extract-linked switch highlighting. Existing selection does not automatically center the map.
- Independent category controls for PMC/Scav/shared extracts, transits, PMC/Scav/boss/cultist spawns, labels, quest items/objectives, hazards and hazard polygons, switches, supported BTR stops and custom pins; show/hide all and optional saved selection. Expose categories applicable to the chosen map; old checkbox defaults are not a parity obligation.
- Marker search: comma-separated, case-insensitive substring terms combined with OR across names/types/factions/quest metadata/categories/zones/conditions. Nonmatches, including hazard outlines, dim rather than disappear; category choices remain unchanged.
- Quest filters: quest-name substring AND case-insensitive exact trader; blank/`all` trader is unrestricted. These hide nonmatching quests independently of quest item/objective toggles. Keep clear-filter behavior and useful quest item icons.
- Manual floor visibility and height-aware marker/polygon visibility; unknown/out-of-band heights retain category-controlled visibility.
- Per-map normalized custom-pin add/remove, plus a session-only latest accepted Scanner snapshot card—not scan-derived map markers. Search/history/correction or catalog/progress refresh must not replace that card as a new accepted scan. [M3–M4]

### Native rendering and asset preparation

**Recommendation.** Use Flutter [InteractiveViewer](https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html) and TransformationController for the viewport. Transform world artwork and polygons together; project glyph anchors into a viewport overlay so icons, player heading and hit targets remain screen-sized. Inverse-transform pointer positions through [toScene](https://api.flutter.dev/flutter/widgets/TransformationController/toScene.html) for geometry selection and pin placement; apply active category/floor rules to drawing and hit testing alike. Keep high-rate viewport updates separate from application-state broadcasts. Use CustomPainter where marker density warrants it, with explicit hit testing and [semantics](https://api.flutter.dev/flutter/rendering/CustomPainter/semanticsBuilder.html), plus keyboard-operable selection and accessible details. Keyboard accessibility is a desired improvement, not established legacy parity.

**Recommendation.** Qualify [flutter_svg](https://pub.dev/packages/flutter_svg) with [vector_graphics](https://pub.dev/packages/vector_graphics) and its [compiler](https://pub.dev/packages/vector_graphics_compiler) against actual cleared artwork before choosing versions. Their documented precompilation path is relevant, but compiler support is not proof of map fidelity: CSS is not fully supported, and filters/some text attributes are unsupported. Do not select a geographic mapping library merely because the product displays maps; these are calibrated game/artwork frames, not established geographic datasets.

**Recommendation.** Build-time preprocessing should emit a layer manifest and reusable scenes sharing the original viewBox, origin, stacking order and coordinate revision. Preserve inherited styles/transforms, shared defs, `use`/other references, clips/masks and packaged image dependencies; do not extract groups as self-contained fragments without resolving dependencies. Check cross-layer opacity/compositing against the original complete artwork. Compile and cache reusable layer scenes, not every possible visibility combination; if an actual cross-layer dependency requires a composition unit, group only those dependent layers. Pan/zoom must not trigger SVG parsing or recompilation. [M2; package documentation above]

**Existing fact and recommendation.** Labs wraps raster tiles, Icebreaker wraps 16 full-floor PNG layers, and Labyrinth is raster-backed. Render these as positioned raster tiles/floor images in the same calibrated scene, preserving image extents, scaling and ordering; do not manufacture vector detail or assume SVG rendering solves raster memory/sharpness. Labs’ 2800-square and Icebreaker’s 4096-square viewBoxes must remain aligned with markers and floor hits. [M2]

**Recommendation.** Key compiled scenes by asset content/version, layer manifest and compiler version; include coordinate revision in scene compatibility. Decode active raster floors/visible tiles lazily and bound retained pictures/images; do not load every high-resolution floor on startup. Rasterized SVG zoom/DPI buckets are an optimization to benchmark, not the default. Pan/zoom changes transforms, not asset cache identity.

### Session evidence and saved pins

**Existing fact and recommendation.** Player position/heading is sampled from screenshot filenames, not continuous telemetry. Preserve map/mode log selection, replay/tail/deduplication and session-epoch protection. Fence screenshot/player/exfil work by current map generation and evidence ordering so late results cannot alter a newer map/session. Exfil-panel OCR supplies map-local extract/transit highlights; a missing panel is not an authoritative empty result. Its existing Windows.Media.Ocr backend differs from item Tesseract: qualify the replacement on panel fixtures. Woods/Streets BTR data establishes named stops only, not routes. [M5]

**Recommendation.** Persist pins as normalized artwork positions with map identity and coordinate revision. Preserve enabled right-click add inside the artwork and pin removal outcomes through accessible controls; keep pin geometry distinct from game coordinates. Explicitly migrate known Labs revision 0→1 through old-frame inversion/new-frame projection; reject unsupported transitions rather than silently relocating pins. [M6]

**Open question—prototype gate.** Can the candidate vector/raster pipeline faithfully render the real maps, compose legal floor states, and keep world geometry, screen-sized glyphs and hits aligned through pan/zoom, density and DPI changes? Answer before renderer commitment; no map performance measurements or new numerical targets are claimed here.

**Map source keys — existing facts, not milestone IDs.** Paths are relative to the separate local `TarkovTracker` reference checkout.

- **M1:** `Services/MapGeometryService.cs:8-251`; `Models/MapModels.cs:73-112`; `Config/maps.json:1-127`.
- **M2:** `Config/map_levels.json:1-182` (Labs/Icebreaker:107-137); `Maps/Labs.svg:1-252`; `Maps/Icebreaker.svg:1-50`; `Assets/map-view.js:626-777`. Labyrinth raster backing is recorded in the settled source assessment; validate its release asset during artwork qualification.
- **M3:** `MainWindow.xaml:46-84,99-170,364-708`; `Assets/map-view.js:10-129,196-302,440-777` (search/quest semantics:499-557); `MainWindow.xaml.cs:2057-2288,2657-2671`.
- **M4:** `Services/LatestScanSnapshotReducer.cs:4-31`; `MainWindow.xaml.cs:880-926`.
- **M5:** `MainWindow.xaml.cs:3497-3793`; `Services/TarkovLogMonitor.cs:340-417,504-567,611-623`; `Services/ScreenshotExfilParser.cs:40-105,377-530`; `Services/RaidExfilMatcher.cs:11-105`; `Config/tarkov_btr.json:1-24`; `Services/MapDataService.cs:45-48`.
- **M6:** `Services/MapPinMigrationService.cs:8-71`; `Assets/map-view.js:259-302`.

## 6. Scanner Strategy

**Decision already made — scope.** Preserve useful recognition and decision behavior through an independent Flutter/Dart implementation, not a transcription of C# or its tests. Retain OpenCV/Tesseract until scanner parity is qualified. Dart owns scheduling, normalization, matching, catalog/progression interpretation, advisory decisions and UI state; native libraries supply vision/OCR primitives. The reference is inspected prior art and a behavioral oracle, never a release runtime dependency. Overlay behavior is removed.

**Existing fact — recognition is a pipeline.** The reference searches grayscale pixels for an inspection marker using OpenCV `CCoeffNormed`, derives a scaled marker-relative title region, bounds/resizes it, applies grayscale/inverted threshold 120, then runs Tesseract. Current host configuration defaults to English, LSTM-only and RawLine; generalized RatEye language options do not establish full multilingual host support. Host FormKC normalization folds case/punctuation/spacing before normalized Levenshtein matching against catalog identities. Baseline gates are marker score .82, similarity .55, minimum normalized title length three, and runner-up margin .05; .03 applies only to the guarded secondary recognized-identity/quantity case. Preserve numeric-quantity safeguards and localized UI-chrome rejection. These are raw correlation/similarity scores, not calibrated identity probabilities. Sources, relative to the inspected reference root: `External/RatEye/RatEye/Processing/Inspection.cs:171-211,253-430`; `External/RatEye/RatEye/Config/Processing.cs:18-24`; `Services/Scanner/RatEyeRuntime.cs:184-200`; `Services/ScannerItemMatcher.cs:27-107,151-181,234-288`.

**Recommendation — complete decision path.** Carry vision evidence → title OCR → normalization → guarded candidate acceptance → mode-correct immutable catalog → progression needs and values → one shared safe decision authority. Automatic scans, manual identity selection and revisited results use that authority rather than parallel recommendation rules. Identity confidence must not imply knowledge of quest completion, item-instance FIR or price freshness. Retain separate known/potential quest and hideout needs, nullable FIR/non-FIR requirements and unknown Flea eligibility; absent progress is not zero remaining needs. Preserve gross Avg24h and a named best positive cash-RUB trader comparison, with deterministic trader ties; do not label those figures fee-adjusted proceeds. Existing value/decision behavior is in `Services/ScannerValueResolver.cs:12-76` and `Services/ScannerDecisionResolver.cs:35-91`.

**Decision already made — conservative advice and precedence.** A confirmed current need wins Keep; a known future need wins Keep for later. Uncertainty remains visible but does not erase a decisive keep reason. Otherwise, unknown FIR, progression relevance or market freshness produces Check / May Need, never confident Sell. This deliberately strengthens legacy behavior: its sale resolver does not gate on per-instance FIR or market age.

Evaluate the following rules in order against one mode-correct immutable resolution. An unaccepted identity remains a correction/no-match outcome, not an item recommendation or accepted Map event.

| Priority | Condition | Primary outcome |
| --- | --- | --- |
| 1 | Confirmed active/available quest need or known actionable hideout need | Keep; show need and any unrelated uncertainty |
| 2 | Known future need, with no higher-priority current need | Keep for later |
| 3 | Conditional need, unauthorized/unknown progression, unknown instance FIR, or stale/unknown decision-critical market facts | Check / May Need; name each missing fact |
| 4 | No need/uncertainty above; Flea explicitly allowed, required eligibility known, positive fresh gross Avg24h greater than the usable trader offer (or no usable trader) | Sell on Flea; label gross, not net |
| 5 | No higher-priority rule; a usable named positive cash trader offer with required facts sufficiently known | Sell to that trader; equal Flea/trader values choose trader, equal traders use deterministic ID order |
| 6 | No usable destination and no earlier keep/check outcome | Price Unavailable; retain factual unavailability/bans rather than inventing zero values |

An unknown Flea restriction is never treated as explicit permission. Sale advice requires the facts its destination/comparison depends on; identity confidence is not evidence of FIR or progression. Known keep advice is not invalidated merely by an irrelevant stale price.

**Recommendation — instance FIR evidence.** No instance-FIR detector is established. If explicit transient FIR input is provided, scope it to the current inspected instance/request, never the canonical item ID. Reset it to unknown on each new scan, correction/manual selection, history selection, or mode/session change—even when the item ID is unchanged. Capture that evidence in its accepted snapshot without transferring it to another decision context; no automatic FIR-detection requirement is introduced.

**Existing fact — fallback is production-active.** `MainWindow.xaml.cs:700-805` runs targeted capture/recognition and matcher acceptance, then full-client `RecognizeAllAndDispose` when the target is not accepted. Automatic fallback waits only until approximately 200 ms after enqueue, not 200 ms after targeted processing; a long targeted call can exceed that deadline. Unaccepted fallback evidence can become an explicit correction opportunity rather than an accepted identity.

**Recommendation — latest-wins coordination.** Use one active recognition request plus one replaceable pending request, retaining the reference’s bounded-work intent (`Services/ScannerOrchestrator.cs:141-263`). Request generations and session/mode epochs fence every publish and acceptance. Cancellation requests stop work where supported but cannot interrupt arbitrary synchronous native calls: never start another call on the same OCR handle, free borrowed buffers, or publish stale output merely because a Dart future timed out. Finish/release obsolete native work, then consume the newest pending request. Mode-neutral evidence may wait for a known mode; detected mode outranks manual fallback. Keep the worker and current result app-scoped across Map/Scanner navigation. Shutdown stops ingress, invalidates publication, then drains active native work before destroying handles.

**Recommendation — distinct state authority.** Separate current result, explicit transient correction, durable identity/activity history, and the session-only accepted Map snapshot. History selection uses its stored mode without changing live mode. Search, correction, history selection and catalog/progress refresh may change the displayed decision but must not masquerade as new scans. Only genuinely accepted automatic/manual scan events advance Map latest, monotonically and once per generation (`Services/ScannerOrchestrator.cs:251-344`; `Services/LatestScanSnapshotReducer.cs:4-39`; `MainWindow.xaml.cs:878-912`).

**Recommendation — advice aging.** Keep accepted identity, evidence, original decision and acceptance time immutable, but apply one shared advice-validity rule when presenting them. If decision-critical facts expire or the session/mode authority changes, show Check / May Need or clearly historical advice instead of a current confident Sell. This safety downgrade does not reprice the frozen snapshot, change its item/time, or emit a new accepted scan; refreshing data and viewing history cannot fake recency.

**Recommendation / open question — native worker qualification.** Evaluate [opencv_dart/dartcv4](https://github.com/rainyl/opencv_dart#supported-platforms), whose maintainers list Windows x64 support, with a minimal owned [Tesseract C-API](https://github.com/tesseract-ocr/tesseract/blob/main/include/tesseract/capi.h) binding, not mobile-only OCR bindings or a new recognition engine. Lock compatible versions only after a Windows release-bundle gate proves DLL/ABI loading, traineddata discovery, licenses, recognition quality and lifetimes. A warm dedicated worker off the UI isolate owns marker templates, OCR handles and reusable scratch resources. Transfer explicit buffer ownership, respect stride/channels, release returned Tesseract text, and avoid PNG round-trips or redundant full-frame copies. Do not promise zero-copy: Tesseract’s [SetImage contract](https://github.com/tesseract-ocr/tesseract/blob/main/include/tesseract/baseapi.h) copies raw image data internally.

**Decision already made / open question — latency and coverage.** Qualify targeted trigger-to-actionable decisions at ≤300 ms p95; when targeted recognition fails, visibly begin real fallback by approximately 300 ms and achieve ≤1.5 s p95 **total from the original trigger**, including queueing/capture/decision/presentation. A timeout label is not running fallback. If a noncancellable call blocks that start, the design fails qualification until its work is bounded appropriately. Automatic coverage must be baseline-or-better and false-positive identities no worse on the fixed corpus: fast rejection or removing difficult cases cannot satisfy latency by sacrificing recognition.

## 7. Windows Integration Strategy

**Recommendation — narrow OS boundary.** Build a small Windows plugin for input events, foreground/process identity, client coordinates/DPI, capture, hotkey registration and separately credential protection. C++ contains no matching, progression, pricing, recommendation or Scanner UI logic. CV/OCR remain separate FFI primitives. Never capture, run OCR or invoke Flutter UI work inside an input callback.

**Existing fact / recommendation — lightweight ingress.** The legacy mouse hook filters left-button-up by foreground window title and queues screen coordinates; later capture independently re-queries foreground/process, so the click and capture do not carry one coherent target (`Services/GlobalMouseHook.cs:63-70,98-150`; `MainWindow.xaml.cs:719-725,806-808`; `Services/InspectionCaptureService.cs:190-220`). Preserve lightweight ingress but attach event time, physical click coordinates and the foreground HWND/process identity available through cheap queries. Defer expensive validation to the capture service. Use a dedicated message loop and bounded event queue, return promptly and pass input onward. Microsoft’s [LowLevelMouseProc guidance](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelmouseproc) explicitly recommends handing work to a worker and immediately returning; timeout can silently remove the hook.

**Recommendation — coherent capture snapshot.** Before acquiring pixels, validate the event’s target identity, foreground status, client bounds mapped into physical desktop coordinates, current DPI and applicable capture region together. Recheck identity/geometry across acquisition; reject a changed, destroyed, reused or minimized target with a typed failure rather than scanning another window. HWND/title alone is insufficient. Maintain signed coordinates for monitors left/above the primary display; never cast negative origins to unsigned values. Establish a per-monitor-aware physical-pixel contract consistent with [Windows DPI guidance](https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows). OS DPI, Flutter logical pixels, game resolution and game UI recognition scale are distinct quantities, not interchangeable multipliers.

**Existing fact / recommendation — acquire the ROI first.** Current `Services/InspectionCaptureService.cs:110-185,230-267` copies visible full-client screen pixels into a bitmap, then crops; its native `PrintWindow` declaration is unused. Replace that acquisition pattern with direct OS capture of the small physical-pixel ROI first, then a larger/full-client fallback after unsuccessful guarded recognition. A desktop-GDI [BitBlt](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-bitblt) path is the initial visible-pixel candidate, subject to game/display-mode qualification. It is not hidden framebuffer access and makes no occluded/minimized-window promise. Fullscreen-like applicability, black/invalid frames and client visibility remain explicit prototype gates, not guaranteed support.

**Recommendation — immutable capture contract.** Return owned BGRA bytes with immutable width, height, stride, pixel format/orientation, signed desktop origin, target identity, capture timestamp and request/session identifiers, or a typed failure. A single documented release/ownership mechanism covers replacement, rejection and shutdown; buffers cannot be reused while native consumers hold them. Dart receives metadata/results without render-isolate pixel conversion. Validate clipping and dimensions explicitly rather than hiding a wrong ROI behind black padding.

Use correlated monotonic trigger/capture/publication timestamps for latency; UTC remains metadata for display and external-data age. Keep capture and pixel delivery off the render thread too: an asynchronous Dart method must not disguise a synchronous full-frame capture in the native UI-channel handler.

**Recommendation — manual trigger and credentials.** Use global [RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey) for the manual Scanner trigger, with the same target validation/pipeline. On registration conflict show the trigger as unavailable, explain the conflict and allow another binding; do not silently claim registration or revive overlay shortcuts. Unregister on rebinding/shutdown. Keep optional progression-token OS protection a separately narrow [DPAPI](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata) operation using user scope, not machine-wide protection; Dart owns mode/session permissions and persistence policy. Capture/input facilities receive no token authority.

## 8. Data and Persistence Strategy

**Recommendation:** Retain good source contracts at adapters; replace the old application's storage and object models. Use one Blackgrid-owned SQLite database through [Drift's native/background-isolate support](https://drift.simonbinder.eu/platforms/vm/), versioned migrations, and transactions. Locate durable state under the user's local application-data directory for Blackgrid, not beside the executable. Cache eviction must never delete user data.

| Storage | Contents and ownership |
| --- | --- |
| Bundled static assets | Cleared map artwork/tiles, floor manifests, coordinate metadata, marker data/icons, fonts, marker templates, and explicitly licensed/versioned OCR models; asset versions and coordinate-frame revisions travel together |
| SQLite — durable user records | Preferences relevant to behavior, selected map, opt-in saved marker filters, frame-versioned custom pins, identity/activity scan history, schema/migration metadata |
| SQLite — replaceable catalog cache | Mode/locale/source-keyed validated item/trader/task/hideout/craft/barter snapshots, fetch/source timestamps and status; replace atomically, retain last good on failure |
| Local preferences | Only small presentation choices if a preferences API adds value; do not create a second authority for the same setting already stored in SQLite |
| Separate protected credential storage | Per-mode user-supplied Tracker tokens through OS protection; no plaintext tokens in SQLite, settings, history, diagnostics, or fixtures |
| In-memory transient state | Active request/worker buffers, mode/session epoch, current result, correction text, selected marker, viewport, search, active raid highlights, latest accepted Map snapshot, and current-session progression authority |
| Evictable file cache | Downloaded item icons and derived artwork only when justified; key by content/source version, enforce a memory/disk budget, do not persist screenshots/OCR by default |

Keep the current JSON GET routes (`regular`, `pve`, `pvp-season`) and six required datasets behind a typed Dart gateway. Optional English identity data and tolerantly parsed source shapes remain adapter concerns; the app consumes canonical models. Validate a candidate off the render path, commit it, then publish one immutable snapshot. No mixed-mode or partial-generation result; no successful price display fabricated from missing values. Preserve source freshness/age and Ready/Stale/Incomplete/Unavailable semantics; the old one-hour cache window is a starting policy, not proof that every quote is current.

**Recommendation:** Freeze a separate, explicit market-freshness policy during baseline qualification, initially using the existing one-hour window where source timestamps support it. Unknown/future timestamps or stale decision-critical values force Check; a freshly downloaded envelope must not conceal an old quote. Display gross Avg24h and trader facts even when advice is Check. Fees/net proceeds, automated sale, and unobserved player/trader eligibility are not invented capabilities.

The retained read-only Tracker connector validates token permission, mode, timestamp, and current-session authority. A permitted same-session stale snapshot may preserve useful needs with a visible warning, but cannot establish fresh “no needs” for a confident Sell. Terminal auth/mode failures invalidate authority; unavailable progress is not an empty completed progression. No writable API calls or new account/signup workflow. Protect tokens with a narrow OS-backed key-store adapter; no automatic import of legacy credentials.

### Contract disposition

- **Retain:** canonical IDs; mode/locale/source keys; world coordinates and normalized pin frames; explicit nullable/unknown counts; requirement semantics; upstream JSON through validated adapters; cleared map art and manifests where suitable.
- **Migrate:** valuable legacy preferences, pins and coordinate revisions, and identity/activity history via an explicit one-time, read-only import. Convert supported old frames and commit atomically; unsupported versions must leave existing Blackgrid data untouched. Do not require the old app to run, mutate its files, or keep reading it afterward.
- **Replace:** C# DTO/RatStash projections, beside-executable settings, browser serialization/document IDs, native dependency manifests specific to .NET, and layered JSON backup machinery where SQLite transactions/migrations now own durability.
- **Discard rather than migrate:** reconstructible catalog/icon caches, overlay settings, old native runtime paths, transient OCR/corrections/results, and claimed persistent progress that the reference never had.

History stores item identity, mode, source and activity only. Reopening a row re-resolves current facts; it is not a historical price/progress audit. Whether raw upstream JSON must also be retained is a prototype/storage-size question; default to one persisted catalog representation, not duplicate authoritative JSON and SQL caches.

## 9. State-Management Strategy

**Recommendation:** Start with focused Flutter SDK `ChangeNotifier` view models and `ValueNotifier` for small immutable presentation values, explicit constructor injection, and an app-scope composition root. This follows [Flutter's view-model/repository separation](https://docs.flutter.dev/app-architecture/guide); it does not put domain logic into notifiers.

| Approach | Material tradeoff | Choice |
| --- | --- | --- |
| SDK notifiers | Minimal dependency and direct test injection; async status, refresh ownership and disposal must be explicit | Chosen for focused presentation models, not a global broadcast bus |
| [Riverpod](https://riverpod.dev/docs/concepts2/auto_dispose) | Strong dependency composition, async caching/test overrides, optional code generation; lifetimes/invalidation still require care | Viable alternative, not necessary to own the present bounded service graph |
| [BLoC/Cubit](https://bloclibrary.dev/flutter-bloc-concepts/) | Explicit event/state workflows; adds event/stream conventions and ceremony | Not the default; scanner transitions already belong to its own coordinator |

Long-lived catalog, progress and scanner services survive navigation. Async states carry data, source generation, loading/error/staleness together; fresh failure cannot erase previous usable data. Repositories and orchestrators are directly testable without widget trees or a framework container. Framework disposal is not request cancellation.

Map transform updates listen directly to `TransformationController` or a repaint listenable; do not notify all app listeners on every pan/zoom tick. Recompute filtered scene data when its real inputs change, not on every transform. Mode, catalog/progress generation and explicit commands invalidate the relevant derived projections; avoid a catch-all global notifier and hidden mutable singletons. Persist settings through their repository; presentation memory is not the durable source.

## 10. UI Architecture

**Decision already made:** One dark Material 3 design system serves Map and Scanner. Use charcoal/near-black surfaces, restrained gold for selection/primary emphasis, green for healthy/ready/success, deliberate spacing/type hierarchy, and readable desktop controls. Color never carries status alone. No military ornament, scanlines, fake terminal UI, tiny text, or border on every component.

**Recommendation:** A two-area desktop shell retains route state and keeps scanner work running while Map is open. Shared components cover status/staleness, item decision summaries, explanatory need rows, filters/chips, search, details, error/empty/loading states and supporting configuration dialogs. “Blackgrid” is the product name; no game name in application branding. The two PNG mockups are references for hierarchy/arrangement, not pixel targets, invented metrics, AI capability, Tools tabs, or overlay controls.

- **Scanner:** verdict and identified item first; explicit uncertainty reason next; gross/per-slot values and named trader; confirmed versus potential needs with FIR/non-FIR counts; correction/search/history available without displacing current scan. Capture preview, OCR text and candidate scores belong in an optional diagnostic disclosure, not the raid-time default.
- **Map:** artwork gets the main canvas; compact controls for map/floors/visibility/search and an accessible selection/details region. A compact genuine latest-accepted-scan card uses the same decision authority; it never steals keyboard focus or presents history viewing as a new scan.
- **Configuration:** scanner enablement, hotkey, token/mode, source folders, saved filters and supported map preferences through dialogs/inline controls. No third primary Settings area in this phase.

Verify keyboard navigation, visible focus, high-DPI/text scaling, minimum usable marker targets, narrow/compact windows, and status readability on the actual Windows surface. Follow normal Material desktop interaction conventions; visual polish is evaluated through real user tasks, not screenshot imitation.

## 11. Migration Plan

**Recommendation:** Use validation gates, not a giant rewrite or date commitments. Foundations are thin but functional; do not spend months completing every model or an empty shell before proving the risky paths. Settings/schema safety begin early, not as a late bolt-on.

| Milestone | Demonstrable result | Validation gate |
| --- | --- | --- |
| **M0 — reference qualification and provenance** | Versioned oracle/fixture and performance reports, representative map control points, asset/dependency rights inventory | Record actual reference trigger-to-result baseline on a named Windows setup; independently label screenshot item truth/negative cases; separate tested behavior from gaps; obtain reuse permissions or replacement sources before assets enter a release |
| **M1 — shared shell and decision foundation** | Two-area Material shell displays real catalog/manual-selected item decisions and supporting configuration; local durable records survive restart | Mode-scoped JSON projection and read-only progress boundary; pure Dart keep/later/check/sale truth table, FIR/unknown safety, gross values and need counts; transaction/migration fixtures; no duplicated Map/Scanner advice |
| **M2 — capture/recognition proof** | Real Windows cursor-triggered direct ROI produces marker/title/OCR/item evidence, with full-viewport fallback and a responsive UI | Package OpenCV/Tesseract with no system-install dependency; compare fixed positive/negative corpus; instrument allocations/copies and stage timings; prove physical pixels, foreground race handling, and initial DPI profiles; bound uninterruptible calls |
| **M3 — native map proof** | Representative vector multilevel map, Labs tiled art, and Icebreaker raster floor scene pan/zoom/select natively | Common-frame alignment, defs/styles/image resolution, overlay/exclusive floors, screen-size markers/hit targets and actual Windows frame profiles; no WebView fallback; prototype results determine renderer/preprocessing choice |
| **M4 — complete raid-time Scanner slice** | Mouse/hotkey → pixels → recognition → mode/catalog/progress → conservative decision → correction/history, usable while Map is open | Latest-wins bursts and late completions; unknown/detected/manual mode transitions; safe current-session progress; accepted event boundaries; targeted ≤300 ms p95, visible fallback near 300 ms, ≤1.5 s p95 total; baseline-or-better coverage with no worse false positives |
| **M5 — complete useful native Map** | All supported map assets and marker behaviors, floors, pins, log selection, screenshot player samples and raid exfil/transit highlights | Geometry/landmark goldens, all marker categories and search/quest semantics, pin frame/migration checks, floor boundaries, map-switch/load/OCR races, rendering/performance and accessible selection; Scanner integration remains one product |
| **M6 — replacement qualification** | Independent release bundle works on a clean Windows machine with durable local state and optional progression integration | Full display matrix and mixed-monitor transitions, offline/refresh/auth failures, restart/import/history correctness, packaged DLL/model/artwork notices, structured raid tasks, all definition-of-done gates |

M2 and M3 can proceed independently after M1's shared contracts; neither depends on a completed full subsystem. Scanner risk is proved early because it carries the primary player outcome. Full Map completion follows its proof rather than preceding scanner feasibility. M4 is a useful checkpoint, not authorization to claim full replacement before M5/M6.

Keep reference comparison tooling separate from Blackgrid's release. Production builds/tests must not need the old checkout or .NET: normal regressions consume cleared, frozen fixtures and recorded expected behavior. When a gate fails, fix the cause or choose a qualified implementation of the same behavior; do not silently drop a map, resolution, fallback, or recognition obligation.

## 12. Risks and Prototypes

Rank reflects consequence and uncertainty, not measured probabilities. All prototypes below are required proposed proofs, not results obtained during this strategy run.

| Rank | Risk | Smallest useful proof and pass condition |
| --- | --- | --- |
| **1** | Item recognition loses coverage or accepts wrong identities; direct ROI/DPI differs from the reference | End-to-end fixed screenshot plus live capture corpus at requested resolutions/scales; expected item IDs/negative outcomes, numeric/chrome cases; coverage ≥ baseline and false positives ≤ baseline without hiding corrections |
| **2** | FFI packaging, buffer lifetime or long native calls block the UI/break latency | Clean-machine Windows x64 release with chosen OpenCV/Tesseract/Leptonica/models; warmed worker repeated scan/cancel/shutdown; no missing DLLs, use-after-free or growing native memory; measured stage/tail latency fits goals |
| **3** | Asset/source rights prevent distribution | Per-artwork/template/icon/model/binary provenance and notice inventory before reuse; cleared permission or independent replacement for every shipped artifact |
| **4** | Native SVG/layer/raster composition is wrong or slow | Vector map with shared defs/styles, Labs tiles, Icebreaker exclusive raster floors; common-frame goldens, level switches, dense markers at zoom extremes/DPI; profiled render and memory budgets |
| **5** | Incorrect trust/freshness/progression produces unsafe Sell | Explicit unknown FIR, missing/stale/wrong-mode progress, stale/missing quotes, bans, paired objectives and hideout observations; zero confident Sell outcomes on safety fixtures, useful positive Keep/sale cases remain |
| **6** | Input/mode/map/refresh races publish stale state | Controlled worker and API barriers plus live rapid clicks/focus/map/mode switches; no old generation commits, one active/one pending bound, correct accepted-event separation |
| **7** | Persistence/import corrupts pins/history or exposes credentials | Versioned SQLite migration/import interruption and unsupported-frame cases; restart and clear-cache checks; durable user records intact, no plaintext secrets or accidental screenshot/OCR storage |

**Existing fact:** RatEye's inspected license says “Based on Elastic License 2.0” and adds an explicit commercial-distribution prohibition, including larger software packages; it is not evidence of unmodified standard ELv2. Map credits/public availability are not redistribution clearance; Icebreaker provenance cites CC BY-NC-SA 4.0. This is a rights-review gate, not a legal determination. Do not ship the old RatEye/RatStash/C# runtime or assume copied fixture/artwork assets are cleared.

**Open questions:** exact package versions/native build strategy; real asset/compiler compatibility and composite-layer dependencies; end-to-end performance on the qualification machine; reliable per-instance FIR evidence beyond explicit user input; source timestamp quality for the freshness policy; and the best qualified exfil-panel OCR backend. Resolve these through the gates above without replacing the established item OpenCV/Tesseract approach for novelty. The reference exfil parser uses Windows OCR, separately from item Tesseract; compare panel fixtures before choosing whether Tesseract can own that profile or a narrow Windows OCR engine adapter is necessary.

## 13. Testing and Parity Plan

### Agent testing boundary

**Decision already made:** [Repository agent instructions](../AGENTS.md) govern every milestone, prototype, benchmark, and replacement check in this document. AI agents must never launch, restart, drive, or verify the app or reference companion while Escape from Tarkov is running, nor automate tests that require a running game. Game-dependent feature testing belongs 100% to the user.

Written tests and fixture/mocked/offline checks are allowed. Agents may launch and verify the app only after confirming the game is not running; otherwise do not launch it. When a confirmation requires the game, stop before that verification and ask the user to perform it or explicitly approve skipping it. Approval to skip does not authorize agent-performed live-game testing. Record user results as user-performed and skipped checks as unverified, never passed. This boundary overrides general smoke/UI/runtime-verification requirements.

### Oracle discipline

**Recommendation:** Freeze the inspected reference revision, relevant processing/model/asset versions, catalog snapshots, viewport/DPI context and expected outputs. Use a private qualification harness where permitted to capture old results; ordinary Blackgrid tests use independent fixtures and do not link the old app. Old output is evidence, not truth when demonstrably wrong: independently label item identity and map landmarks, and record intentional safety divergences such as stale/unknown inputs downgrading Sell.

For the same screenshot compare marker location/score, title crop/preprocessed image, OCR text, candidate scores, accepted item ID, and final decision. Exact OCR text/score differences are diagnostic; useful identity, rejection and safe decision behavior are the gate, not bit-identical native engine output. For the same game coordinate compare normalized position, heading and floor. Pair real positive cases with empty/chrome/ambiguous/occluded negatives, not only happy-path item images.

### Existing evidence and new coverage

| Area | Existing reference evidence | Blackgrid regression and live qualification |
| --- | --- | --- |
| Map math/placement | `MapGeometryTests` covers rotation, affine/tile frames, invalid/off-map points, bearing, nullable height and bands | Independently express those behaviors; actual landmark anchors for every map, pin projection/inverse/frame migrations, normalized scene placement across artwork dimensions |
| Floors/assets/rendering | Config/artwork and offline asset tools; geometry band tests, no native renderer proof | SVG groups/defs/styles/clips/transforms/reference images, base+overlay/exclusive scenes, half-open/gap/overlap floors, unknown height vs zero, manual/auto behavior, real hit/alignment/frame checks |
| Vision/title/OCR | RatEye FHD/QHD/UHD assets and CV/regression tests; several fixture oracles are only non-null/mechanical checks | Cleared corpus with independently expected item IDs/negatives, marker/ROI confidence boundaries, preprocessing variants, UI-chrome rejection, quantity-bearing ambiguous names; real end-to-end host results |
| Matching/acceptance | `ScannerItemMatcherTests`, recognizer tests | Marker/similarity boundaries, runner-up margins, guarded secondary evidence, Unicode/space normalization, numeric ambiguity; no self-confirming candidate shortcuts |
| Targeted/fallback | Capture fake-platform and multi-inspection mechanics; active production caller | Direct physical ROI versus full viewport, clipping/padding/channel stride, fallback trigger/ranking, multiple windows, budget/visible phase timing; no full-client copy on fast path |
| Cancellation/lifecycle | Orchestrator/state/mode/reducer/generation tests | Bursts with ignored cancellation, one pending replacement, noninterruptible native stages, stop/dispose, map/mode/session change, late catalog/progress/icon/asset completions, accepted once |
| Catalog/values/needs | Data, decision and projection tests | Mode/source/locale isolation, required/optional datasets, last-good refresh, bans/unknown prices/gross ties/per-slot dimensions, freshness, authorization, faction/gates, paired find/give, FIR/non-FIR and unknown hideout counts |
| Advice safety/precedence | Shared resolver's need-first rules; no instance-FIR or market-age sale gate | Confirmed current need with stale price still Keep; future need still later; unknown safety facts without a decisive need yield Check; expired accepted advice cannot remain a current confident Sell; FIR evidence resets even for a new instance of the same canonical ID |
| Correction/history | Orchestrator/history tests | Explicit correction without false new-scan Map events, old-result retention on failure, identity/activity-only durability, recorded-mode rehydration without changing live mode, failed save visible but scan retained |
| Session/map inputs | Mode/log aliases and stale map-OCR tests; exfil tests only pixel helpers | Partial log lines, rotation/truncation/missing-file/session epochs; sampled filename XYZ/quaternion; actual panel crops/OCR/name matches, per-map exfil/transit highlight, stale completion rejection |
| Persistence/security | Settings/history recovery and protected-key tests | SQLite migrations/import rollback, unsupported frames, restart/clear-cache isolation, protected per-mode tokens, no tokens/prices/progress/OCR/images in history or unintended diagnostics |

Do not copy incidental label/default/wiring/non-null tests into the rewrite. Tests must detect plausible wrong identities, unsafe recommendations, mislocated markers, stale publication, incorrect counts or lost user state. Add failing-before/passing-after regressions for discovered bugs where practical. UI acceptance exercises real Windows rendering and interaction, not only widget goldens.

### Display and timing matrix

- Deterministic physical/logical geometry and recognition fixtures cover **1920×1080, 2560×1440, 3440×1440, 3840×2160 × 100%, 125%, 150%, 200%** — all 16 resolution/scaling cells.
- Native qualification covers signed negative monitor origins, left/top secondary displays, mixed per-monitor scales, window movement/DPI changes, clipping at client/desktop edges, and foreground/cursor races. Exercise windowed, borderless and fullscreen-like modes where visible-screen capture is available. Unsupported/occluded/minimized capture must fail explicitly, not produce plausible false evidence.
- Record reference and Blackgrid on the same named Windows hardware/build, game/UI settings, viewport, scaling, warmed/cold state and corpus. Measure the complete original-trigger-to-actionable-render path, not OCR-only elapsed time; record fallback start and total latency, scan source, stage timings, success/coverage and false matches together. Do not report only fast successes while hiding misses.
- Initial goals are **≤300 ms p95 targeted**, fallback visibly underway by **approximately 300 ms**, and **≤1.5 s p95 total**. Rapid interaction cannot create an ever-growing stale queue. Unknown-item rejection is not a successful actionable-item result; an identified item with an honest Check decision is useful advice but cannot conceal reduced recognition coverage.
- Profile actual map build/raster frame times, dense-marker filtering, asset decode/switch cost, startup and worker/SQLite/native memory. Fix explicit budgets from the named-machine prototype before full renderer investment; no invented map-FPS or startup pass claims in this document.

Metric evidence remains local: fixture reports, performance traces and structured raid-time play checks. No analytics or telemetry infrastructure.

## 14. Definition of Done

Blackgrid can replace the current application only when:

1. **Independent product:** a complete Windows release bundle runs without .NET, WPF, WebView2, the old checkout/application, or old RatEye/RatStash runtime; required native DLLs/models/assets and notices are packaged and located reliably on a clean machine.
2. **Useful Map parity:** all supported map frames/artwork and existing useful marker, filter/search/quest/detail, pin, pan/zoom/reset/center, player sample/direction, floor and raid-highlight behaviors work natively. Auto floors remain limited to supported authoritative bands; no unproven BTR route or continuous-tracking claim.
3. **Useful Scanner parity:** real automatic/manual triggers, targeted recognition, genuine larger fallback, matching/correction/history, modes, prices and read-only quest/hideout needs work end to end while either primary area is open. Coverage is baseline-or-better and false-positive identity matches no worse on the fixed qualified corpus.
4. **Safe shared decisions:** Map and Scanner agree on one decision projection; unknown/stale decision-critical FIR/progress/market facts never produce confident Sell, zero placeholders or fabricated “no needs”. Known positive cases still yield useful Keep/later/sale advice; fees are not misrepresented as net proceeds.
5. **Correct concurrency and displays:** no stale commit after supersession/map/mode/session change/shutdown; native callbacks remain light, expensive work stays off rendering, native resources remain bounded; the requested display matrix and mixed-monitor/capture cases are qualified.
6. **Measured performance and usability:** reference baseline recorded; targeted/fallback latency goals, useful recognition coverage and local play-check interaction goals met; dense maps and scan work coexist responsively on the named qualification setup.
7. **Durable local state:** settings/pins/history survive restart and supported explicit imports/migrations without silent loss; failed refresh preserves last-good data; protected tokens and transient progress/OCR/screenshots respect the stated boundaries.
8. **Coherent actual UI:** both primary areas use the shared Material system, readable status/uncertainty and usable pointer/keyboard/high-DPI behavior. Mockup imitation is not acceptance.
9. **Honest scope:** no overlay, WebView map, Blackgrid backend/accounts/cloud/telemetry, other-platform release requirement, Database browsing, full progression overview or progression writes. No unresolved required parity, packaging, provenance or display gate hidden as later work.

Implementation checkpoints are not replacement completion. Any proposed reduction of these obligations needs an explicit user decision; benchmark/prototype failure does not authorize silent scope cuts.
