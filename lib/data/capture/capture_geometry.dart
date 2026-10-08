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

/// Plans the targeted region around the desktop point ([x], [y]) in physical
/// client pixels (design D4). DPI never changes the region.
PlanResult planTargeted(
  WindowSnapshot snapshot, {
  required int x,
  required int y,
}) {
  final client = snapshot.client;
  if (client.isEmpty) return const PlanFailure(RoiOutsideClient());
  if (!client.containsPoint(x, y)) return const PlanFailure(RoiOutsideClient());
  final cx = x - client.left;
  final cy = y - client.top;
  // s = min(w / 1920, h / 1080) as the exact rational n / (1920 * 1080), so
  // floor(k * s) is an integer division.
  const denominator = 1920 * 1080;
  final n = client.width * 1080 < client.height * 1920
      ? client.width * 1080
      : client.height * 1920;
  final m = (50 * n) ~/ denominator;
  final r = (600 * n) ~/ denominator;
  final requested = CaptureRect(cx - m ~/ 2, cy - m ~/ 2, m + r, m);
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
