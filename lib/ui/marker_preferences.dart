import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../domain/marker_categories.dart';
import '../maps/map_marker_icons.dart';
import 'theme.dart';

const _tileWidth = 88.0;
const _tileHeight = 76.0;
const _badgeSize = 24.0;

/// The marker categories of the current map as a grid of icon tiles.
///
/// Each tile draws the category's map badge above its player-facing label.
/// Clicking a tile shows or hides the category through
/// `services.settings.setMarker`, and a hidden tile is dimmed and loses its
/// check mark. Tiles ignore clicks while settings are being saved.
class MarkerPreferencesGrid extends StatelessWidget {
  /// Creates the grid for [keys], in the order given.
  ///
  /// [scale] multiplies the tile size, so labels keep their room at larger
  /// text sizes.
  const MarkerPreferencesGrid({
    super.key,
    required this.services,
    required this.keys,
    this.scale = 1,
  });

  /// The services whose settings and marker icons the tiles use.
  final AppServices services;

  /// The category keys to show, one tile each.
  final List<String> keys;

  /// The factor applied to the tile width and height.
  final double scale;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: services.settings,
    builder: (context, _) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final key in keys)
          _MarkerTile(
            key: ValueKey('marker-tile-$key'),
            filterKey: key,
            icons: services.markerIcons,
            scale: scale,
            shown: services.settings.settings.markerFilters[key] ?? true,
            onToggle: services.settings.busy
                ? null
                : () {
                    final shown =
                        services.settings.settings.markerFilters[key] ?? true;
                    services.settings.setMarker(key, !shown);
                  },
          ),
      ],
    ),
  );
}

class _MarkerTile extends StatelessWidget {
  const _MarkerTile({
    super.key,
    required this.filterKey,
    required this.icons,
    required this.scale,
    required this.shown,
    required this.onToggle,
  });

  final String filterKey;
  final MapMarkerIcons icons;
  final double scale;
  final bool shown;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final label = markerCategoryLabel(filterKey);
    return Semantics(
      toggled: shown,
      label: label,
      button: true,
      enabled: onToggle != null,
      onTap: onToggle,
      excludeSemantics: true,
      child: SizedBox(
        width: _tileWidth * scale,
        height: _tileHeight * scale,
        child: Material(
          color: GridColors.inset,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: shown ? GridColors.border : GridColors.quietBorder,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomPaint(
                        size: const Size.square(_badgeSize),
                        painter: _BadgePainter(
                          icons: icons,
                          filterKey: filterKey,
                          shown: shown,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.15,
                          color: shown ? GridColors.text : GridColors.muted,
                        ),
                      ),
                    ],
                  ),
                  if (shown)
                    const Positioned(
                      top: -4,
                      right: -2,
                      child: Icon(
                        Icons.check,
                        size: 14,
                        color: GridColors.green,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the unselected, undimmed map badge of one category, dimmed when the
/// category is hidden.
class _BadgePainter extends CustomPainter {
  _BadgePainter({
    required this.icons,
    required this.filterKey,
    required this.shown,
  }) : super(repaint: icons);

  final MapMarkerIcons icons;
  final String filterKey;
  final bool shown;

  @override
  void paint(Canvas canvas, Size size) => paintMarkerBadge(
    canvas,
    size.center(Offset.zero),
    icons,
    filterKey: filterKey,
    selected: false,
    highlighted: false,
    dimmed: !shown,
  );

  // The icons notify once, when loading ends, through `repaint`; a toggle
  // builds a new painter.
  @override
  bool shouldRepaint(_BadgePainter old) =>
      old.filterKey != filterKey || old.shown != shown || old.icons != icons;
}
