import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../application/app_services.dart';
import '../application/map_controller.dart';
import '../application/map_session_controller.dart';
import '../domain/map_coordinates.dart';
import '../domain/map_marker_query.dart';
import '../domain/map_place_labels.dart';
import '../domain/map_zone_style.dart';
import '../domain/marker_categories.dart';
import '../domain/settings.dart';
import '../maps/map_marker_icons.dart';
import '../maps/map_palette.dart';
import '../maps/marker_presentation.dart';
import '../maps/prepared_map.dart';
import 'marker_popup.dart';
import 'pin_editor.dart';
import 'labels.dart';
import 'ember/ember_tokens.dart';
import 'ember/theme_access.dart';

/// How the player's position reaches the map, as the map help explains it.
const _positionHelp =
    "Your position and facing come from screenshots you take during a raid "
    "with the game's own screenshot key. Blackgrid reads them from the "
    'Screenshot folder set in Settings. Without such a screenshot the map '
    'shows no position. Blackgrid never captures the screen for this.';

/// The map controls listed in the map help, as (control, action) pairs.
const _controlHelp = [
  ('Select a marker badge or Browse', 'Open its anchored summary bubble'),
  ('Scroll inside the bubble', 'Scroll the marker summary'),
  ('Drag or arrow keys outside the bubble', 'Pan the map'),
  ('Mouse wheel or + / - outside the bubble', 'Zoom in or out'),
  ('Home', 'Fit the map to the view'),
  ('C', 'Center on your position'),
  ('Enter', 'Browse markers'),
  ('N or right-click', 'Add a pin'),
  ('Delete', 'Remove the selected pin'),
  ('Escape', 'Clear the selection'),
  ('Hover over an extract', 'Show its area'),
];

/// Gap between the map's edge and the controls drawn over it.
const _overlayInset = 12.0;

/// The id of the floor control's Auto segment.
const _autoFloor = 'auto';

/// The map ground stays dark in both rooms (DESIGN.md X6), so controls drawn on
/// it take the dark room's roles, as the map's own text does.
const _overlayInk = EmberColors.dark;

/// Compact entries keep all thirteen maps and the screenshot item on screen.
final _menuItemStyle = MenuItemButton.styleFrom(
  visualDensity: VisualDensity.compact,
  minimumSize: const Size(0, 32),
);

/// The surface of a control group floating over the map.
final _overlaySurface = BoxDecoration(
  color: _overlayInk.raised,
  border: Border.all(color: _overlayInk.hairlineStrong),
  borderRadius: BorderRadius.circular(EmberRadius.m),
);

/// Native artwork and screen-space targets share the controller's view geometry.
class MapWorkspace extends StatefulWidget {
  /// Creates the map viewport and its session-connected selection controls.
  const MapWorkspace({super.key, required this.services});

  /// The initialized application services shared with the Map screen.
  final AppServices services;

  @override
  State<MapWorkspace> createState() => _MapWorkspaceState();
}

class _MapWorkspaceState extends State<MapWorkspace> {
  String? _hoveredMarker;
  int? _hoverGeneration;

  /// Where the mouse last hovered over the map, or `null` once it left.
  ViewportPoint? _hoverPoint;
  String? _selectedPin;
  String? _selectedPinMapId;
  final _focus = FocusNode(debugLabel: 'Native map workspace');
  MapController get maps => widget.services.maps;

  @override
  void initState() {
    super.initState();
    maps.addListener(_rehover);
    maps.addListener(_dropPinForMarker);
  }

  @override
  void dispose() {
    maps.removeListener(_rehover);
    maps.removeListener(_dropPinForMarker);
    _focus.dispose();
    super.dispose();
  }

  List<CustomPin> get pins => widget.services.settings.pins
      .where((pin) => pin.mapId == maps.selectedMapId)
      .toList();

  bool _isVisiblePin(CustomPin pin) =>
      pin.mapId == maps.selectedMapId &&
      widget.services.settings.settings.markerFilters['CustomPins'] != false;

  ViewportPoint get _viewportCenter =>
      ViewportPoint(maps.viewportSize.width / 2, maps.viewportSize.height / 2);

  /// Clears the selected pin once a marker is selected from outside the
  /// workspace, such as a This raid row, so only one thing is selected.
  ///
  /// The workspace's own pin selections clear the marker first, so they never
  /// reach this with a marker selected.
  void _dropPinForMarker() {
    if (_selectedPin == null || !mounted) return;
    if (maps.selectedMarkerProjection == null) return;
    setState(() {
      _selectedPin = null;
      _selectedPinMapId = null;
    });
  }

  void _selectMarker(String? id) {
    _focus.requestFocus();
    maps.setSelectedMarker(id);
    setState(() {
      _selectedPin = null;
      _selectedPinMapId = null;
    });
  }

  void _closeMarker() {
    _focus.requestFocus();
    maps.setSelectedMarker(null);
  }

  /// The hovered marker id, unless the map or its content changed since.
  String? get _liveHover =>
      _hoverGeneration == maps.contentGeneration ? _hoveredMarker : null;

  void _hover(PointerHoverEvent event) {
    _hoverPoint = ViewportPoint(event.localPosition.dx, event.localPosition.dy);
    _rehover();
  }

  /// Hit-tests the last hover point again, so the hover follows the map when
  /// it pans or zooms under a still pointer.
  void _rehover() {
    final point = _hoverPoint;
    if (point == null || !mounted) return;
    final id = maps.preparedMap == null
        ? null
        : maps
              .hitTestMarker(point, radius: 22, hoveredMarkerId: _liveHover)
              ?.marker
              .id;
    if (id == _liveHover) return;
    setState(() {
      _hoveredMarker = id;
      _hoverGeneration = maps.contentGeneration;
    });
  }

  void _leave() {
    _hoverPoint = null;
    if (_hoveredMarker == null) return;
    setState(() {
      _hoveredMarker = null;
      _hoverGeneration = null;
    });
  }

  void _createPinAt(ViewportPoint point) {
    final coordinates = maps.pinCreationAt(point);
    if (coordinates == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a point inside the map artwork.')),
      );
      return;
    }
    showPinEditor(context, widget.services, coordinates: coordinates);
  }

  /// Opens the map help, then gives keyboard focus back to the map.
  Future<void> _showHelp() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Map help'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your position',
                style: EmberType.uiHeading.copyWith(color: context.ember.ink),
              ),
              const SizedBox(height: EmberSpace.xs),
              const Text(_positionHelp),
              const SizedBox(height: EmberSpace.lg),
              Text(
                'Controls',
                style: EmberType.uiHeading.copyWith(color: context.ember.ink),
              ),
              const SizedBox(height: EmberSpace.xs),
              for (final (control, action) in _controlHelp)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 180, child: Text(control)),
                      Expanded(
                        child: Text(
                          action,
                          style: EmberType.body.copyWith(
                            color: context.ember.inkSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (mounted) _focus.requestFocus();
  }

  Future<void> _removePin(CustomPin pin) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove pin record?'),
        content: Text('${pin.label} · ${mapLabel(pin.mapId)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove == true) await widget.services.settings.removePin(pin);
  }

  void _select(ViewportPoint point) {
    _focus.requestFocus();
    final marker = maps.hitTestMarker(
      point,
      radius: 22,
      hoveredMarkerId: _liveHover,
    );
    String? pinId;
    if (widget.services.settings.settings.markerFilters['CustomPins'] !=
        false) {
      var distance = 22.0 * 22;
      for (final pin in pins) {
        final anchor = maps.projectPin(pin);
        if (anchor == null) continue;
        final dx = anchor.x - point.x, dy = anchor.y - point.y;
        final next = dx * dx + dy * dy;
        if (next <= distance) {
          distance = next;
          pinId = pin.id;
        }
      }
    }
    maps.setSelectedMarker(pinId == null ? marker?.marker.id : null);
    setState(() {
      _selectedPin = pinId;
      _selectedPinMapId = pinId == null ? null : maps.selectedMapId;
    });
  }

  Future<void> _browse() async {
    final visible = maps.visibleMarkers();
    final visiblePins = widget.services.settings.pins
        .where(_isVisiblePin)
        .toList();
    if (visible.isEmpty && visiblePins.isEmpty) return;
    final mapId = maps.selectedMapId;
    final generation = maps.contentGeneration;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: 450,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(EmberSpace.md),
              child: Text(
                'Visible map markers and pins',
                style: EmberType.title.copyWith(color: context.ember.ink),
              ),
            ),
            Expanded(
              child: ListView.builder(
                key: const ValueKey('marker-browser-list'),
                itemCount: visible.length + visiblePins.length,
                itemBuilder: (context, index) {
                  if (index < visible.length) {
                    final marker = visible[index].marker;
                    return MarkerBrowserRow(
                      title: marker.name,
                      subtitle: markerCategoryLabel(marker.filterKey),
                      onTap: () =>
                          Navigator.pop(context, 'marker:${marker.id}'),
                    );
                  }
                  final pin = visiblePins[index - visible.length.toInt()];
                  return MarkerBrowserRow(
                    title: pin.label,
                    subtitle: 'Saved pin',
                    onTap: () => Navigator.pop(context, 'pin:${pin.id}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted ||
        mapId != maps.selectedMapId ||
        generation != maps.contentGeneration ||
        id == null) {
      return;
    }
    if (id.startsWith('marker:') &&
        !maps.visibleMarkers().any(
          (marker) => marker.marker.id == id.substring(7),
        )) {
      return;
    }
    if (id.startsWith('pin:') &&
        !pins.any((pin) => pin.id == id.substring(4) && _isVisiblePin(pin))) {
      return;
    }
    _focus.requestFocus();
    maps.setSelectedMarker(id.startsWith('marker:') ? id.substring(7) : null);
    setState(() {
      _selectedPin = id.startsWith('pin:') ? id.substring(4) : null;
      _selectedPinMapId = _selectedPin == null ? null : mapId;
    });
  }

  KeyEventResult _key(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      maps.panBy(40, 0);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      maps.panBy(-40, 0);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      maps.panBy(0, 40);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      maps.panBy(0, -40);
    } else if (key == LogicalKeyboardKey.home) {
      maps.fit();
    } else if (key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      maps.zoomAt(_viewportCenter, 1.25);
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      maps.zoomAt(_viewportCenter, .8);
    } else if (key == LogicalKeyboardKey.keyC) {
      maps.centerOnPlayer();
    } else if (key == LogicalKeyboardKey.keyN) {
      if (!widget.services.settings.busy) {
        _createPinAt(_viewportCenter);
      }
    } else if (key == LogicalKeyboardKey.enter) {
      _browse();
    } else if (key == LogicalKeyboardKey.delete) {
      if (_selectedPinMapId == maps.selectedMapId &&
          !widget.services.settings.busy) {
        for (final pin in pins) {
          if (pin.id == _selectedPin && _isVisiblePin(pin)) {
            _removePin(pin);
            break;
          }
        }
      }
    } else if (key == LogicalKeyboardKey.escape) {
      maps.setSelectedMarker(null);
      setState(() {
        _selectedPin = null;
        _selectedPinMapId = null;
      });
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Applies the picker's choice. A hand-picked map turns log following off.
  void _chooseMap(String id) {
    if (widget.services.settings.busy) return;
    widget.services.settings.setMap(id);
  }

  /// Reads the newest saved screenshot and says why nothing was applied.
  ///
  /// Only the two failures that leave the player guessing get a notice. An
  /// applied read shows in the map, and a superseded one is silent.
  Future<void> _readLatest() async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await widget.services.mapSession.readLatest();
    if (!mounted) return;
    final message = switch (outcome) {
      ReadLatestApplied() || ReadLatestSuperseded() => null,
      ReadLatestNoScreenshot() => 'There is no screenshot to read.',
      ReadLatestUnavailable() => 'The screenshot could not be read.',
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _setFloorSelection(Set<String> next, Set<String> current) {
    for (final id in {
      ...next.difference(current),
      ...current.difference(next),
    }) {
      if (id == _autoFloor) {
        maps.setAutomaticFloorFollowing(!maps.automaticFloorFollowing);
      } else {
        maps.toggleFloor(id);
      }
    }
  }

  void _closePin() {
    _focus.requestFocus();
    setState(() {
      _selectedPin = null;
      _selectedPinMapId = null;
    });
  }

  /// The map's name as a button that opens the map menu.
  Widget _mapPicker(BuildContext context) {
    final settings = widget.services.settings;
    final session = widget.services.mapSession.state;
    final current = maps.selectedMapId ?? settings.settings.selectedMap;
    final reading = session.readingLatest;
    return MenuAnchor(
      menuChildren: [
        for (final id in supportedMaps)
          MenuItemButton(
            key: Key('map-picker-item-$id'),
            style: _menuItemStyle,
            leadingIcon: SizedBox(
              width: 18,
              child: id == current ? const Icon(Icons.check, size: 18) : null,
            ),
            onPressed: settings.busy ? null : () => _chooseMap(id),
            child: Text(mapLabel(id)),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SizedBox(
            width: 240,
            child: Text(
              'Choosing a map turns log following off until you turn it back '
              'on in Settings.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        const Divider(),
        MenuItemButton(
          key: const Key('map-picker-read-latest'),
          style: _menuItemStyle,
          leadingIcon: const Icon(Icons.refresh, size: 18),
          onPressed: reading || session.screenshotDirectory.isEmpty
              ? null
              : _readLatest,
          child: Text(reading ? 'Reading latest…' : 'Read latest screenshot'),
        ),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        key: const Key('map-picker'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _overlayInk.ink,
          backgroundColor: _overlayInk.raised,
          side: BorderSide(color: _overlayInk.hairlineStrong),
          textStyle: EmberType.title.copyWith(fontSize: 15),
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: Icon(Icons.arrow_drop_down, color: _overlayInk.inkTertiary),
        iconAlignment: IconAlignment.end,
        label: Text(mapLabel(current)),
      ),
    );
  }

  /// Auto, when the map follows height, then each floor of the map.
  Widget? _floorControl(PreparedMap? map) {
    if (map == null || maps.error != null || maps.unavailable) return null;
    final floors = map.floorPolicy.floors;
    final selection = maps.floorSelection;
    final auto = maps.automaticFloorSupported;
    if (!auto && floors.isEmpty) return null;
    final selected = {
      if (auto && maps.automaticFloorFollowing) _autoFloor,
      for (final floor in floors)
        if (selection?.isLayerVisible(floor.id) ?? false) floor.id,
    };
    return SegmentedButton<String>(
      key: const Key('map-floor-control'),
      multiSelectionEnabled: true,
      emptySelectionAllowed: true,
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        foregroundColor: _overlayInk.inkSecondary,
        selectedForegroundColor: _overlayInk.ink,
        backgroundColor: _overlayInk.raised,
        selectedBackgroundColor: _overlayInk.segmentOn,
        side: BorderSide(color: _overlayInk.hairlineStrong),
      ),
      segments: [
        if (auto) const ButtonSegment(value: _autoFloor, label: Text('Auto')),
        for (final floor in floors)
          ButtonSegment(value: floor.id, label: Text(floor.label)),
      ],
      selected: selected,
      onSelectionChanged: (next) => _setFloorSelection(next, selected),
    );
  }

  Widget _actionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
    style: IconButton.styleFrom(
      foregroundColor: _overlayInk.inkSecondary,
      disabledForegroundColor: _overlayInk.inkTertiary,
      hoverColor: _overlayInk.hover,
      minimumSize: const Size(36, 36),
    ),
  );

  /// The icon stack at the map's right edge.
  Widget _actionStack(PreparedMap? map, List<ProjectedMapMarker> visible) {
    final settings = widget.services.settings;
    return DecoratedBox(
      key: const Key('map-actions'),
      decoration: _overlaySurface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actionButton(
            tooltip: 'Fit map',
            icon: Icons.fit_screen,
            onPressed: map == null ? null : maps.fit,
          ),
          _actionButton(
            tooltip: 'Zoom in',
            icon: Icons.add,
            onPressed: map == null
                ? null
                : () => maps.zoomAt(_viewportCenter, 1.25),
          ),
          _actionButton(
            tooltip: 'Zoom out',
            icon: Icons.remove,
            onPressed: map == null
                ? null
                : () => maps.zoomAt(_viewportCenter, .8),
          ),
          _actionButton(
            tooltip: 'Center on player',
            icon: Icons.my_location,
            onPressed: maps.playerPosition == null ? null : maps.centerOnPlayer,
          ),
          _actionButton(
            tooltip: 'Pin at view center',
            icon: Icons.add_location_alt_outlined,
            onPressed: map == null || settings.busy
                ? null
                : () => _createPinAt(_viewportCenter),
          ),
          _actionButton(
            tooltip: 'Browse markers',
            icon: Icons.list,
            onPressed: visible.isEmpty && !settings.pins.any(_isVisiblePin)
                ? null
                : _browse,
          ),
          _actionButton(
            tooltip: 'Map help',
            icon: Icons.help_outline,
            onPressed: _showHelp,
          ),
        ],
      ),
    );
  }

  /// The bar at the bottom of the map for the selected saved [pin].
  Widget _pinBar(CustomPin pin) {
    final busy = widget.services.settings.busy;
    final style = TextButton.styleFrom(
      foregroundColor: _overlayInk.ink,
      disabledForegroundColor: _overlayInk.inkTertiary,
      textStyle: EmberType.control,
    );
    return DecoratedBox(
      key: const Key('map-pin-bar'),
      decoration: _overlaySurface,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                pin.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EmberType.uiHeading.copyWith(color: _overlayInk.ink),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              key: const Key('map-pin-edit'),
              style: style,
              onPressed: busy
                  ? null
                  : () => showPinEditor(context, widget.services, pin: pin),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
            ),
            TextButton.icon(
              key: const Key('map-pin-remove'),
              style: style,
              onPressed: busy ? null : () => _removePin(pin),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Remove'),
            ),
            TextButton.icon(
              key: const Key('map-pin-close'),
              style: style,
              onPressed: _closePin,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      maps,
      widget.services.settings,
      widget.services.catalog,
      widget.services.mapSession,
    ]),
    builder: (context, _) {
      final map = maps.preparedMap;
      final visible = maps.visibleMarkers();
      final selectedProjection = maps.selectedMarkerProjection;
      final selected = selectedProjection?.marker;
      CustomPin? selectedPin;
      if (_selectedPinMapId == maps.selectedMapId &&
          widget.services.settings.settings.markerFilters['CustomPins'] !=
              false) {
        for (final pin in pins) {
          if (pin.id == _selectedPin) selectedPin = pin;
        }
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          // Tile demand follows layout. Scheduling avoids notification in build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) maps.updateViewport(size);
          });
          // The action stack takes the right edge; the rest keeps clear of it.
          final clearWidth = math.max(0.0, size.width - 2 * _overlayInset - 48);
          final floors = _floorControl(map);
          return DecoratedBox(
            decoration: BoxDecoration(
              color: context.blackgrid.mapGround,
              border: Border.all(color: context.ember.hairline),
            ),
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Focus(
                    focusNode: _focus,
                    onKeyEvent: (_, event) => _key(event),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Listener(
                          onPointerSignal: (event) {
                            if (event is PointerScrollEvent && map != null) {
                              GestureBinding.instance.pointerSignalResolver
                                  .register(event, (_) {
                                    maps.zoomAt(
                                      ViewportPoint(
                                        event.localPosition.dx,
                                        event.localPosition.dy,
                                      ),
                                      event.scrollDelta.dy < 0
                                          ? 1.15
                                          : 1 / 1.15,
                                    );
                                  });
                            }
                          },
                          child: MouseRegion(
                            onHover: _hover,
                            onExit: (_) => _leave(),
                            child: GestureDetector(
                              key: const Key('native-map-viewport'),
                              behavior: HitTestBehavior.opaque,
                              onPanUpdate: map == null
                                  ? null
                                  : (event) => maps.panBy(
                                      event.delta.dx,
                                      event.delta.dy,
                                    ),
                              onTapUp: (event) => _select(
                                ViewportPoint(
                                  event.localPosition.dx,
                                  event.localPosition.dy,
                                ),
                              ),
                              onSecondaryTapUp: map == null
                                  ? null
                                  : (event) {
                                      if (!widget.services.settings.busy) {
                                        _createPinAt(
                                          ViewportPoint(
                                            event.localPosition.dx,
                                            event.localPosition.dy,
                                          ),
                                        );
                                      }
                                    },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CustomPaint(
                                    painter: _MapPainter(
                                      maps,
                                      widget.services.markerIcons,
                                      pins,
                                      showPins:
                                          widget
                                              .services
                                              .settings
                                              .settings
                                              .markerFilters['CustomPins'] !=
                                          false,
                                      selectedMarker: selected?.id,
                                      hoveredMarker: _liveHover,
                                      selectedPin: selectedPin?.id,
                                      selectMarker: _selectMarker,
                                      selectPin: (id) {
                                        _focus.requestFocus();
                                        maps.setSelectedMarker(null);
                                        setState(() {
                                          _selectedPin = id;
                                          _selectedPinMapId =
                                              maps.selectedMapId;
                                        });
                                      },
                                    ),
                                  ),
                                  if (maps.loading)
                                    const Align(
                                      alignment: Alignment.topCenter,
                                      child: LinearProgressIndicator(),
                                    ),
                                  if (maps.error != null || maps.unavailable)
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Text(
                                          maps.error ?? 'Artwork is not bundled for this map. Saved preferences and pins remain available.',
                                          textAlign: TextAlign.center,
                                          // The map ground stays dark in
                                          // both rooms (DESIGN.md X6), so
                                          // text on it takes dark-room ink.
                                          style: TextStyle(
                                            color:
                                                EmberColors.dark.inkSecondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (selectedProjection != null &&
                            selectedProjection.viewportPoint.x >= 0 &&
                            selectedProjection.viewportPoint.y >= 0 &&
                            selectedProjection.viewportPoint.x < size.width &&
                            selectedProjection.viewportPoint.y < size.height)
                          Builder(
                            builder: (context) {
                              final marker = selectedProjection.marker;
                              final mode = widget.services.catalog.mode;
                              final snapshot = widget.services.catalog.snapshot;
                              final matchingSnapshot = snapshot?.mode == mode
                                  ? snapshot
                                  : null;
                              final presentation = presentMarker(
                                marker,
                                mapMarkers: maps.activeMarkers,
                                activeMode: mode,
                                catalogSnapshot: matchingSnapshot,
                              );
                              return MarkerPopup(
                                key: ValueKey(marker.id),
                                presentation: presentation,
                                anchor: Offset(
                                  selectedProjection.viewportPoint.x,
                                  selectedProjection.viewportPoint.y,
                                ),
                                onClose: _closeMarker,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  // The controls are siblings of the Focus and the gesture
                  // detector, so a key or a click on them never reaches the
                  // map's own handlers.
                  Positioned(
                    left: _overlayInset,
                    top: _overlayInset,
                    width: clearWidth,
                    child: Row(
                      children: [
                        _mapPicker(context),
                        if (floors != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: floors,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    right: _overlayInset,
                    top: _overlayInset,
                    child: _actionStack(map, visible),
                  ),
                  if (selectedPin != null)
                    Positioned(
                      left: _overlayInset,
                      bottom: _overlayInset + 24,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: clearWidth),
                        child: _pinBar(selectedPin),
                      ),
                    ),
                  if (map != null)
                    Positioned(
                      left: _overlayInset,
                      bottom: _overlayInset - 4,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: clearWidth),
                        child: Text(
                          '${map.attribution['author'] ?? map.name}',
                          key: const Key('map-attribution'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: EmberType.label.copyWith(
                            color: _overlayInk.inkSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

const _labelFontSize = 12.0;
const _labelHaloWidth = 3.0;
const _labelGap = 4.0;
const _labelMaxWidth = 180.0;

class _MapPainter extends CustomPainter {
  _MapPainter(
    this.maps,
    this.markerIcons,
    this.pins, {
    required this.showPins,
    required this.selectedMarker,
    required this.hoveredMarker,
    required this.selectedPin,
    required this.selectMarker,
    required this.selectPin,
  }) : super(repaint: Listenable.merge([maps, markerIcons]));
  final MapController maps;
  final MapMarkerIcons markerIcons;
  final List<CustomPin> pins;
  final bool showPins;
  final String? selectedMarker;
  final String? hoveredMarker;
  final String? selectedPin;
  final ValueChanged<String> selectMarker;
  final ValueChanged<String> selectPin;
  final _badgePaints = MarkerBadgePaints();
  late final _fill = _badgePaints.fill;
  final _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    maps.scene?.paint(canvas, maps.transform, size);
    final map = maps.preparedMap;
    if (map == null) return;
    final markerBounds = Rect.fromLTWH(
      -22,
      -22,
      size.width + 44,
      size.height + 44,
    );
    _placeLabels(canvas, size);
    final visible = maps.visibleMarkers();
    for (final projected in visible) {
      if (_outlineShown(projected.marker)) _outline(canvas, projected);
    }
    for (final projected in visible) {
      final point = Offset(
        projected.viewportPoint.x,
        projected.viewportPoint.y,
      );
      if (markerBounds.contains(point)) _name(canvas, point, projected);
    }
    for (final projected in visible) {
      final point = Offset(
        projected.viewportPoint.x,
        projected.viewportPoint.y,
      );
      if (!markerBounds.contains(point)) continue;
      _badge(
        canvas,
        point,
        filterKey: projected.marker.filterKey,
        selected: projected.marker.id == selectedMarker,
        highlighted: projected.linkedHighlighted || projected.raidHighlighted,
        dimmed: projected.dimmed,
      );
    }
    final player = maps.playerViewportPoint;
    if (player != null) {
      final point = Offset(player.x, player.y);
      final direction = maps.playerSceneDirection;
      canvas.save();
      canvas.translate(point.dx, point.dy);
      _fill.color = mapPlayerMarkerFill;
      canvas.drawCircle(Offset.zero, 6, _fill);
      if (direction != null) {
        canvas.rotate(math.atan2(direction.y, direction.x));
        final arrow = Path()
          ..moveTo(22, 0)
          ..lineTo(8, -6)
          ..lineTo(8, 6)
          ..close();
        canvas.drawPath(arrow, _fill);
      }
      canvas.restore();
    }
    if (showPins) {
      final searchTerms = mapSearchTerms(maps.search);
      for (final pin in pins) {
        final point = maps.projectPin(pin);
        if (point != null) {
          final matches =
              searchTerms.isEmpty ||
              searchTerms.any(pin.label.toLowerCase().contains);
          _badge(
            canvas,
            Offset(point.x, point.y),
            filterKey: 'CustomPins',
            selected: pin.id == selectedPin,
            highlighted: false,
            dimmed: !matches,
          );
        }
      }
    }
  }

  /// Draws the place names under every marker drawing.
  ///
  /// Labels keep a fixed screen size at any zoom. Each placed label is centred
  /// on its anchor and rotated clockwise about it. Search and selection never
  /// change them, and they take no hit testing or semantics.
  void _placeLabels(Canvas canvas, Size size) {
    final projected = maps.visiblePlaceLabels();
    if (projected.isEmpty) return;
    final fills = <TextPainter>[];
    final candidates = <PlaceLabelCandidate>[];
    for (final (index, item) in projected.indexed) {
      final text = _placeText(item.label, _placeFill);
      fills.add(text);
      candidates.add(
        PlaceLabelCandidate(
          x: item.viewportPoint.x,
          y: item.viewportPoint.y,
          width: text.width,
          height: text.height,
          rotationDegrees: item.label.rotation,
          size: item.label.size,
          packIndex: index,
          floorIds: item.label.floorIds.toSet(),
        ),
      );
    }
    final placed = placeLabels(
      candidates,
      PlaceLabelViewport(width: size.width, height: size.height),
      maps.selectedOverlayFloorIds,
    );
    // The halo is laid out for placed labels only; the fill is the measurement.
    for (final halo in [true, false]) {
      for (final index in placed) {
        final item = projected[index];
        final text = halo ? _placeText(item.label, _placeHalo) : fills[index];
        canvas.save();
        canvas.translate(item.viewportPoint.x, item.viewportPoint.y);
        canvas.rotate(item.label.rotation * math.pi / 180);
        text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
        canvas.restore();
        if (halo) text.dispose();
      }
    }
    for (final text in fills) {
      text.dispose();
    }
  }

  TextPainter _placeText(
    PreparedPlaceLabel label,
    TextStyle Function(double) style,
  ) => TextPainter(
    text: TextSpan(
      text: label.text,
      style: style(placeLabelFontSize(label.size)),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  TextStyle _placeFill(double fontSize) => TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    color: mapPlaceLabelColour.withValues(alpha: placeLabelOpacity),
  );

  TextStyle _placeHalo(double fontSize) => TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    foreground: Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _labelHaloWidth
      ..strokeJoin = StrokeJoin.round
      ..color = markerIcons.background.withValues(alpha: placeLabelOpacity),
  );

  bool _outlineShown(PreparedMarker marker) => outlineDrawn(
    marker.filterKey,
    hovered: marker.id == hoveredMarker,
    selected: marker.id == selectedMarker,
  );

  void _outline(Canvas canvas, ProjectedMapMarker projected) {
    if (projected.outline.isEmpty) return;
    final path = Path();
    for (var index = 0; index < projected.outline.length; index++) {
      final p = projected.outline[index];
      if (index == 0) {
        path.moveTo(p.x, p.y);
      } else {
        path.lineTo(p.x, p.y);
      }
    }
    path.close();
    final colour = projected.marker.id == selectedMarker
        ? mapSelectionColour
        : markerIcons.colourFor(projected.marker.filterKey);
    _fill.color = colour.withValues(alpha: projected.dimmed ? .035 : .16);
    canvas.drawPath(path, _fill);
    _edge.color = colour.withValues(
      alpha: projected.dimmed ? dimmedMarkerOpacity : 1,
    );
    canvas.drawPath(path, _edge);
  }

  /// Draws the name of an extract or transit right of its badge: a halo in the
  /// marker background colour, then the faction colour on top.
  void _name(Canvas canvas, Offset point, ProjectedMapMarker projected) {
    final marker = projected.marker;
    final faction = labelFactionFor(marker.filterKey);
    if (faction == null || marker.name.trim().isEmpty) return;
    final opacity = projected.dimmed ? dimmedMarkerOpacity : 1.0;
    const base = TextStyle(
      fontSize: _labelFontSize,
      fontWeight: FontWeight.w600,
    );
    final halo = markerIcons.background.withValues(alpha: opacity);
    final styles = [
      base.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _labelHaloWidth
          ..strokeJoin = StrokeJoin.round
          ..color = halo,
      ),
      base.copyWith(
        color: mapExtractLabelColour(faction).withValues(alpha: opacity),
      ),
    ];
    final start =
        point.dx + markerIcons.geometry.selectedDiameter / 2 + _labelGap;
    for (final style in styles) {
      final text = TextPainter(
        text: TextSpan(text: marker.name, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: _labelMaxWidth);
      text.paint(canvas, Offset(start, point.dy - text.height / 2));
      text.dispose();
    }
  }

  void _badge(
    Canvas canvas,
    Offset point, {
    required String filterKey,
    required bool selected,
    required bool highlighted,
    required bool dimmed,
  }) => paintMarkerBadge(
    canvas,
    point,
    markerIcons,
    filterKey: filterKey,
    selected: selected,
    highlighted: highlighted,
    dimmed: dimmed,
    paints: _badgePaints,
  );

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final bounds = Offset.zero & size;
    final targets = <CustomPainterSemantics>[];
    for (final marker in maps.visibleMarkers()) {
      var rect = Rect.fromCircle(
        center: Offset(marker.viewportPoint.x, marker.viewportPoint.y),
        radius: 22,
      );
      if (_outlineShown(marker.marker)) {
        for (final vertex in marker.outline) {
          rect = rect.expandToInclude(Rect.fromLTWH(vertex.x, vertex.y, 1, 1));
        }
      }
      if (!bounds.overlaps(rect)) continue;
      targets.add(
        CustomPainterSemantics(
          rect: rect.intersect(bounds),
          properties: SemanticsProperties(
            label:
                '${marker.marker.name}, ${markerCategoryLabel(marker.marker.filterKey)}',
            button: true,
            selected: marker.marker.id == selectedMarker,
            textDirection: TextDirection.ltr,
            onTap: () => selectMarker(marker.marker.id),
          ),
        ),
      );
    }
    if (showPins) {
      for (final pin in pins) {
        final point = maps.projectPin(pin);
        if (point == null) continue;
        final rect = Rect.fromCircle(
          center: Offset(point.x, point.y),
          radius: 22,
        );
        if (!bounds.overlaps(rect)) continue;
        targets.add(
          CustomPainterSemantics(
            rect: rect.intersect(bounds),
            properties: SemanticsProperties(
              label: '${pin.label}, saved pin',
              button: true,
              selected: pin.id == selectedPin,
              textDirection: TextDirection.ltr,
              onTap: () => selectPin(pin.id),
            ),
          ),
        );
      }
    }
    return targets;
  };

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
  @override
  bool shouldRebuildSemantics(covariant _MapPainter oldDelegate) => true;
}

/// One pressable row of the marker browser sheet: a title over a subtitle.
///
/// Takes its type and colours from the Ember theme, keeps at least
/// [EmberSize.row] of height (scaled with the text scaler) and is reachable
/// and activated from the keyboard like a button.
class MarkerBrowserRow extends StatelessWidget {
  /// Creates a row showing [title] over [subtitle] that calls [onTap] when
  /// pressed.
  const MarkerBrowserRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  /// The marker or pin name.
  final String title;

  /// The marker category, or `Saved pin`.
  final String subtitle;

  /// Called when the row is pressed or activated from the keyboard.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: EmberSize.row * scale),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EmberSpace.lg,
              vertical: EmberSpace.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: EmberType.body.copyWith(color: ember.ink)),
                Text(
                  subtitle,
                  style: EmberType.label.copyWith(color: ember.inkTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
