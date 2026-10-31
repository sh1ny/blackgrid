# Tasks

## Test map

The Flutter-host renderer (`tool/app_icon/render_host_test.dart`) stays outside `test/` (ADR-0027). The build's new `.vec` output is proved through `buildIcon` with the injected rasterizer, and the committed files are proved by the offline icon test. Widget tests use the real logo bytes on success paths, because `vector_graphics` caches decoded pictures by key across widgets (review S5).

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| app-icon → The icon build also writes the in-app vector | Rebuild writes the vector | test/tool/app_icon/build_test.dart | builds a valid ico and vec, then rewrites the record hashes | red |
| app-icon → The icon build also writes the in-app vector | Compile fails | test/tool/app_icon/build_test.dart | a source the compiler rejects exits non-zero naming it and leaves the ico, vec and record unchanged | red |
| app-icon → The icon build also writes the in-app vector | Record from before the vector | test/tool/app_icon/build_test.dart | a record without the vec hash builds and gains it | red |
| app-icon → The in-app vector stays in step with the source | Vector in step | test/tool/app_icon/committed_icon_test.dart | the committed vec matches its recorded hash and the compiled source | red |
| app-icon → The in-app vector stays in step with the source | Source edited without rebuild | test/tool/app_icon/provenance_test.dart | a vec that differs from the compiled source fails naming the rebuild command | red |
| app-icon → The in-app vector stays in step with the source | Vector without a recorded hash | test/tool/app_icon/provenance_test.dart | a vec on disk with no recorded hash fails naming it and the rebuild command | red |
| app-icon → The in-app vector stays in step with the source | Vector missing | test/tool/app_icon/provenance_test.dart | a recorded vec hash with no vec file fails naming it and the rebuild command | red |
| app-icon → The in-app vector stays in step with the source | Vector replaced by hand | test/tool/app_icon/provenance_test.dart | a source, ico or vec hash differing from the record fails naming the rebuild command | red |
| app-icon → The app header and the startup screen show the application icon | Header shows the logo | test/ui/shell_test.dart | header shows the 32x32 app logo and no hub icon | red |
| app-icon → The app header and the startup screen show the application icon | Startup screen shows the logo | test/ui/app_test.dart | startup and storage error screens show the 54x54 app logo and no hub icon | red |
| app-icon → The app header and the startup screen show the application icon | Logo is not announced | test/ui/app_logo_test.dart | the logo adds no semantics node | red |
| app-icon → The app header and the startup screen show the application icon | Vector fails to load | test/ui/app_logo_test.dart | a failed load leaves an empty box of the same size with no error | red |
| release-bundle-integrity → The bundle carries the committed in-app logo | Logo matches | test/tool/vision/check_bundle_test.dart | app-icon step passes listing ten sizes and app_icon.vec | green |
| release-bundle-integrity → The bundle carries the committed in-app logo | Logo missing from the bundle | test/tool/vision/check_bundle_test.dart | a bundle without the logo vec fails the app-icon step naming the path | green |
| release-bundle-integrity → The bundle carries the committed in-app logo | Stale bundled logo | test/tool/vision/check_bundle_test.dart | a bundled logo vec that differs fails the app-icon step, also when the exe icon is unreadable | green |

## 1. ADR-0028 and the architecture index

- [x] 1.1 Write `docs/adr/0028-app-icon-ships-a-compiled-header-logo.md` (MADR-short, `Status: accepted`, `Amends: 0027`, today's date) from design D1 to D7 and D6's content. It covers: the source folder stays unbundled, `icon:build` writes `assets/app_icon/app_icon.vec` with the marker compile flags, the record binds it by an optional-to-parse, required-to-bind hash, the icon test recompiles it, and `bundle:check`'s `app-icon` step compares the bundled copy. It restates the two ADR-0027 statements it makes false. Its Consequences say the header and the startup screen depend on the bundled asset. Include rejected alternatives. Add its row to `openspec/architecture.md`'s ADR index, and append "amended by 0028" to the status column of the 0027 row. Do not edit ADR-0027. Verify: `grep 0028 openspec/architecture.md` finds the new row and the note on 0027's, and `git diff --stat docs/adr/0027-*` is empty.

## 2. The build writes the `.vec`, and the record binds it

Load `dart-add-unit-test`, `dart-write-documentation` and `dart-use-pattern-matching` first.

- [ ] 2.1 Write failing tests in `test/tool/app_icon/provenance_test.dart` for the rows "Vector without a recorded hash", "Vector missing" and "Vector replaced by hand". Also cover:
  - `parseSourceRecord` accepts a record with or without `sha256["app_icon.vec"]`;
  - it rejects a malformed `app_icon.vec` hash.

  Extend the existing "differing" test name to cover the `.vec`. Add the "Source edited without rebuild" `.vec` check as a test of a pure helper, `checkCompiledVec(svg, vec, {compile})`: it compiles through `compileSources`' compiler and returns failures naming `app_icon.vec` and `mise run icon:build`. Verify they fail for the missing implementation.
- [ ] 2.2 Implement D2 and the helper in `tool/app_icon/provenance.dart`:
  - add `vecName = 'app_icon.vec'` to `_hashFields`, optional in the parser;
  - add a required `Uint8List? vec` argument to `checkHashBinding`;
  - `renderSourceRecord` writes the `.vec` hash.

  Verify that the 2.1 tests pass, and flip the four provenance rows green.
- [ ] 2.3 In `test/tool/app_icon/build_test.dart`, write failing tests for the rows "Rebuild writes the vector", "Compile fails" (the existing render-fails test, renamed and extended to the `.vec`) and "Record from before the vector". Pass a temp `vecPath`. Extend the record-write-failure test so that `checkHashBinding` also gets the `.vec`. Verify they fail.
- [ ] 2.4 Implement D1 in `tool/app_icon/build.dart`:
  - `buildIcon` gains `vecPath`;
  - it writes `main.compiled` after the `.ico` and before the record, each through `writeAtomically`;
  - the success message names all three files;
  - update the header comment.

  In `render_host_test.dart`, add `defaultVecPath = 'assets/app_icon/app_icon.vec'` and pass it. Verify that the 2.3 tests pass, and flip the three build rows green.
- [ ] 2.5 Add `assets/app_icon/** -text` to `.gitattributes`, add `- assets/app_icon/` to `pubspec.yaml`'s assets, and add the `.vec` to the `icon:build` description in `mise.toml`. Then run `mise run icon:build` (offline; it does not launch the app). Verify:
  - `assets/app_icon/app_icon.vec` exists;
  - `provenance.json` holds three hashes;
  - `git diff --stat windows/runner/resources/app_icon.ico` is empty. If the `.ico` changed, stop and report it, as design Flow & State Gaps says.
- [ ] 2.6 Add a test to `test/tool/app_icon/committed_icon_test.dart` for the row "Vector in step": the hash binding with the committed `.vec`, and `checkCompiledVec` on the committed `app_icon.svg` and `.vec`, both empty. Pass the `.vec` in the existing binding test too. Verify that `mise exec -- flutter test test/tool/app_icon` passes, and flip the row green.
- [ ] 2.7 Update `docs/design/app-icon/README.md`: the source section and the rebuild steps name `assets/app_icon/app_icon.vec` and commit it with the `.ico` and the record, and the "never bundled" paragraph points at ADR-0028. Verify: `grep -n "app_icon.vec" docs/design/app-icon/README.md` finds the rebuild step.

## 3. `AppLogo` in the header and on the startup screen

Load `flutter-add-widget-test` and `dart-write-documentation` first.

- [ ] 3.1 Write failing tests in a new `test/ui/app_logo_test.dart` for the rows "Logo is not announced" and "Vector fails to load". The error path injects a `load` that returns a failed `Future`. It asserts:
  - a `SizedBox` of 32x32 where the logo goes;
  - the position of a neighbouring `Text('BLACKGRID')` matches a pump with the real bytes;
  - no `ErrorWidget`;
  - a `FlutterError.onError` spy that was never called, restored before any `expect`;
  - `tester.takeException()` returns null.

  The success path loads the real asset bytes inside `tester.runAsync`, and asserts a 32x32 `AppLogo` with a `VectorGraphic` child and no semantics node of its own. Verify they fail because `AppLogo` does not exist.
- [ ] 3.2 Implement `lib/ui/app_logo.dart` per D4: a `StatefulWidget`, a one-time load in `didChangeDependencies`, the error handled on that future, `SizedBox.square` while loading and after a failure, `VectorGraphic` over a private in-memory `BytesLoader` with `excludeFromSemantics: true`, and `///` docs. Verify that the 3.1 tests pass, and flip both rows green.
- [ ] 3.3 Write a failing test in `test/ui/shell_test.dart` for the row "Header shows the logo": one `AppLogo` of size 32 in the header, beside `BLACKGRID`, and `find.byIcon(Icons.hub_outlined)` finds nothing. Assert on the `AppLogo` widget and its size, not on `VectorGraphic`'s private loader (review S5). Then replace the `Icon` in `lib/ui/shell.dart:73-77` with `const AppLogo()`. Verify that the test and every existing shell layout test pass, and flip the row green.
- [ ] 3.4 Write a failing `test/ui/app_test.dart` for the row "Startup screen shows the logo". It pumps `BlackgridBootstrap(open: ...)` once with a `Completer`'s pending future and once with a failed future, and asserts a 54x54 `AppLogo` and no `Icons.hub_outlined` in both states. Then implement D7, the `open` parameter defaulting to `AppServices.open` (`main.dart` unchanged), and replace the startup screen's `Icon` with `const AppLogo(size: 54)`. Verify that the test passes, and flip the row green.

## 4. Bundle check compares the bundled `.vec`

- [x] 4.1 Write failing tests in `test/tool/vision/check_bundle_test.dart` for the rows "Logo matches", "Logo missing from the bundle" and "Stale bundled logo". The stale case also runs with an unreadable executable icon group, and expects both failures. Update the fixtures so that every expected-pass bundle has a committed `.vec`, passed with `--app-logo` or `appLogoPath`, and a bundled copy at `data/flutter_assets/assets/app_icon/app_icon.vec`. Use small synthetic bytes. Verify the new tests fail.
- [x] 4.2 Implement D5 in `tool/vision/check_bundle.dart`:
  - `appIconStep` gains `bundledVec` and `vecPath`, and the `.vec` comparison runs first, its failures kept across the early returns;
  - add `defaultAppLogoPath`, the `checkBundle` parameter, the `--app-logo` flag in the help text and parser, and the path in `protectedFiles`;
  - pass details gain `app_icon.vec`;
  - update the doc comments.

  Verify that the 4.1 tests and the existing `app-icon` tests pass, and flip the three rows green.

## 5. Integration

- [ ] 5.1 Run `dart format` on the changed Dart files (`mise exec -- dart format ...`), then `mise run analyze` and `mise run test`. Verify: both exit 0, and every Test map row is green.
- [ ] 5.2 Confirm that Escape from Tarkov is not running: `tasklist` must show no `EscapeFromTarkov.exe`. If that can't be confirmed, skip this task and record it as unverified. Then run `mise run build:release`, which runs `bundle:check`. Verify: the `app-icon` step passes, listing the ten sizes and `app_icon.vec`. The app is not launched.
- [ ] 5.3 Run `openspec validate add-header-app-logo --strict`. Verify: it passes.

## Workflow follow-up

- User check, before `0.6.0-beta.1`: launch the built app and confirm the hex logo in the header and on the startup screen, and that its colours sit well on the dark header. This stays unverified until the user reports it.
- After this change merges: `mise run release:prepare -- 0.6.0-beta.1`, merge the release PR, then `mise run release:tag`.
