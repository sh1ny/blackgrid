# Proposal

## Why

`add-app-icon` gave `blackgrid.exe`, the installer and the uninstall entry Blackgrid's own hex icon, but the app header (`lib/ui/shell.dart`) and the startup screen (`lib/ui/app.dart`, shown while local storage opens and when it fails) still show a gold Material `Icons.hub_outlined` next to `BLACKGRID`. The first public beta (`0.6.0-beta.1`, M6) would then show one logo on the taskbar and a different one inside the window. The user asked for the header to show the new icon before that release. This serves M6's icon exit criterion ("Blackgrid's own icon, not the Flutter default"), extended to the app's own header, and lands before the M6 beta, like `add-app-icon`.

## What Changes

- `mise run icon:build` also compiles the icon source `app_icon.svg` with the map marker compile flags to a bundled Flutter asset, `assets/app_icon/app_icon.vec`, and records its SHA-256 in the icon's `provenance.json` beside the existing source and `.ico` hashes.
- The offline icon test fails when the committed `.vec` differs from its recorded hash, or from what compiling the committed `app_icon.svg` produces.
- The app header and the startup screen draw that asset with `vector_graphics` in place of `Icons.hub_outlined`, at the sizes the hub icon had (32 px in the header, 54 px on the startup screen). The logo is decorative: the `BLACKGRID` text beside it stays the name. If the asset cannot load, an empty space of the same size stands in, not an error widget.
- The release bundle check's `app-icon` step also checks that the bundle's `data/flutter_assets/assets/app_icon/app_icon.vec` equals the committed `.vec`.
- A new ADR-0028 amends ADR-0027: the icon source folder stays unbundled, but its compiled vector now ships in the app.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-icon`: the rebuild command also writes the compiled in-app vector and its hash; the source record holds that hash; a new requirement says the app header and the startup screen show the committed icon from that vector.
- `release-bundle-integrity`: the `app-icon` step also compares the bundled in-app vector with the committed one.

## Impact

- `tool/app_icon/` (`build.dart`, `provenance.dart`), `windows/runner/resources/app_icon/provenance.json`, a new `assets/app_icon/app_icon.vec`, `pubspec.yaml` (asset entry), `.gitattributes` (`-text` for the asset folder).
- `lib/ui/shell.dart`, `lib/ui/app.dart` (the startup screen; `BlackgridBootstrap` gains an injectable storage opener for its test) and a small logo widget in `lib/ui/`.
- `tool/vision/check_bundle.dart` (`app-icon` step).
- Tests: `test/tool/app_icon/` (provenance, build, committed icon), `test/tool/vision/check_bundle_test.dart`, `test/ui/shell_test.dart`, `test/ui/app_logo_test.dart`, a new `test/ui/app_test.dart`.
- Docs: `docs/adr/0028-*.md`, `openspec/architecture.md` (ADR index), `docs/design/app-icon/README.md`.
- No new dependency: `vector_graphics` and `vector_graphics_compiler` are already pinned. No game interaction; nothing needs the game running.
