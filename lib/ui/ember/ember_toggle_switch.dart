import 'package:flutter/material.dart';

import 'ember_tokens.dart';
import 'theme_access.dart';

/// A 28 x 16 pill with a 12 px knob, drawn in ink rather than Ember.
///
/// It only draws the state; the row around it takes the press and the
/// semantics.
class EmberToggleSwitch extends StatelessWidget {
  /// Creates a switch that is on when [on] is `true`.
  const EmberToggleSwitch({super.key, required this.on});

  /// Whether the switch is on.
  final bool on;

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    return ExcludeSemantics(
      child: Container(
        width: 28,
        height: 16,
        padding: const EdgeInsets.all(2),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: on ? ember.inkSecondary : ember.hairlineStrong,
          borderRadius: BorderRadius.circular(EmberRadius.pill),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: on ? ember.canvas : ember.inkTertiary,
            shape: BoxShape.circle,
          ),
          child: const SizedBox.square(dimension: 12),
        ),
      ),
    );
  }
}
