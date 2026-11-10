import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blackgrid/ui/import_dialog.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';

import '../fixtures/m1/legacy/legacy_fixture.dart';
import '../support/m1_harness.dart';
import '../support/m1_widget_harness.dart';

/// Opens the Details toggle of the preview, scrolling it into view first.
Future<void> _openDetails(WidgetTester tester) async {
  final toggle = find.byKey(const Key('import-details-toggle'));
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

/// The per-record lines: kind, input order, key and disposition.
Finder get _recordLines => find.textContaining(RegExp(r' #\d+ • '));

Finder get _fingerprint => find.textContaining('File fingerprint');

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
      await _openDetails(tester);
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
  Future<M1Harness> previewHistory(
    WidgetTester tester, {
    int records = 1,
  }) async {
    final h = await pumpM1(tester);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('blackgrid-widget-commit-'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/synthetic-history.json');
    await tester.runAsync(
      () => file.writeAsString(
        jsonEncode(
          syntheticHistory(
            rows: [
              for (var i = 0; i < records; i++) activity(id: 'synthetic-$i'),
            ],
          ),
        ),
      ),
    );
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
    return h;
  }

  testWidgets('legacy-import: Preview read', (tester) async {
    await previewHistory(tester, records: 3);

    expect(find.textContaining('3 records found'), findsOneWidget);
    expect(
      find.text('Replace entries that already exist here'),
      findsOneWidget,
    );
    expect(find.text('Details'), findsOneWidget);
    expect(_fingerprint, findsNothing);
    expect(_recordLines, findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('legacy-import: Details opened', (tester) async {
    await previewHistory(tester, records: 3);
    await _openDetails(tester);

    expect(_fingerprint, findsOneWidget);
    expect(_recordLines, findsNWidgets(3));
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('legacy-import: New preview resets Details', (tester) async {
    await previewHistory(tester, records: 3);
    await _openDetails(tester);
    expect(_recordLines, findsNWidgets(3));

    // Scroll back to the top, where the read button is.
    await tester.drag(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ListView),
      ),
      const Offset(0, 3000),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => tester.tap(find.text('Read files and preview')),
    );
    // The read is under way: the old preview is gone.
    await tester.pump();
    expect(find.textContaining('3 records found'), findsNothing);
    final elapsed = Stopwatch()..start();
    while (find.textContaining('3 records found').evaluate().isEmpty) {
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 10)));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.textContaining('3 records found'), findsOneWidget);
    expect(_fingerprint, findsNothing);
    expect(_recordLines, findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('legacy-import: Already imported', (tester) async {
    await previewHistory(tester);
    await tapM1Async(
      tester,
      find.text('Import now'),
      () => find
          .text('Import finished; your files were not changed')
          .evaluate()
          .isNotEmpty,
    );
    await tapM1Async(
      tester,
      find.text('Read files and preview'),
      () =>
          find.text('These files were already imported.').evaluate().isNotEmpty,
    );

    expect(find.text('These files were already imported.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Import now'))
          .onPressed,
      isNull,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a commit refused as already imported says so', (tester) async {
    final h = await previewHistory(tester);
    // Another import commits the same files after the preview was shown.
    await tester.runAsync(() async {
      final other = h.services.importer;
      final file = File(
        (tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'History file path (optional)'),
            )
            .controller!
            .text),
      );
      final again = await other.previewFiles(historyPath: file.path);
      await other.commit(again, replaceExisting: false);
    });
    await tapM1Async(
      tester,
      find.text('Import now'),
      () => find.textContaining('Nothing was changed').evaluate().isNotEmpty,
    );
    expect(
      find.text('These files were already imported. Nothing was changed.'),
      findsOneWidget,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
  testWidgets('a commit storage failure says the import could not be saved', (
    tester,
  ) async {
    final h = await previewHistory(tester);
    await tester.runAsync(
      () => h.db.customStatement(
        'CREATE TEMP TRIGGER abort_import BEFORE INSERT ON import_records '
        "BEGIN SELECT RAISE(ABORT, 'test'); END",
      ),
    );
    await tapM1Async(
      tester,
      find.text('Import now'),
      () => find.textContaining('Nothing was changed').evaluate().isNotEmpty,
    );
    expect(
      find.text('The import could not be saved. Nothing was changed.'),
      findsOneWidget,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
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
          theme: blackgridTheme(Brightness.dark),
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
