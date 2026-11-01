import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blackgrid/ui/import_dialog.dart';
import 'package:blackgrid/ui/theme.dart';

import '../fixtures/m1/legacy/legacy_fixture.dart';
import '../support/m1_harness.dart';
import '../support/m1_widget_harness.dart';

void main() {
  testWidgets(
    'explicit selected file previews exclusions and confirms once-only import',
    (tester) async {
      final h = await pumpM1(tester);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('blackgrid-widget-import-'),
      ))!;
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/synthetic-history.json');
      final bytes = utf8.encode(jsonEncode(syntheticHistory()));
      await tester.runAsync(() => file.writeAsBytes(bytes));
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'History file path (optional)'),
        file.path,
      );
      await tapM1Async(
        tester,
        find.text('Read files and preview'),
        () => find.textContaining('records found').evaluate().isNotEmpty,
      );
      expect(find.textContaining('records found'), findsOneWidget);
      expect(find.textContaining('History.FIR'), findsOneWidget);
      expect(h.services.history.rows, isEmpty);
      await tapM1Async(
        tester,
        find.text('Import now'),
        () => find
            .text('Import finished; your files were not changed')
            .evaluate()
            .isNotEmpty,
      );
      expect(h.services.history.rows.single.itemId, 'synthetic-unmatched');
      expect(
        find.text('Import finished; your files were not changed'),
        findsOneWidget,
      );
      expect(await tester.runAsync(file.readAsBytes), orderedEquals(bytes));
      await tapM1Async(
        tester,
        find.text('Read files and preview'),
        () => find
            .text('These files were already imported.')
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('These files were already imported.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Import now'),
            )
            .onPressed,
        isNull,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  testWidgets(
    'unsupported selected source is rejected before any destination mutation',
    (tester) async {
      final h = await pumpM1(tester);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('blackgrid-widget-rejected-'),
      ))!;
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/future-settings.json');
      await tester.runAsync(
        () => file.writeAsString(jsonEncode(syntheticSettings(version: 4))),
      );
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Settings file path (optional)'),
        file.path,
      );
      await tapM1Async(
        tester,
        find.text('Read files and preview'),
        () => find
            .textContaining('Unsupported legacy schema version')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.textContaining('Unsupported legacy schema version'),
        findsOneWidget,
      );
      expect(h.services.settings.pins, isEmpty);
      expect(h.services.history.rows, isEmpty);
    },
  );
  testWidgets(
    'a reload failure after a saved import says the import was saved',
    (tester) async {
      final h = (await tester.runAsync(() async {
        final result = M1Harness();
        await result.initialize();
        return result;
      }))!;
      addTearDown(h.dispose);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('blackgrid-widget-reload-'),
      ))!;
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/synthetic-history.json');
      await tester.runAsync(
        () => file.writeAsString(jsonEncode(syntheticHistory())),
      );
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: blackgridTheme(),
          home: Scaffold(
            body: ImportDialog(
              services: h.services,
              reload: () async => throw StateError('synthetic reload failure'),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'History file path (optional)'),
        file.path,
      );
      await tapM1Async(
        tester,
        find.text('Read files and preview'),
        () => find.textContaining('records found').evaluate().isNotEmpty,
      );
      await tapM1Async(
        tester,
        find.text('Import now'),
        () => find
            .textContaining('Restart Blackgrid to see the imported data')
            .evaluate()
            .isNotEmpty,
      );

      expect(
        find.text(
          'The import was saved, but Blackgrid could not reload it. '
          'Restart Blackgrid to see the imported data.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing was changed'), findsNothing);
      expect(
        find.text('Import finished; your files were not changed'),
        findsNothing,
      );
      final rows = await tester.runAsync(h.db.readActivity);
      expect(rows!.rows, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
