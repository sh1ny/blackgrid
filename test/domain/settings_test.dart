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
}
