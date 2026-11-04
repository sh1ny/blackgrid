import 'dart:ui' as ui;

import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/maps/marker_presentation.dart';
import 'package:blackgrid/maps/marker_preview.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/ui/marker_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MarkerPresentation _presentation(String title) => MarkerPresentation(
  title: title,
  categoryLabel: 'Container',
  facts: const ['A prepared marker fact.'],
);

Future<List<bool>> _paintsTetherEndpoints(
  WidgetTester tester,
  Finder tetherFinder,
  Finder viewportFinder,
  List<Offset> points,
) async {
  final painter = tester.widget<CustomPaint>(tetherFinder).painter!;
  final size = tester.getSize(viewportFinder);
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    image.dispose();
    picture.dispose();

    return points.map((point) {
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final x = point.dx.floor() + dx;
          final y = point.dy.floor() + dy;
          if (x < 0 ||
              y < 0 ||
              x >= size.width.ceil() ||
              y >= size.height.ceil()) {
            continue;
          }
          final offset = (y * size.width.ceil() + x) * 4;
          final red = pixels.getUint8(offset);
          final green = pixels.getUint8(offset + 1);
          final blue = pixels.getUint8(offset + 2);
          if (red > 150 && green > 125 && blue < 150) return true;
        }
      }
      return false;
    }).toList();
  }))!;
}

PreparedMarker _marker(String id, String raw) => PreparedMarker(
  id: id,
  category: 'lootContainers',
  filterKey: 'lootContainers',
  name: id,
  position: GamePoint(1, 2),
  details: {'description': raw},
  source: const {'mapId': 'synthetic-map'},
  outline: const [],
);

void main() {
  testWidgets('zero viewport lays out no bubble without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 0,
            height: 0,
            child: MarkerPopup(
              presentation: _presentation('Zero viewport marker'),
              anchor: Offset.zero,
              detailsExpanded: false,
              onDetailsExpandedChanged: (_) {},
              onClose: () {},
              detailsBuilder: (_) => const Text('Must remain lazy'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Zero viewport marker'), findsNothing);
    expect(find.byTooltip('Close marker details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tiny scaled viewport clamps the bubble and keeps Close reachable',
    (tester) async {
      tester.view.physicalSize = const Size(92, 68);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            key: const ValueKey('tiny-popup-viewport'),
            child: MarkerPopup(
              presentation: _presentation('Tiny viewport marker'),
              anchor: const Offset(46, 34),
              detailsExpanded: false,
              onDetailsExpandedChanged: (_) {},
              onClose: () {},
              detailsBuilder: (_) => const Text('Lazy details'),
            ),
          ),
        ),
      );
      final viewport = tester.getRect(
        find.byKey(const ValueKey('tiny-popup-viewport')),
      );
      final popup = tester.getRect(find.byKey(const ValueKey('marker-popup')));
      expect(viewport.contains(popup.topLeft), isTrue);
      expect(viewport.contains(popup.bottomRight), isTrue);
      expect(
        find.byTooltip('Close marker details').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scaled popup placement fits and tethers at all viewport corners',
    (tester) async {
      tester.view.physicalSize = const Size(420, 340);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      for (final (anchor, shouldBeBelow) in [
        (const Offset(1, 1), true),
        (const Offset(419, 1), true),
        (const Offset(1, 339), false),
        (const Offset(419, 339), false),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox.expand(
              key: const ValueKey('corner-popup-viewport'),
              child: MarkerPopup(
                presentation: _presentation('Corner marker'),
                anchor: anchor,
                detailsExpanded: false,
                onDetailsExpandedChanged: (_) {},
                onClose: () {},
                detailsBuilder: (_) => const Text('Lazy details'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final viewport = tester.getRect(
          find.byKey(const ValueKey('corner-popup-viewport')),
        );
        final popup = tester.getRect(
          find.byKey(const ValueKey('marker-popup')),
        );
        final close = tester.getRect(find.byTooltip('Close marker details'));
        final tetherFinder = find.byKey(const ValueKey('marker-popup-tether'));
        final tether = tester.getRect(tetherFinder);

        expect(viewport.contains(popup.topLeft), isTrue);
        expect(viewport.contains(popup.bottomRight), isTrue);
        expect(viewport.contains(close.topLeft), isTrue);
        expect(viewport.contains(close.bottomRight), isTrue);
        expect(
          shouldBeBelow ? popup.top >= anchor.dy : popup.bottom <= anchor.dy,
          isTrue,
        );
        expect(tether.contains(anchor), isTrue);
        expect(tether.contains(popup.center), isTrue);
        expect(tester.widget<CustomPaint>(tetherFinder).painter, isNotNull);
        final tetherEnd = Offset(
          anchor.dx.clamp(popup.left, popup.right).toDouble(),
          anchor.dy.clamp(popup.top, popup.bottom).toDouble(),
        );
        expect(
          await _paintsTetherEndpoints(
            tester,
            tetherFinder,
            find.byKey(const ValueKey('corner-popup-viewport')),
            [anchor, tetherEnd],
          ),
          everyElement(isTrue),
        );
        expect(
          find.byTooltip('Close marker details').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'long interior popup remains tethered, scrollable, and closable',
    (tester) async {
      tester.view.physicalSize = const Size(420, 340);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var closeCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            key: const ValueKey('long-popup-viewport'),
            child: MarkerPopup(
              presentation: _presentation('Interior marker'),
              anchor: const Offset(210, 170),
              detailsExpanded: true,
              onDetailsExpandedChanged: (_) {},
              onClose: () => closeCount++,
              detailsBuilder: (_) => Text(
                List<String>.filled(80, 'Long marker detail').join('\\n'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final viewportFinder = find.byKey(const ValueKey('long-popup-viewport'));
      final viewport = tester.getRect(viewportFinder);
      final popup = tester.getRect(find.byKey(const ValueKey('marker-popup')));
      final closeFinder = find.byTooltip('Close marker details');
      final scrollableState = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('marker-popup-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(viewport.contains(popup.topLeft), isTrue);
      expect(viewport.contains(popup.bottomRight), isTrue);
      expect(scrollableState.position.maxScrollExtent, greaterThan(0));
      expect(closeFinder.hitTestable(), findsOneWidget);
      final tetherFinder = find.byKey(const ValueKey('marker-popup-tether'));
      final tetherEnd = Offset(
        const Offset(210, 170).dx.clamp(popup.left, popup.right).toDouble(),
        const Offset(210, 170).dy.clamp(popup.top, popup.bottom).toDouble(),
      );
      expect(
        await _paintsTetherEndpoints(tester, tetherFinder, viewportFinder, [
          const Offset(210, 170),
          tetherEnd,
        ]),
        everyElement(isTrue),
      );

      await tester.drag(
        find.byKey(const ValueKey('marker-popup-scroll')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(scrollableState.position.pixels, greaterThan(0));
      expect(closeFinder.hitTestable(), findsOneWidget);
      await tester.tap(closeFinder);
      await tester.pump();
      expect(closeCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('collapsed details builder is lazy and follows current marker', (
    tester,
  ) async {
    var selected = _marker('first-marker', 'first current marker details');
    var expanded = false;
    var closeCount = 0;
    final buildsByMarker = <String, int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Center(
              child: Column(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      selected = _marker(
                        'second-marker',
                        'second current marker details',
                      );
                    }),
                    child: const Text('Select second marker'),
                  ),
                  SizedBox(
                    width: 420,
                    height: 320,
                    child: MarkerPopup(
                      presentation: _presentation(selected.name),
                      anchor: const Offset(210, 160),
                      detailsExpanded: expanded,
                      onDetailsExpandedChanged: (value) =>
                          setState(() => expanded = value),
                      onClose: () => closeCount++,
                      detailsBuilder: (context) {
                        buildsByMarker.update(
                          selected.id,
                          (count) => count + 1,
                          ifAbsent: () => 1,
                        );
                        return SelectableText(
                          previewMarkerDetails(selected).text,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(buildsByMarker, isEmpty);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(buildsByMarker, {'first-marker': 1});
    expect(find.textContaining('first current marker details'), findsOneWidget);
    await tester.tap(find.text('Select second marker'));
    await tester.pumpAndSettle();
    expect(buildsByMarker, {'first-marker': 1, 'second-marker': 1});
    expect(find.textContaining('first current marker details'), findsNothing);
    expect(
      find.textContaining('second current marker details'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close marker details'));
    await tester.pumpAndSettle();
    expect(closeCount, 1);
  });
}
