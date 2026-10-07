import 'package:blackgrid/domain/catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';

void main() {
  testWidgets(
    'Map file inputs persist independently of the Follow logs preference',
    (tester) async {
      final h = await pumpM1(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final logs = find.widgetWithText(TextField, 'Game log directory');
      final screenshots = find.widgetWithText(
        TextField,
        'Screenshot directory',
      );
      await tester.ensureVisible(logs);
      await tester.enterText(logs, ' C:/blackgrid-synthetic-missing/logs ');
      await tester.ensureVisible(screenshots);
      await tester.enterText(
        screenshots,
        ' C:/blackgrid-synthetic-missing/screenshots ',
      );
      final save = find.text('Save map inputs');
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
      ))!;
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
        'Tracker token • active mode only',
      );
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'PVP_SYNTHETIC_LOCAL_ONLY');
      await tester.ensureVisible(find.text('Save protected token'));
      await tester.pumpAndSettle();
      await tapM1Async(
        tester,
        find.text('Save protected token'),
        () => find
            .text('Current-user DPAPI credential saved.')
            .evaluate()
            .isNotEmpty,
      );
      expect(h.credentials.values[GameMode.pvp], 'PVP_SYNTHETIC_LOCAL_ONLY');
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(find.text('Current-user DPAPI credential saved.'), findsOneWidget);
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
        find.text('Refresh complete catalog'),
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
