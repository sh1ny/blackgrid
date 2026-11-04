import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';

import '../maps/marker_presentation.dart';

/// Displays one selected marker summary in a measured, viewport-clamped bubble.
class MarkerPopup extends StatelessWidget {
  /// Creates a popup for the selected marker.
  const MarkerPopup({
    super.key,
    required this.presentation,
    required this.anchor,
    required this.onClose,
  });

  /// The prepared, player-facing summary to display.
  final MarkerPresentation presentation;

  /// The selected badge position in the popup's viewport coordinates.
  final Offset anchor;

  /// Clears the selected marker and returns focus to the map.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.hasBoundedWidth ||
          !constraints.hasBoundedHeight ||
          constraints.maxWidth <= 0 ||
          constraints.maxHeight <= 0) {
        return const SizedBox.shrink();
      }
      final inset = math
          .min(
            _MarkerPopupLayoutDelegate._edgeInset,
            math.min(constraints.maxWidth, constraints.maxHeight) / 2,
          )
          .toDouble();
      final availableWidth = constraints.maxWidth - inset * 2;
      final availableHeight = constraints.maxHeight - inset * 2;
      final compact = availableHeight < 104 || availableWidth < 180;
      final padding = compact ? 4.0 : 8.0;
      final closeExtent = compact ? 36.0 : 48.0;
      final theme = Theme.of(context);
      final titleStyle = DefaultTextStyle.of(context).style.merge(
        compact ? theme.textTheme.titleSmall : theme.textTheme.titleMedium,
      );
      final cardWidth = math
          .min(_MarkerPopupLayoutDelegate._maxWidth, availableWidth)
          .toDouble();
      final titleWidth = math
          .max(0, cardWidth - padding * 2 - closeExtent)
          .toDouble();
      final titlePainter = TextPainter(
        text: TextSpan(text: presentation.title, style: titleStyle),
        maxLines: 1,
        ellipsis: '…',
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: titleWidth);
      final minimumCardHeight =
          math.max(closeExtent, titlePainter.height) + padding * 2;
      titlePainter.dispose();
      if (availableWidth < closeExtent + padding * 2 ||
          availableHeight < minimumCardHeight) {
        return const SizedBox.shrink();
      }
      final layout = _MarkerPopupLayoutDelegate(
        anchor,
        minimumCardHeight: minimumCardHeight,
      );
      return Focus(
        onKeyEvent: (_, event) => _handleKey(event),
        child: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          },
          child: CustomMultiChildLayout(
            delegate: layout,
            children: [
              LayoutId(
                id: _tetherLayoutId,
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const ValueKey('marker-popup-tether'),
                    painter: _MarkerPopupTetherPainter(layout),
                  ),
                ),
              ),
              LayoutId(
                id: _popupLayoutId,
                child: Listener(
                  onPointerSignal: (event) {
                    GestureBinding.instance.pointerSignalResolver.register(
                      event,
                      (_) {},
                    );
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    onSecondaryTapUp: (_) {},
                    child: _PopupCard(
                      presentation: presentation,
                      onClose: onClose,
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

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      onClose();
      return KeyEventResult.handled;
    }
    if (const [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.add,
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.numpadAdd,
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.numpadSubtract,
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyN,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.delete,
    ].contains(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

class _PopupCard extends StatelessWidget {
  const _PopupCard({required this.presentation, required this.onClose});

  final MarkerPresentation presentation;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('marker-popup'),
      elevation: 8,
      color: colors.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxHeight < 104 || constraints.maxWidth < 180;
          final padding = compact ? 4.0 : 8.0;
          final closeExtent = compact ? 36.0 : 48.0;
          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        presentation.title,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: compact
                            ? Theme.of(context).textTheme.titleSmall
                            : Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Semantics(
                      label: 'Close marker details',
                      button: true,
                      onTap: onClose,
                      excludeSemantics: true,
                      child: IconButton(
                        tooltip: 'Close marker details',
                        constraints: BoxConstraints.tightFor(
                          width: closeExtent,
                          height: closeExtent,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: compact
                            ? VisualDensity.compact
                            : VisualDensity.standard,
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('marker-popup-scroll'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            presentation.categoryLabel,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        for (final fact in presentation.facts)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(fact),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

const _tetherLayoutId = 'tether';
const _popupLayoutId = 'popup';

class _MarkerPopupLayoutDelegate extends MultiChildLayoutDelegate {
  _MarkerPopupLayoutDelegate(this.anchor, {required this.minimumCardHeight});

  final Offset anchor;
  final double minimumCardHeight;
  Rect? popupRect;

  static const _gap = 10.0;
  static const _edgeInset = 8.0;
  static const _maxWidth = 360.0;
  static const _maxHeight = 480.0;

  @override
  Size getSize(BoxConstraints constraints) => constraints.constrain(
    constraints.hasBoundedWidth && constraints.hasBoundedHeight
        ? constraints.biggest
        : Size.zero,
  );

  @override
  void performLayout(Size size) {
    final margin = math
        .min(_edgeInset, math.min(size.width, size.height) / 2)
        .toDouble();
    final maxWidth = math
        .min(_maxWidth, math.max(0, size.width - margin * 2))
        .toDouble();
    final viewportMaxHeight = math
        .min(_maxHeight, math.max(0, size.height - margin * 2))
        .toDouble();
    final availableAbove = anchor.dy - _gap - margin;
    final availableBelow = size.height - margin - anchor.dy - _gap;
    final availableOnBestSide = math.max(
      0,
      math.max(availableAbove, availableBelow),
    );
    final maxHeight = availableOnBestSide >= minimumCardHeight
        ? math.min(viewportMaxHeight, availableOnBestSide).toDouble()
        : viewportMaxHeight;
    final popupSize = layoutChild(
      _popupLayoutId,
      BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
    );
    final above = anchor.dy - _gap - popupSize.height;
    final below = anchor.dy + _gap;
    final preferredTop = above >= margin ? above : below;
    final left = (anchor.dx - popupSize.width / 2)
        .clamp(margin, math.max(margin, size.width - margin - popupSize.width))
        .toDouble();
    final top = preferredTop
        .clamp(
          margin,
          math.max(margin, size.height - margin - popupSize.height),
        )
        .toDouble();
    popupRect = Rect.fromLTWH(left, top, popupSize.width, popupSize.height);
    positionChild(_popupLayoutId, popupRect!.topLeft);
    layoutChild(_tetherLayoutId, BoxConstraints.tight(size));
    positionChild(_tetherLayoutId, Offset.zero);
  }

  @override
  bool shouldRelayout(covariant _MarkerPopupLayoutDelegate oldDelegate) =>
      anchor != oldDelegate.anchor ||
      minimumCardHeight != oldDelegate.minimumCardHeight;
}

class _MarkerPopupTetherPainter extends CustomPainter {
  const _MarkerPopupTetherPainter(this.layout);

  final _MarkerPopupLayoutDelegate layout;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = layout.popupRect;
    if (rect == null || rect.contains(anchor)) return;
    final end = Offset(
      anchor.dx.clamp(rect.left, rect.right).toDouble(),
      anchor.dy.clamp(rect.top, rect.bottom).toDouble(),
    );
    final paint = Paint()
      ..color = const Color(0xffdcc05a)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5;
    canvas.drawLine(anchor, end, paint);
  }

  Offset get anchor => layout.anchor;

  @override
  bool shouldRepaint(covariant _MarkerPopupTetherPainter oldDelegate) =>
      !identical(layout, oldDelegate.layout);
}

/// Builds an isolated preview with a synthetic marker summary.

@Preview(name: 'Marker popup', group: 'Map', size: Size(420, 320))
Widget markerPopupPreview() => Center(
  child: SizedBox(
    width: 420,
    height: 320,
    child: MarkerPopup(
      presentation: MarkerPresentation(
        title: 'Marked supply crate',
        categoryLabel: 'Containers',
        facts: const ['Common supplies.'],
      ),
      anchor: const Offset(210, 160),
      onClose: () {},
    ),
  ),
);
