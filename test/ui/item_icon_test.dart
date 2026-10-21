import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/item_icon_cache.dart';
import 'package:blackgrid/ui/item_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_item_icon_cache.dart';

void main() {
  late Directory dir;
  late FakeItemIconCache cache;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('item_icon_test');
    cache = FakeItemIconCache();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  File write(String name, List<int> bytes) =>
      File('${dir.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(bytes);

  Widget host(String itemId) => MaterialApp(
    home: Center(
      child: ItemIcon(
        key: ValueKey(itemId),
        cache: cache,
        itemId: itemId,
        iconLink: 'https://example.test/$itemId.webp',
        size: 24,
      ),
    ),
  );

  /// Shows [file] on the lease of [itemId] and waits until the image has
  /// decoded or failed, then rebuilds.
  ///
  /// The load is started inside [WidgetTester.runAsync] so that its file I/O
  /// completes on the real event loop.
  Future<void> showFile(WidgetTester tester, String itemId, File file) async {
    await tester.runAsync(() async {
      cache.leasesFor(itemId).last.value = ReadyItemIcon(file);
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

  Finder generic() => find.byKey(genericItemIconKey);
  Finder drawn() => find.byKey(readyItemIconKey);

  testWidgets('shows the generic icon while loading and after a failure', (
    tester,
  ) async {
    await tester.pumpWidget(host('a'));

    expect(generic(), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    // A failed or absent download leaves the lease generic.
    cache.leasesFor('a').single.value = const GenericItemIcon();
    await tester.pump();
    expect(generic(), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('draws a ready WebP icon once it decodes', (tester) async {
    final file = write('a.webp', tinyWebp);
    await tester.pumpWidget(host('a'));

    await showFile(tester, 'a', file);

    expect(drawn(), findsOneWidget);
    expect(generic(), findsNothing);
  });

  testWidgets('draws a ready PNG icon once it decodes', (tester) async {
    final file = write('a.png', tinyPng);
    await tester.pumpWidget(host('a'));

    await showFile(tester, 'a', file);

    expect(drawn(), findsOneWidget);
    expect(generic(), findsNothing);
  });

  testWidgets('an undecodable file shows the generic icon without an error', (
    tester,
  ) async {
    final file = write('a.webp', utf8.encode('not an image'));
    await tester.pumpWidget(host('a'));

    await showFile(tester, 'a', file);

    expect(generic(), findsOneWidget);
    expect(drawn(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching item shows generic until the new icon is ready', (
    tester,
  ) async {
    final fileA = write('a.webp', tinyWebp);
    final fileB = write('b.webp', tinyWebp);
    await tester.pumpWidget(host('a'));
    await showFile(tester, 'a', fileA);
    expect(drawn(), findsOneWidget);

    await tester.pumpWidget(host('b'));

    expect(generic(), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    await showFile(tester, 'b', fileB);

    expect(drawn(), findsOneWidget);
    expect(generic(), findsNothing);
    expect(tester.widget<Image>(find.byType(Image)).key, ValueKey(fileB.path));
  });

  testWidgets('a late completion for the old item never draws on the new one', (
    tester,
  ) async {
    final fileA = write('a.webp', tinyWebp);
    await tester.pumpWidget(host('a'));
    await tester.pumpWidget(host('b'));
    final oldLease = cache.leasesFor('a').single;

    oldLease.value = ReadyItemIcon(fileA);
    await tester.pump();

    expect(generic(), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets("switching the widget's item releases the old lease", (
    tester,
  ) async {
    await tester.pumpWidget(host('a'));
    final first = cache.leasesFor('a').single;
    expect(first.released, isFalse);

    await tester.pumpWidget(host('b'));

    expect(first.released, isTrue);
    expect(cache.leasesFor('b').single.released, isFalse);

    await tester.pumpWidget(const SizedBox());
    expect(cache.leasesFor('b').single.released, isTrue);
  });

  testWidgets('a changed icon link of the same item takes a new lease', (
    tester,
  ) async {
    Widget withLink(String link) => MaterialApp(
      home: ItemIcon(cache: cache, itemId: 'a', iconLink: link, size: 24),
    );
    await tester.pumpWidget(withLink('https://example.test/1.webp'));
    await tester.pumpWidget(withLink('https://example.test/2.webp'));

    expect(cache.leasesFor('a'), hasLength(2));
    expect(cache.leasesFor('a').first.released, isTrue);
    expect(cache.leasesFor('a').last.released, isFalse);
  });

  testWidgets('an icon on a hidden tab acquires nothing until shown', (
    tester,
  ) async {
    Widget tabs(int index) => MaterialApp(
      home: IndexedStack(
        index: index,
        children: [
          const SizedBox(),
          ItemIcon(
            cache: cache,
            itemId: 'a',
            iconLink: 'https://example.test/a.webp',
            size: 24,
          ),
        ],
      ),
    );
    await tester.pumpWidget(tabs(0));
    expect(cache.acquires, isEmpty);

    await tester.pumpWidget(tabs(1));
    expect(cache.acquires, hasLength(1));
    expect(cache.leasesFor('a').single.released, isFalse);

    await tester.pumpWidget(tabs(0));
    expect(cache.leasesFor('a').single.released, isTrue);
    expect(find.byKey(genericItemIconKey, skipOffstage: false), findsOneWidget);
  });

  testWidgets(
    'a lease change during another icon build is applied after the frame',
    (tester) async {
      Widget icon(String key) => ItemIcon(
        key: ValueKey(key),
        cache: cache,
        itemId: 'a',
        iconLink: 'https://example.test/a.webp',
        size: 24,
      );
      // The second icon is built during layout, in its own build scope, as a
      // lazily built history row is; the first icon is outside that scope.
      Widget icons(int count) => MaterialApp(
        home: Column(
          children: [
            icon('card'),
            LayoutBuilder(
              builder: (_, _) =>
                  count > 1 ? icon('row') : const SizedBox.shrink(),
            ),
          ],
        ),
      );
      await tester.pumpWidget(icons(1));
      final shown = cache.leasesFor('a').single;
      final file = write('a.webp', tinyWebp);
      await tester.runAsync(() async {
        shown.value = ReadyItemIcon(file);
        await tester.pump();
      });

      // The real cache publishes to the item's other leases from inside
      // acquire, which the second icon calls while it is being built.
      cache.onAcquire = (_) => shown.value = const GenericItemIcon();
      await tester.pumpWidget(icons(2));
      expect(tester.takeException(), isNull);

      await tester.pump();
      expect(generic(), findsNWidgets(2));
    },
  );
}
