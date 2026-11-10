import 'package:flutter/material.dart';

import '../ember/ember_toggle_switch.dart';
import '../ember/ember_tokens.dart';
import '../ember/theme_access.dart';

/// One setting on the Settings page: its name, a one-line explanation and the
/// control on the right.
///
/// An optional [message] sits under the row, for a result such as
/// "Not saved. Try again.". The row draws no colour or type of its own: the
/// roles come from the Ember theme.
class SettingsRow extends StatelessWidget {
  /// Creates a row that shows [trailing] as its control.
  ///
  /// [trailing] is a button, a dropdown, a text field or any other control.
  /// The row does not take presses itself; the control does.
  const SettingsRow({
    super.key,
    required this.name,
    required this.explanation,
    required this.trailing,
    this.message,
  }) : _on = null,
       _onChanged = null,
       _enabled = true;

  /// Creates a switch row that is on when [value] is `true`.
  ///
  /// The whole row is the press target and reports a toggled state to
  /// assistive technology. A press calls [onChanged] with the opposite of
  /// [value]. The row ignores presses when [enabled] is `false`.
  const SettingsRow.toggle({
    super.key,
    required this.name,
    required this.explanation,
    required bool value,
    required this._onChanged,
    this._enabled = true,
    this.message,
  }) : trailing = null,
       _on = value;

  /// The setting's name, in the primary ink.
  final String name;

  /// The one-line explanation under the name.
  final String explanation;

  /// The control on the right, or `null` for a switch row.
  final Widget? trailing;

  /// A line under the row, such as a save result, or `null` for none.
  final String? message;

  final bool? _on;
  final ValueChanged<bool>? _onChanged;
  final bool _enabled;

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    final on = _on;
    final onChanged = _enabled ? _onChanged : null;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, style: EmberType.body.copyWith(color: ember.ink)),
        Text(
          explanation,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: EmberType.label.copyWith(color: ember.inkTertiary),
        ),
      ],
    );
    final line = Row(
      children: [
        Expanded(child: texts),
        const SizedBox(width: EmberSpace.lg),
        if (on != null) EmberToggleSwitch(on: on) else ?trailing,
      ],
    );
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: EmberSpace.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: EmberSize.row * scale),
        child: Center(child: line),
      ),
    );
    final note = message;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (on != null)
          Semantics(
            toggled: on,
            label: name,
            hint: explanation,
            enabled: onChanged != null,
            onTap: onChanged == null ? null : () => onChanged(!on),
            excludeSemantics: true,
            child: InkWell(
              onTap: onChanged == null ? null : () => onChanged(!on),
              child: body,
            ),
          )
        else
          body,
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: EmberSpace.sm),
            child: Text(
              note,
              style: EmberType.label.copyWith(color: ember.errInk),
            ),
          ),
      ],
    );
    return column;
  }
}
