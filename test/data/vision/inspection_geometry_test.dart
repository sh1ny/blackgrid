import 'package:blackgrid/data/vision/inspection_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

PeakCandidate p(int x, int y, double score) =>
    PeakCandidate(x: x, y: y, score: score);

List<(int, int)> xy(List<PeakCandidate> peaks) => [
  for (final peak in peaks) (peak.x, peak.y),
];

void main() {
  group('processing scale', () {
    test('3840x2160 gives scale 2 and a 32x32 template', () {
      final scale = processingScale(3840, 2160);
      expect(scale, 2.0);
      expect(scaledTemplateSize(scale), 32);
    });

    test('3440x1440 scale follows height', () {
      expect(processingScale(3440, 1440), closeTo(1440 / 1080, 1e-12));
    });

    test('narrow clients follow width', () {
      expect(processingScale(960, 1080), 0.5);
    });

    test('scaled template sizes truncate per side', () {
      expect(scaledTemplateSize(processingScale(1920, 1080)), 16);
      expect(scaledTemplateSize(processingScale(2560, 1440)), 21);
      expect(scaledTemplateSize(1.5), 24);
    });
  });

  group('title region', () {
    TitleRegionPlan plan({
      int markerX = 100,
      int markerY = 50,
      int scaledW = 16,
      int scaledH = 16,
      double scale = 1,
      int frameW = 1920,
      int frameH = 1080,
    }) => planTitleRegion(
      markerX: markerX,
      markerY: markerY,
      scaledWidth: scaledW,
      scaledHeight: scaledH,
      scale: scale,
      frameWidth: frameW,
      frameHeight: frameH,
    );

    test('close button at x 400 gives title 119,50 217x17', () {
      final p = plan();
      expect(p.needsProbe, isTrue);
      expect(p.probeStartX, 119);
      final region = p.narrow(400);
      expect(
        (region.x, region.y, region.width, region.height),
        (119, 50, 217, 17),
      );
    });

    test('without a close button the region keeps 500 x scale width', () {
      final region = plan().narrow(null);
      expect(
        (region.x, region.y, region.width, region.height),
        (119, 50, 500, 17),
      );
      expect(plan().unprobed, region);
    });

    test('a close button past the region end does not widen it', () {
      final region = plan().narrow(900);
      expect(region.width, 500);
    });

    test('probe row is markerY + scaledH ~/ 2', () {
      expect(plan(markerY: 50, scaledH: 16).probeRow, 58);
      expect(plan(markerY: 50, scaledH: 21).probeRow, 60);
    });

    test('region scales with the processing scale', () {
      final region = plan(
        scale: 2,
        scaledW: 32,
        scaledH: 32,
        frameW: 3840,
        frameH: 2160,
      ).narrow(null);
      expect((region.x, region.width, region.height), (138, 1000, 34));
    });

    test('title region is clamped to the frame without padding', () {
      final region = plan(markerX: 1800, markerY: 1070).narrow(null);
      expect(region.x, 1819);
      expect(region.width, 101);
      expect(region.height, 10);
    });

    test('start x at or beyond the right edge is empty and needs no probe', () {
      for (final markerX in [1901, 1920, 2500]) {
        final p = plan(markerX: markerX);
        expect(p.unprobed.isEmpty, isTrue, reason: 'markerX $markerX');
        expect(p.needsProbe, isFalse);
        expect(p.narrow(null).isEmpty, isTrue);
      }
    });

    test('marker below the frame gives an empty region', () {
      expect(plan(markerY: 1080).needsProbe, isFalse);
    });

    test('close button narrowing to zero or less is empty', () {
      // end = closeX - 64 = 119 -> width 0.
      expect(plan().narrow(183).isEmpty, isTrue);
      expect(plan().narrow(150).isEmpty, isTrue);
      expect(plan().narrow(184).width, 1);
    });

    test('close button bounds are in BGRX channel order', () {
      expect(closeButtonBgrxLo, [10, 10, 50, 0]);
      expect(closeButtonBgrxHi, [15, 15, 80, 255]);
    });
  });

  group('peak suppression', () {
    test('suppression keeps only the higher of two overlapping peaks', () {
      final kept = suppressPeaks([p(10, 10, 0.9), p(15, 12, 0.95)], 16, 16);
      expect(xy(kept), [(15, 12)]);
    });

    test('peaks exactly one template apart are both kept', () {
      expect(xy(suppressPeaks([p(0, 0, 0.9), p(16, 0, 0.9)], 16, 16)), [
        (0, 0),
        (16, 0),
      ]);
      expect(xy(suppressPeaks([p(0, 0, 0.9), p(0, 16, 0.9)], 16, 16)), [
        (0, 0),
        (0, 16),
      ]);
    });

    test('suppression needs both axes within the template', () {
      expect(xy(suppressPeaks([p(0, 0, 0.9), p(15, 16, 0.8)], 16, 16)), [
        (0, 0),
        (15, 16),
      ]);
    });

    test('plateau: earliest in raster order wins among equal neighbours', () {
      final kept = suppressPeaks(
        [p(5, 5, 0.9), p(6, 5, 0.9), p(5, 6, 0.9), p(6, 6, 0.9)],
        2,
        2,
      );
      expect(xy(kept), [(5, 5)]);
    });

    test('plateau applies to diagonal neighbours and ignores input order', () {
      final kept = suppressPeaks([p(6, 6, 0.9), p(5, 5, 0.9)], 1, 1);
      expect(xy(kept), [(5, 5)]);
    });

    test('equal scores that are not neighbours both survive the plateau', () {
      final kept = suppressPeaks([p(0, 0, 0.9), p(2, 0, 0.9)], 2, 2);
      expect(xy(kept), [(0, 0), (2, 0)]);
    });

    test('a lower neighbour is not part of the plateau', () {
      // (0,0) is earlier but scores lower; (1,0) still survives the plateau
      // rule and then suppresses it.
      final kept = suppressPeaks([p(0, 0, 0.85), p(1, 0, 0.9)], 16, 16);
      expect(xy(kept), [(1, 0)]);
    });

    test('order is score desc, then y asc, then x asc', () {
      final kept = suppressPeaks(
        [
          p(100, 0, 0.9),
          p(0, 100, 0.9),
          p(50, 100, 0.9),
          p(0, 0, 0.95),
          p(0, 200, 0.85),
        ],
        10,
        10,
      );
      expect(xy(kept), [(0, 0), (100, 0), (0, 100), (50, 100), (0, 200)]);
    });

    test('maxPeaks 8 are kept in visit order', () {
      final candidates = [
        for (var i = 0; i < 12; i++) p(i * 100, 0, 0.99 - i * 0.01),
      ];
      final kept = suppressPeaks(candidates, 10, 10);
      expect(kept, hasLength(8));
      expect(xy(kept), [for (var i = 0; i < 8; i++) (i * 100, 0)]);
    });

    test('maxPeaks is configurable', () {
      final candidates = [for (var i = 0; i < 5; i++) p(i * 100, 0, 0.9)];
      expect(suppressPeaks(candidates, 10, 10, maxPeaks: 2), hasLength(2));
    });

    test('empty input gives an empty result', () {
      expect(suppressPeaks(const [], 16, 16), isEmpty);
    });
  });
}
