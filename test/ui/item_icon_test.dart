import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/item_icon_cache.dart';
import 'package:blackgrid/ui/item_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1x1 lossless WebP.
final _webp = base64Decode('UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==');

/// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// A lease the test drives by hand.
class FakeLease extends ChangeNotifier implements ItemIconLease {
  FakeLease(this.itemId);

  @override
  final String itemId;

  ItemIconView _view = const GenericItemIcon();
  bool released = false;

  @override
  ItemIconView get value => _view;

  set value(ItemIconView view) {
    _view = view;
    notifyListeners();
  }

  @override
  void release() => released = true;
}

class FakeItemIconCache implements ItemIconCache {
  final List<FakeLease> leases = [];

  List<FakeLease> leasesFor(String itemId) =>
      leases.where((l) => l.itemId == itemId).toList();

  @override
  ItemIconLease acquire(String itemId, String? iconLink) {
    final lease = FakeLease(itemId);
    leases.add(lease);
    return lease;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

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
    final file = write('a.webp', _webp);
    await tester.pumpWidget(host('a'));

    await showFile(tester, 'a', file);

    expect(drawn(), findsOneWidget);
    expect(generic(), findsNothing);
  });

  testWidgets('draws a ready PNG icon once it decodes', (tester) async {
    final file = write('a.png', _png);
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
    final fileA = write('a.webp', _webp);
    final fileB = write('b.webp', _webp);
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
    final fileA = write('a.webp', _webp);
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
}
