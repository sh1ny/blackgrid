@Tags(['qualification'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:blackgrid/data/raid_panel_ocr.dart';
import 'package:blackgrid/domain/raid_exfil_matcher.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';

void main() {
  // Directory holding the built blackgrid_panel_ocr.dll and its .sha256,
  // e.g. build/windows/x64/runner/Release.
  final runtime = Platform.environment['BLACKGRID_PANEL_OCR_RUNTIME'];
  final suppliedImage = Platform.environment['BLACKGRID_PANEL_IMAGE'];
  RaidPanelOcr create() =>
      RaidPanelOcr(nativeLibraryPath: '$runtime/blackgrid_panel_ocr.dll');
  test('actual native decode malformed and oversized dimensions fail without empty authority', () async {
    final ocr = create();
    try {
      expect(
        (await ocr.recognize(Uint8List.fromList([1, 2, 3]))).state,
        RaidPanelState.error,
      );
      final oversized = image.encodePng(image.Image(width: 8193, height: 1));
      expect(
        (await ocr.recognize(Uint8List.fromList(oversized))).state,
        RaidPanelState.error,
      );
    } finally {
      await ocr.close();
    }
  }, skip: runtime == null ? 'Requires the built app-local OCR DLL.' : false);
  test(
    'a DLL that does not match its build hash is refused as unavailable',
    () async {
      final temporary = await Directory.systemTemp.createTemp('m5-ocr-hash-');
      try {
        final dll = '${temporary.path}/blackgrid_panel_ocr.dll';
        await File('$runtime/blackgrid_panel_ocr.dll').copy(dll);
        await File('$dll.sha256').writeAsString('0' * 64);
        final ocr = RaidPanelOcr(nativeLibraryPath: dll);
        try {
          final result = await ocr.recognize(Uint8List.fromList([1, 2, 3]));
          expect(result.state, RaidPanelState.unavailable);
          expect(result.message, contains('hash'));
        } finally {
          await ocr.close();
        }
      } finally {
        await temporary.delete(recursive: true);
      }
    },
    skip: runtime == null ? 'Requires the built app-local OCR DLL.' : false,
  );
  test(
    'repeated actual native blank-image jobs never create empty authority',
    () async {
      final ocr = create();
      final bytes = Uint8List.fromList(
        image.encodePng(image.Image(width: 64, height: 64)),
      );
      try {
        for (var i = 0; i < 12; i++) {
          final result = await ocr.recognize(bytes);
          expect(result.state, isNot(RaidPanelState.empty));
          expect(result.state, isNot(RaidPanelState.recognized));
          expect(
            result.state,
            isNot(RaidPanelState.unavailable),
            reason: result.message,
          );
          expect(result.extractNames, isEmpty);
          expect(result.transitNames, isEmpty);
        }
      } finally {
        await ocr.close();
      }
      expect((await ocr.recognize(bytes)).state, RaidPanelState.unavailable);
    },
    skip: runtime == null ? 'Requires the built app-local OCR DLL.' : false,
  );
  test(
    'only explicitly supplied human-labeled Shoreline image is read offline',
    () async {
      final ocr = create();
      try {
        final bytes = await File(suppliedImage!).readAsBytes();
        expect(
          sha256.convert(bytes).toString(),
          '67f55fcb86eed28ef18b52fc9dd4874325fbc9f9b9b4752a6046ba19964977d6',
          reason: 'This case is bound only to the independently labeled supplied original.',
        );
        final result = await ocr.recognize(bytes);
        expect(result.state, RaidPanelState.recognized, reason: result.message);
        // User-confirmed visible names; current-map matching is the authority.
        const extracts = [
          'Road to North V-Ex',
          'Road to Customs',
          'Railway Bridge',
          'Path to Lighthouse',
          "Smugglers' Path (Co-op)",
          'Pier Boat',
          "Climber's Trail",
        ];
        final matched = RaidExfilMatcher([
          for (final name in extracts)
            RaidExitIdentity(id: name, name: name, transit: false),
          RaidExitIdentity(
            id: 'Transit to Lighthouse',
            name: 'Transit to Lighthouse',
            transit: true,
          ),
        ]).match(result);
        expect(matched.ids, {...extracts, 'Transit to Lighthouse'});
        expect(result.panel, isNotNull);
      } finally {
        await ocr.close();
      }
    },
    skip: runtime == null || suppliedImage == null
        ? 'Requires the explicitly authorized Shoreline image and built OCR DLL.'
        : false,
  );
}
