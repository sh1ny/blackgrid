import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/app_icon/build.dart';
import '../../../tool/app_icon/ico.dart';
import '../../../tool/app_icon/provenance.dart';
import '../../../tool/app_icon/render.dart';
import 'support/icon_fixture.dart';

void main() {
  late Directory root;
  late RecordingRasterizer rasterizer;
  late String candidates;
  late String iconDir;
  late String icoPath;

  setUp(() {
    root = Directory.systemTemp.createTempSync('app_icon_build_');
    rasterizer = RecordingRasterizer();
    candidates = writeCandidates(
      root,
      concepts: ['01-a.png'],
      vectors: {'a.svg': validSvg},
    );
    iconDir = (Directory('${root.path}/app_icon')..createSync()).path;
    icoPath = '${root.path}/app_icon.ico';
  });
  tearDown(() => root.deleteSync(recursive: true));

  String sourceRecordText({String picked = 'vector/a.svg'}) =>
      '''
{
  "schemaVersion": 1,
  "author": "Blackgrid project",
  "method": "hand-authored",
  "tools": ["editor"],
  "date": "2026-11-01",
  "pickedCandidate": "$picked",
  "pickDate": "2026-11-01",
  "concept": "concepts/01-a.png",
  "sha256": {
    "app_icon.svg": "${'0' * 64}",
    "app_icon.ico": "${'0' * 64}"
  }
}
''';

  Future<IconToolResult> run() => buildIcon(
    iconDir: iconDir,
    icoPath: icoPath,
    candidatesDir: candidates,
    rasterize: rasterizer.call,
  );

  void writeSource(String svg, {String? record, String? small}) {
    File('$iconDir/$sourceSvgName').writeAsStringSync(svg);
    if (small != null) {
      File('$iconDir/$smallSvgName').writeAsStringSync(small);
    }
    File('$iconDir/provenance.json')
        .writeAsStringSync(record ?? sourceRecordText());
  }

  group('icon build', () {
    test('a source the compiler rejects exits non-zero naming it and leaves '
        'the ico and record unchanged', () async {
      writeSource(rejectedSvg);
      File(icoPath).writeAsBytesSync([1, 2, 3]);
      final recordBefore = File('$iconDir/provenance.json').readAsBytesSync();

      final result = await run();

      expect(result.ok, isFalse);
      expect(result.exitCode, 1);
      expect(result.messages.join('\n'), contains(sourceSvgName));
      expect(File(icoPath).readAsBytesSync(), [1, 2, 3]);
      expect(File('$iconDir/provenance.json').readAsBytesSync(), recordBefore);
      expect(File('$icoPath.tmp').existsSync(), isFalse);
      expect(File('$iconDir/provenance.json.tmp').existsSync(), isFalse);
      expect(rasterizer.calls, isEmpty);
    });

    test(
      'a rejected small source names it and compiles before rendering',
      () async {
        writeSource(validSvg, small: rejectedSvg);

        final result = await run();

        expect(result.ok, isFalse);
        expect(result.messages.join('\n'), contains(smallSvgName));
        expect(rasterizer.calls, isEmpty);
        expect(File(icoPath).existsSync(), isFalse);
      },
    );

    test('builds a valid ico, then rewrites the record hashes', () async {
      writeSource(validSvg, small: validSvg);

      final result = await run();

      expect(result.ok, isTrue, reason: result.messages.join('\n'));
      final ico = File(icoPath).readAsBytesSync();
      expect(checkIco(ico), isEmpty);
      final record = parseSourceRecord(
        File('$iconDir/provenance.json').readAsStringSync(),
      );
      expect(record, isA<SourceParsed>());
      final hashes = (record as SourceParsed).record.sha256;
      expect(hashes[icoName], sha256.convert(ico).toString());
      expect(hashes.containsKey(smallSvgName), isTrue);
      expect(File('$icoPath.tmp').existsSync(), isFalse);
      Set<int> sizesOf(String file) => {
        for (final (name, size) in rasterizer.calls)
          if (name == file) size,
      };
      expect(sizesOf(smallSvgName), {16, 20, 24});
      expect(sizesOf(sourceSvgName), {32, 40, 48, 64, 96, 128, 256});
    });

    test(
      'without a small source every size comes from the main source',
      () async {
        writeSource(validSvg);

        final result = await run();

        expect(result.ok, isTrue, reason: result.messages.join('\n'));
        expect(rasterizer.calls.map((c) => c.$1).toSet(), {sourceSvgName});
        expect(rasterizer.calls.map((c) => c.$2), icoRequiredSizes);
      },
    );

    test(
      'a picked candidate missing from the candidates record fails',
      () async {
        writeSource(
          validSvg,
          record: sourceRecordText(picked: 'vector/zz.svg'),
        );

        final result = await run();

        expect(result.ok, isFalse);
        expect(result.messages.join('\n'), contains('vector/zz.svg'));
        expect(File(icoPath).existsSync(), isFalse);
      },
    );

    test('a source over 64 KiB fails naming it before rendering', () async {
      writeSource('$validSvg<!-- ${'x' * maxSourceBytes} -->');

      final result = await run();

      expect(result.ok, isFalse);
      expect(result.messages.join('\n'), contains(sourceSvgName));
      expect(rasterizer.calls, isEmpty);
    });

    test('a record write that fails after the ico was written exits non-zero '
        'naming the rebuild command, and the hash check catches it', () async {
      writeSource(validSvg);
      // A directory where the record's temp file goes makes that write fail.
      Directory('$iconDir/provenance.json.tmp').createSync();

      final result = await run();

      expect(result.ok, isFalse);
      expect(result.exitCode, 1);
      expect(result.messages.join('\n'), contains(iconBuildCommand));
      final record = parseSourceRecord(
        File('$iconDir/provenance.json').readAsStringSync(),
      );
      expect(
        checkHashBinding(
          (record as SourceParsed).record,
          svg: File('$iconDir/$sourceSvgName').readAsBytesSync(),
          ico: File(icoPath).readAsBytesSync(),
        ).join('\n'),
        allOf(contains(icoName), contains(iconBuildCommand)),
      );
    });

    test('a missing source record fails naming it', () async {
      File('$iconDir/$sourceSvgName').writeAsStringSync(validSvg);

      final result = await run();

      expect(result.ok, isFalse);
      expect(result.messages.join('\n'), contains('provenance.json'));
    });
  });
}
