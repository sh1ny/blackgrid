# Proposal

## Why

At 1920 × 1080 the Map's horizontal floor picker cuts off much of Icebreaker's deck list without showing how many floors are hidden. The base floor also appears first even though it is partway up the ship. This is a standalone change and advances no roadmap milestone exit criterion.

## What Changes

- Replace the horizontal tabs with a collapsible floor rail under the map picker. Show the floor count, step buttons, Auto status, the player's floor, and how many floors are out of view when the list scrolls.
- Keep Icebreaker exclusive and other maps additive. Highlight visible floors without amber. Hide the control if it has no action to offer.
- Let players step with Page Up or Page Down, toggle Auto with A, and focus the rail with F. A step selects one destination; on additive maps the base stays drawn.
- Write the existing hand-kept floor lists bottom to top and preserve that order in the prepared pack and app. The rail reads the list in reverse. Do not infer floor order from height extents or add a manifest field.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-controls`: The floor rail, selection, Auto status, and keyboard behavior.
- `map-help`: Document the floor shortcuts alongside the existing Map controls.
- `map-marker-popups`: Escape dismisses a popup from the canvas or popup, not from the floor rail.
- `prepared-map-packs`: Preserve reviewed floor order without changing floor identity, artwork or classification.

## Impact

Touches the Map floor control and related help, the floor policy and its manifest loader, and the reviewed floor inventories and active map pack. The viewport, map picker, other map controls, inspector, artwork, screenshot inputs and classification rules stay as they are. No dependency, settings or manifest format change is in scope.

The worktree was created by Orca before the Specwright gate. The owner approved the manual equivalent. Pinned `sw` 0.39.1 reported interface 3 and a clean `feat/floor-deck-rail`; the branch, `main`, and freshly fetched `origin/main` all pointed to `18ee8041d0cf2e9a738d4917725898cf1390e6f7`. No change of this name was in flight or archived on those refs.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Replace only the floor selector

- **Choice:** Build option A, the deck rail over the map's left edge, with a collapsed stepper. Keep both existing floor selection modes and the rest of the Map screen.
- **Rejected:** Another horizontal row, which still hides floors behind a menu, or a picker that hides the whole list until opened.
- **Reversal cost:** medium.
- **Important:** yes, changes the visible map controls.
- **Chosen by:** user.

### S2: Use the authored floor order

- **Choice:** Treat the existing hand-kept lists as bottom-to-top order and reverse that order only for display.
- **Rejected:** Sort by height extents, which can overlap, or add a separate order field that could disagree with the list.
- **Reversal cost:** medium.
- **Important:** yes, sets the pack's floor-order contract.
- **Chosen by:** user.

### S3: Step to one destination

- **Choice:** Follow the mockup on both selection modes. A step chooses an adjacent floor and replaces the overlay set. On additive maps the base remains drawn.
- **Rejected:** Add each destination to the existing overlay set while stepping, which would accumulate layers and make the step's current floor ambiguous.
- **Reversal cost:** low.
- **Important:** yes, changes which floors are visible when stepping.
- **Chosen by:** user.

### S4: Keep the change outside the roadmap

- **Choice:** Proceed as a standalone change with no milestone criteria changed, as approved by the owner.
- **Rejected:** Assign it to M13 Map comfort, which has no floor selector item.
- **Reversal cost:** low.
- **Important:** yes, this sets the proposal's scope.
- **Chosen by:** user.

## Release Notes

The Map now lists floors vertically under the map picker, with the top floor first.

### Changed

- Scroll the floor list or collapse it to a stepper. Page Up and Page Down change floors, A toggles Auto, and F focuses the floor control. The rail marks the floor from your last position screenshot even when Auto is off.
