import 'package:flutter/material.dart';

import '../application/local_stats_controller.dart';
import '../domain/local_stats.dart';
import 'labels.dart';
import 'theme.dart';

/// Opens the Stats dialog for [controller] and, once it closes, drops the
/// clear failure message so it does not outlive the dialog.
Future<void> showStats(
  BuildContext context,
  LocalStatsController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => StatsDialog(controller: controller),
  );
  controller.dismissClearError();
}

/// Shows the current mode's raids per map and flea sales, and clears them on
/// confirmation.
///
/// Rebuilds whenever [controller] notifies, so a new sale or a mode change
/// shows while the dialog is open.
class StatsDialog extends StatelessWidget {
  /// Creates the dialog over [controller].
  const StatsDialog({super.key, required this.controller});

  /// The stats being shown.
  final LocalStatsController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final modeName = controller.modeKnown
          ? '${modeLabel(controller.mode)} stats'
          : 'Stats';
      return AlertDialog(
        title: Text(modeName),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _body(context),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _confirmClear(context),
            child: const Text('Clear stats'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );

  List<Widget> _body(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: GridColors.muted);
    final totals = controller.totals;
    return [
      Text("Counted from the game's logs.", style: muted),
      Text(
        controller.since == null
            ? 'Counted since stats began'
            : 'Counted since ${localTimeLabel(controller.since, now: DateTime.now())}',
        style: muted,
      ),
      const SizedBox(height: 12),
      if (!controller.modeKnown)
        const Text('Stats show once the game mode is known.')
      else if (totals.isEmpty)
        const Text('No raids or flea sales counted yet.')
      else
        ..._totals(totals),
      for (final message in [
        controller.readError,
        controller.writeError,
        controller.clearError,
      ])
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
    ];
  }

  List<Widget> _totals(LocalStatsTotals totals) => [
    Text('Raids counted: ${totals.raidTotal}'),
    for (final MapEntry(:key, :value) in totals.raidsByMap.entries)
      Padding(
        key: Key('stats-map-${key ?? 'unknown'}'),
        padding: const EdgeInsets.only(left: 12, top: 2),
        child: Row(
          children: [
            Expanded(child: Text(key == null ? 'Unknown map' : mapLabel(key))),
            Text('$value'),
          ],
        ),
      ),
    const SizedBox(height: 12),
    Text('Flea sales: ${totals.sales}'),
    Text('Items sold: ${totals.items}'),
    Text('Roubles earned: ${rub(totals.roubles)}'),
    if (totals.salesNotInRoubles > 0)
      Text(
        totals.salesNotInRoubles == 1
            ? '1 sale not paid in roubles'
            : '${totals.salesNotInRoubles} sales not paid in roubles',
        style: const TextStyle(color: GridColors.muted),
      ),
  ];

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text(
          'Clear the stats of every mode? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await controller.clear();
  }
}
