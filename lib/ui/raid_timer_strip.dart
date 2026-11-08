import 'package:flutter/material.dart';

import '../application/raid_timers_controller.dart';
import '../domain/raid_timers.dart';

/// The compact raid timer entries shown in the shell top bar.
///
/// Rebuilds whenever [controller] publishes a new view and takes no space
/// while the view has no entries. Each entry's explanation is its tooltip.
class RaidTimerStrip extends StatelessWidget {
  /// Creates a strip showing [controller]'s view.
  const RaidTimerStrip({super.key, required this.controller});

  /// Where the entries come from.
  final RaidTimersController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final entries = controller.view.entries;
      if (entries.isEmpty) return const SizedBox.shrink();
      return Row(
        key: const Key('raid-timer-strip'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, entry) in entries.indexed) ...[
            if (index > 0) const SizedBox(width: 12),
            _entry(context, entry),
          ],
        ],
      );
    },
  );

  Widget _entry(BuildContext context, RaidTimerEntry entry) {
    final text = Text(
      entry.text,
      style: Theme.of(context).textTheme.labelSmall,
    );
    final tooltip = entry.tooltip;
    return tooltip == null ? text : Tooltip(message: tooltip, child: text);
  }
}
