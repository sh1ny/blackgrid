# Proposal

## Why

M10's `update-map-toolchain` entry covers two upgrades skipped by the weekly dependency run ([#125](https://github.com/sh1ny/blackgrid/issues/125)). Run the existing reproduction check with those versions before accepting them. This maintenance change advances no M10 exit criterion.

## What Changes

- Update `vector_graphics_compiler` from 1.3.4 to [1.3.6](https://pub.dev/packages/vector_graphics_compiler/versions/1.3.6), published on 2026-11-11 UTC, and `xml` from 6.6.1 to [7.0.1](https://pub.dev/packages/xml/versions/7.0.1), published on 2026-04-25 UTC. Both were more than seven days old on 2026-11-26. The pub.dev advisories endpoint and the OSV exact-version query returned no advisories for either version that day.
- Keep the app-icon compiler-failure tests by replacing the now-supported `<filter>` fixture with an SVG element the new compiler still rejects. The app-icon tool continues to accept sources it can compile and render. The marker set still forbids filters under ADR-0023.
- Run `mise run maps:check` once with the new versions. Rebuild and commit the new generation only if the pack no longer reproduces.

## Capabilities

No requirements change. `app-icon` already uses the compiler to accept or reject an SVG, `map-marker-icons` independently forbids filters, and `prepared-map-packs` already defines reproduction and rebuild. This change has no spec delta.

## Impact

The root dependency constraints, lockfile and shipped dependency notices change. The app-icon rejection fixture changes and an offline test checks that a supported blur renders. SVG normalization and its qualification fixture move to `XmlName.parts`. Two map tests move to XML's `namespaceUri:` argument and keep their expected results. Prepared map assets change only when the reproduction report shows a difference. The app-icon artwork, Flutter SDK, `test` and `build_runner` are out of scope. `xml` 7.1.0 is also out of scope because the compiler caps it at `<=7.0.1`.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Upgrade only the two map preparation dependencies

- **Choice:** Keep the existing map reproduction gate and defer the Flutter SDK, `test` and `build_runner` upgrades to `upgrade-flutter-3-50`.
- **Rejected:** Bundle the next toolchain change here. That would make a reproduction failure harder to isolate.
- **Reversal cost:** low.
- **Important:** no. The two upgrades are independently reversible and change no player setting or format contract.
- **Chosen by:** user.

## Release Notes

Blackgrid updates two libraries it uses to prepare its maps. The offline map check still compares the prepared pack against a fresh build from its committed inputs.

### Changed

- Updated the map vector compiler to 1.3.6 and the XML parser to 7.0.1.
