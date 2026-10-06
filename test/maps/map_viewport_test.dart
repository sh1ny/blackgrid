import 'dart:ui' as ui;

import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/app.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';
import '../support/map_widget_harness.dart';

Finder get _viewport => find.byKey(const Key('native-map-viewport'));

// Match the button by its icon, independent of a count that changes on filtering.
Finder get _markerBrowser => find.ancestor(
  of: find.byIcon(Icons.list),
  matching: find.byType(OutlinedButton),
);

Offset _project(WidgetTester tester, MapWidgetHarness h, ScenePoint point) {
  final projected = h.services.maps.transform.sceneToViewport(point);
  return tester.getTopLeft(_viewport) + Offset(projected.x, projected.y);
}

Future<void> _wheel(
  WidgetTester tester,
  MapWidgetHarness h,
  Offset position,
  double delta,
) async {
  tester.binding.handlePointerEvent(
    PointerScrollEvent(position: position, scrollDelta: Offset(0, delta)),
  );
  await settleMapFixture(tester, h);
}

void main() {
  testWidgets('map navigation keys stop at the focused viewport', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    final app = tester.widget<BlackgridApp>(find.byType(BlackgridApp));
    final bubbled = <KeyEvent>[];
    await tester.pumpWidget(
      Focus(
        onKeyEvent: (_, event) {
          bubbled.add(event);
          return KeyEventResult.ignored;
        },
        child: app,
      ),
    );
    await settleMapFixture(tester, h);
    await tester.tapAt(_project(tester, h, ScenePoint(128, 128)));
    await settleMapFixture(tester, h);
    expect(find.text('Ground exit'), findsOneWidget);
    final maps = h.services.maps;
    final before = maps.transform;
    for (final navigation in [
      (LogicalKeyboardKey.arrowLeft, 40.0, 0.0),
      (LogicalKeyboardKey.arrowRight, -40.0, 0.0),
      (LogicalKeyboardKey.arrowUp, 0.0, 40.0),
      (LogicalKeyboardKey.arrowDown, 0.0, -40.0),
    ]) {
      final transform = maps.transform;
      bubbled.clear();
      await tester.sendKeyDownEvent(navigation.$1);
      await settleMapFixture(tester, h);
      expect(
        maps.transform.translationX,
        transform.translationX + navigation.$2,
      );
      expect(
        maps.transform.translationY,
        transform.translationY + navigation.$3,
      );
      expect(bubbled, isEmpty);
      await tester.sendKeyRepeatEvent(navigation.$1);
      await settleMapFixture(tester, h);
      expect(
        maps.transform.translationX,
        transform.translationX + 2 * navigation.$2,
      );
      expect(
        maps.transform.translationY,
        transform.translationY + 2 * navigation.$3,
      );
      expect(bubbled, isEmpty);
      await tester.sendKeyUpEvent(navigation.$1);
    }
    maps.panBy(70, 20);
    bubbled.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.home);
    await settleMapFixture(tester, h);
    expect(maps.transform.translationX, closeTo(before.translationX, 1e-9));
    expect(maps.transform.translationY, closeTo(before.translationY, 1e-9));
    expect(bubbled, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.home);
    bubbled.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await settleMapFixture(tester, h);
    expect(find.text('Ground exit'), findsNothing);
    expect(bubbled, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    bubbled.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
    expect(bubbled.single.logicalKey, LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
    expect(tester.takeException(), isNull);
  });

  for (final map in ['shoreline', 'thelab']) {
    testWidgets(
      '$map overflowing saved pin stays editable without paint errors',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final h = await pumpMapFixture(tester);
          if (map != 'shoreline') {
            await tester.runAsync(() => h.services.settings.setMap(map));
            await settleMapFixture(tester, h);
          }
          final pin = CustomPin(
            id: 'extreme-pin',
            mapId: map,
            x: 1e308,
            y: -1e308,
            frame: map == 'thelab'
                ? 'labs-native-normalized'
                : 'legacy-normalized',
            frameRevision: map == 'thelab' ? 1 : 0,
            label: 'Extreme saved pin',
            updatedAt: DateTime.utc(2026),
          );
          expect(
            await tester.runAsync(() => h.services.settings.savePin(pin)),
            isTrue,
          );
          await settleMapFixture(tester, h);
          final stored = (await tester.runAsync(
            () => h.services.database.readPins(),
          ))!.single;
          expect(stored.x, 1e308);
          expect(stored.y, -1e308);
          expect(h.services.maps.projectPin(stored), isNull);
          expect(
            find.semantics.byLabel('Extreme saved pin, saved pin').evaluate(),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(_markerBrowser);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ListTile, 'Extreme saved pin'));
          await settleMapFixture(tester, h);
          await tester.tap(find.text('Edit pin'));
          await tester.pumpAndSettle();
          final x = find.widgetWithText(TextField, 'Normalized X');
          final y = find.widgetWithText(TextField, 'Normalized Y');
          expect(
            double.parse(tester.widget<TextField>(x).controller!.text),
            1e308,
          );
          expect(
            double.parse(tester.widget<TextField>(y).controller!.text),
            -1e308,
          );
          await tester.enterText(x, '.5');
          await tester.enterText(y, '.5');
          await tapM1Async(
            tester,
            find.text('Save pin'),
            () => h.services.settings.pins.single.x == .5,
          );
          expect(
            h.services.maps.projectPin(h.services.settings.pins.single),
            isNotNull,
          );
          expect(h.services.scans.hasAcceptedScan, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('intersecting hazard remains painted with its anchor offscreen', (
    tester,
  ) async {
    final h = await pumpMapFixture(
      tester,
      hazardOutline: [
        {'x': -64, 'z': 224},
        {'x': 160, 'z': 224},
        {'x': 160, 'z': 160},
        {'x': -64, 'z': 160},
      ],
    );
    final maps = h.services.maps;
    final anchor = maps.transform.sceneToViewport(ScenePoint(64, 64));
    maps.panBy(-40 - anchor.x, 0);
    await settleMapFixture(tester, h);
    expect(maps.transform.sceneToViewport(ScenePoint(64, 64)).x, lessThan(-22));
    final sample = maps.transform.sceneToViewport(ScenePoint(128, 64));
    final size = tester.getSize(_viewport);
    expect(sample.x, inExclusiveRange(0, size.width));
    expect(sample.y, inExclusiveRange(0, size.height));
    final painter = tester
        .widget<CustomPaint>(
          find
              .descendant(of: _viewport, matching: find.byType(CustomPaint))
              .first,
        )
        .painter!;
    final rgba = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      picture.dispose();
      return pixels!;
    });
    final pixel = (sample.y.floor() * size.width.ceil() + sample.x.floor()) * 4;
    expect(
      rgba!.getUint8(pixel),
      greaterThan(rgba.getUint8(pixel + 2)),
      reason: 'The visible hazard fill must tint the blue artwork red.',
    );
    await tester.tapAt(
      tester.getTopLeft(_viewport) + Offset(sample.x, sample.y),
    );
    await settleMapFixture(tester, h);
    expect(find.text('Ground hazard'), findsOneWidget);
  });
  testWidgets(
    'wheel zoom keeps the cursor anchor and logical-pixel hit target',
    (tester) async {
      final h = await pumpMapFixture(tester);
      final bounds = tester.getRect(_viewport);
      // The independent fixture affine maps (128,128) to scene (128,128).
      final centerMarker = _project(tester, h, ScenePoint(128, 128));
      expect(centerMarker.dx, closeTo(bounds.center.dx, 1e-6));
      expect(centerMarker.dy, closeTo(bounds.center.dy, 1e-6));
      final cursor = Offset(bounds.width * .42, bounds.height * .38);
      final before = h.services.maps.transform.viewportToScene(
        ViewportPoint(cursor.dx, cursor.dy),
      );
      final scale = h.services.maps.transform.scale;
      await _wheel(tester, h, bounds.topLeft + cursor, -120);
      final after = h.services.maps.transform.viewportToScene(
        ViewportPoint(cursor.dx, cursor.dy),
      );
      expect(h.services.maps.transform.scale, greaterThan(scale));
      expect(after.x, closeTo(before.x, 1e-9));
      expect(after.y, closeTo(before.y, 1e-9));
      for (final delta in [0.0, -120.0, 120.0]) {
        if (delta != 0) {
          await _wheel(
            tester,
            h,
            _project(tester, h, ScenePoint(128, 128)),
            delta,
          );
        }
        // The radius is in screen units, not stretched scene coordinates.
        await tester.tapAt(
          _project(tester, h, ScenePoint(128, 128)) + const Offset(21, 0),
        );
        await settleMapFixture(tester, h);
        expect(find.text('Ground exit'), findsOneWidget);
        expect(
          find.textContaining('Ground exit offline fixture details'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Close marker details'));
        await settleMapFixture(tester, h);
        await tester.tapAt(
          _project(tester, h, ScenePoint(128, 128)) + const Offset(23, 0),
        );
        await settleMapFixture(tester, h);
        expect(find.text('Ground exit'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden floors and categories cannot expose details or accessible targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final h = await pumpMapFixture(tester);
        expect(
          find.semantics.byLabel('Upper exit, PmcExtracts').evaluate(),
          isEmpty,
        );
        await tester.tapAt(_project(tester, h, ScenePoint(192, 64)));
        await settleMapFixture(tester, h);
        expect(find.text('Upper exit'), findsNothing);
        await tester.tap(find.widgetWithText(FilterChip, 'Upper'));
        await settleMapFixture(tester, h);
        expect(
          find.semantics.byLabel('Upper exit, PmcExtracts').evaluate(),
          hasLength(1),
        );
        await tester.tapAt(_project(tester, h, ScenePoint(192, 64)));
        await settleMapFixture(tester, h);
        expect(find.text('Upper exit'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilterChip, 'Upper'));
        await settleMapFixture(tester, h);
        expect(find.text('Upper exit'), findsNothing);
        expect(
          find.semantics.byLabel('Upper exit, PmcExtracts').evaluate(),
          isEmpty,
        );
        await tester.tapAt(_project(tester, h, ScenePoint(64, 64)));
        await settleMapFixture(tester, h);
        expect(find.text('Ground hazard'), findsOneWidget);
        expect(
          find.semantics.byLabel('Ground hazard, Hazards').evaluate(),
          hasLength(1),
        );
        final hazardFilter = find.widgetWithText(FilterChip, 'Hazards');
        await tester.ensureVisible(hazardFilter);
        await tester.pumpAndSettle();
        // Inner-filter scrolling changes its bounds in the independently
        // scrollable rail. Recompute the outer position after that layout.
        await Scrollable.ensureVisible(
          tester.element(hazardFilter),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        expect(hazardFilter.hitTestable(), findsOneWidget);
        await tapM1Async(
          tester,
          hazardFilter,
          () => h.services.settings.settings.markerFilters['Hazards'] == false,
        );
        expect(find.text('Ground hazard'), findsNothing);
        expect(
          find.semantics.byLabel('Ground hazard, Hazards').evaluate(),
          isEmpty,
        );
        await tester.tapAt(_project(tester, h, ScenePoint(64, 64)));
        await settleMapFixture(tester, h);
        expect(find.text('Ground hazard'), findsNothing);
        await tester.tap(_markerBrowser);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ListTile, 'Ground exit'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Upper exit'), findsNothing);
        expect(find.widgetWithText(ListTile, 'Ground hazard'), findsNothing);
        // Browse is the keyboard-accessible alternative to canvas targets. Traverse
        // normally, without directly invoking callbacks or assigning a focus node.
        ListTile? focusedTile;
        for (var attempt = 0; attempt < 20 && focusedTile == null; attempt++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          focusedTile = FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<ListTile>();
        }
        expect(
          focusedTile,
          isNotNull,
          reason: 'A visible marker must be keyboard reachable in Browse.',
        );
        expect((focusedTile!.title! as Text).data, 'Ground exit');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settleMapFixture(tester, h);
        expect(find.widgetWithText(ListTile, 'Ground exit'), findsNothing);
        expect(find.text('Ground exit'), findsOneWidget);
        expect(find.text('Upper exit'), findsNothing);
        expect(find.text('Ground hazard'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final category in [
    'lootContainers',
    'lootLoose',
    'locks',
    'stationaryWeapons',
  ]) {
    testWidgets('$category markers can be filtered through the Map rail', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final h = await pumpMapFixture(tester, sourceCategory: category);
        await tester.tapAt(_project(tester, h, ScenePoint(64, 64)));
        await settleMapFixture(tester, h);
        expect(find.text('Ground hazard'), findsOneWidget);
        expect(
          find.semantics.byLabel('Ground hazard, $category').evaluate(),
          hasLength(1),
        );
        final filter = find.widgetWithText(FilterChip, category);
        await tester.ensureVisible(filter);
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(filter), alignment: .5);
        await tester.pumpAndSettle();
        expect(filter.hitTestable(), findsOneWidget);
        await tapM1Async(
          tester,
          filter,
          () => h.services.settings.settings.markerFilters[category] == false,
        );
        expect(find.text('Ground hazard'), findsNothing);
        expect(
          find.semantics.byLabel('Ground hazard, $category').evaluate(),
          isEmpty,
        );
        await tester.tapAt(_project(tester, h, ScenePoint(64, 64)));
        await settleMapFixture(tester, h);
        expect(find.text('Ground hazard'), findsNothing);
      } finally {
        semantics.dispose();
      }
    });
  }

  for (final map in ['shoreline', 'thelab']) {
    testWidgets(
      '$map right-click pin uses its persisted frame, not viewport pixels',
      (tester) async {
        final h = await pumpMapFixture(tester);
        if (map != 'shoreline') {
          await tester.runAsync(() => h.services.settings.setMap(map));
          await settleMapFixture(tester, h);
        }
        // Native artwork (64,64) corresponds to game (64,192). Shoreline's
        // retained legacy frame has Y=.75; Labs retains native artwork Y=.25.
        final pointer = await tester.startGesture(
          _project(tester, h, ScenePoint(64, 64)),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await pointer.up();
        await tester.pumpAndSettle();
        expect(
          double.parse(
            tester
                .widget<TextField>(
                  find.widgetWithText(TextField, 'Normalized X'),
                )
                .controller!
                .text,
          ),
          closeTo(.25, 1e-9),
        );
        expect(
          double.parse(
            tester
                .widget<TextField>(
                  find.widgetWithText(TextField, 'Normalized Y'),
                )
                .controller!
                .text,
          ),
          closeTo(map == 'thelab' ? .25 : .75, 1e-9),
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Pin label'),
          'Cursor-created pin',
        );
        await tapM1Async(
          tester,
          find.text('Save pin'),
          () => h.services.settings.pins.isNotEmpty,
        );
        final pin = h.services.settings.pins.single;
        expect(pin.mapId, map);
        expect(pin.x, closeTo(.25, 1e-9));
        expect(pin.y, closeTo(map == 'thelab' ? .25 : .75, 1e-9));
        expect(
          pin.frame,
          map == 'thelab' ? 'labs-native-normalized' : 'legacy-normalized',
        );
        expect(pin.frameRevision, map == 'thelab' ? 1 : 0);
        await tester.tapAt(_project(tester, h, ScenePoint(64, 64)));
        await settleMapFixture(tester, h);
        expect(find.textContaining('Cursor-created pin'), findsOneWidget);
        expect(find.text('Edit pin'), findsOneWidget);
        expect(h.services.scans.hasAcceptedScan, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Scanner round trip retains Map view, floors and selected details',
    (tester) async {
      final h = await pumpMapFixture(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Upper'));
      await settleMapFixture(tester, h);
      await tester.drag(_viewport, const Offset(35, -20));
      await settleMapFixture(tester, h);
      await _wheel(tester, h, tester.getCenter(_viewport), -120);
      await tester.tapAt(_project(tester, h, ScenePoint(192, 64)));
      await settleMapFixture(tester, h);
      expect(find.text('Upper exit'), findsOneWidget);
      final before = h.services.maps.transform;
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      expect(_viewport, findsNothing);
      await tester.tap(find.byKey(const Key('nav-map')));
      await settleMapFixture(tester, h);
      final after = h.services.maps.transform;
      expect(after.scale, before.scale);
      expect(after.translationX, before.translationX);
      expect(after.translationY, before.translationY);
      expect(h.services.maps.floorSelection!.isLayerVisible('upper'), isTrue);
      expect(find.text('Upper exit'), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Upper'))
            .selected,
        isTrue,
      );
      await tester.tap(find.byTooltip('Close marker details'));
      await settleMapFixture(tester, h);
      await tester.tapAt(_project(tester, h, ScenePoint(192, 64)));
      await settleMapFixture(tester, h);
      expect(find.text('Upper exit'), findsOneWidget);
      expect(h.services.scans.hasAcceptedScan, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
