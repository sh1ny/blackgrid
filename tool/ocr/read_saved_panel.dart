import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/raid_panel_ocr.dart';

/// Reads one saved screenshot with the built app-local OCR DLL and prints the
/// panel names before current-map matching.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/ocr/read_saved_panel.dart IMAGE [OCR_DLL]\n'
      'OCR_DLL defaults to build/windows/x64/runner/Release/blackgrid_panel_ocr.dll',
    );
    exitCode = 64;
    return;
  }
  final dll = File(
    arguments.length == 2
        ? arguments[1]
        : 'build/windows/x64/runner/Release/blackgrid_panel_ocr.dll',
  ).absolute.path;
  final ocr = RaidPanelOcr(nativeLibraryPath: dll);
  final watch = Stopwatch()..start();
  try {
    final image = File(arguments[0]);
    final size = await image.length();
    if (size <= 0 || size > 64 * 1024 * 1024) {
      throw StateError('Saved-image size is invalid.');
    }
    final evidence = await ocr.recognize(await image.readAsBytes());
    watch.stop();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'state': evidence.state.name,
        'extract_names': evidence.extractNames,
        'transit_names': evidence.transitNames,
        'raw_text': evidence.rawText,
        'message': evidence.message,
        'panel': evidence.panel == null
            ? null
            : [
                evidence.panel!.left,
                evidence.panel!.top,
                evidence.panel!.right,
                evidence.panel!.bottom,
              ],
        'elapsed_ms': watch.elapsedMicroseconds / 1000,
      }),
    );
    if (evidence.state.name != 'recognized') exitCode = 2;
  } finally {
    await ocr.close();
  }
}
