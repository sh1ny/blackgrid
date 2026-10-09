import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/data/vision/vision_image.dart';
import 'package:blackgrid/data/vision/vision_native.dart';
import 'package:blackgrid/data/vision/vision_primitives.dart';
import 'package:blackgrid/data/vision/vision_runtime.dart'
    show visionCoreFiles, visionExpectedAbi;
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart' show fail;

/// Layout of the native control block shared by the test isolate and the
/// worker isolate. Every slot is an `Int64`. Each counter has a single writer
/// (the worker) except the clock, which both sides may read.
abstract final class VisionControl {
  /// 1 = native operations (primitives, recognise) block synchronously.
  static const hold = 0;

  /// 1 = the library opener blocks synchronously.
  static const openHold = 1;

  /// Native operations currently executing.
  static const concurrent = 2;

  /// High-water mark of [concurrent].
  static const maxConcurrent = 3;

  /// Times the opener was entered.
  static const openCount = 4;

  /// Times an engine was disposed.
  static const engineDisposeCount = 5;

  /// 0 = operations succeed; a negative value makes every operation throw
  /// `VisionNativeError(status)`, like a native `bgv_*` failure.
  static const nativeStatus = 6;

  /// Fake QPC clock value.
  static const qpc = 7;

  /// Ticks the clock advances after each [FakeVisionClock.now] read.
  static const qpcStep = 8;

  /// Times `VisionNative.close` ran.
  static const nativeCloseCount = 9;

  /// Native operations started (held or not).
  static const operationCount = 10;

  /// Address of the call log block (separate from this block so the control
  /// block keeps its size).
  static const logAddress = 11;

  static const slots = 12;

  /// The call log block: slot 0 counts the entries, then [logCapacity]
  /// entries of [logWidth] slots, each `[op, arg0 ... arg6]`.
  static const logCapacity = 64;
  static const logWidth = 8;
  static const logSlots = 1 + logCapacity * logWidth;
}

/// Operation ids written to the call log.
abstract final class VisionOp {
  /// `[width, height, channels, rgbOrder]`
  static const toGray = 1;

  /// `[srcWidth, srcHeight, dstWidth, dstHeight, interp, channels]`
  static const resize = 2;

  /// `[width, height, thresh, maxval]`
  static const threshold = 3;

  /// `[imageWidth, imageHeight, templateWidth, templateHeight]`
  static const matchBest = 4;

  /// `[imageWidth, imageHeight, templateWidth, templateHeight, cap,
  /// thresholdBits]`; read the threshold with [VisionCall.doubleAt].
  static const peaks = 5;

  /// `[width, height, row, startX, loPacked, hiPacked, channels]`; the bounds
  /// are packed as `b | g << 8 | r << 16`.
  static const findRow = 6;

  /// `[width, height, channels]`
  static const recognise = 7;

  static const count = 8;
}

/// One native call as the fake saw it.
final class VisionCall {
  const VisionCall(this.op, this.args);

  final int op;
  final List<int> args;

  /// The argument at [index] reinterpreted as a double stored with
  /// [VisionCall.bitsOf].
  double doubleAt(int index) =>
      (ByteData(8)..setInt64(0, args[index])).getFloat64(0);

  /// The bits to log for [value].
  static int bitsOf(double value) =>
      (ByteData(8)..setFloat64(0, value)).getInt64(0);
}

/// A native failure injected at the [call]th (0-based) invocation of [op].
typedef VisionInjectedFailure = ({int op, int call, int status});

/// Scripted results of the fake native, plain data so it crosses into the
/// worker isolate. The defaults reproduce the fixed values the fake always
/// returned.
final class VisionScript {
  const VisionScript({
    this.bestScore = 0.5,
    this.bestX = 1,
    this.bestY = 2,
    this.peaks = const [TemplatePeak(1, 2, 0.9)],
    this.findRowResults = const [null],
    this.ocrTexts = const ['hello'],
    this.failures = const [],
    this.patternedThreshold = false,
  });

  /// What `matchTemplateBest` returns.
  final double bestScore;
  final int bestX;
  final int bestY;

  /// What `matchTemplatePeaks` returns.
  final List<TemplatePeak> peaks;

  /// `findInRangeRow` answers in call order; the last repeats.
  final List<int?> findRowResults;

  /// OCR texts in call order; the last repeats.
  final List<String> ocrTexts;

  /// Failures to inject; a failing call throws `VisionNativeError(status)`.
  final List<VisionInjectedFailure> failures;

  /// Whether `thresholdBinaryInv` returns [patternByte] bytes instead of zeros.
  final bool patternedThreshold;

  int? failureFor(int op, int call) {
    for (final f in failures) {
      if (f.op == op && f.call == call) return f.status;
    }
    return null;
  }
}

/// The byte at [index] of a patterned threshold output.
int patternByte(int index) => (index * 13 + 5) & 0xff;

/// Records the call, counts it per op and runs [body] as a held, counted
/// native operation, failing first when the script injects a failure.
T _scripted<T>(
  Pointer<Int64> control,
  VisionScript script,
  List<int> counts,
  int op,
  List<int> args,
  T Function(int call) body,
) {
  final log = Pointer<Int64>.fromAddress(control[VisionControl.logAddress]);
  final index = log[0];
  if (index >= VisionControl.logCapacity) {
    throw StateError('vision call log is full');
  }
  final base = 1 + index * VisionControl.logWidth;
  log[base] = op;
  for (var i = 0; i < args.length; i++) {
    log[base + 1 + i] = args[i];
  }
  log[0] = index + 1;
  final call = counts[op]++;
  return _operation(control, () {
    final status = script.failureFor(op, call);
    if (status != null) throw VisionNativeError(status);
    return body(call);
  });
}

T _lastOrAt<T>(List<T> values, int index) =>
    values[index < values.length ? index : values.length - 1];

/// The control block's owner side: allocate once, pass [address] to the worker,
/// free after the worker is gone.
final class VisionControlBlock {
  VisionControlBlock()
    : _mem = calloc<Int64>(VisionControl.slots),
      _log = calloc<Int64>(VisionControl.logSlots) {
    _mem[VisionControl.qpc] = 1000;
    _mem[VisionControl.qpcStep] = 10;
    _mem[VisionControl.logAddress] = _log.address;
  }

  final Pointer<Int64> _mem;
  final Pointer<Int64> _log;

  int get address => _mem.address;

  void free() {
    calloc.free(_mem);
    calloc.free(_log);
  }

  set held(bool value) => _mem[VisionControl.hold] = value ? 1 : 0;
  set openHeld(bool value) => _mem[VisionControl.openHold] = value ? 1 : 0;
  set nativeStatus(int value) => _mem[VisionControl.nativeStatus] = value;

  int get concurrent => _mem[VisionControl.concurrent];
  int get maxConcurrent => _mem[VisionControl.maxConcurrent];
  int get openCount => _mem[VisionControl.openCount];
  int get engineDisposeCount => _mem[VisionControl.engineDisposeCount];
  int get nativeCloseCount => _mem[VisionControl.nativeCloseCount];
  int get operationCount => _mem[VisionControl.operationCount];

  /// Every native call so far, in order.
  List<VisionCall> get calls => [
    for (var i = 0; i < _log[0]; i++)
      () {
        final base = 1 + i * VisionControl.logWidth;
        return VisionCall(_log[base], [
          for (var a = 1; a < VisionControl.logWidth; a++) _log[base + a],
        ]);
      }(),
  ];

  /// The calls of one [VisionOp].
  List<VisionCall> callsOf(int op) => [
    for (final call in calls)
      if (call.op == op) call,
  ];

  /// The clock as seen from this isolate. Reads advance it by the step.
  FakeVisionClock get clock => FakeVisionClock.fromAddress(address);
}

/// A QPC clock in shared native memory so the service and the worker read one
/// timeline. Each [now] returns the current tick and advances by the step
/// (default 10; 0 freezes the clock). Reads from two isolates at the same
/// instant are not atomic: tests that assert exact ticks read from one side.
final class FakeVisionClock {
  FakeVisionClock.fromAddress(int controlAddress)
    : _mem = Pointer<Int64>.fromAddress(controlAddress);

  final Pointer<Int64> _mem;

  int now() {
    final value = _mem[VisionControl.qpc];
    _mem[VisionControl.qpc] = value + _mem[VisionControl.qpcStep];
    return value;
  }

  /// Sets the next tick [now] returns.
  void set(int value) => _mem[VisionControl.qpc] = value;

  void setStep(int step) => _mem[VisionControl.qpcStep] = step;
}

/// Top-level so the closure captures one int and can be sent to an isolate.
VisionNativeOpener holdableVisionOpener(
  int controlAddress, [
  VisionScript script = const VisionScript(),
]) => (leptonica, tesseract, vision) {
  final control = Pointer<Int64>.fromAddress(controlAddress);
  control[VisionControl.openCount] += 1;
  _spinWhile(control, VisionControl.openHold);
  return HoldableVisionNative(controlAddress, script);
};

/// An opener that fails like a library the OS refuses to load.
VisionNative failingVisionOpener(
  String leptonica,
  String tesseract,
  String vision,
) => throw VisionLoadException(vision, 'fixture: cannot load library');

void _spinWhile(Pointer<Int64> control, int slot) {
  while (control[slot] == 1) {
    sleep(const Duration(milliseconds: 2));
  }
}

/// Runs [body] as one native operation: counted, blocking while the hold flag
/// is set, and failing with the scripted native status.
T _operation<T>(Pointer<Int64> control, T Function() body) {
  control[VisionControl.operationCount] += 1;
  final now = control[VisionControl.concurrent] + 1;
  control[VisionControl.concurrent] = now;
  if (now > control[VisionControl.maxConcurrent]) {
    control[VisionControl.maxConcurrent] = now;
  }
  try {
    _spinWhile(control, VisionControl.hold);
    final status = control[VisionControl.nativeStatus];
    if (status != 0) throw VisionNativeError(status);
    return body();
  } finally {
    control[VisionControl.concurrent] -= 1;
  }
}

/// A [VisionNative] whose operations block while the control hold flag is set.
final class HoldableVisionNative implements VisionNative {
  HoldableVisionNative(
    int controlAddress, [
    this._script = const VisionScript(),
  ]) : _control = Pointer<Int64>.fromAddress(controlAddress),
       primitives = HoldableVisionPrimitives(controlAddress, _script);

  final Pointer<Int64> _control;
  final VisionScript _script;
  late final HoldableVisionEngine _engine = HoldableVisionEngine(
    _control.address,
    _script,
  );

  @override
  final VisionPrimitives primitives;

  @override
  int get visionAbi => visionExpectedAbi;

  @override
  String get tessVersion => '5.0.0';

  @override
  VisionEngine? createEngine() => _engine;

  @override
  void close() => _control[VisionControl.nativeCloseCount] += 1;
}

/// Fake OCR engine: recognition is held and scripted like a primitive.
final class HoldableVisionEngine implements VisionEngine {
  HoldableVisionEngine(
    int controlAddress, [
    this._script = const VisionScript(),
  ]) : _control = Pointer<Int64>.fromAddress(controlAddress);

  final Pointer<Int64> _control;
  final VisionScript _script;
  final List<int> _counts = List.filled(VisionOp.count, 0);
  int _psm = 0;

  @override
  int init(String datapath, String language, int oem) => 0;

  @override
  void setPageSegMode(int psm) => _psm = psm;

  @override
  String get initLanguages => 'eng';

  @override
  int get oem => 1;

  @override
  int get pageSegMode => _psm;

  @override
  OcrText recognise(VisionImage image) => _scripted(
    _control,
    _script,
    _counts,
    VisionOp.recognise,
    [image.width, image.height, image.channels],
    (call) => OcrText(_lastOrAt(_script.ocrTexts, call), truncated: false),
  );

  @override
  void dispose() => _control[VisionControl.engineDisposeCount] += 1;
}

/// Fake primitives: each call is a held, counted, logged, scripted native
/// operation.
final class HoldableVisionPrimitives implements VisionPrimitives {
  HoldableVisionPrimitives(
    int controlAddress, [
    this._script = const VisionScript(),
  ]) : _control = Pointer<Int64>.fromAddress(controlAddress);

  final Pointer<Int64> _control;
  final VisionScript _script;
  final List<int> _counts = List.filled(VisionOp.count, 0);

  T _run<T>(int op, List<int> args, T Function(int call) body) =>
      _scripted(_control, _script, _counts, op, args, body);

  @override
  Uint8List toGray(VisionImage src, {required bool rgbOrder}) => _run(
    VisionOp.toGray,
    [src.width, src.height, src.channels, rgbOrder ? 1 : 0],
    (_) => Uint8List(src.width * src.height),
  );

  @override
  Uint8List resize(VisionImage src, int dw, int dh, int interp) => _run(
    VisionOp.resize,
    [src.width, src.height, dw, dh, interp, src.channels],
    (_) => Uint8List(dw * dh * src.channels),
  );

  @override
  Uint8List thresholdBinaryInv(VisionImage src, int thresh, int maxval) => _run(
    VisionOp.threshold,
    [src.width, src.height, thresh, maxval],
    (_) => _script.patternedThreshold
        ? Uint8List.fromList([
            for (var i = 0; i < src.width * src.height; i++) patternByte(i),
          ])
        : Uint8List(src.width * src.height),
  );

  @override
  TemplateMatch matchTemplateBest(VisionImage image, VisionImage template) =>
      _run(VisionOp.matchBest, [
        image.width,
        image.height,
        template.width,
        template.height,
      ], (_) => TemplateMatch(_script.bestScore, _script.bestX, _script.bestY));

  @override
  List<TemplatePeak> matchTemplatePeaks(
    VisionImage image,
    VisionImage template,
    double threshold,
    int cap,
  ) => _run(VisionOp.peaks, [
    image.width,
    image.height,
    template.width,
    template.height,
    cap,
    VisionCall.bitsOf(threshold),
  ], (_) => _script.peaks);

  @override
  int? findInRangeRow(
    VisionImage src,
    int row,
    int startX,
    List<int> lo,
    List<int> hi,
  ) => _run(VisionOp.findRow, [
    src.width,
    src.height,
    row,
    startX,
    lo[0] | lo[1] << 8 | lo[2] << 16,
    hi[0] | hi[1] << 8 | hi[2] << 16,
    src.channels,
  ], (call) => _lastOrAt(_script.findRowResults, call));
}

/// A runtime directory that passes `VisionRuntime.open` verification with
/// [holdableVisionOpener]: placeholder files plus a matching manifest.
/// Delete it with `deleteSync(recursive: true)`.
Directory createFakeRuntimeDirectory() {
  const core = visionCoreFiles;
  final dir = Directory.systemTemp.createTempSync('bgvisionworker');
  final root = dir.path.replaceAll('\\', '/');
  final files = <Map<String, Object>>[];
  for (final path in core) {
    final bytes = utf8.encode('content of $path');
    final file = File('$root/$path')..parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    files.add({'path': path, 'sha256': sha256.convert(bytes).toString()});
  }
  final manifest = File('$root/data/vision/runtime.manifest.json');
  manifest.parent.createSync(recursive: true);
  manifest.writeAsStringSync(
    jsonEncode({
      'format': 1,
      'abi': visionExpectedAbi,
      'engineVersion': '5.0.0',
      'files': files,
    }),
  );
  return dir;
}

/// Bounded poll for state that crosses an isolate (native memory written by
/// the worker); there is no signal to await.
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('condition not met in $timeout');
    await Future<void>.delayed(interval);
  }
}
