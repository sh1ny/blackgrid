import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/ember/ember_toggle_switch.dart';
import 'package:blackgrid/ui/settings/settings_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget row) => tester.pumpWidget(
  MaterialApp(
    theme: blackgridTheme(Brightness.dark),
    home: Scaffold(
      body: Center(child: SizedBox(width: 600, child: row)),
    ),
  ),
);

Finder _semanticsOf(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

void main() {
  testWidgets('shows the name, a one-line explanation and a trailing control', (
    tester,
  ) async {
    await _pump(
      tester,
      SettingsRow(
        name: 'Game log folder',
        explanation: 'Where the game writes its logs.',
        trailing: TextButton(onPressed: () {}, child: const Text('Browse')),
      ),
    );
    expect(find.text('Game log folder'), findsOneWidget);
    expect(find.text('Where the game writes its logs.'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.text('Where the game writes its logs.'))
          .maxLines,
      1,
    );
  });

  testWidgets('shows a message line under the row when given one', (
    tester,
  ) async {
    await _pump(
      tester,
      const SettingsRow(
        name: 'Folder',
        explanation: 'Explained.',
        trailing: SizedBox(),
        message: 'Not saved. Try again.',
      ),
    );
    expect(find.text('Not saved. Try again.'), findsOneWidget);
  });

  testWidgets('a switch row toggles on a press anywhere in the row', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final changes = <bool>[];
    await _pump(
      tester,
      SettingsRow.toggle(
        name: 'Show raid timers',
        explanation: 'Shows the timers in the top bar.',
        value: false,
        onChanged: changes.add,
      ),
    );
    expect(find.byType(EmberToggleSwitch), findsOneWidget);

    await tester.tap(find.text('Shows the timers in the top bar.'));
    await tester.pump();
    expect(changes, [true]);

    expect(
      tester.getSemantics(_semanticsOf('Show raid timers')),
      matchesSemantics(
        label: 'Show raid timers',
        hint: 'Shows the timers in the top bar.',
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('a switch that is on reports toggled semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      SettingsRow.toggle(
        name: 'Live scan',
        explanation: 'Scans on a key press.',
        value: true,
        onChanged: (_) {},
      ),
    );
    expect(
      tester.getSemantics(_semanticsOf('Live scan')),
      matchesSemantics(
        label: 'Live scan',
        hint: 'Scans on a key press.',
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('a disabled row ignores presses', (tester) async {
    final handle = tester.ensureSemantics();
    final changes = <bool>[];
    await _pump(
      tester,
      SettingsRow.toggle(
        name: 'Live scan',
        explanation: 'Scans on a key press.',
        value: false,
        enabled: false,
        onChanged: changes.add,
      ),
    );
    await tester.tap(find.text('Live scan'));
    await tester.pump();
    expect(changes, isEmpty);
    expect(
      tester.getSemantics(_semanticsOf('Live scan')),
      matchesSemantics(
        label: 'Live scan',
        hint: 'Scans on a key press.',
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    handle.dispose();
  });
}
