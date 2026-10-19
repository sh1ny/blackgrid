import 'package:blackgrid/domain/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings.liveScan', () {
    test('defaults to off', () {
      expect(AppSettings().liveScan, isFalse);
    });

    test('round-trips through toJson and fromJson', () {
      final on = AppSettings().copyWith(liveScan: true);
      expect(on.liveScan, isTrue);
      expect(AppSettings.fromJson(on.toJson()).liveScan, isTrue);
      expect(AppSettings.fromJson(AppSettings().toJson()).liveScan, isFalse);
    });

    test('payload without liveScan reads as off', () {
      final json = AppSettings().copyWith(liveScan: true).toJson()
        ..remove('liveScan');
      expect(AppSettings.fromJson(json).liveScan, isFalse);
    });
  });

  group('AppSettings.scanHotkey', () {
    test('scanHotkey: no saved value', () {
      final saved = AppSettings(
        selectedMap: 'customs',
        followGameLogs: false,
        liveScan: true,
      );
      final json = saved.toJson()..remove('scanHotkey');
      final loaded = AppSettings.fromJson(json);
      expect(loaded.scanHotkey, ScanHotkey.f9);
      expect(loaded.selectedMap, 'customs');
      expect(loaded.followGameLogs, isFalse);
      expect(loaded.liveScan, isTrue);
    });

    test('scanHotkey: saved off', () {
      final saved = AppSettings().copyWith(scanHotkey: ScanHotkey.off);
      expect(saved.toJson()['scanHotkey'], 'off');
      expect(AppSettings.fromJson(saved.toJson()).scanHotkey, ScanHotkey.off);
    });

    test('scanHotkey: malformed value', () {
      for (final bad in <Object?>['Ctrl+Q', 9, 'F25', null]) {
        final json = AppSettings(
          selectedMap: 'customs',
          liveScan: true,
        ).toJson()..['scanHotkey'] = bad;
        final loaded = AppSettings.fromJson(json);
        expect(loaded.scanHotkey, ScanHotkey.f9, reason: '$bad');
        expect(loaded.selectedMap, 'customs');
        expect(loaded.liveScan, isTrue);
      }
    });

    test('every key round-trips and maps to its virtual-key code', () {
      expect(ScanHotkey.values, hasLength(25));
      expect(ScanHotkey.off.vk, 0);
      expect(ScanHotkey.off.label, 'Off');
      expect(ScanHotkey.f1.vk, 0x70);
      expect(ScanHotkey.f9.vk, 0x78);
      expect(ScanHotkey.f24.vk, 0x87);
      expect(ScanHotkey.f24.label, 'F24');
      for (final key in ScanHotkey.values) {
        final loaded = AppSettings.fromJson(
          AppSettings().copyWith(scanHotkey: key).toJson(),
        );
        expect(loaded.scanHotkey, key);
      }
    });
  });
}
