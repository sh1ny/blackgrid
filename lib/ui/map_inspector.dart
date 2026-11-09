import 'dart:async';

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../domain/map_coordinates.dart';
import '../domain/settings.dart';
import '../maps/map_marker_icons.dart';
import 'ember/ember_tokens.dart';
import 'ember/theme_access.dart';
import 'item_decision_card.dart';
import 'labels.dart';
import 'marker_preferences.dart';
import 'panels.dart';
import 'pin_editor.dart';

/// The working lists of the Map area, shown in the inspector.
///
/// Three sections stack: the extracts this raid's screenshot matched, the
/// marker rows with their filters, and the pins of the current map. Item
/// details stay on Scanner.
class MapInspector extends StatelessWidget {
  /// Creates the inspector for the map `services.maps` shows.
  ///
  /// [clock] supplies the time the screenshot age is measured against; tests
  /// inject a controlled one.
  const MapInspector({super.key, required this.services, this.clock});

  /// The services whose map, session and settings the sections use.
  final AppServices services;

  /// The current time, or `null` for [DateTime.now].
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('map-inspector'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GridPanel(
        title: 'This raid',
        icon: Icons.flag_outlined,
        fitContent: true,
        child: _RaidSection(services: services, clock: clock ?? DateTime.now),
      ),
      const SizedBox(height: EmberSpace.md),
      GridPanel(
        title: 'Markers',
        icon: Icons.place_outlined,
        fitContent: true,
        child: MarkerPreferences(services: services),
      ),
      const SizedBox(height: EmberSpace.md),
      GridPanel(
        title: 'Pins',
        icon: Icons.push_pin_outlined,
        fitContent: true,
        child: _PinsSection(services: services),
      ),
    ],
  );
}

/// The extracts the latest raid-panel screenshot matched, with its age.
///
/// A one-second timer refreshes the age, and runs only while the section is
/// mounted and a match time exists.
class _RaidSection extends StatefulWidget {
  const _RaidSection({required this.services, required this.clock});

  final AppServices services;
  final DateTime Function() clock;

  @override
  State<_RaidSection> createState() => _RaidSectionState();
}

class _RaidSectionState extends State<_RaidSection> {
  late final Listenable _sources = Listenable.merge([
    widget.services.maps,
    widget.services.mapSession,
  ]);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sources.addListener(_changed);
  }

  @override
  void dispose() {
    _sources.removeListener(_changed);
    _timer?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _syncTimer() {
    final needed = widget.services.mapSession.raidMatchedAt != null;
    if (needed && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!needed) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // The timer follows the match time. It is started here, not from the
    // listener, so it always belongs to the zone that builds the frame.
    _syncTimer();
    final ember = context.ember;
    final maps = widget.services.maps;
    final matched = widget.services.mapSession.raidMatchedAt;
    final rows = maps.raidMatchedMarkers;
    var age = matched == null
        ? Duration.zero
        : widget.clock().toUtc().difference(matched.toUtc());
    if (age.isNegative) age = Duration.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (matched != null && rows.isNotEmpty)
          Padding(
            key: const ValueKey('raid-age'),
            padding: const EdgeInsets.only(bottom: EmberSpace.xs),
            child: Text(
              'Screenshot ${scanAgeLabel(age)} ago',
              style: EmberType.label.copyWith(color: ember.inkTertiary),
            ),
          ),
        if (rows.isEmpty)
          Text(
            key: const ValueKey('raid-empty'),
            'No matched extracts yet',
            style: EmberType.body.copyWith(color: ember.inkSecondary),
          )
        else
          for (final row in rows)
            _ListRow(
              rowKey: ValueKey('raid-row-${row.marker.id}'),
              filterKey: row.marker.filterKey,
              icons: widget.services.markerIcons,
              label: row.marker.name,
              onTap: () => maps.revealMarker(row.marker.id),
            ),
      ],
    );
  }
}

/// The pins of the current map, with Add pin and per-row removal.
class _PinsSection extends StatelessWidget {
  const _PinsSection({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([services.settings, services.maps]),
    builder: (context, _) {
      final settings = services.settings;
      final map = services.maps.selectedMapId ?? settings.settings.selectedMap;
      final pins = settings.pins.where((p) => p.mapId == map).toList();
      final busy = settings.busy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('pins-add'),
              onPressed: busy
                  ? null
                  : () => showPinEditor(
                      context,
                      services,
                      coordinates: MapPinCoordinates(
                        mapId: map,
                        point: ArtworkPoint(.5, .5),
                        frame: map == 'thelab'
                            ? MapCoordinateFrame.labsNativeNormalized
                            : MapCoordinateFrame.legacyNormalized,
                      ),
                    ),
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Add pin'),
            ),
          ),
          const SizedBox(height: EmberSpace.sm),
          if (pins.isEmpty)
            Text(
              'No saved pins for this map',
              style: EmberType.body.copyWith(color: context.ember.inkSecondary),
            )
          else
            for (final pin in pins)
              _ListRow(
                rowKey: ValueKey('pin-row-${pin.id}'),
                filterKey: 'CustomPins',
                icons: services.markerIcons,
                label: pin.label,
                onTap: busy
                    ? null
                    : () => showPinEditor(context, services, pin: pin),
                trailing: IconButton(
                  key: ValueKey('pin-remove-${pin.id}'),
                  tooltip: 'Remove pin ${pin.label}',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: busy ? null : () => _remove(context, pin),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
        ],
      );
    },
  );

  Future<void> _remove(BuildContext context, CustomPin pin) async {
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
    if (remove == true) await services.settings.removePin(pin);
  }
}

/// A 30 px row of a map badge and a label, with an optional trailing action.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.rowKey,
    required this.filterKey,
    required this.icons,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  /// Keys the pressable part, which leaves the trailing action out.
  final Key rowKey;

  final String filterKey;
  final MapMarkerIcons icons;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: EmberSize.row * scale),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: rowKey,
              onTap: onTap,
              child: Row(
                children: [
                  MarkerBadge(icons: icons, filterKey: filterKey),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EmberType.body.copyWith(color: context.ember.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
