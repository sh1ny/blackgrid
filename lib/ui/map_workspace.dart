import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../application/app_services.dart';
import '../application/map_controller.dart';
import '../domain/map_coordinates.dart';
import '../domain/map_marker_query.dart';
import '../domain/settings.dart';
import '../maps/map_marker_icons.dart';
import '../maps/prepared_map.dart';
import 'pin_editor.dart';
import 'theme.dart';

/// Native artwork and screen-space targets share the controller's view geometry.
class MapWorkspace extends StatefulWidget {
  const MapWorkspace({super.key, required this.services});
  final AppServices services;
  @override
  State<MapWorkspace> createState() => _MapWorkspaceState();
}

class _MapWorkspaceState extends State<MapWorkspace> {
  String? _selectedMarker;
  int? _selectionGeneration;
  String? _selectedPin;
  String? _selectedPinMapId;
  final _focus = FocusNode(debugLabel: 'Native map workspace');
  MapController get maps => widget.services.maps;

  @override
  void dispose() {
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

  void _selectMarker(String? id) {
    _focus.requestFocus();
    maps.setSelectedMarker(id);
    setState(() {
      _selectedMarker = id;
      _selectionGeneration = maps.contentGeneration;
      _selectedPin = null;
      _selectedPinMapId = null;
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
    final marker = maps.hitTestMarker(point, radius: 22);
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
      _selectedMarker = pinId == null ? marker?.marker.id : null;
      _selectionGeneration = maps.contentGeneration;
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
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Visible map markers and pins'),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length + visiblePins.length,
                itemBuilder: (context, index) {
                  if (index < visible.length) {
                    final marker = visible[index].marker;
                    return ListTile(
                      title: Text(marker.name),
                      subtitle: Text(marker.filterKey),
                      onTap: () =>
                          Navigator.pop(context, 'marker:${marker.id}'),
                    );
                  }
                  final pin = visiblePins[index - visible.length.toInt()];
                  return ListTile(
                    title: Text(pin.label),
                    subtitle: const Text('Saved pin'),
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
      _selectedMarker = id.startsWith('marker:') ? id.substring(7) : null;
      _selectionGeneration = maps.contentGeneration;
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
        _selectedMarker = null;
        _selectedPin = null;
        _selectedPinMapId = null;
      });
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([maps, widget.services.settings]),
    builder: (context, _) {
      final map = maps.preparedMap;
      final visible = maps.visibleMarkers();
      PreparedMarker? selected;
      for (final marker in visible) {
        if (_selectionGeneration == maps.contentGeneration &&
            marker.marker.id == _selectedMarker) {
          selected = marker.marker;
        }
      }
      CustomPin? selectedPin;
      if (_selectedPinMapId == maps.selectedMapId &&
          widget.services.settings.settings.markerFilters['CustomPins'] !=
              false) {
        for (final pin in pins) {
          if (pin.id == _selectedPin) selectedPin = pin;
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: map == null ? null : maps.fit,
                icon: const Icon(Icons.fit_screen, size: 18),
                label: const Text('Fit map'),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: map == null
                    ? null
                    : () => maps.zoomAt(_viewportCenter, 1.25),
                icon: const Icon(Icons.add),
              ),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: map == null
                    ? null
                    : () => maps.zoomAt(_viewportCenter, .8),
                icon: const Icon(Icons.remove),
              ),
              OutlinedButton.icon(
                onPressed:
                    visible.isEmpty &&
                        !widget.services.settings.pins.any(_isVisiblePin)
                    ? null
                    : _browse,
                icon: const Icon(Icons.list, size: 18),
                label: Text('Markers (${visible.length})'),
              ),
              OutlinedButton.icon(
                onPressed: maps.playerPosition == null
                    ? null
                    : maps.centerOnPlayer,
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text('Center on player'),
              ),
              OutlinedButton.icon(
                onPressed: map == null || widget.services.settings.busy
                    ? null
                    : () => _createPinAt(_viewportCenter),
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Pin at view center'),
              ),
              if (maps.automaticFloorSupported)
                FilterChip(
                  label: const Text('Automatic floor'),
                  selected: maps.automaticFloorFollowing,
                  onSelected: maps.setAutomaticFloorFollowing,
                ),
              if (map != null)
                for (final floor in map.floorPolicy.floors)
                  FilterChip(
                    label: Text(floor.label),
                    selected:
                        maps.floorSelection?.isLayerVisible(floor.id) ?? false,
                    onSelected: (_) => maps.toggleFloor(floor.id),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                // Tile demand follows layout. Scheduling avoids notification in build.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) maps.updateViewport(size);
                });
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: GridColors.inset,
                    border: Border.all(color: GridColors.quietBorder),
                  ),
                  child: ClipRect(
                    child: Focus(
                      focusNode: _focus,
                      onKeyEvent: (_, event) => _key(event),
                      child: Listener(
                        onPointerSignal: (event) {
                          if (event is PointerScrollEvent && map != null) {
                            GestureBinding.instance.pointerSignalResolver
                                .register(event, (_) {
                                  maps.zoomAt(
                                    ViewportPoint(
                                      event.localPosition.dx,
                                      event.localPosition.dy,
                                    ),
                                    event.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15,
                                  );
                                });
                          }
                        },
                        child: GestureDetector(
                          key: const Key('native-map-viewport'),
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: map == null
                              ? null
                              : (event) =>
                                    maps.panBy(event.delta.dx, event.delta.dy),
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
                                  selectedPin: selectedPin?.id,
                                  selectMarker: _selectMarker,
                                  selectPin: (id) {
                                    _focus.requestFocus();
                                    maps.setSelectedMarker(null);
                                    setState(() {
                                      _selectedPin = id;
                                      _selectedPinMapId = maps.selectedMapId;
                                      _selectedMarker = null;
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
                                      style: const TextStyle(
                                        color: GridColors.muted,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (selected != null)
            _MarkerDetails(
              marker: selected,
              metadata: maps.metadataFor(selected),
              onClose: () => _selectMarker(null),
            ),
          if (selectedPin != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${selectedPin.label} · ${selectedPin.frame} r${selectedPin.frameRevision}',
                    ),
                  ),
                  TextButton(
                    onPressed: widget.services.settings.busy
                        ? null
                        : () => showPinEditor(
                            context,
                            widget.services,
                            pin: selectedPin,
                          ),
                    child: const Text('Edit pin'),
                  ),
                  IconButton(
                    tooltip: 'Remove selected pin',
                    onPressed: widget.services.settings.busy
                        ? null
                        : () => _removePin(selectedPin!),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  IconButton(
                    tooltip: 'Close pin details',
                    onPressed: () => setState(() {
                      _selectedPin = null;
                      _selectedPinMapId = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          if (widget.services.settings.busy)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Saving map preferences or pins…'),
            ),
          const SizedBox(height: 6),
          Text(
            map == null
                ? 'No artwork loaded · saved files only; no live tracking'
                : 'Drag/arrows pan · wheel/+/- zoom · Home fits · C centers player · Enter browses · N/right-click adds pin · Delete removes selected pin · ${map.attribution['author'] ?? map.name}',
            style: const TextStyle(color: GridColors.muted, fontSize: 12),
          ),
        ],
      );
    },
  );
}

class _MarkerDetails extends StatelessWidget {
  const _MarkerDetails({
    required this.marker,
    required this.metadata,
    required this.onClose,
  });
  final PreparedMarker marker;
  final MapMarkerMetadata metadata;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                marker.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Close marker details',
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Text(
          '${marker.category} / ${marker.filterKey} · X ${marker.position.x} · Z ${marker.position.z} · height ${marker.position.height ?? 'unknown'}',
        ),
        if (metadata.questNames.isNotEmpty)
          Text('Quest: ${metadata.questNames.join(', ')}'),
        if (metadata.traders.isNotEmpty)
          Text('Trader: ${metadata.traders.join(', ')}'),
        for (final link in metadata.questLinks) SelectableText(link),
        SizedBox(
          height: 80,
          child: SingleChildScrollView(
            child: SelectableText(
              metadata.fields.entries
                  .map((entry) => '${entry.key}: ${entry.value}')
                  .join(' · '),
            ),
          ),
        ),
      ],
    ),
  );
}

class _MapPainter extends CustomPainter {
  _MapPainter(
    this.maps,
    this.markerIcons,
    this.pins, {
    required this.showPins,
    required this.selectedMarker,
    required this.selectedPin,
    required this.selectMarker,
    required this.selectPin,
  }) : super(repaint: Listenable.merge([maps, markerIcons]));
  final MapController maps;
  final MapMarkerIcons markerIcons;
  final List<CustomPin> pins;
  final bool showPins;
  final String? selectedMarker;
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
    for (final projected in maps.visibleMarkers()) {
      final point = Offset(
        projected.viewportPoint.x,
        projected.viewportPoint.y,
      );
      final marker = projected.marker;
      if (projected.outline.isNotEmpty) {
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
        _fill.color = Colors.red.withValues(
          alpha: projected.dimmed ? .035 : .16,
        );
        canvas.drawPath(path, _fill);
        _edge.color = Colors.redAccent.withValues(
          alpha: projected.dimmed ? .22 : 1,
        );
        canvas.drawPath(path, _edge);
      }
      if (!markerBounds.contains(point)) continue;
      _badge(
        canvas,
        point,
        filterKey: marker.filterKey,
        selected: marker.id == selectedMarker,
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
      _fill.color = Colors.white;
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
      for (final vertex in marker.outline) {
        rect = rect.expandToInclude(Rect.fromLTWH(vertex.x, vertex.y, 1, 1));
      }
      if (!bounds.overlaps(rect)) continue;
      targets.add(
        CustomPainterSemantics(
          rect: rect.intersect(bounds),
          properties: SemanticsProperties(
            label: '${marker.marker.name}, ${marker.marker.filterKey}',
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
