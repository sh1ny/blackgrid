import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../tool/maps/pack.dart';

void main() {
  late Directory root;
  late Directory packs;
  late File pubspec;
  var fetches = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('artwork-stage-path-');
    packs = await Directory('${root.path}/packs').create();
    pubspec = File('${root.path}/missing-pubspec.yaml');
    fetches = 0;
  });

  tearDown(() async => root.delete(recursive: true));

  Future<void> run(Directory stage) async {
    await stageArtworkRefresh(
      packs,
      pubspec,
      stage: stage,
      toolchain: const {},
      fetch: (uri) async {
        fetches++;
        return Uint8List(0);
      },
      reviewedContext: MapBuildContext.reviewed(
        calibration: const {},
        sourceLock: const {},
        noticeBytes: const [],
      ),
    );
  }

  Future<void> expectRefused(Directory stage) async {
    await expectLater(run(stage), throwsA(isA<FormatException>()));
    expect(fetches, 0);
    expect(await stage.exists(), isFalse);
    expect(await Directory('${stage.path}.raw').exists(), isFalse);
  }

  test(
    'rejects a missing stage within the active pack tree before input reads',
    () async {
      final sentinel = File('${packs.path}/sentinel')
        ..writeAsStringSync('keep');
      await expectRefused(Directory('${packs.path}/new-stage'));
      expect(await sentinel.readAsString(), 'keep');
    },
  );

  test('rejects a separator-only stage before input reads', () async {
    await expectLater(run(Directory('//')), throwsA(isA<FormatException>()));
    expect(fetches, 0);
  });

  test('rejects a missing stage through a linked pack ancestor', () async {
    final alias = Link('${root.path}/alias');
    await alias.create(packs.path);
    addTearDown(() => alias.delete());
    await expectRefused(Directory('${alias.path}/new-stage'));
  });

  test(
    'rejects an existing file at the stage path before input reads',
    () async {
      final stage = Directory('${root.path}/stage');
      final file = File(stage.path)..writeAsStringSync('keep');
      await expectRefused(stage);
      expect(await file.readAsString(), 'keep');
    },
  );

  test('rejects an existing file at the raw path before input reads', () async {
    final stage = Directory('${root.path}/stage');
    final file = File('${stage.path}.raw')..writeAsStringSync('keep');
    await expectRefused(stage);
    expect(await file.readAsString(), 'keep');
  });

  for (final separator in Platform.isWindows ? ['/', r'\'] : ['/']) {
    test('rejects a raw sibling with a trailing $separator', () async {
      final stage = Directory('${root.path}/stage');
      final file = File('${stage.path}.raw')..writeAsStringSync('keep');
      await expectRefused(Directory('${stage.path}$separator'));
      expect(await file.readAsString(), 'keep');
    });
  }

  test('rejects raw output colliding with the protected pubspec', () async {
    final stage = Directory('${root.path}/stage');
    pubspec = File('${stage.path}.raw');
    const contents =
        'name: fixture\nflutter:\n  assets:\n'
        '$mapPackAssetsBegin\n$mapPackAssetsEnd\n';
    await pubspec.writeAsString(contents);
    await expectRefused(stage);
    expect(await pubspec.readAsString(), contents);
  });

  test(
    'accepts a fresh sibling whose name only shares the pack prefix',
    () async {
      final stage = Directory('${packs.path}-outside');
      await expectLater(run(stage), throwsA(isA<FileSystemException>()));
      expect(fetches, 0);
      expect(await stage.exists(), isFalse);
      expect(await Directory('${stage.path}.raw').exists(), isFalse);
    },
  );

  test('rejects a dangling stage link', () async {
    final stage = Directory('${root.path}/stage');
    final target = await Directory('${root.path}/target').create();
    final link = Link(stage.path);
    await link.create(target.path);
    await target.delete();
    addTearDown(() => link.delete());
    await expectRefused(stage);
  });
}
