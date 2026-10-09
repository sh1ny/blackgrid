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

  static const slots = 12;
}

/// The control block's owner side: allocate once, pass [address] to the worker,
/// free after the worker is gone.
final class VisionControlBlock {
  VisionControlBlock() : _mem = calloc<Int64>(VisionControl.slots) {
    _mem[VisionControl.qpc] = 1000;
    _mem[VisionControl.qpcStep] = 10;
  }

  final Pointer<Int64> _mem;

  int get address => _mem.address;

  void free() => calloc.free(_mem);

  set held(bool value) => _mem[VisionControl.hold] = value ? 1 : 0;
  set openHeld(bool value) => _mem[VisionControl.openHold] = value ? 1 : 0;
  set nativeStatus(int value) => _mem[VisionControl.nativeStatus] = value;

  int get concurrent => _mem[VisionControl.concurrent];
  int get maxConcurrent => _mem[VisionControl.maxConcurrent];
  int get openCount => _mem[VisionControl.openCount];
  int get engineDisposeCount => _mem[VisionControl.engineDisposeCount];
  int get nativeCloseCount => _mem[VisionControl.nativeCloseCount];
  int get operationCount => _mem[VisionControl.operationCount];

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
VisionNativeOpener holdableVisionOpener(int controlAddress) =>
    (leptonica, tesseract, vision) {
      final control = Pointer<Int64>.fromAddress(controlAddress);
      control[VisionControl.openCount] += 1;
      _spinWhile(control, VisionControl.openHold);
      return HoldableVisionNative(controlAddress);
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
  HoldableVisionNative(int controlAddress)
    : _control = Pointer<Int64>.fromAddress(controlAddress),
      primitives = HoldableVisionPrimitives(controlAddress);

  final Pointer<Int64> _control;
  late final HoldableVisionEngine _engine = HoldableVisionEngine(
    _control.address,
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
  HoldableVisionEngine(int controlAddress)
    : _control = Pointer<Int64>.fromAddress(controlAddress);

  final Pointer<Int64> _control;
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
  OcrText recognise(VisionImage image) =>
      _operation(_control, () => const OcrText('hello', truncated: false));

  @override
  void dispose() => _control[VisionControl.engineDisposeCount] += 1;
}

/// Fake primitives: each call is a held, counted, scripted native operation.
final class HoldableVisionPrimitives implements VisionPrimitives {
  HoldableVisionPrimitives(int controlAddress)
    : _control = Pointer<Int64>.fromAddress(controlAddress);

  final Pointer<Int64> _control;

  @override
  Uint8List toGray(VisionImage src, {required bool rgbOrder}) =>
      _operation(_control, () => Uint8List(src.width * src.height));

  @override
  Uint8List resize(VisionImage src, int dw, int dh, int interp) =>
      _operation(_control, () => Uint8List(dw * dh * src.channels));

  @override
  Uint8List thresholdBinaryInv(VisionImage src, int thresh, int maxval) =>
      _operation(_control, () => Uint8List(src.width * src.height));

  @override
  TemplateMatch matchTemplateBest(VisionImage image, VisionImage template) =>
      _operation(_control, () => const TemplateMatch(0.5, 1, 2));

  @override
  List<TemplatePeak> matchTemplatePeaks(
    VisionImage image,
    VisionImage template,
    double threshold,
    int cap,
  ) => _operation(_control, () => const [TemplatePeak(1, 2, 0.9)]);

  @override
  int? findInRangeRow(
    VisionImage src,
    int row,
    int startX,
    List<int> lo,
    List<int> hi,
  ) => _operation(_control, () => null);
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
