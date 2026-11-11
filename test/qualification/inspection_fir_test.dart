@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_native.dart';
import 'package:blackgrid/data/vision/inspection_geometry.dart';
import 'package:blackgrid/data/vision/inspection_recognition.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/data/vision/vision_primitives.dart'
    show visionInterArea, visionInterCubic;
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:blackgrid/data/vision/vision_service.dart';
import 'package:blackgrid/domain/inspection_context.dart' show FirState;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'support/inspection_fir.dart';

const _manifestPath = 'test/fixtures/vision/fir/manifest.json';
const _privateSkip =
    'Requires the twelve private found-in-raid JPGs and their expected hashes.';
const _limit = Duration(seconds: 60);

// Owned images never use capture or a frame registry. This platform exposes
// only the clock required by the vision worker.
final class _ClockOnly implements CapturePlatform {
  @override
  int qpcNow() => DateTime.now().microsecondsSinceEpoch;
  @override
  int qpcFrequency() => 1000000;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Offline qualification has no capture API');
}

CapturePlatform _clockPlatform() => _ClockOnly();
FrameRegistry _noFrames() => throw UnsupportedError('No captured frames');

bool _gameNotRunningConfirmed() {
  if (!Platform.isWindows) return false;
  try {
    final result = Process.runSync('tasklist', [
      '/FI',
      'IMAGENAME eq EscapeFromTarkov.exe',
      '/NH',
      '/FO',
      'CSV',
    ]);
    return result.exitCode == 0 &&
        !(result.stdout as String).toLowerCase().contains(
          'escapefromtarkov.exe',
        );
  } on ProcessException {
    return false;
  }
}

String _sourcePath(FirManifest manifest, FirFixtureFrame frame) =>
    '${manifest.privateInputRoot}/${frame.file}';

// Check every present input even when another is missing: a hash disagreement
// must fail rather than being masked by the private-input skip.
({List<String> missing, List<String> mismatches}) _preflight(
  FirManifest manifest,
) {
  final missing = <String>[];
  final mismatches = <String>[];
  final checks = checkFirInputs(manifest, (frame) {
    final file = File(_sourcePath(manifest, frame));
    return file.existsSync() ? file.readAsBytesSync() : null;
  });
  for (final check in checks) {
    final frame = check.frame;
    final identity = check.identity;
    final path = _sourcePath(manifest, frame);
    if (identity.status == FirSourceStatus.missingHash) {
      missing.add('$path: expected SHA-256 unavailable');
      if (identity.actualHash == null) missing.add('$path: source unavailable');
    } else if (identity.status == FirSourceStatus.missingSource) {
      missing.add('$path: source unavailable');
    } else if (identity.status == FirSourceStatus.hashMismatch) {
      mismatches.add(
        '$path: expected ${frame.expectedHash}, got ${identity.actualHash}',
      );
    }
  }
  return (missing: missing, mismatches: mismatches);
}

T _value<T>(VisionResult<T> result) => switch (result) {
  VisionOk<T>(:final value) => value,
  VisionFailed<T>(:final failure) => throw StateError(failure.message),
};

VisionImage _crop(
  VisionImage source,
  int left,
  int top,
  int width,
  int height,
) {
  final rowBytes = width * source.channels;
  final bytes = Uint8List(rowBytes * height);
  for (var y = 0; y < height; y++) {
    final start = (top + y) * source.stride + left * source.channels;
    bytes.setRange(y * rowBytes, (y + 1) * rowBytes, source.bytes, start);
  }
  return VisionImage(
    bytes,
    width: width,
    height: height,
    stride: rowBytes,
    channels: source.channels,
  );
}

// The derived cases use the production FIR helper in a real vision worker,
// with the same native gray conversion, resize and NCC primitives as the job.
// This also permits a top clip where the title marker itself lies outside the
// image; the full production job cannot find an off-frame marker.
final class _ProbeRequest {
  const _ProbeRequest(this.markerX, this.markerY, this.scale);
  final int markerX;
  final int markerY;
  final double scale;
}

final class _ProbeJob
    implements VisionJob<_ProbeRequest, InspectionFirReading> {
  @override
  InspectionFirReading run(
    VisionJobContext context,
    VisionJobInput input,
    _ProbeRequest request,
  ) => input.withImage((frame) {
    final gray = _value(context.toGray(frame));
    final template = context.templates[firTemplateName]!.image;
    return readInspectionFir(
      frame: frame,
      gray: gray,
      markerX: request.markerX,
      markerY: request.markerY,
      scale: request.scale,
      match: (region, side) {
        final scaled = side == template.width
            ? template
            : _value(
                context.resize(
                  template,
                  side,
                  side,
                  interp: side < template.width
                      ? visionInterArea
                      : visionInterCubic,
                ),
              );
        if (!scaled.bytes.any((byte) => byte != scaled.bytes.first)) {
          return null;
        }
        final search = _crop(
          gray,
          region.x,
          region.y,
          region.width,
          region.height,
        );
        return _value(context.matchTemplate(search, scaled));
      },
    );
  });
}

VisionJob<_ProbeRequest, InspectionFirReading> _probeFactory() => _ProbeJob();

Future<R> _submit<P, R>(
  VisionService<P, R> service,
  VisionImage frame,
  P request,
) async {
  final answer = await service.submit(frame, request).timeout(_limit);
  if (answer is! VisionDelivered<R>) {
    fail('Vision worker did not deliver: $answer');
  }
  return answer.result;
}

InspectionEvidence _nearest(InspectionRecognised result, int x, int y) {
  if (result.evidence.isEmpty) fail('No marker found near ($x, $y)');
  final sorted = [...result.evidence]
    ..sort((a, b) {
      final da = (a.markerX - x).abs() + (a.markerY - y).abs();
      final db = (b.markerX - x).abs() + (b.markerY - y).abs();
      return da.compareTo(db);
    });
  final found = sorted.first;
  expect((found.markerX - x).abs(), lessThanOrEqualTo(4), reason: 'marker x');
  expect((found.markerY - y).abs(), lessThanOrEqualTo(4), reason: 'marker y');
  return found;
}

void _record(
  String caseName,
  FirFixtureFrame source,
  InspectionFirReading reading, {
  String? expected,
}) {
  // Evidence is printed, never written by the runner.
  // ignore: avoid_print
  print(
    jsonEncode({
      'case': caseName,
      'source': source.file,
      'sourceSha256': source.expectedHash,
      'expected': expected,
      'actual': reading.value.name,
      'reason': reading.reason.name,
      'nativeScore': reading.score,
      'readableNegativeAdmitted':
          reading.reason == InspectionFirReason.iconAbsent,
    }),
  );
}

Future<void> _derived(
  VisionService<_ProbeRequest, InspectionFirReading> probe,
  VisionImage original,
  FirFixtureFrame source,
) async {
  final scale = processingScale(source.clientWidth, source.clientHeight);
  final mx = source.markerX - source.capturedLeft;
  final my = source.markerY - source.capturedTop;
  final region = planInspectionFirRegion(
    markerX: mx,
    markerY: my,
    scale: scale,
  );
  final cases = <String, (int, int, int, int)>{
    'clip-left': (
      region.x + 1,
      0,
      original.width - region.x - 1,
      original.height,
    ),
    'clip-top': (
      0,
      region.y + 1,
      original.width,
      original.height - region.y - 1,
    ),
    'clip-right': (0, 0, region.x + region.width - 1, original.height),
    'clip-bottom': (0, 0, original.width, region.y + region.height - 1),
  };
  for (final entry in cases.entries) {
    final (left, top, width, height) = entry.value;
    final reading = await _submit(
      probe,
      _crop(original, left, top, width, height),
      _ProbeRequest(mx - left, my - top, scale),
    );
    _record(entry.key, source, reading, expected: 'unknown');
    expect(reading.reason, InspectionFirReason.cornerCutOff, reason: entry.key);
    expect(reading.value, FirState.unknown, reason: entry.key);
  }
  for (final blackoutWidth in [12, 16]) {
    final altered = VisionImage(
      Uint8List.fromList(original.bytes),
      width: original.width,
      height: original.height,
      stride: original.stride,
      channels: 4,
    );
    for (var y = 735; y < 756; y++) {
      for (var x = 1202; x < 1202 + blackoutWidth; x++) {
        final i =
            (y - source.capturedTop) * altered.stride +
            (x - source.capturedLeft) * 4;
        altered.bytes[i] = 0;
        altered.bytes[i + 1] = 0;
        altered.bytes[i + 2] = 0;
      }
    }
    final reading = await _submit(probe, altered, _ProbeRequest(mx, my, scale));
    _record(
      'partial-check-$blackoutWidth',
      source,
      reading,
      expected: 'unknown',
    );
    expect(
      reading.value,
      FirState.unknown,
      reason: 'partial check $blackoutWidth',
    );
    expect(reading.reason, InspectionFirReason.cornerUnreadable);
    expect(reading.score, isNotNull);
    expect(reading.score!, lessThanOrEqualTo(0.60));
  }
}

Future<void> _translatedCascade(
  VisionService<InspectionRequest, InspectionRecognition> service,
  VisionImage original,
  FirFixtureFrame source,
) async {
  // Translate a saved inspection patch within a synthetic 1080p client. This
  // demonstrates coverage, not another observed game layout.
  const newX = 562;
  const newY = 400;
  final sourceX = source.markerX - source.capturedLeft - 16;
  final sourceY = source.markerY - source.capturedTop - 4;
  const patchWidth = 520;
  const patchHeight = 340;
  final patch = _crop(original, sourceX, sourceY, patchWidth, patchHeight);
  final pixels = Uint8List(1920 * 1080 * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 20;
    pixels[i + 1] = 20;
    pixels[i + 2] = 20;
    pixels[i + 3] = 255;
  }
  for (var y = 0; y < patchHeight; y++) {
    final offset = ((newY - 4 + y) * 1920 + newX - 16) * 4;
    pixels.setRange(
      offset,
      offset + patch.stride,
      patch.bytes,
      y * patch.stride,
    );
  }
  final client = VisionImage(
    pixels,
    width: 1920,
    height: 1080,
    stride: 1920 * 4,
    channels: 4,
  );
  final band = _crop(client, 520, 0, 1140, 940);
  final result = await _submit(
    service,
    band,
    const InspectionRequest(
      kind: InspectionFrameKind.targeted,
      clientWidth: 1920,
      clientHeight: 1080,
    ),
  );
  expect(result, isA<InspectionRecognised>());
  final evidence = _nearest(result as InspectionRecognised, newX - 520, newY);
  final corner = planInspectionFirRegion(
    markerX: newX,
    markerY: newY,
    scale: 1,
  );
  expect(corner.y, greaterThan(600)); // The former 1080p band's lower edge.
  expect(corner.y + corner.height, lessThanOrEqualTo(940));
  _record(
    'synthetic-cascade-translation',
    source,
    evidence.fir,
    expected: 'yes',
  );
  expect(evidence.fir.value, FirState.yes);
}

void main() {
  final manifest = parseFirManifest(File(_manifestPath).readAsStringSync());
  final preflight = _preflight(manifest);
  if (preflight.missing.isNotEmpty) {
    // ignore: avoid_print
    print('FIR matrix unverified: ${preflight.missing.join('; ')}');
  }
  final skip = preflight.missing.isNotEmpty && preflight.mismatches.isEmpty
      ? _privateSkip
      : false;

  test(
    'qualification prerequisites are present and game absence confirmed',
    () {
      final bundle = Platform.environment['BLACKGRID_RELEASE_BUNDLE'];
      expect(
        bundle,
        isNotNull,
        reason: 'A built Release bundle is required, not a skip.',
      );
      expect(bundle, isNotEmpty);
      expect(
        Directory(bundle!).existsSync(),
        isTrue,
        reason: 'Release bundle must exist.',
      );
      expect(
        _gameNotRunningConfirmed(),
        isTrue,
        reason: 'Escape from Tarkov must be confirmed absent before native runtime use.',
      );
    },
  );

  test(
    'twelve owner pictures match frozen FIR labels',
    () async {
      expect(
        preflight.mismatches,
        isEmpty,
        reason: 'A mismatched source is a failure.',
      );
      expect(
        preflight.missing,
        isEmpty,
        reason: 'Missing inputs cannot complete the matrix.',
      );
      final bundleEnv = Platform.environment['BLACKGRID_RELEASE_BUNDLE'];
      expect(bundleEnv, isNotNull);
      expect(
        _gameNotRunningConfirmed(),
        isTrue,
        reason: 'Game absence must be confirmed before native runtime use.',
      );
      final bundle = Directory(bundleEnv!).resolveSymbolicLinksSync();
      final loaded = loadInspectionTemplates(bundle);
      if (loaded is! InspectionTemplatesLoaded) {
        fail('Inspection templates unavailable: $loaded');
      }
      final service = VisionService<InspectionRequest, InspectionRecognition>(
        runtimeDirectory: bundle,
        jobFactory: inspectionRecognitionJobFactory,
        templates: loaded.templates,
        platformFactory: _clockPlatform,
        registryFactory: _noFrames,
        deadline: _limit,
      );
      final probe = VisionService<_ProbeRequest, InspectionFirReading>(
        runtimeDirectory: bundle,
        jobFactory: _probeFactory,
        templates: loaded.templates,
        platformFactory: _clockPlatform,
        registryFactory: _noFrames,
        deadline: _limit,
      );
      try {
        final start = await service.start().timeout(_limit);
        expect(start, isNull, reason: start?.message);
        final probeStart = await probe.start().timeout(_limit);
        expect(probeStart, isNull, reason: probeStart?.message);
        for (final source in manifest.frames) {
          final bytes = File(_sourcePath(manifest, source)).readAsBytesSync();
          final identity = verifyFirSource(source, bytes);
          expect(
            identity.status,
            FirSourceStatus.verified,
            reason: source.file,
          );
          final decoded = image.decodeJpg(bytes);
          if (decoded == null) fail('Cannot decode ${source.file}');
          final captured = normalizeFirImage(source, decoded);
          final result = await _submit(
            service,
            captured.image,
            InspectionRequest(
              kind: InspectionFrameKind.fullClient,
              clientWidth: captured.clientWidth,
              clientHeight: captured.clientHeight,
            ),
          );
          expect(result, isA<InspectionRecognised>(), reason: source.file);
          final evidence = _nearest(
            result as InspectionRecognised,
            source.markerX - captured.left,
            source.markerY - captured.top,
          );
          final expected = source.expectedFir == 'yes'
              ? FirState.yes
              : FirState.no;
          _record(
            'owner-picture',
            source,
            evidence.fir,
            expected: source.expectedFir,
          );
          expect(evidence.fir.value, expected, reason: source.file);
          expect(
            evidence.fir.reason,
            expected == FirState.yes
                ? InspectionFirReason.iconFound
                : InspectionFirReason.iconAbsent,
            reason: source.file,
          );
          if (source.file == 'afak_fir_yes_no_medal_3440x1440.jpg') {
            await _derived(probe, captured.image, source);
          }
          if (source.file == 'm4a1_fir_yes_with_medal_cascade_1920x1080.jpg') {
            await _translatedCascade(service, captured.image, source);
          }
        }
      } finally {
        final probeClose = await probe.close();
        final serviceClose = await service.close();
        if (probe.workerRunning) await probe.workerExit;
        if (service.workerRunning) await service.workerExit;
        expect(probeClose, VisionCloseResult.closed);
        expect(serviceClose, VisionCloseResult.closed);
      }
    },
    skip: skip,
    timeout: Timeout.none,
  );
}
