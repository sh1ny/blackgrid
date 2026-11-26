# Proposal

## Why

M10's weekly dependency run (#125) could not update the test and generation tools under Flutter 3.47.9. Flutter 3.50.1 pins `test_api` 0.7.14, which allows `test` 1.32.0 and an analyzer compatible with `build_runner` 2.17.1.

This is the toolchain entry in M10, not an alert or screenshot-cleanup exit criterion. The owner alone runs the install check and starts Blackgrid with the game closed. The result stays unverified until reported for an identified installer. Agents run only the offline gates; installation is separate from OpenSpec's implementation tasks.

## What Changes

- Change the shared local and CI mise pin to Flutter 3.50.1, which bundles Dart 3.14.0. Update the README, third-party notices and OpenSpec context to match.
- Use `test` 1.32.0 in the root and `blackgrid_progress` workspace member. Use `build_runner` 2.17.1 and resolve an `analyzer` in `>=14.3.0 <15.0.0`. Keep `test` 1.33.0 out because it needs `test_api` 0.7.15.
- Keep unrelated package versions and app behaviour unchanged. Run analysis, the fast tests, map reproduction, the Windows Release build, the full hosted qualification tier and packaging under the new SDK. Fix only regressions attributable to this upgrade.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. `continuous-integration` already requires CI to use the `mise.toml` pin and qualify the bundle it builds. Neither requirement changes.

## Impact

The root and progress manifests share one lockfile. The Flutter framework adds `listen` and raises the `vector_math` minimum, so both the build tools and the application dependency notices need review. No Blackgrid API, data format, game interaction or installer policy changes.

### Dependency vetting

[Flutter's Windows SDK index](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json) gives the Flutter release date and bundled Dart version. Pub dates come from the linked version records. The hosted package checks used the [pub.dev advisory feeds](https://pub.dev/api/packages/analyzer/advisories) and [OSV](https://osv.dev/). The SDKs were checked against [Flutter's advisories](https://github.com/flutter/flutter/security/advisories) and [Dart's advisories](https://github.com/dart-lang/sdk/security/advisories). No advisory found applies to the versions listed below. Dart's [eMudhra CA advisory](https://github.com/dart-lang/sdk/security/advisories/GHSA-frr6-h895-5pxp) and [Pub archive extraction advisory](https://github.com/dart-lang/sdk/security/advisories/GHSA-q739-79rh-vmvp) affect earlier SDKs.

| Candidate | Release date (UTC) | Why it changes |
| --- | --- | --- |
| Flutter 3.50.1 | 2026-11-20 | Windows stable SDK |
| [Dart 3.14.0](https://storage.googleapis.com/dart-archive/channels/stable/release/3.14.0/VERSION) | 2026-11-04 | Dart archive date; bundled in Flutter 3.50.1 |
| [`test` 1.32.0](https://pub.dev/packages/test/versions/1.32.0) | 2026-09-02 | Workspace test dependency |
| [`test_api` 0.7.14](https://pub.dev/packages/test_api/versions/0.7.14) | 2026-09-02 | Pinned by Flutter's `flutter_test` |
| [`test_core` 0.6.20](https://pub.dev/packages/test_core/versions/0.6.20) | 2026-09-02 | Pinned by `test` |
| [`build_runner` 2.17.1](https://pub.dev/packages/build_runner/versions/2.17.1) | 2026-10-14 | Requested generation tool |
| [`analyzer` 14.7.0](https://pub.dev/packages/analyzer/versions/14.7.0) | 2026-10-29 | Latest compatible candidate for `build_runner`; its minimum [14.3.0](https://pub.dev/packages/analyzer/versions/14.3.0) was released on 2026-09-01 |
| [`_fe_analyzer_shared` 111.0.0](https://pub.dev/packages/_fe_analyzer_shared/versions/111.0.0) | 2026-10-29 | Required by `analyzer` 14.7.0 |
| [`build` 5.0.0](https://pub.dev/packages/build/versions/5.0.0) | 2026-10-14 | Required by `build_runner` |
| [`build_config` 1.4.0](https://pub.dev/packages/build_config/versions/1.4.0) | 2026-10-14 | Minimum required by `build_runner` |
| [`source_gen` 4.3.1](https://pub.dev/packages/source_gen/versions/4.3.1) | 2026-10-14 | Keeps `drift_dev` compatible with `build` 5 |
| [`listen` 1.0.1](https://pub.dev/packages/listen/versions/1.0.1) | 2026-07-31 | New Flutter framework dependency |
| [`vector_math` 2.4.4](https://pub.dev/packages/vector_math/versions/2.4.4) | 2026-10-26 | Latest compatible candidate for Flutter's new minimum [2.4.3](https://pub.dev/packages/vector_math/versions/2.4.3), released on 2026-09-18 |

This table records the candidates checked before the solve. Before installing the workspace packages, check a targeted dry run and vet any additional version it selects. The [apply evidence](evidence/1.1.md) will record the actual lockfile changes, release dates and advisory results. If resolution needs a change outside this proposal, stop for a scope decision and review the revised plan before proceeding. The owner confirmed that the publication-age hold applies to Kakeibo's npm dependencies, not to Flutter or Dart packages in Blackgrid. Advisory checks still apply.

### Branch gate

Specwright 0.39.1 reported a clean, precreated Orca branch `feat/upgrade-flutter-3-50`, rather than a worktree on `main`. The manual gate for that case confirmed that HEAD, local `main` and freshly fetched `origin/main` all pointed to `a9469b01`, there was no active change of this name, and neither main ref contained an archive of it. The code and planning roots are the same worktree. No branch switch or shared installation was needed.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Upgrade the toolchain without changing app features

- **Choice:** Ship the SDK, test and generation updates in the M10 roadmap entry. Keep the Windows install check with the owner.
- **Rejected:** Upgrade unrelated packages or override Flutter's `test_api` pin to use `test` 1.33.0.
- **Reversal cost:** medium. Reverting the shared pin also reverts the test and generator lockfile changes.
- **Important:** yes, because the SDK ships in the Windows bundle and CI uses the same pin.
- **Chosen by:** user.

## Release Notes

Blackgrid uses Flutter 3.50.1 for Windows builds. This update does not change player settings or add features.

### Changed

- The Windows build uses Flutter 3.50.1 and Dart 3.14.0. Both workspace packages use `test` 1.32.0, and code generation uses `build_runner` 2.17.1.
