import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/legacy/legacy_fixture.dart';
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
        find.widgetWithText(TextField, 'Selected history JSON path • optional'),
        file.path,
      );
      await tapM1Async(
        tester,
        find.text('Read and preview selected files'),
        () => find
            .textContaining('supported records accounted for')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.textContaining('supported records accounted for'),
        findsOneWidget,
      );
      expect(find.textContaining('History.FIR'), findsOneWidget);
      expect(h.services.history.rows, isEmpty);
      await tapM1Async(
        tester,
        find.text('Accept preview and import'),
        () => find
            .text('Import committed atomically. Sources were unchanged.')
            .evaluate()
            .isNotEmpty,
      );
      expect(h.services.history.rows.single.itemId, 'synthetic-unmatched');
      expect(
        find.text('Import committed atomically. Sources were unchanged.'),
        findsOneWidget,
      );
      expect(await tester.runAsync(file.readAsBytes), orderedEquals(bytes));
      await tapM1Async(
        tester,
        find.text('Read and preview selected files'),
        () => find
            .text('These exact source bytes were already imported.')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.text('These exact source bytes were already imported.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Accept preview and import'),
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
        find.widgetWithText(
          TextField,
          'Selected settings JSON path • optional',
        ),
        file.path,
      );
      await tapM1Async(
        tester,
        find.text('Read and preview selected files'),
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
}
