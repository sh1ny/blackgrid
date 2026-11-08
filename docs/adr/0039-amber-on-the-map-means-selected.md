# 0039 - Amber on the map means selected

- Status: accepted
- Date: 2026-11-08 (change `restyle-map-workspace`)
- Source: change `restyle-map-workspace`, decisions S1, S6, D1, D2 and D3
- Supersedes: 0023 ([ADR-0023](0023-project-authored-map-marker-icons.md)), its "Palette rules (D4, D7)" bullet as far as this record adds to it and the quest and loot role values. The single-tint glyphs, the manifest and provenance format, the allow-list, the 3:1 contrast floor, the cyan highlight band, the exit, danger and pin roles, the ban on third-party marker art and the offline tools stay in force, as does the rest of ADR-0023.

## Context and problem

The Ember interface uses amber as its one accent. On the map, amber meant four other things: quest markers, loot markers, the Scav extract label and the fallback badge. A selected marker kept its role colour and only grew, so selection had no colour of its own. The player needs a selected marker to stand out at a glance, on a surface that stays dark in both rooms.

## Decision

- **Selection draws Ember.** A selected marker, extract or pin draws in `mapSelectionColour`, a literal in `lib/maps/map_palette.dart` (ADR-0037's named exception) that a test pins to `EmberColors.dark.accent`, `#E9A14B`. The map is dark in both rooms, so the light room's accent does not apply. `paintMarkerBadge` resolves the colour in one place: selected, then highlighted, then role. A zone outline and the popup leader line take the same colour for a selected marker.
- **Selection wins over highlight.** Linked and raid-matched highlights stay cyan. A marker that is both selected and highlighted draws Ember.
- **The amber band is reserved.** No marker role and no label colour uses hue 25° to 60° at HSL saturation 10% or more; below 10% counts as grey. The check joins the cyan-band check in `tool/markers/icon_set.dart` and the label palette test.
- **New values off the band.** Quest is `#C5E063`, loot is `#7ED9C6` and the Scav extract label is `#F59AB8`. The shared extract label keeps `#8CB4FF`. Each role still reaches 3:1 against `#090F0D`.
- **Colours stay apart.** A new role or label colour keeps an OKLab distance of at least 0.08 from every other shipped role and label colour. A test over the shipped palette enforces this; the set check does not, so candidate icon sets stay free to explore.
- **Fallback is neutral.** The badge drawn for an unknown key or a failed load uses `#C9CDBF`, the spawn role's neutral, so it reads as "no category".

## Rejected alternatives

- **A separate selected ring painted after the badge:** the list, map and preview would disagree on what a selected badge is, and ring and glyph would need two paint passes.
- **Ember for highlights as well:** amber would also mean "matched from a raid".
- **Marker roles in `EmberColors`:** ADR-0037 keeps Blackgrid map roles out of the shared kit, and these colours do not follow the rooms.
- **The mock-up's quest `#8CB4FF`:** it is already the shared label and sits too close to the pin role.
- **A distance rule in the set check:** candidate sets need room to explore, and the test covers what ships.

## Consequences

- A later icon set that uses amber fails the set check.
- A new role or label colour has to clear the band and the distance test before it ships.
- Marker glyphs do not change, so their hashes and compiled files stay as they are.
- **Reversal cost:** medium. The manifest values and constants are small edits, but this rule binds future icon sets.
