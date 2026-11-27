import 'dart:ui' show CheckedState, Tristate;

import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/ui/map_floor_rail.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/map_widget_harness.dart';

Finder get _rail => find.byKey(const Key('map-floor-control'));
Finder get _list => find.byKey(const Key('map-floor-list'));
Finder get _map => find.byKey(const Key('native-map-viewport'));
Finder _row(String id) => find.byKey(ValueKey('map-floor-$id'));
Finder _text(String text) =>
    find.descendant(of: _rail, matching: find.text(text));

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump();
}

Future<void> _focusMap(WidgetTester tester) async {
  await tester.tapAt(tester.getRect(_map).centerRight - const Offset(80, 50));
  await tester.pump();
}

Future<void> _labs(WidgetTester tester, MapWidgetHarness harness) async {
  await tester.runAsync(() => harness.services.settings.setMap('thelab'));
  await settleMapFixture(tester, harness);
}

void main() {
  testWidgets('a manual deck choice checks exactly one floor', (tester) async {
    final h = await pumpMapFixture(tester, exclusiveLabs: true, extraFloors: 1);
    await _labs(tester, h);
    await tester.tap(_row('upper'));
    await settleMapFixture(tester, h);
    expect(h.services.maps.floorSelection!.visibleLayerIds, ['upper']);
    expect(
      tester
          .getSemantics(_row('upper'))
          .getSemanticsData()
          .flagsCollection
          .isChecked,
      CheckedState.isTrue,
    );
    expect(
      tester
          .getSemantics(_row('ground'))
          .getSemanticsData()
          .flagsCollection
          .isChecked,
      CheckedState.isFalse,
    );
    await tester.tap(_row('upper'));
    await tester.pump();
    expect(h.services.maps.floorSelection!.visibleLayerIds, ['upper']);
  });

  testWidgets('checked overlays retain the base and show the ground divider', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester, extraFloors: 1);
    await tester.tap(_row('upper'));
    await settleMapFixture(tester, h);
    await tester.tap(_row('lower'));
    await settleMapFixture(tester, h);
    expect(h.services.maps.floorSelection!.visibleLayerIds, [
      'lower',
      'ground',
      'upper',
    ]);
    expect(_text('base'), findsOneWidget);
    expect(
      tester.getCenter(_row('upper')).dy,
      lessThan(tester.getCenter(_row('ground')).dy),
    );
    expect(
      tester.getCenter(_text('Below ground')).dy,
      inExclusiveRange(
        tester.getCenter(_row('ground')).dy,
        tester.getCenter(_row('lower')).dy,
      ),
    );
    await tester.tap(find.byTooltip('Collapse floors'));
    await tester.pump();
    expect(_text('Upper'), findsOneWidget);
  });

  testWidgets('multiple manual floors have no Auto switch', (tester) async {
    await pumpMapFixture(tester);
    expect(_row('upper'), findsOneWidget);
    expect(_text('Auto'), findsNothing);
  });

  testWidgets('a single Auto floor has no adjacent step', (tester) async {
    final h = await pumpMapFixture(tester, singleFloor: true);
    await _labs(tester, h);
    expect(_text('Auto'), findsOneWidget);
    expect(_row('ground'), findsOneWidget);
    for (final id in ['up', 'down']) {
      expect(
        tester
            .widget<IconButton>(find.byKey(ValueKey('map-floor-step-$id')))
            .onPressed,
        isNull,
      );
    }
  });

  testWidgets('a single manual floor has no rail', (tester) async {
    await pumpMapFixture(tester, singleFloor: true);
    expect(_rail, findsNothing);
  });

  testWidgets('a scrolled rail counts both clipped edges', (tester) async {
    final h = await pumpMapFixture(
      tester,
      size: const Size(1590, 680),
      extraFloors: 36,
    );
    final before = h.services.maps.transform;
    expect(find.textContaining('more above'), findsOneWidget);
    await tester.drag(_list, const Offset(0, 250));
    await tester.pumpAndSettle();
    expect(find.textContaining('more above'), findsOneWidget);
    expect(find.textContaining('more below'), findsOneWidget);
    expect(h.services.maps.transform, same(before));
  });

  testWidgets('growing the viewport clears both overflow cues', (tester) async {
    await pumpMapFixture(tester, size: const Size(1590, 590), extraFloors: 19);
    expect(find.textContaining('more above'), findsOneWidget);
    tester.view.physicalSize = const Size(1660, 1080);
    await tester.pumpAndSettle();
    expect(find.textContaining('more above'), findsNothing);
    expect(find.textContaining('more below'), findsNothing);
    expect(_row('lower').hitTestable(), findsOneWidget);
    expect(_row('deck-18').hitTestable(), findsOneWidget);
  });

  testWidgets('the compact line retains current floor and Auto', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _labs(tester, h);
    h.services.maps.setPlayerSample(GamePoint(128, 128, height: 4));
    await settleMapFixture(tester, h);
    final selection = h.services.maps.floorSelection;
    await tester.tap(find.byTooltip('Collapse floors'));
    await tester.pump();
    expect(_text('Upper'), findsOneWidget);
    expect(_text('Auto'), findsOneWidget);
    expect(_text('Following you'), findsNothing);
    await tester.tap(find.byTooltip('Expand floors'));
    await tester.pumpAndSettle();
    expect(_text('Following you'), findsOneWidget);
    expect(h.services.maps.floorSelection, same(selection));
  });

  testWidgets('You remains on the sampled floor when Auto is off', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _labs(tester, h);
    h.services.maps.setPlayerSample(GamePoint(128, 128, height: 4));
    await settleMapFixture(tester, h);
    await tester.tap(_row('ground'));
    await settleMapFixture(tester, h);
    expect(_text('Off'), findsOneWidget);
    expect(
      find.descendant(of: _row('upper'), matching: find.text('You')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _row('ground'), matching: find.text('You')),
      findsNothing,
    );
  });

  testWidgets('unresolved position keeps selection and shows waiting', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _labs(tester, h);
    h.services.maps.setPlayerSample(GamePoint(128, 128, height: 4));
    await settleMapFixture(tester, h);
    h.services.maps.setPlayerSample(GamePoint(128, 128));
    await tester.pump();
    expect(_text('Waiting for a position'), findsOneWidget);
    expect(_text('You'), findsNothing);
    expect(h.services.maps.floorSelection!.selectedOverlayIds, {'upper'});
  });

  testWidgets('enabling Auto immediately shows the known floor', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _labs(tester, h);
    final maps = h.services.maps;
    maps.setAutomaticFloorFollowing(false);
    maps.setPlayerSample(GamePoint(128, 128, height: 4));
    await tester.pump();
    await tester.tap(_text('Auto'));
    await settleMapFixture(tester, h);
    expect(_text('Following you'), findsOneWidget);
    expect(maps.floorSelection!.selectedOverlayIds, {'upper'});
  });

  testWidgets('A updates the Auto tag without expanding the rail', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _labs(tester, h);
    await tester.tap(find.byTooltip('Collapse floors'));
    await tester.pump();
    await _focusMap(tester);
    await _key(tester, LogicalKeyboardKey.keyA);
    expect(_text('Auto'), findsNothing);
    expect(find.byTooltip('Expand floors'), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.keyA);
    expect(_text('Auto'), findsOneWidget);
    expect(find.byTooltip('Expand floors'), findsOneWidget);
  });

  testWidgets('a step replaces overlays and announces the destination', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester, extraFloors: 2);
    final maps = h.services.maps;
    maps.toggleFloor('lower');
    maps.toggleFloor('deck-1');
    await settleMapFixture(tester, h);
    await _focusMap(tester);
    await _key(tester, LogicalKeyboardKey.pageDown);
    expect(maps.floorSelection!.visibleLayerIds, ['ground', 'deck-0']);
    final toast = find.byKey(const Key('map-floor-toast'));
    expect(find.text('Floor: Deck 1, 4 of 5'), findsOneWidget);
    expect(
      tester
          .getSemantics(toast)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 2600));
    expect(toast, findsNothing);
    await settleMapFixture(tester, h);
  });

  testWidgets('a boundary step keeps selection and Auto', (tester) async {
    final h = await pumpMapFixture(tester);
    await _labs(tester, h);
    h.services.maps.setPlayerSample(GamePoint(128, 128, height: 4));
    await settleMapFixture(tester, h);
    final selection = h.services.maps.floorSelection;
    await _focusMap(tester);
    await _key(tester, LogicalKeyboardKey.pageUp);
    expect(h.services.maps.automaticFloorFollowing, isTrue);
    expect(h.services.maps.floorSelection, same(selection));
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('map-floor-step-up')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('exclusive keyboard traversal selects and reveals the deck', (
    tester,
  ) async {
    final h = await pumpMapFixture(
      tester,
      size: const Size(1590, 680),
      extraFloors: 36,
      exclusiveLabs: true,
    );
    await _labs(tester, h);
    await _focusMap(tester);
    await _key(tester, LogicalKeyboardKey.keyF);
    await _key(tester, LogicalKeyboardKey.home);
    expect(h.services.maps.floorSelection!.visibleLayerIds, ['deck-35']);
    expect(_row('deck-35').hitTestable(), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.end);
    expect(h.services.maps.floorSelection!.visibleLayerIds, ['lower']);
    expect(_row('lower').hitTestable(), findsOneWidget);
    final data = tester.getSemantics(_row('lower')).getSemanticsData();
    expect(data.label, 'Lower');
    expect(data.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(data.flagsCollection.isChecked, CheckedState.isTrue);
    await settleMapFixture(tester, h);
  });

  testWidgets(
    'additive keyboard traversal moves focus before changing visibility',
    (tester) async {
      final h = await pumpMapFixture(tester, extraFloors: 1);
      await _focusMap(tester);
      await _key(tester, LogicalKeyboardKey.keyF);
      await _key(tester, LogicalKeyboardKey.arrowUp);
      expect(h.services.maps.floorSelection!.visibleLayerIds, ['ground']);
      await _key(tester, LogicalKeyboardKey.space);
      expect(h.services.maps.floorSelection!.visibleLayerIds, [
        'ground',
        'upper',
      ]);
      expect(
        tester.getSemantics(_row('ground')).getSemanticsData().label,
        contains('always drawn'),
      );
      expect(
        tester
            .getSemantics(_row('upper'))
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isTrue,
      );
      await settleMapFixture(tester, h);
    },
  );

  testWidgets('expanding from the keyboard focuses the current row', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester, extraFloors: 1);
    await tester.tap(find.byTooltip('Collapse floors'));
    await tester.pump();
    await _focusMap(tester);
    await _key(tester, LogicalKeyboardKey.keyF);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(h.services.maps.floorSelection!.visibleLayerIds, ['ground']);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(h.services.maps.floorSelection!.visibleLayerIds, [
      'ground',
      'upper',
    ]);
    await settleMapFixture(tester, h);
  });

  testWidgets('collapsing from the keyboard moves focus to Expand', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _focusMap(tester);
    await _key(tester, LogicalKeyboardKey.keyF);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _key(tester, LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(find.byTooltip('Expand floors'), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.pageUp);
    expect(h.services.maps.floorSelection!.visibleLayerIds, [
      'ground',
      'upper',
    ]);
    await settleMapFixture(tester, h);
  });

  testWidgets('a short map pane keeps the stepper until the list fits again', (
    tester,
  ) async {
    final preview = floorRailPreview();
    Future<void> resize(double height) => tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 220, height: height, child: preview),
        ),
      ),
    );
    await resize(60);
    expect(_text('Deck 7'), findsOneWidget);
    expect(_list, findsNothing);
    await tester.tap(find.byTooltip('Floor up'));
    await tester.pump();
    expect(_text('Deck 8'), findsOneWidget);
    await resize(280);
    await tester.pump();
    expect(_text('16 floors'), findsOneWidget);
    expect(_row('deck-8').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
