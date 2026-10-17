/// Pure parts of the targeted-region replay (design D5): `frames.jsonl`
/// parsing, the centred band, per-frame classification, the summary and the
/// report, and the output guard.
///
/// Nothing here loads the vision runtime or reads a recording. The
/// qualification test `targeted_region_replay_test.dart` supplies the real
/// service; these parts are unit-tested offline in
/// `targeted_region_replay_support_test.dart`.
///
/// The hint fields of a recorded line (`outcome`, `acceptedId` and the rest)
/// are never read: they are what the app saw at record time, not truth.
library;

import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/output_path_guard.dart';
import 'package:blackgrid/data/capture/capture_geometry.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';

/// Most lines one session's `frames.jsonl` may hold: a recording session
/// stops at 500 hand-offs, so a longer file is not a recording.
const int replayMaxFramesPerSession = 500;

/// The run-directory subdirectory the replay writes into.
const String replayOutputDir = 'out';

/// The report file name inside [replayOutputDir].
const String replayReportName = 'replay.json';

/// The version of the `replay.json` layout.
const int replayReportVersion = 1;

/// Why a recorded line is not replayed.
enum ReplaySkip {
  /// The line has no whole-client image (`image: null`).
  noImage,

  /// The whole-client image is clipped, so it is smaller than the client.
  clipped,

  /// The scan was full-client: it has no cursor to place the band from.
  fullClient,
}

/// One replayable recorded scan: a targeted line with a whole-client image.
final class ReplayFrame {
  /// Creates a frame.
  const ReplayFrame({
    required this.id,
    required this.image,
    required this.clientWidth,
    required this.clientHeight,
    required this.cursorX,
    required this.cursorY,
  });

  /// The recorded scan id.
  final String id;

  /// The whole-client PNG file name, relative to the session folder.
  final String image;

  /// Client width in pixels.
  final int clientWidth;

  /// Client height in pixels.
  final int clientHeight;

  /// Cursor x in client pixels at the scan.
  final int cursorX;

  /// Cursor y in client pixels at the scan.
  final int cursorY;
}

/// The replayable frames of one session and what was skipped.
final class ReplaySession {
  /// Creates a parsed session.
  const ReplaySession(this.frames, this.skipped, this.partialFinalLine);

  /// The frames to replay, in file order.
  final List<ReplayFrame> frames;

  /// The number of skipped lines per reason; every reason is present.
  final Map<ReplaySkip, int> skipped;

  /// Whether an unparseable final line was dropped.
  final bool partialFinalLine;
}

final _plainFileName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

/// Parses a session's `frames.jsonl` [source] by the CORPUS.md rules.
///
/// Lines with `image: null`, `clipped: true` or `kind: fullClient` are
/// skipped and counted in [ReplaySession.skipped]. An unparseable final line
/// (a crash mid-append) is dropped and reported in
/// [ReplaySession.partialFinalLine]. Any other malformed line, a duplicate
/// id, or more than [replayMaxFramesPerSession] lines throws a
/// [FormatException] naming the line.
ReplaySession parseFramesJsonl(String source) {
  final lines = const LineSplitter().convert(source);
  if (lines.length > replayMaxFramesPerSession) {
    throw FormatException(
      'frames.jsonl has ${lines.length} lines, more than the '
      '$replayMaxFramesPerSession a recording session writes',
    );
  }
  final frames = <ReplayFrame>[];
  final skipped = {for (final r in ReplaySkip.values) r: 0};
  final seen = <String>{};
  var partial = false;
  for (final (index, text) in lines.indexed) {
    final number = index + 1;
    Never bad(String why) =>
        throw FormatException('frames.jsonl line $number: $why');
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      if (number == lines.length && text.isNotEmpty) {
        partial = true;
        break;
      }
      bad('not JSON');
    }
    final line = switch (decoded) {
      final Map<String, Object?> m => m,
      _ => bad('not a JSON object'),
    };
    if (line['v'] != 1) bad('unsupported version ${line['v']}');
    final id = switch (line['id']) {
      final String s when s.isNotEmpty => s,
      _ => bad('missing id'),
    };
    if (!seen.add(id)) bad('duplicate id $id');
    final fullClient = switch (line['kind']) {
      'targeted' => false,
      'fullClient' => true,
      final other => bad('$id: unknown kind $other'),
    };
    final image = switch (line['image']) {
      null => null,
      final String s when _plainFileName.hasMatch(s) => s,
      final other => bad('$id: image $other is not a plain file name'),
    };
    if (image == null) {
      skipped.update(ReplaySkip.noImage, (n) => n + 1);
      continue;
    }
    final clipped = switch (line['clipped']) {
      final bool b => b,
      _ => bad('$id: clipped must be true or false with an image'),
    };
    if (clipped) {
      skipped.update(ReplaySkip.clipped, (n) => n + 1);
      continue;
    }
    if (fullClient) {
      skipped.update(ReplaySkip.fullClient, (n) => n + 1);
      continue;
    }
    final (width, height) = switch (line['client']) {
      {'width': final int w, 'height': final int h} when w > 0 && h > 0 => (
        w,
        h,
      ),
      _ => bad('$id: client must hold a positive width and height'),
    };
    final (x, y) = switch (line['cursor']) {
      {'x': final int x, 'y': final int y}
          when x >= 0 && y >= 0 && x < width && y < height =>
        (x, y),
      {'x': int(), 'y': int()} => bad('$id: cursor lies outside the client'),
      _ => bad('$id: a targeted line needs a cursor'),
    };
    frames.add(
      ReplayFrame(
        id: id,
        image: image,
        clientWidth: width,
        clientHeight: height,
        cursorX: x,
        cursorY: y,
      ),
    );
  }
  return ReplaySession(frames, skipped, partial);
}

/// The centred targeted band of the app's `planTargeted` for a client of
/// [clientWidth] by [clientHeight] and a trigger at ([cursorX], [cursorY]),
/// in client pixels, or null when the trigger lies outside the client.
CaptureRect? replayBand({
  required int clientWidth,
  required int clientHeight,
  required int cursorX,
  required int cursorY,
}) {
  final client = CaptureRect(0, 0, clientWidth, clientHeight);
  final snapshot = WindowSnapshot(
    hwnd: 0,
    pid: 0,
    tid: 0,
    minimised: false,
    foreground: true,
    dpi: 96,
    client: client,
    monitor: client,
    virtualDesktop: client,
    title: 'replay',
  );
  return switch (planTargeted(snapshot, x: cursorX, y: cursorY)) {
    PlanOk(:final plan) => plan.captured,
    PlanFailure() => null,
  };
}

/// Whether a marker whose top-left corner is at ([x], [y]) lies inside
/// [band]; both are in client pixels.
bool markerInsideBand(CaptureRect band, int x, int y) =>
    x >= band.left &&
    y >= band.top &&
    x < band.left + band.width &&
    y < band.top + band.height;

/// How the two passes over one frame compare.
enum ReplayVerdict {
  /// Both passes accepted the same item.
  agreement,

  /// Neither pass accepted an item.
  bothRejected,

  /// The targeted pass accepted an item the full-client pass did not: it
  /// rejected, or accepted another item. This is the hard failure.
  conflict,

  /// The full-client pass accepted an item and the targeted pass rejected.
  miss,
}

/// Why the targeted pass missed a full-client accept.
enum ReplayMissCause {
  /// The full-client winner's marker lies outside the band.
  winnerOutsideBand,

  /// The marker lies inside the band and the targeted pass still rejected.
  insideBandRejected,
}

/// What both passes produced for one frame.
final class ReplayFrameResult {
  /// Creates a frame result.
  const ReplayFrameResult({
    required this.frameId,
    required this.session,
    required this.band,
    required this.targetedAccepted,
    required this.fullClientAccepted,
    required this.targetedRejectReason,
    required this.fullClientRejectReason,
    required this.targetedMs,
    required this.fullClientMs,
    required this.fullWinnerInBand,
  });

  /// The recorded scan id.
  final String frameId;

  /// The session folder the frame came from.
  final String session;

  /// The band the targeted pass read, in client pixels.
  final CaptureRect band;

  /// The item the targeted pass accepted alone, or null when it rejected.
  final String? targetedAccepted;

  /// The item the full-client pass accepted alone, or null when it rejected.
  final String? fullClientAccepted;

  /// The targeted outcome's reject reason name, when rejected.
  final String? targetedRejectReason;

  /// The full-client outcome's reject reason name, when rejected.
  final String? fullClientRejectReason;

  /// The targeted job time in milliseconds.
  final int targetedMs;

  /// The full-client job time in milliseconds.
  final int fullClientMs;

  /// Whether the full-client winner's marker lies inside [band]; null when
  /// the full-client pass rejected.
  final bool? fullWinnerInBand;

  /// How the two passes compare.
  ReplayVerdict get verdict => switch ((targetedAccepted, fullClientAccepted)) {
    (null, null) => ReplayVerdict.bothRejected,
    (null, _) => ReplayVerdict.miss,
    (final t?, final f) when t == f => ReplayVerdict.agreement,
    _ => ReplayVerdict.conflict,
  };

  /// Why the targeted pass missed, or null when the verdict is not a miss.
  ReplayMissCause? get missCause => verdict != ReplayVerdict.miss
      ? null
      : fullWinnerInBand == true
      ? ReplayMissCause.insideBandRejected
      : ReplayMissCause.winnerOutsideBand;

  /// The JSON form written to `replay.json`.
  Map<String, Object?> toJson() => {
    'id': frameId,
    'session': session,
    'band': {
      'left': band.left,
      'top': band.top,
      'width': band.width,
      'height': band.height,
    },
    'targetedAccepted': targetedAccepted,
    'targetedRejectReason': targetedRejectReason,
    'fullClientAccepted': fullClientAccepted,
    'fullClientRejectReason': fullClientRejectReason,
    'targetedMs': targetedMs,
    'fullClientMs': fullClientMs,
    'fullWinnerInBand': fullWinnerInBand,
    'verdict': verdict.name,
    'missCause': missCause?.name,
  };
}

/// The nearest-rank p50, p90, p95 and p99, the maximum and the count of the
/// job times [ms]; the statistics are null with no samples.
Map<String, Object?> jobTimeDistribution(Iterable<int> ms) {
  final sorted = ms.toList()..sort();
  int? rank(int percent) {
    if (sorted.isEmpty) return null;
    final r = (percent * sorted.length + 99) ~/ 100;
    return sorted[(r < 1 ? 1 : r) - 1];
  }

  return {
    'count': sorted.length,
    'p50': rank(50),
    'p90': rank(90),
    'p95': rank(95),
    'p99': rank(99),
    'max': sorted.isEmpty ? null : sorted.last,
  };
}

/// The totals of a replay run.
final class ReplaySummary {
  ReplaySummary._(this._results);

  final List<ReplayFrameResult> _results;

  Iterable<ReplayFrameResult> _with(ReplayVerdict v) =>
      _results.where((r) => r.verdict == v);

  /// The number of frames replayed.
  int get frames => _results.length;

  /// The number of frames the full-client pass accepted.
  int get fullClientAccepts =>
      _results.where((r) => r.fullClientAccepted != null).length;

  /// The full-client accepts the targeted pass accepted too, as the same
  /// item.
  int get alsoAcceptedByTargeted => _with(ReplayVerdict.agreement).length;

  /// [alsoAcceptedByTargeted] over [fullClientAccepts], or null when the
  /// full-client pass accepted nothing.
  double? get share => fullClientAccepts == 0
      ? null
      : alsoAcceptedByTargeted / fullClientAccepts;

  /// The ids of the frames with a conflicting accept.
  List<String> get conflicts => [
    for (final r in _with(ReplayVerdict.conflict)) r.frameId,
  ];

  /// The ids of the missed frames, by cause; every cause is present.
  Map<ReplayMissCause, List<String>> get misses => {
    for (final cause in ReplayMissCause.values)
      cause: [
        for (final r in _results)
          if (r.missCause == cause) r.frameId,
      ],
  };

  /// The JSON form written as the report's `summary`.
  Map<String, Object?> toJson() => {
    'frames': frames,
    'fullClientAccepts': fullClientAccepts,
    'alsoAcceptedByTargeted': alsoAcceptedByTargeted,
    'share': share,
    'agreements': alsoAcceptedByTargeted,
    'bothRejected': _with(ReplayVerdict.bothRejected).length,
    'conflictCount': conflicts.length,
    'conflicts': conflicts,
    'misses': {
      for (final MapEntry(:key, :value) in misses.entries) key.name: value,
    },
    'targetedMs': jobTimeDistribution(_results.map((r) => r.targetedMs)),
    'fullClientMs': jobTimeDistribution(_results.map((r) => r.fullClientMs)),
  };
}

/// Summarises [results].
ReplaySummary summariseReplay(List<ReplayFrameResult> results) =>
    ReplaySummary._(List.unmodifiable(results));

/// The `replay.json` document: the summary, each session with its skip
/// counts, and every frame result.
Map<String, Object?> buildReplayReport({
  required List<({String directory, ReplaySession session})> sessions,
  required List<ReplayFrameResult> results,
}) => {
  'version': replayReportVersion,
  'summary': summariseReplay(results).toJson(),
  'sessions': [
    for (final (:directory, :session) in sessions)
      {
        'directory': directory,
        'frames': session.frames.length,
        'skipped': {
          for (final MapEntry(:key, :value) in session.skipped.entries)
            key.name: value,
        },
        'partialFinalLine': session.partialFinalLine,
      },
  ],
  'frames': [for (final r in results) r.toJson()],
};

/// The report path `<runDirectory>/out/replay.json`.
String replayReportPath(String runDirectory) {
  final sep = Platform.pathSeparator;
  return '${Directory(runDirectory).absolute.path}$sep$replayOutputDir$sep'
      '$replayReportName';
}

/// Why writing the report at [reportPath] is refused, or null when it is
/// safe.
///
/// Refused when the path, its temp sibling or an ancestor is a link or
/// junction, when it would overwrite one of [inputFiles], or when it lies
/// inside one of [inputDirectories] (the recording folders and the bundle).
String? replayOutputRefusal(
  String reportPath, {
  required List<String> inputDirectories,
  required List<String> inputFiles,
}) => unsafeOutputReason(
  reportPath,
  protectedFiles: inputFiles,
  protectedDirectories: inputDirectories,
);
