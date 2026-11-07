import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../application/live_map_data_controller.dart';
import '../domain/catalog.dart';
import 'labels.dart';
import 'theme.dart';

/// Presents the selected map mode separately from the map-data authority.
class LiveMapStatus extends StatelessWidget {
  /// Creates a status presentation without requiring application services.
  const LiveMapStatus({
    super.key,
    required this.mode,
    required this.dataMode,
    required this.source,
    required this.checkedAt,
    required this.failure,
    required this.refreshing,
    required this.onRefresh,
  });

  /// The user-selected mode that governs fallback selection.
  final GameMode mode;

  /// The mode whose map data currently supplies the map.
  final GameMode dataMode;

  /// The authority currently supplying map data.
  final LiveMapDataSource source;

  /// The time of the last successful data check, if one has completed.
  final DateTime? checkedAt;

  /// The most recent refresh failure, if present.
  final Object? failure;

  /// Whether a map-data refresh is in progress.
  final bool refreshing;

  /// The explicit refresh action, or `null` when it is unavailable.
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final modeLabel = switch (mode) {
      GameMode.unknown => 'Unknown',
      GameMode.pvp => 'PvP',
      GameMode.pve => 'PvE',
      GameMode.seasonal => 'Seasonal',
    };
    final dataModeLabel = switch (dataMode) {
      GameMode.unknown => 'Unknown',
      GameMode.pvp => 'PvP',
      GameMode.pve => 'PvE',
      GameMode.seasonal => 'Seasonal',
    };
    final checkedAtValue = checkedAt;
    final checkedAtLabel = checkedAtValue == null
        ? localTimeLabel(null, now: DateTime.now())
        : '${localTimeLabel(checkedAtValue, now: DateTime.now())} '
              '(${checkedAtValue.toLocal().year})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Selected mode: $modeLabel'),
        Text('Map data mode: $dataModeLabel'),
        Text('Map data source: ${liveMapDataSourceLabel(source)}'),
        Text('Last map data check: $checkedAtLabel'),
        if (refreshing) const Text('Refreshing map data…'),
        if (failure != null)
          Text(
            'Map data refresh failed: $failure',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: refreshing ? null : onRefresh,
            icon: const Icon(Icons.refresh),
            label: Text(
              refreshing ? 'Refreshing map data…' : 'Refresh map data',
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows synthetic fallback status without constructing application services.
@Preview(name: 'Live map status', group: 'Settings', size: Size(420, 260))
Widget liveMapStatusPreview() => MaterialApp(
  theme: blackgridTheme(),
  home: const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(20),
      child: LiveMapStatus(
        mode: GameMode.pve,
        dataMode: GameMode.pvp,
        source: LiveMapDataSource.bundled,
        checkedAt: null,
        failure: 'The map source is temporarily unavailable.',
        refreshing: false,
        onRefresh: null,
      ),
    ),
  ),
);
