import 'dart:math' as math;

/// Reads the source extent list without treating malformed data as absence.
List<dynamic> sourceLayerExtents(Map layer, String context) {
  if (!layer.containsKey('extents')) return const [];
  final extents = layer['extents'];
  if (extents is! List) {
    throw FormatException('$context: extents must be a list');
  }
  return extents;
}

/// Reads the nonempty finite height interval shared with label preparation.
List<num> sourceExtentHeight(Object? extent, String context) =>
    switch (extent) {
      {'height': [final num low, final num high]}
          when _positiveSpan(low, high) =>
        [low, high],
      _ => throw FormatException('$context: invalid extent height range'),
    };

/// Converts one source extent into the canonical prepared floor representation.
Map<String, Object?> normalizeSourceExtent(Object? raw, String context) {
  final height = sourceExtentHeight(raw, context);
  final extent = raw as Map;
  final bounds = extent.containsKey('bounds') ? extent['bounds'] : const [];
  if (bounds is! List) {
    throw FormatException('$context: extent bounds must be a list');
  }
  return {
    'height': height,
    'bounds': [for (final rectangle in bounds) _normalize(rectangle, context)],
  };
}

List<num> _normalize(Object? rectangle, String context) {
  if (rectangle
      case [
        [final num x1, final num z1],
        [final num x2, final num z2],
        ...final rest,
      ]
      when rest.isEmpty || (rest.length == 1 && rest.single is String)) {
    final minX = math.min(x1, x2), maxX = math.max(x1, x2);
    final minZ = math.min(z1, z2), maxZ = math.max(z1, z2);
    if (_positiveSpan(minX, maxX) && _positiveSpan(minZ, maxZ)) {
      return [minX, minZ, maxX, maxZ];
    }
  }
  throw FormatException('$context: invalid extent rectangle');
}

bool _positiveSpan(num low, num high) {
  final span = high.toDouble() - low.toDouble();
  return span.isFinite && span > 0;
}
