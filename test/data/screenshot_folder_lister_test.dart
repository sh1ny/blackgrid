import 'dart:io';

import 'package:blackgrid/data/screenshot_folder_lister.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:blackgrid/domain/screenshot_cleanup.dart';
import 'package:test/test.dart';

const _gameName =
    '2026-11-22[14-05]_-120.5, 2.1, 33.4_0, 0.70711, 0, 0.70711_12.34.png';
final _time = DateTime(2026, 11, 22, 14, 5, 10);
final _raid = Raid(
  mapId: null,
  mode: null,
  queueTime: null,
  startTime: DateTime(2026, 11, 22, 14),
  startId: const LogRecordId('session', LogFile.application, 1),
  entry: RaidEntry.noQueue,
  endTime: DateTime(2026, 11, 22, 14, 30),
);

void main() {
  late Directory temp;
  late Directory folder;
  final lister = ScreenshotFolderLister();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('blackgrid-cleanup-');
    folder = await Directory('${temp.path}/screenshots').create();
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<File> createFile(String path) async {
    final file = File(path);
    await file.writeAsString('synthetic screenshot');
    await file.setLastModified(_time);
    return file;
  }

  test('screenshot-cleanup: Files that are not game screenshots', () async {
    final notes = await createFile('${folder.path}/notes.png');
    final renamed = await createFile(
      '${folder.path}/2026-11-22[14-05]_renamed.png',
    );
    final bitmap = await createFile('${folder.path}/shot.bmp');
    final subfolder = await Directory('${folder.path}/nested').create();
    final nested = await createFile('${subfolder.path}/$_gameName');
    final eligible = await createFile('${folder.path}/$_gameName');

    final listing = await lister.list(folder.path);
    expect(listing, isA<ScreenshotFolderListed>());
    final entries = (listing as ScreenshotFolderListed).entries;
    expect(pickRaidScreenshots(entries, _raid), [_gameName]);
    final eligibleEntry = entries.singleWhere(
      (entry) => entry.name == _gameName,
    );
    expect(eligibleEntry.isFile, isTrue);
    expect(eligibleEntry.isLink, isFalse);
    expect(eligibleEntry.modified, _time);
    for (final file in [notes, renamed, bitmap, nested, eligible]) {
      expect(await file.readAsString(), 'synthetic screenshot');
    }
  });

  test('screenshot-cleanup: A link to a file elsewhere', () async {
    final target = await createFile('${temp.path}/target.png');
    final link = Link('${folder.path}/$_gameName');
    try {
      await link.create(target.path);
    } on FileSystemException catch (error) {
      markTestSkipped('Creating a file symlink is not permitted: $error');
      return;
    }

    final listing = await lister.list(folder.path);
    expect(listing, isA<ScreenshotFolderListed>());
    expect(
      pickRaidScreenshots((listing as ScreenshotFolderListed).entries, _raid),
      isEmpty,
    );
    expect(await link.exists(), isTrue);
    expect(await target.readAsString(), 'synthetic screenshot');
  });

  test('a missing screenshot folder is reported as missing', () async {
    expect(
      await lister.list('${temp.path}/missing'),
      isA<ScreenshotFolderMissing>(),
    );
  });
}
