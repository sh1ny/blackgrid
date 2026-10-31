# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:**
  - First pass: openspec/changes/add-header-app-logo/{proposal.md, design.md, specs/app-icon/spec.md, specs/release-bundle-integrity/spec.md}; openspec/specs/app-icon/spec.md; openspec/specs/release-bundle-integrity/spec.md; openspec/architecture.md (ADR index); docs/adr/0027-application-icon-pipeline.md; docs/adr/README.md; lib/ui/shell.dart; lib/ui/app.dart; tool/app_icon/build.dart; tool/app_icon/render.dart; tool/app_icon/provenance.dart; tool/app_icon/render_host_test.dart; tool/markers/icon_set.dart (compileIconSvg); tool/vision/check_bundle.dart (checkBundle, appIconStep, runCli); test/tool/app_icon/committed_icon_test.dart; test/tool/vision/check_bundle_test.dart; test/qualification/m2_bundle_integrity_test.dart; windows/runner/resources/app_icon/provenance.json; pubspec.yaml; .gitattributes; mise.toml; vector_graphics-1.2.3 lib/src/{vector_graphics.dart, loader.dart}; flutter_test (Flutter 3.47.6) lib/src/binding.dart.
  - First re-check: lib/application/app_services.dart:190.
  - This re-check (corrected M2 and the S4 remainder): the current design.md (the Context bullet on `vector_graphics`, D4, D6, Failure & Visibility, Risks), specs/app-icon/spec.md ("Vector fails to load"), and the Rebuttals in review.md.
  - Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, flutter-add-widget-test, dart-run-static-analysis.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. The startup and storage-error screen kept the old hub logo.** Status: **resolved.**
- **Problem:** `lib/ui/app.dart:60-64` drew `Icons.hub_outlined` at 54 px on the startup and storage-error screen. The window would still have shown two different logos.
- **Fix:** the proposal covers `app.dart`. D4 uses `const AppLogo(size: 54)` there. The `app-icon` delta has the "Startup screen shows the logo" scenario for both states. Failure & Visibility has a row for the startup screen. D7 lets a test inject the storage opener; its default, `AppServices.open`, is a static method (`app_services.dart:190`), so it is a valid const default.

**M2. A failed logo load escaped as an uncaught async error, and the planned error-path widget test could not pass.** Status: **resolved with option (a) of the corrected Required Change 2.**
- **Problem:** with `AssetBytesLoader`, a failed load leaks through `_loadPicture`'s discarded `whenComplete` future (`vector_graphics.dart:385`). In `testWidgets`, the binding reports that leak through `FlutterError.onError` and fails the test (`binding.dart:1815-1921`).
- **Fix:**
  - **D4:** `AppLogo` is now a `StatefulWidget`. It loads the bytes once through an injectable `load`, by default `DefaultAssetBundle.of(context).load(appLogoAsset)`, and handles that future's error itself. While loading and after a failure it builds `SizedBox.square(dimension: size)`. Only after a successful load does it build `VectorGraphic` over a private in-memory `BytesLoader`. A failed asset load therefore never reaches `_loadPicture`, so nothing leaks.
  - **Spec:** the THEN "no error widget is shown, and `FlutterError.onError` is not called" now holds and can be asserted.
  - **Context:** now describes the binding's real behaviour and no longer claims that `tester.takeException()` can take the leaked error.
  - **Failure & Visibility:** a separate row covers the remaining case, a `.vec` that loads but fails to decode. That case still leaks, but D3 (the icon test recompiles the source) and D5 (the bundle check compares the bundled copy) keep such a file from shipping.
  - **Risks:** the error-path test injects a `load` that returns a failed `Future`, the same path a missing asset takes. It asserts the empty 32x32 box, the unchanged `BLACKGRID` position, no `ErrorWidget`, a `FlutterError.onError` spy that is never called and is restored before any `expect`, and `tester.takeException()` returning null. Those assertions are consistent with the pinned binding.

### Suggestions

**S1. Keep the `.vec` comparison independent of the ICO step's early returns, and pass the bundled bytes in.** Status: **applied (D5).**

**S2. Have the recompile check in the icon test reuse `compileSources`.** Status: **applied (D3).**

**S3. Spell out the `check_bundle_test.dart` fixture work.** Status: **applied (D5).** Also add a test that a `--report` pointed at the `--app-logo` path is refused, alongside the existing marker-manifest test.

**S4. Update the text that ADR-0027 leaves stale.** Status: **applied (D6).** ADR-0028 restates both ADR-0027 statements it makes false. Its Consequences say the header and the startup screen now depend on the bundled asset. The `mise.toml` description of `icon:build` names the `.vec`.

**S5 (new, non-blocking). Update the stale success-path wording in Risks.**
- **What is stale:** the first Risks entry still says the widget test "asserts the `VectorGraphic`'s loader". Under the new D4, the loader is the private `_LoadedBytes`, and `VectorGraphic` exists only after the bytes load.
- **Suggested wording:** the success-path test asserts an `AppLogo` of the expected size in the header and on the startup screen, and proves the real asset exists by loading it through `rootBundle` inside `tester.runAsync`, as the entry already says.
- **Cache-key note:** `_LoadedBytes` uses `appLogoAsset` as its cache key, and `VectorGraphic`'s picture cache is static. A test that injects different success bytes while another test's logo still holds a cached picture would see the cached one. Use the real asset bytes in success-path tests, or derive the cache key from the bytes.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **(M1)** The bootstrap screen uses `AppLogo(size: 54)`, the spec has a scenario for both of its states, and D7 makes them testable. Applied and verified.
2. **(M2, corrected)** Option (a): `AppLogo` loads the bytes itself, handles the error, and hands `VectorGraphic` only bytes that loaded. Context drops the `takeException()` claim, a Failure & Visibility row covers the decode-failure leak, and the Risks test assertions are consistent with the pinned binding. Applied and verified.

CHANGES_APPLIED: yes

## Rebuttals

- **M1:** fixed with option (a). The proposal (Why, What Changes, Impact) covers `lib/ui/app.dart`. The `app-icon` delta renames the requirement to "The app header and the startup screen show the application icon" and adds the "Startup screen shows the logo" scenario. Design D4 uses `AppLogo(size: 54)` on the startup screen. A new D7 injects the storage opener so `test/ui/app_test.dart` can cover both states. Failure & Visibility gains a startup-screen row. — **accepted by reviewer.**
- **M2:** fixed. The Context bullet on `vector_graphics` 1.2.3 now describes the discarded `whenComplete` future and the uncaught async error. Failure & Visibility notes the console print. The widget-test Risk now uses a loader whose `loadBytes` returns a failed `Future`, a `FlutterError.onError` spy, and `tester.takeException()`. The spec's "Vector fails to load" THEN now reads "no error widget is shown, and `FlutterError.onError` is not called". — **not accepted.**
  - That change rested on a wrong premise about `flutter_test` (binding.dart:1815-1921).
  - The corrected change is resolved below.
- **S1-S4:** applied in D5 (the `.vec` failures are kept across the early returns, bundled bytes are passed in, the `check_bundle_test` fixtures are updated), D3 (`compileSources`) and D6 (ADR-0028 restates both ADR-0027 statements; the `mise.toml` description is updated). — **accepted by reviewer.**
- **M2 (corrected):** fixed with option (a). In D4, `AppLogo` is a `StatefulWidget`. It loads the bytes through an injectable `load`, by default `DefaultAssetBundle.of(context).load`, and handles the error itself. It hands `VectorGraphic` only bytes that loaded, through a private in-memory `BytesLoader`. Context now states the binding's real behaviour and drops the `takeException()` claim. Failure & Visibility has a separate row for the residual decode-failure leak, which D3 and D5 keep from shipping. The Risks entry now asserts that the `FlutterError.onError` spy is never called and that `takeException()` returns null. The spec THEN is unchanged and now holds. The S4 remainder is applied: ADR-0028's Consequences name the asset dependency. — **accepted by reviewer.**
