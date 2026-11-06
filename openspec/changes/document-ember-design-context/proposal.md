# Proposal

## Why

Blackgrid is about to be redesigned so that it reads as a sibling of Mythspine. Both apps should share the Ember visual system. Before anyone changes `lib/`, the redesign needs product context and design authority in the repository:

- the brand kit itself;
- a product record that design work can read;
- an honest record of how Blackgrid looks today;
- a DESIGN.md that applies Ember to Blackgrid.

Without these, each redesign step would re-derive the brand from another repository and would lose the before state.

The user chose (2026-11-06) to give the redesign a milestone of its own, M8.5 "Ember interface", after M8 and before M9, and picked Direction B, "Answer strip". This change is M8.5's first change: it adds the milestone to the roadmap and sets up the design context. It advances no M8 exit criterion.

## What Changes

- Add `brand/`: a real copy of the Ember brand kit from Mythspine, with its fonts and their OFL licences. Its Flutter files (`brand/flutter/`) are not wired into `lib/`.
- Add `PRODUCT.md`: Blackgrid's product record for design work (users, purpose, positioning, operating context, constraints, brand commitments).
- Add `.impeccable/review/current/`: screenshots of the current app taken before the redesign, a `PROVENANCE.md` listing each one, and `DESIGN.before.md`, a record of today's visual system in DESIGN.md format.
- Add `DESIGN.md` and its sidecar `.impeccable/design.json`. DESIGN.md is started from `brand/BRAND.md` and renamed for Blackgrid. It keeps the shared Ember tokens unchanged and lists Blackgrid's extensions X1–X14, with reasons, in a "Blackgrid extensions" section. The owner's answers to the questions raised while it was written (verdict size, green for Keep, map selection, serif names, the brand lockup, the light theme, Direction B) are recorded in its "Owner decisions" table, together with the owner's second review of Direction B (marker icons and switches, map picker, raid timers, history pictures, the Settings page, marker and quest filters).
- Add `.impeccable/preview/ember-directions.html`: a static HTML mock-up of Directions A, B and C built from the kit's CSS and the project's marker icons. Its B view, round 2, is the layout the owner approved. It is a design reference, not shipped and not part of the app build.
- Plan edits: add M8.5 to `openspec/roadmap.md` as Next, with exit criteria and a proposed split that the user agrees when it is promoted; move M9 to the head of Later with its agreed split unchanged; replace STRATEGY.md's brand line with Ember.
- No application code, tests or assets under `lib/`, `test/`, `assets/` or `windows/` change.

## Capabilities

### New Capabilities

None. This change records design context only; no system behaviour changes, so it sets `skip_specs: true`.

### Modified Capabilities

None.

## Impact

- New top-level files `PRODUCT.md` and `DESIGN.md`, and new folders `brand/` and `.impeccable/` (sidecar, before record, mock-up).
- Edited plan files: `openspec/roadmap.md` (M8.5 added, M9 moved under Later) and `STRATEGY.md` (brand line).
- `brand/` adds about 0.5 MB, mostly WOFF2 fonts and a specimen PNG. The fonts stay in `brand/` and are not bundled into the app.
- Third-party notices: Geist and Literata are under the SIL OFL 1.1. Their licence texts travel with them in `brand/fonts/`. They are not shipped in the app by this change.
- No dependency, build, data-format or runtime changes.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Setup only, no app code

- **Choice:** Bring in the brand kit and write PRODUCT.md, the before-redesign record and DESIGN.md. Leave `lib/` and the kit's Flutter files untouched until the user picks a redesign direction.
- **Rejected:** Wiring `ember_theme.dart` into the app now. The user asked for no app code changes before a direction is chosen, and the Dart files have never been compiled.
- **Reversal cost:** low
- **Important:** yes, because it binds future changes: the redesign builds on these documents.
- **Chosen by:** user

### S2: Shared Ember tokens stay unchanged; Blackgrid extends them, with owner-approved widenings

- **Choice:** Keep the palette, both themes, type, spacing, radii, elevation, component shapes, motion and rules as `brand/BRAND.md` defines them. Blackgrid adds extensions, listed with reasons. Where an extension widens a shared rule, the owner approves it first and DESIGN.md records it as an approved family extension for Blackgrid only. On 2026-11-06 the owner allowed the brand to be expanded for Blackgrid's use cases and approved four widenings (a 22px verdict role, a green set for Keep, Ember selection on the map, the brand lockup exemption). The kit in `brand/` and the Mythspine repository are not changed.
- **Rejected:** Changing the shared kit itself now, which would also change Mythspine; and refusing every widening, which would leave the verdict at 13px and Keep without green.
- **Reversal cost:** medium
- **Important:** yes, because it binds future changes and is visible to users.
- **Chosen by:** user

### S3: A new roadmap milestone, M8.5, for the redesign

- **Choice:** The redesign gets its own milestone, M8.5 "Ember interface", after M8 and before M9. This change is its first change and carries the roadmap entry, so the milestone and its setup land together. The rest of the split is an agent draft until the user agrees it at promotion.
- **Rejected:** Folding the work into M8 (map labels), placing it after M9, or leaving it unplanned.
- **Reversal cost:** low
- **Important:** yes, because it changes the roadmap.
- **Chosen by:** user

### S4: Ember supersedes STRATEGY.md's brand line

- **Choice:** PRODUCT.md records Ember as the brand commitment, and this change replaces STRATEGY.md's wording ("Dark Material 3, charcoal surfaces, restrained gold accents, green healthy/ready/success states") with Ember.
- **Rejected:** Keeping both brand lines in force.
- **Reversal cost:** low
- **Important:** yes, because it is visible to users.
- **Chosen by:** user

### S5: The before-redesign record lives beside the screenshots

- **Choice:** Write the impeccable `document` output for today's UI to `.impeccable/review/current/DESIGN.before.md`. The root `DESIGN.md` then holds the Ember system.
- **Rejected:** Writing today's UI to `DESIGN.md` and then overwriting it, which would lose the before record. Also rejected: committing the before record to `docs/`, which would put a retired design system next to current documentation.
- **Reversal cost:** low
- **Important:** no
- **Chosen by:** agent

## Release Notes

Design groundwork for an interface redesign. The app itself does not change.

### Added

- Design context for the coming interface redesign (M8.5): the Ember brand kit, a product record, a before-redesign record of the current interface, and a DESIGN.md that applies Ember to Blackgrid in the "Answer strip" layout.
