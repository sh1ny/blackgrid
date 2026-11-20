# Proposal

## Why

The owner's M8.5 check of the Ember interface found three small faults that are still there:

- The "Last scan not accepted — pick the item" block in the answer strip scrolls inside a box 64–130 px tall, so its search results hide behind a scroll bar.
- The map credit at the bottom left of the Map is dim and shows a bare name, which does not say what the name is.
- On windows wider than about 1920 px, Stats, Import and Settings stop short of the top bar's right edge. The existing `workspace-shell` scenario "Wide tools alignment" already asks for them to align at the right edge, but its test runs at 1660 px wide, where the fault does not show.

This change is the last change of **M9 - local progress tracker** (change 9 of 9). The owner scoped it on 2026-11-20 to exactly these three fixes. It serves the user-verified exit criterion "On live scans, Found in raid reads correctly for found and not-found items, and the `polish-ember-ui` fixes look right." That criterion is checked through a `[user]` task in tasks.md: the owner looks at the three fixes in the app. Agents do not run that check (AGENTS.md).

## What Changes

- **Correction offer fits without a scroll bar.** The answer strip no longer wraps the correction offer in its own height-capped scroll view. The offer's search results are laid out as wrapping buttons, like its candidates, so the block stays short. The answer strip's existing outer height limit is unchanged.
- **Map credit reads "Map creator: <name>" in primary ink.** The attribution under the map reads `Map creator: <author>` in the Ember theme's primary ink, not secondary ink. A pack map with no author keeps today's fallback, the map's name, without the prefix.
- **Top-bar tools reach the right edge on every wide window.** The search field keeps its 480 px maximum, and on wide windows of any width the space it does not use goes between the search and the timers. Timers, the inspector toggle, Stats, Import and Settings sit at the right edge.

No new capability, setting, data format or dependency.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `workspace-shell`: the top bar's tools align at the right edge on every wide window width, including widths above 1920 px.
- `scan-correction`: the offer is shown in the answer strip at its own height, with no scroll view of its own, and its search results wrap as buttons.
- `map-controls`: the artwork attribution reads `Map creator: <author>` in primary ink.

## Impact

- `lib/ui/shell.dart`: the wide top-bar row layout of the search slot.
- `lib/ui/answer_strip.dart`: the correction offer's height cap and scroll view are removed.
- `lib/ui/correction_offer_block.dart`: the search results become wrapping buttons.
- `lib/ui/map_workspace.dart`: the attribution text and colour.
- Tests: `test/ui/shell_test.dart`, the correction offer and answer strip widget tests, `test/ui/map_workspace_controls_test.dart`.
- No change to the game boundary, the scan pipeline, data or packs.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Scope is exactly the three fixes the roadmap lists

- **Choice:** the correction offer fit, the map credit and the top-bar alignment. Nothing else.
- **Rejected:** adding fixes from the new progress screens (Settings progress entry, the quest checklist, Map objectives). The owner declined them on 2026-11-20 and keeps the change small.
- **Reversal cost:** low
- **Important:** yes, because it changes behaviour users see
- **Chosen by:** user

### S2: The offer fits by a compact layout, not by a taller box

- **Choice:** remove the inner scroll view and lay the up-to-8 search results out as wrapping buttons, about 200 px tall at most in common cases.
- **Rejected:** keeping the vertical result list at its natural height (up to about 400 px), which pushes the map or Scanner content down.
- **Reversal cost:** low
- **Important:** yes, because it changes behaviour users see
- **Chosen by:** user

### S3: The credit uses the theme's primary ink

- **Choice:** the existing primary ink token (#E8E6E1 on the dark overlay).
- **Rejected:** prose ink (#DCD9D2), a smaller step; a larger size in secondary ink, which adds weight rather than contrast.
- **Reversal cost:** low
- **Important:** yes, because it changes behaviour users see
- **Chosen by:** user

### S4: A map with no author keeps the map name, without the prefix

- **Choice:** when a pack map has no `author`, show the map's name alone, as today.
- **Rejected:** `Map creator: unknown`, which states something about the artwork the pack does not say. Every map in the current pack has an author, so this is a fallback only.
- **Reversal cost:** low
- **Important:** no; no shipped map reaches it
- **Chosen by:** agent

## Release Notes

Three small fixes to the Ember interface. The "Last scan not accepted" block fits in the answer strip without a scroll bar. The map credit is easier to read and says who made the map. On wide screens, Stats, Import and Settings line up with the right edge of the top bar.

### Fixed

- The "Last scan not accepted — pick the item" block on Map and Scanner shows its search results as wrapping buttons and no longer scrolls inside a small box.
- The map credit at the bottom left of the Map is brighter and reads "Map creator: <name>".
- On windows wider than 1920 px, the top bar's timers, Stats, Import and Settings line up with its right edge.
