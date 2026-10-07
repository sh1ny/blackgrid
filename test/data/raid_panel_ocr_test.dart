import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/data/raid_panel_ocr.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';

void main() {
  test(
    'empty and over-limit inputs fail honestly before native work',
    () async {
      final ocr = RaidPanelOcr();
      try {
        expect((await ocr.recognize(Uint8List(0))).state, RaidPanelState.error);
        expect(
          (await ocr.recognize(Uint8List(64 * 1024 * 1024 + 1))).state,
          RaidPanelState.error,
        );
      } finally {
        await ocr.close();
      }
    },
  );
  test(
    'missing app-local engine is unavailable, never missing/empty evidence',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'map-ocr-missing-',
      );
      final ocr = RaidPanelOcr(
        nativeLibraryPath: '${temporary.path}/missing.dll',
      );
      try {
        final evidence = await ocr.recognize(Uint8List.fromList([1, 2, 3]));
        expect(evidence.state, RaidPanelState.unavailable);
        expect(evidence.extractNames, isEmpty);
        expect(evidence.transitNames, isEmpty);
        expect(evidence.message, isNotEmpty);
      } finally {
        await ocr.close();
        await temporary.delete();
      }
    },
  );
  test('close is idempotent and rejects future ingress', () async {
    final ocr = RaidPanelOcr();
    await ocr.close();
    await ocr.close();
    expect(
      (await ocr.recognize(Uint8List.fromList([1]))).state,
      RaidPanelState.unavailable,
    );
  });
  test(
    'shutdown during initialization invalidates a pending publication',
    () async {
      final temporary = await Directory.systemTemp.createTemp('map-ocr-close-');
      final ocr = RaidPanelOcr(
        nativeLibraryPath: '${temporary.path}/missing.dll',
      );
      final read = ocr.recognize(Uint8List.fromList([1, 2, 3]));
      await ocr.close();
      final evidence = await read;
      expect(evidence.state, RaidPanelState.unavailable);
      expect(evidence.extractNames, isEmpty);
      await temporary.delete();
    },
  );
  test('bounded ingress does not accumulate saved images', () async {
    final temporary = await Directory.systemTemp.createTemp('map-ocr-busy-');
    final ocr = RaidPanelOcr(
      nativeLibraryPath: '${temporary.path}/missing.dll',
    );
    try {
      final first = ocr.recognize(Uint8List.fromList([1, 2, 3]));
      final second = await ocr.recognize(Uint8List.fromList([4, 5, 6]));
      expect(second.state, RaidPanelState.unavailable);
      expect(second.message, contains('busy'));
      await first;
    } finally {
      await ocr.close();
      await temporary.delete();
    }
  });
}
