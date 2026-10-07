import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../data/vision/vision_native.dart' show openVisionNative;
import '../data/vision/vision_runtime.dart';
import 'launch_mode.dart';
import 'output_path_guard.dart';

/// Overall time allowed for the native steps.
const Duration visionSelfCheckWatchdog = Duration(seconds: 60);

/// Report format version.
const int visionSelfCheckReportFormat = 1;

/// Sample location relative to the runtime directory.
const String visionSelfCheckSampleDirectory = 'data/vision/self_check';

/// Minimum template-match score the sample must reach.
const double visionSelfCheckMinScore = 0.99;

const String visionSelfCheckHelp = r'''
Usage: blackgrid.exe --vision-self-check <report.json>

Verifies and loads the bundled vision runtime (Tesseract, Leptonica,
blackgrid_vision.dll), runs a template match and OCR on a bundled sample,
disposes, and writes a JSON report to <report.json>. The directory of the
report must already exist.

blackgrid.exe is a GUI-subsystem app, so a shell does not wait for it. Use:

  PowerShell:
    $p = Start-Process -Wait -PassThru .\blackgrid.exe -ArgumentList '--vision-self-check','C:\temp\vision.json'; $p.ExitCode

  cmd:
    start /wait blackgrid.exe --vision-self-check C:\temp\vision.json
    echo %ERRORLEVEL%

Exit codes:
  0  pass
  1  a step failed (or the report could not be written)
  2  usage error (no report path, extra arguments, or missing report directory)
  3  timeout (a step did not return within 60 seconds)

The "result" field of the report is authoritative; the exit code mirrors it.
''';

/// One step outcome sent from the helper isolate to the main isolate.
final class SelfCheckStepResult {
  const SelfCheckStepResult({
    required this.name,
    required this.ok,
    required this.ms,
    this.failure,
    this.detail = '',
  });

  factory SelfCheckStepResult.fromJson(Map<Object?, Object?> json) =>
      SelfCheckStepResult(
        name: json['name'] as String,
        ok: json['ok'] as bool,
        ms: json['ms'] as int,
        failure: (json['failure'] as Map<Object?, Object?>?)
            ?.cast<String, Object?>(),
        detail: (json['detail'] as String?) ?? '',
      );

  final String name;
  final bool ok;
  final int ms;

  /// `{kind, message}` for a failed step.
  final Map<String, Object?>? failure;
  final String detail;

  Map<String, Object?> toJson() => {
    'name': name,
    'ok': ok,
    'ms': ms,
    if (failure != null) 'failure': failure,
    'detail': detail,
  };
}

/// What the step runner reports as it goes. Only plain data crosses isolates.
abstract interface class SelfCheckSink {
  void sendProgress(String step);

  void sendStep(SelfCheckStepResult step);

  void sendIdentity(Map<String, Object?> identity);

  void sendDone();
}

/// The message handed to the helper isolate; also its [SelfCheckSink].
final class SelfCheckRequest implements SelfCheckSink {
  SelfCheckRequest(this.port, this.runtimeDirectory);

  final SendPort port;
  final String runtimeDirectory;

  @override
  void sendProgress(String step) => port.send(['progress', step]);

  @override
  void sendStep(SelfCheckStepResult step) => port.send(['step', step.toJson()]);

  @override
  void sendIdentity(Map<String, Object?> identity) =>
      port.send(['identity', identity]);

  @override
  void sendDone() => port.send(['done']);
}

/// Entry point of the helper isolate; a top-level function so it can be
/// spawned. Injected in tests.
typedef SelfCheckWorker = void Function(SelfCheckRequest request);

/// The real worker: runs the steps against the bundle.
void visionSelfCheckWorker(SelfCheckRequest request) {
  executeSelfCheckSteps(request, runtimeDirectory: request.runtimeDirectory);
}

/// Runs the self-check and returns the process exit code. Only `main` exits.
///
/// [args] is the full argument list, `--vision-self-check <report.json>`.
Future<int> runVisionSelfCheck(
  List<String> args, {
  Duration watchdog = visionSelfCheckWatchdog,
  String? runtimeDirectory,
  SelfCheckWorker worker = visionSelfCheckWorker,
  void Function(String text)? writeUsage,
}) async {
  void usage(String problem) {
    final text = '$problem\n\n$visionSelfCheckHelp';
    if (writeUsage != null) {
      writeUsage(text);
      return;
    }
    try {
      stderr.write(text);
    } catch (_) {
      // A GUI-subsystem process may have no console.
    }
  }

  if (args.length < 2 || args.first != visionSelfCheckFlag) {
    usage('Missing report path.');
    return 2;
  }
  if (args.length > 2) {
    usage('Unexpected arguments: ${args.skip(2).join(' ')}');
    return 2;
  }
  final reportPath = args[1];
  if (reportPath.isEmpty || reportPath.startsWith('--')) {
    usage('Invalid report path: "$reportPath"');
    return 2;
  }
  final reportDirectory = File(reportPath).absolute.parent;
  if (!reportDirectory.existsSync()) {
    usage('Report directory does not exist: ${reportDirectory.path}');
    return 2;
  }

  final runtimeRoot =
      runtimeDirectory ?? File(Platform.resolvedExecutable).parent.path;
  final unsafe = unsafeOutputReason(
    reportPath,
    protectedFiles: [
      for (final path in [
        visionManifestPath,
        ...visionCoreFiles,
        'data/vision/self_check/title.gray',
        'data/vision/self_check/title.json',
      ])
        '$runtimeRoot/$path',
    ],
  );
  if (unsafe != null) {
    usage('Refusing report path: $unsafe');
    return 2;
  }
  final startedAt = DateTime.now().toUtc();
  final clock = Stopwatch()..start();

  final steps = <SelfCheckStepResult>[];
  var identity = <String, Object?>{
    'files': <Object?>[],
    'tesseractVersion': null,
    'visionAbi': null,
    'loadedModulePaths': <Object?>[],
  };
  String? lastProgress;
  final finished = Completer<String?>();
  void finish([String? error]) {
    if (!finished.isCompleted) finished.complete(error);
  }

  final messages = ReceivePort();
  final errors = ReceivePort();
  final exits = ReceivePort();
  messages.listen((Object? message) {
    if (message is! List || message.isEmpty) return;
    switch (message[0]) {
      case 'progress':
        lastProgress = message[1] as String;
      case 'step':
        steps.add(
          SelfCheckStepResult.fromJson(message[1] as Map<Object?, Object?>),
        );
      case 'identity':
        identity = (message[1] as Map<Object?, Object?>)
            .cast<String, Object?>();
      case 'done':
        finish();
    }
  });
  errors.listen((Object? error) => finish('helper isolate error: $error'));
  exits.listen((_) => finish('helper isolate exited without a result'));

  Isolate? helper;
  var timedOut = false;
  String? error;
  try {
    helper = await Isolate.spawn<SelfCheckRequest>(
      worker,
      SelfCheckRequest(messages.sendPort, runtimeRoot),
      onError: errors.sendPort,
      onExit: exits.sendPort,
      errorsAreFatal: true,
    );
    error = await finished.future.timeout(watchdog);
  } on TimeoutException {
    timedOut = true;
  } catch (e) {
    error = 'cannot start helper isolate: $e';
  } finally {
    helper?.kill(priority: Isolate.immediate);
    messages.close();
    errors.close();
    exits.close();
  }

  if (timedOut) {
    final step = lastProgress ?? 'verify';
    steps.add(
      SelfCheckStepResult(
        name: step,
        ok: false,
        ms: clock.elapsedMilliseconds,
        failure: {'kind': 'timeout', 'message': VisionTimeout(step).message},
        detail: 'step did not return within ${watchdog.inMilliseconds} ms',
      ),
    );
  } else if (error != null) {
    steps.add(
      SelfCheckStepResult(
        name: lastProgress ?? 'verify',
        ok: false,
        ms: clock.elapsedMilliseconds,
        failure: {'kind': 'helperFailed', 'message': error},
        detail: error,
      ),
    );
  }

  final pass =
      !timedOut &&
      error == null &&
      steps.isNotEmpty &&
      steps.every((step) => step.ok);
  var code = timedOut ? 3 : (pass ? 0 : 1);

  final report = <String, Object?>{
    'format': visionSelfCheckReportFormat,
    'startedAt': startedAt.toIso8601String(),
    'runtimeIdentity': identity,
    'steps': [for (final step in steps) step.toJson()],
    'result': pass ? 'pass' : 'fail',
  };
  if (!_writeReport(reportPath, report) && code != 3) {
    code = 1;
  }
  return code;
}

/// Writes `<path>.tmp` then renames it over [path], so the report is absent,
/// the previous complete one, or the new complete one.
bool _writeReport(String path, Map<String, Object?> report) {
  final temp = File('$path.tmp');
  try {
    temp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    temp.renameSync(path);
    return true;
  } catch (e) {
    try {
      stderr.writeln('Cannot write self-check report $path: $e');
    } catch (_) {}
    try {
      if (FileSystemEntity.isFileSync(temp.path)) temp.deleteSync();
    } catch (_) {}
    return false;
  }
}

/// Actual paths of the loaded bundle modules (proves bundle origin).
typedef LoadedModulePaths = List<String> Function();

const List<String> _moduleNames = [
  'blackgrid_vision.dll',
  'tesseract50.dll',
  'leptonica-1.82.0.dll',
];

/// Reads each module's path through `GetModuleHandleW` and
/// `GetModuleFileNameW`.
List<String> windowsLoadedModulePaths() {
  if (!Platform.isWindows) return const [];
  final paths = <String>[];
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getHandle = kernel32
        .lookupFunction<
          IntPtr Function(Pointer<Utf16>),
          int Function(Pointer<Utf16>)
        >('GetModuleHandleW');
    final getFileName = kernel32
        .lookupFunction<
          Uint32 Function(IntPtr, Pointer<Utf16>, Uint32),
          int Function(int, Pointer<Utf16>, int)
        >('GetModuleFileNameW');
    const capacity = 32768;
    final buffer = calloc<Uint16>(capacity).cast<Utf16>();
    try {
      for (final name in _moduleNames) {
        final wide = name.toNativeUtf16();
        try {
          final handle = getHandle(wide);
          if (handle == 0) continue;
          final length = getFileName(handle, buffer, capacity);
          if (length > 0 && length < capacity) {
            paths.add(buffer.toDartString(length: length));
          }
        } finally {
          calloc.free(wide);
        }
      }
    } finally {
      calloc.free(buffer);
    }
  } catch (_) {
    // Reported as a shorter list; module paths are evidence, not a gate.
  }
  return paths;
}

/// Runs verify, load, match, OCR and dispose, reporting through [sink]. A
/// failed step skips the later steps except dispose, which always runs.
///
/// Verification and loading are one `VisionRuntime.open` call; a failure is
/// attributed to `verify` when the bundle files are wrong and to `load`
/// otherwise.
void executeSelfCheckSteps(
  SelfCheckSink sink, {
  required String runtimeDirectory,
  VisionNativeOpener opener = openVisionNative,
  LoadedModulePaths loadedModulePaths = windowsLoadedModulePaths,
}) {
  final clock = Stopwatch()..start();
  var mark = 0;
  int lap() {
    final now = clock.elapsedMilliseconds;
    final ms = now - mark;
    mark = now;
    return ms;
  }

  var healthy = true;
  void pass(String name, String detail) => sink.sendStep(
    SelfCheckStepResult(name: name, ok: true, ms: lap(), detail: detail),
  );
  void fail(String name, String kind, String message) {
    healthy = false;
    sink.sendStep(
      SelfCheckStepResult(
        name: name,
        ok: false,
        ms: lap(),
        failure: {'kind': kind, 'message': message},
        detail: message,
      ),
    );
  }

  // Progress is sent before the call so a hang is attributed to `load`.
  sink.sendProgress('verify');
  sink.sendProgress('load');
  final runtime = VisionRuntime.open(
    runtimeDirectory: runtimeDirectory,
    opener: opener,
  );
  try {
    switch (runtime.status) {
      case VisionReady(:final identity):
        pass('verify', 'manifest and file hashes verified');
        pass('load', 'libraries opened, engine initialised');
        sink.sendIdentity({
          'files': [
            for (final file in identity.files)
              {'path': file.path, 'sha256': file.sha256},
          ],
          'tesseractVersion': identity.tesseractVersion,
          'visionAbi': identity.visionAbi,
          'loadedModulePaths': loadedModulePaths(),
        });
      case VisionUnavailable(:final failure):
        if (failure is VisionInvalidPath ||
            failure is VisionMissingFile ||
            failure is VisionHashMismatch) {
          fail('verify', _failureKind(failure), failure.message);
        } else {
          pass('verify', 'manifest and file hashes verified');
          fail('load', _failureKind(failure), failure.message);
        }
      case VisionDisposed():
        fail('load', 'disposed', 'runtime disposed during open');
    }

    _Sample? sample;
    if (healthy) {
      sink.sendProgress('match');
      lap();
      sample = _loadSample(runtimeDirectory);
      if (sample.error != null) {
        fail('match', 'sampleUnavailable', sample.error!);
      } else {
        _matchStep(runtime, sample, pass, fail);
      }
    }
    if (healthy && sample != null) {
      sink.sendProgress('ocr');
      lap();
      _ocrStep(runtime, sample, pass, fail);
    }
  } catch (error) {
    fail('match', 'unexpected', '$error');
  }

  sink.sendProgress('dispose');
  lap();
  try {
    runtime.dispose();
    pass('dispose', 'engine ended and libraries closed');
  } catch (error) {
    fail('dispose', 'disposeFailed', '$error');
  }
  sink.sendDone();
}

typedef _Pass = void Function(String name, String detail);
typedef _Fail = void Function(String name, String kind, String message);

final class _Sample {
  const _Sample.error(String this.error)
    : image = null,
      text = '',
      templateRect = null;

  const _Sample(this.image, this.text, this.templateRect) : error = null;

  final String? error;
  final VisionImage? image;
  final String text;

  /// `[x, y, width, height]`.
  final List<int>? templateRect;
}

/// Reads `title.gray` and `title.json`:
/// `{"format":1,"width":..,"height":..,"stride":..,"text":"..",
/// "template":{"x":..,"y":..,"width":..,"height":..}}`.
_Sample _loadSample(String runtimeDirectory) {
  final directory = '$runtimeDirectory/$visionSelfCheckSampleDirectory';
  try {
    final meta = jsonDecode(
      File('$directory/title.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final Uint8List bytes = File('$directory/title.gray').readAsBytesSync();
    final template = meta['template'] as Map<String, dynamic>;
    final image = VisionImage(
      bytes,
      width: meta['width'] as int,
      height: meta['height'] as int,
      stride: meta['stride'] as int,
      channels: 1,
    );
    final invalid = image.validate();
    if (invalid != null) return _Sample.error(invalid.message);
    final rect = [
      template['x'] as int,
      template['y'] as int,
      template['width'] as int,
      template['height'] as int,
    ];
    if (rect[0] < 0 ||
        rect[1] < 0 ||
        rect[2] < 1 ||
        rect[3] < 1 ||
        rect[0] + rect[2] > image.width ||
        rect[1] + rect[3] > image.height) {
      return const _Sample.error('sample template rect is outside the image');
    }
    return _Sample(image, meta['text'] as String, rect);
  } catch (error) {
    return _Sample.error('cannot read sample in $directory: $error');
  }
}

void _matchStep(VisionRuntime runtime, _Sample sample, _Pass pass, _Fail fail) {
  final image = sample.image!;
  final rect = sample.templateRect!;
  final templateWidth = rect[2];
  final templateHeight = rect[3];
  final crop = Uint8List(templateWidth * templateHeight);
  for (var row = 0; row < templateHeight; row++) {
    final start = (rect[1] + row) * image.stride + rect[0];
    crop.setRange(
      row * templateWidth,
      (row + 1) * templateWidth,
      image.bytes,
      start,
    );
  }
  final template = VisionImage(
    crop,
    width: templateWidth,
    height: templateHeight,
    stride: templateWidth,
    channels: 1,
  );
  switch (runtime.matchTemplate(image, template)) {
    case VisionFailed(:final failure):
      fail('match', _failureKind(failure), failure.message);
    case VisionOk(:final value):
      final found = '(${value.x}, ${value.y}) score ${value.score}';
      if (value.x == rect[0] &&
          value.y == rect[1] &&
          value.score >= visionSelfCheckMinScore) {
        pass('match', 'template found at $found');
      } else {
        fail(
          'match',
          'matchMismatch',
          'template expected at (${rect[0]}, ${rect[1]}) with score >= '
              '$visionSelfCheckMinScore, found $found',
        );
      }
  }
}

void _ocrStep(VisionRuntime runtime, _Sample sample, _Pass pass, _Fail fail) {
  switch (runtime.recognise(sample.image!)) {
    case VisionFailed(:final failure):
      fail('ocr', _failureKind(failure), failure.message);
    case VisionOk(:final value):
      final actual = value.text.trim();
      if (actual == sample.text.trim()) {
        pass('ocr', 'recognised "$actual"');
      } else {
        fail(
          'ocr',
          'textMismatch',
          'expected "${sample.text.trim()}", recognised "$actual"',
        );
      }
  }
}

String _failureKind(VisionFailure failure) => switch (failure) {
  VisionInvalidPath() => 'invalidPath',
  VisionMissingFile() => 'missingFile',
  VisionHashMismatch() => 'hashMismatch',
  VisionAbiMismatch() => 'abiMismatch',
  VisionLoadFailed() => 'loadFailed',
  VisionEngineInitFailed() => 'engineInitFailed',
  VisionInvalidImage() => 'invalidImage',
  VisionNativeFailure() => 'nativeFailure',
  VisionDisposedFailure() => 'disposed',
  VisionTimeout() => 'timeout',
};
