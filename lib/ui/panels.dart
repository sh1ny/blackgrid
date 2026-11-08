import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'ember/ember_theme.dart';
import 'ember/ember_tokens.dart';
import 'ember/theme_access.dart';

/// The Ember panel surface: panel colour, a 1px hairline, 12px corners, 18px
/// padding and no elevation.
class _PanelSurface extends StatelessWidget {
  const _PanelSurface({required this.padding, required this.child});

  final double padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: context.ember.panel,
    elevation: 0,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: context.ember.hairline),
      borderRadius: BorderRadius.circular(EmberRadius.l),
    ),
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

/// A titled panel on the Ember panel surface.
class GridPanel extends StatelessWidget {
  /// Creates a panel with a [title], a leading [icon] and a [child] body.
  const GridPanel({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = 18,
    this.fitContent = false,
  });

  /// The panel title, set in the UI Heading role.
  final String title;

  /// The 16px icon at the start of the header.
  final IconData icon;

  /// An optional line under the [title].
  final String? subtitle;

  /// An optional widget at the end of the header.
  final Widget? trailing;

  /// The panel body.
  final Widget child;

  /// Whether the body sizes itself instead of filling a bounded panel.
  final bool fitContent;

  /// The padding around the panel content.
  final double padding;

  @override
  Widget build(BuildContext context) => _PanelSurface(
    padding: padding,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelIcon(icon),
            const SizedBox(width: EmberSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 14),
        if (fitContent) child else Flexible(fit: FlexFit.loose, child: child),
      ],
    ),
  );
}

class _PanelIcon extends StatelessWidget {
  const _PanelIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, color: context.ember.inkSecondary, size: EmberSize.icon);
}

/// A [GridPanel]-style panel whose body can be collapsed.
///
/// The whole header row is one button that asks the parent to flip
/// [expanded]. The panel is stateless: the parent owns the flag. The [child]
/// is built only while expanded, and there is no animation.
class CollapsibleGridPanel extends StatelessWidget {
  /// Creates a collapsible panel.
  const CollapsibleGridPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.expanded,
    required this.onExpandedChanged,
    this.toggleKey,
    required this.child,
  });

  /// The header title, also used as the semantic label of the header button.
  final String title;

  /// The 16px icon shown at the start of the header.
  final IconData icon;

  /// Whether the [child] is shown.
  final bool expanded;

  /// Called with the negated [expanded] value when the header is tapped.
  final ValueChanged<bool> onExpandedChanged;

  /// The key applied to the header [InkWell], for locating it in tests.
  final Key? toggleKey;

  /// The body, built only while [expanded] is `true`.
  final Widget child;

  @override
  Widget build(BuildContext context) => _PanelSurface(
    padding: 18,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: title,
          onTap: () => onExpandedChanged(!expanded),
          excludeSemantics: true,
          child: InkWell(
            key: toggleKey,
            onTap: () => onExpandedChanged(!expanded),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PanelIcon(icon),
                const SizedBox(width: EmberSpace.sm),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: context.ember.inkSecondary,
                  size: EmberSize.icon,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 14),
          Flexible(fit: FlexFit.loose, child: child),
        ],
      ],
    ),
  );
}

/// A collapsible "Details" block that sits inline inside a panel.
///
/// The whole title row is one button that asks the parent to flip [expanded].
/// The section is stateless: the parent owns the flag. It starts collapsed
/// when the parent passes `false`, shows only the title row while collapsed,
/// and calls [builder] only while expanded. There is no animation.
class DetailsSection extends StatelessWidget {
  /// Creates a details section.
  const DetailsSection({
    super.key,
    required this.expanded,
    required this.onExpandedChanged,
    required this.builder,
  });

  /// Whether the content is shown.
  final bool expanded;

  /// Called with the negated [expanded] value when the title row is tapped.
  final ValueChanged<bool> onExpandedChanged;

  /// Builds the content, called only while [expanded] is `true`.
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        button: true,
        expanded: expanded,
        label: 'Details',
        onTap: () => onExpandedChanged(!expanded),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onExpandedChanged(!expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: EmberSpace.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Details',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: context.ember.inkSecondary,
                  size: EmberSize.icon,
                ),
              ],
            ),
          ),
        ),
      ),
      if (expanded) builder(context),
    ],
  );
}

@Preview(name: 'Blackgrid panel in the dark room', size: Size(500, 280))
Widget panelPreview() => MaterialApp(
  theme: blackgridTheme(Brightness.dark),
  home: const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(14),
      child: GridPanel(
        title: 'Pick or scan an item',
        icon: Icons.search,
        child: Text(
          'Select a real catalog item. Unknown facts remain unknown.',
        ),
      ),
    ),
  ),
);
