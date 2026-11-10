import 'dart:async';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/ui/app.dart';
import 'package:blackgrid/ui/app_logo.dart';
import 'package:blackgrid/ui/brand_lockup.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void expectStartupLogo(WidgetTester tester) {
  final logo = find.byType(AppLogo);
  expect(logo, findsOneWidget);
  expect(tester.widget<AppLogo>(logo).size, 54);
  expect(tester.getSize(logo), const Size(54, 54));
  expect(find.byIcon(Icons.hub_outlined), findsNothing);
}

/// Pumps the startup screen in the room [brightness] that the system asks for.
Future<void> _pumpStartup(
  WidgetTester tester,
  Future<AppServices> Function() open,
  Brightness brightness,
) async {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(BlackgridBootstrap(key: UniqueKey(), open: open));
  await tester.pump();
}

void main() {
  testWidgets('app-icon: Startup screen shows the logo', (tester) async {
    for (final brightness in Brightness.values) {
      final pending = Completer<AppServices>();
      await _pumpStartup(tester, () => pending.future, brightness);
      final ember = brightness == Brightness.dark
          ? EmberColors.dark
          : EmberColors.light;

      expect(find.byType(BrandLockup), findsOneWidget);
      expectStartupLogo(tester);
      final logo = tester.getTopLeft(find.byType(AppLogo)).dy;
      final name = tester.getTopLeft(find.text('BLACKGRID')).dy;
      final tagline = tester.getTopLeft(find.text('TRACK. PLAN. SURVIVE.')).dy;
      expect(logo, lessThan(name), reason: 'logo above BLACKGRID');
      expect(name, lessThan(tagline), reason: 'tagline below BLACKGRID');
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        ember.canvas,
        reason: 'Canvas of the $brightness room',
      );
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.color, ember.inkSecondary);
    }
  });

  testWidgets('interface-theme: Startup error', (tester) async {
    for (final brightness in Brightness.values) {
      await _pumpStartup(
        tester,
        () => Future<AppServices>.error(StateError('storage')),
        brightness,
      );
      final ember = brightness == Brightness.dark
          ? EmberColors.dark
          : EmberColors.light;

      expect(
        find.text(
          'Local storage or current-user protection could not be opened. Existing data is not reset, downgraded or deleted.',
        ),
        findsOneWidget,
      );
      final retry = find.widgetWithText(
        FilledButton,
        'Retry opening local storage',
      );
      expect(retry, findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        ember.canvas,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
  });

  testWidgets(
    'startup and storage error screens show the 54x54 app logo and no hub icon',
    (tester) async {
      final pending = Completer<AppServices>();
      await tester.pumpWidget(BlackgridBootstrap(open: () => pending.future));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expectStartupLogo(tester);

      await tester.pumpWidget(
        BlackgridBootstrap(
          key: UniqueKey(),
          open: () => Future<AppServices>.error(StateError('storage')),
        ),
      );
      await tester.pump();
      expect(find.text('Retry opening local storage'), findsOneWidget);
      expectStartupLogo(tester);
    },
  );

  const newer =
      'Your data was saved by a newer version of Blackgrid. Install that version or a later one to open it. Your data has not been changed.';
  const generic =
      'Local storage or current-user protection could not be opened. Existing data is not reset, downgraded or deleted.';

  testWidgets('a newer database shows the newer-version startup message', (
    tester,
  ) async {
    await tester.pumpWidget(
      BlackgridBootstrap(
        open: () => Future<AppServices>.error(
          const NewerDatabaseException(onDisk: 99, supported: 3),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(newer), findsOneWidget);
    expect(find.text(generic), findsNothing);
    expect(find.text('Retry opening local storage'), findsOneWidget);
  });

  testWidgets('any other open failure shows the generic storage message', (
    tester,
  ) async {
    await tester.pumpWidget(
      BlackgridBootstrap(
        open: () => Future<AppServices>.error(StateError('storage')),
      ),
    );
    await tester.pump();
    expect(find.text(generic), findsOneWidget);
    expect(find.text(newer), findsNothing);
    expect(find.text('Retry opening local storage'), findsOneWidget);
  });
}
