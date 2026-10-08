/// A rectangle in signed integer pixels. Desktop rectangles use physical
/// desktop coordinates and may have negative origins; client rectangles are
/// relative to the client origin.
final class CaptureRect {
  const CaptureRect(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;
  bool get isEmpty => width <= 0 || height <= 0;

  CaptureRect translate(int dx, int dy) =>
      CaptureRect(left + dx, top + dy, width, height);

  bool containsPoint(int x, int y) =>
      x >= left && x < right && y >= top && y < bottom;

  /// The intersection, or null when it is empty.
  CaptureRect? intersect(CaptureRect other) {
    final l = left > other.left ? left : other.left;
    final t = top > other.top ? top : other.top;
    final r = right < other.right ? right : other.right;
    final b = bottom < other.bottom ? bottom : other.bottom;
    if (r <= l || b <= t) return null;
    return CaptureRect(l, t, r - l, b - t);
  }

  @override
  bool operator ==(Object other) =>
      other is CaptureRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => '($left, $top, $width, $height)';
}

/// Window facts decoded from `bgc_window_snapshot`. Plain sendable data.
final class WindowSnapshot {
  const WindowSnapshot({
    required this.hwnd,
    required this.pid,
    required this.tid,
    required this.minimised,
    required this.foreground,
    required this.dpi,
    required this.client,
    required this.monitor,
    required this.virtualDesktop,
    required this.title,
  });

  final int hwnd;
  final int pid;
  final int tid;
  final bool minimised;
  final bool foreground;
  final int dpi;

  /// Client area in signed physical desktop pixels.
  final CaptureRect client;
  final CaptureRect monitor;
  final CaptureRect virtualDesktop;
  final String title;

  /// Whether [other] describes the same window state for coherence: window,
  /// ids, foreground and minimised state, client rectangle and DPI.
  bool coherentWith(WindowSnapshot other) =>
      hwnd == other.hwnd &&
      pid == other.pid &&
      tid == other.tid &&
      foreground == other.foreground &&
      minimised == other.minimised &&
      client == other.client &&
      dpi == other.dpi;

  /// Names the first field that differs from [other].
  String describeDifference(WindowSnapshot other) {
    if (hwnd != other.hwnd) return 'window handle';
    if (pid != other.pid) return 'process id';
    if (tid != other.tid) return 'thread id';
    if (foreground != other.foreground) return 'foreground state';
    if (minimised != other.minimised) return 'minimised state';
    if (client != other.client) {
      return 'client rectangle $client -> ${other.client}';
    }
    if (dpi != other.dpi) return 'dpi $dpi -> ${other.dpi}';
    return 'none';
  }
}

/// One accepted mouse release, decoded from `bgc_trigger_event`.
final class TriggerEvent {
  const TriggerEvent({
    required this.x,
    required this.y,
    required this.hwnd,
    required this.pid,
    required this.tid,
    required this.qpc,
  });

  /// Physical screen point, signed.
  final int x;
  final int y;
  final int hwnd;
  final int pid;
  final int tid;

  /// `QueryPerformanceCounter` ticks, on the same clock as capture times.
  final int qpc;
}

/// Which region a capture request plans.
enum CaptureMode { targeted, fallback }
