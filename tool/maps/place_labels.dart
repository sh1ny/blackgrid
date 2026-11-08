/// Place labels for prepared map packs: extraction from the frozen interactive
/// metadata, floor assignment from a reviewed height-band table, and a check
/// that the table still matches the metadata.
///
/// This library has no dependency on the pack builder. The builder calls
/// [extractPlaceLabels] and [assignLabelFloors] for each map and
/// `validateCandidate` repeats both on the candidate's own evidence.
library;

/// The default label rotation in degrees when the source gives none.
const defaultLabelRotation = 0;

/// The default relative label size when the source gives none.
const defaultLabelSize = 80;

/// One place label with defaults applied and numeric strings converted.
final class PlaceLabel {
  /// Creates a label.
  const PlaceLabel({
    required this.text,
    required this.x,
    required this.z,
    this.rotation = defaultLabelRotation,
    this.size = defaultLabelSize,
    this.bottom,
    this.top,
    this.floorIds = const [],
  });

  /// The source text, unchanged.
  final String text;

  /// The game X coordinate (source `position[0]`).
  final num x;

  /// The game Z coordinate (source `position[1]`).
  final num z;

  /// The rotation in degrees.
  final num rotation;

  /// The relative size.
  final num size;

  /// The lower height bound, or `null` when the source gives none.
  final num? bottom;

  /// The upper height bound, or `null` when the source gives none.
  final num? top;

  /// The Blackgrid floors the label belongs to, empty before assignment.
  final List<String> floorIds;

  /// Whether the source gave the label a height bound.
  bool get isBanded => bottom != null || top != null;

  /// Returns a copy that belongs to [floorIds].
  PlaceLabel withFloors(List<String> floorIds) => PlaceLabel(
    text: text,
    x: x,
    z: z,
    rotation: rotation,
    size: size,
    bottom: bottom,
    top: top,
    floorIds: List.unmodifiable(floorIds),
  );

  /// The manifest form: the raw game position, never scene coordinates.
  Map<String, Object?> toJson() => {
    'text': text,
    'position': {'x': x, 'z': z},
    'rotation': rotation,
    'size': size,
    'floorIds': floorIds,
  };
}

/// Where a floor band is read from in a map's interactive metadata entry.
sealed class LabelBandSource {
  const LabelBandSource();
}

/// The interactive entry's `heightRange`.
final class MapHeightRange extends LabelBandSource {
  /// Creates the source.
  const MapHeightRange();
}

/// The interactive entry's `_heightRange` (Interchange).
final class InterchangeHeightRange extends LabelBandSource {
  /// Creates the source.
  const InterchangeHeightRange();
}

/// The `height` of one extent of the layer called [name].
final class LayerExtent extends LabelBandSource {
  /// Creates the source for extent [extentIndex] of the layer [name].
  const LayerExtent(this.name, this.extentIndex);

  /// The metadata layer's name.
  final String name;

  /// The index into the layer's `extents`.
  final int extentIndex;
}

/// A floor's label band `[min, max)` and the metadata height it comes from.
final class LabelFloorBand {
  /// Creates a band for [floorId].
  const LabelFloorBand(this.floorId, this.min, this.max, this.source);

  /// The Blackgrid floor id.
  final String floorId;

  /// The inclusive lower bound.
  final num min;

  /// The exclusive upper bound.
  final num max;

  /// The metadata height this band was reviewed against.
  final LabelBandSource source;
}

/// The reviewed band table, keyed by prepared map id.
///
/// A floor that is left out gets no banded labels. Reserve's upper floors
/// and Ground Zero's garage are left out on purpose: their metadata layers
/// are many bounded pieces, not one band, and no label needs them.
const placeLabelBandTable = <String, List<LabelFloorBand>>{
  'factory': [
    LabelFloorBand('Ground_Floor', -1, 3, MapHeightRange()),
    LabelFloorBand('Second_Floor', 3, 6, LayerExtent('2nd Floor', 0)),
    LabelFloorBand('Third_Floor', 6, 10000, LayerExtent('3rd Floor', 0)),
    LabelFloorBand('Basement', -10000, -1, LayerExtent('Tunnels', 0)),
  ],
  'interchange': [
    LabelFloorBand('Ground_Level', -1000, 25, InterchangeHeightRange()),
    LabelFloorBand('First_Floor', 25, 34, LayerExtent('2nd Floor', 0)),
    LabelFloorBand('Second_Floor', 34, 1000, LayerExtent('3rd Floor', 0)),
  ],
  'thelab': [
    LabelFloorBand('First_Level', -0.9, 3, MapHeightRange()),
    LabelFloorBand('Second_Level', 3, 10000, LayerExtent('Second Level', 0)),
    LabelFloorBand(
      'Technical_Level',
      -10000,
      -0.9,
      LayerExtent('Technical', 0),
    ),
  ],
  'shoreline': [
    LabelFloorBand('Ground_Level', -1000, -1, MapHeightRange()),
    LabelFloorBand('Second_Floor', -1, 2, LayerExtent('2nd Floor', 0)),
    LabelFloorBand('Third_Floor', 2, 1000, LayerExtent('3rd Floor', 0)),
    LabelFloorBand(
      'Underground_Level',
      -1000,
      -5,
      LayerExtent('Underground', 0),
    ),
  ],
  'groundzero': [
    LabelFloorBand('Ground_Level', -1000, 28, MapHeightRange()),
    LabelFloorBand('Second_Floor', 28, 32.3, LayerExtent('2nd Floor', 0)),
    LabelFloorBand('Third_Floor', 32.3, 1000, LayerExtent('3rd Floor', 0)),
  ],
  'reserve': [LabelFloorBand('Ground_Level', -7, 10000, MapHeightRange())],
};

/// Extracts and validates the place labels of one interactive metadata entry.
///
/// Returns the labels in source order with a rotation of 0 and a size of 80
/// when the source gives none, and numeric strings converted. A missing
/// `labels` list is an empty list. [mapId] names the map in errors.
///
/// Throws a [FormatException] naming [mapId] and the label index for a label
/// with blank text, a position that is not two finite numbers, a rotation,
/// size, bottom or top that is not a finite number or numeric string, or a
/// size that is not positive. A malformed label is never skipped.
List<PlaceLabel> extractPlaceLabels(
  Map<String, dynamic> interactive, {
  required String mapId,
}) {
  final raw = interactive['labels'];
  if (raw == null) return const [];
  if (raw is! List) {
    throw FormatException('$mapId: labels is not a list');
  }
  return [
    for (var index = 0; index < raw.length; index++)
      _extractLabel(raw[index], mapId, index),
  ];
}

PlaceLabel _extractLabel(Object? source, String mapId, int index) {
  Never fail(String problem) =>
      throw FormatException('$mapId: label $index $problem');
  if (source is! Map) fail('is not an object');
  final text = source['text'];
  if (text is! String || text.trim().isEmpty) fail('has blank text');
  final (num x, num z) = switch (source['position']) {
    [final num px, final num pz] when px.isFinite && pz.isFinite => (px, pz),
    _ => fail('"$text" has a position that is not two finite numbers'),
  };
  num? optional(String key) {
    final value = source[key];
    if (value == null) return null;
    final number = switch (value) {
      final num n => n,
      final String s => num.tryParse(s.trim()),
      _ => null,
    };
    if (number == null || !number.isFinite) {
      fail('"$text" has a non-numeric $key: $value');
    }
    return number;
  }

  final size = optional('size') ?? defaultLabelSize;
  if (size <= 0) fail('"$text" has a size that is not positive: $size');
  return PlaceLabel(
    text: text,
    x: x,
    z: z,
    rotation: optional('rotation') ?? defaultLabelRotation,
    size: size,
    bottom: optional('bottom'),
    top: optional('top'),
  );
}

/// Assigns each label of [mapId] to the floors whose band it overlaps.
///
/// A banded label (a missing bound is infinite) belongs to every floor of
/// [table] for [mapId] with a band `[min, max)` where `bottom < max` and
/// `top >= min`, in table order. An unbanded label belongs to [baseFloorId].
/// The result keeps the source order.
///
/// Throws a [FormatException] naming [mapId] and the label text for a banded
/// label on a map whose table has no floors, or for a label that overlaps no
/// floor band.
List<PlaceLabel> assignLabelFloors(
  List<PlaceLabel> labels, {
  required String mapId,
  required String baseFloorId,
  Map<String, List<LabelFloorBand>> table = placeLabelBandTable,
}) {
  final bands = table[mapId] ?? const <LabelFloorBand>[];
  final assigned = <PlaceLabel>[];
  for (final label in labels) {
    if (!label.isBanded) {
      assigned.add(label.withFloors([baseFloorId]));
      continue;
    }
    if (bands.isEmpty) {
      throw FormatException(
        '$mapId: label "${label.text}" has a height band but the band '
        'table gives the map no floor bands',
      );
    }
    final bottom = label.bottom ?? double.negativeInfinity;
    final top = label.top ?? double.infinity;
    final floorIds = [
      for (final band in bands)
        if (bottom < band.max && top >= band.min) band.floorId,
    ];
    if (floorIds.isEmpty) {
      throw FormatException(
        '$mapId: label "${label.text}" [${label.bottom}, ${label.top}] '
        'overlaps no floor band',
      );
    }
    assigned.add(label.withFloors(floorIds));
  }
  return assigned;
}

/// The manifest `labels` of one map: extraction, floor assignment and the
/// manifest form, in one call.
///
/// The builder writes this and `validateCandidate` derives it again from the
/// candidate's own metadata, so both sides run the same code. [baseFloorId] is
/// the map's base floor.
List<Map<String, Object?>> manifestLabels(
  Map<String, dynamic> interactive, {
  required String mapId,
  required String baseFloorId,
  Map<String, List<LabelFloorBand>> table = placeLabelBandTable,
}) => [
  for (final label in assignLabelFloors(
    extractPlaceLabels(interactive, mapId: mapId),
    mapId: mapId,
    baseFloorId: baseFloorId,
    table: table,
  ))
    label.toJson(),
];

/// Checks the band table against the interactive metadata.
///
/// [metadata] is the decoded `metadata/maps.json`. [maps] are the prepared
/// maps (manifest entries or calibration records) with `id`, `sourceKey`,
/// `kind` and `floors`. For every table entry this resolves the metadata
/// height it names and requires the band to equal it, and requires the
/// metadata layer's identity (`svgLayer` for vector maps, otherwise
/// `tilePath`, as `reconcileFloors` reads it) to equal the floor's
/// `sourceTileUrl` or id, so a floor cannot be paired with the wrong layer.
///
/// Throws a [FormatException] listing every mismatch, each naming the map,
/// the floor and both bands.
void checkBandTable(
  List<dynamic> metadata,
  List<Map<String, Object?>> maps, {
  Map<String, List<LabelFloorBand>> table = placeLabelBandTable,
}) {
  final problems = <String>[];
  for (final MapEntry(key: mapId, value: bands) in table.entries) {
    final local = maps.where((m) => m['id'] == mapId).firstOrNull;
    if (local == null) {
      problems.add('$mapId: the table names a map the pack does not have');
      continue;
    }
    final sourceKey = local['sourceKey'] as String;
    final upstream = _interactive(metadata, sourceKey);
    if (upstream == null) {
      problems.add('$mapId: no interactive metadata for $sourceKey');
      continue;
    }
    final floors = (local['floors'] as List).cast<Map<String, Object?>>();
    for (final band in bands) {
      final floor = floors.where((f) => f['id'] == band.floorId).firstOrNull;
      if (floor == null) {
        problems.add('$mapId: floor ${band.floorId} is not a floor of the map');
        continue;
      }
      final resolved = _resolve(band.source, upstream, '${local['kind']}');
      final label = '$mapId ${band.floorId}';
      if (resolved == null) {
        problems.add('$label: the metadata has no ${_describe(band.source)}');
        continue;
      }
      if (resolved.band[0] != band.min || resolved.band[1] != band.max) {
        problems.add(
          '$label: table band [${band.min}, ${band.max}) differs from '
          'metadata band ${resolved.band} (${_describe(band.source)})',
        );
      }
      final expected = floor['sourceTileUrl'] ?? floor['id'];
      if (resolved.identity != expected) {
        problems.add(
          '$label: ${_describe(band.source)} belongs to layer '
          '${resolved.identity}, not $expected',
        );
      }
    }
  }
  if (problems.isNotEmpty) throw FormatException(problems.join('\n'));
}

Map<String, dynamic>? _interactive(List<dynamic> metadata, String sourceKey) {
  for (final entry in metadata.cast<Map<String, dynamic>>()) {
    if (entry['normalizedName'] != sourceKey) continue;
    for (final map in (entry['maps'] as List).cast<Map<String, dynamic>>()) {
      if (map['key'] == sourceKey && map['projection'] == 'interactive') {
        return map;
      }
    }
  }
  return null;
}

String _describe(LabelBandSource source) => switch (source) {
  MapHeightRange() => 'heightRange',
  InterchangeHeightRange() => '_heightRange',
  LayerExtent(:final name, :final extentIndex) =>
    'layer "$name" extent #$extentIndex',
};

({List<num> band, String? identity})? _resolve(
  LabelBandSource source,
  Map<String, dynamic> upstream,
  String kind,
) {
  String? identity(Map node) => kind == 'vector' && node['svgLayer'] is String
      ? node['svgLayer'] as String
      : node['tilePath'] as String?;
  List<num>? pair(Object? value) => switch (value) {
    [final num low, final num high] => [low, high],
    _ => null,
  };
  switch (source) {
    case MapHeightRange():
      final band = pair(upstream['heightRange']);
      return band == null ? null : (band: band, identity: identity(upstream));
    case InterchangeHeightRange():
      final band = pair(upstream['_heightRange']);
      return band == null ? null : (band: band, identity: identity(upstream));
    case LayerExtent(:final name, :final extentIndex):
      for (final layer in (upstream['layers'] as List? ?? const [])) {
        if (layer is! Map || layer['name'] != name) continue;
        final extents = layer['extents'] as List? ?? const [];
        if (extentIndex >= extents.length) return null;
        final band = pair((extents[extentIndex] as Map)['height']);
        return band == null ? null : (band: band, identity: identity(layer));
      }
      return null;
  }
}
