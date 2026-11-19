import 'dart:io';

import 'package:blackgrid/data/local_paths.dart';
import 'package:blackgrid/data/retired_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late LocalPaths paths;
  final sep = Platform.pathSeparator;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('retired-tokens-');
    paths = LocalPaths(Directory('${temp.path}${sep}Blackgrid')..createSync());
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Directory credentials() => Directory('${paths.root.path}${sep}credentials');
  File inCredentials(String name) => File('${credentials().path}$sep$name');
  File put(String relative) => File('${paths.root.path}$sep$relative')
    ..createSync(recursive: true)
    ..writeAsStringSync('x');

  test('local-data-durability: Upgrade with saved tokens', () async {
    put('credentials${sep}pvp.dpapi');
    put('credentials${sep}pve.dpapi');
    put('blackgrid.sqlite');
    put('logs${sep}scan-timings.jsonl');
    put('item-icons${sep}a.png');

    await deleteRetiredTokens(paths);

    expect(credentials().existsSync(), isFalse);
    expect(File(paths.database.path).existsSync(), isTrue);
    expect(
      File('${paths.logs.path}${sep}scan-timings.jsonl').existsSync(),
      isTrue,
    );
    expect(File('${paths.itemIcons.path}${sep}a.png').existsSync(), isTrue);
  });

  test('local-data-durability: Temporary token file left by a crash', () async {
    put('credentials${sep}pvp.dpapi.4242.1700000000.tmp');

    await deleteRetiredTokens(paths);

    expect(credentials().existsSync(), isFalse);
  });

  test('local-data-durability: Nothing saved', () async {
    await deleteRetiredTokens(paths);

    expect(credentials().existsSync(), isFalse);
    expect(paths.root.listSync(), isEmpty);
  });

  test('local-data-durability: A file cannot be deleted', () async {
    final locked = put('credentials${sep}pvp.dpapi');
    put('credentials${sep}seasonal.dpapi');

    // The first launch cannot delete the locked file; it must not throw.
    await deleteRetiredTokens(
      paths,
      deleteFile: (file) async {
        if (file.path == locked.path) {
          throw const FileSystemException('locked');
        }
        await file.delete();
      },
    );

    expect(locked.existsSync(), isTrue);
    expect(inCredentials('seasonal.dpapi').existsSync(), isFalse);
    expect(credentials().existsSync(), isTrue);

    // The next launch deletes it once it is unlocked.
    await deleteRetiredTokens(paths);

    expect(locked.existsSync(), isFalse);
    expect(credentials().existsSync(), isFalse);
  });

  test('local-data-durability: Unexpected file in the folder', () async {
    put('credentials${sep}pvp.dpapi');
    put('credentials${sep}pve.dpapi.1.2.tmp');
    final notes = put('credentials${sep}notes.txt');
    final backup = put('credentials${sep}pvp.dpapi.bak');
    final unknownMode = put('credentials${sep}other.dpapi');

    await deleteRetiredTokens(paths);

    expect(inCredentials('pvp.dpapi').existsSync(), isFalse);
    expect(inCredentials('pve.dpapi.1.2.tmp').existsSync(), isFalse);
    expect(notes.existsSync(), isTrue);
    expect(backup.existsSync(), isTrue);
    expect(unknownMode.existsSync(), isTrue);
    expect(credentials().existsSync(), isTrue);
  });
}
