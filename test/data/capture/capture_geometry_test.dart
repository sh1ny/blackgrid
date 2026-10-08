import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_geometry.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

WindowSnapshot snapshot({
  required CaptureRect client,
  CaptureRect? virtualDesktop,
  int dpi = 96,
}) => WindowSnapshot(
  hwnd: 0x1234,
  pid: 10,
  tid: 11,
  minimised: false,
  foreground: true,
  dpi: dpi,
  client: client,
  monitor: virtualDesktop ?? client,
  virtualDesktop:
      virtualDesktop ??
      CaptureRect(
        client.left < 0 ? client.left : 0,
        client.top < 0 ? client.top : 0,
        client.right + (client.left < 0 ? -client.left : 0),
        client.bottom + (client.top < 0 ? -client.top : 0),
      ),
  title: 'EscapeFromTarkov',
);

CapturePlan planned(PlanResult result) {
  expect(result, isA<PlanOk>(), reason: '$result');
  return (result as PlanOk).plan;
}

void main() {
  group('targeted planning', () {
    // Expected values come from the spec scenarios, not from the planner.
    // client size -> (planned width, height, origin x, origin y) for a click
    // at client point (900, 500).
    final cells = <(int, int, int, int, int, int)>[
      (1920, 1080, 650, 50, 875, 475),
      (2560, 1440, 866, 66, 867, 467),
      (3440, 1440, 866, 66, 867, 467),
      (3840, 2160, 1300, 100, 850, 450),
    ];

    test('targeted region for all 16 resolution and DPI cells', () {
      var count = 0;
      for (final (w, h, pw, ph, ox, oy) in cells) {
        for (final dpi in const [96, 120, 144, 192]) {
          final plan = planned(
            planTargeted(
              snapshot(client: CaptureRect(0, 0, w, h), dpi: dpi),
              x: 900,
              y: 500,
            ),
          );
          expect(
            plan.requested,
            CaptureRect(ox, oy, pw, ph),
            reason: '${w}x$h @ $dpi dpi',
          );
          expect(plan.captured, plan.requested);
          expect(plan.clipped, isFalse);
          count++;
        }
      }
      expect(count, 16);
    });

    test('negative-origin monitor maps to client and back', () {
      final plan = planned(
        planTargeted(
          snapshot(
            client: const CaptureRect(-2560, -360, 2560, 1440),
            virtualDesktop: const CaptureRect(-2560, -360, 4480, 1800),
            dpi: 144,
          ),
          x: -1200,
          y: 340,
        ),
      );
      expect(plan.requested, const CaptureRect(1327, 667, 866, 66));
      expect(plan.captured, const CaptureRect(1327, 667, 866, 66));
      expect(plan.desktop, const CaptureRect(-1233, 307, 866, 66));
      expect(plan.clipped, isFalse);
    });

    test('trigger outside client is roiOutsideClient', () {
      final client = snapshot(client: const CaptureRect(100, 100, 1920, 1080));
      for (final (x, y) in const [
        (99, 500),
        (500, 99),
        (2020, 500),
        (500, 1180),
        (-5, -5),
      ]) {
        final result = planTargeted(client, x: x, y: y);
        expect(result, isA<PlanFailure>(), reason: '($x, $y)');
        expect((result as PlanFailure).failure, isA<RoiOutsideClient>());
      }
    });
  });

  group('fallback', () {
    test('fallback plans the whole client', () {
      final plan = planned(
        planFallback(snapshot(client: const CaptureRect(0, 0, 2560, 1440))),
      );
      expect(plan.requested, const CaptureRect(0, 0, 2560, 1440));
      expect(plan.captured, const CaptureRect(0, 0, 2560, 1440));
      expect(plan.clipped, isFalse);
    });

    test('fallback clips to the virtual desktop', () {
      final plan = planned(
        planFallback(
          snapshot(
            client: const CaptureRect(-100, 0, 1920, 1080),
            virtualDesktop: const CaptureRect(0, 0, 3840, 1080),
          ),
        ),
      );
      expect(plan.requested, const CaptureRect(0, 0, 1920, 1080));
      expect(plan.captured, const CaptureRect(100, 0, 1820, 1080));
      expect(plan.desktop, const CaptureRect(0, 0, 1820, 1080));
      expect(plan.clipped, isTrue);
    });
  });

  group('clipping', () {
    final hd = snapshot(client: const CaptureRect(0, 0, 1920, 1080));

    test('right-edge region is clipped not padded', () {
      final plan = planned(planTargeted(hd, x: 1500, y: 500));
      expect(plan.requested, const CaptureRect(1475, 475, 650, 50));
      expect(plan.captured, const CaptureRect(1475, 475, 445, 50));
      expect(plan.desktop, const CaptureRect(1475, 475, 445, 50));
      expect(plan.clipped, isTrue);
    });

    test('top-left region is clipped not padded', () {
      final plan = planned(planTargeted(hd, x: 10, y: 10));
      expect(plan.requested, const CaptureRect(-15, -15, 650, 50));
      expect(plan.captured, const CaptureRect(0, 0, 635, 35));
      expect(plan.clipped, isTrue);
    });

    test('off-desktop region is roiOutsideClient', () {
      // The client lies inside its own bounds but the virtual desktop ends
      // before the region begins.
      final result = planFallback(
        snapshot(
          client: const CaptureRect(2000, 0, 1920, 1080),
          virtualDesktop: const CaptureRect(0, 0, 1920, 1080),
        ),
      );
      expect(result, isA<PlanFailure>());
      expect((result as PlanFailure).failure, isA<RoiOutsideClient>());
    });
  });

  group('size bounds', () {
    test('3840x2160 fallback is within bounds', () {
      final plan = planned(
        planFallback(snapshot(client: const CaptureRect(0, 0, 3840, 2160))),
      );
      expect(plan.captured, const CaptureRect(0, 0, 3840, 2160));
    });

    test('7680x4320 fallback is captureTooLarge', () {
      final result = planFallback(
        snapshot(client: const CaptureRect(0, 0, 7680, 4320)),
      );
      expect(result, isA<PlanFailure>());
      final failure = (result as PlanFailure).failure;
      expect(failure, isA<CaptureTooLarge>());
      expect(failure.message, contains('7680x4320'));
    });
  });
}
