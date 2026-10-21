import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../application/item_icon_cache.dart';

/// Key of the generic placeholder icon, for tests.
const genericItemIconKey = Key('item-icon-generic');

/// Key of the drawn icon image, for tests.
const readyItemIconKey = Key('item-icon-image');

/// Shows the icon of one item, or a generic icon when none is available.
///
/// The widget holds a lease from [cache] for [itemId] and [iconLink], and
/// releases it when the item changes, the widget is hidden or it goes away.
/// A hidden widget holds no lease, so it requests nothing. It never keeps
/// the previous item's image while a new item loads. Callers should also key
/// it by [itemId] so a new item always gets a new element.
class ItemIcon extends StatefulWidget {
  /// Creates an icon of [size] logical pixels for [itemId].
  ///
  /// [color] tints the generic icon only.
  const ItemIcon({
    super.key,
    required this.cache,
    required this.itemId,
    required this.iconLink,
    required this.size,
    this.color,
  });

  /// Where icons come from.
  final ItemIconCache cache;

  /// The item whose icon is shown.
  final String itemId;

  /// The icon's link, or null when the item has none.
  final String? iconLink;

  /// Width and height of the icon.
  final double size;

  /// The color of the generic icon.
  final Color? color;

  @override
  State<ItemIcon> createState() => _ItemIconState();
}

class _ItemIconState extends State<ItemIcon> {
  /// The held lease, or null while the icon is hidden, such as on a tab an
  /// [IndexedStack] does not show.
  ItemIconLease? _lease;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = Visibility.of(context);
    if (visible && _lease == null) {
      _acquire();
    } else if (!visible && _lease != null) {
      _release();
    }
  }

  @override
  void didUpdateWidget(ItemIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lease != null &&
        (oldWidget.itemId != widget.itemId ||
            oldWidget.iconLink != widget.iconLink ||
            !identical(oldWidget.cache, widget.cache))) {
      _release();
      _acquire();
    }
  }

  @override
  void dispose() {
    if (_lease != null) _release();
    super.dispose();
  }

  void _acquire() {
    _lease = widget.cache.acquire(widget.itemId, widget.iconLink)
      ..addListener(_onChanged);
  }

  void _release() {
    _lease!
      ..removeListener(_onChanged)
      ..release();
    _lease = null;
  }

  /// Rebuilds for a new view, after the frame if the change came mid-build.
  ///
  /// The cache publishes to every lease of an item from `acquire`, which
  /// another [ItemIcon] may call while it is being built.
  void _onChanged() {
    if (!mounted) return;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  Widget _generic() => Icon(
    Icons.inventory_2_outlined,
    key: genericItemIconKey,
    size: widget.size,
    color: widget.color,
  );

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox.square(
      dimension: size,
      child: switch (_lease?.value ?? const GenericItemIcon()) {
        GenericItemIcon() => _generic(),
        ReadyItemIcon(:final file) => Image.file(
          file,
          key: ValueKey(file.path),
          width: size,
          height: size,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          fit: BoxFit.contain,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => _generic(),
          frameBuilder: (_, child, frame, _) => frame == null
              ? _generic()
              : KeyedSubtree(key: readyItemIconKey, child: child),
        ),
      },
    );
  }
}
