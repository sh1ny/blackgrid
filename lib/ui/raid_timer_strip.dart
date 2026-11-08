import 'package:flutter/material.dart';

import '../application/raid_timers_controller.dart';
import '../domain/raid_timers.dart';
import 'ember/theme_access.dart';

/// The slim strip under the shell header that shows the raid timers.
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
      return Container(
        key: const Key('raid-timer-strip'),
        height: 28 * MediaQuery.textScalerOf(context).scale(1),
        decoration: BoxDecoration(
          color: context.ember.canvas,
          border: Border(bottom: BorderSide(color: context.ember.hairline)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (final (i, entry) in entries.indexed) ...[
                  if (i > 0) const SizedBox(width: 22),
                  _entry(context, entry),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _entry(BuildContext context, RaidTimerEntry entry) {
    final text = Text(entry.text, style: Theme.of(context).textTheme.bodySmall);
    final tooltip = entry.tooltip;
    return Center(
      child: tooltip == null ? text : Tooltip(message: tooltip, child: text),
    );
  }
}
