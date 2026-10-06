# blackgrid

Independent **Windows desktop only** tactical companion. M1 provides real mode-scoped catalog search, manual item inspection, conservative Keep/Later/Check/Sell decisions, protected read-only Tracker access, durable identity history and custom pins, and explicit legacy JSON import.

Primary navigation is **Map and Scanner only**. M1 deliberately has no capture/OCR, game/log interaction, accepted scan producer, map artwork, player position, overlay, Database browser, or progression-write controls. Empty or unavailable evidence is shown honestly rather than replaced with demonstration data.

The visual hierarchy follows [the Map and Scanner references](docs/vision/): compact shared navigation, near-black green surfaces, muted gold panel rules, Scanner's three columns and split lower evidence, and Map's broad workspace with a scrollable right rail. These images are design references, not shipped artwork or evidence of implemented capture/map rendering.

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
| `mise run test` | Flutter tests |
| `mise run format` | Format Dart source |
| `mise run format:check` | Check formatting without modifying files |
| `mise run changelog` | Regenerate `CHANGELOG.md` from local Git history, offline |
| `mise run release-notes` | Print changelog entries without the project heading |

The full offline suite includes independently authored synthetic wire fixtures, real SQLite transactions/reopen/migrations, credential replacement failure injection, authority fencing, conservative decisions, legacy revision/frame validation, and shared UI state/layout checks at both reference sizes and 100/125/150% text scaling. Production composition uses actual HTTP, SQLite and Windows DPAPI boundaries, not these test fixtures.

For agent verification, use the mounted official Dart MCP `run_tests`, `analyze_files` and `dart_format` tools; do not substitute shell test commands. Run expensive checks serially after authoring. Before each real Windows launch/restart or UI verification, freshly establish that Escape from Tarkov is closed. Never focus, inspect, capture, hook or read memory from the game or anti-cheat.

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

## Legacy import

Use **Import**, explicitly enter the chosen settings and/or history JSON paths, then **Preview** before accepting. There is no automatic directory scan. Supported settings revisions are 0–3, scanner preferences 0–1 and history 0–1. Pins require supported map identities and coordinate-frame revisions; finite off-map coordinates are retained. Labs revision 0 is converted to the revision-1 native normalized frame; revision 1 is preserved.
An absent or exactly empty legacy selected-map preference uses the existing Shoreline default; explicit null, malformed values and unknown map identities remain invalid. Explicit activity revisions must be positive; only absent revisions receive positive input-order values, before collision resolution.

The preview accounts for every recognized record, source collision, existing destination collision and intentionally excluded field. It never imports Tracker keys, personal progress, computed advice/FIR/prices, overlay state or obsolete capture configuration. Source activity collisions resolve by positive revision, latest UTC observation, then stable source order. Existing destination records win by default; replacement requires an explicit choice. Acceptance commits all supported records and the once-only digest ledger in one transaction. Unsupported revisions or malformed frame metadata fail the complete candidate; source files remain untouched.

## Attribution and distribution

See [third-party notices](THIRD_PARTY_NOTICES.md) for the dependencies actually selected for M1. The repository's project license remains unselected; it is private and this implementation does not authorize publication. No reference implementation or map/game artwork is copied or shipped. Live JSON source hosting is not a blanket license to redistribute downloaded datasets or artwork.

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
