import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../domain/map_coordinates.dart';
import '../domain/map_floors.dart';
import '../domain/map_geometry.dart';
import '../domain/map_marker_query.dart';
import '../domain/settings.dart';
import '../maps/native_map_scene.dart';
import '../maps/prepared_map.dart';
import '../maps/prepared_map_loader.dart';

/// App-scope map state with explicit local-resource ownership and no DB writes.
///
/// The caller supplies authoritative settings only after its durable save
/// succeeds. Gesture transforms remain in memory per map, including tab/map
/// revisits. This controller neither tracks the game nor produces accepted
/// scans. Each scene demand invalidates older publication before awaiting.
class MapController extends ChangeNotifier {
  MapController({
    required this.loader,
    required this.resources,
    this.unknownHeightVisibility = UnknownHeightVisibility.visible,
  });
  final PreparedMapPackLoader loader;
  final NativeMapResourceOwner resources;
  final UnknownHeightVisibility unknownHeightVisibility;
  PreparedMapPack? _pack;
  PreparedMap? _preparedMap;
  NativeMapScene? _scene;
  MapFloorSelection? _floorSelection;
  // Only deliberate pan/zoom views are retained; absence means auto-fit.
  final Map<String, MapViewTransform> _views = {};
  final Map<String, MapFloorSelection> _floors = {};
  final Map<String, List<_MarkerScenePosition>> _markerPositions = {};
  List<_MarkerProjection>? _projectedMarkers;
  List<ProjectedMapMarker>? _visibleMarkerCache;
  double? _visibleMarkerMargin;
  Map<String, bool> _categoryVisibility = const {};
  String? _selectedMapId;
  Size _viewport = Size.zero;
  MapViewTransform _transform = MapViewTransform();
  int _generation = 0;
  int _inventoryGeneration = 0;
  int _contentGeneration = 0;
  String _search = '';
  List<String> _searchTerms = const [];
  String _questName = '';
  String _questTrader = '';
  String? _selectedMarkerId;
  Set<String> _raidHighlights = const {};
  GamePoint? _playerPosition;
  double? _forwardX;
  double? _forwardZ;
  final Map<String, bool> _automaticFloors = {};
  bool _disposed = false;
  bool _loading = false;
  bool _inventoryLoading = false;
  String? _error;

  List<PreparedMap> get maps => _pack?.maps ?? const [];
  String? get selectedMapId => _selectedMapId;

  /// Changes only when selected map or prepared content authority changes.
  int get contentGeneration => _contentGeneration;
  String get search => _search;
  String get questName => _questName;
  String get questTrader => _questTrader;
  GamePoint? get playerPosition => _playerPosition;
  bool get automaticFloorSupported =>
      _floorSelection?.policy.supportsAutomaticHeight ?? false;
  bool get automaticFloorFollowing =>
      automaticFloorSupported && (_automaticFloors[_selectedMapId] ?? true);
  Set<String> get applicableCategories => {
    ...?_preparedMap?.categories,
    'CustomPins',
  };
  PreparedMap? get preparedMap => _preparedMap;
  NativeMapScene? get scene => _scene;
  MapFloorSelection? get floorSelection => _floorSelection;
  MapViewTransform get transform => _transform;
  Size get viewportSize => _viewport;
  Map<String, bool> get categoryVisibility => _categoryVisibility;
  bool get loading => _loading;
  String? get error => _error;
  bool get unavailable =>
      _pack != null && _preparedMap == null && _selectedMapId != null;

  /// Opens the local inventory with the caller's already-persisted selection.
  Future<void> initialize({
    required String selectedMapId,
    Map<String, bool> categoryVisibility = const {},
  }) async {
    if (_disposed) return;
    final inventoryGeneration = ++_inventoryGeneration;
    ++_contentGeneration;
    _markerPositions.clear();
    _floors.clear();
    _views.clear();
    _clearEvidence();
    ++_generation;
    _selectedMapId = selectedMapId;
    _categoryVisibility = Map.unmodifiable(categoryVisibility);
    _invalidateMarkers();
    _clearScene();
    _preparedMap = null;
    _floorSelection = null;
    _loading = true;
    _inventoryLoading = true;
    _error = null;
    notifyListeners();
    try {
      final pack = await loader.load();
      if (_disposed || inventoryGeneration != _inventoryGeneration) return;
      _pack = pack;
      _inventoryLoading = false;
      _bindSelectedMap();
      await _requestScene();
    } catch (error) {
      if (_disposed || inventoryGeneration != _inventoryGeneration) return;
      _loading = false;
      _inventoryLoading = false;
      _error = 'Prepared map inventory could not be opened: $error';
      notifyListeners();
    }
  }

  /// Applies the caller's effective selection authority: a durable manual
  /// identity or the Map session's detected saved-log identity.
  ///
  /// Unsupported/unbundled identities remain authoritative but expose an
  /// unavailable state. A prior map's scene is cleared before any await.
  Future<void> selectPersistedMap(String id) async {
    if (_disposed || id == _selectedMapId) return;
    ++_generation;
    ++_contentGeneration;
    _clearEvidence();
    _selectedMapId = id;
    _invalidateMarkers();
    _clearScene();
    _preparedMap = null;
    _floorSelection = null;
    if (_pack == null) {
      notifyListeners();
      return;
    }
    _error = null;
    _bindSelectedMap();
    await _requestScene();
  }

  void _bindSelectedMap() {
    _invalidateMarkers();
    final map = _pack?.byId[_selectedMapId];
    _preparedMap = map;
    if (map == null) {
      _floorSelection = null;
      _loading = false;
      return;
    }
    _floorSelection = _floors[map.id] ?? map.floorPolicy.reset();
    _floors[map.id] = _floorSelection!;
    final savedView = _views[map.id];
    _transform =
        savedView ??
        (_hasViewport
            ? MapViewTransform.fit(
                scene: map.displayFrame.sceneExtent,
                viewport: MapExtent(_viewport.width, _viewport.height),
                padding: _fitPadding,
              )
            : MapViewTransform());
    _markerPositions.putIfAbsent(
      map.id,
      () => List.unmodifiable(
        map.markers.map(
          (marker) => _MarkerScenePosition(
            marker,
            map.gameToScene(marker.position),
            List.unmodifiable(marker.outline.map(map.gameToScene)),
          ),
        ),
      ),
    );
  }

  /// Applies the authoritative category snapshot without touching scene art.
  void setCategoryVisibility(Map<String, bool> values) {
    if (_disposed || mapEquals(_categoryVisibility, values)) return;
    _categoryVisibility = Map.unmodifiable(values);
    _invalidateMarkers();
    notifyListeners();
  }

  void setSearch(String value) {
    if (_disposed || value == _search) return;
    _search = value;
    _searchTerms = mapSearchTerms(value);
    _invalidateMarkers();
    notifyListeners();
  }

  void setQuestFilters({String? name, String? trader}) {
    if (_disposed) return;
    final nextName = name ?? _questName;
    final nextTrader = trader ?? _questTrader;
    if (nextName == _questName && nextTrader == _questTrader) return;
    _questName = nextName;
    _questTrader = nextTrader;
    _invalidateMarkers();
    notifyListeners();
  }

  MapMarkerMetadata metadataFor(PreparedMarker marker) {
    for (final position
        in _markerPositions[_selectedMapId] ?? const <_MarkerScenePosition>[]) {
      if (identical(position.marker, marker)) return position.metadata;
    }
    throw ArgumentError('Marker is not in the current prepared map.');
  }

  /// Selection never changes the view; only explicitly source-linked switches
  /// receive a linked highlight.
  void setSelectedMarker(String? id) {
    if (_disposed || id == _selectedMarkerId) return;
    _selectedMarkerId = id;
    _invalidateMarkers();
    notifyListeners();
  }

  void setRaidHighlights(Set<String> ids) {
    if (_disposed || setEquals(ids, _raidHighlights)) return;
    _raidHighlights = Set.unmodifiable(ids);
    _invalidateMarkers();
    notifyListeners();
  }

  void _clearEvidence() {
    _playerPosition = null;
    _forwardX = null;
    _forwardZ = null;
    _raidHighlights = const {};
    _selectedMarkerId = null;
  }

  /// Heading is a game-world X/Z vector, projected by the map's geometry.
  void setPlayerSample(
    GamePoint? position, {
    double? forwardX,
    double? forwardZ,
  }) {
    if (_disposed) return;
    if ((forwardX == null) != (forwardZ == null)) {
      throw ArgumentError('A heading requires both X and Z components.');
    }
    if (forwardX != null) {
      requireFinite(forwardX, 'forwardX');
      requireFinite(forwardZ!, 'forwardZ');
      if (forwardX == 0 && forwardZ == 0) {
        throw ArgumentError('A heading must be nonzero.');
      }
    }
    if (_playerPosition?.x == position?.x &&
        _playerPosition?.z == position?.z &&
        _playerPosition?.height == position?.height &&
        _forwardX == forwardX &&
        _forwardZ == forwardZ) {
      return;
    }
    _playerPosition = position;
    _forwardX = forwardX;
    _forwardZ = forwardZ;
    if (automaticFloorFollowing) applyOfflineHeight(position?.height);
    notifyListeners();
  }

  ViewportPoint? get playerViewportPoint {
    final map = _preparedMap;
    final player = _playerPosition;
    if (map == null || player == null) return null;
    return _transform.sceneToViewport(map.gameToScene(player));
  }

  /// A projected direction, not an arbitrary glyph-angle convention.
  ScenePoint? get playerSceneDirection {
    final map = _preparedMap;
    final x = _forwardX;
    final z = _forwardZ;
    if (map == null || x == null || z == null) return null;
    final origin = map.gameToScene(GamePoint(0, 0));
    final forward = map.gameToScene(GamePoint(x, z));
    return ScenePoint(forward.x - origin.x, forward.y - origin.y);
  }

  void centerOnPlayer() {
    final point = playerViewportPoint;
    if (_disposed || point == null || !_hasViewport) return;
    panBy(_viewport.width / 2 - point.x, _viewport.height / 2 - point.y);
  }

  void setAutomaticFloorFollowing(bool value) {
    if (_disposed || !automaticFloorSupported) return;
    _automaticFloors[_selectedMapId!] = value;
    if (value) applyOfflineHeight(_playerPosition?.height);
    notifyListeners();
  }

  /// Updates viewport demand, refitting auto-fit maps and preserving manual views.
  void updateViewport(Size size) {
    if (_disposed || size == _viewport) return;
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width < 0 ||
        size.height < 0) {
      throw ArgumentError.value(
        size,
        'size',
        'Viewport must have finite nonnegative dimensions.',
      );
    }
    _viewport = size;
    _invalidateMarkers();
    final map = _preparedMap;
    if (map != null && _hasViewport && !_views.containsKey(map.id)) {
      _transform = MapViewTransform.fit(
        scene: map.displayFrame.sceneExtent,
        viewport: MapExtent(size.width, size.height),
        padding: _fitPadding,
      );
    }
    unawaited(_requestScene());
  }

  void panBy(double dx, double dy) {
    if (_disposed || _preparedMap == null) return;
    _setTransform(_transform.panBy(dx, dy));
  }

  /// Zooms around a fixed viewport-space cursor without coordinate clamping.
  void zoomAt(ViewportPoint cursor, double factor) {
    if (_disposed || _preparedMap == null) return;
    _setTransform(_transform.zoomAt(cursor, factor));
  }

  /// Fits the current viewport and returns this map to automatic fitting.
  void fit() {
    final map = _preparedMap;
    if (_disposed || map == null || !_hasViewport) return;
    _views.remove(map.id);
    _setTransform(
      MapViewTransform.fit(
        scene: map.displayFrame.sceneExtent,
        viewport: MapExtent(_viewport.width, _viewport.height),
        padding: _fitPadding,
      ),
      retainView: false,
    );
  }

  void _setTransform(MapViewTransform value, {bool retainView = true}) {
    _transform = value;
    _invalidateMarkers();
    if (retainView) _views[_preparedMap!.id] = value;
    unawaited(_requestScene());
  }

  void toggleFloor(String floorId) {
    if (_disposed || _floorSelection == null) return;
    final next = _floorSelection!.toggle(floorId);
    _automaticFloors[_selectedMapId!] = false;
    _setFloors(next);
    notifyListeners();
  }

  /// Applies a known offline height only to height-capable maps.
  ///
  /// Unknown height is not zero and leaves the manual selection unchanged.
  /// Conventional vector maps never acquire automatic height behavior from
  /// upstream bands alone. Returns whether a known height was applied.
  bool applyOfflineHeight(double? height) {
    if (_disposed ||
        _floorSelection == null ||
        height == null ||
        !automaticFloorFollowing) {
      return false;
    }
    requireFinite(height, 'height');
    final policy = _floorSelection!.policy;
    if (!policy.supportsAutomaticHeight) return false;
    _setFloors(policy.selectionForHeight(height));
    return true;
  }

  void _setFloors(MapFloorSelection value) {
    final previous = _floorSelection!;
    if (setEquals(previous.selectedOverlayIds, value.selectedOverlayIds)) {
      return;
    }
    ++_generation;
    _floorSelection = value;
    _invalidateMarkers();
    _floors[value.policy.mapId] = value;
    // A hidden floor must disappear immediately from art and marker hits.
    _clearScene();
    unawaited(_requestScene());
  }

  bool get _hasViewport => _viewport.width > 0 && _viewport.height > 0;
  double get _fitPadding => _viewport.shortestSide > 64 ? 24 : 0;

  Future<void> _requestScene() async {
    if (_disposed) return;
    final map = _preparedMap;
    final floors = _floorSelection;
    if (map == null || floors == null || !_hasViewport) {
      ++_generation;
      _loading = _inventoryLoading;
      notifyListeners();
      return;
    }
    if (_scene?.matchesDemand(floors, _transform, _viewport) == true) {
      ++_generation;
      _loading = false;
      _error = null;
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    final transform = _transform;
    final viewport = _viewport;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final scene = await resources.loadScene(
        map,
        floors,
        transform,
        viewport,
        isCurrent: () => !_disposed && generation == _generation,
      );
      if (_disposed || generation != _generation) {
        scene?.dispose();
        return;
      }
      if (scene == null) return;
      final previous = _scene;
      _scene = scene;
      previous?.dispose();
      _loading = false;
      notifyListeners();
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _loading = false;
      _error = 'Prepared artwork could not be loaded: $error';
      // Previous-good viewport resources are retained only under the same
      // map/floor identity. Map/floor switches cleared them synchronously.
      notifyListeners();
    }
  }

  /// Returns the shared drawable, focusable and hittable marker inventory.
  ///
  /// Categories default to visible unless explicitly disabled. Marker height
  /// stays nullable and the same floor predicate governs all access paths.
  /// Positions and outlines use viewport units so glyph/hit sizes stay fixed.
  List<ProjectedMapMarker> visibleMarkers({double margin = 24}) {
    requireFinite(margin, 'margin');
    if (margin < 0) throw ArgumentError.value(margin, 'margin');
    final map = _preparedMap;
    final floors = _floorSelection;
    if (_disposed || map == null || floors == null || !_hasViewport) {
      return const [];
    }
    if (_visibleMarkerCache != null && _visibleMarkerMargin == margin) {
      return _visibleMarkerCache!;
    }
    final projections = _projectedMarkers ??= _projectMarkers(map, floors);
    _visibleMarkerMargin = margin;
    return _visibleMarkerCache = List.unmodifiable([
      for (final projection in projections)
        if (projection.right >= -margin &&
            projection.left <= _viewport.width + margin &&
            projection.bottom >= -margin &&
            projection.top <= _viewport.height + margin)
          projection.marker,
    ]);
  }

  void _invalidateMarkers() {
    _projectedMarkers = null;
    _visibleMarkerCache = null;
    _visibleMarkerMargin = null;
  }

  List<_MarkerProjection> _projectMarkers(
    PreparedMap map,
    MapFloorSelection floors,
  ) {
    final result = <_MarkerProjection>[];
    MapMarkerMetadata? selected;
    for (final position
        in _markerPositions[map.id] ?? const <_MarkerScenePosition>[]) {
      if (position.marker.id == _selectedMarkerId &&
          position.marker.category == 'extracts' &&
          _markerEligible(position, floors)) {
        selected = position.metadata;
      }
    }
    for (final position
        in _markerPositions[map.id] ?? const <_MarkerScenePosition>[]) {
      final marker = position.marker;
      if (!_markerEligible(position, floors)) {
        continue;
      }
      final point = _transform.sceneToViewport(position.point);
      final outline = List<ViewportPoint>.unmodifiable(
        position.outline.map(_transform.sceneToViewport),
      );
      var left = point.x;
      var right = point.x;
      var top = point.y;
      var bottom = point.y;
      for (final vertex in outline) {
        if (vertex.x < left) left = vertex.x;
        if (vertex.x > right) right = vertex.x;
        if (vertex.y < top) top = vertex.y;
        if (vertex.y > bottom) bottom = vertex.y;
      }
      result.add(
        _MarkerProjection(
          ProjectedMapMarker(
            marker: marker,
            scenePoint: position.point,
            viewportPoint: point,
            outline: outline,
            dimmed: !position.metadata.matchesSearch(_searchTerms),
            raidHighlighted: _raidHighlights.contains(marker.id),
            linkedHighlighted:
                marker.category == 'switches' &&
                selected != null &&
                ((position.metadata.sourceId != null &&
                        selected.linkedSwitchIds.contains(
                          position.metadata.sourceId,
                        )) ||
                    (selected.sourceId != null &&
                        position.metadata.activatedIds.contains(
                          selected.sourceId,
                        ))),
          ),
          left,
          top,
          right,
          bottom,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  bool _markerEligible(
    _MarkerScenePosition position,
    MapFloorSelection floors,
  ) =>
      _categoryVisibility[position.marker.filterKey] != false &&
      _categoryVisibility[position.marker.category] != false &&
      position.metadata.matchesQuest(name: _questName, trader: _questTrader) &&
      floors.isVisible(
        floorId: position.marker.floorId,
        height: position.marker.position.height,
        unknownHeight: unknownHeightVisibility,
      );

  /// Selects a visible marker with a fixed logical-pixel hit radius.
  ProjectedMapMarker? hitTestMarker(ViewportPoint point, {double radius = 18}) {
    requirePositiveFinite(radius, 'radius');
    ProjectedMapMarker? nearest;
    var distance = radius * radius;
    final markers = visibleMarkers(margin: radius);
    for (final marker in markers.reversed) {
      final dx = point.x - marker.viewportPoint.x;
      final dy = point.y - marker.viewportPoint.y;
      final candidate = dx * dx + dy * dy;
      if (candidate <= distance) {
        nearest = marker;
        distance = candidate;
      }
    }
    if (nearest != null) return nearest;
    for (final marker in markers.reversed) {
      if (_insideOutline(point, marker.outline)) return marker;
    }
    return null;
  }

  /// Projects an unchanged persisted frame, or null if projection overflows.
  ViewportPoint? projectPin(CustomPin pin) {
    final map = _preparedMap;
    if (_disposed || map == null || pin.mapId != map.id) return null;
    final coordinates = MapPinCoordinates.fromPin(pin);
    try {
      final artwork = map.pinProjector.pinToArtwork(coordinates);
      return _transform.sceneToViewport(
        map.displayFrame.artworkToScene(artwork),
      );
    } on ArgumentError catch (error) {
      final value = error.invalidValue;
      if (value is double && !value.isFinite) return null;
      rethrow;
    }
  }

  /// Interprets a viewport location in the selected map's persisted pin frame.
  MapPinCoordinates? pinAt(ViewportPoint point) {
    final map = _preparedMap;
    if (_disposed || map == null) return null;
    return map.pinProjector.artworkToPin(
      map.displayFrame.sceneToArtwork(_transform.viewportToScene(point)),
    );
  }

  /// New pointer/keyboard pins must be inside displayed original artwork.
  /// Existing finite off-artwork records still use [pinAt] without clamping.
  MapPinCoordinates? pinCreationAt(ViewportPoint point) {
    final map = _preparedMap;
    if (_disposed || map == null) return null;
    final scenePoint = _transform.viewportToScene(point);
    final extent = map.displayFrame.sceneExtent;
    if (scenePoint.x < 0 ||
        scenePoint.y < 0 ||
        scenePoint.x > extent.width ||
        scenePoint.y > extent.height) {
      return null;
    }
    return pinAt(point);
  }

  void _clearScene() {
    _scene?.dispose();
    _scene = null;
  }

  /// Silently invalidates all pending work and releases native resources.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    ++_inventoryGeneration;
    _clearScene();
    resources.dispose();
    super.dispose();
  }
}

/// One visible independent marker projected for painting, focus and details.
class ProjectedMapMarker {
  const ProjectedMapMarker({
    required this.marker,
    required this.scenePoint,
    required this.viewportPoint,
    required this.outline,
    this.dimmed = false,
    this.linkedHighlighted = false,
    this.raidHighlighted = false,
  });
  final bool dimmed;
  final bool linkedHighlighted;
  final bool raidHighlighted;
  final PreparedMarker marker;
  final ScenePoint scenePoint;
  final ViewportPoint viewportPoint;
  final List<ViewportPoint> outline;
}

class _MarkerProjection {
  const _MarkerProjection(
    this.marker,
    this.left,
    this.top,
    this.right,
    this.bottom,
  );
  final ProjectedMapMarker marker;
  final double left;
  final double top;
  final double right;
  final double bottom;
}

class _MarkerScenePosition {
  _MarkerScenePosition(this.marker, this.point, this.outline)
    : metadata = MapMarkerMetadata(
        name: marker.name,
        type: marker.filterKey,
        category: marker.category,
        details: marker.details,
        source: marker.source,
      );
  final MapMarkerMetadata metadata;
  final PreparedMarker marker;
  final ScenePoint point;
  final List<ScenePoint> outline;
}

bool _insideOutline(ViewportPoint point, List<ViewportPoint> outline) {
  if (outline.length < 3) return false;
  var inside = false;
  for (var i = 0, j = outline.length - 1; i < outline.length; j = i++) {
    final a = outline[i];
    final b = outline[j];
    if ((a.y > point.y) != (b.y > point.y) &&
        point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}
