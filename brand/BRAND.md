---
name: Ember
description: "A quiet, dark-first workbench system for tools people stay in for hours: layered near-black surfaces, hairline dividers, one warm accent, a compact sans for the tool and a bookish serif for the user's own words."
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
---

# Design System: Ember

## Overview

**Creative North Star: "The Lamplit Workbench"**

A dark room, one warm lamp, and the work in the middle of the bench. Ember is for tools people stay inside for long sessions (editors, knowledge tools, planners, consoles), not for marketing pages. The user's material sits in the centre; navigation is compact, quiet and always within one keystroke. Surfaces are layered near-blacks separated by hairlines. The only warm light in the room is the accent, Ember, and it is spent on whatever the user is touching: the current selection, linked references, the caret, keyboard focus and the one primary action.

Density is deliberate. The chrome uses compact Geist at 13px with tabular figures, so lists, counts and metadata stay legible at a glance. Long-form content switches to Literata at 17px with a 1.75 line height, so reading stays comfortable. Information is shown rather than hidden behind drill-downs, but every surface stays calm: monochrome one-stroke icons, pill controls, soft 8–12px corners, no decorative art.

Ember was first built for Mythspine, a desktop writing app; its DESIGN.md is the worked example of this system applied to a real product. This file keeps only what carries over to another product.

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

## Using Ember in another product

- **Web:** link `tokens.css` and `components.css`, add `class="em"` to `<body>`, and set `data-theme="light"` on `<html>` for the light room (without it, the OS preference decides). Fonts load from `fonts/` relative to `tokens.css`.
- **Flutter:** copy `flutter/` into `lib/theme/`, then `MaterialApp(theme: emberTheme(Brightness.light), darkTheme: emberTheme(Brightness.dark))`. Read Ember roles Material has no slot for with `Theme.of(context).extension<EmberColors>()!`. Bundle Geist and Literata as font assets (`.ttf` from the google/fonts repository, OFL); the `.woff2` files here are for the web only.
- **Changing tokens:** edit `tokens.json`, then run `node brand/tools/build.mjs` to regenerate `tokens.css` and `flutter/ember_tokens.dart`. Keep BRAND.md's frontmatter in step.
- **Making it yours:** a product may rename Ember, swap the accent (keeping fill, text, ink, soft and line variants that pass contrast in both rooms) or swap the serif. Keep the structure: one accent, tonal depth, two voices, one motion family. Write the product's own DESIGN.md that cites this file and records what it changed.
