import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/app_services.dart';
import '../domain/catalog.dart';
import 'ember/theme_access.dart';

/// Item search in the shared header, with an anchored list of explicit picks.
///
/// Query and selection belong to the existing selection controller. The popup
/// owns only its visibility and keyboard highlight for this focus session.
class TopItemSearch extends StatefulWidget {
  /// Creates a search using the shell-owned [controller] and [focusNode].
  const TopItemSearch({
    super.key,
    required this.services,
    required this.controller,
    required this.focusNode,
    this.onPicked,
  });

  /// The existing catalog and selection owners.
  final AppServices services;

  /// The shell-owned query field controller.
  final TextEditingController controller;

  /// The shell-owned focus target used by Ctrl K.
  final FocusNode focusNode;

  /// Called after the player picks an item, and never for a change of the
  /// selection that did not come from this search.
  final VoidCallback? onPicked;

  @override
  State<TopItemSearch> createState() => _TopItemSearchState();
}

class _TopItemSearchState extends State<TopItemSearch> {
  static const _optionLimit = 50;
  final _portal = OverlayPortalController();
  final _anchor = LayerLink();
  final _scroll = ScrollController();
  CatalogSnapshot? _catalogSnapshot;
  GameMode? _catalogMode;
  int _active = 0;

  double _optionHeight(BuildContext context) =>
      56 *
      MediaQuery.textScalerOf(context).scale(1).clamp(1.0, double.infinity);

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_focusChanged);
    widget.services.catalog.addListener(_catalogChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_focusChanged);
    widget.services.catalog.removeListener(_catalogChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!widget.focusNode.hasFocus) _hide();
  }

  void _catalogChanged() {
    final catalog = widget.services.catalog;
    if (_portal.isShowing &&
        (catalog.mode != _catalogMode ||
            catalog.snapshot != _catalogSnapshot)) {
      _hide();
    }
  }

  void _hide() {
    if (_portal.isShowing) _portal.hide();
  }

  void _changed(String value) {
    widget.services.selection.setQuery(value);
    _active = 0;
    _catalogMode = widget.services.catalog.mode;
    _catalogSnapshot = widget.services.catalog.snapshot;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (value.trim().isEmpty) {
      _hide();
    } else if (!_portal.isShowing) {
      _portal.show();
    }
    setState(() {});
  }

  void _select(CatalogItem item) {
    _hide();
    unawaited(widget.services.selection.selectManual(item));
    widget.onPicked?.call();
    widget.focusNode.unfocus();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        !_portal.isShowing) {
      return KeyEventResult.ignored;
    }
    final results = widget.services.selection.results;
    final count = results.length.clamp(0, _optionLimit);
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _hide();
      return KeyEventResult.handled;
    }
    if (count == 0) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        final delta = event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
        _active = (_active + delta).clamp(0, count - 1);
      });
      if (_scroll.hasClients) {
        final height = _optionHeight(context);
        final top = _active * height;
        final position = _scroll.position;
        final offset = top < position.pixels
            ? top
            : top + height > position.pixels + position.viewportDimension
            ? top + height - position.viewportDimension
            : position.pixels;
        _scroll.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _select(results[_active.clamp(0, count - 1)]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        final results = widget.services.selection.results;
        final count = results.length.clamp(0, _optionLimit);
        return Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _anchor,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            // Results belong to this editing interaction even though the
            // overlay paints them outside the field's render subtree.
            child: TextFieldTapRegion(
              child: SizedBox(
                key: const Key('top-search-results'),
                width: constraints.maxWidth,
                child: Material(
                  color: context.ember.raised,
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (count == 0)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('No matching items'),
                          )
                        else
                          Flexible(
                            child: ListView.builder(
                              controller: _scroll,
                              itemExtent: _optionHeight(context),
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: count,
                              itemBuilder: (context, index) => Tooltip(
                                message: results[index].name,
                                child: ListTile(
                                  dense: true,
                                  minTileHeight: _optionHeight(context),
                                  minVerticalPadding: 4,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  selected: index == _active,
                                  selectedColor: context.ember.accentText,
                                  selectedTileColor: context.ember.accentSoft,
                                  title: Text(
                                    results[index].name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => _select(results[index]),
                                ),
                              ),
                            ),
                          ),
                        if (results.length > _optionLimit)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              constraints.maxWidth < 250
                                  ? '50 shown\nRefine'
                                  : 'Showing 50 items. Refine your search.',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _anchor,
        child: Focus(
          onKeyEvent: _key,
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            onChanged: _changed,
            onSubmitted: (_) {
              final results = widget.services.selection.results;
              if (_portal.isShowing && results.isNotEmpty) {
                _select(
                  results[_active.clamp(
                    0,
                    (results.length - 1).clamp(0, _optionLimit - 1),
                  )],
                );
              }
            },
            decoration: const InputDecoration(
              hintText: 'Search items…',
              prefixIcon: Icon(Icons.search, size: 20),
              suffixText: 'Ctrl K',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
          ),
        ),
      ),
    ),
  );
}
