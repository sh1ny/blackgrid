import 'dart:async';
import 'dart:io';

import 'package:blackgrid/application/item_icon_cache.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/item_decision_card.dart';
import 'package:blackgrid/ui/item_icon.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/fake_item_icon_cache.dart';
import '../support/m1_harness.dart';

const _link = 'https://assets.tarkov.dev/item-a-icon.webp';
const _noArtwork = 'Identity only • no artwork';

void main() {
  late Directory dir;
  late FakeItemIconCache cache;
  late File iconFile;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('item_icon_surfaces_test');
    cache = FakeItemIconCache();
    final file = File('${dir.path}${Platform.pathSeparator}item-a.webp')
      ..writeAsBytesSync(tinyWebp);
    iconFile = file;
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<M1Harness> harness(WidgetTester tester) async {
    final h = (await tester.runAsync(() async {
      final result = M1Harness(itemIcons: cache);
      await result.initialize();
      return result;
    }))!;
    addTearDown(h.dispose);
    return h;
  }

  Future<void> show(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: blackgridTheme(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  /// Makes the newest lease of `item-a` ready and waits until its image has
  /// decoded, then rebuilds.
  ///
  /// The load starts inside [WidgetTester.runAsync] so that its file I/O
  /// completes on the real event loop.
  Future<void> readyIcon(WidgetTester tester) async {
    await tester.runAsync(() async {
      cache.leasesFor('item-a').last.value = ReadyItemIcon(iconFile);
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      final done = Completer<void>();
      final stream = image.image.resolve(
        createLocalImageConfiguration(tester.element(find.byType(Image))),
      );
      final listener = ImageStreamListener(
        (_, _) => done.complete(),
        onError: (_, _) => done.complete(),
      );
      stream.addListener(listener);
      await done.future;
      stream.removeListener(listener);
    });
    await tester.pump();
  }

  Future<void> selectA(WidgetTester tester, M1Harness h) => tester.runAsync(
    () => h.services.selection.selectManual(
      h.services.catalog.snapshot!.items['item-a']!,
    ),
  );

  Future<void> showCard(
    WidgetTester tester,
    M1Harness h,
    Size size, {
    bool compact = false,
  }) async {
    await show(
      tester,
      size,
      ItemDecisionCard(services: h.services, compact: compact),
    );
    await readyIcon(tester);
  }

  testWidgets(
    'Scanner decision card shows the cached item icon in wide and narrow layouts',
    (tester) async {
      final h = await harness(tester);
      await selectA(tester, h);

      // Wide layout: the image box.
      await showCard(tester, h, const Size(900, 700));
      expect(find.byType(ItemIcon), findsOneWidget);
      expect(find.byKey(readyItemIconKey), findsOneWidget);
      expect(find.text(_noArtwork), findsNothing);
      expect(find.byKey(const Key('item-title-row')), findsNothing);
      expect(cache.acquires, [('item-a', _link)]);

      // Narrow layout: beside the name.
      cache.acquires.clear();
      await showCard(tester, h, const Size(420, 700));
      expect(find.byType(ItemIcon), findsOneWidget);
      expect(find.byKey(readyItemIconKey), findsOneWidget);
      expect(find.text(_noArtwork), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('item-title-row')),
          matching: find.byType(ItemIcon),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Map compact decision card shows the cached item icon', (
    tester,
  ) async {
    final h = await harness(tester);
    await selectA(tester, h);

    await showCard(tester, h, const Size(900, 700), compact: true);

    expect(find.byType(ItemIcon), findsOneWidget);
    expect(find.byKey(readyItemIconKey), findsOneWidget);
    expect(find.text(_noArtwork), findsNothing);
    final row = find.byKey(const Key('item-title-row'));
    expect(
      find.descendant(of: row, matching: find.byType(ItemIcon)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Synthetic component')),
      findsOneWidget,
    );
    expect(cache.acquires, [('item-a', _link)]);
  });

  testWidgets("a history row shows its item's cached icon", (tester) async {
    final h = await harness(tester);
    await tester.runAsync(() async {
      await h.db.recordActivity('item-a', GameMode.pvp, fixtureNow);
      await h.services.history.load();
    });

    await show(
      tester,
      const Size(700, 500),
      HistoryPanel(services: h.services),
    );
    await readyIcon(tester);

    final tile = find.widgetWithText(ListTile, 'Synthetic component');
    expect(
      find.descendant(of: tile, matching: find.byKey(readyItemIconKey)),
      findsOneWidget,
    );
    expect(cache.acquires, [('item-a', _link)]);
  });

  testWidgets(
    'a history row from another mode stays generic and acquires nothing',
    (tester) async {
      final h = await harness(tester);
      expect(h.services.catalog.mode, GameMode.pvp);
      await tester.runAsync(() async {
        await h.db.recordActivity('item-a', GameMode.pve, fixtureNow);
        await h.services.history.load();
      });

      await show(
        tester,
        const Size(700, 500),
        HistoryPanel(services: h.services),
      );

      final tile = find.widgetWithText(ListTile, 'item-a');
      expect(tile, findsOneWidget);
      expect(
        find.descendant(
          of: tile,
          matching: find.byIcon(Icons.inventory_2_outlined),
        ),
        findsOneWidget,
      );
      expect(find.byType(ItemIcon), findsNothing);
      expect(cache.acquires, isEmpty);
    },
  );
}
