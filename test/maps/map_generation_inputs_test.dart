import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../tool/maps/pack.dart';

String _hash(List<int> bytes) => sha256.convert(bytes).toString();

/// A tiny committed generation: one evidence source, one visible tile, one
/// empty-tile witness and a notice, with a hand-built manifest and index.
class _Generation {
  _Generation._(this.packs, this.id);

  final Directory packs;
  final String id;

  Directory get directory => Directory('${packs.path}/versions/$id');

  File file(String relative) => File('${directory.path}/$relative');

  static final visible = utf8.encode('visible tile');
  static final empty = utf8.encode('empty tile');
  static final terms = utf8.encode('terms');

  static String get emptyPath => 'evidence/tile-alpha/${_hash(empty)}.png';

  static Future<_Generation> create(Directory packs) async {
    final stage = Directory('${packs.path}/stage');
    final files = <String, List<int>>{
      'NOTICE.txt': utf8.encode('notice'),
      'artwork/m/F/0/0.png': visible,
      emptyPath: empty,
      'evidence/terms/a.md': terms,
    };
    final index = {
      'schemaVersion': 1,
      'sources': [
        {
          'path': 'terms/a.md',
          'url': 'https://example.invalid/a.md',
          'sha256': _hash(terms),
        },
        {
          'path': 'tiles/m/F/0_0.png',
          'url': 'https://example.invalid/0_0.png',
          'sha256': _hash(visible),
        },
        {
          'path': 'tiles/m/F/1_0.png',
          'url': 'https://example.invalid/1_0.png',
          'sha256': _hash(empty),
        },
        {
          'path': 'tiles/m/F/2_0.png',
          'url': 'https://example.invalid/2_0.png',
          'sha256': _hash(utf8.encode('never carried')),
        },
      ],
    };
    files['evidence/sources.json'] = utf8.encode(canonicalJson(index));
    for (final entry in files.entries) {
      final file = File('${stage.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value);
    }
    final paths = files.keys.toList()..sort();
    await File('${stage.path}/manifest.json').writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'outputs': [
          for (final path in paths)
            {'path': path, 'sha256': _hash(files[path]!)},
        ],
      }),
    );
    final id = _hash(await File('${stage.path}/manifest.json').readAsBytes());
    await Directory('${packs.path}/versions').create();
    await stage.rename('${packs.path}/versions/$id');
    await File('${packs.path}/active.json').writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'version': id,
        'manifest': 'versions/$id/manifest.json',
      }),
    );
    return _Generation._(packs, id);
  }
}

Matcher _formatMessage(Matcher message) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', message),
);

void main() {
  late Directory packs;
  late _Generation generation;

  setUp(() async {
    packs = await Directory.systemTemp.createTemp('blackgrid-generation-');
    addTearDown(() => packs.delete(recursive: true));
    generation = await _Generation.create(packs);
  });

  group('verifyCommittedGeneration', () {
    test('consistent generation passes and names its id', () async {
      final verified = await verifyCommittedGeneration(packs);
      expect(verified.id, generation.id);
      expect(verified.directory.path, generation.directory.path);
      expect(verified.manifest['outputs'], hasLength(5));
    });

    test('manifest hash differing from the id fails naming the id', () async {
      final manifest = generation.file('manifest.json');
      await manifest.writeAsString('${await manifest.readAsString()} ');
      await expectLater(
        verifyCommittedGeneration(packs),
        _formatMessage(contains(generation.id)),
      );
    });

    test('edited or extra generation file fails naming it', () async {
      await generation.file('NOTICE.txt').writeAsString('edited');
      await expectLater(
        verifyCommittedGeneration(packs),
        _formatMessage(contains('NOTICE.txt')),
      );
      await generation.file('NOTICE.txt').writeAsString('notice');
      await generation.file('extra/stray.txt').parent.create();
      await generation.file('extra/stray.txt').writeAsString('stray');
      await expectLater(
        verifyCommittedGeneration(packs),
        _formatMessage(contains('extra/stray.txt')),
      );
    });

    test('missing generation file fails naming it', () async {
      await generation.file('artwork/m/F/0/0.png').delete();
      await expectLater(
        verifyCommittedGeneration(packs),
        throwsA(predicate((error) => '$error'.contains('artwork/m/F/0/0.png'))),
      );
    });

    test('malformed active pointer fails', () async {
      await File('${packs.path}/active.json').writeAsString(
        canonicalJson({
          'schemaVersion': 1,
          'version': 'not-a-generation',
          'manifest': 'versions/not-a-generation/manifest.json',
        }),
      );
      await expectLater(
        verifyCommittedGeneration(packs),
        _formatMessage(contains('active pointer')),
      );
    });
  });

  group('FrozenInputs.fromGeneration', () {
    test('evidence sources resolve under evidence and tiles by hash', () async {
      final frozen = await FrozenInputs.fromGeneration(generation.directory);
      expect(await frozen.bytes('terms/a.md'), _Generation.terms);
      expect(await frozen.bytes('tiles/m/F/0_0.png'), _Generation.visible);
      expect(await frozen.bytes('tiles/m/F/1_0.png'), _Generation.empty);
      expect(
        canonicalJson(frozen.index),
        await generation.file('evidence/sources.json').readAsString(),
      );
    });

    test('edited evidence fails naming the file', () async {
      await generation.file('evidence/terms/a.md').writeAsString('edited');
      await expectLater(
        FrozenInputs.fromGeneration(generation.directory),
        _formatMessage(contains('terms/a.md')),
      );
    });

    test('reading an uncarried source names its path', () async {
      final frozen = await FrozenInputs.fromGeneration(generation.directory);
      await expectLater(
        frozen.bytes('tiles/m/F/2_0.png'),
        _formatMessage(
          allOf(
            contains('tiles/m/F/2_0.png'),
            contains(generation.id),
            contains('rebuild --raw'),
          ),
        ),
      );
      await expectLater(
        frozen.bytes('tiles/never/listed.png'),
        throwsFormatException,
      );
    });

    test(
      'tile carrier that no longer matches its hash fails naming it',
      () async {
        final frozen = await FrozenInputs.fromGeneration(generation.directory);
        await generation.file('artwork/m/F/0/0.png').writeAsString('edited');
        await expectLater(
          frozen.bytes('tiles/m/F/0_0.png'),
          _formatMessage(contains('tiles/m/F/0_0.png')),
        );
      },
    );
  });

  group('pruneSupersededGenerations', () {
    test('pruning deletes only 64-hex non-active generations', () async {
      final versions = Directory('${packs.path}/versions');
      final old = 'ab' * 32;
      final names = {
        'old': old,
        'old2': 'cd' * 32,
        'upper': 'FE' * 32,
        'short': 'ab' * 31,
        'long': '${'ab' * 32}0',
        'staging': '.${'ef' * 32}.staging',
        'plain': 'notes',
      };
      for (final name in names.values) {
        await File('${versions.path}/$name/keep.txt').create(recursive: true);
      }
      // A plain file whose name looks like an id is not a generation folder.
      await File('${versions.path}/${'12' * 32}').writeAsString('x');

      final deleted = await pruneSupersededGenerations(packs, generation.id);

      expect(deleted, unorderedEquals([old, 'cd' * 32]));
      final remaining = {
        await for (final entity in versions.list())
          entity.path.replaceAll('\\', '/').split('/').last,
      };
      expect(remaining, {
        generation.id,
        names['upper']!,
        names['short']!,
        names['long']!,
        names['staging']!,
        names['plain']!,
        '12' * 32,
      });
      expect(generation.file('manifest.json').existsSync(), isTrue);
    });

    test('a packs folder without versions prunes nothing', () async {
      final empty = await Directory.systemTemp.createTemp('blackgrid-prune-');
      addTearDown(() => empty.delete(recursive: true));
      expect(await pruneSupersededGenerations(empty, 'ab' * 32), isEmpty);
    });
  });

  group('requireNoInterruptedPromotion', () {
    test('clean packs folder passes', () async {
      await requireNoInterruptedPromotion(packs);
      await requireNoInterruptedPromotion(Directory('${packs.path}/absent'));
    });

    test(
      'leftover precheck names a staging folder of any id or active.next.json',
      () async {
        final staging = Directory(
          '${packs.path}/versions/.${'ab' * 32}.staging',
        );
        await staging.create();
        await expectLater(
          requireNoInterruptedPromotion(packs),
          _formatMessage(
            equals(
              'Interrupted map pack promotion left '
              '${staging.path.replaceAll('\\', '/')}; '
              'inspect and remove it, then rerun.',
            ),
          ),
        );
        await staging.delete();
        await File('${packs.path}/active.next.json').writeAsString('x');
        await expectLater(
          requireNoInterruptedPromotion(packs),
          _formatMessage(
            allOf(
              startsWith('Interrupted map pack promotion left '),
              contains('active.next.json'),
              endsWith('inspect and remove it, then rerun.'),
            ),
          ),
        );
      },
    );
  });
}
