import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';

void main() {
  testWidgets('settings dialog shows the given app version', (tester) async {
    final h = await pumpM1(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsDialog(services: h.services, version: '0.2.0+120'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('0.2.0+120'), findsOneWidget);
  });

  testWidgets('settings dialog shows dev by default', (tester) async {
    final h = await pumpM1(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsDialog(services: h.services)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Version dev'), findsOneWidget);
  });

  testWidgets(
    'Map file inputs persist independently of the Follow logs preference',
    (tester) async {
      final h = await pumpM1(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final logs = find.widgetWithText(TextField, 'Game log folder');
      final screenshots = find.widgetWithText(TextField, 'Screenshot folder');
      await tester.ensureVisible(logs);
      await tester.enterText(logs, ' C:/blackgrid-synthetic-missing/logs ');
      await tester.ensureVisible(screenshots);
      await tester.enterText(
        screenshots,
        ' C:/blackgrid-synthetic-missing/screenshots ',
      );
      final save = find.text('Save map files');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tapM1Async(
        tester,
        save,
        () =>
            h.services.settings.settings.gameLogDirectory ==
            'C:/blackgrid-synthetic-missing/logs',
      );
      final follow = find.widgetWithText(SwitchListTile, 'Follow logs').last;
      await tester.ensureVisible(follow);
      await tester.pumpAndSettle();
      await tapM1Async(
        tester,
        follow,
        () => !h.services.settings.settings.followGameLogs,
      );
      final persisted = (await tester.runAsync(
        () => h.services.database.readSettings(),
      ))!.settings;
      expect(persisted.gameLogDirectory, 'C:/blackgrid-synthetic-missing/logs');
      expect(
        persisted.screenshotDirectory,
        'C:/blackgrid-synthetic-missing/screenshots',
      );
      expect(persisted.followGameLogs, isFalse);
      expect(
        h.services.settings.settings.gameLogDirectory,
        persisted.gameLogDirectory,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'configuration masks active-mode token saves and removes through controller',
    (tester) async {
      final h = await pumpM1(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(
        TextField,
        'Tracker token (current game mode)',
      );
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'PVP_SYNTHETIC_LOCAL_ONLY');
      await tester.ensureVisible(find.text('Save token'));
      await tester.pumpAndSettle();
      await tapM1Async(
        tester,
        find.text('Save token'),
        () => find.text('Tracker token saved').evaluate().isNotEmpty,
      );
      expect(h.credentials.values[GameMode.pvp], 'PVP_SYNTHETIC_LOCAL_ONLY');
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(find.text('Tracker token saved'), findsOneWidget);
      await tapM1Async(
        tester,
        find.text('Remove token'),
        () => h.credentials.values[GameMode.pvp] == null,
      );
      expect(h.credentials.values[GameMode.pvp], isNull);
      expect(h.services.progress.snapshot, isNull);
    },
  );
  testWidgets(
    'mode and catalog refresh configuration are working supporting controls',
    (tester) async {
      final h = await pumpM1(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<GameMode>).last);
      await tester.pumpAndSettle();
      await tapM1Async(
        tester,
        find.text('PvE').last,
        () =>
            h.services.catalog.mode == GameMode.pve &&
            !h.services.catalog.loading,
      );
      expect(h.services.catalog.mode, GameMode.pve);
      await tapM1Async(
        tester,
        find.text('Refresh item data'),
        () =>
            h.services.catalog.snapshot?.mode == GameMode.pve &&
            !h.services.catalog.loading,
      );
      expect(h.services.catalog.snapshot?.mode, GameMode.pve);
      expect(h.requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
