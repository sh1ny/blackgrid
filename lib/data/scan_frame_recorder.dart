import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
    required this.clientWidth,
    required this.clientHeight,
    required this.kind,
    required this.outcome,
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

  /// Client area width in pixels.
  final int clientWidth;

  /// Client area height in pixels.
  final int clientHeight;

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
  final line = <String, Object?>{
    'v': 1,
    'id': scan.id,
    'image': full == null ? null : scanFullImageName(scan.id),
    'client': {'width': scan.clientWidth, 'height': scan.clientHeight},
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
