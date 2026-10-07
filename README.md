# blackgrid

Independent **Windows desktop only** tactical companion. M1 provides real mode-scoped catalog search, manual item inspection, conservative Keep/Later/Check/Sell decisions, protected read-only Tracker access, durable identity history and custom pins, and explicit legacy JSON import.

Primary navigation is **Map and Scanner only**. The native Map workspace renders all 13 supported maps (Factory, Customs, Woods, Shoreline, Interchange, Labs, Reserve, Lighthouse, Streets of Tarkov, Ground Zero, Terminal, Icebreaker and Labyrinth) from a locally bundled, versioned pack. Map owns its log/session inputs, saved-screenshot player samples, marker queries and saved-panel exfil/transit OCR; it does not use Scanner capture or recognition. Empty or unavailable evidence is shown honestly rather than replaced with demonstration data. There is no overlay, Database browser, continuous position tracking, game-memory inspection or progression-write control.

The visual hierarchy follows [the Map and Scanner references](docs/vision/): compact shared navigation, near-black green surfaces, muted gold panel rules, Scanner's three columns and split lower evidence, and Map's broad workspace with a scrollable right rail. These images are design references, not shipped artwork or capture evidence. Historical native-map evidence remains in [M3 status](docs/qualification/m3/STATUS.md); current independent-Map delivery and verification state is recorded in [M5 status](docs/qualification/m5/STATUS.md). M3 verification waivers do not qualify M5. Implemented rendering and offline package integrity do not establish live-game parity.

## Prerequisites

- Windows 11, Git, and [mise](https://mise.jdx.dev/).
- Visual Studio with **Desktop development with C++**, its CMake tools, and a Windows SDK. See [Flutter's Windows setup](https://docs.flutter.dev/platform-integration/windows/setup).
- Windows Developer Mode when native plugins require build-time symlinks.

Flutter **3.47.6** (including Dart **3.13.5**) and git-cliff **2.14.2** are pinned in `mise.toml`. No global Flutter installation is required.

## Setup and run

```text
mise trust mise.toml
mise install
mise exec -- flutter pub get
mise exec -- flutter doctor -v
# Close Escape from Tarkov before any agent-driven app launch or UI verification.
mise exec -- flutter run -d windows
```

Warnings about unselected Android or web tooling do not block Windows development. Do not enable additional platforms just to silence those warnings.

Build the Windows release bundle:

```text
mise exec -- flutter build windows
```

The executable is `build/windows/x64/runner/Release/blackgrid.exe`; distribute the complete release directory, not just the executable.

## Development

| Command | Purpose |
| --- | --- |
| `mise run analyze` | Flutter static analysis |
| `mise run test` | Fast development tests; excludes `qualification` |
| `mise run test:qualification` | Expensive offline map-pack and reference-evidence qualification |
| `mise run test:all` | Complete Flutter test suite, including qualification |
| `mise run format` | Format Dart source |
| `mise run format:check` | Check formatting without modifying files |
| `mise run changelog` | Regenerate `CHANGELOG.md` from local Git history, offline |
| `mise run release-notes` | Print changelog entries without the project heading |

The full offline suite includes independently authored synthetic wire fixtures, real SQLite transactions/reopen/migrations, credential replacement failure injection, authority fencing, conservative decisions, legacy revision/frame validation, and shared UI state/layout checks at both reference sizes and 100/125/150% text scaling. Production composition uses actual HTTP, SQLite and Windows DPAPI boundaries, not these test fixtures.

During normal implementation, run `mise run analyze`, `mise run test` and directly affected test files. UI-only changes need the relevant widget/UI tests, not artwork-pack rebuilds. Before completing substantial map-pipeline changes, also run `mise run test:qualification`. Final acceptance/before merge uses `mise run test:all`, plus Release/native acceptance gates when the change requires them; do not repeat full qualification after each small edit.

The `qualification` tag isolates filesystem-heavy preparation, determinism, production-grid inventory, corruption and promotion checks in `test/maps/map_preparation_qualification_test.dart`, plus expensive reference-freeze collector and fixture-closure acceptance tests. Ordinary map geometry, floors, controllers, placement controls, widgets and M0 logic tests remain in the fast suite. Both workflows are deterministic and offline. Map qualification reuses read-only inputs and gives mutation cases private small packs bound to their own frozen calibration; current-production rebuilds still require all 19 raster floors and every 16×16 tile grid.

For agents, the equivalent mounted `run_tests` arguments are `exclude-tags: ["qualification"]`, `tags: ["qualification"]`, and no tag filter, respectively.

For agent verification, use the mounted official Dart MCP `run_tests`, `analyze_files` and `dart_format` tools; do not substitute shell test commands. Run expensive checks serially after authoring. Before each real Windows launch/restart or UI verification, freshly establish that Escape from Tarkov is closed. Never focus, inspect, capture, hook or read memory from the game or anti-cheat.

### Test runtime and fixture writes

The supplied pre-refactor baseline was 6m55s for the full suite, 60s for two deterministic rebuilds, 43s for generation preservation and roughly 27s per promotion case. It was not rerun.

Observed runner JSON elapsed times on Windows; suite setup is included, and suites run concurrently:

| Check | Passing tests | Elapsed |
| --- | ---: | ---: |
| Development (`--exclude-tags qualification`) | 497 | 13.1s |
| Dedicated qualification (`--tags qualification`) | 36 | 97.3s |
| Complete suite | 533 | 99.0s |
| Map preparation qualification within the complete run | 8 | 22.4s |
| Focused map preparation qualification after review | 8 | 14.1s |

All checks had zero failures or skips. The dedicated qualification run preceded strengthening the normalization test to invoke the real normalize → compile path; the complete run verified that path and every qualification case. After review, additional corrupt-published-version assertions passed in the focused map qualification rerun; no production code changed after the complete run. Final analysis was clean. Test-runner times exclude dependency resolution and MCP transport overhead.

The remaining qualification bottleneck is `m0_collector_test.dart`: 96.1s in the final run, including a 14.8s record/sidecar alias-safety case. These real Git/PowerShell/Dart pipeline checks remain intact and opt-in; fixture-closure checks also remain qualification, not normal development work.

Map qualification now materializes one 4,864-PNG raw fixture per run instead of eight (38,912 PNGs). Narrow mutation tests copy 38-file prepared packs, not raw tile trees. The two independent complete rebuilds and real normalization reuse the raw fixture read-only; current-production tile requirements and independent promotion validation are unchanged.

### Database generation

Regenerate the committed Drift implementation and migration helpers after intentional schema changes:

```text
mise exec -- dart run build_runner build
mise exec -- dart run drift_dev schema dump lib/data/database.dart drift_schemas/
mise exec -- dart run drift_dev schema generate drift_schemas test/data/generated
```

`drift_schemas/` freezes schema versions. Version 1 defines initial local settings/pins/activity/catalog tables; version 2 adds the once-only import ledger. A newer database is refused without reset or downgrade.

The real unauthenticated catalog qualification uses the same production adapter and a temporary real SQLite database:

```text
mise exec -- dart run tool/m1/catalog_smoke.dart
```

`integration_test/m1_windows_smoke_test.dart` exercises actual current-user DPAPI and native replacement failure, a real catalog, shared UI decisions and SQLite reopen in a run-owned directory. Run it through the official Dart MCP runner on the Windows device only after the game-closure gate. Its synthetic credential verifies protection only; it is never sent to Tracker. Authenticated Tracker verification requires a user-supplied credential and is not implied by fixture tests or the catalog smoke.

## Data, authority and privacy

- First launch leaves mode **Unknown**. Select PvP, PvE or Seasonal explicitly; refresh loads all six mandatory datasets before committing and publishing one immutable revision. English dictionaries are optional. Failed refresh retains the last complete mode-specific snapshot.
- Overlapping mode choices invalidate both catalog and progress authority before their asynchronous reads complete. Returning to a mode can join its already-running refresh without downloading or committing twice; only the current requested context publishes the result.
- Every catalog, dictionary and Tracker GET has a 30-second header-and-body deadline and signals request abortion on expiry. Transport failure releases the manual refresh action and retains last-good data; there are no automatic retries. Tracker `Retry-After` accepts delta seconds and HTTP dates, including zero or past deadlines; missing or malformed values use a finite 60-second cooldown before another explicit refresh is allowed.
- Recommendations are conservative: **Keep → Keep for later → Check → Flea → Trader → Price unavailable**. Missing/stale relevance, mode/FIR ambiguity and unsupported gates cannot silently become confident Sell. Flea additionally requires eligible fresh positive gross value **greater than** a usable named cash-RUB trader offer (or no usable trader). Equal Flea/trader values choose the trader; equal trader offers use stable canonical trader ID order. Prices are gross RUB, not fee-adjusted net proceeds.
- Catalog authority is 24 hours only when its six source timestamps are known and coherent; download time is not source freshness. A Flea quote has its own one-hour evidence window. Tracker progression is session-memory only, with a 15-minute authority window. Manual refresh and visible rate-limit cooldown do not schedule automatic requests.
- The public catalog envelopes observed on 2026-10-06 have no source timestamps. A successful refresh therefore remains labeled stale/Unknown rather than claiming current authority. Shared objective IDs across distinct tasks retain every owner; flat objective progress cannot resolve an ambiguous requirement unless its owning task is authoritatively completed or failed.
- Missing or null hideout station/trader/skill prerequisite arrays remain unresolved rather than proving an actionable requirement. A successful unchanged-content refresh renews durable observation metadata transactionally without inventing source freshness.
- `%LOCALAPPDATA%/Blackgrid/blackgrid.sqlite` holds local settings, versioned pins, complete catalog snapshots and identity-only activity. History contains canonical item ID, stored mode, source, UTC observation and revision—not FIR, prices, needs, token, account or progress payloads. Opening history does not switch the live mode.
- History's Source authority panel uses the inspected mode's snapshot and status only. A stored-mode snapshot is labeled stale until that same mode has live refresh authority; a missing stored snapshot cannot borrow another live mode's records.
- Per-mode files under `%LOCALAPPDATA%/Blackgrid/credentials/` contain **current-user Windows DPAPI ciphertext**, not plaintext tokens. Replacement is atomic; protection/replacement failure preserves the previous credential and never falls back to plaintext. Removal affects only the selected mode. Backing up the ciphertext does not make it portable to another Windows user.
- Tracker is opt-in, read-only and GET-only on `api.tarkovtracker.org`; `PVP_`, `PVE_` and `SZN_` credentials are mode-scoped. No credentials, account identities, response bodies or personal progress are logged or persisted. No telemetry, Blackgrid account or backend is present.
- FIR is a transient manual inspection fact. It resets on a new identity, mode, history inspection or authority context—not merely typing a query or changing Map/Scanner tabs. Restart restores durable data, not a selected item/FIR/progress/accepted scan.

## Native maps

- Drag to pan, use the mouse wheel for cursor-anchored zoom, or use the zoom and **Fit map** controls. The focused viewport also supports arrow-key panning, Home to fit, plus/minus (including numpad) to zoom, C to center on a sampled player without changing zoom, N to add a pin, Enter to browse, Delete to remove the selected pin, and Escape to clear details.
- Floor controls use source-specific layers. Interchange and Labs retain base-plus-overlay composition; Icebreaker selects one replacement floor and restores Infirmary when that selection is cleared.
- Select a visible marker for its source details, or open **Markers** and use Tab/Enter to select through the keyboard-accessible list. Drawing and selection share floor/filter visibility. Map interaction never produces an accepted scan.
- **Add pin** and viewport right-click use the shared inverse geometry. Existing pin frames/revisions and finite off-artwork coordinates remain intact.
- Runtime artwork uses bundled assets, cached vector components and lazily decoded visible tiles/active raster floors. Navigation does not download artwork or parse SVG on every gesture.
- Marker search dims nonmatches rather than making visible markers unselectable. Category/floor visibility still controls painting, pointer hits and keyboard-accessible targets; quest filters use prepared quest identities and the shared read-only progression facts.
- Configure **Game log directory** and **Screenshot directory** in Settings. **Follow game logs** chooses detected map/mode without overwriting the saved manual selection. With follow disabled, watched evidence from a different detected map cannot publish player samples or raid highlights onto the manually selected map.
- **Read Latest** explicitly reads a stable saved image. Filename metadata supplies position and heading; OCR does not. Saved evidence without a confirmed raid/map association is visibly assumed, and its timestamp is not refreshed merely by rereading it. Automatic floors require supported authoritative height bands.
- Saved-panel OCR uses Windows `Windows.Media.Ocr`, as the reference companion does, through a hash-bound DLL built with the app. It has its own bounded worker, session/map/evidence fences and shutdown lifecycle. Missing, unreadable or unavailable evidence never becomes an authoritative empty panel. To check a saved screenshot offline, run `mise exec -- dart run tool/ocr/read_saved_panel.dart <image>`.
- All live-game verification is user-only. Agents must never interact with games or their memory, and must confirm EFT is closed before launching or driving Blackgrid/reference apps.

The current bundled preparation-v3 pack is manifest/version `6a2868b8c4b7c9c8cc53fc2f9b21f77101a4b2d26570d5518b88bdd8fb64b4a5`, with calibration evidence SHA-256 `0eb38479d6aeff22890404685fa1e4e0fbe4881f5ffeeef94abf6f608af91818`. It covers all 13 maps. `<use>` references to symbols the publisher deleted (Customs `path493`, Streets stairs) are dropped, matching browser rendering; any other missing symbol fails preparation. Historical placement/native/performance receipts belong to their recorded generations; this pack has no new native, performance or standalone launch qualification.

Map preparation commands are maintenance-only tooling, separate from runtime rendering. Inspect the command contract with:

```text
mise exec -- dart run tool/maps/prepare.dart --help
```

`acquire` freezes the approved inputs into a fresh raw directory and is the only network operation. `rebuild` creates a fresh candidate from frozen inputs offline; `normalize` and `compile` expose its two stages. `validate` checks the complete candidate before `promote` publishes an immutable version and atomically replaces `active.json`. Failed candidates leave the active pack untouched. `assets` prints the promoted pack's complete Flutter asset declarations, including nested tiles and preparation evidence. The current declarations cover 105 active asset directories, including `evidence/tile-alpha/`; update `pubspec.yaml` when promoting another generation.

Preparation-v2 validation binds canonical vector component paths, dependency-closed source SVGs, compiler SVG/native effects and actual `.vec` payload hashes to the pinned compiler output. Raster validation decodes and hash-binds visible tiles and original transparent PNG witnesses; empty tiles are not inferred from byte size or accepted on manifest assertions alone. Witnesses are deduplicated unchanged source bytes, not replacement artwork. Candidate crops must stay wholly inside the original artwork frame; the crop changes display only, not geometry or persisted pin frames.

Existing preparation-v1 packs lacking transparent witnesses must be rebuilt offline from frozen inputs before this validator can promote them. This is a maintenance requirement, not a runtime `preparationVersion` gate. Runtime loads prepared artwork and marker data; it does not run acquisition, normalization, compilation or candidate validation.

Only the exact Interchange console `switches:6b9023f26446d73433823e872e6d69688083beaf:0` gains prepared `Second_Floor` ownership. Its frozen full height volume `[37.187, 37.507]` and outline are contained in the locked metadata's `Second_Floor` band `[34, 1000]` and mall rectangle. The assignment retains `source.floorAssignment` provenance; source position/height/outline, pins and shared geometry are unchanged. Automatic Interchange vector height resolution still returns null. This is not a rule for unknown, out-of-extent or cross-floor records. See [placement controls](docs/qualification/m3/PLACEMENT_CONTROLS.md) for the exact frozen evidence and the retained Icebreaker ownership/source-parity limits.

Selected-source identities, licences, notices and calibration evidence travel with the pack. Review source changes and rights before acquiring or promoting updates; source hosting alone does not grant redistribution permission.

## Legacy import

Use **Import**, explicitly enter the chosen settings and/or history JSON paths, then **Preview** before accepting. There is no automatic directory scan. Supported settings revisions are 0–3, scanner preferences 0–1 and history 0–1. Pins require supported map identities and coordinate-frame revisions; finite off-map coordinates are retained. Labs revision 0 is converted to the revision-1 native normalized frame; revision 1 is preserved.
An absent or exactly empty legacy selected-map preference uses the existing Shoreline default; explicit null, malformed values and unknown map identities remain invalid. Explicit activity revisions must be positive; only absent revisions receive positive input-order values, before collision resolution.

The preview accounts for every recognized record, source collision, existing destination collision and intentionally excluded field. It never imports Tracker keys, personal progress, computed advice/FIR/prices, overlay state or obsolete capture configuration. Source activity collisions resolve by positive revision, latest UTC observation, then stable source order. Existing destination records win by default; replacement requires an explicit choice. Acceptance commits all supported records and the once-only digest ledger in one transaction. Unsupported revisions or malformed frame metadata fail the complete candidate; source files remain untouched.

## Attribution and distribution

See [third-party notices](THIRD_PARTY_NOTICES.md) for selected dependencies and bundled map artwork, including each source's attribution and published terms. The repository's project license remains unselected; it is private and this implementation does not authorize public publication. No reference implementation or reference runtime is copied or shipped. Third-party artwork remains its creators' property; live source hosting is not a blanket licence to redistribute downloaded datasets or artwork.

## Changelog and release notes

Use conventional commits: `feat`, `fix`, `perf`, `docs`, `refactor`, `test`, `build`, `ci`, `chore`, and `style`. Breaking changes use `!` or a `BREAKING CHANGE:` footer. Merge commits are excluded; other commits remain under **Other**.

Release tags must be strict, `v`-prefixed semantic versions, such as `v1.0.0` or `v1.2.3-beta.1`. These commands generate text only; they do not create tags, releases, or remotes.

```text
mise run changelog
mise run release-notes -- --unreleased
mise run release-notes -- --latest
mise run release-notes -- -- v0.1.0..v0.2.0
```

Use a range only after both tags exist. Before the first commit, the small dependency-free `tool/changelog.dart` runner supplies an empty JSON context because git-cliff cannot traverse an unborn branch. The changelog contains **Unreleased**; release notes are empty until history exists.

## AI tooling

- `.omp/mcp.json` launches the [official Dart MCP server](https://dart.dev/tools/mcp-server) through mise using the pinned Dart and Flutter SDKs. CLI and Flutter lifecycle capabilities are enabled. The Windows launch command uses built-in PowerShell and isolates the server's tool cache under ignored `.dart_tool/dart-data/`.
- `.omp/skills/` contains 10 first-party Flutter skills and 7 first-party Dart skills. Source commits, file hashes, and licenses are recorded alongside them in `UPSTREAM.json`, `LICENSE.flutter`, and `LICENSE.dart`.
- Sources: [flutter/agent-plugins](https://github.com/flutter/agent-plugins) and [dart-lang/skills](https://github.com/dart-lang/skills). These are guidance, not installed application packages or architecture decisions.
- Restart or reload OMP after setup so it discovers the repository-local server and skills. Approve only the tools and project roots needed for your work.
- The official [`skills` package](https://pub.dev/packages/skills) **1.0.3** was used to inspect `flutter`, `flutter_test`, and `flutter_lints`; none supplied package skills. Its current generic-agent installer targets `.agents/skills/`, not `.omp/skills/`, so discovery was run in a disposable copy of the dependency workspace. No duplicate skill directory or extra project dependency was added.
