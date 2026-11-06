# Ember brand kit

A product-neutral copy of the visual system first built for Mythspine, ready to reuse in another app.

| File | What it is |
| --- | --- |
| `BRAND.md` | The system: tokens in frontmatter (DESIGN.md format), then colours, type, layout, depth, shapes, components, motion, rules, and how to adopt it. Start here. |
| `tokens.json` | The single source of token values, dark and light. |
| `tokens.css` | CSS custom properties and `@font-face`, generated from `tokens.json`. |
| `components.css` | The component styles (`em-` prefix), built on the tokens. |
| `specimen.html` (+ `.css`, `.js`) | Every component in both themes. Serve the folder over HTTP to view it (the page uses a module script); `specimen.png` is a capture. |
| `flutter/ember_tokens.dart` | `EmberColors` (a `ThemeExtension`), `EmberType`, `EmberRadius`, `EmberSpace`, `EmberSize`, `EmberShadows`, `EmberMotion`, generated from `tokens.json`. |
| `flutter/ember_theme.dart` | `emberTheme(Brightness)`: a Material `ThemeData` wired to the tokens. |
| `tools/build.mjs` | Regenerates the CSS and Dart token files: `node brand/tools/build.mjs`. No dependencies. |
| `fonts/` | Geist and Literata (variable, Latin-subset WOFF2) with their licences. |

## Using it with impeccable

To start a new product on this system, copy `brand/` into the project and use `BRAND.md` as the starting `DESIGN.md`: rename it, change `name`/`description`, and record what the product changes. impeccable reads DESIGN.md frontmatter, so the tokens carry over directly.

## Status

- The CSS and the specimen were checked in a browser, in both themes.
- The Dart files have **not** been compiled here, because this repository has no Flutter SDK. Run `flutter analyze` after dropping them into an app. They target Flutter 3.22 or later, which provides `WidgetStatePropertyAll` and the `surfaceContainer*` colour roles.

## Licences

The fonts are under the SIL Open Font License 1.1. The full texts are in `fonts/OFL-geist.txt` and `fonts/OFL-literata.txt`, and `fonts/OFL-NOTICE.md` records their provenance. The OFL lets you bundle the fonts with any app, provided the licence goes with them; the fonts may not be sold on their own. Everything else in this folder is the project's own work.
