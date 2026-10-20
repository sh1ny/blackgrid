import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

abstract final class GridColors {
  static const background = Color(0xff070d0b);
  static const surface = Color(0xff0d1512);
  static const inset = Color(0xff090f0d);
  static const border = Color(0xff50462b);
  static const quietBorder = Color(0xff29332c);
  static const gold = Color(0xffdcc05a);
  static const text = Color(0xffe6e8df);
  static const muted = Color(0xffa0aaa0);
  static const green = Color(0xff48d28b);
}

ThemeData blackgridTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: 'Segoe UI',
  scaffoldBackgroundColor: GridColors.background,
  colorScheme: const ColorScheme.dark(
    primary: GridColors.gold,
    onPrimary: GridColors.background,
    secondary: GridColors.gold,
    surface: GridColors.surface,
    onSurface: GridColors.text,
    error: Color(0xffef9790),
    outline: GridColors.quietBorder,
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 13, height: 1.4),
    bodySmall: TextStyle(fontSize: 12, color: GridColors.muted, height: 1.4),
    titleLarge: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: GridColors.inset,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: GridColors.quietBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: GridColors.quietBorder),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: GridColors.text,
      side: const BorderSide(color: GridColors.quietBorder),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: GridColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: GridColors.border),
    ),
  ),
  dividerTheme: const DividerThemeData(
    color: GridColors.quietBorder,
    thickness: 1,
  ),
);

class GridPanel extends StatelessWidget {
  const GridPanel({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = 16,
  });
  final String title;
  final IconData icon;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final double padding;
  @override
  Widget build(BuildContext context) => Material(
    color: GridColors.surface,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: GridColors.border),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: GridColors.gold, size: 26),
              const SizedBox(width: 12),
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
          const SizedBox(height: 15),
          Flexible(fit: FlexFit.loose, child: child),
        ],
      ),
    ),
  );
}

/// A [GridPanel]-style bordered panel whose body can be collapsed.
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

  /// The gold icon shown at the start of the header.
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
  Widget build(BuildContext context) => Material(
    color: GridColors.surface,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: GridColors.border),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
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
                  Icon(icon, color: GridColors.gold, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: GridColors.gold,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 15),
            Flexible(fit: FlexFit.loose, child: child),
          ],
        ],
      ),
    ),
  );
}

@Preview(name: 'Blackgrid independent visual tokens', size: Size(500, 280))
Widget themePreview() => MaterialApp(
  theme: blackgridTheme(),
  home: const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(14),
      child: GridPanel(
        title: 'Manual inspection',
        icon: Icons.search,
        subtitle: 'M1 • no accepted scan',
        child: Text(
          'Select a real catalog item. Unknown facts remain unknown.',
        ),
      ),
    ),
  ),
);

String modeLabel(Object mode) => switch (mode.toString().split('.').last) {
  'pvp' => 'PvP',
  'pve' => 'PvE',
  'seasonal' => 'Seasonal',
  _ => 'Unknown',
};
String mapLabel(String id) => switch (id) {
  'thelab' => 'The Lab',
  'streetsoftarkov' => 'Streets',
  'groundzero' => 'Ground Zero',
  _ => id.isEmpty ? id : '${id[0].toUpperCase()}${id.substring(1)}',
};
String rub(num? value) => value == null
    ? 'Unavailable'
    : '₽${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';
