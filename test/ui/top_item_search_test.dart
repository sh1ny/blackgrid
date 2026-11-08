import 'dart:ui' show PointerDeviceKind;

import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/top_item_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_harness.dart';

Future<M1Harness> _showSearch(
  WidgetTester tester, {
  bool many = false,
  bool longNames = false,
  int matchCount = 55,
  double width = 500,
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
              for (var i = 0; i < matchCount; i++) {
                final suffix = i.toString().padLeft(2, '0');
                final nameKey = 'option-$suffix Name';
                wire['items_en']['data'][nameKey] = longNames
                    ? 'Option $suffix ${List.filled(40, 'component').join(' ')}'
                    : 'Option $suffix';
                items['option-$suffix'] = {
                  ...template,
                  'id': 'option-$suffix',
                  'name': nameKey,
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
            width: width,
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
  testWidgets('held arrow keys navigate anchored results', (tester) async {
    await _showSearch(tester, many: true);
    final field = find.byType(TextField);
    await tester.enterText(field, 'Option');
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 2);
    final caret = controller.selection;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final active = tester.widget<ListTile>(
      find.byWidgetPredicate((widget) => widget is ListTile && widget.selected),
    );
    expect((active.title! as Text).data, 'Option 02');
    expect(controller.selection, caret);
  });

  for (final width in [150.0, 500.0]) {
    testWidgets('long result names fit scaled rows width=$width', (
      tester,
    ) async {
      await _showSearch(
        tester,
        many: true,
        longNames: true,
        matchCount: 3,
        width: width,
        scale: 2,
      );
      await tester.enterText(find.byType(TextField), 'Option');
      await tester.pumpAndSettle();
      final row = find.byType(ListTile).first;
      final title = find.descendant(of: row, matching: find.byType(Text)).first;
      final rowRect = tester.getRect(row);
      final titleRect = tester.getRect(title);
      expect(titleRect.top, greaterThanOrEqualTo(rowRect.top));
      expect(titleRect.bottom, lessThanOrEqualTo(rowRect.bottom));
      final text = tester.widget<Text>(title).data!;
      expect(find.byTooltip(text), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow scaled result cap keeps options reachable', (
    tester,
  ) async {
    await _showSearch(tester, many: true, width: 150, scale: 2);
    await tester.enterText(find.byType(TextField), 'Option');
    await tester.pumpAndSettle();
    expect(find.text('50 shown\nRefine'), findsOneWidget);
    expect(find.byType(ListTile).hitTestable(), findsWidgets);
    expect(tester.takeException(), isNull);
  });

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
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final point = tester.getCenter(options.last);
    await tester.runAsync(() async {
      await mouse.addPointer(location: point);
      await mouse.down(point);
    });
    // A real desktop click can span frames. The popup must survive the down
    // event so its result still receives the later up event.
    await tester.pump();
    expect(popup, findsOneWidget);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.runAsync(() => mouse.up());
    // Advance the native database work and the widget zone together. Each
    // read is an I/O completion signal, rather than an arbitrary time delay.
    for (var step = 0; h.services.history.rows.isEmpty && step < 20; step++) {
      await tester.runAsync(h.db.readActivity);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(h.services.selection.selectedId, expected);
    expect(h.services.history.rows, hasLength(1));
    expect(h.services.history.rows.single.itemId, expected);
    expect(find.byKey(const Key('top-search-results')), findsNothing);
  });

  testWidgets('mouse outside search dismisses without selecting or recording', (
    tester,
  ) async {
    final h = await _showSearch(tester);
    final field = find.byType(TextField);
    await tester.enterText(field, 'component');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('top-search-results')), findsOneWidget);
    await tester.tapAt(const Offset(20, 400), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('top-search-results')), findsNothing);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
    expect(h.services.selection.selectedId, isNull);
    expect((await tester.runAsync(h.db.readActivity))!.rows, isEmpty);
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
