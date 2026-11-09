/// The map's own colours that the interface draws on top of the map.
///
/// These values are owned by ADR-0023 and ADR-0039, not by the Ember theme, and they do not
/// follow the light or dark room. They are the values that were built inline in
/// `lib/ui` before the theme check banned colour literals there.
library;

import 'dart:ui' show Color;

import '../domain/map_zone_style.dart';

/// The fill of the player marker.
const Color mapPlayerMarkerFill = Color(0xFFFFFFFF);

/// The colour of place labels, before [placeLabelOpacity] is applied.
const Color mapPlaceLabelColour = Color(placeLabelColour);

/// The colour of the extract label for [faction], before its opacity.
Color mapExtractLabelColour(LabelFaction faction) =>
    Color(labelColourFor(faction));

/// The colour of the selected marker: its ring, glyph and outline.
///
/// This is the dark-room Ember accent (`EmberColors.dark.accent`, `#E9A14B`).
/// The map is dark in both rooms, so selection does not follow the room, and
/// `lib/maps` imports nothing from `lib/ui`; a test pins the two together.
/// ADR-0039 reserves the amber band for this colour.
const Color mapSelectionColour = Color(0xFFE9A14B);

/// The leader line from a marker's anchor to its popup bubble.
///
/// It only ever joins a selected marker to its bubble, so it takes
/// [mapSelectionColour].
const Color mapPopupLeaderLine = mapSelectionColour;
