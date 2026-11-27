import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/map_floors.dart';
import 'ember/ember_toggle_switch.dart';
import 'ember/ember_tokens.dart';

const _ink = EmberColors.dark;

/// The Map's floating deck list and compact floor stepper.
class MapFloorRail extends StatefulWidget {
  /// Binds the rail to the current floor state and workspace commands.
  const MapFloorRail({
    super.key,
    required this.selection,
    required this.playerFloor,
    required this.autoFollowing,
    required this.collapsed,
    required this.onActivate,
    required this.onStep,
    required this.onToggleAuto,
    required this.onCollapseChanged,
    required this.onFocusChanged,
    required this.onKeyEvent,
  });

  /// Bottom-to-top floor policy and visible layers.
  final MapFloorSelection selection;

  /// The sampled floor, independently of whether Auto is following it.
  final MapFloor? playerFloor;

  /// Whether this map is following the player's sampled floor.
  final bool autoFollowing;

  /// Whether the rail takes its one-line form.
  final bool collapsed;

  /// Activates a floor row under the current map's selection rules.
  final ValueChanged<String> onActivate;

  /// Steps one floor toward the top (`1`) or bottom (`-1`).
  final ValueChanged<int> onStep;

  /// Toggles automatic following.
  final VoidCallback onToggleAuto;

  /// Stores the collapse choice for the mounted workspace.
  final ValueChanged<bool> onCollapseChanged;

  /// Reports whether any rail control has focus.
  final ValueChanged<bool> onFocusChanged;

  /// Handles the shared Map floor shortcuts and Escape.
  final KeyEventResult Function(KeyEvent) onKeyEvent;

  @override
  MapFloorRailState createState() => MapFloorRailState();
}

/// Owns the rail's scroll position and the focus of its floor list.
class MapFloorRailState extends State<MapFloorRail> {
  final _scope = FocusNode(debugLabel: 'Floor rail');
  final _listFocus = FocusNode(debugLabel: 'Floor list');
  final _expand = FocusNode(debugLabel: 'Expand floor rail');
  final _scroll = ScrollController(keepScrollOffset: false);
  int? _focusedIndex;
  double _rowHeight = 28;
  double _dividerHeight = 18;
  double _cueHeight = 24;
  bool _revealPending = false;

  MapFloorPolicy get _policy => widget.selection.policy;
  int get _count => _policy.floors.length;
  int get _current => widget.selection.currentIndex;
  bool get _showDivider => !_policy.exclusive && _policy.baseIndex > 0;
  bool get _showAuto => _policy.supportsAutomaticHeight;
  double get _contentHeight =>
      _count * _rowHeight + (_showDivider ? _dividerHeight : 0);

  /// Whether keyboard focus is on any rail control.
  bool get hasFocus => _scope.hasFocus;

  /// Focuses Expand or the current floor without changing the selection.
  void focusCurrent() {
    if (widget.collapsed) {
      _expand.requestFocus();
    } else {
      _focusRow(_current);
      _listFocus.requestFocus();
    }
  }

  /// Keeps a step's destination visible without taking focus from other controls.
  void revealStep(int index) {
    if (_listFocus.hasFocus) {
      _focusRow(index);
    } else {
      _scheduleReveal();
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scale = MediaQuery.textScalerOf(context);
    _rowHeight = math.max(28, scale.scale(12.5) * 1.4 + 8);
    _dividerHeight = math.max(18, scale.scale(10) * 1.2 + 4);
    _cueHeight = math.max(24, scale.scale(11) * 1.2 + 6);
  }

  @override
  void didUpdateWidget(MapFloorRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_policy != oldWidget.selection.policy ||
        (oldWidget.collapsed && !widget.collapsed)) {
      _focusedIndex = _listFocus.hasFocus ? _current : null;
      _scheduleReveal();
    } else if (_focusedIndex == null &&
        oldWidget.selection.currentIndex != _current) {
      _scheduleReveal();
    }
  }

  @override
  void dispose() {
    _scope.dispose();
    _listFocus.dispose();
    _expand.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _collapse(bool collapsed) {
    if (_scope.hasFocus) {
      // A request made before attachment is fulfilled when the new view mounts.
      if (collapsed) {
        _expand.requestFocus();
      } else {
        _listFocus.requestFocus();
      }
    }
    widget.onCollapseChanged(collapsed);
  }

  double _rowTop(int index) =>
      (_count - 1 - index) * _rowHeight +
      (_showDivider && index < _policy.baseIndex ? _dividerHeight : 0);

  void _scheduleReveal() {
    if (_revealPending) return;
    _revealPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealPending = false;
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final top = _rowTop(_focusedIndex ?? _current);
      final offset = position.pixels;
      final pastBottom = top + _rowHeight - position.viewportDimension;
      final target = top < offset ? top : math.max(offset, pastBottom);
      if (target != offset) _scrollTo(target);
    });
  }

  void _scrollTo(double target) {
    final position = _scroll.position;
    _scroll.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  void _focusRow(int index) {
    setState(() => _focusedIndex = index);
    _scheduleReveal();
  }

  KeyEventResult _rowKey(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    final index = _focusedIndex ?? _current;
    final next = switch (key) {
      LogicalKeyboardKey.arrowUp => math.min(index + 1, _count - 1),
      LogicalKeyboardKey.arrowDown => math.max(index - 1, 0),
      LogicalKeyboardKey.home => _count - 1,
      LogicalKeyboardKey.end => 0,
      _ => null,
    };
    if (next != null) {
      if (next != index && (event is KeyDownEvent || event is KeyRepeatEvent)) {
        _focusRow(next);
        if (_policy.exclusive) widget.onActivate(_policy.floors[next].id);
      }
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) widget.onActivate(_policy.floors[index].id);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: WidgetOrderTraversalPolicy(),
    child: Focus(
      focusNode: _scope,
      skipTraversal: true,
      canRequestFocus: false,
      onFocusChange: widget.onFocusChanged,
      onKeyEvent: (_, event) => widget.onKeyEvent(event),
      child: Listener(
        key: const Key('map-floor-control'),
        behavior: HitTestBehavior.opaque,
        onPointerSignal: (event) {
          // Scrollable descendants register first. The rest of the surface
          // consumes wheel input without scrolling the artwork underneath.
          GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
        },
        child: Theme(
          data: Theme.of(context).copyWith(extensions: const [_ink]),
          child: Material(
            color: _ink.raised,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: _ink.hairlineStrong),
              borderRadius: const BorderRadius.all(
                Radius.circular(EmberRadius.l),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: widget.collapsed ? _compact() : _expanded(),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _compact() {
    final name = _policy.floors[_current].label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepButton(1),
        Flexible(
          child: Tooltip(
            message: 'Current floor: $name',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EmberType.uiHeading.copyWith(color: _ink.ink),
              ),
            ),
          ),
        ),
        _stepButton(-1),
        if (widget.autoFollowing) const _FloorTag('Auto'),
        _iconButton(
          Icons.unfold_more,
          'Expand floors',
          () => _collapse(false),
          focus: _expand,
        ),
      ],
    );
  }

  Widget _expanded() => SizedBox(
    width: 188,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: _meta('$_count ${_count == 1 ? 'floor' : 'floors'}'),
            ),
            _stepButton(1),
            _stepButton(-1),
            _iconButton(
              Icons.unfold_less,
              'Collapse floors',
              () => _collapse(true),
            ),
          ],
        ),
        if (_showAuto) _auto(),
        Flexible(child: _list()),
      ],
    ),
  );

  Widget _auto() {
    final status = !widget.autoFollowing
        ? 'Off'
        : widget.playerFloor == null
        ? 'Waiting for a position'
        : 'Following you';
    return Semantics(
      container: true,
      label: 'Auto',
      value: status,
      toggled: widget.autoFollowing,
      child: InkWell(
        onTap: widget.onToggleAuto,
        hoverColor: _ink.hover,
        focusColor: _ink.accentSoft,
        borderRadius: BorderRadius.circular(EmberRadius.m),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auto',
                        style: EmberType.control.copyWith(color: _ink.ink),
                      ),
                      _meta(status),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                EmberToggleSwitch(on: widget.autoFollowing),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list() => LayoutBuilder(
    builder: (context, constraints) {
      final hasOverflow = _contentHeight > constraints.maxHeight;
      final cueHeight =
          hasOverflow && constraints.maxHeight >= _rowHeight + 2 * _cueHeight
          ? _cueHeight
          : 0.0;
      final height = math.min(
        _contentHeight,
        constraints.maxHeight - 2 * cueHeight,
      );
      return Focus(
        focusNode: _listFocus,
        includeSemantics: false,
        onFocusChange: (focused) {
          setState(
            () => _focusedIndex = focused ? _focusedIndex ?? _current : null,
          );
          if (focused) _scheduleReveal();
        },
        onKeyEvent: _rowKey,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Floors',
          role: _policy.exclusive ? SemanticsRole.radioGroup : null,
          child: ListenableBuilder(
            listenable: _scroll,
            child: SizedBox(
              height: height,
              child: ListView.builder(
                key: const Key('map-floor-list'),
                controller: _scroll,
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                itemCount: _count + (_showDivider ? 1 : 0),
                itemExtentBuilder: (slot, _) =>
                    _isDivider(slot) ? _dividerHeight : _rowHeight,
                itemBuilder: (_, slot) {
                  if (_isDivider(slot)) return const _BelowGround();
                  final index =
                      _count -
                      1 -
                      slot +
                      (_showDivider && slot > _count - _policy.baseIndex
                          ? 1
                          : 0);
                  return _floorRow(index);
                },
              ),
            ),
            builder: (context, child) {
              final offset = _scroll.hasClients
                  ? _scroll.offset
                        .clamp(0.0, math.max(0.0, _contentHeight - height))
                        .toDouble()
                  : 0.0;
              final above = _clippedFloors(offset, fromTop: true);
              final below = _clippedFloors(
                _contentHeight - height - offset,
                fromTop: false,
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cueHeight > 0) _cue(above, true, cueHeight),
                  Stack(
                    children: [
                      child!,
                      if (above > 0) _fade(Alignment.topCenter),
                      if (below > 0) _fade(Alignment.bottomCenter),
                    ],
                  ),
                  if (cueHeight > 0) _cue(below, false, cueHeight),
                ],
              );
            },
          ),
        ),
      );
    },
  );

  bool _isDivider(int slot) =>
      _showDivider && slot == _count - _policy.baseIndex;

  int _clippedFloors(double extent, {required bool fromTop}) {
    final clipped = extent - precisionErrorTolerance;
    if (clipped <= 0) return 0;
    final beforeDivider = fromTop
        ? _count - _policy.baseIndex
        : _policy.baseIndex;
    final toDivider = beforeDivider * _rowHeight;
    if (_showDivider && clipped > toDivider) {
      return beforeDivider +
          (math.max(0.0, clipped - toDivider - _dividerHeight) / _rowHeight)
              .ceil();
    }
    return (clipped / _rowHeight).ceil();
  }

  Widget _cue(int count, bool above, double height) => SizedBox(
    height: height,
    width: double.infinity,
    child: count == 0
        ? null
        : InkWell(
            onTap: () => _scrollTo(
              _scroll.offset +
                  _scroll.position.viewportDimension * (above ? -.8 : .8),
            ),
            hoverColor: _ink.hover,
            focusColor: _ink.accentSoft,
            borderRadius: BorderRadius.circular(EmberRadius.s),
            child: Center(
              child: _meta('$count more ${above ? 'above' : 'below'}'),
            ),
          ),
  );

  Widget _fade(Alignment edge) => Positioned.fill(
    child: IgnorePointer(
      child: Align(
        alignment: edge,
        child: Container(
          height: 10,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: edge,
              end: -edge,
              colors: [_ink.raised, _ink.raised.withAlpha(0)],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _floorRow(int index) {
    final floor = _policy.floors[index];
    final base = !_policy.exclusive && index == _policy.baseIndex;
    final current = index == _current;
    final visible = widget.selection.isLayerVisible(floor.id);
    final player = floor.id == widget.playerFloor?.id;
    final focused = _listFocus.hasFocus && index == (_focusedIndex ?? _current);
    final label =
        '${floor.label}${base ? ', base, always drawn' : ''}${player ? ', You' : ''}';
    void activate() {
      _focusRow(index);
      _listFocus.requestFocus();
      widget.onActivate(floor.id);
    }

    return Semantics(
      key: ValueKey('map-floor-${floor.id}'),
      container: true,
      excludeSemantics: true,
      label: label,
      checked: _policy.exclusive ? visible : null,
      inMutuallyExclusiveGroup: _policy.exclusive ? true : null,
      toggled: _policy.exclusive ? null : visible,
      focusable: true,
      focused: focused,
      onTap: activate,
      child: Tooltip(
        message: floor.label,
        excludeFromSemantics: true,
        child: Material(
          color: current ? _ink.segmentOn : Colors.transparent,
          borderRadius: BorderRadius.circular(EmberRadius.m),
          child: InkWell(
            canRequestFocus: false,
            onTap: activate,
            hoverColor: _ink.hover,
            borderRadius: BorderRadius.circular(EmberRadius.m),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: focused ? Border.all(color: _ink.focus) : null,
                borderRadius: BorderRadius.circular(EmberRadius.m),
              ),
              child: Row(
                children: [
                  if (current)
                    Container(
                      width: 3,
                      height: _rowHeight - 8,
                      color: _ink.inkSecondary,
                    )
                  else
                    const SizedBox(width: 3),
                  SizedBox(
                    width: 23,
                    child: visible
                        ? Icon(Icons.check, size: 14, color: _ink.ink)
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      floor.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EmberType.control.copyWith(
                        color: visible ? _ink.ink : _ink.inkSecondary,
                        fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (base)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: _meta('base'),
                    ),
                  if (player)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: _FloorTag('You'),
                    ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepButton(int by) {
    final up = by > 0;
    return _iconButton(
      up ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
      up ? 'Floor up' : 'Floor down',
      _current + by >= 0 && _current + by < _count
          ? () => widget.onStep(by)
          : null,
      key: ValueKey('map-floor-step-${up ? 'up' : 'down'}'),
    );
  }
}

Widget _iconButton(
  IconData icon,
  String label,
  VoidCallback? onPressed, {
  Key? key,
  FocusNode? focus,
}) => IconButton(
  key: key,
  tooltip: label,
  focusNode: focus,
  onPressed: onPressed,
  icon: Icon(icon, size: 18),
  style: ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? _ink.hairlineStrong
          : _ink.ink,
    ),
    overlayColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.focused) ? _ink.accentSoft : _ink.hover,
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: _ink.focus)
          : BorderSide.none,
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(EmberRadius.s)),
      ),
    ),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    fixedSize: const WidgetStatePropertyAll(Size.square(26)),
    minimumSize: const WidgetStatePropertyAll(Size.square(26)),
  ),
);

Widget _meta(String label) => Text(
  label,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: EmberType.label.copyWith(color: _ink.inkSecondary),
);

class _FloorTag extends StatelessWidget {
  const _FloorTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: _ink.hairlineStrong),
      borderRadius: BorderRadius.circular(EmberRadius.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: _meta(label),
    ),
  );
}

class _BelowGround extends StatelessWidget {
  const _BelowGround();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        const Expanded(child: CustomPaint(painter: _DashLine())),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _meta('Below ground'),
        ),
        const Expanded(child: CustomPaint(painter: _DashLine())),
      ],
    ),
  );
}

class _DashLine extends CustomPainter {
  const _DashLine();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _ink.hairlineStrong;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(math.min(x + 3, size.width), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashLine oldDelegate) => false;
}

/// Previews a long exclusive stack without an app session or prepared pack.
@Preview(name: 'Floor deck rail', group: 'Map', size: Size(300, 380))
Widget floorRailPreview() {
  final decks = [
    for (var i = 1; i <= 16; i++)
      MapFloor(
        id: 'deck-$i',
        label: 'Deck $i',
        extents: [FloorExtent(HeightBand(i.toDouble(), i + .5))],
      ),
  ];
  final policy = MapFloorPolicy(
    mapId: 'preview',
    baseId: 'deck-7',
    floors: decks,
    exclusive: true,
  );
  var selection = policy.reset();
  var automatic = true;
  var collapsed = false;
  return Align(
    alignment: Alignment.topLeft,
    child: StatefulBuilder(
      builder: (context, setState) => MapFloorRail(
        selection: selection,
        playerFloor: policy.base,
        autoFollowing: automatic,
        collapsed: collapsed,
        onActivate: (id) => setState(() {
          automatic = false;
          selection = selection.selectOnly(id);
        }),
        onStep: (by) => setState(() {
          automatic = false;
          selection = selection.selectOnly(
            decks[selection.currentIndex + by].id,
          );
        }),
        onToggleAuto: () => setState(() {
          automatic = !automatic;
          if (automatic) selection = selection.selectOnly(policy.base.id);
        }),
        onCollapseChanged: (value) => setState(() => collapsed = value),
        onFocusChanged: (_) {},
        onKeyEvent: (_) => KeyEventResult.ignored,
      ),
    ),
  );
}
