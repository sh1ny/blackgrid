import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart' as vg;

import '../../../tool/markers/icon_set.dart' show compileIconSvg;

const _extent = 64;

void main() {
  testWidgets('app icon blur paints outside the unfiltered shape', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final plain = await _rasterize(blurred: false);
      final blurred = await _rasterize(blurred: true);

      // Two pixels beyond the circle are outside its antialiasing edge.
      const fringe = (32 * _extent + 46) * 4 + 3;
      expect(plain.getUint8(fringe), 0);
      expect(blurred.getUint8(fringe), greaterThan(0));
    });
  });
}

Future<ByteData> _rasterize({required bool blurred}) async {
  final svg =
      '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_extent $_extent">
  ${blurred ? '<defs><filter id="blur"><feGaussianBlur stdDeviation="4"/></filter></defs>' : ''}
  <circle cx="32" cy="32" r="12" fill="#ffffff" ${blurred ? 'filter="url(#blur)"' : ''}/>
</svg>
''';
  final compiled = compileIconSvg(svg, 'app-icon-blur.svg');
  final info = await vg.vg.loadPicture(
    _CompiledBytes(ByteData.sublistView(compiled)),
    null,
    clipViewbox: false,
  );
  try {
    final image = await info.picture.toImage(_extent, _extent);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    } finally {
      image.dispose();
    }
  } finally {
    info.picture.dispose();
  }
}

class _CompiledBytes extends vg.BytesLoader {
  const _CompiledBytes(this.bytes);

  final ByteData bytes;

  @override
  Future<ByteData> loadBytes(BuildContext? context) async => bytes;
}
