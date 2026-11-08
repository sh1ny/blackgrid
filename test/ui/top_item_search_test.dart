import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/top_item_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_harness.dart';
import '../support/m1_widget_harness.dart' show tapM1Async;

Future<M1Harness> _showSearch(
  WidgetTester tester, {
  bool many = false,
  Brightness room = Brightness.dark,
  double scale = 1,
}) async {
  final h = (await tester.runAsync(() async {
    final result = M1Harness(
      shapeWire: many
          ? (wire) {
              final items = wire['items']['data']['items'] as Map;
              final template = Map<String, dynamic>.from(
                items['item-a'] as Map,
              );
              for (var i = 0; i < 55; i++) {
                final suffix = i.toString().padLeft(2, '0');
                items['option-$suffix'] = {
                  ...template,
                  'id': 'option-$suffix',
                  'name': 'Option $suffix',
                  'normalizedName': 'option-$suffix',
                };
              }
            }
          : null,
    );
    await result.initialize();
    return result;
  }))!;
  final query = TextEditingController();
  final focus = FocusNode();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    query.dispose();
    focus.dispose();
    await h.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: blackgridTheme(room),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 500,
            child: TopItemSearch(
              services: h.services,
              controller: query,
              focusNode: focus,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('typing and Escape do not select or record an item', (
    tester,
  ) async {
    final h = await _showSearch(tester);
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, 'component');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('top-search-results')), findsOneWidget);
    expect(h.services.selection.selectedId, isNull);
    expect((await tester.runAsync(h.db.readActivity))!.rows, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('top-search-results')), findsNothing);
    expect(h.services.selection.selectedId, isNull);
    expect((await tester.runAsync(h.db.readActivity))!.rows, isEmpty);
  });

  testWidgets('mouse chooses one anchored result and records only that item', (
    tester,
  ) async {
    final h = await _showSearch(tester);
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, 'component');
    await tester.pumpAndSettle();
    final expected = h.services.selection.results.last.id;
    final popup = find.byKey(const Key('top-search-results'));
    final options = find.descendant(of: popup, matching: find.byType(ListTile));
    await tapM1Async(
      tester,
      options.last,
      () => h.services.history.rows.length == 1,
    );
    expect(h.services.selection.selectedId, expected);
    expect(h.services.history.rows.single.itemId, expected);
    expect(find.byKey(const Key('top-search-results')), findsNothing);
  });

  for (final room in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'search caps options and keeps the keyboard highlight visible $room scale=$scale',
        (tester) async {
          final h = await _showSearch(
            tester,
            many: true,
            room: room,
            scale: scale,
          );
          final field = find.byType(TextField);
          await tester.tap(field);
          await tester.enterText(field, 'Option');
          await tester.pumpAndSettle();
          expect(h.services.selection.results.length, 55);
          final popup = find.byKey(const Key('top-search-results'));
          final list = tester.widget<ListView>(
            find.descendant(of: popup, matching: find.byType(ListView)),
          );
          expect(list.childrenDelegate.estimatedChildCount, 50);
          expect(
            find.text('Showing 50 items. Refine your search.'),
            findsOneWidget,
          );
          final options = h.services.selection.results;
          for (var i = 0; i < 12; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pumpAndSettle();
          }
          final active = find.descendant(
            of: popup,
            matching: find.byWidgetPredicate(
              (w) => w is ListTile && w.selected,
            ),
          );
          expect(active, findsOneWidget);
          expect(
            tester.getRect(active).top,
            greaterThanOrEqualTo(tester.getRect(popup).top),
          );
          expect(
            tester.getRect(active).bottom,
            lessThanOrEqualTo(tester.getRect(popup).bottom),
          );
          expect(h.services.selection.selectedId, isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.runAsync(h.services.history.load);
          await tester.pumpAndSettle();
          expect(h.services.selection.selectedId, options[12].id);
          expect(
            (await tester.runAsync(h.db.readActivity))!.rows.single.itemId,
            options[12].id,
          );
        },
      );
    }
  }

  testWidgets(
    'a mode change dismisses stale anchored options without recording',
    (tester) async {
      final h = await _showSearch(tester);
      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.enterText(field, 'component');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('top-search-results')), findsOneWidget);
      await tester.runAsync(() => h.services.setMode(GameMode.pve));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('top-search-results')), findsNothing);
      expect(h.services.selection.selectedId, isNull);
      expect((await tester.runAsync(h.db.readActivity))!.rows, isEmpty);
    },
  );
}
