import 'map_coordinates.dart';

enum UnknownHeightVisibility { visible, hidden }

class HeightBand {
  HeightBand(this.min, this.max) {
    requireFinite(min, 'minimum height');
    requireFinite(max, 'maximum height');
    if (max <= min) throw ArgumentError('Height band must be nonempty.');
  }
  final double min;
  final double max;
}

/// A floor's height interval and optional game-space coverage.
class FloorExtent {
  FloorExtent(this.height, {Iterable<GameBounds> bounds = const []})
    : _span = height.max - height.min,
      bounds = bounds.isEmpty ? const [] : List.unmodifiable(bounds) {
    requirePositiveFinite(_span, 'floor extent height span');
  }

  final HeightBand height;
  final List<GameBounds> bounds;
  final double _span;

  bool _matches(GamePoint point, double height) {
    if (height < this.height.min || height >= this.height.max) return false;
    if (bounds.isEmpty) return true;
    for (final rectangle in bounds) {
      if (point.x >= rectangle.minX &&
          point.x <= rectangle.maxX &&
          point.z >= rectangle.minZ &&
          point.z <= rectangle.maxZ) {
        return true;
      }
    }
    return false;
  }
}

class MapFloor {
  MapFloor({
    required this.id,
    required this.label,
    Iterable<String> attachedLayerIds = const [],
    Iterable<FloorExtent> extents = const [],
  }) : attachedLayerIds = List.unmodifiable(attachedLayerIds),
       extents = extents.isEmpty ? const [] : List.unmodifiable(extents) {
    if (id.isEmpty ||
        label.isEmpty ||
        this.attachedLayerIds.any((id) => id.isEmpty)) {
      throw ArgumentError(
        'Floor and attached layer identities must be nonempty.',
      );
    }
  }
  final String id;
  final String label;
  final List<String> attachedLayerIds;
  final List<FloorExtent> extents;
}

/// The ordered, selectable floors and their associated artwork layers.
class MapFloorPolicy {
  /// Creates the floor policy in the supplied bottom-to-top order.
  MapFloorPolicy({
    required this.mapId,
    required String baseId,
    required Iterable<MapFloor> floors,
    this.exclusive = false,
  }) : floors = List.unmodifiable(floors) {
    baseIndex = this.floors.indexWhere((floor) => floor.id == baseId);
    if (baseIndex < 0) throw ArgumentError.value(baseId, 'baseId');
    final owners = <String, MapFloor>{};
    for (final floor in this.floors) {
      for (final id in [floor.id, ...floor.attachedLayerIds]) {
        if (owners.containsKey(id)) {
          throw ArgumentError(
            'Duplicate or independently selectable attached layer: $id.',
          );
        }
        owners[id] = floor;
      }
    }
    _layerOwners = Map.unmodifiable(owners);
    _selectable = Map.unmodifiable({
      for (final floor in this.floors) floor.id: floor,
    });
  }
  final String mapId;

  /// The base floor, regardless of its place in the floor array.
  MapFloor get base => floors[baseIndex];

  /// The base floor's index in [floors].
  late final int baseIndex;

  late final List<MapFloor> overlays = List.unmodifiable(
    floors.where((floor) => floor.id != base.id),
  );
  final bool exclusive;
  late final Map<String, MapFloor> _layerOwners;
  late final Map<String, MapFloor> _selectable;

  /// Selectable floors in the prepared bottom-to-top order.
  final List<MapFloor> floors;
  Iterable<MapFloor> get selectableFloors => _selectable.values;

  /// Whether any prepared floor provides automatic classification data.
  late final bool supportsAutomaticHeight = floors.any(
    (floor) => floor.extents.isNotEmpty,
  );

  MapFloorSelection reset() => MapFloorSelection._(this, const {});

  /// Classifies [position] using the narrowest matching extent, then floor ID.
  ///
  /// Missing height or a map without extents is unresolved. A known position
  /// outside every extent belongs to the base.
  MapFloor? floorForPosition(GamePoint? position) {
    if (position == null || !supportsAutomaticHeight) return null;
    final height = position.height;
    if (height == null) return null;
    MapFloor? best;
    var bestSpan = double.infinity;
    for (final floor in floors) {
      for (final extent in floor.extents) {
        final span = extent._span;
        if (span > bestSpan ||
            (span == bestSpan && floor.id.compareTo(best!.id) >= 0)) {
          continue;
        }
        if (extent._matches(position, height)) {
          best = floor;
          bestSpan = span;
        }
      }
    }
    return best ?? base;
  }
}

class MapFloorSelection {
  MapFloorSelection._(this.policy, Set<String> overlays)
    : selectedOverlayIds = Set.unmodifiable(overlays);
  final MapFloorPolicy policy;
  final Set<String> selectedOverlayIds;

  /// The index of the highest visible overlay, or the base when none is shown.
  late final int currentIndex = selectedOverlayIds.isEmpty
      ? policy.baseIndex
      : policy.floors.lastIndexWhere(
          (floor) => selectedOverlayIds.contains(floor.id),
        );

  MapFloorSelection select(String floorId) {
    if (!policy._selectable.containsKey(floorId)) {
      throw ArgumentError.value(
        floorId,
        'floorId',
        'Not a manually selectable floor.',
      );
    }
    if (floorId == policy.base.id) return policy.reset();
    return MapFloorSelection._(
      policy,
      policy.exclusive ? {floorId} : {...selectedOverlayIds, floorId},
    );
  }

  /// Shows only [floorId] and the base if this map draws additive overlays.
  MapFloorSelection selectOnly(String floorId) {
    if (!policy._selectable.containsKey(floorId)) {
      throw ArgumentError.value(
        floorId,
        'floorId',
        'Not a manually selectable floor.',
      );
    }
    return _selectOnly(floorId);
  }

  MapFloorSelection _selectOnly(String floorId) {
    if (floorId == policy.base.id) {
      return selectedOverlayIds.isEmpty ? this : policy.reset();
    }
    if (selectedOverlayIds.length == 1 &&
        selectedOverlayIds.contains(floorId)) {
      return this;
    }
    return MapFloorSelection._(policy, {floorId});
  }

  MapFloorSelection toggle(String floorId) {
    if (!policy._selectable.containsKey(floorId)) {
      throw ArgumentError.value(
        floorId,
        'floorId',
        'Not a manually selectable floor.',
      );
    }
    if (floorId == policy.base.id) return policy.reset();
    if (selectedOverlayIds.contains(floorId)) {
      return MapFloorSelection._(
        policy,
        {...selectedOverlayIds}..remove(floorId),
      );
    }
    return select(floorId);
  }

  /// Selects the floor for [position], keeping this selection if unresolved.
  MapFloorSelection followPosition(GamePoint? position) {
    final floor = policy.floorForPosition(position);
    return floor == null ? this : _selectOnly(floor.id);
  }

  bool isLayerVisible(String layerId) {
    final owner = policy._layerOwners[layerId];
    if (owner == null) {
      throw ArgumentError.value(layerId, 'layerId', 'Unknown layer identity.');
    }
    if (owner.id == policy.base.id) {
      return !policy.exclusive || selectedOverlayIds.isEmpty;
    }
    return selectedOverlayIds.contains(owner.id);
  }

  Iterable<String> get visibleLayerIds sync* {
    // Canonical source order, not manual click order.
    for (final floor in policy.floors) {
      if (isLayerVisible(floor.id)) {
        yield floor.id;
        yield* floor.attachedLayerIds;
      }
    }
  }

  /// Tests the resolved marker floor, or the caller's policy when unresolved.
  bool isVisible({
    String? floorId,
    required UnknownHeightVisibility unknownHeight,
  }) => floorId == null
      ? unknownHeight == UnknownHeightVisibility.visible
      : isLayerVisible(floorId);
}
