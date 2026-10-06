import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../application/app_services.dart';
import '../application/map_controller.dart';
import '../domain/map_coordinates.dart';
import '../domain/settings.dart';
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
    setState(() {
      _selectedPin = pinId;
      _selectedPinMapId = pinId == null ? null : maps.selectedMapId;
      _selectedMarker = pinId == null ? marker?.marker.id : null;
    });
  }

  Future<void> _browse() async {
    final visible = maps.visibleMarkers();
    final visiblePins = widget.services.settings.pins
        .where(_isVisiblePin)
        .toList();
    final mapId = maps.selectedMapId;
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
    if (!mounted || mapId != maps.selectedMapId || id == null) return;
    setState(() {
      _selectedPin = id.startsWith('pin:') ? id.substring(4) : null;
      _selectedPinMapId = _selectedPin == null ? null : mapId;
      _selectedMarker = id.startsWith('marker:') ? id.substring(7) : null;
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
    } else if (key == LogicalKeyboardKey.escape) {
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
    listenable: maps,
    builder: (context, _) {
      final map = maps.preparedMap;
      final visible = maps.visibleMarkers();
      PreparedMarker? selected;
      for (final marker in visible) {
        if (marker.marker.id == _selectedMarker) selected = marker.marker;
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
                    : () => maps.zoomAt(ViewportPoint(0, 0), 1.25),
                icon: const Icon(Icons.add),
              ),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: map == null
                    ? null
                    : () => maps.zoomAt(ViewportPoint(0, 0), .8),
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
                                  final coordinates = maps.pinAt(
                                    ViewportPoint(
                                      event.localPosition.dx,
                                      event.localPosition.dy,
                                    ),
                                  );
                                  if (coordinates != null) {
                                    showPinEditor(
                                      context,
                                      widget.services,
                                      coordinates: coordinates,
                                    );
                                  }
                                },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CustomPaint(
                                painter: _MapPainter(
                                  maps,
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
                                  selectMarker: (id) => setState(() {
                                    _selectedMarker = id;
                                    _selectedPin = null;
                                    _selectedPinMapId = null;
                                  }),
                                  selectPin: (id) => setState(() {
                                    _selectedPin = id;
                                    _selectedPinMapId = maps.selectedMapId;
                                    _selectedMarker = null;
                                  }),
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
              onClose: () => setState(() => _selectedMarker = null),
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
                    onPressed: () => showPinEditor(
                      context,
                      widget.services,
                      pin: selectedPin,
                    ),
                    child: const Text('Edit pin'),
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
          const SizedBox(height: 6),
          Text(
            map == null
                ? 'No game listener or live tracking'
                : 'Drag to pan · wheel zooms at cursor · right-click adds a pin · ${map.attribution['author'] ?? map.name}',
            style: const TextStyle(color: GridColors.muted, fontSize: 12),
          ),
        ],
      );
    },
  );
}

class _MarkerDetails extends StatelessWidget {
  const _MarkerDetails({required this.marker, required this.onClose});
  final PreparedMarker marker;
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
          '${marker.filterKey} · X ${marker.position.x} · Z ${marker.position.z} · height ${marker.position.height ?? 'unknown'}',
        ),
        SizedBox(
          height: 80,
          child: SingleChildScrollView(
            child: SelectableText(
              marker.details.entries
                  .where(
                    (entry) =>
                        entry.key != 'position' && entry.key != 'outline',
                  )
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
    this.pins, {
    required this.showPins,
    required this.selectedMarker,
    required this.selectedPin,
    required this.selectMarker,
    required this.selectPin,
  }) : super(repaint: maps);
  final MapController maps;
  final List<CustomPin> pins;
  final bool showPins;
  final String? selectedMarker;
  final String? selectedPin;
  final ValueChanged<String> selectMarker;
  final ValueChanged<String> selectPin;
  final _fill = Paint();
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
        _fill.color = Colors.red.withValues(alpha: .16);
        canvas.drawPath(path, _fill);
        _edge.color = Colors.redAccent;
        canvas.drawPath(path, _edge);
      }
      if (!markerBounds.contains(point)) continue;
      _glyph(
        canvas,
        point,
        marker.filterKey.contains('Extract')
            ? GridColors.green
            : marker.category == 'hazards'
            ? Colors.redAccent
            : GridColors.gold,
        marker.id == selectedMarker,
      );
    }
    if (showPins) {
      for (final pin in pins) {
        final point = maps.projectPin(pin);
        if (point != null) {
          _glyph(
            canvas,
            Offset(point.x, point.y),
            Colors.lightBlueAccent,
            pin.id == selectedPin,
          );
        }
      }
    }
  }

  void _glyph(Canvas canvas, Offset point, Color color, bool selected) {
    _fill.color = GridColors.inset;
    canvas.drawCircle(point, selected ? 12 : 9, _fill);
    _edge.color = color;
    canvas.drawCircle(point, selected ? 12 : 9, _edge);
    _fill.color = color;
    canvas.drawCircle(point, 3, _fill);
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final bounds = Offset.zero & size;
    final targets = <CustomPainterSemantics>[];
    for (final marker in maps.visibleMarkers()) {
      final rect = Rect.fromCircle(
        center: Offset(marker.viewportPoint.x, marker.viewportPoint.y),
        radius: 22,
      );
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
