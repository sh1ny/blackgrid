# Proposal

## Why

The user checked the M4.5 look on 2026-10-29. In Marker preferences, a tile whose label fits on one line ("Locks", "PMC extracts", "Switches") draws its badge and label at the tile's left edge. Tiles whose label wraps to two lines ("Quest objectives", "Stationary weapons") look centred. The grid therefore looks uneven, and the user failed the M4.5 exit criterion "Marker preferences is a uniform grid of clickable icon tiles with player-facing labels" (user for the look). This change closes that gap, so M4.5 (player-facing polish, item icons and own map markers) can close. It is change 8 of M4.5 in the roadmap.

## What Changes

- Every Marker preferences tile centres its badge and label horizontally, whatever the label's length or the tile scale.
- Nothing else changes: tile size, the check mark's place, clicking to toggle, the dimmed hidden state, semantics, Show all, Hide all, search and the quest filters stay as they are.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities
- `marker-preferences`: the "Each applicable category is one icon tile" requirement now says that the badge and label are centred in the tile.

## Impact

- `lib/ui/marker_preferences.dart` (the tile layout) and `test/ui/marker_preferences_test.dart`.
- No change to settings, stored filters, the map's marker drawing or any other screen.
