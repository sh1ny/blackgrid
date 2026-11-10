import 'dart:async';
import 'dart:io';

import 'package:blackgrid/application/item_icon_cache.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/item_icon.dart';
import 'package:blackgrid/ui/shell.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
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
        theme: blackgridTheme(Brightness.dark),
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
  Future<void> readyIcon(WidgetTester tester, {Finder? within}) async {
    final images = within == null
        ? find.byType(Image)
        : find.descendant(of: within, matching: find.byType(Image));
    await tester.runAsync(() async {
      final leases = cache.leasesFor('item-a');
      // A closed inspector's released lease is not the one on screen.
      final live = within == null
          ? leases.last
          : leases.lastWhere((lease) => !lease.released);
      live.value = ReadyItemIcon(iconFile);
      await tester.pump();
      final image = tester.widget<Image>(images);
      final done = Completer<void>();
      final stream = image.image.resolve(
        createLocalImageConfiguration(tester.element(images)),
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

  final strip = find.byKey(const Key('answer-strip'));

  /// Shows the shell on [area] at [size] and waits for the strip's icon.
  Future<void> showStrip(
    WidgetTester tester,
    M1Harness h,
    Size size,
    String area,
  ) async {
    await show(tester, size, BlackgridShell(services: h.services));
    await tester.tap(find.byKey(Key(area)));
    await tester.pumpAndSettle();
    // An open inspector's history row would also lease the icon.
    if (find.byKey(const Key('shell-inspector')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
    }
    await readyIcon(tester, within: strip);
  }

  testWidgets('closed inspector does not acquire history images', (
    tester,
  ) async {
    final h = await harness(tester);
    await show(
      tester,
      const Size(1660, 870),
      BlackgridShell(services: h.services),
    );
    // History lives in the Scanner inspector, not the Map one.
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await h.db.recordActivity('item-a', GameMode.pvp, fixtureNow);
      await h.services.history.load();
    });
    await tester.pumpAndSettle();
    expect(cache.acquires, isEmpty);
    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
    final list = find
        .descendant(
          of: find.byKey(const Key('shell-inspector')),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(list).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(cache.acquires, [('item-a', _link)]);
    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
    expect(cache.leases.single.released, isTrue);
    expect(cache.acquires, hasLength(1));
  });

  testWidgets(
    'Scanner decision card shows the cached item icon in wide and narrow layouts',
    (tester) async {
      final h = await harness(tester);
      await selectA(tester, h);

      // Wide layout: the strip lays its blocks out in one row.
      await showStrip(tester, h, const Size(1672, 941), 'nav-scanner');
      final icon = find.descendant(of: strip, matching: find.byType(ItemIcon));
      expect(icon, findsOneWidget);
      expect(find.byKey(readyItemIconKey), findsOneWidget);
      expect(find.text(_noArtwork), findsNothing);
      // The inspector's history row leased the icon too; only the strip's
      // lease is still held once it is closed.
      expect(cache.acquires.toSet(), {('item-a', _link)});
      expect(cache.leasesFor('item-a').where((l) => !l.released), hasLength(1));

      // Narrow layout: the blocks wrap, the icon stays beside the name.
      await showStrip(tester, h, const Size(960, 720), 'nav-scanner');
      expect(icon, findsOneWidget);
      expect(find.byKey(readyItemIconKey), findsOneWidget);
      expect(find.text(_noArtwork), findsNothing);
      expect(
        find.descendant(of: strip, matching: find.text('Synthetic component')),
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

    await showStrip(tester, h, const Size(1672, 941), 'nav-map');

    final icon = find.descendant(of: strip, matching: find.byType(ItemIcon));
    expect(icon, findsOneWidget);
    expect(find.byKey(readyItemIconKey), findsOneWidget);
    expect(find.text(_noArtwork), findsNothing);
    final name = find.descendant(
      of: strip,
      matching: find.text('Synthetic component'),
    );
    expect(name, findsOneWidget);
    // The icon sits beside the name, on the same row.
    expect(
      (tester.getCenter(icon).dy - tester.getCenter(name).dy).abs(),
      lessThan(48),
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
