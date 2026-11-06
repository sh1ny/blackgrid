---
name: Blackgrid (before the Ember redesign)
description: "Record of Blackgrid's visual system as built on 2026-11-06 (commit 2343fb2), captured before the Ember redesign. Descriptive, not normative."
colors:
  background: "#070d0b"
  surface: "#0d1512"
  inset: "#090f0d"
  border: "#50462b"
  quiet-border: "#29332c"
  gold: "#dcc05a"
  text: "#e6e8df"
  muted: "#a0aaa0"
  green: "#48d28b"
  error: "#ef9790"
  tab-selected: "#191c10"
  marker-danger: "#ff5252"
  marker-pin: "#40c4ff"
  marker-highlight: "#18ffff"
  marker-boss: "#e57ce5"
  marker-spawn: "#c9cdbf"
  marker-loot: "#e8a04a"
  marker-utility: "#b7a6f0"
  extract-pmc: "#7be495"
  extract-scav: "#f2c14e"
  extract-shared: "#8cb4ff"
  extract-transit: "#d29bf2"
typography:
  wordmark:
    fontFamily: "Segoe UI"
    fontSize: "23px"
    fontWeight: 700
    letterSpacing: "1px"
  title-large:
    fontFamily: "Segoe UI"
    fontSize: "23px"
    fontWeight: 600
  verdict:
    fontFamily: "Segoe UI"
    fontSize: "22px"
    fontWeight: 600
  title-medium:
    fontFamily: "Segoe UI"
    fontSize: "16px"
    fontWeight: 600
  body:
    fontFamily: "Segoe UI"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.4
  body-small:
    fontFamily: "Segoe UI"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.4
  section-label:
    fontFamily: "Segoe UI"
    fontSize: "12px"
    fontWeight: 400
    letterSpacing: "1px"
rounded:
  row: "3px"
  control: "4px"
  panel: "5px"
  dialog: "6px"
  popup: "12px"
spacing:
  shell: "14px"
  panel: "16px"
  bar: "20px"
components:
  panel:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.panel}"
    padding: "16px"
  verdict-box:
    backgroundColor: "{colors.inset}"
    textColor: "{colors.gold}"
    typography: "{typography.verdict}"
    rounded: "{rounded.control}"
  button-outlined:
    textColor: "{colors.text}"
    rounded: "{rounded.control}"
    padding: "13px 14px"
  button-filled:
    backgroundColor: "{colors.gold}"
    textColor: "{colors.background}"
    rounded: "{rounded.control}"
  input:
    backgroundColor: "{colors.inset}"
    rounded: "{rounded.control}"
    padding: "13px 12px"
  nav-tab-selected:
    backgroundColor: "{colors.tab-selected}"
    textColor: "{colors.gold}"
  header:
    backgroundColor: "{colors.inset}"
    height: "66px"
  footer:
    backgroundColor: "{colors.inset}"
    textColor: "{colors.muted}"
    height: "34px"
  marker-popup:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.popup}"
    width: "360px"
---

<!-- BEFORE RECORD: written 2026-11-06 from lib/ui at commit 2343fb2 and the screenshots in this folder. It describes what was built, inconsistencies included, so the Ember redesign can be compared against it. It is not a design authority; the root DESIGN.md is. -->

# Design System: Blackgrid (before the Ember redesign)

## Overview

**Observed character: "Tactical dark console, gold on green-black."**

Blackgrid today is a dark Material 3 desktop app that matches STRATEGY.md's earlier brand line: "charcoal surfaces, restrained gold accents, green healthy states". The surfaces are green-tinted near-blacks. Gold (#dcc05a) is the only accent, and it carries a lot of meanings: the selected tab, every panel icon, every verdict, warnings, section labels, the live-scan "on" state, selected rows and primary buttons. The type is Segoe UI, mixed with Material's defaults wherever the theme leaves a role undefined.

The layout is a dashboard of equal-weight bordered panels in fixed proportions. The Scanner is a three-column grid (19:57:24), and the Map is a 70:30 split with a scrolling rail. Each panel has a 26px gold icon, a 16px title and a subtitle, so every panel claims the same attention, and the verdict competes with settings panels for the eye. Below 1100 px everything stacks in source order, which puts the scanner's settings above the answer (`16-scanner-narrow-960.png`).

There is no motion beyond Material's own ripples, switch animations and route transitions.

**Key Characteristics:**
- Dark only; no light theme.
- One accent hue, gold, used for about a dozen unrelated jobs.
- Green-black surfaces with warm olive borders (#50462b) on every panel.
- Square header, footer and timer strip; containers rounded 3, 4, 5, 6 or 12 px with no clear rule.
- Uppercase, letter-spaced gold section labels ("LIVE SCAN", "MANUAL INSPECTION", "RECENT SCANS") and an uppercase, tracked wordmark and tagline ("TRACK. PLAN. SURVIVE.").
- Material Icons throughout; project-authored single-tint glyphs on the map (ADR-0023).

## Colors

A near-monochrome green-black stack with one gold accent, plus a separate, saturated palette on the map canvas.

### Primary
- **Brass Gold** (#dcc05a): the Material primary and the only accent in the chrome. It marks the selected tab (with a 2px underline), panel header icons, primary buttons, all six verdict labels and their borders, warning bullets, catalog and tracker error lines, requirement state lines ("Task • Done"), section labels, the selected history tile border and the live-scan "on" footer text. It is also repeated as a raw literal in the map's fallback badge colours and the popup tether line.

### Neutral
- **Pine Black** (#070d0b): scaffold background.
- **Deep Pine** (#0d1512): panels and dialogs.
- **Inset Pine** (#090f0d): header, footer, timer strip, inputs, tiles, value boxes and the map viewport. It is darker than the panel it sits in, so insets read as wells rather than raised cards.
- **Olive Rule** (#50462b): panel and dialog borders and the header and footer rules.
- **Moss Rule** (#29332c): inputs, outlined buttons, dividers, inner tiles.
- **Bone** (#e6e8df) and **Lichen** (#a0aaa0): text and secondary text.

### Status
- **Signal Green** (#48d28b): only "Import finished" and the check on a shown marker tile.
- **Soft Coral** (#ef9790): the `colorScheme.error`, used about 20 times. Some errors use gold instead.

### Map content
Marker roles (manifest): exit #48d28b, danger #ff5252, boss #e57ce5, spawn #c9cdbf, quest #dcc05a, loot #e8a04a, utility #b7a6f0, pin #40c4ff. Extract name labels by faction: PMC #7be495, Scav #f2c14e, shared #8cb4ff, transit #d29bf2. A highlighted badge is always cyan #18ffff, and a dimmed badge is drawn at 22% opacity. Zone outlines fill with the role colour at 16% opacity and stroke it at 2px.

## Typography

**Body Font:** Segoe UI (Windows system font)

**Character:** a system grotesk with no second voice. Hierarchy comes from size jumps. Ten sizes are in use: 10, 11, 12, 13, 14, 16, 17, 22, 23 and 26. Two of the theme's roles (`titleSmall`, `labelMedium`) are used without being defined, so they fall back to Material's defaults.

### Hierarchy
- **Wordmark** (700, 23px, tracked 1px, uppercase): "BLACKGRID" in the header; 26px on the bootstrap screen.
- **Title Large** (600, 23px): item names and empty-state headings ("Find an item").
- **Verdict** (600, 22px, gold): the keep/sell answer, the same for all six verdicts.
- **Title Medium** (600, 16px): every panel title.
- **Body** (400, 13px, 1.4): default text.
- **Body Small** (400, 12px, 1.4, muted): helper text, footer and captions.
- **Section Label** (400, 12px, tracked 1px, uppercase, gold): three in-panel section labels.
- **Micro** (10–11px): the tagline (tracked 1.7px), marker tile labels and the footer's live-scan text.

## Layout

- **Shell:** a 66px header (logo, wordmark and tagline, Map and Scanner tabs, an expanding search field with Ctrl K, and Settings, Stats and Import buttons). Below it a 28px raid timer strip (only when timers are on), the body with 14px padding, and a 34px status footer (game mode, item data, tracker, live scan). Below 1220 px the header scrolls sideways.
- **Map:** at 1100 px and wider, a 70:30 row with the map workspace on the left and a scrolling rail on the right. The rail holds Active map, the decision card, Marker preferences, Manual item search and the collapsible saved-file inputs. Below 1100 px they stack, the map at 650 px high and the rail below it.
- **Scanner:** at 1100 px and wider, three columns at 19:57:24. The left column has the live-scan and manual-inspection settings. The middle has the decision card (46%) above Requirements and Data sources (54%). The right column has Scan evidence (60%) above Recent item activity (40%). Below 1100 px every panel stacks at a fixed height, settings first.
- **Spacing:** 14px between panels, 16px inside them, 20px horizontal padding on the bars, 10–12px inside tiles. Gaps vary across 4–24px with no fixed step.
- Panels have fixed heights and proportions, so content that grows is clipped rather than reflowed: the decision card cuts off its own warnings (`11-scanner-history-item-warnings.png`).

## Elevation & Depth

Flat. Depth comes from a darker inset fill inside bordered panels. The only explicit elevation is the marker popup (Material elevation 8). Dialogs, bottom sheets and snackbars use Material defaults with a dark scrim. There is no BoxShadow in the UI layer. The map scene draws its own drop shadows from the map data.

## Shapes

All borders are 1px. Radii: 3 (requirement rows), 4 (inputs, buttons, verdict box, value tiles, history tiles), 5 (panels), 6 (dialogs, marker tiles) and 12 (marker popup). The bars are square. Buttons are 4px-rounded rectangles, and the floor buttons are outlined rectangles with a gold filled state. Switches and checkboxes are Material 3 defaults in gold.

## Components

### Panel (GridPanel, CollapsibleGridPanel)
Deep Pine fill, Olive Rule border, 5px radius, 16px padding. The header has a 26px gold icon, a 16px/600 title and an optional muted subtitle, followed by a 15px gap. The collapsible variant makes the whole header a button with a gold chevron and no animation.

### Decision card
A panel whose title names the source ("Picked item", "History inspection", "Accepted scan", "Corrected scan"). In the wide layout it has a 185px image well with the item icon, short name and slot size. Then come:
- the item name at 23px, with the raw item ID below it;
- the verdict box;
- three 180px value tiles (Flea price, best trader, "Still needed"), each with a 12px caption, a 17px/600 value and a per-slot line;
- warning bullets in gold, clipped when the card is short.

### Verdict box
A gold 22px/600 label inside an inset box with a gold border and 4px radius. Keep, Keep for later, Check / May Need, Flea, Trader and Price unavailable all look the same.

### Requirement row
Inset fill, Moss Rule border, 3px radius, 10px padding. It has a w600 task name, a gold "Task • Done" state line and muted detail lines. Optional uses collapse under a chevron.

### Navigation tabs
Icon and label. The selected tab has an olive fill (#191c10), a 2px gold underline and a gold icon and label.

### Buttons
Outlined rectangles (Moss Rule, Bone text, 18px icon) for most actions. Gold filled for "Save map files", "Save token" and the selected floor or FIR choice. Text buttons in gold ("Close", "Clear stats").

### Marker tiles
88×76 inset tiles with a 24px badge and an 11px label. A shown tile has an Olive Rule border and a green check; a hidden tile is muted.

### Marker popup
Deep Pine, 12px radius, elevation 8, at most 360×480. It has a small category label, a close button and a title over the facts, and a gold tether line to the marker.

### Status footer
A centred row of muted 12px status items. Live scan is 11px and turns gold when on.

## Do's and Don'ts

This records practice as built. It is not guidance for new work.

### Observed practice
- Gold is the default emphasis for anything that matters, from verdicts to warnings to section labels.
- Every region is a bordered panel with an icon and a title, at equal weight.
- The verdict does not change its look with its meaning. Only the word changes.
- Uppercase, tracked labels mark sections and the brand.
- Errors appear in up to four places (Map screen, pins sheet, Manual controls, Settings), in coral or gold depending on the place.
