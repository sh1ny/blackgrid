# Proposal

## Why

M8 — map labels and popups — needs marker information at the selected place, not in a raw-data strip below the map. This change advances M8's anchored, viewport-contained bubble criterion; real-map readability remains a user-verified criterion judged at milestone close, when location labels and the remaining M8 work are also present, rather than claiming that partial milestone check passed here.

## What Changes

- Replace the built-in marker details strip with one in-map bubble anchored to the selected badge. It follows pan, zoom and resize without moving the map, prefers above then below, stays inside the viewport and scrolls long content.
- Preserve pointer, marker-browser and accessibility selection. Close, Escape, an empty-map click or selecting a pin clears the marker; another marker replaces it. Offscreen anchors temporarily hide the bubble; floor/category/quest ineligibility or map/content replacement clears the selection.
- Show quest name and objective text, extract source-linked switches and required/payment item counts, lock type and key name, container name, or boss name and available spawn chance. Use the existing matching-mode catalog for item names without initiating a request; missing names get plain-language unavailable text, never raw IDs in the open summary.
- Show only player-facing summaries in marker bubbles; remove the raw Details control, diagnostic preview and its session state. Prepared marker details and source remain available internally for summary derivation.
- Select the nearest eligible badge within the inclusive hit radius; for equal-distance badges select the topmost painted badge. Keep popup keyboard input isolated from all map navigation shortcuts without stealing input handled by its controls.
- Preserve saved-pin details/editing, marker badges, extract labels/outlines, search dimming, selection-linked switch highlights and map help. No new network endpoint, stored preference, dependency, pack generation or artwork change.

## Capabilities

### New Capabilities

- `map-marker-popups`: selection lifecycle, anchored viewport placement, player-facing marker summaries and accessible interaction for built-in map markers.

### Modified Capabilities

None. `player-facing-text` requires plain-language summaries and session-lasting lazy Details where an app surface offers Details; this marker bubble no longer offers Details. Other app surfaces and their applicable Details contract remain unchanged. Existing `map-help`, `map-zone-labels`, `map-marker-icons`, `marker-preferences` and `map-rail` contracts remain in force.

## Impact

- `lib/ui/map_workspace.dart` and `lib/ui/map_screen.dart`: replace marker-only strip, integrate bubble input/focus and remove marker Details state across layouts.
- A focused marker-presentation module plus small popup widget/layout helper; existing map metadata/projection and catalog access are reused rather than a second geometry or loading pipeline.
- `lib/application/map_controller.dart`: expose selection eligibility/projection without viewport culling, so offscreen and ineligible selection are not confused; keep source-linked highlights consistent with dismissal and resolve equal-distance badge hits by paint order.
- Focused model/layout/widget tests and affected existing map viewport tests. No native/game interaction, runtime map-data fetching, catalog schema changes or release/version work.
- Constrained by ADR-0002 (SDK notifiers), ADR-0005 as amended by ADR-0033 (native prepared map), ADR-0023 (existing marker art) and ADR-0029 (proposal release notes).

## Decision Making

DECISION_MAKING: important
- **Source:** setting; user explicitly required keeping `decision_making: important` for this change.

### S1: One M8 presentation change only

- **Choice:** Deliver only `add-marker-popups`; keep artwork refresh, live map data, location labels, other milestones, dependencies, broad refactors and release work out of scope. The approved amendment continues the existing apply workflow.
- **Rejected:** Bundling later M8 data/artwork work; it exceeds the user's explicit scope.
- **Reversal cost:** low.
- **Important:** yes — changes user-visible scope and binds the implementation boundary.
- **Chosen by:** user.

### S2: Existing data and truthful name resolution

- **Choice:** Use the frozen prepared marker data and the loaded matching-mode catalog, including last-good cached names; no popup-triggered fetch. Missing key/item names are explicitly unavailable without displaying raw IDs; switch names require source links within the same map. Boss rates remain the bundled snapshot, with no REST refresh or live network lookup; do not invent extraction availability or location-level boss chances.
- **Rejected:** Pack-only names leave most key names unavailable; new endpoint or pack enrichment belongs to separate roadmap work.
- **Reversal cost:** medium.
- **Important:** yes — user-visible content and catalog/data seam.
- **Chosen by:** user (Names answer: “Use existing catalog names”).

## Release Notes

Selected map markers show their information in a bubble at the marker instead of a strip below the map. Quest objectives, extract requirements, keys, containers and boss chances read in plain language.

### Added

- Marker bubbles follow pan and zoom, stay inside the map view and support pointer and keyboard dismissal.
- Marker summaries resolve key and required-item names from already loaded item data; unavailable names are stated rather than shown as IDs.

### Fixed

- Equally close overlapping map badges select the topmost visible marker, so boss badges open the boss information rather than an underlying generic spawn.
- Map navigation shortcuts no longer pan or zoom the map while a marker bubble control has keyboard focus.
- Removing the current session's application log resets raid input even when the folder is deleted afterward.
- Long marker names remain readable by scrolling, and untranslated spawn-zone identifiers use readable category labels.
- Selecting a different marker starts its summary at the top, while updates to the current marker retain its scroll position.
