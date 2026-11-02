import 'dart:typed_data';

import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:flutter_test/flutter_test.dart';
// The codec is the runtime's own transitive dependency; a direct pin would
// reintroduce the toolchain pin this change removes.
// ignore: depend_on_referenced_packages
import 'package:vector_graphics_codec/vector_graphics_codec.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart'
    as compiler;

import '../../tool/maps/pack.dart' show vectorPayloadFormat;

const _svg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8">'
    '<rect width="8" height="8" fill="#336699"/></svg>';

void main() {
  test('resolved codec writes and decodes the supported format', () {
    final bytes = compiler.encodeSvg(
      xml: _svg,
      debugName: 'tiny.svg',
      warningsAsErrors: true,
      enableMaskingOptimizer: false,
      enableClippingOptimizer: false,
      enableOverdrawOptimizer: false,
    );
    final format = vectorPayloadFormat(bytes, 'tiny.vec');
    expect(
      format,
      preparedVectorCodecFormat,
      reason: unsupportedVectorFormatMessage(format, preparedVectorCodecFormat),
    );
    expect(
      () => VectorGraphicsCodec().decode(ByteData.sublistView(bytes), null),
      returnsNormally,
    );
  });

  test('format mismatch message names both formats and maps:rebuild', () {
    final message = unsupportedVectorFormatMessage(2, 1);
    expect(message, contains('vector format 2 is not supported'));
    expect(message, contains('decodes format 1'));
    expect(message, contains('mise run maps:rebuild'));
  });
}
