/// The map's own colours that the interface draws on top of the map.
///
/// These values are owned by ADR-0023, not by the Ember theme, and they do not
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

/// The leader line from a marker's anchor to its popup bubble.
const Color mapPopupLeaderLine = Color(0xFFDCC05A);
