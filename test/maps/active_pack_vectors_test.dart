import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:flutter_test/flutter_test.dart';
// The codec is the runtime's own transitive dependency; a direct pin would
// reintroduce the toolchain pin this change removes.
// ignore: depend_on_referenced_packages
import 'package:vector_graphics_codec/vector_graphics_codec.dart';

import '../../tool/maps/pack.dart' show encodeMapVector, vectorPayloadFormat;

/// Proves the committed active generation against the installed toolchain:
/// every vector recompiles to its committed bytes, decodes with the shipped
/// codec, and carries the recorded format.
void main() {
  final active = jsonDecode(
    File('assets/maps/active.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final generation = 'assets/maps/versions/${active['version']}';
  final manifest = jsonDecode(
    File('$generation/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final components = [
    for (final map in manifest['maps'] as List)
      for (final floor in (map as Map)['floors'] as List)
        for (final component
            in ((floor as Map)['artwork'] as Map?)?['components'] as List? ??
                const [])
          component as Map<String, dynamic>,
  ];

  test('the active generation has compiled vectors and a format record', () {
    expect(manifest['vectorsCompiled'], isTrue);
    expect(manifest['vectorCodecFormat'], preparedVectorCodecFormat);
    expect(components, isNotEmpty);
  });

  test('every committed vector reproduces, decodes and matches the format', () {
    for (final component in components) {
      final path = component['path'] as String;
      final reason = '$path: run mise run maps:rebuild';
      final committed = File('$generation/$path').readAsBytesSync();
      final source = File('$generation/${component['compilerSvg']}')
          .readAsStringSync();
      expect(
        encodeMapVector(source, component['compilerSvg'] as String),
        committed,
        reason: reason,
      );
      expect(
        vectorPayloadFormat(committed, path),
        manifest['vectorCodecFormat'],
        reason: reason,
      );
      expect(
        () =>
            VectorGraphicsCodec().decode(ByteData.sublistView(committed), null),
        returnsNormally,
        reason: reason,
      );
    }
  });
}
