import 'dart:typed_data';

import 'package:blackgrid/data/vision/inspection_fir.dart';
import 'package:blackgrid/data/vision/inspection_geometry.dart';
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:flutter_test/flutter_test.dart';

// At scale one the whole required rectangle is exactly this small image.
const int markerX = 8;
const int markerY = -275;
const int width = 88;
const int height = 55;

final class Corner {
  Corner()
    : frame = VisionImage(
        Uint8List(width * height * 4),
        width: width,
        height: height,
        stride: width * 4,
        channels: 4,
      ),
      gray = VisionImage(
        Uint8List(width * height),
        width: width,
        height: height,
        stride: width,
        channels: 1,
      ) {
    for (final x in [60, 65, 70, 75]) {
      for (final y in [323, 324, 325]) {
        pixel(x, y, 26, 26, 26);
      }
    }
    // Nonconstant search: the scripted NCC callback must be exercised.
    gray.bytes[0] = 1;
  }

  final VisionImage frame;
  final VisionImage gray;

  void pixel(int x, int y, int b, int g, int r, [int alpha = 0]) {
    final i = ((markerY + y) * width + markerX + x) * 4;
    frame.bytes.setRange(i, i + 4, [b, g, r, alpha]);
  }

  InspectionFirReading read({
    double score = 0.5,
    int x = 0,
    int y = 0,
    double scale = 1,
    VisionImage? image,
    VisionImage? grayImage,
    void Function(TitleRegion, int)? onMatch,
  }) => readInspectionFir(
    frame: image ?? frame,
    gray: grayImage ?? gray,
    markerX: markerX,
    markerY: markerY,
    scale: scale,
    match: (region, side) {
      onMatch?.call(region, side);
      return TemplateMatch(score, x, y);
    },
  );
}

void main() {
  test('check without a medal yields Yes', () {
    final corner = Corner();
    final reading = corner.read(
      score: 0.82,
      x: 10,
      y: 3,
      onMatch: (region, side) {
        expect(region, const TitleRegion(x: 0, y: 0, width: 88, height: 55));
        expect(side, 21);
      },
    );
    expect(reading.value, FirState.yes);
    expect(reading.reason, InspectionFirReason.iconFound);
    expect(reading.score, 0.82);
  });

  test('check beside a medal yields Yes', () {
    final corner = Corner()
      ..pixel(-4, 280, 20, 120, 180)
      ..pixel(-3, 280, 20, 120, 180);
    final reading = corner.read(score: 0.9, x: 42, y: 4);
    expect(reading.value, FirState.yes);
    expect(reading.reason, InspectionFirReason.iconFound);
  });

  test('readable empty and medal-only corners yield No', () {
    final empty = Corner().read(score: 0.6);
    expect(empty.value, FirState.no);
    expect(empty.reason, InspectionFirReason.iconAbsent);
    final medal = Corner()
      ..pixel(-4, 280, 20, 120, 180)
      ..pixel(-3, 280, 20, 120, 180)
      ..pixel(5, 280, 20, 120, 180);
    expect(medal.read().value, FirState.no);
  });

  test('any missing required corner edge yields Unknown', () {
    final corner = Corner();
    for (final (x, y, w, h) in [
      (markerX - 1, markerY, width, height),
      (markerX + 1, markerY, width, height),
      (markerX, markerY - 1, width, height),
      (markerX, markerY + 1, width, height),
    ]) {
      final reading = readInspectionFir(
        frame: corner.frame,
        gray: corner.gray,
        markerX: x,
        markerY: y,
        scale: 1,
        match: (_, _) => throw StateError('clipped corner was matched'),
      );
      expect(reading.value, FirState.unknown, reason: '$x $y $w $h');
      expect(reading.reason, InspectionFirReason.cornerCutOff);
    }
  });

  test('broken boundary and score gap yield Unknown', () {
    for (final (x, y, value) in [
      (60, 318, 13),
      (75, 320, 13),
      (65, 323, 17),
      (70, 325, 46),
    ]) {
      final corner = Corner()..pixel(x, y, value, value, value, 255);
      expect(
        corner.read(score: 0.5).reason,
        InspectionFirReason.cornerUnreadable,
        reason: '$x $y $value',
      );
    }
    for (final score in [
      0.60001,
      0.81999,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final reading = Corner().read(score: score);
      expect(reading.value, FirState.unknown, reason: '$score');
      expect(reading.reason, InspectionFirReason.cornerUnreadable);
      if (!score.isFinite) expect(reading.score, isNull);
    }
    for (final value in [12, 18, 45]) {
      final corner = Corner();
      if (value == 12) {
        corner.pixel(60, 318, value, value, value, 255);
      } else {
        corner.pixel(60, 323, value, value, value, 255);
      }
      expect(corner.read().value, FirState.no, reason: '$value');
    }
  });

  test('partial check below positive gate never yields No', () {
    final corner = Corner()..pixel(40, 290, 20, 120, 180);
    for (final score in [0.0, 0.5034, 0.6, 0.7]) {
      expect(
        corner.read(score: score).reason,
        InspectionFirReason.cornerUnreadable,
        reason: '$score',
      );
    }
    expect(corner.read(score: 0.82).value, FirState.yes);
  });

  test('medal witness and residual slot boundaries are exact', () {
    final one = Corner()
      ..pixel(-4, 280, 20, 120, 180)
      ..pixel(5, 280, 20, 120, 180);
    expect(one.read().value, FirState.unknown);
    one.pixel(-3, 280, 20, 120, 180);
    expect(one.read().value, FirState.no);
    one.pixel(32, 280, 20, 120, 180);
    expect(one.read().value, FirState.unknown);
    final outside = Corner()..pixel(75, 280, 20, 120, 180);
    expect(outside.read().value, FirState.no);
  });

  test('scaled witness uses floor of two times scale squared', () {
    const scale = 2.0;
    const w = 176;
    const h = 110;
    const mx = 16;
    const my = -550;
    final frame = VisionImage(
      Uint8List(w * h * 4),
      width: w,
      height: h,
      stride: w * 4,
      channels: 4,
    );
    final gray = VisionImage(
      Uint8List(w * h)..[0] = 1,
      width: w,
      height: h,
      stride: w,
      channels: 1,
    );
    void pixel(int x, int y, int b, int g, int r) {
      final i = ((my + y) * w + mx + x) * 4;
      frame.bytes.setRange(i, i + 4, [b, g, r, 255]);
    }

    for (final x in [60, 65, 70, 75]) {
      for (final y in [323, 324, 325]) {
        pixel(x * 2, y * 2, 26, 26, 26);
      }
    }
    InspectionFirReading read() => readInspectionFir(
      frame: frame,
      gray: gray,
      markerX: mx,
      markerY: my,
      scale: scale,
      match: (_, side) {
        expect(side, 42);
        return const TemplateMatch(0.5, 0, 0);
      },
    );
    // At 2x, seven witness pixels are insufficient; the eighth admits the
    // medal-only gold in the excluded left part of the slot.
    pixel(10, 560, 20, 120, 180);
    for (var x = -8; x < -1; x++) {
      pixel(x, 560, 20, 120, 180);
    }
    expect(read().value, FirState.unknown);
    pixel(-1, 560, 20, 120, 180);
    expect(read().value, FirState.no);
    pixel(64, 560, 20, 120, 180);
    expect(read().value, FirState.unknown);
  });

  test('gold channel comparisons are strict and ignore X', () {
    for (final (b, g, r, gold) in [
      (20, 120, 180, true),
      (20, 120, 110, false),
      (20, 90, 180, false),
      (80, 100, 180, false),
      (100, 130, 140, false),
    ]) {
      final corner = Corner()..pixel(40, 290, b, g, r, 255);
      expect(
        corner.read().value,
        gold ? FirState.unknown : FirState.no,
        reason: '$b $g $r',
      );
    }
  });

  test('invalid scale and candidate are unreadable', () {
    for (final scale in [0.0, -1.0, double.nan, double.infinity, 0.01]) {
      expect(
        Corner().read(scale: scale).reason,
        InspectionFirReason.cornerUnreadable,
        reason: '$scale',
      );
    }
    for (final (x, y) in [(-1, 0), (0, -1), (68, 0), (0, 35)]) {
      expect(
        Corner().read(score: 0.9, x: x, y: y).reason,
        InspectionFirReason.cornerUnreadable,
        reason: '$x $y',
      );
    }
  });

  test(
    'uniformly dark search is negative only after guards and residual gold',
    () {
      final corner = Corner();
      corner.gray.bytes.fillRange(0, corner.gray.bytes.length, 0);
      expect(
        corner.read(onMatch: (_, _) => fail('constant image matched')).value,
        FirState.no,
      );
      corner.pixel(40, 290, 20, 120, 180);
      expect(
        corner.read(onMatch: (_, _) => fail('constant image matched')).reason,
        InspectionFirReason.cornerUnreadable,
      );
      corner.pixel(60, 318, 13, 13, 13);
      expect(
        corner.read(onMatch: (_, _) => fail('constant image matched')).reason,
        InspectionFirReason.cornerUnreadable,
      );
    },
  );

  test('scaled coordinates floor negative offsets and fit independently', () {
    expect(
      planInspectionFirRegion(markerX: 10, markerY: 20, scale: 1.25),
      const TitleRegion(x: 0, y: 363, width: 110, height: 69),
    );
    expect(
      planInspectionFirRegion(markerX: 10, markerY: 20, scale: 1.1),
      const TitleRegion(x: 1, y: 322, width: 97, height: 61),
    );
  });
}
