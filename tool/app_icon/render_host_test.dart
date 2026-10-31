// The Flutter host for the app icon tools (design D1). It is outside `test/`
// so `mise run test` never runs it; run it through the mise tasks:
//
//   mise run icon:build   rebuilds app_icon.ico, app_icon.vec and their
//                         provenance hashes
//   mise run icon:sheet   writes build/app-icon-preview/index.html
//
// Both run `flutter test tool/app_icon/render_host_test.dart` with
// `--dart-define=APP_ICON_MODE=build|sheet` from the repository root. With no
// mode, or an unknown one, the test fails and writes nothing.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart' as vg;

import 'build.dart';
import 'sheet.dart';

const String _mode = String.fromEnvironment('APP_ICON_MODE');

void main() {
  testWidgets('app icon tool', (tester) async {
    final run = switch (_mode) {
      'build' => () => buildIcon(
        iconDir: defaultIconSourceDir,
        icoPath: defaultIcoPath,
        vecPath: defaultVecPath,
        candidatesDir: defaultCandidatesDir,
        rasterize: _rasterize,
      ),
      'sheet' => () => writeSheet(
        candidatesDir: defaultCandidatesDir,
        outputPath: defaultSheetPath,
        rasterize: _rasterize,
      ),
      _ => null,
    };
    if (run == null) {
      fail(
        'APP_ICON_MODE is "$_mode"; nothing was written. Run '
        '`mise run icon:build` or `mise run icon:sheet` instead of running '
        'this file directly.',
      );
    }

    final result = await tester.runAsync(run);
    result!.messages.forEach(debugPrint);
    if (!result.ok) {
      fail('app icon $_mode failed:\n${result.messages.join('\n')}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Draws [compiled] scaled to [size] and returns straight-alpha RGBA.
///
/// Reads `rawStraightRgba`, not the premultiplied `rawRgba`, which would
/// darken every anti-aliased edge (design D1).
Future<Uint8List> _rasterize(Uint8List compiled, int size, String name) async {
  final info = await vg.vg.loadPicture(
    _CompiledBytes(name, ByteData.sublistView(compiled)),
    null,
    clipViewbox: false,
    onError: (error, stack) =>
        Error.throwWithStackTrace(error, stack ?? StackTrace.current),
  );
  try {
    final source = info.size;
    if (source.isEmpty || source.width != source.height) {
      throw FormatException('$name must have a square viewBox, got $source');
    }
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..scale(size / source.width, size / source.height)
      ..drawPicture(info.picture);
    final scaled = recorder.endRecording();
    try {
      final image = await scaled.toImage(size, size);
      try {
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (data == null) throw StateError('$name: no pixels at $size px');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      scaled.dispose();
    }
  } finally {
    info.picture.dispose();
  }
}

class _CompiledBytes extends vg.BytesLoader {
  const _CompiledBytes(this.name, this.bytes);
  final String name;
  final ByteData bytes;

  @override
  Future<ByteData> loadBytes(BuildContext? context) async => bytes;

  @override
  String toString() => 'AppIconBytes($name)';
}
