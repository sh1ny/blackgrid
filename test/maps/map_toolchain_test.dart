import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../tool/maps/pack.dart';

String _lock(Iterable<String> skip) {
  const versions = {
    'xml': '6.6.1',
    'image': '4.12.0',
    'vector_graphics_compiler': '1.3.4',
    'vector_graphics': '1.2.5',
    'vector_graphics_codec': '1.1.13',
    'meta': '1.0.0',
  };
  final buffer = StringBuffer('packages:\n');
  for (final entry in versions.entries) {
    if (skip.contains(entry.key)) continue;
    buffer
      ..writeln('  ${entry.key}:')
      ..writeln('    dependency: transitive')
      ..writeln('    description:')
      ..writeln('      name: ${entry.key}')
      ..writeln('      url: "https://pub.dev"')
      ..writeln('    source: hosted')
      ..writeln('    version: "${entry.value}"');
  }
  buffer.writeln('sdks:\n  dart: ">=3.0.0 <4.0.0"');
  return buffer.toString();
}

void main() {
  group('toolchainFromLock', () {
    test('complete lock returns the five resolved versions', () {
      expect(toolchainFromLock(_lock(const [])), {
        'xml': '6.6.1',
        'image': '4.12.0',
        'vector_graphics_compiler': '1.3.4',
        'vector_graphics': '1.2.5',
        'vector_graphics_codec': '1.1.13',
      });
    });

    test('lock without vector_graphics_codec names the package', () {
      expect(
        () => toolchainFromLock(_lock(const ['vector_graphics_codec'])),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('vector_graphics_codec'),
          ),
        ),
      );
    });
  });

  group('vectorPayloadFormat', () {
    test('payload header returns format byte after the magic number', () {
      expect(
        vectorPayloadFormat(
          Uint8List.fromList([0x62, 0x2d, 0x88, 0x00, 7, 99]),
          'a.vec',
        ),
        7,
      );
    });

    test('wrong magic or under 5 bytes throws naming the path', () {
      for (final bytes in [
        [0x62, 0x2d, 0x88, 0x01, 1],
        [0x62, 0x2d, 0x88, 0x00],
        <int>[],
      ]) {
        expect(
          () => vectorPayloadFormat(Uint8List.fromList(bytes), 'x/b.vec'),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('x/b.vec'),
            ),
          ),
          reason: '$bytes',
        );
      }
    });
  });

  group('vector compile determinism', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('blackgrid-toolchain-');
      await File('${root.path}/in.compiler.svg').writeAsString('<svg/>');
    });
    tearDown(() => root.delete(recursive: true));

    test('stable encoder output is written', () async {
      var calls = 0;
      await compileVector(
        root,
        'in.compiler.svg',
        'out.vec',
        encode: (xml, name) {
          calls++;
          return Uint8List.fromList(utf8.encode('payload:$xml'));
        },
      );
      expect(calls, 2);
      expect(
        await File('${root.path}/out.vec').readAsString(),
        'payload:<svg/>',
      );
    });

    test('differing second encoding fails naming the vec path', () async {
      var calls = 0;
      await expectLater(
        compileVector(
          root,
          'in.compiler.svg',
          'artwork/customs/Ground_Level.vec',
          encode: (xml, name) => Uint8List.fromList([++calls]),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('artwork/customs/Ground_Level.vec'),
          ),
        ),
      );
      expect(
        File('${root.path}/artwork/customs/Ground_Level.vec').existsSync(),
        isFalse,
      );
    });
  });
}
