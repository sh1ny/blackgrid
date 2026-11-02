import 'dart:async';

import 'package:blackgrid/application/local_stats_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_stats.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:blackgrid/ui/stats_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LocalStatsTotals _totals({
  Map<String?, int> maps = const {},
  int sales = 0,
  int items = 0,
  int roubles = 0,
  int notRoubles = 0,
}) => LocalStatsTotals(
  raidsByMap: maps,
  raidTotal: maps.values.fold(0, (a, b) => a + b),
  sales: sales,
  items: items,
  roubles: roubles,
  salesNotInRoubles: notRoubles,
);

/// A store whose totals per mode are set by the test.
final class _FakeStore implements LocalStatsStore {
  final totalsByMode = <GameMode, LocalStatsTotals>{};
  DateTime? sinceValue;
  bool failRead = false;
  bool failRecord = false;
  bool failClear = false;
  final cleared = <DateTime>[];

  @override
  Future<void> recordRaid(RaidStatRow row) async {
    if (failRecord) throw StateError('record');
  }

  @override
  Future<void> recordSale(FleaSaleRow row) async {
    if (failRecord) throw StateError('record');
    final current = totalsByMode[GameMode.pvp] ?? LocalStatsTotals.empty;
    totalsByMode[GameMode.pvp] = _totals(
      maps: current.raidsByMap,
      sales: current.sales + 1,
      items: current.items + row.count,
      roubles: current.roubles + (row.roubles ?? 0),
    );
  }

  @override
  Future<LocalStatsTotals> readTotals(GameMode mode) async {
    if (failRead) throw StateError('read');
    return totalsByMode[mode] ?? LocalStatsTotals.empty;
  }

  @override
  Future<DateTime?> readSince() async => sinceValue;

  @override
  Future<void> clear(DateTime now) async {
    if (failClear) throw StateError('clear');
    cleared.add(now);
    sinceValue = now;
    totalsByMode.clear();
  }
}

void main() {
  late StreamController<RaidTransition> lifecycle;
  late ValueNotifier<GameMode> mode;
  late _FakeStore store;
  late LocalStatsController controller;

  Future<void> open(
    WidgetTester tester, {
    GameMode initial = GameMode.pvp,
  }) async {
    mode.value = initial;
    controller = LocalStatsController(
      transitions: lifecycle.stream,
      modeChanges: mode,
      mode: () => mode.value,
      store: store,
      clock: () => DateTime(2026, 11, 2, 9),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showStats(context, controller),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    lifecycle = StreamController<RaidTransition>.broadcast(sync: true);
    mode = ValueNotifier(GameMode.pvp);
    store = _FakeStore();
  });

  tearDown(() async {
    await lifecycle.close();
    mode.dispose();
  });

  testWidgets("shows the current mode's maps by count, total and sales", (
    tester,
  ) async {
    store.totalsByMode[GameMode.pvp] = _totals(
      maps: {'woods': 1, 'customs': 3},
      sales: 2,
      items: 5,
      roubles: 2000,
    );
    store.totalsByMode[GameMode.pve] = _totals(maps: {'lighthouse': 9});
    store.sinceValue = DateTime(2020, 3, 3, 8, 30);
    await open(tester);

    expect(find.text('PvP stats'), findsOneWidget);
    final customs = find.byKey(const Key('stats-map-customs'));
    final woods = find.byKey(const Key('stats-map-woods'));
    expect(
      find.descendant(of: customs, matching: find.text('Customs')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: customs, matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: woods, matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(customs).dy,
      lessThan(tester.getTopLeft(woods).dy),
    );
    expect(find.text('Raids counted: 4'), findsOneWidget);
    expect(find.text('Flea sales: 2'), findsOneWidget);
    expect(find.text('Items sold: 5'), findsOneWidget);
    expect(find.text('Roubles earned: ₽2000'), findsOneWidget);
    expect(find.textContaining('not paid in roubles'), findsNothing);
    expect(find.text('Lighthouse'), findsNothing);
    expect(find.text('Counted since 3 Mar 08:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown map shows as Unknown map and sales not in roubles '
      'are noted', (tester) async {
    store.totalsByMode[GameMode.pvp] = _totals(
      maps: {null: 2},
      sales: 3,
      items: 3,
      roubles: 100,
      notRoubles: 1,
    );
    await open(tester);

    expect(find.text('Unknown map'), findsOneWidget);
    expect(find.text('1 sale not paid in roubles'), findsOneWidget);
    expect(find.text('Counted since stats began'), findsOneWidget);
  });

  testWidgets('empty mode shows no raids or flea sales message', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('No raids or flea sales counted yet.'), findsOneWidget);
    expect(find.textContaining('Raids counted'), findsNothing);
  });

  testWidgets('an unknown mode says stats show once the mode is known', (
    tester,
  ) async {
    await open(tester, initial: GameMode.unknown);

    expect(
      find.text('Stats show once the game mode is known.'),
      findsOneWidget,
    );
    expect(find.text('No raids or flea sales counted yet.'), findsNothing);
    expect(find.textContaining('Raids counted'), findsNothing);
  });

  testWidgets('a mode change while open shows the other mode', (tester) async {
    store.totalsByMode[GameMode.pvp] = _totals(maps: {'customs': 3});
    store.totalsByMode[GameMode.pve] = _totals(maps: {'woods': 7});
    await open(tester);
    expect(find.text('Customs'), findsOneWidget);

    mode.value = GameMode.pve;
    await tester.pumpAndSettle();

    expect(find.text('PvE stats'), findsOneWidget);
    expect(find.text('Woods'), findsOneWidget);
    expect(find.text('Customs'), findsNothing);
  });

  testWidgets('a new sale while open raises the shown count', (tester) async {
    store.totalsByMode[GameMode.pvp] = _totals(sales: 2, items: 2);
    await open(tester);
    expect(find.text('Flea sales: 2'), findsOneWidget);

    lifecycle.add(
      FleaSoldTransition(
        LogRecordId('log_a', LogFile.application, 1),
        DateTime(2026, 11, 2, 9),
        'item',
        1,
        500,
        GameMode.pvp,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Flea sales: 3'), findsOneWidget);
  });

  testWidgets('read, write and clear failures each show their own message', (
    tester,
  ) async {
    store
      ..failRead = true
      ..failRecord = true
      ..failClear = true;
    await open(tester);
    lifecycle.add(
      FleaSoldTransition(
        LogRecordId('log_a', LogFile.application, 1),
        DateTime(2026, 11, 2, 9),
        'item',
        1,
        500,
        GameMode.pvp,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear stats'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text(localStatsReadErrorMessage), findsOneWidget);
    expect(find.text(localStatsWriteErrorMessage), findsOneWidget);
    expect(find.text(localStatsClearErrorMessage), findsOneWidget);
  });

  testWidgets('closing the dialog dismisses the clear message', (tester) async {
    store.failClear = true;
    await open(tester);
    await tester.tap(find.text('Clear stats'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(controller.clearError, localStatsClearErrorMessage);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(controller.clearError, isNull);
  });

  testWidgets('confirming clear empties the stats', (tester) async {
    store.totalsByMode[GameMode.pvp] = _totals(maps: {'customs': 3}, sales: 1);
    await open(tester);
    await tester.tap(find.text('Clear stats'));
    await tester.pumpAndSettle();

    expect(
      find.text('Clear the stats of every mode? This cannot be undone.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(store.cleared, [DateTime(2026, 11, 2, 9)]);
    expect(find.text('No raids or flea sales counted yet.'), findsOneWidget);
    expect(find.text('Customs'), findsNothing);
    expect(
      find.text('Clear the stats of every mode? This cannot be undone.'),
      findsNothing,
    );
  });

  testWidgets('cancelling clear deletes nothing', (tester) async {
    store.totalsByMode[GameMode.pvp] = _totals(maps: {'customs': 3}, sales: 1);
    await open(tester);
    await tester.tap(find.text('Clear stats'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(store.cleared, isEmpty);
    expect(find.text('Customs'), findsOneWidget);
    expect(
      find.text('Clear the stats of every mode? This cannot be undone.'),
      findsNothing,
    );
  });
}
