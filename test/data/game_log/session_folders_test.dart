import 'dart:io';

import 'package:blackgrid/data/game_log/session_folders.dart';
import 'package:test/test.dart';

const _older = 'log_2026.10.30_20-27-43_1.3.0.0.48484';
const _nine = 'log_2026.11.02_9-00-00_1.3.0.0.48484';
const _ten = 'log_2026.11.02_10-00-00_1.3.0.0.48484';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('blackgrid-folders-');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('lists session folders by date and ignores other entries', () async {
    await Directory('${root.path}/$_ten').create();
    await Directory('${root.path}/$_older').create();
    await Directory('${root.path}/screenshots').create();
    await File('${root.path}/log_2026.10.01_10-00-00_1.3.0.0.48484')
        .writeAsString('not a directory');

    final folders = await listSessionFolders(root.path);
    expect(folders.map((folder) => folder.name), [_older, _ten]);
    expect(folders.map((folder) => folder.path.replaceAll('\\', '/')), [
      '${root.path}/$_older'.replaceAll('\\', '/'),
      '${root.path}/$_ten'.replaceAll('\\', '/'),
    ]);
    expect(folders.map((folder) => folder.time), [
      DateTime(2026, 10, 30, 20, 27, 43),
      DateTime(2026, 11, 2, 10),
    ]);
    expect(parseSessionFolderTime('screenshots'), isNull);
    expect(parseSessionFolderTime(_older), DateTime(2026, 10, 30, 20, 27, 43));
  });

  test('one-digit hour sorts before two-digit hour', () async {
    const nineLaterName = 'log_2026.11.02_9-00-00_2';
    await Directory('${root.path}/$_ten').create();
    await Directory('${root.path}/$nineLaterName').create();
    await Directory('${root.path}/$_nine').create();

    final folders = await listSessionFolders(root.path);
    expect(folders.map((folder) => folder.name), [_nine, nineLaterName, _ten]);
    expect(compareSessionFolderNames(_nine, _ten), lessThan(0));
    expect(compareSessionFolderNames(_ten, _nine), greaterThan(0));
    expect(compareSessionFolderNames(_nine, nineLaterName), lessThan(0));
    expect(compareSessionFolderNames(_nine, _nine), 0);
    expect(parseSessionFolderTime(_nine), DateTime(2026, 11, 2, 9));
  });
}
