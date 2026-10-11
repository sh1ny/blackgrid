import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Which kind of capture a recorded scan came from.
enum RecordedScanKind {
  /// The scan read a strip around the cursor.
  targeted('targeted'),

  /// The scan fell back to the whole client area.
  fullClient('fullClient');

  const RecordedScanKind(this.wire);

  /// The string written to `frames.jsonl`.
  final String wire;
}

/// How a recorded scan ended.
enum RecordedOutcome {
  /// The scan published an item.
  accepted('accepted'),

  /// The scan read text that matched no item.
  rejected('rejected'),

  /// The scan failed before it could be matched.
  failed('failed');

  const RecordedOutcome(this.wire);

  /// The string written to `frames.jsonl`.
  final String wire;
}

/// A rectangle in client pixels.
typedef RecordedRect = ({int left, int top, int width, int height});

/// One captured frame, as plain data that can cross an isolate boundary.
class RecordedFrame {
  /// Creates a frame. [pixels] holds [height] rows of [stride] bytes.
  const RecordedFrame({
    required this.width,
    required this.height,
    required this.stride,
    required this.pixels,
    required this.clipped,
    required this.capturedAtUtc,
    required this.captured,
  });

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Bytes per row, which may exceed `width * 4`.
  final int stride;

  /// BGRX pixels in top-down rows. The X byte is undefined.
  final TransferableTypedData pixels;

  /// Whether the capture was clipped to the virtual desktop, so it covers
  /// less than the whole client.
  final bool clipped;

  /// When the frame was captured.
  final DateTime capturedAtUtc;

  /// The client-pixel rectangle the frame covers.
  final RecordedRect captured;
}

/// One published scan, as plain data that can cross an isolate boundary.
class RecordedScan {
  /// Creates a recorded scan. Absent values are `null`.
  const RecordedScan({
    required this.id,
    required this.kind,
    required this.outcome,
    this.clientWidth,
    this.clientHeight,
    this.cursorX,
    this.cursorY,
    this.acceptedId,
    this.rejectReason,
    this.failure,
    this.fullFailure,
    this.text,
    this.targetedMarkerScore,
    this.fallbackMarkerScore,
    this.full,
    this.strip,
  });

  /// The scan's id, which names its files.
  final String id;

  /// Client area width in pixels, or `null` when the scan has no frame.
  final int? clientWidth;

  /// Client area height in pixels, or `null` when the scan has no frame.
  final int? clientHeight;

  /// Whether the scan was targeted or whole-client.
  final RecordedScanKind kind;

  /// Cursor x in client pixels, or `null` for a whole-client scan.
  final int? cursorX;

  /// Cursor y in client pixels, or `null` for a whole-client scan.
  final int? cursorY;

  /// How the scan ended.
  final RecordedOutcome outcome;

  /// The id of the accepted item, when there is one.
  final String? acceptedId;

  /// Why the text was rejected, when it was.
  final String? rejectReason;

  /// The scan's failure code, when it failed.
  final String? failure;

  /// Why no full-client frame exists, when one was attempted.
  final String? fullFailure;

  /// The text read from the frame.
  final String? text;

  /// The marker score of the targeted pass.
  final double? targetedMarkerScore;

  /// The marker score of the fallback pass.
  final double? fallbackMarkerScore;

  /// The full-client frame, when the scan has one.
  final RecordedFrame? full;

  /// The targeted strip, when the scan has one.
  final RecordedFrame? strip;
}

/// File name of the full-client PNG of scan [id].
String scanFullImageName(String id) => '$id-full.png';

/// File name of the targeted-strip PNG of scan [id].
String scanStripImageName(String id) => '$id-targeted.png';

/// Name of the case file inside a session folder.
const String scanFramesFileName = 'frames.jsonl';

/// Serialises [scan] as one `frames.jsonl` line, without the trailing newline.
///
/// The line holds the corpus case fields, then the hint fields. Absent values
/// are explicit `null`; the `cursor` key is omitted for a whole-client scan.
/// There is never an `expected` field: labelling stays with the user.
String encodeScanFrameLine(RecordedScan scan) {
  final full = scan.full;
  final strip = scan.strip;
  final captured = full?.captured;
  final (clientWidth, clientHeight) = (scan.clientWidth, scan.clientHeight);
  final line = <String, Object?>{
    'v': 1,
    'id': scan.id,
    'image': full == null ? null : scanFullImageName(scan.id),
    'client': clientWidth == null || clientHeight == null
        ? null
        : {'width': clientWidth, 'height': clientHeight},
    'kind': scan.kind.wire,
    if (scan.kind == RecordedScanKind.targeted &&
        scan.cursorX != null &&
        scan.cursorY != null)
      'cursor': {'x': scan.cursorX, 'y': scan.cursorY},
    'captured': captured == null
        ? null
        : {
            'left': captured.left,
            'top': captured.top,
            'width': captured.width,
            'height': captured.height,
          },
    'clipped': full?.clipped,
    'strip': strip == null ? null : scanStripImageName(scan.id),
    'outcome': scan.outcome.wire,
    'acceptedId': scan.acceptedId,
    'rejectReason': scan.rejectReason,
    'failure': scan.failure,
    'fullFailure': scan.fullFailure,
    'text': scan.text,
    'targetedMarkerScore': scan.targetedMarkerScore,
    'fallbackMarkerScore': scan.fallbackMarkerScore,
    'stripCapturedAtUtc': strip?.capturedAtUtc.toUtc().toIso8601String(),
    'fullCapturedAtUtc': full?.capturedAtUtc.toUtc().toIso8601String(),
  };
  return jsonEncode(line);
}

/// The file operations the writer needs, so tests can fail them.
abstract interface class ScanFrameFileOps {
  /// Creates [path] and any missing parents.
  Future<void> createDirectory(String path);

  /// Writes [bytes] to [path], replacing it.
  Future<void> writeBytes(String path, List<int> bytes);

  /// Renames [from] to [to], replacing any file at [to].
  Future<void> rename(String from, String to);

  /// Appends [bytes] to [path] in one write, creating it if needed.
  Future<void> appendBytes(String path, List<int> bytes);
}

/// [ScanFrameFileOps] over `dart:io`.
final class DiskScanFrameFileOps implements ScanFrameFileOps {
  /// Creates the disk operations.
  const DiskScanFrameFileOps();

  @override
  Future<void> createDirectory(String path) =>
      Directory(path).create(recursive: true);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      File(path).writeAsBytes(bytes, flush: true);

  @override
  Future<void> rename(String from, String to) async {
    await File(from).rename(to);
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    final handle = await File(path).open(mode: FileMode.append);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
  }
}

/// The default factory for [ScanFrameFileOps]. Top-level so it can be sent to
/// the writer isolate.
ScanFrameFileOps defaultScanFrameFileOps() => const DiskScanFrameFileOps();

/// What the writer reports back, each tagged with the session [token] it was
/// spawned for so a late answer from an earlier session can be ignored.
sealed class ScanFrameWriterAnswer {
  const ScanFrameWriterAnswer(this.token);

  /// The token of the session this writer belongs to.
  final int token;
}

/// The scan [id] has its PNGs and its line on disk.
final class ScanFrameAck extends ScanFrameWriterAnswer {
  /// Creates an acknowledgement for scan [id].
  const ScanFrameAck(super.token, this.id);

  /// The scan's id.
  final String id;
}

/// The scan [id] could not be written and has no line.
final class ScanFrameFailure extends ScanFrameWriterAnswer {
  /// Creates a failure for scan [id] carrying [error].
  const ScanFrameFailure(super.token, this.id, this.error);

  /// The scan's id.
  final String id;

  /// The description of what went wrong.
  final String error;
}

/// The writer isolate died, exited or raised an uncaught error.
final class ScanFrameWriterExited extends ScanFrameWriterAnswer {
  /// Creates an exit answer, with [error] when the isolate failed.
  const ScanFrameWriterExited(super.token, [this.error]);

  /// The uncaught error, or `null` for a plain exit.
  final String? error;
}

/// A writer of recorded scans, which the recorder can fake in tests.
abstract interface class ScanFrameWriter {
  /// Queues [scan]. The writer handles scans one at a time, in order, and
  /// answers each with a [ScanFrameAck] or [ScanFrameFailure].
  void write(RecordedScan scan);

  /// Stops the writer at once. A scan being written may leave a `.png.tmp`
  /// but never a partial `.png` or a line. No answer follows.
  void kill();
}

/// [ScanFrameWriter] running in its own isolate.
///
/// Per scan the isolate materialises each frame, builds an image, encodes a
/// PNG, writes `<name>.png.tmp` and renames it to `<name>.png`, the full frame
/// first. Only once every PNG exists does it append the line to
/// `frames.jsonl` in one write. Any error yields a [ScanFrameFailure] and no
/// line.
///
/// Pixels use the image 4.8.0 API: `Image.fromBytes` with `numChannels: 4`,
/// `rowStride: stride` and `ChannelOrder.bgra`, then `convert(numChannels: 3)`
/// to drop the undefined fourth byte, then `encodePng` at a fast level.
class IsolateScanFrameWriter implements ScanFrameWriter {
  IsolateScanFrameWriter._(
    this._isolate,
    this._commands,
    this._replies,
    this._exits,
    this._errors,
  );

  /// PNG compression level: fast, since the frame is written off the scan path.
  static const int pngLevel = 1;

  /// Spawns a writer for [folder], tagging every answer with [token].
  ///
  /// [fileOps] runs inside the isolate, so it must be a top-level or static
  /// function. [onAnswer] runs on the calling isolate.
  static Future<IsolateScanFrameWriter> spawn({
    required String folder,
    required int token,
    required void Function(ScanFrameWriterAnswer answer) onAnswer,
    ScanFrameFileOps Function() fileOps = defaultScanFrameFileOps,
  }) async {
    final replies = ReceivePort();
    final exits = ReceivePort();
    final errors = ReceivePort();
    final ready = Completer<SendPort>();
    var exited = false;
    void exit(String? error) {
      if (exited) return;
      exited = true;
      if (!ready.isCompleted) {
        ready.completeError(StateError('scan frame writer exited: $error'));
      }
      onAnswer(ScanFrameWriterExited(token, error));
    }

    replies.listen((Object? message) {
      switch (message) {
        case SendPort port when !ready.isCompleted:
          ready.complete(port);
        case _Ack(:final id):
          onAnswer(ScanFrameAck(token, id));
        case _Failure(:final id, :final error):
          onAnswer(ScanFrameFailure(token, id, error));
      }
    });
    exits.listen((_) => exit(null));
    errors.listen((Object? message) => exit(message.toString()));

    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _writerMain,
        _Init(replies.sendPort, folder, fileOps),
        onExit: exits.sendPort,
        onError: errors.sendPort,
      );
    } on Object {
      replies.close();
      exits.close();
      errors.close();
      rethrow;
    }
    final commands = await ready.future;
    return IsolateScanFrameWriter._(isolate, commands, replies, exits, errors);
  }

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _replies;
  final ReceivePort _exits;
  final ReceivePort _errors;

  @override
  void write(RecordedScan scan) => _commands.send(scan);

  @override
  void kill() {
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
    _exits.close();
    _errors.close();
  }
}

final class _Init {
  const _Init(this.replies, this.folder, this.fileOps);

  final SendPort replies;
  final String folder;
  final ScanFrameFileOps Function() fileOps;
}

final class _Ack {
  const _Ack(this.id);

  final String id;
}

final class _Failure {
  const _Failure(this.id, this.error);

  final String id;
  final String error;
}

Future<void> _writerMain(_Init init) async {
  final commands = ReceivePort();
  init.replies.send(commands.sendPort);
  final ops = init.fileOps();
  // `await for` handles one scan to the end before taking the next.
  await for (final message in commands) {
    if (message is! RecordedScan) continue;
    try {
      await _writeScan(ops, init.folder, message);
      init.replies.send(_Ack(message.id));
    } on Object catch (error) {
      init.replies.send(_Failure(message.id, error.toString()));
      // A failed session writes nothing more: leaving the loop closes the
      // command port, drops the scans queued behind and ends the isolate.
      break;
    }
  }
}

Future<void> _writeScan(
  ScanFrameFileOps ops,
  String folder,
  RecordedScan scan,
) async {
  await ops.createDirectory(folder);
  final full = scan.full;
  final strip = scan.strip;
  if (full != null) {
    await _writePng(ops, '$folder/${scanFullImageName(scan.id)}', full);
  }
  if (strip != null) {
    await _writePng(ops, '$folder/${scanStripImageName(scan.id)}', strip);
  }
  // Both PNGs are final, so the line may name them. One write keeps a crash
  // from leaving more than a torn last line.
  await ops.appendBytes(
    '$folder/$scanFramesFileName',
    utf8.encode('${encodeScanFrameLine(scan)}\n'),
  );
}

Future<void> _writePng(
  ScanFrameFileOps ops,
  String path,
  RecordedFrame frame,
) async {
  final bgrx = frame.pixels.materialize();
  final image = img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: bgrx,
    numChannels: 4,
    rowStride: frame.stride,
    order: img.ChannelOrder.bgra,
  ).convert(numChannels: 3);
  final png = img.encodePng(image, level: IsolateScanFrameWriter.pngLevel);
  await ops.writeBytes('$path.tmp', png);
  await ops.rename('$path.tmp', path);
}

/// Where a recording session stands.
enum ScanRecordingState {
  /// No session. Scans are refused.
  off,

  /// A session is creating its folder and spawning its writer.
  starting,

  /// A session takes scans.
  on,

  /// A session takes no new scans and waits for the outstanding ones.
  stopping,
}

/// Why a session ended.
sealed class ScanRecordingStopReason {
  const ScanRecordingStopReason();
}

/// The session handed over [ScanFrameRecorder.maxHandOffs] scans.
final class ScanRecordingCapReached extends ScanRecordingStopReason {
  /// Creates the cap reason.
  const ScanRecordingCapReached();
}

/// The session folder or the writer could not be created.
final class ScanRecordingStartFailed extends ScanRecordingStopReason {
  /// Creates a start failure carrying [error].
  const ScanRecordingStartFailed(this.error);

  /// The description of what went wrong.
  final String error;
}

/// The writer failed or died, so the session ended.
final class ScanRecordingWriteFailed extends ScanRecordingStopReason {
  /// Creates a write failure carrying [error].
  const ScanRecordingWriteFailed(this.error);

  /// The description of what went wrong.
  final String error;
}

/// An immutable snapshot of the recorder, for the panel.
///
/// After a session ends the folder, counts and [stopReason] stay until the
/// next [ScanFrameRecorder.start], so the panel can still show them.
@immutable
class ScanRecordingStatus {
  /// Creates a status.
  const ScanRecordingStatus({
    this.state = ScanRecordingState.off,
    this.written = 0,
    this.dropped = 0,
    this.handedOff = 0,
    this.folder,
    this.stopReason,
  });

  /// The session state.
  final ScanRecordingState state;

  /// Scans acknowledged as written this session.
  final int written;

  /// Scans left out of the recording this session: dropped at the outstanding
  /// bound, or lost with the writer.
  final int dropped;

  /// Scans handed to the writer this session.
  final int handedOff;

  /// The session folder path, or `null` before one was created.
  final String? folder;

  /// Why the last session ended, or `null` while it runs or after a plain
  /// stop.
  final ScanRecordingStopReason? stopReason;

  ScanRecordingStatus _copy({
    ScanRecordingState? state,
    int? written,
    int? dropped,
    int? handedOff,
    String? folder,
    ScanRecordingStopReason? stopReason,
  }) => ScanRecordingStatus(
    state: state ?? this.state,
    written: written ?? this.written,
    dropped: dropped ?? this.dropped,
    handedOff: handedOff ?? this.handedOff,
    folder: folder ?? this.folder,
    stopReason: stopReason ?? this.stopReason,
  );
}

/// What [ScanFrameRecorder.record] did with a scan.
enum ScanRecordResult {
  /// The scan went to the writer.
  handedOver,

  /// Two scans were outstanding, so the scan was dropped and counted.
  dropped,

  /// Recording is not taking scans. Nothing is counted.
  refused,
}

/// Creates the writer of a session.
typedef ScanFrameWriterFactory = Future<ScanFrameWriter> Function({
  required String folder,
  required int token,
  required void Function(ScanFrameWriterAnswer answer) onAnswer,
});

/// Owns the recording session: its state, token, counts and writer.
///
/// States run `off`, `starting`, `on`, `stopping`, back to `off`. Every writer
/// answer carries the token of the session it was spawned for, and answers
/// with another token are ignored. All calls come from the UI isolate.
class ScanFrameRecorder {
  /// Creates a recorder that puts session folders under [root].
  ///
  /// [clock] names the folders by local time. [writerFactory] spawns the
  /// writer and defaults to [IsolateScanFrameWriter.spawn].
  ScanFrameRecorder({
    required this.root,
    this.clock = DateTime.now,
    ScanFrameWriterFactory? writerFactory,
  }) : _spawn = writerFactory ?? _spawnIsolateWriter;

  /// Scans that may be handed to the writer and not yet written.
  static const int maxOutstanding = 2;

  /// Hand-offs one session accepts.
  static const int maxHandOffs = 500;

  /// How long [close] waits for outstanding scans by default.
  static const Duration defaultCloseTimeout = Duration(seconds: 2);

  /// The directory holding the session folders.
  final String root;

  /// The clock that names session folders.
  final DateTime Function() clock;

  final ScanFrameWriterFactory _spawn;
  final ValueNotifier<ScanRecordingStatus> _status =
      ValueNotifier<ScanRecordingStatus>(const ScanRecordingStatus());

  int _token = 0;
  int _outstanding = 0;
  bool _closed = false;
  ScanFrameWriter? _writer;
  Completer<void> _ended = Completer<void>()..complete();

  /// The recorder's state, counts, folder and stop reason.
  ValueListenable<ScanRecordingStatus> get status => _status;

  ScanRecordingStatus get _now => _status.value;

  /// Starts a session and completes with whether it is now `on`.
  ///
  /// Refused, with `false` and no folder, unless the recorder is `off` and not
  /// closed. Resets the counts, creates the session folder and spawns the
  /// writer. A folder or spawn failure leaves the recorder `off` with a
  /// [ScanRecordingStartFailed]. A [stop] or [close] while this runs makes it
  /// complete with `false` and kill a writer that arrives late.
  Future<bool> start() async {
    if (_closed || _now.state != ScanRecordingState.off) return false;
    final token = ++_token;
    _outstanding = 0;
    _ended = Completer<void>();
    _status.value = const ScanRecordingStatus(
      state: ScanRecordingState.starting,
    );
    final String folder;
    try {
      folder = await _createSessionFolder();
    } on Object catch (error) {
      return _failStart(token, error);
    }
    if (token != _token) return false;
    _status.value = _now._copy(folder: folder);
    final ScanFrameWriter writer;
    try {
      writer = await _spawn(folder: folder, token: token, onAnswer: _onAnswer);
    } on Object catch (error) {
      return _failStart(token, error);
    }
    if (token != _token || _now.state != ScanRecordingState.starting) {
      writer.kill();
      return false;
    }
    _writer = writer;
    _status.value = _now._copy(state: ScanRecordingState.on);
    return true;
  }

  /// Ends the session the user's way.
  ///
  /// From `starting` it goes `off` at once and the late writer is killed. From
  /// `on` it takes no new scans, lets the outstanding ones finish, then goes
  /// `off`. In any other state it does nothing.
  void stop() {
    switch (_now.state) {
      case ScanRecordingState.starting:
        _token++;
        _finish(null);
      case ScanRecordingState.on:
        _beginStopping(null);
      case ScanRecordingState.off || ScanRecordingState.stopping:
        break;
    }
  }

  /// Offers [scan] to the session.
  ///
  /// Only an `on` session takes scans; otherwise the result is
  /// [ScanRecordResult.refused] and nothing is counted. With two scans
  /// outstanding the scan is dropped and counted. The [maxHandOffs]th
  /// hand-off ends intake, and its acknowledgement turns recording off.
  ScanRecordResult record(RecordedScan scan) {
    final writer = _writer;
    if (_now.state != ScanRecordingState.on || writer == null) {
      return ScanRecordResult.refused;
    }
    if (_outstanding >= maxOutstanding) {
      _status.value = _now._copy(dropped: _now.dropped + 1);
      return ScanRecordResult.dropped;
    }
    _outstanding++;
    final handedOff = _now.handedOff + 1;
    _status.value = _now._copy(handedOff: handedOff);
    writer.write(scan);
    if (handedOff >= maxHandOffs) {
      _beginStopping(const ScanRecordingCapReached());
    }
    return ScanRecordResult.handedOver;
  }

  /// Counts a scan that ended while recording but could not be offered, such
  /// as one whose pixel copy failed. Only an `on` session counts it.
  void drop() {
    if (_now.state != ScanRecordingState.on) return;
    _status.value = _now._copy(dropped: _now.dropped + 1);
  }

  /// Stops intake, waits up to [timeout] for outstanding scans, then kills the
  /// writer.
  ///
  /// Answers after this are ignored, and [start] is refused. Calling it again
  /// is harmless.
  Future<void> close({Duration timeout = defaultCloseTimeout}) async {
    _closed = true;
    stop();
    if (_now.state == ScanRecordingState.stopping) {
      await _ended.future.timeout(timeout, onTimeout: () {});
    }
    if (_now.state != ScanRecordingState.off) _finish(null);
    _token++;
  }

  bool _failStart(int token, Object error) {
    if (token == _token) _finish(ScanRecordingStartFailed('$error'));
    return false;
  }

  void _beginStopping(ScanRecordingStopReason? reason) {
    _status.value = _now._copy(
      state: ScanRecordingState.stopping,
      stopReason: reason,
    );
    if (_outstanding == 0) _finish(null);
  }

  void _onAnswer(ScanFrameWriterAnswer answer) {
    if (answer.token != _token) return;
    final state = _now.state;
    if (state != ScanRecordingState.on &&
        state != ScanRecordingState.stopping) {
      return;
    }
    switch (answer) {
      case ScanFrameAck():
        _outstanding--;
        _status.value = _now._copy(written: _now.written + 1);
        if (state == ScanRecordingState.stopping && _outstanding == 0) {
          _finish(null);
        }
      case ScanFrameFailure(:final error):
        // The failed scan has no line and is reported by the error; the scans
        // behind it are never written.
        _outstanding--;
        _finish(ScanRecordingWriteFailed(error));
      case ScanFrameWriterExited(:final error):
        _finish(ScanRecordingWriteFailed(error ?? 'scan frame writer exited'));
    }
  }

  /// Kills the writer and goes `off`, counting scans still outstanding as
  /// dropped. A [reason] replaces the current one; `null` keeps it.
  void _finish(ScanRecordingStopReason? reason) {
    _writer?.kill();
    _writer = null;
    _status.value = _now._copy(
      state: ScanRecordingState.off,
      dropped: _now.dropped + _outstanding,
      stopReason: reason,
    );
    _outstanding = 0;
    if (!_ended.isCompleted) _ended.complete();
  }

  Future<String> _createSessionFolder() async {
    final name = _folderName(clock());
    final sep = Platform.pathSeparator;
    var path = '$root$sep$name';
    var n = 2;
    while (true) {
      if (!await Directory(path).exists()) {
        await Directory(path).create(recursive: true);
        // Creating a directory that exists succeeds, so another session
        // starting in the same second could share it. Creating the case file
        // exclusively claims the folder: the loser moves to the next suffix.
        try {
          await File('$path$sep$scanFramesFileName').create(exclusive: true);
          return path;
        } on PathExistsException {
          // Claimed by another session; try the next suffix.
        }
      }
      path = '$root$sep$name-${n++}';
    }
  }

  static String _folderName(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    final y = time.year.toString().padLeft(4, '0');
    return '$y${two(time.month)}${two(time.day)}-'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}

Future<ScanFrameWriter> _spawnIsolateWriter({
  required String folder,
  required int token,
  required void Function(ScanFrameWriterAnswer answer) onAnswer,
}) => IsolateScanFrameWriter.spawn(
  folder: folder,
  token: token,
  onAnswer: onAnswer,
);
