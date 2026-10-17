import 'capture_failure.dart';
import 'capture_snapshot.dart';

/// Capture size bounds, equal to the vision bounds (design D5/D7).
const int captureMaxSide = 8192;
const int captureMaxPixels = 24 * 1024 * 1024;

/// A planned capture. Client rectangles are relative to the client origin;
/// [desktop] is [captured] in signed physical desktop pixels.
final class CapturePlan {
  const CapturePlan({
    required this.requested,
    required this.captured,
    required this.desktop,
  });

  /// The region before any clipping (may extend beyond the client).
  final CaptureRect requested;

  /// The region actually captured, inside the client and the virtual desktop.
  final CaptureRect captured;
  final CaptureRect desktop;

  bool get clipped => requested != captured;
}

sealed class PlanResult {
  const PlanResult();
}

final class PlanOk extends PlanResult {
  const PlanOk(this.plan);

  final CapturePlan plan;
}

final class PlanFailure extends PlanResult {
  const PlanFailure(this.failure);

  final CaptureFailure failure;
}

/// Reference-resolution extent of the targeted band left of the client
/// centre: the centred window (400) plus the 40 pixel cascade margin.
const int targetedLeftReference = 440;

/// Reference-resolution extent of the targeted band right of the client
/// centre: the centred window (400) plus the 300 pixel cascade margin.
const int targetedRightReference = 700;

/// Reference-resolution extent of the targeted band below the client centre.
const int targetedBelowCentreReference = 60;

/// Reference client width and height (1920x1080) that define the scale.
const int _referenceWidth = 1920;
const int _referenceHeight = 1080; // 2 * 540, the reference half height.

/// Plans the targeted region as a fixed band around the client centre
/// (design D1).
///
/// With physical client size `w x h`, `cx = w div 2`, `cy = h div 2` and the
/// exact rational scale `s = min(w / 1920, h / 1080)`, the band is
/// `(cx - f(440), 0, f(440) + f(700), cy + f(60))` where `f(k) = floor(k * s)`.
/// The point ([x], [y]) no longer moves the region; it must still lie inside
/// the client or the plan fails with [RoiOutsideClient]. DPI never changes
/// the region, and only the virtual desktop can clip it.
PlanResult planTargeted(
  WindowSnapshot snapshot, {
  required int x,
  required int y,
}) {
  final client = snapshot.client;
  if (client.isEmpty) return const PlanFailure(RoiOutsideClient());
  if (!client.containsPoint(x, y)) return const PlanFailure(RoiOutsideClient());
  // s = min(w / 1920, h / 1080) as the exact rational n / (1920 * 1080), so
  // floor(k * s) is an integer division.
  const denominator = _referenceWidth * _referenceHeight;
  final n = client.width * _referenceHeight < client.height * _referenceWidth
      ? client.width * _referenceHeight
      : client.height * _referenceWidth;
  int f(int k) => (k * n) ~/ denominator;
  final cx = client.width ~/ 2;
  final cy = client.height ~/ 2;
  final left = f(targetedLeftReference);
  final requested = CaptureRect(
    cx - left,
    0,
    left + f(targetedRightReference),
    cy + f(targetedBelowCentreReference),
  );
  return _clip(snapshot, requested);
}

/// Plans the whole client, clipped to the virtual desktop.
PlanResult planFallback(WindowSnapshot snapshot) {
  final client = snapshot.client;
  if (client.isEmpty) return const PlanFailure(RoiOutsideClient());
  return _clip(snapshot, CaptureRect(0, 0, client.width, client.height));
}

PlanResult _clip(WindowSnapshot snapshot, CaptureRect requested) {
  final client = snapshot.client;
  final inClient = requested.intersect(
    CaptureRect(0, 0, client.width, client.height),
  );
  if (inClient == null) return const PlanFailure(RoiOutsideClient());
  // Express the virtual desktop in client coordinates, then intersect.
  final desktopInClient = snapshot.virtualDesktop.translate(
    -client.left,
    -client.top,
  );
  final captured = inClient.intersect(desktopInClient);
  if (captured == null) return const PlanFailure(RoiOutsideClient());
  if (captured.width > captureMaxSide ||
      captured.height > captureMaxSide ||
      captured.width * captured.height > captureMaxPixels) {
    return PlanFailure(CaptureTooLarge(captured.width, captured.height));
  }
  return PlanOk(
    CapturePlan(
      requested: requested,
      captured: captured,
      desktop: captured.translate(client.left, client.top),
    ),
  );
}
