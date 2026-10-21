import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:blackgrid/application/item_icon_cache.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/item_icon_client.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart';

/// One request the fake client received, completed on demand by a test.
class FakeCall {
  FakeCall(this.link, this.etag);
  final Uri link;
  final String? etag;
  final Completer<ItemIconFetchResult> _result = Completer();
  bool cancelled = false;

  Future<ItemIconFetchResult> get result => _result.future;
  bool get isDone => _result.isCompleted;

  void complete(ItemIconFetchResult value) {
    if (!_result.isCompleted) _result.complete(value);
  }
}

/// Hand-written client: records every call and answers when a test says so.
class FakeItemIconClient implements ItemIconClient {
  final calls = <FakeCall>[];
  int maxActive = 0;

  /// Whether a cancel answers the call at once; false models a transport
  /// that is slow to honour aborts, so the test completes the call itself.
  bool answerCancel = true;
  int _active = 0;
  final _waiters = <(int, Completer<void>)>[];

  @override
  Duration get timeout => const Duration(seconds: 15);
  @override
  String get userAgent => 'test';

  @override
  Future<ItemIconFetchResult> fetch(
    Uri link, {
    String? etag,
    Future<void>? cancel,
  }) {
    final call = FakeCall(link, etag);
    calls.add(call);
    _active++;
    maxActive = math.max(maxActive, _active);
    cancel?.then<void>((_) {
      call.cancelled = true;
      if (answerCancel) call.complete(const IconCancelled());
    });
    call.result.whenComplete(() => _active--);
    for (final (count, waiter) in List.of(_waiters)) {
      if (calls.length >= count && !waiter.isCompleted) waiter.complete();
    }
    return call.result;
  }

  /// Completes once at least [count] calls have arrived.
  Future<void> waitForCalls(int count) {
    if (calls.length >= count) return Future.value();
    final waiter = Completer<void>();
    _waiters.add((count, waiter));
    return waiter.future;
  }

  Iterable<FakeCall> get open => calls.where((c) => !c.isDone);
}

/// A database whose icon upserts throw while [failUpserts] is set.
class FlakyDatabase extends BlackgridDatabase {
  FlakyDatabase(super.executor);

  bool failUpserts = false;

  @override
  Future<void> upsertItemIcon(ItemIconRecordsCompanion row) {
    if (failUpserts) return Future.error(StateError('upsert failed'));
    return super.upsertItemIcon(row);
  }
}

const _base = 'https://assets.tarkov.dev';
String linkFor(String id) => '$_base/$id-icon.webp';

Uint8List webp(int seed, {int extra = 4}) => Uint8List.fromList([
  0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, //
  seed, ...List.filled(extra, seed),
]);

IconFetched fetched(Uint8List bytes, {String? etag}) =>
    IconFetched(bytes, IconFormat.webp, etag: etag);

String _hash16(List<int> bytes) =>
    sha256.convert(bytes).toString().substring(0, 16);

String iconName(String id, List<int> bytes) =>
    '${_hash16(utf8.encode(id))}-${_hash16(bytes)}.webp';

/// Matches a stored time by instant, whatever its UTC flag.
Matcher atMoment(DateTime expected) => predicate<DateTime?>(
  (value) => value != null && value.isAtSameMomentAs(expected),
  'is the instant $expected',
);

Future<ReadyItemIcon> whenReady(ItemIconLease lease) {
  if (lease.value case final ReadyItemIcon ready) return Future.value(ready);
  final done = Completer<ReadyItemIcon>();
  void listener() {
    if (lease.value case final ReadyItemIcon ready) {
      lease.removeListener(listener);
      done.complete(ready);
    }
  }

  lease.addListener(listener);
  return done.future;
}

void main() {
  late FlakyDatabase db;
  late Directory root;
  late Directory dir;
  late FakeItemIconClient client;
  late List<ItemIconCache> caches;
  var now = fixtureNow;

  setUp(() async {
    db = FlakyDatabase(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('blackgrid-icons-');
    dir = Directory('${root.path}${Platform.pathSeparator}icons')..createSync();
    client = FakeItemIconClient();
    caches = [];
    now = fixtureNow;
  });

  tearDown(() async {
    // A call a test left open would hold dispose forever.
    for (final call in client.calls) {
      call.complete(const IconCancelled());
    }
    for (final cache in caches) {
      await cache.dispose();
    }
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<ItemIconCache> openCache({
    int budget = 1 << 20,
    int maxConcurrent = 4,
  }) async {
    final cache = ItemIconCache(
      database: db,
      client: client,
      directory: dir,
      clock: () => now,
      budgetBytes: budget,
      maxConcurrent: maxConcurrent,
    );
    caches.add(cache);
    await cache.open();
    return cache;
  }

  /// Writes a row and its file as an earlier session would have.
  Future<File> seed(
    String id, {
    String? link,
    Uint8List? bytes,
    DateTime? validatedAt,
    DateTime? lastShownAt,
    String? etag,
    DateTime? failedUntil,
    String? failedLink,
    bool writeFile = true,
  }) async {
    final body = bytes ?? webp(1);
    final name = iconName(id, body);
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    if (writeFile) file.writeAsBytesSync(body);
    await db.upsertItemIcon(
      ItemIconRecordsCompanion.insert(
        itemId: id,
        iconLink: link ?? linkFor(id),
        fileName: Value(name),
        byteSize: Value(body.length),
        etag: Value(etag),
        validatedAt: Value(validatedAt ?? now),
        lastShownAt: lastShownAt ?? now,
        failedUntil: Value(failedUntil),
        failedLink: Value(failedLink),
      ),
    );
    return file;
  }

  Future<ItemIconRecord?> rowFor(String id) async =>
      (await db.readItemIcons()).where((r) => r.itemId == id).firstOrNull;

  List<String> folderNames() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  /// Shows [id] once, fails it, and waits until the failure is recorded.
  Future<void> failOnce(
    ItemIconCache cache,
    String id, [
    ItemIconFetchResult failure = const IconFailed(IconFailureKind.status),
  ]) async {
    final lease = cache.acquire(id, linkFor(id));
    final call = client.calls.last;
    call.complete(failure);
    await itemIconCacheIdle(cache);
    lease.release();
  }

  group('item icon cache', () {
    test(
      'names files from hashes so unsafe item ids stay inside the folder',
      () async {
        final cache = await openCache();
        const ids = ['../../x', r'a\b', 'c:d'];
        final leases = [
          for (final (i, id) in ids.indexed) cache.acquire(id, linkFor('x$i')),
        ];
        expect(client.calls, hasLength(3));
        for (var i = 0; i < ids.length; i++) {
          client.calls[i].complete(fetched(webp(i + 1)));
        }
        final ready = [for (final lease in leases) await whenReady(lease)];
        await itemIconCacheIdle(cache);

        final entities = dir.listSync();
        expect(entities, hasLength(3));
        for (final entity in entities) {
          expect(entity, isA<File>());
          expect(entity.parent.path, dir.path);
          final name = entity.uri.pathSegments.last;
          for (final id in ids) {
            expect(name, isNot(contains(id)));
          }
          expect(name, matches(RegExp(r'^[0-9a-f]{16}-[0-9a-f]{16}\.webp$')));
        }
        for (final r in ready) {
          expect(r.file.parent.path, dir.path);
        }
        expect(root.listSync().map((e) => e.path), [dir.path]);
      },
    );

    test(
      'first acquire of an uncached item sends one GET and becomes ready',
      () async {
        final cache = await openCache();
        final lease = cache.acquire('a', linkFor('a'));
        expect(lease.itemId, 'a');
        expect(lease.value, isA<GenericItemIcon>());
        expect(client.calls, hasLength(1));
        expect(client.calls.single.link, Uri.parse(linkFor('a')));
        expect(client.calls.single.etag, isNull);

        final body = webp(7);
        client.calls.single.complete(fetched(body, etag: '"e1"'));
        final ready = await whenReady(lease);
        expect(ready.file.readAsBytesSync(), body);
        expect(ready.file.parent.path, dir.path);
        final row = await rowFor('a');
        expect(row!.iconLink, linkFor('a'));
        expect(row.fileName, iconName('a', body));
        expect(row.byteSize, body.length);
        expect(row.etag, '"e1"');
        expect(row.validatedAt, atMoment(now));
        expect(client.calls, hasLength(1));
      },
    );

    test('an item with no icon link stays generic and sends nothing', () async {
      final cache = await openCache();
      final lease = cache.acquire('a', null);
      await itemIconCacheIdle(cache);
      expect(lease.value, isA<GenericItemIcon>());
      expect(client.calls, isEmpty);
      expect(await db.readItemIcons(), isEmpty);
      lease.release();
    });

    test('two leases on one item share one request', () async {
      final cache = await openCache();
      final card = cache.acquire('a', linkFor('a'));
      final row = cache.acquire('a', linkFor('a'));
      expect(client.calls, hasLength(1));
      client.calls.single.complete(fetched(webp(1)));
      final cardReady = await whenReady(card);
      final rowReady = await whenReady(row);
      expect(cardReady.file.path, rowReady.file.path);
      expect(client.calls, hasLength(1));
    });

    test(
      're-acquiring during a held download sends no second request',
      () async {
        final cache = await openCache();
        final card = cache.acquire('a', linkFor('a'));
        final row = cache.acquire('a', linkFor('a'));
        card.release();
        final again = cache.acquire('a', linkFor('a'));
        expect(client.calls, hasLength(1));
        expect(client.calls.single.cancelled, isFalse);
        client.calls.single.complete(fetched(webp(1)));
        await whenReady(row);
        await whenReady(again);
        expect(client.calls, hasLength(1));
        expect(client.calls.single.cancelled, isFalse);
      },
    );

    test(
      'a 400-day-old icon validated 10 days ago is used without a request',
      () async {
        final file = await seed(
          'a',
          validatedAt: now.subtract(const Duration(days: 10)),
          lastShownAt: now.subtract(const Duration(days: 400)),
        );
        final cache = await openCache();
        final lease = cache.acquire('a', linkFor('a'));
        expect((lease.value as ReadyItemIcon).file.path, file.path);
        await itemIconCacheIdle(cache);
        expect(client.calls, isEmpty);
        expect(file.existsSync(), isTrue);
      },
    );

    test('a new icon link downloads once and removes the old file unless it is the same file', () async {
      final sameBody = webp(1);
      final oldBody = webp(2);
      final sameFile = await seed(
        'same',
        link: '$_base/old-same.webp',
        bytes: sameBody,
      );
      final oldFile = await seed(
        'moved',
        link: '$_base/old-moved.webp',
        bytes: oldBody,
      );
      final cache = await openCache();

      final moved = cache.acquire('moved', linkFor('moved'));
      final same = cache.acquire('same', linkFor('same'));
      expect(moved.value, isA<GenericItemIcon>());
      expect(same.value, isA<GenericItemIcon>());
      expect(client.calls.map((c) => c.link.toString()), [
        linkFor('moved'),
        linkFor('same'),
      ]);

      final newBody = webp(3);
      client.calls[0].complete(fetched(newBody));
      client.calls[1].complete(fetched(sameBody));
      final movedReady = await whenReady(moved);
      final sameReady = await whenReady(same);
      await itemIconCacheIdle(cache);

      expect(oldFile.existsSync(), isFalse);
      expect(movedReady.file.path, isNot(oldFile.path));
      expect(movedReady.file.readAsBytesSync(), newBody);
      expect(sameReady.file.path, sameFile.path);
      expect(sameFile.existsSync(), isTrue);
      expect((await rowFor('moved'))!.iconLink, linkFor('moved'));
      expect((await rowFor('same'))!.iconLink, linkFor('same'));
      expect(client.calls, hasLength(2));
    });

    test('a recorded icon whose file is gone downloads again', () async {
      await seed('a', writeFile: false);
      final cache = await openCache();
      final lease = cache.acquire('a', linkFor('a'));
      expect(lease.value, isA<GenericItemIcon>());
      expect(client.calls, hasLength(1));
      client.calls.single.complete(fetched(webp(5)));
      final ready = await whenReady(lease);
      expect(ready.file.existsSync(), isTrue);
      expect(client.calls, hasLength(1));
    });

    test('an icon validated 29 days ago is not revalidated', () async {
      await seed('a', validatedAt: now.subtract(const Duration(days: 29)));
      final cache = await openCache();
      final lease = cache.acquire('a', linkFor('a'));
      await itemIconCacheIdle(cache);
      expect(lease.value, isA<ReadyItemIcon>());
      expect(client.calls, isEmpty);
    });

    test('a 30-day-old icon revalidates with If-None-Match and a 304 keeps the file', () async {
      final file = await seed(
        'a',
        etag: '"e1"',
        validatedAt: now.subtract(const Duration(days: 30)),
      );
      final modified = file.lastModifiedSync();
      final cache = await openCache();
      final lease = cache.acquire('a', linkFor('a'));
      expect((lease.value as ReadyItemIcon).file.path, file.path);
      expect(client.calls, hasLength(1));
      expect(client.calls.single.etag, '"e1"');

      client.calls.single.complete(const IconNotModified());
      await itemIconCacheIdle(cache);
      expect((lease.value as ReadyItemIcon).file.path, file.path);
      expect(file.lastModifiedSync(), modified);
      final row = await rowFor('a');
      expect(row!.validatedAt, atMoment(now));
      expect(row.fileName, iconName('a', webp(1)));

      cache.acquire('a', linkFor('a'));
      expect(client.calls, hasLength(1));
    });

    test('a 304 after the file vanished mid-revalidation downloads it again without a wait', () async {
      final file = await seed(
        'a',
        etag: '"e1"',
        validatedAt: now.subtract(const Duration(days: 30)),
      );
      final cache = await openCache();
      final card = cache.acquire('a', linkFor('a'));
      expect(client.calls.single.etag, '"e1"');

      file.deleteSync();
      final row = cache.acquire('a', linkFor('a'));
      expect(row.value, isA<GenericItemIcon>());
      expect(client.calls, hasLength(1));

      client.calls.single.complete(const IconNotModified());
      // Idle with no second call means the 304 ended the work, as a failure.
      await Future.any([client.waitForCalls(2), itemIconCacheIdle(cache)]);
      expect(client.calls, hasLength(2));
      expect(client.calls[1].link.toString(), linkFor('a'));
      expect(client.calls[1].etag, isNull);

      client.calls[1].complete(fetched(webp(5)));
      final ready = await whenReady(row);
      expect(ready.file.existsSync(), isTrue);
      await itemIconCacheIdle(cache);
      final stored = await rowFor('a');
      expect(stored!.failedUntil, isNull);
      expect(stored.failedLink, isNull);
      expect(client.calls, hasLength(2));
      card.release();
      row.release();
    });

    test('a cached file that cannot be read downloads again', () async {
      final file = await seed('a');
      // An exclusive lock through another handle makes reads fail on
      // Windows while the file still exists.
      final lock = file.openSync(mode: FileMode.append)
        ..lockSync(FileLock.exclusive);
      var locked = true;
      addTearDown(() {
        if (locked) lock.closeSync();
      });
      final cache = await openCache();
      final lease = cache.acquire('a', linkFor('a'));
      expect(lease.value, isA<GenericItemIcon>());
      expect(client.calls, hasLength(1));
      expect(client.calls.single.etag, isNull);

      lock
        ..unlockSync()
        ..closeSync();
      locked = false;
      client.calls.single.complete(fetched(webp(8)));
      final ready = await whenReady(lease);
      expect(ready.file.readAsBytesSync(), webp(8));
      lease.release();
    }, testOn: 'windows');

    test(
      'a 304 for a file deleted with no new acquire downloads it again',
      () async {
        final file = await seed(
          'a',
          etag: '"e1"',
          validatedAt: now.subtract(const Duration(days: 30)),
        );
        final cache = await openCache();
        final lease = cache.acquire('a', linkFor('a'));
        expect(client.calls.single.etag, '"e1"');

        file.deleteSync();
        client.calls.single.complete(const IconNotModified());
        await Future.any([client.waitForCalls(2), itemIconCacheIdle(cache)]);
        expect(client.calls, hasLength(2));
        expect(client.calls[1].etag, isNull);
        expect(lease.value, isA<GenericItemIcon>());

        client.calls[1].complete(fetched(webp(6)));
        final ready = await whenReady(lease);
        expect(ready.file.existsSync(), isTrue);
        lease.release();
      },
    );

    test(
      'a 304 whose write fails records no failure and sends nothing more',
      () async {
        final file = await seed(
          'a',
          etag: '"e1"',
          validatedAt: now.subtract(const Duration(days: 30)),
        );
        final cache = await openCache();
        final card = cache.acquire('a', linkFor('a'));
        db.failUpserts = true;
        client.calls.single.complete(const IconNotModified());
        await itemIconCacheIdle(cache);
        // No new revalidation while the database keeps failing.
        expect(client.calls, hasLength(1));
        expect(card.value, isA<ReadyItemIcon>());

        // Without a failure wait, a vanished file downloads again at once.
        db.failUpserts = false;
        file.deleteSync();
        final row = cache.acquire('a', linkFor('a'));
        expect(client.calls, hasLength(2));
        expect(client.calls[1].etag, isNull);
        client.calls[1].complete(fetched(webp(7)));
        await whenReady(row);
        card.release();
        row.release();
      },
    );

    test(
      'a 200 revalidation replaces the icon and stores the new etag',
      () async {
        final oldFile = await seed(
          'a',
          etag: '"e1"',
          validatedAt: now.subtract(const Duration(days: 31)),
        );
        final cache = await openCache();
        final lease = cache.acquire('a', linkFor('a'));
        final newBody = webp(9);
        client.calls.single.complete(fetched(newBody, etag: '"e2"'));
        await itemIconCacheIdle(cache);

        final ready = lease.value as ReadyItemIcon;
        expect(ready.file.path, isNot(oldFile.path));
        expect(ready.file.readAsBytesSync(), newBody);
        expect(oldFile.existsSync(), isFalse);
        final row = await rowFor('a');
        expect(row!.etag, '"e2"');
        expect(row.fileName, iconName('a', newBody));
        expect(row.validatedAt, atMoment(now));
      },
    );

    test('a 200 revalidation with identical bytes keeps the file and sends nothing next time', () async {
      final body = webp(1);
      final file = await seed(
        'a',
        bytes: body,
        etag: '"e1"',
        validatedAt: now.subtract(const Duration(days: 40)),
      );
      final modified = file.lastModifiedSync();
      final cache = await openCache();
      final lease = cache.acquire('a', linkFor('a'));
      client.calls.single.complete(fetched(body, etag: '"e2"'));
      await itemIconCacheIdle(cache);

      expect((lease.value as ReadyItemIcon).file.path, file.path);
      expect(file.existsSync(), isTrue);
      expect(file.lastModifiedSync(), modified);
      expect(folderNames(), [iconName('a', body)]);
      final row = await rowFor('a');
      expect(row!.etag, '"e2"');
      expect(row.validatedAt, atMoment(now));

      cache.acquire('a', linkFor('a'));
      await itemIconCacheIdle(cache);
      expect(client.calls, hasLength(1));
    });

    test('a failed revalidation keeps the cached icon ready', () async {
      final file = await seed(
        'a',
        etag: '"e1"',
        validatedAt: now.subtract(const Duration(days: 45)),
      );
      final cache = await openCache();
      final lease = cache.acquire('a', linkFor('a'));
      client.calls.single.complete(const IconFailed(IconFailureKind.status));
      await itemIconCacheIdle(cache);

      expect((lease.value as ReadyItemIcon).file.path, file.path);
      expect(file.existsSync(), isTrue);
      final row = await rowFor('a');
      expect(row!.fileName, isNotNull);
      expect(row.failedLink, linkFor('a'));
      expect(row.failedUntil, atMoment(now.add(const Duration(hours: 24))));
      cache.acquire('a', linkFor('a'));
      expect(client.calls, hasLength(1));
    });

    test('a 404 item shown 50 times in 23 hours sends one request', () async {
      final cache = await openCache();
      await failOnce(cache, 'a');
      expect(client.calls, hasLength(1));
      for (var i = 1; i <= 50; i++) {
        now = fixtureNow.add(Duration(minutes: i * 23 * 60 ~/ 50));
        final lease = cache.acquire('a', linkFor('a'));
        expect(lease.value, isA<GenericItemIcon>());
        lease.release();
      }
      await itemIconCacheIdle(cache);
      expect(client.calls, hasLength(1));
    });

    test('a reopened cache keeps the failure wait', () async {
      final first = await openCache();
      await failOnce(first, 'a');
      await first.dispose();

      now = fixtureNow.add(const Duration(hours: 5));
      final second = await openCache();
      final lease = second.acquire('a', linkFor('a'));
      await itemIconCacheIdle(second);
      expect(lease.value, isA<GenericItemIcon>());
      expect(client.calls, hasLength(1));
    });

    test('after 24 hours a failed item gets exactly one new request', () async {
      final cache = await openCache();
      await failOnce(cache, 'a');

      now = fixtureNow.add(
        const Duration(hours: 24) - const Duration(seconds: 1),
      );
      cache.acquire('a', linkFor('a')).release();
      expect(client.calls, hasLength(1));

      now = fixtureNow.add(const Duration(hours: 24));
      final first = cache.acquire('a', linkFor('a'));
      final second = cache.acquire('a', linkFor('a'));
      expect(client.calls, hasLength(2));
      client.calls.last.complete(fetched(webp(4)));
      await whenReady(first);
      await whenReady(second);
      expect(client.calls, hasLength(2));
    });

    test(
      'a new icon link inside the wait sends one request to the new link',
      () async {
        final cache = await openCache();
        await failOnce(cache, 'a');

        now = fixtureNow.add(const Duration(hours: 1));
        final lease = cache.acquire('a', '$_base/a-icon-v2.webp');
        cache.acquire('a', '$_base/a-icon-v2.webp');
        expect(client.calls, hasLength(2));
        expect(client.calls.last.link, Uri.parse('$_base/a-icon-v2.webp'));
        client.calls.last.complete(fetched(webp(6)));
        await whenReady(lease);
        expect((await rowFor('a'))!.failedUntil, isNull);
      },
    );

    test("one item's failure wait does not block another", () async {
      final cache = await openCache();
      await failOnce(cache, 'a');
      final other = cache.acquire('b', linkFor('b'));
      expect(client.calls, hasLength(2));
      expect(client.calls.last.link, Uri.parse(linkFor('b')));
      client.calls.last.complete(fetched(webp(2)));
      await whenReady(other);
    });

    test('client failures start the wait', () async {
      final cache = await openCache();
      for (final (i, kind) in IconFailureKind.values.indexed) {
        await failOnce(cache, 'item$i', IconFailed(kind));
        final row = await rowFor('item$i');
        expect(row!.fileName, isNull, reason: '$kind');
        expect(row.failedUntil, atMoment(now.add(const Duration(hours: 24))));
        expect(row.failedLink, linkFor('item$i'));
        final lease = cache.acquire('item$i', linkFor('item$i'));
        expect(lease.value, isA<GenericItemIcon>());
        lease.release();
      }
      expect(client.calls, hasLength(IconFailureKind.values.length));
      expect(folderNames(), isEmpty);
    });

    test('six shown items run at most four requests at once and download each once', () async {
      final cache = await openCache();
      final ids = ['a', 'b', 'c', 'd', 'e', 'f'];
      final leases = [for (final id in ids) cache.acquire(id, linkFor(id))];
      expect(client.calls, hasLength(4));
      for (var done = 0; done < ids.length; done++) {
        await client.waitForCalls(math.min(ids.length, done + 4));
        client.calls[done].complete(fetched(webp(done + 1)));
      }
      for (final lease in leases) {
        await whenReady(lease);
      }
      expect(client.maxActive, 4);
      expect(client.calls.map((c) => c.link.toString()).toSet(), {
        for (final id in ids) linkFor(id),
      });
      expect(client.calls, hasLength(6));
    });

    test(
      'a cancelled request keeps its slot until its fetch returns',
      () async {
        client.answerCancel = false;
        final cache = await openCache(maxConcurrent: 1);
        cache.acquire('a', linkFor('a')).release();
        final b = cache.acquire('b', linkFor('b'));
        await Future<void>.value();
        expect(client.calls, hasLength(1));
        expect(client.calls.single.cancelled, isTrue);

        client.calls.single.complete(const IconCancelled());
        await client.waitForCalls(2);
        client.calls.last.complete(fetched(webp(2)));
        await whenReady(b);
        expect(client.maxActive, 1);
      },
    );

    test(
      'an item acquired again waits for its cancelled request to return',
      () async {
        client.answerCancel = false;
        final cache = await openCache();
        cache.acquire('a', linkFor('a')).release();
        final again = cache.acquire('a', linkFor('a'));
        await Future<void>.value();
        expect(client.calls, hasLength(1));
        expect(client.calls.single.cancelled, isTrue);

        client.calls.single.complete(const IconCancelled());
        await client.waitForCalls(2);
        client.calls.last.complete(fetched(webp(4)));
        await whenReady(again);
        expect(client.maxActive, 1);
      },
    );

    test(
      'a new link waits for the cancelled request of the old link',
      () async {
        client.answerCancel = false;
        final cache = await openCache();
        final old = cache.acquire('a', '$_base/a-old.webp');
        final current = cache.acquire('a', '$_base/a-new.webp');
        old.release();
        await Future<void>.value();
        expect(client.calls, hasLength(1));
        expect(client.calls.single.cancelled, isTrue);

        client.calls.single.complete(const IconCancelled());
        await client.waitForCalls(2);
        expect(client.calls.last.link.toString(), '$_base/a-new.webp');
        client.calls.last.complete(fetched(webp(5)));
        await whenReady(current);
        expect(client.maxActive, 1);
      },
    );

    test('releasing the last lease aborts without a wait', () async {
      final cache = await openCache();
      final lease = cache.acquire('a', linkFor('a'));
      lease.release();
      lease.release();
      expect(await client.calls.single.result, isA<IconCancelled>());
      await itemIconCacheIdle(cache);
      expect(client.calls.single.cancelled, isTrue);
      expect(await db.readItemIcons(), isEmpty);
      expect(folderNames(), isEmpty);
    });

    test(
      'a cancelled item sends one new request when acquired again',
      () async {
        final cache = await openCache();
        cache.acquire('a', linkFor('a')).release();
        expect(await client.calls.single.result, isA<IconCancelled>());
        final again = cache.acquire('a', linkFor('a'));
        expect(client.calls, hasLength(2));
        client.calls.last.complete(fetched(webp(8)));
        await whenReady(again);
        expect(client.calls, hasLength(2));
      },
    );

    test('releasing one of two leases keeps the download', () async {
      final cache = await openCache();
      final card = cache.acquire('a', linkFor('a'));
      final row = cache.acquire('a', linkFor('a'));
      card.release();
      client.calls.single.complete(fetched(webp(3)));
      await whenReady(row);
      expect(client.calls.single.cancelled, isFalse);
      expect(client.calls, hasLength(1));
    });

    test('storing under the injected budget evicts nothing', () async {
      final cache = await openCache(budget: 60);
      for (final (i, id) in ['a', 'b', 'c'].indexed) {
        final lease = cache.acquire(id, linkFor(id));
        client.calls[i].complete(fetched(webp(i + 1, extra: 7)));
        await whenReady(lease);
        await itemIconCacheIdle(cache);
        lease.release();
        now = now.add(const Duration(minutes: 1));
      }
      expect(await db.readItemIcons(), hasLength(3));
      expect(folderNames(), hasLength(3));
    });

    test(
      'over budget evicts least recently shown and keeps the new icon',
      () async {
        final cache = await openCache(budget: 50);

        Future<ItemIconView> show(String id, int seed) async {
          final lease = cache.acquire(id, linkFor(id));
          if (lease.value is GenericItemIcon) {
            client.calls.last.complete(fetched(webp(seed, extra: 7)));
            await whenReady(lease);
          }
          await itemIconCacheIdle(cache);
          final view = lease.value;
          lease.release();
          return view;
        }

        await show('a', 1);
        now = now.add(const Duration(hours: 2));
        await show('b', 2);
        now = now.add(const Duration(hours: 2));
        await show('a', 1);
        now = now.add(const Duration(hours: 2));
        expect(client.calls, hasLength(2));

        final newest = await show('c', 3);

        expect(newest, isA<ReadyItemIcon>());
        expect(await rowFor('b'), isNull);
        expect(await rowFor('a'), isNotNull);
        expect(await rowFor('c'), isNotNull);
        expect(
          folderNames(),
          unorderedEquals([
            iconName('a', webp(1, extra: 7)),
            iconName('c', webp(3, extra: 7)),
          ]),
        );
      },
    );

    test(
      'open removes a leftover tmp file and the item downloads when shown',
      () async {
        final body = webp(1);
        final tmp = File(
          '${dir.path}${Platform.pathSeparator}${iconName('a', body)}.tmp',
        )..writeAsBytesSync(body.sublist(0, 6));
        final cache = await openCache();
        expect(tmp.existsSync(), isFalse);
        expect(folderNames(), isEmpty);

        final lease = cache.acquire('a', linkFor('a'));
        expect(client.calls, hasLength(1));
        client.calls.single.complete(fetched(body));
        await whenReady(lease);
        expect(folderNames(), [iconName('a', body)]);
      },
    );

    test(
      'open removes files no row names before any acquire is admitted',
      () async {
        final kept = await seed('kept');
        final stray = File('${dir.path}${Platform.pathSeparator}stray.webp')
          ..writeAsBytesSync(webp(2));
        final cache = ItemIconCache(
          database: db,
          client: client,
          directory: dir,
          clock: () => now,
        );
        caches.add(cache);

        final opening = cache.open();
        final early = cache.acquire('kept', linkFor('kept'));
        final earlyMissing = cache.acquire('other', linkFor('other'));
        expect(early.value, isA<GenericItemIcon>());
        expect(earlyMissing.value, isA<GenericItemIcon>());
        expect(client.calls, isEmpty);

        await opening;
        expect(stray.existsSync(), isFalse);
        expect(kept.existsSync(), isTrue);
        expect(client.calls, isEmpty);
        expect(
          cache.acquire('kept', linkFor('kept')).value,
          isA<ReadyItemIcon>(),
        );
      },
    );
  });

  group('item icon cache lifecycle', () {
    test(
      'dispose aborts every request and releasing afterwards does not throw',
      () async {
        final cache = await openCache(maxConcurrent: 1);
        final first = cache.acquire('a', linkFor('a'));
        final queued = cache.acquire('b', linkFor('b'));
        expect(client.calls, hasLength(1));

        await cache.dispose();
        expect(await client.calls.single.result, isA<IconCancelled>());
        first.release();
        queued.release();
        final late = cache.acquire('c', linkFor('c'));
        expect(late.value, isA<GenericItemIcon>());
        late.release();
        expect(client.calls, hasLength(1));
      },
    );

    test('a cache that cannot open stays generic and sends nothing', () async {
      // A file where the folder should be makes opening fail.
      final blocked = File('${root.path}${Platform.pathSeparator}blocked')
        ..writeAsStringSync('');
      final cache = ItemIconCache(
        database: db,
        client: client,
        directory: Directory(blocked.path),
        clock: () => now,
      );
      caches.add(cache);

      await cache.open();
      final lease = cache.acquire('a', linkFor('a'));

      expect(lease.value, isA<GenericItemIcon>());
      lease.release();
      expect(client.calls, isEmpty);
    });

    test('a disabled cache is generic and sends nothing', () async {
      final cache = ItemIconCache.disabled();
      await cache.open();
      final lease = cache.acquire('a', linkFor('a'));
      expect(lease.value, isA<GenericItemIcon>());
      lease.release();
      await cache.dispose();
      expect(client.calls, isEmpty);
    });
  });
}
