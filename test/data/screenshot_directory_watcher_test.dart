import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/data/screenshot_directory_watcher.dart';
import 'package:blackgrid/domain/map_session.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late ScreenshotDirectoryWatcher watcher;
  late List<SavedScreenshot> arrivals;
  late List<MapInputStatus> statuses;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('blackgrid-saved-input-');
    watcher = ScreenshotDirectoryWatcher(
      stabilityDelay: const Duration(milliseconds: 5),
      pollInterval: const Duration(days: 1),
    );
    arrivals = [];
    statuses = [];
    watcher.screenshots.listen(arrivals.add);
    watcher.statuses.listen((state) => statuses.add(state.$1));
  });
  tearDown(() async {
    await watcher.close();
    await directory.delete(recursive: true);
  });

  test('initial files are baseline; explicit Read Latest shares deterministic time/path order', () async {
    final a = await File('${directory.path}${Platform.pathSeparator}a.png')
        .writeAsBytes([1]);
    final z = await File('${directory.path}${Platform.pathSeparator}z.png')
        .writeAsBytes([2]);
    final stamp = DateTime(2026, 10, 7);
    await a.setLastModified(stamp);
    await z.setLastModified(stamp);
    await watcher.bind(directory.path);
    await watcher.rescan();
    expect(arrivals, isEmpty);
    final latest = _found(await watcher.readLatest());
    expect(latest.path, z.path);
    expect(latest.bytes, [2]);
    expect(latest.modifiedAt, stamp);
  });

  test(
    'created renamed and duplicate events coalesce by stable content identity',
    () async {
      await watcher.bind(directory.path);
      await File('${directory.path}${Platform.pathSeparator}a.png')
          .writeAsBytes([1]);
      await File('${directory.path}${Platform.pathSeparator}z.png')
          .writeAsBytes([2]);
      await watcher.rescan();
      expect(arrivals.last.bytes, [2]);
      final count = arrivals.length;
      await watcher.rescan();
      await File('${directory.path}${Platform.pathSeparator}z.png')
          .rename('${directory.path}${Platform.pathSeparator}zz.png');
      await watcher.rescan();
      expect(arrivals.length, count);
      await File('${directory.path}${Platform.pathSeparator}zz.png')
          .writeAsBytes([3]);
      await watcher.rescan();
      expect(arrivals.last.bytes, [3]);
    },
  );

  test('write in progress does not publish unstable bytes; subsequent complete file is read', () async {
    watcher = await _replace(
      watcher,
      ScreenshotDirectoryWatcher(
        stabilityDelay: const Duration(milliseconds: 50),
        pollInterval: const Duration(days: 1),
      ),
    );
    watcher.screenshots.listen(arrivals.add);
    await watcher.bind(directory.path);
    final file = await File('${directory.path}${Platform.pathSeparator}a.png')
        .writeAsBytes([1]);
    final read = watcher.readLatest();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await file.writeAsBytes([1, 2, 3]);
    expect(await read, isA<ScreenshotUnavailable>());
    await watcher.rescan();
    expect(_found(await watcher.readLatest()).bytes, [1, 2, 3]);
  });

  test('disabled missing empty overlimit and shutdown are honest', () async {
    await watcher.bind('');
    expect(statuses.last, MapInputStatus.disabled);
    expect(await watcher.readLatest(), isA<ScreenshotUnavailable>());
    await watcher.bind('${directory.path}${Platform.pathSeparator}missing');
    expect(statuses.last, MapInputStatus.missing);
    expect(await watcher.readLatest(), isA<ScreenshotUnavailable>());
    await watcher.bind(directory.path);
    expect(statuses.last, MapInputStatus.empty);
    expect(await watcher.readLatest(), isA<ScreenshotEmpty>());
    await File('${directory.path}${Platform.pathSeparator}empty.png')
        .writeAsBytes([]);
    expect(await watcher.readLatest(), isA<ScreenshotUnavailable>());
    expect(statuses.last, MapInputStatus.unavailable);
    await watcher.close();
    final count = arrivals.length;
    await File('${directory.path}${Platform.pathSeparator}new.png')
        .writeAsBytes([1]);
    await watcher.rescan();
    expect(arrivals.length, count);
  });

  test('older and equal-time lower-path files cannot replace newer observed evidence', () async {
    await watcher.bind(directory.path);
    final newest = await File('${directory.path}${Platform.pathSeparator}z.png')
        .writeAsBytes([1]);
    final time = DateTime(2026, 10, 7);
    await newest.setLastModified(time);
    await watcher.rescan();
    final count = arrivals.length;
    final old = await File('${directory.path}${Platform.pathSeparator}old.png')
        .writeAsBytes([2]);
    await old.setLastModified(time.subtract(const Duration(minutes: 1)));
    final tied = await File('${directory.path}${Platform.pathSeparator}a.png')
        .writeAsBytes([3]);
    await tied.setLastModified(time);
    await watcher.rescan();
    expect(arrivals.length, count);
    expect(_found(await watcher.readLatest()).path, newest.path);
  });

  test(
    'overlimit files report error instead of relabeling as unavailable',
    () async {
      watcher = await _replace(
        watcher,
        ScreenshotDirectoryWatcher(stabilityDelay: Duration.zero, maxBytes: 2),
      );
      watcher.statuses.listen((state) => statuses.add(state.$1));
      await watcher.bind(directory.path);
      await File('${directory.path}${Platform.pathSeparator}large.png')
          .writeAsBytes([1, 2, 3]);
      expect(await watcher.readLatest(), isA<ScreenshotUnavailable>());
      expect(statuses.last, MapInputStatus.error);
    },
  );

  test('directory rebind fences a delayed old read', () async {
    await watcher.bind(directory.path);
    await File('${directory.path}${Platform.pathSeparator}a.png')
        .writeAsBytes([1]);
    final pending = watcher.readLatest();
    await watcher.bind('');
    expect(await pending, isA<ScreenshotDiscarded>());
  });

  test('map-controls: Read latest result distinguishes empty from unavailable', () async {
    // A folder that exists but holds no png or jpeg is empty, not unavailable.
    await File('${directory.path}${Platform.pathSeparator}notes.txt')
        .writeAsString('not a screenshot');
    await watcher.bind(directory.path);
    expect(await watcher.readLatest(), isA<ScreenshotEmpty>());
    // No folder was ever bound.
    final unbound = ScreenshotDirectoryWatcher();
    addTearDown(unbound.close);
    expect(await unbound.readLatest(), isA<ScreenshotUnavailable>());
  });

  test('map-controls: A closed watcher discards a read', () async {
    await watcher.bind(directory.path);
    await watcher.close();
    expect(await watcher.readLatest(), isA<ScreenshotDiscarded>());
  });

  test(
    'map-controls: A read in flight when the watcher closes is discarded',
    () async {
      watcher = await _replace(
        watcher,
        ScreenshotDirectoryWatcher(
          stabilityDelay: const Duration(milliseconds: 50),
          pollInterval: const Duration(days: 1),
        ),
      );
      await watcher.bind(directory.path);
      await File('${directory.path}${Platform.pathSeparator}a.png')
          .writeAsBytes([1]);
      final pending = watcher.readLatest();
      await watcher.close();
      expect(await pending, isA<ScreenshotDiscarded>());
    },
  );

  group('paths the real filesystem cannot be made to take', () {
    late File real;
    setUp(() async {
      real = await File('${directory.path}${Platform.pathSeparator}a.png')
          .writeAsBytes([1]);
      await watcher.bind(directory.path);
    });

    Future<ScreenshotRead> readWith(Directory Function() fake) =>
        IOOverrides.runZoned(
          () => watcher.readLatest(),
          createDirectory: (_) => fake(),
        );

    test('a FileSystemException while listing is unavailable', () async {
      final read = await readWith(
        () => _FakeDirectory(
          const [],
          listFailure: const FileSystemException('denied'),
        ),
      );
      expect(read, isA<ScreenshotUnavailable>());
    });

    test('a FileSystemException during the read is unavailable', () async {
      final read = await readWith(
        () => _FakeDirectory([
          _FakeFile(real, () async => throw const FileSystemException('gone')),
        ]),
      );
      expect(read, isA<ScreenshotUnavailable>());
    });

    test(
      'a watcher that closes during the read is discarded, not changing',
      () async {
        final read = await readWith(
          () => _FakeDirectory([
            _FakeFile(real, () async {
              unawaited(watcher.close());
              return Uint8List.fromList([
                1,
                2,
                3,
              ]); // length mismatches the stat
            }),
          ]),
        );
        expect(read, isA<ScreenshotDiscarded>());
      },
    );

    test(
      'a generation that moves during the read is discarded, not changing',
      () async {
        final read = await readWith(
          () => _FakeDirectory([
            _FakeFile(real, () async {
              unawaited(watcher.bind(''));
              return Uint8List.fromList([1, 2, 3]);
            }),
          ]),
        );
        expect(read, isA<ScreenshotDiscarded>());
      },
    );
  });
}

class _FakeDirectory implements Directory {
  _FakeDirectory(this.entries, {this.listFailure});
  final List<FileSystemEntity> entries;
  final FileSystemException? listFailure;

  @override
  Future<bool> exists() async => true;

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => listFailure == null
      ? Stream.fromIterable(entries)
      : Stream.error(listFailure!);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stats like [real] but reads through [onRead].
class _FakeFile implements File {
  _FakeFile(this.real, this.onRead);
  final File real;
  final Future<Uint8List> Function() onRead;

  @override
  String get path => real.path;

  @override
  Future<FileStat> stat() => real.stat();

  @override
  Future<Uint8List> readAsBytes() => onRead();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SavedScreenshot _found(ScreenshotRead result) => switch (result) {
  ScreenshotFound(:final screenshot) => screenshot,
  ScreenshotEmpty() ||
  ScreenshotUnavailable() ||
  ScreenshotDiscarded() => fail('Expected a found screenshot, got $result'),
};

Future<ScreenshotDirectoryWatcher> _replace(
  ScreenshotDirectoryWatcher old,
  ScreenshotDirectoryWatcher next,
) async {
  await old.close();
  return next;
}
