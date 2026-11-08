import 'package:flutter/material.dart';

import '../application/raid_timers_controller.dart';
import '../domain/raid_timers.dart';
import 'ember/theme_access.dart';

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
      return Wrap(
        key: const Key('raid-timer-strip'),
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (index, entry) in entries.indexed) ...[
            if (index > 0)
              Container(
                key: index == 1
                    ? const Key('timer-separator')
                    : ValueKey('timer-separator-$index'),
                width: 1,
                height: 14,
                color: context.ember.hairlineStrong,
              ),
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
