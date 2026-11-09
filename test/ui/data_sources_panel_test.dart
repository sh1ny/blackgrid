import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/progress_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_harness.dart';

void main() {
  Future<M1Harness> harness(
    WidgetTester tester, {
    bool noMode = false,
    DateTime Function()? clock,
  }) async {
    final h = (await tester.runAsync(() async {
      final result = M1Harness(clock: clock);
      await result.initialize(
        mode: noMode ? GameMode.unknown : GameMode.pvp,
        refresh: !noMode,
      );
      return result;
    }))!;
    addTearDown(h.dispose);
    return h;
  }

  Future<void> show(
    WidgetTester tester,
    M1Harness h, {
    bool diagnostics = false,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: blackgridTheme(Brightness.dark),
        home: Scaffold(
          body: diagnostics
              ? SingleChildScrollView(
                  child: DataSourceDiagnostics(services: h.services),
                )
              : SourcePanel(services: h.services),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'current item data says up to date with its local time and has no Details',
    (tester) async {
      final h = await harness(tester);
      final snapshot = h.services.catalog.snapshot!;
      expect(h.services.catalog.status, CatalogStatus.current);
      await show(tester, h);

      final time = localTimeLabel(snapshot.observedAt, now: DateTime.now());
      expect(find.text('Data sources'), findsOneWidget);
      expect(
        find.text('Item data: up to date · updated $time'),
        findsOneWidget,
      );
      expect(snapshot.source, isNotEmpty);
      expect(find.text('Details'), findsNothing);
      expect(find.textContaining(snapshot.source), findsNothing);
      expect(find.textContaining('http'), findsNothing);
      expect(find.textContaining('records'), findsNothing);
      expect(
        find.textContaining(snapshot.observedAt.toUtc().toIso8601String()),
        findsNothing,
      );
    },
  );

  testWidgets('no catalog says item data is not downloaded yet', (
    tester,
  ) async {
    final h = await harness(tester, noMode: true);
    expect(h.services.catalog.snapshot, isNull);
    await show(tester, h);

    expect(find.text('Item data: not downloaded yet'), findsOneWidget);
  });

  testWidgets('cooldown is said in the panel with no end time', (tester) async {
    final h = await harness(tester);
    final until = DateTime.now().add(const Duration(minutes: 3));
    h.services.progress
      ..status = ProgressStatus.cooldown
      ..cooldownUntil = until;
    await show(tester, h);

    expect(
      find.text(
        'Tracker progress: '
        '${progressStatusLabel(ProgressStatus.cooldown)} · PvP',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('cooling down'), findsWidgets);
    expect(find.text('Details'), findsNothing);
    expect(find.textContaining('available again'), findsNothing);
    expect(find.textContaining(until.toUtc().toIso8601String()), findsNothing);
    expect(
      find.textContaining(localTimeLabel(until, now: DateTime.now())),
      findsNothing,
    );
  });

  testWidgets(
    'Tracker progress mode stays visible when it differs from the game mode',
    (tester) async {
      final h = await harness(tester);
      h.services.progress.mode = GameMode.pve;
      await show(tester, h);

      expect(find.text('Game mode: PvP'), findsOneWidget);
      expect(
        find.text(
          'Tracker progress: '
          '${progressStatusLabel(h.services.progress.status)} · PvE',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('a catalog error shows beside the out of date item status', (
    tester,
  ) async {
    final h = await harness(tester);
    h.failNetwork = true;
    await tester.runAsync(h.services.catalog.refresh);
    expect(h.services.catalog.status, CatalogStatus.stale);
    await show(tester, h);

    expect(find.textContaining('Item data: out of date'), findsOneWidget);
    expect(
      find.text(
        'Item data could not be downloaded: tarkov.dev answered with an '
        'error. The last item data is still in use.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a successful refresh clears the catalog error from the panel', (
    tester,
  ) async {
    final h = await harness(tester);
    h.failNetwork = true;
    await tester.runAsync(h.services.catalog.refresh);
    await show(tester, h);
    expect(find.textContaining('Item data could not be'), findsOneWidget);

    h.failNetwork = false;
    await tester.runAsync(h.services.catalog.refresh);
    await tester.pump();

    expect(find.textContaining('Item data: up to date'), findsOneWidget);
    expect(find.textContaining('Item data could not be'), findsNothing);
  });

  testWidgets('a missing flea quote time reads unknown', (tester) async {
    final h = await harness(tester);
    expect(h.services.selection.item, isNull);
    await show(tester, h);

    expect(find.text('Prices: price time unknown'), findsOneWidget);
  });

  testWidgets('Diagnostics shows source, UTC download time and record counts', (
    tester,
  ) async {
    final downloaded = DateTime.utc(2026, 11, 10, 8, 5);
    final h = await harness(tester, clock: () => downloaded);
    final snapshot = h.services.catalog.snapshot!;
    expect(snapshot.observedAt.toUtc(), downloaded);
    expect(snapshot.datasetCounts, isNotEmpty);
    await show(tester, h, diagnostics: true);

    expect(find.text('Source: ${snapshot.source}'), findsOneWidget);
    expect(
      find.text('Item data downloaded (UTC): 2026-11-10T08:05:00.000Z'),
      findsOneWidget,
    );
    for (final e in snapshot.datasetCounts.entries) {
      expect(find.text('${e.key}: ${e.value} records'), findsOneWidget);
    }
    expect(find.textContaining('Data is treated as old after'), findsOneWidget);
  });

  testWidgets('Diagnostics says there is no complete item data download', (
    tester,
  ) async {
    final h = await harness(tester, noMode: true);
    expect(h.services.catalog.snapshot, isNull);
    await show(tester, h, diagnostics: true);

    expect(find.text('No complete item data download.'), findsOneWidget);
    expect(find.textContaining('records'), findsNothing);
    expect(find.textContaining('Source:'), findsNothing);
  });

  testWidgets('Diagnostics shows when progress refresh is available again', (
    tester,
  ) async {
    final h = await harness(tester);
    final until = DateTime.now().add(const Duration(minutes: 3));
    h.services.progress
      ..status = ProgressStatus.cooldown
      ..cooldownUntil = until;
    await show(tester, h, diagnostics: true);

    final time = localTimeLabel(until, now: DateTime.now());
    expect(find.text('Refresh available again at $time'), findsOneWidget);
  });
}
