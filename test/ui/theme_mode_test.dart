import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';

ThemeData _theme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first));

void main() {
  testWidgets('System follows a light Windows setting by default', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final h = await pumpM1(tester);

    expect(h.services.settings.settings.themeMode.name, 'system');
    final theme = _theme(tester);
    expect(theme.brightness, Brightness.light);
    expect(theme.extension<EmberColors>(), same(EmberColors.light));
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .themeAnimationDuration,
      Duration.zero,
    );
  });

  testWidgets('System follows a Windows brightness change without restart', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpM1(tester);
    expect(_theme(tester).extension<EmberColors>(), same(EmberColors.light));

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(_theme(tester).brightness, Brightness.dark);
    expect(_theme(tester).extension<EmberColors>(), same(EmberColors.dark));

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    expect(_theme(tester).extension<EmberColors>(), same(EmberColors.light));
  });
}
