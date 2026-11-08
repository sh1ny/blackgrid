import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';

Finder _segment(String label) => find.descendant(
  of: find.byType(SegmentedButton<ThemeChoice>),
  matching: find.text(label),
);

ThemeData _theme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first));

void main() {
  testWidgets('selecting Light switches the room in the next frame', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final h = await pumpM1(tester);
    expect(_theme(tester).extension<EmberColors>(), same(EmberColors.dark));

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(_segment('System'), findsOneWidget);
    expect(_segment('Dark'), findsOneWidget);
    final selected = tester
        .widget<SegmentedButton<ThemeChoice>>(
          find.byType(SegmentedButton<ThemeChoice>),
        )
        .selected;
    expect(selected, {ThemeChoice.system});

    await tapM1Async(
      tester,
      _segment('Light'),
      () => h.services.settings.settings.themeMode == ThemeChoice.light,
    );

    expect(_theme(tester).extension<EmberColors>(), same(EmberColors.light));
    expect(
      tester.widget<AnimatedTheme>(find.byType(AnimatedTheme).first).duration,
      Duration.zero,
    );
    final stored = (await tester.runAsync(
      () => h.services.database.readSettings(),
    ))!.settings;
    expect(stored.themeMode, ThemeChoice.light);
  });

  testWidgets('selecting the current option saves nothing', (tester) async {
    final h = await pumpM1(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final before = h.services.settings.settings;
    var notifications = 0;
    void count() => notifications++;
    h.services.settings.addListener(count);
    addTearDown(() => h.services.settings.removeListener(count));

    await tester.tap(_segment('System'));
    await tester.pumpAndSettle();

    expect(notifications, 0);
    expect(h.services.settings.settings, same(before));
    expect(h.services.settings.settings.themeMode, ThemeChoice.system);
    expect(h.services.settings.busy, isFalse);
  });
}
