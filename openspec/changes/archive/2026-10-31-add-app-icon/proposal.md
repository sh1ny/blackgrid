# Proposal

## Why

`blackgrid.exe`, the installer and its uninstall entry still show the default Flutter icon (`windows/runner/resources/app_icon.ico`: 256, 48, 32 and 16 px only). Releases are now published from tags (`publish-github-releases`), so the first public beta at the M6 close would ship with Flutter's icon. This is M6 change 4 (Windows CI and releases). It serves two exit criteria:
- `blackgrid.exe`, the installer and its uninstall entry show Blackgrid's own icon, not the Flutter default, at every size from 16 to 256 px (agent).
- The user picks that icon from the compared candidates (user).

## What Changes

- Commit the user's four ChatGPT concept PNGs (grid shield, scanner aperture, extraction waypoint, scanned cargo) as design candidates, each with a provenance record, and their preview composite beside the design record. They are currently kept out of git through a local exclude line.
- Add in-repo vector candidates: an SVG redraw of each of the four concepts plus two original designs.
- Add an offline comparison sheet that shows every candidate side by side at the icon sizes, on light and dark backgrounds. For a vector candidate it shows the same rasters the `.ico` would hold.
- The user picks one icon. If they pick a PNG concept, its SVG redraw becomes the source. The final icon is always built from an SVG.
- Add an offline tool that renders the chosen SVG to a multi-size `.ico` with 16, 20, 24, 32, 40, 48, 64, 96, 128 and 256 px images, and replace `windows/runner/resources/app_icon.ico` with its output.
- Add a test that checks the committed `.ico`: its sizes, its pixel format, and that it is not the Flutter default. Add a test that the installer script takes its setup icon from that file and its uninstall icon from `blackgrid.exe`.
- Add a release bundle check step: the icon embedded in the built `blackgrid.exe` matches the committed `.ico`, image for image.
- Write a design record for the candidates, the user's pick and the regeneration command, and ADR-0027 for the icon pipeline and its scope difference from ADR-0023.

## Capabilities

### New Capabilities
- `app-icon`: Blackgrid's application icon: the provenance of its source and candidates, the sizes and format of the `.ico`, and where the executable, the installer and the uninstall entry take it from.

### Modified Capabilities
- `release-bundle-integrity`: the bundle check gains a step that compares the executable's embedded icon with the committed `.ico`.

## Impact

- `windows/runner/resources/app_icon.ico` (replaced). `windows/runner/Runner.rc` and `windows/installer/blackgrid.iss` already point at it and stay unchanged.
- New: `windows/runner/resources/app_icon/` (chosen SVG source and its provenance record; not a Flutter asset, so not bundled), `docs/design/app-icon/` (candidates, design record), `tool/app_icon/` (render, ICO encoder, comparison sheet), and tests under `test/tool/app_icon/`.
- `tool/vision/pe.dart` gains icon-resource reading, and `tool/vision/check_bundle.dart` gains an `app-icon` step. The CI `bundle:check` run covers it.
- A new `mise` task to rebuild the `.ico`. No new dependency: `image` and `vector_graphics_compiler` are already in `pubspec.yaml`.
- No change to the app's Dart UI, its data or its game boundary.
