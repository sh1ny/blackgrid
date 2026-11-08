# Proposal

## Why

Blackgrid still ships its first dark-green and gold look. Every verdict sits in the same gold-outlined box, so a player who glances away from the game cannot tell Keep from Sell before reading the word (`.impeccable/review/current/10-scanner-history-item.png`). The owner moved Blackgrid onto Ember, the brand kit it shares with Mythspine, and approved DESIGN.md with its Blackgrid extensions on 2026-11-06. This change is change 2 of milestone **M8.5 - Ember interface**. It puts Ember underneath today's layout, so the three layout changes after it (`add-answer-strip`, `restyle-map-workspace`, `restyle-dialogs`) only move things around and do not also have to recolour them.

It advances three M8.5 exit criteria, all agent-verified by widget tests:

- both Ember rooms are built from the DESIGN.md tokens, and Settings has a System/Dark/Light switch that is saved and restored;
- each of the six verdicts shows its own plate as DESIGN.md X1 describes, and its reason is never clipped;
- Geist and Literata are bundled as font assets, with their OFL texts in the third-party notices.

It also prepares the user-verified criterion ("the verdict reads at a glance… the map and dialogs look right"). That criterion is judged at the milestone close, after the layout changes land, because the final layout does not exist until then. This change adds no `[user]` task for it.

## What Changes

- **Fonts.** Bundle Geist and Literata as `.ttf` font assets from their upstream OFL sources, with the OFL texts and a provenance entry in `THIRD_PARTY_NOTICES.md`. The web-only `.woff2` files in `brand/fonts/` stay where they are.
- **Tokens and theme in `lib/`.** Copy the kit's generated `ember_tokens.dart` and hand-written `ember_theme.dart` from `brand/flutter/` into `lib/ui/ember/`. They have never been compiled before, so `mise run analyze` checks them now. The owner approved one fix to Blackgrid's copy of the kit generator (`brand/tools/build.mjs`): it drops a redundant `dart:ui` import the analyzer rejects, and the tokens are regenerated. Mythspine's copy is not changed. Add Blackgrid's own tokens (the `ok-*` green set for verdicts, `map-ground`) in a separate Blackgrid extension, so they never leak into the shared kit.
- **Both rooms.** The app builds a dark and a light `ThemeData` from those tokens. `GridColors`, `blackgridTheme()` and the gold-bordered `GridPanel` styling are replaced by Ember roles: Shelf panels with hairlines, UI Heading titles, monochrome icons, pill controls and sentence-case labels (the uppercase "LIVE SCAN" and "MANUAL INSPECTION" headings become sentence case). The brand lockup keeps its capitals (X9).
- **Theme switch.** A new saved setting, `themeMode`, with System (the default, following Windows), Dark and Light. It is a three-option segmented control at the top of today's Settings dialog. The room changes instantly with no animation. The setting is decoded on its own, so a bad value falls back to System and never resets other settings. Restyling Settings into its own page is left to `restyle-dialogs`.
- **Verdict plates (X1).** The decision card's verdict, on the Scanner and in the Map rail, becomes one of five plate styles for the six verdicts: solid green Keep, green-triplet Keep for later, warning-triplet Check / May Need, neutral Flea and Trader with their price, and a dashed Price unavailable. No plate uses Ember.
- **Verdict reason line.** A new plain-language one-line reason sits below every plate and wraps instead of clipping. A pure domain function derives it from the decision: the deciding need for Keep and Keep for later, the first open question for Check / May Need (an unknown Found in raid comes before the needs it leaves open), the gross price comparison the engine makes for Flea and Trader, and the missing price for Price unavailable.
- **Freshness tag (X3).** One tag on the decision card's price row says when the Flea price was taken ("Prices 11:08"). Past one hour it takes the warning tone and says the age in words ("price 3 h old"). An unknown price time shows "price time unknown" in the warning tone. Items that cannot be sold on the Flea get no tag, because the Flea price cannot change their verdict. The Data sources panel keeps its text lines.
- **Out of scope here** (left to the later M8.5 changes): the answer strip and top-bar layout, the Settings page, map selection colours and marker role colours (ADR-0023 is not touched), the marker bubble, the startup screen, and the raw item ID under item names.

## Capabilities

### New Capabilities
- `interface-theme`: Blackgrid's visual system: the Ember dark and light rooms built from the design tokens, the saved System/Dark/Light theme setting, the bundled Geist and Literata fonts with their notices, and the rule that screens take colours only from the theme.
- `verdict-presentation`: how a keep/sell verdict is shown to the player: one distinct plate per verdict, the one-line reason below it, and the price freshness tag.

### Modified Capabilities
None. The decision engine's result, the scan rules and the Map rail's section order do not change. This change only changes how the verdict is shown, and adds a reason line derived from the existing decision.

## Impact

- **Code:** `lib/ui/theme.dart` (replaced), new `lib/ui/ember_tokens.dart`, `lib/ui/ember_theme.dart` and a Blackgrid token extension; `lib/ui/app.dart` (theme, dark theme and theme mode); every `lib/ui` file that reads `GridColors` (14 files); `lib/ui/item_decision_card.dart` (plate, reason line, freshness tag); `lib/ui/settings_dialog.dart` (theme switch); `lib/domain/settings.dart` (`themeMode`); a new pure domain function for the verdict reason.
- **Kit:** `brand/tools/build.mjs` (one redundant import dropped) and the regenerated `brand/flutter/ember_tokens.dart`.
- **Assets:** new font `.ttf` files under `assets/fonts/` and a `fonts:` block in `pubspec.yaml`. The bundle grows by the size of the font files.
- **Notices:** `THIRD_PARTY_NOTICES.md` gains the Geist and Literata entries with their OFL texts.
- **Stored data:** settings JSON gains one optional key. Older settings without it read as System. Older app versions ignore the key.
- **Not affected:** the map canvas, marker glyph and role colours, extract label colours (`lib/maps/`, `lib/domain/map_zone_style.dart`) and ADR-0023. The few map colours still written as literals in `lib/ui` (the map painter and the marker bubble's leader line) move into `lib/maps/` with their values unchanged. The map stays on its dark ground in both rooms (X6) until `restyle-map-workspace`.
- **Tests:** model tests for the setting and the reason function; widget tests for both rooms, the switch, the six plates, the reason line at narrow widths and the freshness tag; a source check that `lib/ui` has no colour literals outside the theme files.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Scope: Ember under today's layout, layout moves later

- **Choice:** Fonts, tokens, both rooms, the theme switch, verdict plates and the freshness tag land on today's layout. Layout, Settings page, map colours and dialogs follow in their own changes.
- **Rejected:** Restyling and re-laying-out in one change. It would be too big for one PR and would mix two kinds of review.
- **Reversal cost:** low
- **Important:** yes, because it changes what users see
- **Chosen by:** user (the M8.5 split agreed at the M8 close, 2026-11-08)

### S2: Theme default is System

- **Choice:** `themeMode` defaults to System, following Windows, as DESIGN.md X8 says. Players on light-mode Windows see the light room after updating.
- **Rejected:** Dark until changed. It would keep today's look for everyone, but it differs from X8.
- **Reversal cost:** low
- **Important:** yes, because it changes behaviour users see, and it adds a settings key
- **Chosen by:** user

### S3: A new plain-language reason line

- **Choice:** A pure domain function picks one line per verdict from the existing decision, with new wording written as a headline.
- **Rejected:** Reusing the first need reason or warning as worded today. Flea and Trader would get no reason, and that wording was written for lists.
- **Reversal cost:** low
- **Important:** yes, because it changes text users see
- **Chosen by:** user

### S4: Freshness tag only on the price row

- **Choice:** One freshness tag on the decision card's price row, on the Scanner and in the Map rail. The Data sources panel keeps its text.
- **Rejected:** Also turning the Data sources lines into tags now. That panel moves again in `add-answer-strip`.
- **Reversal cost:** low
- **Important:** yes, because it changes what users see
- **Chosen by:** user

### S5: Theme switch goes in today's Settings dialog

- **Choice:** The segmented System/Dark/Light control goes at the top of the existing Settings dialog. `restyle-dialogs` moves it into the General section of the Settings page.
- **Rejected:** Waiting for the Settings page. The exit criterion needs the switch, and that page is the last M8.5 change.
- **Reversal cost:** low
- **Important:** no, because the placement is temporary and its final home is fixed by DESIGN.md X12
- **Chosen by:** agent

### S6: Map palette untouched

- **Choice:** Marker glyph and role colours, extract label colours, place label and player marker colours, the cyan selection and the marker bubble's leader line keep their values. The literals among them that sit in `lib/ui` move into `lib/maps/` unchanged. The map keeps its dark ground in both rooms.
- **Rejected:** Recolouring the map now. It needs the new ADR that supersedes parts of ADR-0023, which belongs to `restyle-map-workspace`.
- **Reversal cost:** low
- **Important:** no, because the roadmap already assigns it to change 4
- **Chosen by:** agent

## Release Notes

Blackgrid now uses Ember, the design it shares with Mythspine. It has a dark and a light theme that follows Windows by default, new fonts, and verdicts you can tell apart at a glance. Each verdict now has its own plate and a one-line reason, and the price shows how old it is.

### Added
- A System, Dark and Light theme switch in Settings. System follows Windows and is the default.
- A one-line reason under every verdict, and a tag on the price that says when it was taken and warns once it is over an hour old.

### Changed
- New Ember look: near-black and warm paper surfaces, the Geist and Literata fonts, and one warm accent for what you are touching.
- Each verdict has its own plate: solid green Keep, soft green Keep for later, warm Check / May Need, neutral Flea and Trader, and a dashed Price unavailable.
