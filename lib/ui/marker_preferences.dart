import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../application/map_controller.dart';
import '../domain/map_marker_query.dart';
import '../domain/marker_categories.dart';
import '../maps/map_marker_icons.dart';
import '../maps/prepared_map.dart';
import 'ember/ember_toggle_switch.dart';
import 'ember/ember_tokens.dart';
import 'ember/theme_access.dart';

/// The fixed groups of the marker list, in order, with their categories.
///
/// A group none of whose categories the current map can show is left out.
const _groups = <(String title, List<String> keys)>[
  ('Extracts', ['PmcExtracts', 'ScavExtracts', 'SharedExtracts', 'Transits']),
  ('Quests', ['QuestItems', 'QuestObjectives']),
  ('Danger', ['Hazards', 'HazardZones']),
  ('Bosses', ['BossSpawns']),
  ('Spawns', ['CultistSpawns', 'PmcSpawns', 'ScavSpawns']),
  ('Loot', ['lootContainers', 'lootLoose']),
  ('Utility', ['locks', 'Switches', 'BtrStops', 'stationaryWeapons']),
  ('Yours', ['CustomPins']),
];

/// What the Markers section reads from the current map's marker inventory.
///
/// It is derived in one pass over the inventory and kept until the content
/// changes, so panning and zooming never count the markers again.
class MarkerFacts {
  MarkerFacts._({
    required this.generation,
    required this.mapId,
    required this.markers,
    required this.keys,
    required this.counts,
    required this.traders,
  });

  /// The facts of the selected map in [maps].
  ///
  /// The same instance comes back until the content generation, the selected
  /// map or the marker inventory changes.
  factory MarkerFacts.of(MapController maps) {
    final cached = _cache[maps];
    final markers = maps.activeMarkers;
    if (cached != null &&
        cached.generation == maps.contentGeneration &&
        cached.mapId == maps.selectedMapId &&
        identical(cached.markers, markers)) {
      return cached;
    }
    final counts = <String, int>{};
    final traders = <String>{};
    for (final marker in markers) {
      counts[marker.filterKey] = (counts[marker.filterKey] ?? 0) + 1;
      final metadata = MapMarkerMetadata(
        name: marker.name,
        type: marker.filterKey,
        category: marker.category,
        details: marker.details,
        source: marker.source,
      );
      if (metadata.isQuest) traders.addAll(metadata.traders);
    }
    return _cache[maps] = MarkerFacts._(
      generation: maps.contentGeneration,
      mapId: maps.selectedMapId,
      markers: markers,
      keys: List.unmodifiable(markerPreferenceKeys(maps.applicableCategories)),
      counts: Map.unmodifiable(counts),
      traders: List.unmodifiable(traders.toList()..sort()),
    );
  }

  static final _cache = Expando<MarkerFacts>();

  /// The content generation these facts were derived for.
  final int generation;

  /// The selected map these facts were derived for.
  final String? mapId;

  /// The marker inventory these facts were derived from.
  final List<PreparedMarker> markers;

  /// The saveable categories of the map, Saved pins included, in list order.
  final List<String> keys;

  /// The number of markers of each category, without saved pins.
  final Map<String, int> counts;

  /// The traders of the map's quest markers, sorted.
  final List<String> traders;
}

/// Draws the unselected map badge of one category on a 24 px canvas.
///
/// The drawing is the one the map uses, so a list and the map agree. A
/// category whose icon failed draws the map's fallback badge.
class MarkerBadge extends StatelessWidget {
  /// Creates the badge of [filterKey], dimmed when [dimmed] is `true`.
  const MarkerBadge({
    super.key,
    required this.icons,
    required this.filterKey,
    this.dimmed = false,
  });

  /// The icons the map draws its badges from.
  final MapMarkerIcons icons;

  /// The category key of the badge.
  final String filterKey;

  /// Whether the badge is drawn at the dimmed-marker opacity.
  final bool dimmed;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(24),
    painter: _BadgePainter(icons: icons, filterKey: filterKey, dimmed: dimmed),
  );
}

class _BadgePainter extends CustomPainter {
  _BadgePainter({
    required this.icons,
    required this.filterKey,
    required this.dimmed,
  }) : super(repaint: icons);

  final MapMarkerIcons icons;
  final String filterKey;
  final bool dimmed;

  @override
  void paint(Canvas canvas, Size size) => paintMarkerBadge(
    canvas,
    size.center(Offset.zero),
    icons,
    filterKey: filterKey,
    selected: false,
    highlighted: false,
    dimmed: dimmed,
  );

  // The icons notify once, when loading ends, through `repaint`.
  @override
  bool shouldRepaint(_BadgePainter old) =>
      old.filterKey != filterKey || old.dimmed != dimmed || old.icons != icons;
}

/// Rebuilds [builder] only when [select] returns a different value.
///
/// It ignores the notifications that leave the selected value alone, such as
/// a pan or a zoom.
class _Selector<T> extends StatefulWidget {
  const _Selector({
    required this.listenable,
    required this.select,
    required this.builder,
  });

  final Listenable listenable;
  final T Function() select;
  final Widget Function(BuildContext context) builder;

  @override
  State<_Selector<T>> createState() => _SelectorState<T>();
}

class _SelectorState<T> extends State<_Selector<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.select();
    widget.listenable.addListener(_check);
  }

  @override
  void didUpdateWidget(_Selector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_check);
      widget.listenable.addListener(_check);
    }
    _value = widget.select();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final next = widget.select();
    if (next != _value && mounted) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// The Markers section: filters, bulk switches and the marker rows.
///
/// The filters come first: a marker search, a quest name filter and one chip
/// per trader of the map plus All. Show all and Hide all set every row of the
/// map. Saving marker filters lives in Settings, not here.
class MarkerPreferences extends StatelessWidget {
  /// Creates the section for the map `services.maps` shows.
  const MarkerPreferences({super.key, required this.services});

  /// The services whose map, settings and marker icons the section uses.
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final maps = services.maps;
    return _Selector<(int, List<PreparedMarker>, String)>(
      listenable: maps,
      select: () =>
          (maps.contentGeneration, maps.activeMarkers, maps.questTrader),
      builder: (context) {
        final facts = MarkerFacts.of(maps);
        final active = maps.questTrader.trim();
        final allActive = active.isEmpty || active.toLowerCase() == 'all';
        // An active trader the map lacks stays as a selected chip, so a
        // filter is never active out of sight.
        final traders = [
          ...facts.traders,
          if (!allActive &&
              !facts.traders.any(
                (name) => name.toLowerCase() == active.toLowerCase(),
              ))
            active,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: const ValueKey('marker-section-search'),
              initialValue: maps.search,
              decoration: const InputDecoration(
                labelText: 'Find markers',
                hintText: 'door, tunnel',
              ),
              onChanged: maps.setSearch,
            ),
            const SizedBox(height: EmberSpace.sm),
            TextFormField(
              key: const ValueKey('marker-quest-name'),
              initialValue: maps.questName,
              decoration: const InputDecoration(
                labelText: 'Quest name contains',
              ),
              onChanged: (value) => maps.setQuestFilters(name: value),
            ),
            const SizedBox(height: EmberSpace.md),
            Text(
              'Quest trader',
              style: EmberType.label.copyWith(color: context.ember.inkTertiary),
            ),
            const SizedBox(height: EmberSpace.xs),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _TraderChip(
                  chipKey: const ValueKey('trader-chip-all'),
                  label: 'All',
                  selected: allActive,
                  onSelected: () => maps.setQuestFilters(trader: ''),
                ),
                for (final name in traders)
                  _TraderChip(
                    chipKey: ValueKey('trader-chip-$name'),
                    label: name,
                    selected:
                        !allActive &&
                        name.toLowerCase() == active.toLowerCase(),
                    onSelected: () => maps.setQuestFilters(trader: name),
                  ),
              ],
            ),
            const SizedBox(height: EmberSpace.sm),
            ListenableBuilder(
              listenable: services.settings,
              builder: (context, _) => Wrap(
                spacing: EmberSpace.xs,
                children: [
                  for (final (label, value) in [
                    ('Show all', true),
                    ('Hide all', false),
                  ])
                    TextButton(
                      onPressed: services.settings.busy
                          ? null
                          : () => services.settings.save(
                              services.settings.settings.copyWith(
                                markerFilters: {
                                  ...services.settings.settings.markerFilters,
                                  for (final key in facts.keys) key: value,
                                },
                              ),
                            ),
                      child: Text(label),
                    ),
                ],
              ),
            ),
            MarkerRows(services: services),
          ],
        );
      },
    );
  }
}

class _TraderChip extends StatelessWidget {
  const _TraderChip({
    required this.chipKey,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final Key chipKey;
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    key: chipKey,
    label: Text(label),
    selected: selected,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    onSelected: (_) => onSelected(),
  );
}

/// The marker categories of the current map as grouped 30 px rows.
///
/// Each row draws the category's map badge, its player-facing label, its
/// count on this map and a switch. Clicking anywhere on a row shows or hides
/// the category through `services.settings.setMarker`; a hidden row dims its
/// badge and label. Rows ignore clicks while settings are being saved.
class MarkerRows extends StatelessWidget {
  /// Creates the rows for the map `services.maps` shows.
  const MarkerRows({super.key, required this.services});

  /// The services whose settings and marker icons the rows use.
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final maps = services.maps;
    return _Selector<(int, List<PreparedMarker>, String?)>(
      listenable: maps,
      select: () =>
          (maps.contentGeneration, maps.activeMarkers, maps.selectedMapId),
      builder: (context) {
        final facts = MarkerFacts.of(maps);
        return ListenableBuilder(
          listenable: services.settings,
          builder: (context, _) {
            final settings = services.settings;
            final mapId = maps.selectedMapId ?? settings.settings.selectedMap;
            final pins = settings.pins.where((p) => p.mapId == mapId).length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (title, keys) in _groups)
                  if (keys.any(facts.keys.contains)) ...[
                    _GroupHeading(title),
                    for (final key in keys)
                      if (facts.keys.contains(key))
                        _MarkerRow(
                          key: ValueKey('marker-row-$key'),
                          switchKey: ValueKey('marker-switch-$key'),
                          filterKey: key,
                          icons: services.markerIcons,
                          count: key == 'CustomPins'
                              ? pins
                              : facts.counts[key] ?? 0,
                          shown: settings.settings.markerFilters[key] ?? true,
                          onToggle: settings.busy
                              ? null
                              : () {
                                  final shown =
                                      settings.settings.markerFilters[key] ??
                                      true;
                                  settings.setMarker(key, !shown);
                                },
                        ),
                  ],
              ],
            );
          },
        );
      },
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey('marker-group-$title'),
    padding: const EdgeInsets.only(top: EmberSpace.md, bottom: EmberSpace.xs),
    child: Text(
      title,
      style: EmberType.label.copyWith(color: context.ember.inkTertiary),
    ),
  );
}

class _MarkerRow extends StatelessWidget {
  const _MarkerRow({
    super.key,
    required this.switchKey,
    required this.filterKey,
    required this.icons,
    required this.count,
    required this.shown,
    required this.onToggle,
  });

  final Key switchKey;
  final String filterKey;
  final MapMarkerIcons icons;
  final int count;
  final bool shown;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    final label = markerCategoryLabel(filterKey);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Semantics(
      toggled: shown,
      label: label,
      enabled: onToggle != null,
      onTap: onToggle,
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: EmberSize.row * scale),
          child: Row(
            children: [
              MarkerBadge(icons: icons, filterKey: filterKey, dimmed: !shown),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EmberType.body.copyWith(
                    color: shown ? ember.ink : ember.inkTertiary,
                  ),
                ),
              ),
              Text(
                '$count',
                style: EmberType.label.copyWith(color: ember.inkTertiary),
              ),
              const SizedBox(width: 10),
              EmberToggleSwitch(key: switchKey, on: shown),
            ],
          ),
        ),
      ),
    );
  }
}
