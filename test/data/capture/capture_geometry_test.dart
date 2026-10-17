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
    // client size -> the planned (left, top, width, height) for a click at
    // client point (900, 500).
    final cells = <(int, int, CaptureRect)>[
      (1920, 1080, const CaptureRect(520, 0, 1140, 600)),
      (2560, 1440, const CaptureRect(694, 0, 1519, 800)),
      (3440, 1440, const CaptureRect(1134, 0, 1519, 800)),
      (3840, 2160, const CaptureRect(1040, 0, 2280, 1200)),
    ];

    test('targeted region for all 16 resolution and DPI cells', () {
      var count = 0;
      for (final (w, h, expected) in cells) {
        for (final dpi in const [96, 120, 144, 192]) {
          final plan = planned(
            planTargeted(
              snapshot(client: CaptureRect(0, 0, w, h), dpi: dpi),
              x: 900,
              y: 500,
            ),
          );
          expect(plan.requested, expected, reason: '${w}x$h @ $dpi dpi');
          expect(plan.captured, plan.requested);
          expect(plan.clipped, isFalse);
          count++;
        }
      }
      expect(count, 16);
    });

    test('targeted region is the same for any in-client point', () {
      final hd = snapshot(client: const CaptureRect(0, 0, 1920, 1080));
      for (final (x, y) in const [(10, 10), (900, 500), (1900, 1070)]) {
        final plan = planned(planTargeted(hd, x: x, y: y));
        expect(
          plan.requested,
          const CaptureRect(520, 0, 1140, 600),
          reason: '($x, $y)',
        );
        expect(plan.clipped, isFalse, reason: '($x, $y)');
      }
    });

    test('targeted region on a 1920x1200 client starts at the top', () {
      final plan = planned(
        planTargeted(
          snapshot(client: const CaptureRect(0, 0, 1920, 1200)),
          x: 900,
          y: 500,
        ),
      );
      expect(plan.requested, const CaptureRect(520, 0, 1140, 660));
      expect(plan.clipped, isFalse);
    });

    test('targeted region on a 1366x768 client floors each term', () {
      final plan = planned(
        planTargeted(
          snapshot(client: const CaptureRect(0, 0, 1366, 768)),
          x: 600,
          y: 300,
        ),
      );
      expect(plan.requested, const CaptureRect(371, 0, 809, 426));
      expect(plan.clipped, isFalse);
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
      expect(plan.requested, const CaptureRect(694, 0, 1519, 800));
      expect(plan.captured, const CaptureRect(694, 0, 1519, 800));
      expect(plan.desktop, const CaptureRect(-1866, -360, 1519, 800));
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
    test('band inside a visible client is not clipped', () {
      final plan = planned(
        planTargeted(
          snapshot(client: const CaptureRect(0, 0, 1920, 1080)),
          x: 900,
          y: 500,
        ),
      );
      expect(plan.requested, const CaptureRect(520, 0, 1140, 600));
      expect(plan.captured, plan.requested);
      expect(plan.clipped, isFalse);
    });

    test('right-edge region is clipped not padded', () {
      final plan = planned(
        planTargeted(
          snapshot(
            client: const CaptureRect(0, 0, 1920, 1080),
            virtualDesktop: const CaptureRect(0, 0, 1200, 1080),
          ),
          x: 600,
          y: 500,
        ),
      );
      expect(plan.requested, const CaptureRect(520, 0, 1140, 600));
      expect(plan.captured, const CaptureRect(520, 0, 680, 600));
      expect(plan.desktop, const CaptureRect(520, 0, 680, 600));
      expect(plan.clipped, isTrue);
    });

    test('top-left region is clipped not padded', () {
      final plan = planned(
        planTargeted(
          snapshot(
            client: const CaptureRect(-1000, -200, 1920, 1080),
            virtualDesktop: const CaptureRect(0, 0, 1920, 1080),
          ),
          x: 500,
          y: 300,
        ),
      );
      expect(plan.requested, const CaptureRect(520, 0, 1140, 600));
      expect(plan.captured, const CaptureRect(1000, 200, 660, 400));
      expect(plan.desktop, const CaptureRect(0, 0, 660, 400));
      expect(plan.clipped, isTrue);
    });

    test('off-desktop region is roiOutsideClient', () {
      // The trigger is inside the client, but the desktop begins after the
      // whole band.
      final result = planTargeted(
        snapshot(
          client: const CaptureRect(-1700, 0, 1920, 1080),
          virtualDesktop: const CaptureRect(0, 0, 1920, 1080),
        ),
        x: 100,
        y: 500,
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
