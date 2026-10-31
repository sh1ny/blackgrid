# 0028 - The app icon ships a compiled header logo

- Status: accepted
- Amends: 0027
- Date: 2026-10-31 (M6 change `add-header-app-logo`)
- Source: change `add-header-app-logo` (design D1-D7)

## Context and problem

The app header and the startup screen draw Material's `Icons.hub_outlined`, while the executable, installer and uninstall entry show Blackgrid's own icon (ADR-0027). Every launch shows two different logos. The header needs the icon as a runtime asset. ADR-0027 says "The folder is not a Flutter asset and is never bundled" and lists the files its hash binding covers, so shipping the icon in the header makes two of its statements false. Accepted ADRs are immutable, so this ADR amends them.

## Decision

- **The source folder stays unbundled; its compiled vector ships (D6).** `windows/runner/resources/app_icon/` is still not a Flutter asset. `mise run icon:build` also writes `assets/app_icon/app_icon.vec`, the compiled vector of `app_icon.svg` that it already holds before rasterizing, listed in `pubspec.yaml` and stored `-text` so hashed bytes survive checkout. The small SVG never feeds it, because the header draws at 32 px.
- **One writer (D1).** Only `icon:build` writes the `.vec`. It compiles with the map marker flags (`compileIconSvg`: warnings as errors, masking, clipping and overdraw optimizers off). The write order is `.ico`, `.vec`, record, each through `.tmp` and a rename, after every size rendered and encoded.
- **The record binds it by a hash that is optional to parse and required to bind (D2).** `sha256["app_icon.vec"]` joins the record's hash fields. `parseSourceRecord` accepts a record without it, so the one command that adds it can still read the old record. `checkHashBinding` requires it: a `.vec` on disk without a recorded hash fails and names `mise run icon:build`. `schemaVersion` stays 1.
- **The offline icon test recompiles the source (D3).** It compares the compile of `app_icon.svg` with the committed `.vec`, as well as checking the hash. A hand-edited record cannot bind a `.vec` built from another source. It runs in `mise run test`, so in CI.
- **`bundle:check` compares the bundled copy (D5).** The `app-icon` step compares `data/flutter_assets/assets/app_icon/app_icon.vec` in the bundle with the committed file, and reports that failure together with the icon-group failures. Step names and order do not change.
- **A decorative `AppLogo` widget draws it (D4, D7).** The header and the startup screen use it with the icon's own colours. It loads the bytes itself and shows an empty box of the same size while loading or after a failure.

### What this amends in ADR-0027

- ADR-0027: "The folder is not a Flutter asset and is never bundled." Now: the source folder is still not a Flutter asset and is never bundled, but its compiled vector, `assets/app_icon/app_icon.vec`, is.
- ADR-0027 binds by hash "each source and the `.ico`", and its icon test "fails when a source or the `.ico` differs from its recorded hash". Now the list of bound files also includes the `.vec`, and the test also recompiles the source and compares it with the `.vec`.

Everything else in ADR-0027 stands.

## Rejected alternatives

- **A separate `icon:vec` task, or a step in the `map:pack` marker tool (D1):** a second writer of one output that could run without the other, so the record could bind an `.ico` and a `.vec` built at different times.
- **Bundling `app_icon.svg` and compiling it at runtime with `flutter_svg` (D1):** adds a dependency and a runtime parser for one file, and ships the source folder that ADR-0027 keeps out of the bundle.
- **A required `.vec` hash in the parser, or `schemaVersion` 2 (D2):** `buildIcon` parses the record before rewriting it, so a required key would stop the command that adds it, and a version bump would make the build accept version 1 anyway.
- **Hash binding alone, without the recompile (D3):** a hand-edited record could bind a `.vec` compiled from another source.
- **`VectorGraphic` with `AssetBytesLoader` and `errorBuilder` (D4):** a failed load leaks an uncaught async error, which fails any widget test of that path.
- **`vg.loadPicture` into a `CustomPaint`, as the map markers do (D4):** it suits many icons on a map canvas; the header needs one widget with layout, placeholder and error handling.
- **A Material icon tinted to match (D4), or leaving the startup screen on the hub icon (D4):** neither is Blackgrid's logo, and the second keeps two logos in one window.
- **A separate `app-logo` bundle step, or an entry in `bundle_inventory.json` (D5):** the first changes the step list that the qualification test and the CI report pin, for one byte comparison that belongs with the icon; the second lists native, model and sample files, and Flutter assets are covered by their own steps, as the markers are.

## Consequences

- The app header and the startup screen now depend on the bundled asset. A missing asset shows an empty box of the same size, with layout unchanged. `bundle:check` and the icon test catch every way that can happen in a shipped build.
- Changing the icon means editing the SVG, running `mise run icon:build` and committing the `.ico`, the `.vec` and `provenance.json` together; the icon test fails until all are committed.
- A bundle built before an icon change fails `app-icon` until rebuilt. That is intended.
- The logo keeps the icon's own colours, so the user checks it on the dark header in the running app; this is recorded as unverified until they report it.
- **Reversal cost:** low. One extra output file, one optional record key, one widget and one comparison in the existing step.
