import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/app_icon/ico.dart';
import '../../../tool/app_icon/render.dart';
import '../../../tool/app_icon/sheet.dart';
import 'support/icon_fixture.dart';

void main() {
  late Directory root;
  late RecordingRasterizer rasterizer;

  setUp(() {
    root = Directory.systemTemp.createTempSync('app_icon_sheet_');
    rasterizer = RecordingRasterizer();
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<IconToolResult> run(String candidates, {String? out}) => writeSheet(
    candidatesDir: candidates,
    outputPath: out ?? '${root.path}/out/index.html',
    rasterize: rasterizer.call,
  );

  group('unrecorded candidates', () {
    test('an unrecorded PNG or SVG in the candidates folder fails naming it '
        'and writes no sheet', () async {
      for (final (concepts, vectors, stray) in [
        (
          ['01-a.png', '02-stray.png'],
          {'a.svg': validSvg},
          'concepts/02-stray.png',
        ),
        (['01-a.png'], {'a.svg': validSvg, 'b.svg': validSvg}, 'vector/b.svg'),
      ]) {
        final dir = writeCandidates(
          root,
          concepts: concepts,
          vectors: vectors,
          recorded: [
            for (final c in concepts)
              if ('concepts/$c' != stray) 'concepts/$c',
            for (final v in vectors.keys)
              if ('vector/$v' != stray) 'vector/$v',
          ],
        );
        final out = '${root.path}/out/index.html';

        final result = await run(dir, out: out);

        expect(result.ok, isFalse, reason: stray);
        expect(result.exitCode, 1);
        expect(result.messages.join('\n'), contains(stray));
        expect(File(out).existsSync(), isFalse);
        expect(File('$out.tmp').existsSync(), isFalse);
        expect(rasterizer.calls, isEmpty);
        Directory(dir).deleteSync(recursive: true);
      }
    });
  });

  group('sheet with ten candidates', () {
    test('four concepts and six vectors give ten columns at all ten sizes on '
        'both backgrounds, with no external URL', () async {
      final concepts = ['01-a.png', '02-b.png', '03-c.png', '04-d.png'];
      final vectors = {for (final n in 'abcdef'.split('')) '$n.svg': validSvg};
      final dir = writeCandidates(root, concepts: concepts, vectors: vectors);
      final out = '${root.path}/out/index.html';

      final result = await run(dir, out: out);

      expect(result.ok, isTrue, reason: result.messages.join('\n'));
      final html = File(out).readAsStringSync();
      expect(
        RegExp('class="candidate"').allMatches(html),
        hasLength(10),
        reason: 'one column per candidate',
      );
      for (final file in [
        for (final c in concepts) 'concepts/$c',
        for (final v in vectors.keys) 'vector/$v',
      ]) {
        expect(html, contains('data-file="$file"'));
        for (final size in icoRequiredSizes) {
          for (final bg in ['light', 'dark']) {
            expect(
              html,
              contains(
                'data-file="$file" data-size="$size" data-background="$bg"',
              ),
              reason: '$file at $size on $bg',
            );
          }
        }
      }
      expect(html, contains('#F3F4F6'));
      expect(html, contains('#11161A'));
      expect(html, contains('image-rendering: pixelated'));
      expect(html, contains('browser-scaled concept'));
      expect(html, contains('Test Author'));
      expect(html, contains('ChatGPT'));
      expect(html, contains('concepts/01-a.png'), reason: 'concept shown');

      expect(html, isNot(contains('http:')));
      expect(html, isNot(contains('https:')));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('@font-face')));
      expect(html, isNot(contains('@import')));
      expect(html, isNot(matches(RegExp(r'(src|href)\s*=\s*"?\s*//'))));
      expect(html, isNot(contains('<link')));
      // Every vector is rastered at all ten sizes, once each.
      expect(rasterizer.calls, hasLength(6 * icoRequiredSizes.length));
      expect(File('$out.tmp').existsSync(), isFalse);
    });

    test('rejects a rasterizer result of the wrong length', () async {
      final dir = writeCandidates(root, vectors: {'a.svg': validSvg});
      final out = '${root.path}/out/index.html';

      final result = await writeSheet(
        candidatesDir: dir,
        outputPath: out,
        rasterize: (compiled, size, name) async => Uint8List(3),
      );

      expect(result.ok, isFalse);
      expect(
        result.messages.join('\n'),
        allOf(contains('vector/a.svg'), contains('16')),
      );
      expect(File(out).existsSync(), isFalse);
    });
  });

  group('invalid vector candidate', () {
    test('a vector that fails to compile exits non-zero naming it and leaves '
        'the earlier sheet', () async {
      final dir = writeCandidates(
        root,
        concepts: ['01-a.png'],
        vectors: {'good.svg': validSvg, 'bad.svg': rejectedSvg},
      );
      final out = File('${root.path}/out/index.html')
        ..createSync(recursive: true)
        ..writeAsStringSync('earlier sheet');
      final before = out.readAsBytesSync();

      final result = await run(dir, out: out.path);

      expect(result.ok, isFalse);
      expect(result.exitCode, 1);
      expect(result.messages.join('\n'), contains('vector/bad.svg'));
      expect(out.readAsBytesSync(), before);
      expect(File('${out.path}.tmp').existsSync(), isFalse);
      expect(rasterizer.calls, isEmpty, reason: 'compile everything first');
    });

    test('a vector over 64 KiB fails naming it before rendering', () async {
      final big = '$validSvg<!-- ${'x' * maxSourceBytes} -->';
      final dir = writeCandidates(root, vectors: {'big.svg': big});

      final result = await run(dir);

      expect(result.ok, isFalse);
      expect(result.messages.join('\n'), contains('vector/big.svg'));
      expect(rasterizer.calls, isEmpty);
    });
  });

  group('candidate bound', () {
    test('more than 12 candidates exit before rendering and name the '
        'count', () async {
      final vectors = {for (var i = 0; i < 13; i++) 'v$i.svg': validSvg};
      final dir = writeCandidates(root, vectors: vectors);
      final out = '${root.path}/out/index.html';

      final result = await run(dir, out: out);

      expect(result.ok, isFalse);
      expect(result.messages.join('\n'), allOf(contains('13'), contains('12')));
      expect(rasterizer.calls, isEmpty);
      expect(File(out).existsSync(), isFalse);
    });

    test('exactly 12 candidates are accepted', () async {
      final vectors = {for (var i = 0; i < 12; i++) 'v$i.svg': validSvg};
      final dir = writeCandidates(root, vectors: vectors);

      final result = await run(dir);

      expect(result.ok, isTrue, reason: result.messages.join('\n'));
    });
  });
}
