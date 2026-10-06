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
  bool contains(double height) {
    requireFinite(height, 'height');
    return min <= height && height < max;
  }
}

class MapFloor {
  MapFloor({
    required this.id,
    required this.label,
    Iterable<String> attachedLayerIds = const [],
    this.heightBand,
  }) : attachedLayerIds = List.unmodifiable(attachedLayerIds) {
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
  final HeightBand? heightBand;
}

class MapFloorPolicy {
  MapFloorPolicy({
    required this.mapId,
    required this.base,
    Iterable<MapFloor> overlays = const [],
    this.exclusive = false,
  }) : overlays = List.unmodifiable(overlays) {
    floors = List.unmodifiable([base, ...this.overlays]);
    final owners = <String, MapFloor>{};
    for (final floor in floors) {
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
      for (final floor in floors) floor.id: floor,
    });
  }
  final String mapId;
  final MapFloor base;
  final List<MapFloor> overlays;
  final bool exclusive;
  late final Map<String, MapFloor> _layerOwners;
  late final Map<String, MapFloor> _selectable;
  late final List<MapFloor> floors;
  Iterable<MapFloor> get selectableFloors => _selectable.values;
  bool get supportsAutomaticHeight =>
      mapId == 'thelab' || mapId == 'icebreaker';

  factory MapFloorPolicy.streets() => MapFloorPolicy(
    mapId: 'streetsoftarkov',
    base: MapFloor(
      id: 'Ground_Level',
      label: 'Ground Level',
      attachedLayerIds: ['First_Floor'],
    ),
    overlays: [
      MapFloor(id: 'Fifth_Floor', label: '5th Floor'),
      MapFloor(id: 'Fourth_Floor', label: '4th Floor'),
      MapFloor(id: 'Third_Floor', label: '3rd Floor'),
      MapFloor(id: 'Second_Floor', label: '2nd Floor'),
      MapFloor(id: 'Underground_Level', label: 'Underground'),
    ],
  );

  factory MapFloorPolicy.labs() => MapFloorPolicy(
    mapId: 'thelab',
    base: MapFloor(id: 'First_Level', label: 'First Level'),
    overlays: [
      MapFloor(
        id: 'Second_Level',
        label: 'Second Level',
        heightBand: HeightBand(3, 1000),
      ),
      MapFloor(
        id: 'Technical_Level',
        label: 'Technical',
        heightBand: HeightBand(-1000, -.9),
      ),
    ],
  );

  factory MapFloorPolicy.icebreaker() => MapFloorPolicy(
    mapId: 'icebreaker',
    base: MapFloor(id: 'Infirmary', label: 'Infirmary'),
    exclusive: true,
    overlays: [
      MapFloor(
        id: 'Bridge_Roof',
        label: 'Bridge Roof',
        heightBand: HeightBand(43.8, 10000),
      ),
      MapFloor(
        id: 'Bridge',
        label: 'Bridge',
        heightBand: HeightBand(40.7, 43.8),
      ),
      MapFloor(
        id: 'Stairs_Blocked',
        label: 'Stairs Blocked',
        heightBand: HeightBand(37.6, 40.7),
      ),
      MapFloor(
        id: 'Officers_Deck',
        label: 'Officers Deck',
        heightBand: HeightBand(34.5, 37.6),
      ),
      MapFloor(
        id: 'Accommodation_Upper',
        label: 'Accommodation Upper',
        heightBand: HeightBand(31.4, 34.5),
      ),
      MapFloor(
        id: 'Accommodation_Mid',
        label: 'Accommodation Mid',
        heightBand: HeightBand(28.3, 31.4),
      ),
      MapFloor(
        id: 'Accommodation_Lower',
        label: 'Accommodation Lower',
        heightBand: HeightBand(25.3, 28.3),
      ),
      MapFloor(
        id: 'Gym_Canteen',
        label: 'Gym Canteen',
        heightBand: HeightBand(22.2, 25.3),
      ),
      MapFloor(
        id: 'Helipad',
        label: 'Helipad',
        heightBand: HeightBand(19.57, 22.2),
      ),
      MapFloor(
        id: 'Storage_Security',
        label: 'Storage Security',
        heightBand: HeightBand(15, 18.92),
      ),
      MapFloor(
        id: 'Fuel_Pumps',
        label: 'Fuel Pumps',
        heightBand: HeightBand(11.9, 15),
      ),
      MapFloor(
        id: 'Fuel_Pumps_Lower',
        label: 'Fuel Pumps Lower',
        heightBand: HeightBand(8.8, 11.9),
      ),
      MapFloor(
        id: 'Engine_Room_Upper',
        label: 'Engine Room Upper',
        heightBand: HeightBand(5.7, 8.8),
      ),
      MapFloor(
        id: 'Engine_Room',
        label: 'Engine Room',
        heightBand: HeightBand(3.6, 5.7),
      ),
      MapFloor(
        id: 'Control_Room',
        label: 'Control Room',
        heightBand: HeightBand(-10000, 3.6),
      ),
    ],
  );

  MapFloorSelection reset() => MapFloorSelection._(this, const {});

  // Null is unresolved; an unmatched known height belongs to the base. No
  // conventional map is auto-classified even when imported metadata has bands.
  MapFloor? floorForHeight(double? height) {
    if (height == null) return null;
    requireFinite(height, 'height');
    if (!supportsAutomaticHeight) return null;
    MapFloor? best;
    for (final floor in overlays) {
      final band = floor.heightBand;
      if (band == null || !band.contains(height)) continue;
      final winningBand = best?.heightBand;
      if (winningBand == null ||
          band.min > winningBand.min ||
          (band.min == winningBand.min && band.max < winningBand.max)) {
        best = floor;
      }
    }
    return best ?? base;
  }

  MapFloorSelection selectionForHeight(double? height) {
    final floor = floorForHeight(height);
    return floor == null || floor.id == base.id
        ? reset()
        : reset().select(floor.id);
  }
}

class MapFloorSelection {
  MapFloorSelection._(this.policy, Set<String> overlays)
    : selectedOverlayIds = Set.unmodifiable(overlays);
  final MapFloorPolicy policy;
  final Set<String> selectedOverlayIds;

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

  // Use this same result for paint, pointer, keyboard focus and details. An
  // explicit floor always wins over height. Unassigned/null height never means
  // height zero or ground: the caller must choose the uncertainty visibility.
  bool isVisible({
    String? floorId,
    double? height,
    required UnknownHeightVisibility unknownHeight,
  }) {
    if (height != null) requireFinite(height, 'height');
    if (floorId != null) return isLayerVisible(floorId);
    final inferred = policy.floorForHeight(height);
    if (inferred == null) {
      return unknownHeight == UnknownHeightVisibility.visible;
    }
    return isLayerVisible(inferred.id);
  }
}
