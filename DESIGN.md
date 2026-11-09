---
name: Blackgrid
description: "Blackgrid on Ember, the system it shares with Mythspine: a dark-first desktop companion for raid-time keep/sell decisions and the map, with layered near-black surfaces, hairline dividers and one warm accent. The answer comes first and is readable at a glance."
colors:
  accent: "#e9a14b"
  accent-text: "#eeab5c"
  accent-ink: "#1a1206"
  accent-soft: "rgba(233,161,75,.13)"
  accent-line: "rgba(233,161,75,.42)"
  focus: "#e9a14b"
  canvas: "#0c0c0e"
  panel: "#121215"
  raised: "#18181c"
  hover: "#1f1f24"
  press: "#26262c"
  hairline: "rgba(255,255,255,.07)"
  hairline-strong: "rgba(255,255,255,.12)"
  ink: "#e8e6e1"
  ink-secondary: "#aaa69f"
  ink-tertiary: "#87837c"
  prose: "#dcd9d2"
  ok: "#6fcf8e"
  warn-bg: "rgba(232,128,92,.08)"
  warn-line: "rgba(232,128,92,.28)"
  warn-ink: "#f0b49a"
  warn-strong: "#f7d0bd"
  err-bg: "rgba(240,96,96,.08)"
  err-line: "rgba(240,96,96,.3)"
  err-ink: "#f3a3a0"
  light-accent: "#d98a2b"
  light-accent-text: "#8a4c05"
  light-accent-ink: "#1d1206"
  light-accent-soft: "rgba(217,138,43,.14)"
  light-accent-line: "rgba(186,108,18,.5)"
  light-focus: "#8a4c05"
  light-canvas: "#f7f6f3"
  light-panel: "#efede9"
  light-raised: "#ffffff"
  light-hover: "#e6e3de"
  light-press: "#dcd8d1"
  light-hairline: "rgba(30,24,16,.09)"
  light-hairline-strong: "rgba(30,24,16,.15)"
  light-ink: "#1d1b18"
  light-ink-secondary: "#565149"
  light-ink-tertiary: "#6c675e"
  light-prose: "#2a2722"
  light-ok: "#2f9a57"
  light-warn-bg: "#fbeee6"
  light-warn-line: "#efc6b0"
  light-warn-ink: "#8a3d1c"
  light-warn-strong: "#6e2d10"
  light-err-bg: "#fbeaea"
  light-err-line: "#efbcbc"
  light-err-ink: "#9b2420"
  map-ground: "#0c0c0e"
  light-map-ground: "#0c0c0e"
  ok-fill: "#6fcf8e"
  ok-on-fill: "#0c0c0e"
  ok-bg: "rgba(111,207,142,.10)"
  ok-line: "rgba(111,207,142,.32)"
  ok-ink: "#a6e3ba"
  ok-strong: "#cdeed8"
  light-ok-fill: "#1f6b3b"
  light-ok-on-fill: "#ffffff"
  light-ok-bg: "#e8f5ec"
  light-ok-line: "#b5dcc2"
  light-ok-ink: "#1f6b3b"
  light-ok-strong: "#154d2a"
typography:
  display:
    fontFamily: "Literata, Georgia, serif"
    fontSize: "30px"
    fontWeight: 500
    lineHeight: 1.2
    letterSpacing: "-0.015em"
  headline:
    fontFamily: "Literata, Georgia, serif"
    fontSize: "22px"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "-0.01em"
  title:
    fontFamily: "Literata, Georgia, serif"
    fontSize: "19px"
    fontWeight: 500
    lineHeight: 1.2
    letterSpacing: "-0.01em"
  prose:
    fontFamily: "Literata, Georgia, serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.75
  prose-small:
    fontFamily: "Literata, Georgia, serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.6
  body:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.45
    fontFeature: "\"tnum\" 1"
  ui-heading:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 600
    lineHeight: 1.45
  control:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "12.5px"
    fontWeight: 500
    lineHeight: 1.45
  label:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "11.5px"
    fontWeight: 500
    lineHeight: 1.45
  verdict:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: 1.2
  mono:
    fontFamily: "ui-monospace, Cascadia Mono, Consolas, monospace"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.7
rounded:
  s: "6px"
  m: "8px"
  l: "12px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  2xl: "32px"
components:
  top-bar:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    height: "44px"
  rail:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink-secondary}"
    width: "52px"
  rail-item-active:
    backgroundColor: "{colors.accent-soft}"
    textColor: "{colors.accent-text}"
  sidebar:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.ink-secondary}"
    width: "268px"
  inspector:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.ink}"
    width: "352px"
  status-bar:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink-tertiary}"
    typography: "{typography.label}"
    height: "28px"
  button:
    textColor: "{colors.ink}"
    typography: "{typography.control}"
    rounded: "{rounded.pill}"
    padding: "0 12px"
    height: "28px"
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.accent-ink}"
    typography: "{typography.control}"
    rounded: "{rounded.pill}"
    padding: "0 12px"
    height: "28px"
  button-quiet:
    textColor: "{colors.ink-secondary}"
    rounded: "{rounded.pill}"
    padding: "0 12px"
    height: "28px"
  icon-button:
    textColor: "{colors.ink-secondary}"
    rounded: "{rounded.m}"
    size: "28px"
  segmented:
    backgroundColor: "{colors.raised}"
    rounded: "{rounded.pill}"
    padding: "2px"
  segmented-option-selected:
    backgroundColor: "{colors.press}"
    textColor: "{colors.ink}"
  chip:
    textColor: "{colors.ink-secondary}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 10px"
    height: "24px"
  chip-selected:
    backgroundColor: "{colors.accent-soft}"
    textColor: "{colors.accent-text}"
  input:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.ink}"
    rounded: "{rounded.m}"
    padding: "7px 10px"
  panel:
    backgroundColor: "{colors.panel}"
    rounded: "{rounded.l}"
    padding: "18px"
  card:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.ink}"
    rounded: "{rounded.m}"
    padding: "10px 12px"
  row:
    textColor: "{colors.ink-secondary}"
    rounded: "{rounded.m}"
    height: "30px"
  menu:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.ink}"
    rounded: "{rounded.l}"
    padding: "6px"
  toast:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    padding: "8px 14px"
  monogram:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.accent-text}"
    rounded: "{rounded.l}"
    size: "48px"
  verdict-keep:
    backgroundColor: "{colors.ok-fill}"
    textColor: "{colors.ok-on-fill}"
    typography: "{typography.verdict}"
    rounded: "{rounded.m}"
    height: "44px"
    padding: "0 16px"
  verdict-keep-later:
    backgroundColor: "{colors.ok-bg}"
    textColor: "{colors.ok-strong}"
    typography: "{typography.verdict}"
    rounded: "{rounded.m}"
    height: "44px"
    padding: "0 16px"
  verdict-check:
    backgroundColor: "{colors.warn-bg}"
    textColor: "{colors.warn-strong}"
    typography: "{typography.verdict}"
    rounded: "{rounded.m}"
    height: "44px"
    padding: "0 16px"
  verdict-sell:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.ink-secondary}"
    typography: "{typography.verdict}"
    rounded: "{rounded.m}"
    height: "44px"
    padding: "0 16px"
  verdict-unavailable:
    textColor: "{colors.ink-tertiary}"
    typography: "{typography.verdict}"
    rounded: "{rounded.m}"
    height: "44px"
    padding: "0 16px"
  row-dense:
    textColor: "{colors.ink-secondary}"
    typography: "{typography.body}"
    rounded: "{rounded.s}"
    height: "24px"
    padding: "0 8px"
  freshness-tag:
    textColor: "{colors.ink-tertiary}"
    typography: "{typography.label}"
    rounded: "{rounded.s}"
    height: "20px"
    padding: "0 6px"
  freshness-tag-stale:
    backgroundColor: "{colors.warn-bg}"
    textColor: "{colors.warn-ink}"
  item-frame:
    backgroundColor: "{colors.raised}"
    rounded: "{rounded.l}"
    size: "96px"
  map-viewport:
    backgroundColor: "{colors.map-ground}"
  answer-strip:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    height: "76px"
    padding: "0 16px"
  toggle-switch:
    backgroundColor: "{colors.hairline-strong}"
    textColor: "{colors.ink-tertiary}"
    rounded: "{rounded.pill}"
    width: "28px"
    height: "16px"
  toggle-switch-on:
    backgroundColor: "{colors.ink-secondary}"
    textColor: "{colors.canvas}"
  history-row:
    textColor: "{colors.ink-secondary}"
    typography: "{typography.body}"
    rounded: "{rounded.m}"
    height: "38px"
    padding: "0 8px"
---

# Design System: Blackgrid

<!-- Started on 2026-11-06 from brand/BRAND.md (Ember), the system Blackgrid shares with Mythspine. Everything above "Blackgrid extensions" is the shared Ember system, unchanged apart from this file's name, description and the Mythspine paragraph in the Overview. Blackgrid's additions are listed with their reasons under "Blackgrid extensions". The owner approved some widenings of shared rules for Blackgrid on 2026-11-06 (see "Owner decisions"). They are recorded only here, as approved family extensions; the shared kit in `brand/` and in Mythspine is not changed. Any further change to a shared token or rule goes to the owner first. -->

## Overview

**Creative North Star: "The Lamplit Workbench"**

A dark room, one warm lamp, and the work in the middle of the bench. Ember is for tools people stay inside for long sessions (editors, knowledge tools, planners, consoles), not for marketing pages. The user's material sits in the centre; navigation is compact, quiet and always within one keystroke. Surfaces are layered near-blacks separated by hairlines. The only warm light in the room is the accent, Ember, and it is spent on whatever the user is touching: the current selection, linked references, the caret, keyboard focus and the one primary action.

Density is deliberate. The chrome uses compact Geist at 13px with tabular figures, so lists, counts and metadata stay legible at a glance. Long-form content switches to Literata at 17px with a 1.75 line height, so reading stays comfortable. Information is shown rather than hidden behind drill-downs, but every surface stays calm: monochrome one-stroke icons, pill controls, soft 8–12px corners, no decorative art.

Ember was first built for Mythspine, a desktop writing app. Blackgrid is its sibling: a desktop companion that sits beside a game and answers "keep this item or sell it?" and "where am I, and where are my extracts?". Someone who uses both apps should recognise one family. The owner confirmed this reading of Ember's two voices for Blackgrid (2026-11-06, Q4). The subject on screen is the item being judged or the map being read, so its name takes the serif title roles. Everything Blackgrid computes or reports is the tool speaking, in Geist. The player's own words are pin labels and notes, in Literata.

**Key Characteristics:**
- Dark-first; a warm paper-light theme mirrors the same structure under the same token names.
- One accent, Ember, reserved for selection, links, caret, focus and primary actions.
- Layered near-black surfaces divided by hairlines; shadows only on floating layers.
- Two type voices: compact Geist for the tool, Literata for the user's own words.
- Pills for controls, soft 8–12px corners for containers.
- One motion family: panels slide, stretch and collapse in 200ms with an exponential ease-out. Nothing else animates.

## Colors

A near-monochrome stack of warm-neutral greys with a single ember-amber accent; the light theme is the same structure on warm paper. Every role has a dark and a light value under one name (`tokens.json`).

### Accent
- **Ember** (`accent`): fills only. Used for the primary button, the selected-card edge, active drop indicators and badges.
- **Ember Text** (`accent-text`): the accent as text or icon. In light it drops to a deep #8a4c05 so small text stays readable on paper.
- **Ember Ink** (`accent-ink`): text on an Ember fill.
- **Ember Glow** (`accent-soft`): translucent fill for selected chips, active rail items, the current row and the focus halo.
- **Ember Thread** (`accent-line`): semi-opaque accent for selected borders and link underlines.
- **Focus** (`focus`): the 2px keyboard outline. Equal to Ember in dark; in light it matches Ember Text.

### Neutral
- **Night Desk** (`canvas`): the page itself: top bar, rail, main column, status bar.
- **Shelf** (`panel`): docked side panels and in-page panels, one step lighter than the desk.
- **Lifted Card** (`raised`): anything that sits on top: inputs, cards, menus, toasts, tooltips, monograms.
- **Hover** (`hover`) and **Press** (`press`): row and button hover; Press is the selected segment in dark (white in light, `segment-on`).
- **Hairline** (`hairline`) and **Strong Hairline** (`hairline-strong`): 7% and 12% white (warm black in light). Hairline divides regions; Strong Hairline outlines controls, chips and floating layers.
- **Ink**, **Ink Secondary**, **Ink Tertiary**: the three text levels: content, controls and secondary text, meta and labels and counts.
- **Prose** (`prose`): a half-step softer than Ink, only for long-form serif text, to cut glare.

### Status
- **Saved Green** (`ok`): the saved-state dot only.
- **Warm Warning** (`warn-bg`, `warn-line`, `warn-ink`, `warn-strong`): conflicts and things that need a look.
- **Soft Error** (`err-bg`, `err-line`, `err-ink`): failed saves, unreadable records, validation errors.

### Named Rules
**The One Lamp Rule.** Ember is the only hue in the chrome. It marks what the user is touching and nothing decorative. If two Ember fills compete on one screen, one of them is wrong.

**The Readable Ember Rule.** Ember as a fill and Ember as text are different tokens. Small text and focus rings use Ember Text / Focus; never set small text in the raw fill colour on paper.

**The Same Room Rule.** Light and dark share every token name, every structure and the same accent. A component may not branch on theme except through tokens (the scrim is the one documented exception, and it is a token too).

## Typography

**Display Font:** Literata (with Georgia, serif)
**Body Font:** Geist (with system-ui, sans-serif)
**Mono:** ui-monospace / Cascadia Mono / Consolas, for source or code views only

**Character:** A crisp, compact grotesk runs the machinery while a warm, bookish screen serif carries everything the user wrote. The split is semantic: if the words belong to the user's material, they are Literata; if they belong to the tool, they are Geist.

### Hierarchy
- **Display** (Literata 500, 30px, 1.2, -0.015em): the title of the thing being worked on. Balanced wrapping.
- **Headline** (Literata 500, 22px, 1.25, -0.01em): empty-state headings, title fields in forms.
- **Title** (Literata 500, 19px, 1.2, -0.01em): the name of a record in a side panel.
- **Prose** (Literata 400, 17px, 1.75; 16px on narrow screens): long-form content in a 66ch column.
- **Prose Small** (Literata 400, 14px, 1.6): summaries, notes, description textareas.
- **Body** (Geist 400, 13px, 1.45, tabular figures): the whole UI default.
- **UI Heading** (Geist 600, 13px): panel and sidebar titles. Chrome never goes larger than body size; hierarchy in the chrome comes from weight and colour.
- **Control** (Geist 500, 12.5px): buttons, segments, toasts.
- **Label** (Geist 500, 11.5px): section labels, counts, chips, status bar. Sentence case, never uppercase.

### Named Rules
**The Two Voices Rule.** User content is Literata; tool content is Geist. Never set a control in the serif or a long paragraph of user content in the sans.

**The Flat Chrome Scale Rule.** Chrome text lives between 11px and 13px. Anything bigger is a serif title belonging to the subject on screen.

## Layout

The reference shell is a fixed desktop frame: four columns (icon rail 52px, contextual sidebar 268px, main `minmax(0, 1fr)`, inspector 352px) and three rows (top bar 44px, content, status bar 28px). Top and status bars span the full width. Products without a rail or inspector drop those columns; the proportions of what remains stay the same.

Spacing is a compact 4px rhythm with frequent 6/10/14px half-steps: 4–8px inside controls, 8–12px between rows and chips, 14–18px panel padding, 24–28px between page sections. Pages scroll inside the main column with 44px top and 32px side padding; long-form text caps at 66ch.

**Responsive.** At ≤1080px the inspector leaves the grid and becomes an overlay sheet from the right (with Float and a scrim). At ≤760px the rail and sidebar become one slide-in drawer behind a scrim, and prose drops to 16px. Inside the main column, components respond to the column's own width (container queries; `LayoutBuilder` in Flutter), not the window's.

### Named Rules
**The Centre Holds Rule.** Opening, stretching or closing a side panel never replaces the central subject. Whatever the user is working on, including an unsaved draft, stays mounted underneath.

## Elevation & Depth

Depth is tonal, not shadowed. At rest every region is flat: desk, shelves and lifted cards are separated by one luminance step and a hairline. Shadows exist only on things that float and must read as temporary: menus, the command palette, toasts, tooltips and overlay sheets. A scrim (`scrim`) sits behind modal layers.

### Shadow Vocabulary
- **Float** (`shadow.float`): menus, palette, toasts, tooltips, overlay sheets, a dragged item.
- **Seated** (`shadow.seated`): the selected option in a segmented control.
- **Focus Halo** (`0 0 0 3px` Ember Glow): text inputs while focused, with an Ember border.

### Named Rules
**The Flat Desk Rule.** Docked surfaces never cast shadows. If it is part of the shell, it is separated by tone and a hairline; if it floats, it gets Float.

## Shapes

Soft, small curves; nothing sharp, nothing bubbly. 8px (`rounded.m`) for rows, inputs, cards and icon buttons; 12px (`rounded.l`) for panels, banners, menus and monograms; 6px (`rounded.s`) for tooltips, tags and the focus outline. Anything you press to change mode or state is a full pill: buttons, segmented controls and their options, chips, toasts. Borders are always 1px; a dashed border means a fixed, read-only value or a broken link. Icons are 24-unit, one-stroke (1.6px, round caps and joins), monochrome, drawn at 16px (12–14px inside small controls).

### Named Rules
**The Pill Means Press Rule.** Pills are for controls; containers get soft corners. A pill-shaped container (except a toast or a graph node) or a square button is off-system.

## Components

Every component below is in `components.css` (class prefix `em-`) and on `specimen.html`. State is expressed with ARIA attributes (`aria-pressed`, `aria-selected`, `aria-current`, `aria-invalid`) so the styling and the semantics cannot drift apart.

### Buttons (`.em-btn`, `.em-ib`)
- **Shape:** full pill, 28px tall, 12px padding; large variant 34px / 16px (`data-size="large"`).
- **Default:** transparent with a Strong Hairline border, Ink text, Control type, 14px icon with a 6px gap.
- **Primary** (`data-variant="primary"`): Ember fill, Ember Ink text. One per view.
- **Quiet** (`data-variant="quiet"`): borderless, Ink Secondary.
- **Hover / Focus / Disabled:** Hover fill (primary brightens 7%); 2px Focus outline at 2px offset; 45% opacity with a not-allowed cursor, ideally with a hint saying why. No transitions.
- **Icon buttons:** 28px square, 8px radius, Ink Secondary; Hover fill and Ink on hover or when `aria-pressed`.

### Segmented controls (`.em-seg`)
Pill track (Lifted Card, Hairline border, 2px inset) of 24px pill options in Ink Secondary; the selected option takes `segment-on`, Ink and the Seated shadow. For mutually exclusive views and tabs.

### Chips (`.em-chip`)
24px pill, Strong Hairline border, Ink Secondary, Label type. Pressed or current: Ember Glow fill, Ember Thread border, Ember Text. Filters and read-only tags; a removable chip carries an 18px round ✕.

### Fields (`.em-field`, `.em-input`, `.em-textarea`)
Lifted Card fill, Strong Hairline border, 8px radius, 7/10px padding; label above in 12px/500 Ink Secondary. Title fields may use Headline serif, description fields Prose Small. Focus: Ember border plus the Focus Halo. `aria-invalid` turns the border Soft Error with the message below in 12px Error ink, and the value is not saved until fixed. Fixed values render as a 34px dashed row with a lock icon (`.em-fixed`).

### Containers (`.em-panel`, `.em-card`, `.em-row`)
- **Panel:** Shelf, Hairline, 12px radius, 18px padding, 14px gap. No shadow.
- **Card:** Lifted Card, Hairline (Strong on hover), 8px radius. The current card (`aria-current`) takes an Ember Thread border and a 3px inset Ember edge.
- **Row:** 30px minimum, 8px radius, Ink Secondary; Hover fill and Ink on hover or when current; trailing meta in Ink Tertiary.

### Banners (`.em-banner`)
Inline, never modal; they say what happened and what was kept. Info (Lifted Card, Strong Hairline), Warning (`data-tone="warn"`) and Error (`data-tone="error"`) triplets; 12px radius, 10/12px padding, 12.5px text, a leading 16px icon, a medium-weight first line, and 24px pill actions outlined in `currentColor`.

### Menus and toasts (`.em-menu`, `.em-toast`)
Menus are 220px+ Lifted Card panels, 12px radius, Float, 6px padding, with 8px-radius items carrying optional small descriptions or a key cap; arrow keys move (skipping disabled items), Escape returns focus to the opener. Toasts are Lifted Card pills with Float, bottom-centre, no motion: plain messages go after about 2.6s; a toast with an action (Undo) shows it as an Ember Text link and stays 8s. At most two stack.

### Save state (`.em-save`)
A 6px dot plus words: green Saved, Ember busy (Saving…, Unsaved changes), Error ink for not saved or conflict. Never claim a save that did not happen.

### Monogram (`.em-monogram`)
48px (24px small) Lifted Card tile with serif initials in Ember Text. Any record without a picture is complete with its monogram; a picture, when present, sits in the same frame and adds no chrome.

### Linked reference (`.em-ref`) (signature)
An inline link inside long-form text: Ink text with a 1.5px Ember Thread underline offset 4px; on hover or while its record is open, an Ember Glow background and a full-Ember underline. A broken reference has a dashed Ink Secondary underline. Opening it shows the record beside the text, never instead of it.

### Docked inspector (signature)
A 352px Shelf panel at the right with a tabbed segmented header, stretch and close. Stretching animates its width over the main column (rail and sidebar stay visible) and back; while stretched, the main column is inert and Escape collapses it. Closing returns focus to whatever opened it.

## Motion

**The One Motion Rule.** Only the panel family moves: sidebar collapse, inspector open/stretch/collapse, overlay sheets and drawers, all at 200ms on `cubic-bezier(.16, 1, .3, 1)`. Hovers, tabs, menus, the palette, toasts and banners change instantly. Reduced-motion users get effectively instant panels (1ms). Direct manipulation (dragging, panning, zooming) follows the pointer and lands instantly; that is not animation.

## Do's and Don'ts

### Do:
- **Do** spend Ember only on what the user is touching, and keep one primary button per view.
- **Do** separate docked regions with tone and a hairline; save shadows for things that float.
- **Do** set the user's own words in Literata and everything the tool says in Geist.
- **Do** show state in words as well as colour (Saved, Not saved, Changed elsewhere) and say what was kept when something fails.
- **Do** give every drag a keyboard and menu equivalent, and pair every spatial view with a non-spatial one.
- **Do** design both rooms at once: every new token gets a dark and a light value.

### Don't:
- **Don't** add a second accent hue, gradients, glows or decorative illustration to the chrome.
- **Don't** use uppercase labels, letter-spaced small caps or chrome text larger than 13px.
- **Don't** put shadows on docked panels or cards at rest.
- **Don't** animate hovers, tabs, menus or toasts.
- **Don't** make square buttons or pill-shaped containers.
- **Don't** imply something saved, synced or exported when it did not.


## Blackgrid extensions

Each extension builds on Ember and changes none of its existing token values. New tokens carry a dark and a light value. Where an extension widens a shared rule (X1, X6, X9), the owner approved it for Blackgrid only (see "Owner decisions"). Each entry says what Blackgrid needs that the shared system does not cover, and why.

### X1. Verdict plates (`verdict-keep`, `verdict-keep-later`, `verdict-check`, `verdict-sell`, `verdict-unavailable`)
**Need.** The verdict (Keep, Keep for later, Check / May Need, Flea, Trader, Price unavailable) is the answer the product exists to give. Today all six look the same (`.impeccable/review/current/10-scanner-history-item.png`). A player glancing away from the game has to tell them apart before reading the word.

**In Ember's idiom.** A verdict is a 44px plate with 8px corners (`rounded.m`). It is a container, not a pill, because it states a fact rather than offering a press. The verdict word is set in the Verdict type role (Geist 600, 22px), an approved exception to the Flat Chrome Scale Rule (Q1). Flea and Trader add the price in the same role. The reason sits on the line below the plate in Body and is never clipped. Tone, ordered by how strongly the answer protects the player:
- **Keep** is a solid green plate: `ok-fill` with `ok-on-fill` text (dark 10.2:1; light `#1f6b3b` with white, 6.5:1). It is the strongest plate on any screen (Q2).
- **Keep for later** uses the green triplet: `ok-bg` fill, `ok-line` border, `ok-strong` text (dark 12.6:1; light 8.8:1).
- **Check / May Need** uses the Warm Warning triplet: `warn-bg` fill, `warn-line` border, `warn-strong` text. That triplet already means "things that need a look".
- **Flea** and **Trader** are a Lifted Card plate with Ink Secondary text and the price in Ink.
- **Price unavailable** has a dashed Ink Tertiary border and no fill. In Ember a dashed border already means a missing or broken value.

No verdict uses Ember: Ember stays on what the player is touching (the One Lamp Rule). Hue carries the meaning first, but fill strength and border style still differ, so Keep (solid), Flea and Trader (neutral) and Price unavailable (dashed) can be told apart without colour. Keep for later and Check share a structure and differ by word and hue.

### X2. Dense data rows (`row-dense`)
**Need.** Requirement lists, price breakdowns, marker lists and raid stats are tables of short facts. Ember's 30px row fits about two thirds as many per glance.

**In Ember's idiom.** A 24px row (`spacing.xs` vertical rhythm, 8px side padding, 6px corners, Body type with tabular figures). Numbers are right-aligned in their own column, and trailing meta is Ink Tertiary. Hover and current states are the same as Ember's Row. Use it only for tabular data. Navigation and pickable lists keep the 30px Row.

### X3. Freshness tag (`freshness-tag`, `freshness-tag-stale`)
**Need.** Blackgrid's advice depends on how old its inputs are ("Prices: 11:08", "price time unknown", "Tracker up to date"). Stale data is the most common reason for Check, and it has to sit next to the number it qualifies, not in a separate panel.

**In Ember's idiom.** A 20px read-only tag with 6px corners (Ember's tag radius) in Label type and Ink Tertiary, with no border. Once a value is older than its freshness limit (one hour for prices), it takes `warn-bg` and `warn-ink` and says so in words ("price 3 h old").

### X4. Live-scan state
**Need.** Live scan watches the player's clicks and the scan key, and the player must always know whether it is listening.

**In Ember's idiom.** It reuses the Save state pattern unchanged: a 6px dot plus words. Off has an Ink Tertiary dot; Listening ("Live scan on · F9 or click", with the player's key) has an Ember dot, Ember's established "busy" signal; Unavailable has an Error Ink dot and the reason. It lives in the status bar, and clicking it turns live scan on or off (X11). The key and the other live-scan options are in Settings (X12). No new token is needed.

### X5. Item frame (`item-frame`)
**Need.** The game's item picture is the fastest recognition cue, and it needs more room than a 48px monogram.

**In Ember's idiom.** The Monogram frame (Lifted Card, `rounded.l`, no chrome) at 96px. An item without a picture shows its short name as a monogram in the same frame. The picture keeps its own pixels: no tint and no border.

### X6. Map ground (`map-ground`, `map-viewport`)
**Need.** The map viewport shows third-party artwork and project marker glyphs drawn for a dark ground. Marker role colours are checked for at least 3:1 contrast against a dark badge background (ADR-0023).

**In Ember's idiom.** One token with the same value in both rooms (`#0c0c0e`, Night Desk's dark value). Following the Same Room Rule, the map branches on theme only through this token, as the scrim does. Everything around the map follows the room. The map canvas is subject content, but selection on it follows the family (Q3): the selected marker, extract or pin is drawn in Ember, not in ADR-0023's cyan band. The quest role (`#dcc05a`) and the loot role (`#e8a04a`, almost Ember's `#e9a14b`) move off the amber band, so the only amber on the map means "selected". The other role colours, the badge background and the at-least-3:1 contrast check stay. This file records the design intent. The change that restyles the map writes a new ADR superseding those parts of ADR-0023 and picks the new role values. The approved mock-up (`.impeccable/preview/ember-directions.html`) proposes quest `#8cb4ff` and loot `#7ed9c6`. The extract name labels are part of the same map palette (`lib/domain/map_zone_style.dart`: PMC `#7be495`, Scav `#f2c14e`, shared `#8cb4ff`, transit `#d29bf2`). The Scav label is on the amber band, so the ADR moves it off as well; otherwise amber would not mean only "selected". These are starting points, not decisions. Before fixing them, the ADR checks the new quest and loot values for at least 3:1 against the badge background, and for distance from the pin role (`#40c4ff`) and from every extract label colour. The proposed quest `#8cb4ff` is the shared label colour today, so one of the two must change. Markers keep the project's own glyphs from ADR-0023 on the map and in every marker list (X13).

### X7. The Answer First Rule (Blackgrid's layout rule)
**Need.** At narrow widths today, settings panels come before the verdict (`.impeccable/review/current/16-scanner-narrow-960.png`).

**In Ember's idiom.** It adds to the Centre Holds Rule.

**The Answer First Rule.** At every width, the current item's verdict and its reason are the first thing in the main column, above the fold. Settings, evidence and history may collapse, move into the inspector, or drop below; they never go above the answer.

### X8. Theme switch (System, Dark, Light)
**Need.** Ember designs both rooms, but Blackgrid has shipped only the dark one. The owner chose to ship both (Q6).

**In Ember's idiom.** A three-option segmented control in Settings: System (the default, following Windows), Dark and Light. The switch changes rooms instantly, with no animation (the One Motion Rule). Both rooms use the same token names; only `map-ground` keeps its dark value in the light room (X6).

### X9. Brand lockup exemption
**Need.** The header's "BLACKGRID" wordmark and "TRACK. PLAN. SURVIVE." tagline are set in tracked capitals, which Ember forbids in the chrome.

**In Ember's idiom.** The hex logo, wordmark and tagline form one brand asset. It is exempt from the no-uppercase rule and the Flat Chrome Scale Rule (Q5). The exemption covers only that lockup, in the top bar and on the startup screen. Every other label stays in sentence case.

### X10. The answer strip (Direction B shell)
**Need.** The owner chose Direction B, "Answer strip" (2026-11-06). Players glance at Blackgrid for a few seconds at a time, in either area. Today the answer sits in a panel on the Scanner and in the rail on the Map, and it competes with configuration panels (`09-scanner-default.png`, `01-map-default.png`).

**In Ember's idiom.** The reference shell keeps its top bar, main column and status bar, and drops the icon rail and sidebar. Map and Scanner are a two-option segmented control in the top bar. Under the top bar, on both areas, sits one full-width strip (`answer-strip`) holding:
- the item frame (X5) at 48px;
- the item name in Literata Title;
- the verdict plate (X1), with its reason below;
- the price and its freshness (X3).

The Found in raid control (Unknown, Yes, No) sits beside the verdict plate, because it belongs to this item and can change its verdict.

With no item, the strip says "Find an item" with the Ctrl K hint. The main column below belongs to the current area: the map with its map picker and floor control (X13), or the Scanner's details (requirements as dense rows, the price breakdown, scan evidence). The docked inspector on the right holds the area's working lists: on the Scanner, recent items (X14); on the Map, this raid's extracts, the markers (X13) and pins. The player can close it from the top bar. Settings are a page of their own (X12), never permanent panels. In a narrow window the strip wraps to two lines but stays first (the Answer First Rule, X7), and the inspector floats over the main column. The strip is a Panel surface, divided from the main column by a hairline. It has no shadow and does not move.

The approved state of this shell is the B view of `.impeccable/preview/ember-directions.html` (round 2, owner approval 2026-11-06). It is a static mock-up: names, prices and the map are illustrative.

### X11. Top bar and status bar
**Need.** The raid timers (time in raid, run-through, scav cooldown) are read during and between raids, as often as the verdict. Today they sit in a strip under the header. Settings, Stats and Import must be easy to find; an unlabelled gear icon was missed in review (owner feedback 2026-11-06).

**In Ember's idiom.** The top bar holds, from left to right: the brand lockup (X9), the Map/Scanner switch, the item search (Ctrl K), then the raid timers, the inspector button, and Settings, Stats and Import as quiet buttons with an icon and a label. Each timer is a Label-type name with its value in Ink and tabular figures, separated by hairlines. The run-through value takes `warn-ink` while it counts down. The Raid timers settings decide which timers show (X12). In a narrow window the three buttons drop their labels and keep their tooltips, and the lockup keeps only the hex logo.

The status bar holds status that can be changed in one click: the game mode (click to switch), item data freshness and Tracker state (click to open their Settings section), and live scan (X4, click to turn on or off). Each item is a quiet text button that shows a Hover fill. Everything there is also in Settings.

### X12. Settings page
**Need.** Moving configuration out of the Map and Scanner rails (X7) needs one place where every setting lives. With seven groups, a dialog would scroll inside a scroll.

**In Ember's idiom.** Settings opens as a page in place of the strip and the main column; the top bar and status bar stay. A Panel sidebar on the left lists the sections and a "Back to Map/Scanner" quiet button. The page on the right is one scrolling column, at most 720px wide, with the page title in Literata Display and each section title in Literata Title. Each setting is a row: the name in Ink, a one-line explanation in Ink Tertiary, and the control on the right. Changes save as they are made, with no Save button except for the Tracker token. Stats and Import stay dialogs.

| Section | Settings |
|---|---|
| General | Theme (System, Dark, Light; X8), game mode (PvP, PvE, Seasonal; also in the status bar) |
| Live scan | Live scan on/off (also in the status bar), scan key, record scan frames. A click scans whenever live scan is on, as today; there is no separate setting for it |
| Item data | Refresh item data, with its freshness |
| Tracker progress | Use Tracker progress, token (save, remove), refresh progress |
| Game files | Game log folder, screenshot folder, follow logs |
| Raid timers | Show raid timers; time in raid, run-through and scav cooldown each on or off; run-through length (m:ss); Fence reputation per game mode |
| Map | Save marker filters |
| Diagnostics | A collapsed section at the end, closed each time Settings opens: the log, screenshot and raid-panel status lines, the folders in use, and the saved screenshot's source and age. It holds the debug detail the Map screen does not show |

Two controls stay on the work screens because they belong to what is in front of the player: Found in raid sits with the verdict (X10), and the marker switches and filters sit in the Map inspector (X13).

### X13. Map controls and the marker list
**Need.** The player has to switch maps by hand, pick a floor, and turn each marker type on or off. They also search markers and quests. Direction B's first mock-up dropped all of these, and its colour dots lost the marker icons (owner feedback 2026-11-06).

**In Ember's idiom.**
- **Map picker.** The map name, in Literata Title, is a button at the top left of the map that opens an Ember Menu listing every map, with a check on the current one. Following the logs picks the map when a raid starts; choosing a map by hand turns following off until it is turned back on in Settings, as today. The menu says so in a footnote. Below the footnote, a "Read latest screenshot" item keeps today's Read Latest action: it applies the newest saved screenshot to the selected map as assumed evidence. This is the only way to use a screenshot when the detected map differs from the selected one, or when the screenshot was saved before Blackgrid started watching. It is disabled while no screenshot folder is set and reads "Reading latest…" while it works.
- **Floor.** A segmented control beside the picker: Auto (follows the position from the last screenshot), then the map's floors.
- **Marker list.** The Markers section of the Map inspector starts with the filters: "Find markers" (comma means OR; markers that do not match are dimmed, not hidden), "Quest name contains", and the quest trader as one chip per trader plus All. Below them, "Show all" and "Hide all" links, then every marker type grouped (Extracts, Quests, Danger, Bosses, Spawns, Loot, Utility, Yours). Each row is 30px: the type's badge (ADR-0023's glyph in its role colour on the badge background, the same drawing as on the map), its name, its count on this map, and a `toggle-switch` on the right. A type that is off dims its badge and name.
- **Toggle switch** (`toggle-switch`, `toggle-switch-on`). A 28 × 16px pill track with a 12px knob. Off is a Hairline Strong track with an Ink Tertiary knob; on is an Ink Secondary track with a Canvas knob. It uses ink, not Ember, so the only amber in the map area stays the selection (One Lamp Rule, X6). The whole row is the press target. Settings rows use the same switch.

### X14. History rows with pictures
**Need.** The player recognises a recent item by its picture before its name (owner feedback 2026-11-06).

**In Ember's idiom.** A `history-row` is 38px: a 30px item frame (X5, `rounded.s`) with the item's picture, the name in Ink Secondary (ellipsis when long), a verdict dot, and how long ago in Ink Tertiary. The dot repeats the plate's language at 8px: solid green for Keep, a green ring for Keep for later, warning ink for Check, Ink Tertiary for Flea and Trader, and a dashed ring for Price unavailable. Current and hover rows follow Ember's Row.

## Owner decisions (2026-11-06)

The owner answered the questions raised when this file was started. Q1, Q2, Q3 and Q5 widen shared Ember rules. They apply to Blackgrid only, as approved family extensions; the shared kit in `brand/` and the Mythspine repository are not changed.

| # | Question | Decision |
|---|---|---|
| Q1 | Verdict size against the 13px Flat Chrome Scale | A Verdict type role, Geist 600 at 22px, for the verdict word and price only (X1) |
| Q2 | Green for Keep | Yes. A green set (`ok-fill`, `ok-on-fill`, `ok-bg`, `ok-line`, `ok-ink`, `ok-strong`) in both rooms, on Saved Green's hue (X1) |
| Q3 | Map selection against Ember | Selection on the map is Ember; the quest and loot roles move off the amber band. A new ADR superseding parts of ADR-0023 is written when the map is restyled (X6) |
| Q4 | Item and map names in Literata | Yes, in the serif title roles |
| Q5 | Wordmark and tagline in capitals | Exempt as a brand asset (X9) |
| Q6 | Ship the light room | Yes, with a System/Dark/Light switch (X8) |
| — | Redesign direction | B, "Answer strip" (X10) |

**Direction B, round 2 (2026-11-06).** The owner reviewed the first B mock-up and asked for seven fixes, then chose four layouts. The owner approved the result as settled.

| # | Owner feedback or question | Decision |
|---|---|---|
| R1 | Markers need their icons, on the map and in the list, and must be switchable | ADR-0023 glyphs everywhere; per-type switches in the Map inspector (X13) |
| R2 | The map must still be switchable by hand | Map picker on the map (X13) |
| R3 | The scav and run-through timers are missing | All three raid timers in the top bar (X11) |
| R4 | History entries need pictures | History rows with item pictures (X14) |
| R5 | Settings are hard to find | Labelled Settings, Stats and Import buttons (X11) |
| R6 | Settings removed from the rails need a home | The Settings page with every setting (X12) |
| R7 | The marker, quest and trader search is missing | Filters at the top of the marker list (X13) |
| C1 | Where the raid timers go | Top bar (not the status bar) |
| C2 | Quick marker buttons on the map | No; switches only in the inspector, the map stays clean |
| C3 | Marker and quest search | Its own filters in the Map inspector; the top search stays for items |
| C4 | What Settings opens as | A full page with a section list (not a larger dialog) |

## Adopting the kit in Blackgrid

- The Flutter token and theme files stay in `brand/flutter/` until the first M8.5 implementation change. They have never been compiled; the first implementation change moves them into `lib/` and runs `mise run analyze`.
- Flutter needs Geist and Literata as `.ttf` font assets (from the google/fonts repository, OFL). The `.woff2` files in `brand/fonts/` are for the web only. Bundling them adds their OFL texts to `THIRD_PARTY_NOTICES.md`.
- Token values come from `brand/tokens.json`. Regenerate with `node brand/tools/build.mjs` and keep this file's frontmatter in step. Blackgrid's own tokens and roles (X1–X14) are listed only here, so they never leak into the shared kit.
