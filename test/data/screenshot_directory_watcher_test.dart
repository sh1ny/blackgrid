import 'dart:async';
import 'dart:io';

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
    final latest = (await watcher.readLatest())!;
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
    expect(await read, isNull);
    await watcher.rescan();
    expect((await watcher.readLatest())!.bytes, [1, 2, 3]);
  });

  test('disabled missing empty overlimit and shutdown are honest', () async {
    await watcher.bind('');
    expect(statuses.last, MapInputStatus.disabled);
    expect(await watcher.readLatest(), isNull);
    await watcher.bind('${directory.path}${Platform.pathSeparator}missing');
    expect(statuses.last, MapInputStatus.missing);
    await watcher.bind(directory.path);
    expect(statuses.last, MapInputStatus.empty);
    await File('${directory.path}${Platform.pathSeparator}empty.png')
        .writeAsBytes([]);
    expect(await watcher.readLatest(), isNull);
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
    expect((await watcher.readLatest())!.path, newest.path);
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
      expect(await watcher.readLatest(), isNull);
      expect(statuses.last, MapInputStatus.error);
    },
  );

  test('directory rebind fences a delayed old read', () async {
    await watcher.bind(directory.path);
    await File('${directory.path}${Platform.pathSeparator}a.png')
        .writeAsBytes([1]);
    final pending = watcher.readLatest();
    await watcher.bind('');
    expect(await pending, isNull);
  });
}

Future<ScreenshotDirectoryWatcher> _replace(
  ScreenshotDirectoryWatcher old,
  ScreenshotDirectoryWatcher next,
) async {
  await old.close();
  return next;
}
