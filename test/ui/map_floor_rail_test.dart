import 'dart:ui' show CheckedState, Tristate;

import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
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

Future<void> _tabToAction(WidgetTester tester, Finder label) async {
  final action = tester.element(
    find.ancestor(of: label, matching: find.byType(InkWell)).first,
  );
  bool focused() {
    var match = false;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
      element,
    ) {
      match = element == action;
      return !match;
    });
    return match;
  }

  final visited = <String?>[];
  for (var i = 0; i < 12 && !focused(); i++) {
    await _key(tester, LogicalKeyboardKey.tab);
    visited.add(FocusManager.instance.primaryFocus?.debugLabel);
  }
  expect(
    focused(),
    isTrue,
    reason: 'Tab should reach $label (visited $visited)',
  );
}

void _expectFocusOutline(WidgetTester tester, Finder label) {
  final action = find.ancestor(of: label, matching: find.byType(InkWell)).first;
  final railLuminance = EmberColors.dark.raised.computeLuminance();
  final outlines = tester
      .widgetList<DecoratedBox>(
        find.descendant(of: action, matching: find.byType(DecoratedBox)),
      )
      .any((box) {
        if (box.decoration case BoxDecoration(border: final Border border)) {
          final ink = border.top.color.computeLuminance();
          final contrast = (ink > railLuminance)
              ? (ink + .05) / (railLuminance + .05)
              : (railLuminance + .05) / (ink + .05);
          return border.top.width >= 2 && contrast >= 3;
        }
        return false;
      });
  expect(outlines, isTrue);
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
    await _focusMap(tester);
    await _key(tester, LogicalKeyboardKey.keyF);
    final cue = find.textContaining('more above');
    await _tabToAction(tester, cue);
    _expectFocusOutline(tester, cue);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: _list, matching: find.byType(Scrollable)),
        )
        .position;
    final offset = position.pixels;
    final selection = h.services.maps.floorSelection;
    final auto = h.services.maps.automaticFloorFollowing;
    await _key(tester, LogicalKeyboardKey.enter);
    expect(position.pixels, lessThan(offset));
    expect(h.services.maps.floorSelection, same(selection));
    expect(h.services.maps.automaticFloorFollowing, auto);
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

  testWidgets('a shorter expanded rail keeps its focused row in view', (
    tester,
  ) async {
    final h = await pumpMapFixture(
      tester,
      size: const Size(1590, 860),
      extraFloors: 36,
    );
    await _focusMap(tester);
    await _key(tester, LogicalKeyboardKey.keyF);
    final selection = h.services.maps.floorSelection;
    final focus = FocusManager.instance.primaryFocus;
    expect(_row('ground').hitTestable(), findsOneWidget);

    tester.view.physicalSize = const Size(1590, 600);
    await tester.pumpAndSettle();
    expect(_list, findsOneWidget);
    expect(_row('ground').hitTestable(), findsOneWidget);
    expect(
      tester.getRect(_list).bottom,
      greaterThanOrEqualTo(tester.getRect(_row('ground')).bottom),
    );
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(h.services.maps.floorSelection, same(selection));
  });

  testWidgets('scrolling a focused list moves focus without selecting a deck', (
    tester,
  ) async {
    final h = await pumpMapFixture(
      tester,
      size: const Size(1590, 620),
      exclusiveLabs: true,
      extraFloors: 22,
    );
    await _labs(tester, h);
    await _focusMap(tester);
    await _key(tester, LogicalKeyboardKey.keyF);
    final maps = h.services.maps;
    final selection = maps.floorSelection!;
    final current = selection.visibleLayerIds.single;
    expect(maps.automaticFloorFollowing, isTrue);
    expect(_row(current).hitTestable(), findsOneWidget);

    await tester.drag(_list, const Offset(0, 380));
    await tester.pumpAndSettle();
    expect(_row(current).hitTestable(), findsNothing);
    expect(maps.floorSelection, same(selection));
    expect(maps.automaticFloorFollowing, isTrue);
    final focused = find
        .descendant(
          of: _list,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.focused == true,
          ),
        )
        .hitTestable();
    expect(focused, findsOneWidget);
    final key = tester.widget<Semantics>(focused).key! as ValueKey<String>;
    final deck = key.value.substring('map-floor-'.length);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(maps.floorSelection!.visibleLayerIds, [deck]);
    expect(maps.automaticFloorFollowing, isFalse);
    await settleMapFixture(tester, h);
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

  testWidgets('modified floor letters leave Auto and focus alone', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _labs(tester, h);
    await _focusMap(tester);
    Future<void> controlLetters() async {
      final original = FocusManager.instance.primaryFocus;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await _key(tester, LogicalKeyboardKey.keyA);
      await _key(tester, LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(FocusManager.instance.primaryFocus, same(original));
      expect(h.services.maps.automaticFloorFollowing, isTrue);
    }

    await controlLetters();
    await _key(tester, LogicalKeyboardKey.keyF);
    final auto = _text('Auto');
    await _tabToAction(tester, auto);
    _expectFocusOutline(tester, auto);
    await controlLetters();
  });

  testWidgets('a focused rail that disappears returns focus to the map', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester, singleFloor: true);
    await _labs(tester, h);
    await tester.tap(_row('ground'));
    await tester.pump();
    await tester.runAsync(() => h.services.settings.setMap('shoreline'));
    await settleMapFixture(tester, h);
    expect(_rail, findsNothing);
    final maps = h.services.maps;
    final before = maps.transform.translationX;
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(maps.transform.translationX, before - 40);
    await settleMapFixture(tester, h);
  });

  testWidgets('a step toast does not return after switching maps', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _focusMap(tester);
    await _key(tester, LogicalKeyboardKey.pageUp);
    final toast = find.byKey(const Key('map-floor-toast'));
    expect(toast, findsOneWidget);
    for (final id in ['thelab', 'shoreline']) {
      await tester.runAsync(() => h.services.settings.setMap(id));
      await tester.pump();
      expect(h.services.maps.selectedMapId, id);
      expect(toast, findsNothing);
    }
    await settleMapFixture(tester, h);
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
    await resize(140);
    expect(_text('Deck 8'), findsOneWidget);
    expect(_list, findsNothing);
    await resize(280);
    await tester.pump();
    expect(_text('16 floors'), findsOneWidget);
    expect(_row('deck-8').hitTestable(), findsOneWidget);
    expect(_text('4 more above'), findsOneWidget);
    expect(_text('7 more below'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse floors'));
    await tester.pump();
    final rail = tester.state<MapFloorRailState>(find.byType(MapFloorRail));
    rail.focusCurrent();
    await tester.pumpAndSettle();
    expect(rail.hasFocus, isTrue);
    await resize(140);
    await tester.pumpAndSettle();
    expect(rail.hasFocus, isTrue);
    expect(_list, findsNothing);
    await resize(280);
    await tester.pumpAndSettle();
    expect(_list, findsNothing);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_list, findsOneWidget);
    expect(_row('deck-8').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
