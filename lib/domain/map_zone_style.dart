/// Rules for the map's extract name labels and zone outline visibility.
///
/// The painter, the hit test and the accessibility targets share these rules,
/// so an outline that is not drawn is neither clicked nor announced.
library;

/// Who can use an extract or transit, as shown by its name label colour.
enum LabelFaction {
  /// A `PmcExtracts` marker.
  pmc,

  /// A `ScavExtracts` marker.
  scav,

  /// A `SharedExtracts` marker.
  shared,

  /// A `Transits` marker.
  transit,
}

/// Returns the label faction of the marker category [filterKey], or `null`
/// when markers of that category get no name label.
///
/// Only extracts and transits are labelled.
LabelFaction? labelFactionFor(String filterKey) => switch (filterKey) {
  'PmcExtracts' => LabelFaction.pmc,
  'ScavExtracts' => LabelFaction.scav,
  'SharedExtracts' => LabelFaction.shared,
  'Transits' => LabelFaction.transit,
  _ => null,
};

/// Returns the opaque ARGB name label colour of [faction].
///
/// Each colour reaches at least 3:1 contrast against the map background
/// `#090F0D` and stays outside the cyan highlight band, following the marker
/// palette rules of ADR-0023. Badges keep their own role colours.
int labelColourFor(LabelFaction faction) => switch (faction) {
  LabelFaction.pmc => 0xFF7BE495,
  LabelFaction.scav => 0xFFF2C14E,
  LabelFaction.shared => 0xFF8CB4FF,
  LabelFaction.transit => 0xFFD29BF2,
};

/// The opaque ARGB colour of place labels, a muted off-white (`#C8D0CB`).
///
/// It differs from every [labelColourFor] colour and, blended at
/// [placeLabelOpacity] over the map background, keeps 3:1 contrast.
const int placeLabelColour = 0xFFC8D0CB;

/// The opacity place labels are drawn with.
const double placeLabelOpacity = 0.85;

/// Whether the outline of a marker in category [filterKey] is drawn.
///
/// Extract and transit outlines show only while their marker is [hovered] or
/// [selected]; every other category's outline always shows.
bool outlineDrawn(
  String filterKey, {
  required bool hovered,
  required bool selected,
}) => labelFactionFor(filterKey) == null || hovered || selected;
