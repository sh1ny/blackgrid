# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components (new component, or 3+ with directed relationships) | No | Changes stay inside the existing painter `_MapPainter` (`lib/ui/map_workspace.dart:563`), the workspace state and `MapController.hitTestMarker` (`lib/application/map_controller.dart:577`). The new code is one pure-Dart rules file beside `lib/domain/marker_categories.dart`, called by both. That is a function module, not a component with its own lifecycle or relationships. |
| T2 State (persistent state, caches, 3+ state machine) | No | Hover is one nullable marker id in widget state, lost on dispose, with the same generation guard as selection (`map_workspace.dart:28-29`). Nothing is persisted. Labels are laid out per frame, with no cache (D5). |
| T3 Concurrency (background work, workers/isolates, async, retries) | No | Everything runs synchronously on pointer events and in `paint`. The icon set's async load is unchanged; outlines read its colour through `colourFor`, which already serves a fallback before load (`lib/maps/map_marker_icons.dart:226`). |
| T4 Boundaries (data format, migration, shared interface, IPC, external) | No | The pack format, marker icon manifest and settings are unchanged. `hitTestMarker` is an in-app method with two callers (`map_workspace.dart:105`, tests), not a shared contract. |
| T5 Volume (grows without a fixed bound) | No | Labels and outlines are per visible marker. The bundled pack has 146 extracts and 29 transits over all maps (counted from the active manifest), a few dozen per map. |
| T6 Risk (security, money, data loss, unrecoverable user data) | No | Drawing and help text only. The help text explains the existing screenshot input. It adds no input and touches no game process (AGENTS.md game-interaction rules). |

TIER: LIGHT

## Context

See `proposal.md` for the why. The facts the approach needs:

- **Outlines.** `_MapPainter.paint` draws every projected outline with a red fill (alpha .16, dimmed .035) and a `redAccent` 2 px edge (dimmed .22) before the marker's badge (`map_workspace.dart:605-622`). In the active pack, outlines exist on `QuestObjectives` (546), hazards (330, all `HazardZones`), extracts (146), switches (39) and transits (29).
- **Extract factions.** A raw extract's `details.faction` (`pmc`, `scav`, `shared`) already decides its filter key (`lib/maps/prepared_map.dart:698-702`). An unknown faction becomes `SharedExtracts`. Transits are `Transits`. So the label faction is a pure function of `filterKey`, and the label reads the marker's `name` (for example "Med Tent Gate", "Transit to Woods").
- **Colours.** `MapMarkerIcons.colourFor(filterKey)` returns the manifest role colour, or `markerFallbackColour` before the manifest loads (`map_marker_icons.dart:73-78, 226-227`). Roles are `exit #48D28B`, `danger #FF5252`, `quest #DCC05A`, `utility #B7A6F0`, and others. ADR-0023 D4 and the `map-marker-icons` spec pin every extract key to the `exit` role, so badges cannot carry faction colours.
- **Hit testing.** `hitTestMarker` first takes the nearest badge within the radius, then any marker whose outline contains the point (`map_controller.dart:577-595`). The semantics builder widens each target rect to its outline vertices (`map_workspace.dart:696-705`). The workspace hit-tests clicks with radius 22 (`map_workspace.dart:105`).
- **Selection.** The workspace keeps `_selectedMarker` together with the controller's `contentGeneration` (`map_workspace.dart:28-29, 119-124`), and `MapController.setSelectedMarker` mirrors it (`map_controller.dart:226`). The selection is cleared by Escape (`map_workspace.dart:247-253`).
- **Tests.** Painter tests go through `test/support/map_widget_harness.dart`, with an injected icon manifest (`test/ui/map_marker_painting_test.dart:15-60`). The repo has no mocking package.

## Decisions

### D1: Faction colour goes on the name label, not on the badge

- **Choice:** Badges keep ADR-0023's role colours: all extract keys stay exit green. The faction colour is applied to the name text only. Four label colours are constants in a new pure-Dart file, `lib/domain/map_zone_style.dart`:

  | Faction | Keys | Colour | Contrast vs `#090F0D` | Hue / sat. |
  |---|---|---|---|---|
  | PMC | `PmcExtracts` | `#7BE495` | 12.3:1 | 135° / 66% |
  | Scav | `ScavExtracts` | `#F2C14E` | 11.5:1 | 42° / 86% |
  | Shared | `SharedExtracts` | `#8CB4FF` | 9.3:1 | 219° / 100% |
  | Transit | `Transits` | `#D29BF2` | 8.9:1 | 278° / 77% |

  A test applies ADR-0023's palette rules to these four colours: at least 3:1 against `#090F0D`, outside the 170°–190° highlight band at 10% saturation or more, and pairwise distinct.
- **Rejected:** Recolour extract badges by faction through four new manifest roles. That breaks the accepted ADR-0023 decision and the `map-marker-icons` requirement that extract keys use the exit role, so it would need a superseding ADR. It would also put four near-green-or-not exits beside each other on the badge layer, where the glyph shape already tells PMC, Scav and shared apart.
- **Rejected:** Put the label colours in the marker manifest. The manifest is the icon set's attested provenance record (ADR-0023 D3), and its `roles` feed badge rings. Label colours are a painter concern, so keeping them out avoids a manifest format change.
- **Reversal cost:** low. Four constants and one test.

### D2: Outline colour comes from the category's role colour

- **Choice:** The painter colours each outline with `markerIcons.colourFor(marker.filterKey)`: the fill at alpha .16 (dimmed .035) and the 2 px edge at alpha 1 (dimmed .22), the same alphas as today. Hazard zones stay danger red, quest objectives turn quest gold, switches utility violet, and extracts and transits exit green. Before the manifest loads, `markerFallbackColour` gives gold or the extract/hazard colours, as badges already do.
- **Rejected:** A separate outline palette per category. That creates a second colour source that can drift from the badges, and the role colours already meet the contrast and hue rules.
- **Reversal cost:** low.

### D3: One rule decides whether an outline is drawn, and the painter, hit test and semantics all use it

- **Choice:** `lib/domain/map_zone_style.dart` exports:
  - `labelFactionFor(String filterKey)`, which returns `LabelFaction?` (`pmc`, `scav`, `shared`, `transit`, or `null` for no label);
  - `labelColourFor(LabelFaction)`;
  - `outlineDrawn(String filterKey, {required bool hovered, required bool selected})`. It is true for every key except the four exit keys, which need `hovered || selected`.

  `MapController.hitTestMarker` takes a new optional `String? hoveredMarkerId`. Its outline fallback only considers markers for which `outlineDrawn(filterKey, hovered: id == hoveredMarkerId, selected: id == _selectedMarkerId)` holds. The badge-radius pass is unchanged. The painter and the semantics builder call the same function, so a hidden outline is neither drawn, clicked nor announced as an area.
- **Rejected:** Keep `hitTestMarker` unchanged and filter in the widget. The widget would have to repeat the outline loop or post-filter a single result. Post-filtering would drop a click that should have fallen through to a drawn outline underneath, such as a hazard zone inside an extract area.
- **Rejected:** Strip extract outlines from `ProjectedMapMarker` in the controller unless hovered or selected. Hover is a high-frequency UI state. Routing it through the controller would invalidate the projection cache (`_invalidateMarkers`) and notify every listener on each hover change.
- **Reversal cost:** low. One optional parameter and one pure function.

### D4: Hover lives in the workspace state, set from a `MouseRegion`

- **Choice:** Wrap the viewport `GestureDetector` in a `MouseRegion`. `onHover` runs `maps.hitTestMarker(point, radius: 22, hoveredMarkerId: _hoveredMarker)` and calls `setState` only when the resulting id changes. It stores the id with `maps.contentGeneration`, as selection does, so a map or content change makes a stale hover inert. `onExit` clears it. Passing the current hover id keeps a revealed outline hittable while the pointer moves from the badge into the area (spec scenario "Moving into the revealed outline keeps it"). The painter gets `hoveredMarker` next to `selectedMarker`. Pins are not hover targets.
- **Rejected:** Put hover in `MapController`. See D3: it would rebuild every listener and the projection cache on each pointer move.
- **Reversal cost:** low.

### D5: Labels are painted with a per-frame `TextPainter`, after outlines and before badges

- **Choice:** `paint` runs in three passes over `visibleMarkers()`:
  1. outlines that are drawn (D3);
  2. names for markers with a label faction whose badge point is inside `markerBounds`;
  3. badges.

  Each name uses a `TextPainter` with a fixed 12 logical-pixel, weight-600 style, laid out with `maxWidth` 180 and ellipsized to one line. It is drawn twice: first as a 3 px stroke in the marker background colour (the halo), then as a fill in the faction colour. Both are multiplied by `dimmedMarkerOpacity` when the marker is dimmed. It starts at `badgePoint.dx + selectedDiameter / 2 + 4` and is centred vertically on the point. Empty or blank names are skipped. The size is set in logical pixels and does not take the canvas scale, so zoom does not change it. Pins get no labels.
- **Rejected:** Label widgets positioned in a `Stack` over the canvas. These are hundreds of widgets rebuilt on every pan, outside the painter's draw order, so a label could not sit below the badges.
- **Rejected:** A `TextPainter` cache in the workspace state, keyed by name and faction. Extracts and transits are at most a few dozen per map (Triage T5), and the layout of 12 px single-line text is cheap. A cache adds invalidation for dimming, font and map changes. Add one only if profiling a pan on the busiest map shows label layout above 2 ms per frame.
- **Reversal cost:** low.

### D6: The help is a static dialog behind a `?` toolbar button

- **Choice:** An `IconButton` (`Icons.help_outline`, tooltip "Map help") at the end of the map toolbar `Wrap` (`map_workspace.dart:273`) opens an `AlertDialog` titled "Map help" with a Close button. It is always enabled. It has two sections:
  - **Your position:** the game's own screenshot key, the screenshot folder in Settings, no screenshot means no position, and Blackgrid never captures the screen for this.
  - **Controls:** the control list from the `map-help` spec.

  On close, focus goes back to `_focus`, so the map keys keep working. The text is a `const` in `map_workspace.dart`, written to the `player-facing-text` rules. The footer hint line (`map_workspace.dart:497-503`) stays unchanged, so the current controls stay visible at a glance.
- **Rejected:** A help page in the Settings dialog or a docs link. Both are a step away from the map, where the question comes up, and a docs link opens a browser from a desktop app.
- **Reversal cost:** low.

## ADRs

- **In force, constraining this change:** ADR-0023 (project-authored map marker icons). D1 keeps extract badges on the exit role, and the label palette reuses its contrast and hue rules. The map ADRs on pack format and calibration are untouched: no pack or tooling change.
- **To record during apply:** none. The label colours and the outline rule are tactical painter choices, not decisions that bind future changes. `add-location-labels` builds on the `map-zone-labels` spec instead.
