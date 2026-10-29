import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/progress_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_harness.dart';

/// Owns the Details flag the way the screen does, so a test can tap Details.
class _Host extends StatefulWidget {
  const _Host(this.h);

  final M1Harness h;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => SourcePanel(
    services: widget.h.services,
    detailsExpanded: _expanded,
    onDetailsExpandedChanged: (value) => setState(() => _expanded = value),
  );
}

void main() {
  Future<M1Harness> harness(WidgetTester tester, {bool noMode = false}) async {
    final h = (await tester.runAsync(() async {
      final result = M1Harness();
      await result.initialize(
        mode: noMode ? GameMode.unknown : GameMode.pvp,
        refresh: !noMode,
      );
      return result;
    }))!;
    addTearDown(h.dispose);
    return h;
  }

  Future<void> show(WidgetTester tester, M1Harness h) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: blackgridTheme(),
        home: Scaffold(body: _Host(h)),
      ),
    );
    await tester.pump();
  }

  Future<void> openDetails(WidgetTester tester) async {
    await tester.tap(find.text('Details'));
    await tester.pump();
  }

  testWidgets(
    'current item data says up to date with its local time and hides the URL',
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
      expect(find.textContaining(snapshot.source), findsNothing);
      expect(
        find.textContaining(snapshot.observedAt.toUtc().toIso8601String()),
        findsNothing,
      );

      await openDetails(tester);

      expect(find.textContaining(snapshot.source), findsOneWidget);
      expect(
        find.textContaining(snapshot.observedAt.toUtc().toIso8601String()),
        findsWidgets,
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

  testWidgets('cooldown is said in the open and its end time only in Details', (
    tester,
  ) async {
    final h = await harness(tester);
    final until = DateTime.now().add(const Duration(minutes: 3));
    h.services.progress
      ..status = ProgressStatus.cooldown
      ..cooldownUntil = until;
    await show(tester, h);

    expect(
      find.text(
        'Tracker progress: ${progressStatusLabel(ProgressStatus.cooldown)}',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('cooling down'), findsWidgets);
    expect(find.textContaining('available again'), findsNothing);
    expect(find.textContaining(until.toUtc().toIso8601String()), findsNothing);

    await openDetails(tester);

    final time = localTimeLabel(until, now: DateTime.now());
    expect(find.text('Refresh available again at $time'), findsOneWidget);
  });

  testWidgets('a missing flea quote time reads unknown', (tester) async {
    final h = await harness(tester);
    expect(h.services.selection.item, isNull);
    await show(tester, h);

    expect(find.text('Prices: price time unknown'), findsOneWidget);
  });
}
