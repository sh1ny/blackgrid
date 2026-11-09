# Proposal

## Why

M8.5's Ember interface still leaves the Map on an interim layout: the map shares its column with a rail of settings panels, developer-facing status lines are one click away, and amber on the map means quest, loot, a Scav extract or fallback. This change serves milestone **M8.5 - Ember interface**, change 4 of 5, and advances three exit criteria:

- "Selection on the map is Ember. The quest and loot roles and the Scav extract label are off the amber band. The new role colours pass the at-least-3:1 badge contrast check and stay apart from the pin role and every extract label colour. A new ADR supersedes those parts of ADR-0023." (agent)
- The Map part of "every setting ... is reachable and nothing is lost": marker switches with their icons, the map picker, Read Latest, the floor control, and the marker and quest filters. (agent) The Settings page itself is `restyle-dialogs`.
- The Map half of the answer-first geometry: no settings panel above the answer strip, wide and at 960 px. (agent)

The user-verified criterion (both rooms, second monitor, alt-tabbed full window) is judged by the owner at the milestone close, after `restyle-dialogs`, because the screens it covers are not finished until then.

## What Changes

- The map takes the whole main column. The rail and its panels are removed from the Map screen.
- The map carries its own controls (DESIGN.md X13): a map picker Ember Menu with the Read latest screenshot item, and a floor segmented control with Auto. Fit, zoom, center, pin, browse and help stay as quiet controls on the map.
- The Map inspector holds, in order, **This raid** (the extracts matched from the last raid-panel screenshot), **Markers** (filters, Show all and Hide all, and grouped rows with the map badge, name, count and a toggle switch) and **Pins** (DESIGN.md X10, X13). The item decision card, Requirements, Sources and History leave the Map inspector and stay on Scanner.
- The Map stops showing debug information, following the owner's rule that main windows stay clean. The saved-file status lines (logs, screenshots, raid panel, saved evidence, sampled position) move to a collapsed Diagnostics section at the end of Settings, the app's one home for debug detail. Pin coordinates, frames and revisions leave the Map's pin rows and the selected-pin strip, which becomes a small bar over the map, and the "Saving map preferences" line and the instruction line under the map go (the instructions are in Map help). The artwork attribution and save failures the player must act on stay.
- The Manual item search panel leaves Map; the top-bar search, status bar and Settings cover it.
- A selected marker, extract or pin is drawn in Ember. Quest, loot and the Scav extract label move off the amber band, and so do the fallback badge gold and the popup leader line, so amber on the map means only "selected". A new ADR supersedes those parts of ADR-0023, and the set check gains the amber-band rule.
- The marker bubble shows spawn chances as whole percentages.

## Capabilities

### New Capabilities
- `map-controls`: the on-map picker with Read latest screenshot, the floor control, and the Map inspector's This raid and Pins sections.

### Modified Capabilities
- `map-rail`: the rail's arrangement is replaced by the full-width map and inspector; the saved-file status becomes a collapsed Diagnostics section in Settings.
- `marker-preferences`: icon tiles become the grouped 30px rows with a toggle switch; the search and quest trader controls take their X13 form.
- `map-marker-icons`: selection is drawn in Ember, new quest and loot colours, the amber band is reserved, and the fallback badge leaves it.
- `map-zone-labels`: the Scav label colour moves, the palette rule gains the amber band, and quest outlines change colour.
- `map-marker-popups`: spawn chance is shown as a whole percentage.
- `workspace-shell`: the Map inspector holds working lists rather than item details.
- `latest-accepted-scan`: Map shows accepted scans through the answer strip, not a rail card.
- `scanner-evidence`: drops the sentence protecting the interim Map rail.
- `verdict-presentation`: the compact Map rail card becomes the answer strip.

## Impact

- Code: `lib/ui/map_screen.dart`, `lib/ui/map_workspace.dart`, `lib/ui/marker_preferences.dart`, `lib/ui/shell.dart` (Map inspector branch), `lib/ui/settings_dialog.dart` (Diagnostics), `lib/maps/map_marker_icons.dart`, `lib/maps/map_palette.dart`, `lib/maps/marker_presentation.dart`, `lib/domain/map_zone_style.dart`, `lib/application/map_controller.dart` and `lib/application/map_session_controller.dart` (raid match accessor and time, read outcome), `lib/data/screenshot_directory_watcher.dart` (a read result that tells an empty folder from an unavailable one). `lib/ui/manual_controls.dart` and its tests are deleted: the panel was its only caller.
- Assets and tools: role colours in `assets/map_markers/manifest.json` (no glyph changes, so hashes and compiled files stay); `tool/markers/icon_set.dart` and `tool/markers/preview.dart` for the amber-band rule and the selected state.
- Docs: new ADR superseding parts of ADR-0023, with `openspec/architecture.md`'s index updated; DESIGN.md X6 and X12 record the chosen colours and the Diagnostics section.
- Tests: Map rail placement tests are replaced with geometry and behaviour tests; palette fixtures follow the new values.
- No change to log following, capture, stored settings format or dependencies. AGENTS.md's safety boundary applies: all checks are offline.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: New role colours

- **Choice:** Quest `#C5E063`, loot `#7ED9C6`, Scav extract label `#F59AB8`. The shared label keeps `#8CB4FF`.
- **Rejected:** The mock-up's quest `#8CB4FF`, which is already the shared label and too close to the pin role; swapping rose and lime between quest and Scav, which offers no gain.
- **Reversal cost:** low (manifest values and constants; no glyphs change)
- **Important:** yes; changes what users see and binds the new ADR.
- **Chosen by:** user

### S2: Map saved-file status lines

- **Choice:** Main windows stay clean of debug information. A collapsed Diagnostics section at the end of Settings holds the status lines and is the home for later debug detail. Read Latest goes to the map picker, and Follow logs stays in Settings. This change cleans the Map only; Scanner's source and scan-evidence detail is left for a follow-up, because this change does not otherwise touch Scanner.
- **Rejected:** A collapsed section in the Map inspector, which keeps developer-facing text on the work screen (owner: "they shouldn't be visible by default"); log only, which loses an in-app way to see why the map is not following.
- **Reversal cost:** low
- **Important:** yes; changes what users see.
- **Chosen by:** user ("the main windows should be clean"; a debug section in Settings or a small button, not visible by default; the agent picked the Settings section and the Map-only scope)

### S3: Map inspector contents

- **Choice:** Follow DESIGN.md X10: This raid, Markers, Pins. Item details stay on Scanner, and the verdict stays in the answer strip on both areas.
- **Rejected:** Keeping Requirements, Sources and History as collapsed sections on Map, which departs from the approved layout.
- **Reversal cost:** low
- **Important:** yes; changes what users see.
- **Chosen by:** user

### S4: This raid list

- **Choice:** Build it in this change: the matched extracts with badge and name, the age of the screenshot, click to select, and an empty state. Open and fee details are out, because they need data Blackgrid does not parse.
- **Rejected:** Deferring it to M14, which leaves the inspector short of the approved layout.
- **Reversal cost:** low
- **Important:** yes; changes what users see.
- **Chosen by:** user

### S6: Selection against highlights

- **Choice:** A selected marker is Ember. Linked and raid-matched highlights stay cyan, and a marker that is both draws Ember.
- **Rejected:** Ember for highlights too, which makes amber also mean "matched from a raid".
- **Reversal cost:** low
- **Important:** yes; changes what users see.
- **Chosen by:** user

### S5: Spawn chance rounding

- **Choice:** Round to the nearest whole percent, and keep a chance strictly between 0 and 100 between 1% and 99%, so it never reads as impossible or certain.
- **Rejected:** Plain rounding, which shows 0.4% as 0%.
- **Reversal cost:** low
- **Important:** no
- **Chosen by:** agent

## Release Notes

The Map now gives the map the whole main column, with its controls on the map and marker switches in the inspector. Amber on the map now only means "selected".

### Changed
- The map takes the full main column. The map picker, Read latest screenshot and the floor control sit on the map.
- The Map inspector lists this raid's extracts, markers with their icons, counts and switches, and your pins.
- A selected marker, extract or pin is drawn in amber. Quest markers are now lime, loot markers teal and Scav extract names rose.
- Spawn chances show as whole percentages.
- The Map no longer shows debug information. Saved-file status lines are in a collapsed Diagnostics section in Settings.
