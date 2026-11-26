# Proposal

## Why

M10's weekly dependency run (#125) could not update the test and generation tools under Flutter 3.47.9. Flutter 3.50.1 pins `test_api` 0.7.14, which allows `test` 1.32.0 and an analyzer compatible with `build_runner` 2.17.1.

This is the toolchain entry in M10, not an alert or screenshot-cleanup exit criterion. The owner alone runs the install check and starts Blackgrid with the game closed. The result stays unverified until reported for an identified installer. Agents run only the offline gates; installation is separate from OpenSpec's implementation tasks.

## What Changes

- Change the shared local and CI mise pin to Flutter 3.50.1, which bundles Dart 3.14.0. Update the README, third-party notices and OpenSpec context to match.
- Use `test` 1.32.0 in the root and `blackgrid_progress` workspace member. Use `build_runner` 2.17.1 and resolve an `analyzer` in `>=14.3.0 <15.0.0`. Keep `test` 1.33.0 out because it needs `test_api` 0.7.15.
- Move Blackgrid's Material imports to the official `material_ui` package. Flutter 3.50.1 deprecates `package:flutter/material.dart`, which makes the existing analyzer gate fail. The owner approved a mechanical migration in this change. Do not change widget behaviour, golden expectations, or gate settings to make it pass.
- Keep Flutter 3.50.1 and work around [Dart SDK #64917](https://github.com/dart-lang/sdk/issues/64917). Windows Release compilation crashes in `CapturePolicy.capture` when its rejection closure captures a `final` assigned in a switch. Bind the frame ID after the switch and capture that ID instead. Keep capture results, frame ownership and the Release gate unchanged.
- Keep unrelated package versions and app behaviour unchanged. Run analysis, the fast tests, map reproduction, the Windows Release build, the full hosted qualification tier and packaging under the new SDK. Fix only regressions attributable to this upgrade.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. `continuous-integration` already requires CI to use the `mise.toml` pin and qualify the bundle it builds. Neither requirement changes.

## Impact

The root and progress manifests share one lockfile. Flutter adds `listen` and raises the `vector_math` minimum. The extracted Material library adds a direct application dependency and its localization dependencies. The portable progress member gains no Flutter dependency. No Blackgrid API, data format, game interaction or installer policy changes.

Projects that copy the standalone Ember kit must now declare `material_ui` in their own manifest. Blackgrid supplies it in the root manifest.

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
| [`material_ui` 1.11.1](https://pub.dev/packages/material_ui/versions/1.11.1) | 2026-11-16 | Official replacement for Flutter's deprecated Material import |
| [`cupertino_ui` 1.1.7](https://pub.dev/packages/cupertino_ui/versions/1.1.7) | 2026-11-16 | Dependency of `material_ui` |
| [`intl` 0.20.3](https://pub.dev/packages/intl/versions/0.20.3) | 2026-06-25 | Required by Flutter's localization package and both UI packages |
| [`flutter_localizations`](https://github.com/flutter/flutter/tree/3.50.1/packages/flutter_localizations) | 2026-11-20 | Bundled Flutter SDK dependency, not a separate hosted release |

The table records vetted candidates. Before accepting a workspace solve, vet every newly selected version. The [SDK resolution evidence](evidence/1.1.md) and [Material resolution evidence](evidence/1.3.md) record the final lockfile changes, release dates and advisory results. Stop and re-review if resolution needs a change outside this proposal. The owner confirmed that the publication-age hold applies to Kakeibo's npm dependencies, not to Flutter or Dart packages in Blackgrid. Advisory checks still apply.

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

### S2: Migrate Material imports in the upgrade

- **Choice:** The owner said, "Migrate in this change." Add the official `material_ui` package and move the affected app, test and tool imports. The owner also approved updating the import emitted by the Ember generator and refreshing both byte-identical token files. Keep every token value, widget behaviour, assertion and gate intact.
- **Rejected:** Hold the SDK upgrade for a separate migration, or mute the deprecation. The current import fails the required analyzer gate with Flutter 3.50.1.
- **Reversal cost:** medium. Revert the imports and Material dependency together with the SDK pin.
- **Important:** yes, because Blackgrid ships the replacement as a runtime dependency.
- **Chosen by:** user.

### S3: Keep Flutter 3.50.1 and work around the AOT compiler crash

- **Choice:** The owner said, "Reword the function, keep 3.50.1". Make the frame ID capture explicit and leave a short comment naming Dart SDK #64917 and the removal condition: Flutter bundles Dart 3.14.1 or later. Prove the same Windows Release AOT target compiles and the existing offline capture ownership tests pass.
- **Rejected:** Pause the upgrade until stable Flutter ships the compiler fix. The narrow change preserves runtime behaviour and keeps all gates.
- **Reversal cost:** low; remove the workaround after the SDK fix is present and rerun the same checks.
- **Important:** yes. This widens the approved edits from toolchain and imports to one capture function.
- **Chosen by:** user.

## Release Notes

Blackgrid uses Flutter 3.50.1 for Windows builds. This update does not change player settings or add features.

### Changed

- The Windows build uses Flutter 3.50.1 and Dart 3.14.0. Both workspace packages use `test` 1.32.0, and code generation uses `build_runner` 2.17.1.
- Blackgrid uses Flutter's official standalone Material package in place of the deprecated SDK import. No widget or layout changes are planned.
- The Windows build avoids a Dart AOT compiler crash without changing capture behaviour.
