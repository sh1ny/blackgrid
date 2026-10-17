import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/vision/inspection_geometry.dart';
import 'package:blackgrid/data/vision/inspection_recognition.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/data/vision/vision_primitives.dart'
    show TemplatePeak, visionInterArea, visionInterCubic;
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:blackgrid/data/vision/vision_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../capture/support/fake_capture_platform.dart';
import 'support/clock_capture_platform.dart';
import 'support/holdable_vision_native.dart';
import 'support/shared_frame_registry.dart';

/// The .82 marker gate as the native single-precision value.
final double gate = (Float32List(1)..[0] = 0.82)[0];

const int frameWidth = 200;
const int frameHeight = 40;

/// 1080p client: processing scale 1, a 16 px scaled marker.
const InspectionRequest targeted = InspectionRequest(
  kind: InspectionFrameKind.targeted,
  clientWidth: 1920,
  clientHeight: 1080,
);
const InspectionRequest fullClient = InspectionRequest(
  kind: InspectionFrameKind.fullClient,
  clientWidth: 1920,
  clientHeight: 1080,
);

/// Top-level so it can be sent to the worker: a job whose crop cap is far
/// below 256 KiB, so an ordinary crop is "oversized" without a large frame.
VisionJob<InspectionRequest, InspectionRecognition> smallCropJob() =>
    InspectionRecognitionJob(cropByteLimit: 256);

VisionTemplate markerTemplate() => VisionTemplate(
  markerTemplateName,
  VisionImage(
    Uint8List.fromList([for (var i = 0; i < 28 * 28; i++) (i * 37) & 0xff]),
    width: 28,
    height: 28,
    stride: 28,
    channels: 1,
  ),
);

VisionImage frameImage({int width = frameWidth, int height = frameHeight}) =>
    VisionImage(
      Uint8List(width * height * 4),
      width: width,
      height: height,
      stride: width * 4,
      channels: 4,
    );

CaptureFrameMetadata frameMetadata() => CaptureFrameMetadata(
  width: frameWidth,
  height: frameHeight,
  stride: frameWidth * 4,
  desktopLeft: 0,
  desktopTop: 0,
  requested: CaptureRect(0, 0, frameWidth, frameHeight),
  captured: CaptureRect(0, 0, frameWidth, frameHeight),
  clipped: false,
  clientWidth: 1920,
  clientHeight: 1080,
  dpi: 96,
  hwnd: 1,
  pid: 2,
  tid: 3,
  exeName: 'EscapeFromTarkov.exe',
  qpcBefore: 10,
  qpcAfter: 20,
  capturedAtUtc: DateTime.utc(2026, 10, 9),
  requestId: 1,
);

typedef Answer = VisionAnswer<InspectionRecognition>;

/// A real [VisionService] running the real job in a worker over the scripted
/// fake native.
final class Rig {
  Rig({
    VisionScript script = const VisionScript(),
    VisionJobFactory<InspectionRequest, InspectionRecognition> jobFactory =
        inspectionRecognitionJobFactory,
    bool withTemplate = true,
  }) : control = VisionControlBlock(),
       directory = createFakeRuntimeDirectory(),
       frames = FakeFrameRegistry.create() {
    service = VisionService<InspectionRequest, InspectionRecognition>(
      runtimeDirectory: directory.path,
      jobFactory: jobFactory,
      templates: [if (withTemplate) markerTemplate()],
      opener: holdableVisionOpener(control.address, script),
      platformFactory: clockPlatformFactory(control.address),
      registryFactory: sharedFrameRegistryFactory(frames.address),
      qpcNow: control.clock.now,
    );
  }

  final VisionControlBlock control;
  final Directory directory;
  final FakeFrameRegistry frames;
  late final VisionService<InspectionRequest, InspectionRecognition> service;

  Future<Answer> run(
    InspectionRequest request, {
    int width = frameWidth,
    int height = frameHeight,
  }) => service.submit(frameImage(width: width, height: height), request);

  /// The recognition of a delivered answer; fails the test otherwise.
  Future<InspectionRecognition> recognition(
    InspectionRequest request, {
    int width = frameWidth,
    int height = frameHeight,
  }) async {
    final answer = await run(request, width: width, height: height);
    expect(answer, isA<VisionDelivered<InspectionRecognition>>());
    return (answer as VisionDelivered<InspectionRecognition>).result;
  }

  Future<void> dispose() async {
    await service.close();
    expect(frames.liveCount, 0, reason: 'live frames at teardown');
    control.free();
    directory.deleteSync(recursive: true);
  }
}

Rig newRig({
  VisionScript script = const VisionScript(),
  VisionJobFactory<InspectionRequest, InspectionRecognition> jobFactory =
      inspectionRecognitionJobFactory,
  bool withTemplate = true,
}) {
  final rig = Rig(
    script: script,
    jobFactory: jobFactory,
    withTemplate: withTemplate,
  );
  addTearDown(rig.dispose);
  return rig;
}

InspectionRecognised recognised(InspectionRecognition result) {
  expect(result, isA<InspectionRecognised>());
  return result as InspectionRecognised;
}

/// `b | g << 8 | r << 16`, how the fake logs the colour bounds.
int packed(List<int> bounds) => bounds[0] | bounds[1] << 8 | bounds[2] << 16;

void main() {
  test('template under 2px or larger than frame rejects scaleOutOfRange '
      'without matching', () async {
    // A 192x108 client scales the 28 px template to 1 px; a 7680x4320 client
    // scales it to 64 px, taller than the 40 px frame.
    for (final (width, height) in [(192, 108), (7680, 4320)]) {
      for (final kind in InspectionFrameKind.values) {
        final rig = newRig();
        final request = InspectionRequest(
          kind: kind,
          clientWidth: width,
          clientHeight: height,
        );

        final result = await rig.recognition(request);

        expect(
          result,
          isA<InspectionRejected>()
              .having(
                (r) => r.reason,
                'reason',
                InspectionRejection.scaleOutOfRange,
              )
              .having((r) => r.kind, 'kind', kind)
              .having((r) => r.scale, 'scale', processingScale(width, height))
              .having((r) => r.bestMarkerScore, 'bestMarkerScore', isNull),
          reason: '$kind ${width}x$height',
        );
        expect(rig.control.operationCount, 0, reason: 'no native call at all');
      }
    }
  });

  test('best score 0.8199 yields no evidence and no OCR call', () async {
    final rig = newRig(script: const VisionScript(bestScore: 0.8199));

    final result = recognised(await rig.recognition(targeted));

    expect(result.kind, InspectionFrameKind.targeted);
    expect(result.bestMarkerScore, 0.8199);
    expect(result.evidence, isEmpty);
    expect(rig.control.callsOf(VisionOp.matchBest), hasLength(1));
    expect(rig.control.callsOf(VisionOp.recognise), isEmpty);
    expect(rig.control.callsOf(VisionOp.findRow), isEmpty);
  });

  test('best score exactly 0.82 runs title extraction', () async {
    // The single-precision gate value is the real boundary; the decimal 0.82
    // is just above it.
    for (final score in [gate, 0.82]) {
      final rig = newRig(
        script: VisionScript(
          bestScore: score,
          bestX: 40,
          bestY: 12,
          ocrTexts: const ['  SALEWA FIRST AID KIT \n'],
        ),
      );

      final result = recognised(await rig.recognition(targeted));

      expect(result.bestMarkerScore, score);
      expect(result.evidence, hasLength(1), reason: '$score');
      final evidence = result.evidence.single;
      expect(evidence.markerScore, score);
      expect(evidence.markerX, 40);
      expect(evidence.markerY, 12);
      expect(evidence.titleStatus, InspectionTitleStatus.read);
      expect(evidence.text, 'SALEWA FIRST AID KIT');
      expect(rig.control.callsOf(VisionOp.recognise), hasLength(1));
    }
  });

  test('targeted extraction runs the specified stages with the specified '
      'arguments', () async {
    final rig = newRig(
      script: const VisionScript(
        bestScore: 0.9,
        bestX: 40,
        bestY: 12,
        findRowResults: [130],
      ),
    );

    final result = recognised(await rig.recognition(targeted));

    // Marker 16 px at (40, 12): title x 59, probe row 12 + 8, close button at
    // x 130 ends the title 64 px before it: width 130 - 64 - 59 = 7.
    final evidence = result.evidence.single;
    expect(
      evidence.titleRect,
      const TitleRegion(x: 59, y: 12, width: 7, height: 17),
    );
    expect(result.scale, 1.0);

    final calls = rig.control.calls;
    expect(calls.map((c) => c.op), [
      VisionOp.toGray,
      VisionOp.resize,
      VisionOp.matchBest,
      VisionOp.findRow,
      VisionOp.resize,
      VisionOp.toGray,
      VisionOp.threshold,
      VisionOp.recognise,
    ]);
    // The BGRX frame is converted with BGR weights.
    expect(calls[0].args.take(4), [frameWidth, frameHeight, 4, 0]);
    // 28 -> 16: area. The match runs on the 16 px gray template.
    expect(calls[1].args.take(6), [28, 28, 16, 16, visionInterArea, 1]);
    expect(calls[2].args.take(4), [frameWidth, frameHeight, 16, 16]);
    // The probe runs on the colour frame with the three BGR bounds.
    expect(calls[3].args.take(7), [
      frameWidth,
      frameHeight,
      20,
      59,
      packed(closeButtonBgrLo),
      packed(closeButtonBgrHi),
      4,
    ]);
    // 7x17 crop, x2 enlarged with cubic interpolation, then gray, then
    // inverted threshold at 120.
    expect(calls[4].args.take(6), [7, 17, 14, 34, visionInterCubic, 4]);
    expect(calls[5].args.take(3), [14, 34, 4]);
    expect(calls[6].args.take(4), [14, 34, 120, 255]);
    expect(calls[7].args.take(3), [14, 34, 1]);
    expect(evidence.cropWidth, 14);
    expect(evidence.cropHeight, 34);
  });

  test(
    'two separated peaks give two evidence entries in score order',
    () async {
      final rig = newRig(
        script: const VisionScript(
          // Raster order: the lower score comes first.
          peaks: [TemplatePeak(20, 10, 0.9), TemplatePeak(100, 10, 0.95)],
          ocrTexts: ['HIGH', 'LOW'],
        ),
      );

      final result = recognised(await rig.recognition(fullClient));

      expect(result.kind, InspectionFrameKind.fullClient);
      expect(result.bestMarkerScore, 0.95);
      expect(
        result.evidence.map((e) => (e.markerX, e.markerY, e.markerScore)),
        [(100, 10, 0.95), (20, 10, 0.9)],
      );
      // Each entry has its own title read, in score order.
      expect(result.evidence.map((e) => e.text), ['HIGH', 'LOW']);
      final peaks = rig.control.callsOf(VisionOp.peaks).single;
      expect(peaks.args.take(5), [frameWidth, frameHeight, 16, 16, 4096]);
      expect(peaks.doubleAt(5), gate);
      expect(
        rig.control.callsOf(VisionOp.matchBest),
        isEmpty,
        reason: 'peaks already give the best score',
      );
    },
  );

  test('overlapping peaks are suppressed and at most 8 inspections are read', () async {
    final rig = newRig(
      script: VisionScript(
        // Ten markers 17 px apart do not suppress each other; a lower peak one
        // pixel from the first does.
        peaks: [
          for (var i = 0; i < 10; i++)
            TemplatePeak(i * 17, 10, 0.99 - i * 0.01),
          const TemplatePeak(1, 10, 0.83),
        ],
      ),
    );

    final result = recognised(await rig.recognition(fullClient));

    expect(result.evidence, hasLength(8));
    expect(result.evidence.map((e) => e.markerX), [
      for (var i = 0; i < 8; i++) i * 17,
    ]);
    expect(rig.control.callsOf(VisionOp.recognise), hasLength(8));
  });

  test('no peak at .82 gives empty evidence with best score', () async {
    final rig = newRig(script: const VisionScript(peaks: [], bestScore: 0.6));

    final result = recognised(await rig.recognition(fullClient));

    expect(result.evidence, isEmpty);
    // With no peak the best match is asked once, for the score observed.
    expect(result.bestMarkerScore, 0.6);
    expect(rig.control.callsOf(VisionOp.peaks), hasLength(1));
    expect(rig.control.callsOf(VisionOp.matchBest), hasLength(1));
    expect(rig.control.callsOf(VisionOp.recognise), isEmpty);
  });

  test(
    'peak overflow is a typed rejection, any other native failure aborts',
    () async {
      final overflow = newRig(
        script: const VisionScript(
          failures: [(op: VisionOp.peaks, call: 0, status: -6)],
        ),
      );
      expect(
        await overflow.recognition(fullClient),
        isA<InspectionRejected>()
            .having(
              (r) => r.reason,
              'reason',
              InspectionRejection.markerPeaksOverflow,
            )
            .having((r) => r.kind, 'kind', InspectionFrameKind.fullClient)
            .having((r) => r.scale, 'scale', 1.0)
            .having((r) => r.bestMarkerScore, 'bestMarkerScore', isNull),
      );

      for (final (request, op) in [
        (fullClient, VisionOp.peaks),
        (targeted, VisionOp.matchBest),
      ]) {
        final rig = newRig(
          script: VisionScript(failures: [(op: op, call: 0, status: -4)]),
        );
        final answer = await rig.run(request);
        expect(
          answer,
          isA<VisionFailureAnswer<InspectionRecognition>>().having(
            (a) => a.failure,
            'failure',
            isA<VisionNativeFailure>().having((f) => f.status, 'status', -4),
          ),
          reason: 'op $op',
        );
      }
    },
  );

  test('empty or off-frame title region is emptyTitleRegion with no probe or '
      'OCR', () async {
    // Marker at x 190: the title would start at 190 + 19 = 209, past the
    // 200 px frame edge.
    final offFrame = newRig(
      script: const VisionScript(bestScore: 0.9, bestX: 190, bestY: 12),
    );
    final off = recognised(await offFrame.recognition(targeted))
        .evidence
        .single;
    expect(off.titleStatus, InspectionTitleStatus.emptyTitleRegion);
    expect(off.text, isEmpty);
    expect(off.crop, isEmpty);
    expect(off.markerX, 190);
    expect(offFrame.control.callsOf(VisionOp.findRow), isEmpty);
    expect(offFrame.control.callsOf(VisionOp.recognise), isEmpty);

    // A close button left of the title start narrows it to nothing: the probe
    // runs, OCR does not, and the request still succeeds.
    final narrowed = newRig(
      script: const VisionScript(
        bestScore: 0.9,
        bestX: 40,
        bestY: 12,
        findRowResults: [100],
      ),
    );
    final empty = recognised(await narrowed.recognition(targeted))
        .evidence
        .single;
    expect(empty.titleStatus, InspectionTitleStatus.emptyTitleRegion);
    expect(empty.text, isEmpty);
    expect(narrowed.control.callsOf(VisionOp.findRow), hasLength(1));
    expect(narrowed.control.callsOf(VisionOp.recognise), isEmpty);

    // Next to a readable entry in the same request: it is still read.
    final mixed = newRig(
      script: const VisionScript(
        peaks: [TemplatePeak(190, 10, 0.99), TemplatePeak(20, 10, 0.9)],
        ocrTexts: ['READ'],
      ),
    );
    final result = recognised(await mixed.recognition(fullClient));
    expect(result.evidence.map((e) => e.titleStatus), [
      InspectionTitleStatus.emptyTitleRegion,
      InspectionTitleStatus.read,
    ]);
    expect(result.evidence.map((e) => e.text), ['', 'READ']);
  });

  test('native OCR failure aborts with the typed failure', () async {
    final rig = newRig(
      script: const VisionScript(
        bestScore: 0.9,
        bestX: 40,
        bestY: 12,
        failures: [(op: VisionOp.recognise, call: 0, status: -3)],
      ),
    );

    final answer = await rig.run(targeted);

    expect(
      answer,
      isA<VisionFailureAnswer<InspectionRecognition>>().having(
        (a) => a.failure,
        'failure',
        isA<VisionNativeFailure>().having((f) => f.status, 'status', -3),
      ),
    );

    // A failure on the second of two titles discards the whole request.
    final partial = newRig(
      script: const VisionScript(
        peaks: [TemplatePeak(20, 10, 0.9), TemplatePeak(100, 10, 0.95)],
        failures: [(op: VisionOp.recognise, call: 1, status: -3)],
      ),
    );
    expect(
      await partial.run(fullClient),
      isA<VisionFailureAnswer<InspectionRecognition>>(),
    );
    expect(partial.control.callsOf(VisionOp.recognise), hasLength(2));
  });

  test('a missing marker template is a job failure, not a result', () async {
    final rig = newRig(withTemplate: false);

    final answer = await rig.run(targeted);

    expect(
      answer,
      isA<VisionJobFailed<InspectionRecognition>>().having(
        (a) => a.description,
        'description',
        contains(markerTemplateName),
      ),
    );
    expect(rig.control.operationCount, 0);
  });

  test(
    'evidence crop and text survive frame release and isolate transfer',
    () async {
      final rig = newRig(
        script: const VisionScript(
          bestScore: 0.9,
          bestX: 40,
          bestY: 12,
          ocrTexts: ['SALEWA FIRST AID KIT'],
          patternedThreshold: true,
        ),
      );
      final frame = CaptureFrame(
        rig.frames.createFrame(frameWidth, frameHeight),
        frameMetadata(),
        rig.frames,
      );

      final answer = await rig.service.submitFrame(frame, targeted);

      // The worker released the frame before it answered.
      expect(frame.isReleased, isTrue);
      expect(rig.frames.liveCount, 0);
      final result = recognised(
        (answer as VisionDelivered<InspectionRecognition>).result,
      );
      final evidence = result.evidence.single;
      expect(evidence.text, 'SALEWA FIRST AID KIT');
      expect(evidence.cropWidth * evidence.cropHeight, evidence.crop.length);
      expect(evidence.crop, isNotEmpty);
      // The crop holds the leftmost columns of each patterned threshold row.
      final [sourceWidth, ...] = rig.control
          .callsOf(VisionOp.threshold)
          .single
          .args;
      expect(evidence.crop, [
        for (var y = 0; y < evidence.cropHeight; y++)
          for (var x = 0; x < evidence.cropWidth; x++)
            patternByte(y * sourceWidth + x),
      ]);
      // Plain owned bytes, not a window onto a larger or foreign buffer.
      expect(evidence.crop.buffer.lengthInBytes, evidence.crop.length);
      expect(evidence.cropDownscaled, isFalse);
    },
  );

  test('crop above 256 KiB is downscaled and flagged while OCR used full '
      'size', () async {
    expect(inspectionCropByteLimit, 256 * 1024);
    const script = VisionScript(
      bestScore: 0.9,
      bestX: 40,
      bestY: 12,
      patternedThreshold: true,
    );

    // The 141x17 title crop is enlarged to 282x34. The pattern's rightmost
    // black pixel is in column 269, so OCR reads 278x34 = 9452 bytes. Under
    // the production cap that is kept whole.
    final whole = newRig(script: script);
    final kept = recognised(await whole.recognition(targeted)).evidence.single;
    expect(kept.cropDownscaled, isFalse);
    expect((kept.cropWidth, kept.cropHeight), (278, 34));

    // Under a 256 byte cap it is over the limit.
    final capped = newRig(script: script, jobFactory: smallCropJob);
    final evidence = recognised(await capped.recognition(targeted))
        .evidence
        .single;

    expect(evidence.cropDownscaled, isTrue);
    expect(evidence.cropWidth * evidence.cropHeight, lessThanOrEqualTo(256));
    expect(evidence.crop.length, evidence.cropWidth * evidence.cropHeight);
    // OCR read the full-size crop, and the preview was an area shrink of it.
    expect(capped.control.callsOf(VisionOp.recognise).single.args.take(3), [
      278,
      34,
      1,
    ]);
    final shrink = capped.control.callsOf(VisionOp.resize).last;
    expect(shrink.args.take(6), [
      278,
      34,
      evidence.cropWidth,
      evidence.cropHeight,
      visionInterArea,
      1,
    ]);
  });

  test('stage timestamps are non-decreasing', () async {
    final rig = newRig(
      script: const VisionScript(
        peaks: [TemplatePeak(190, 10, 0.99), TemplatePeak(20, 10, 0.9)],
      ),
    );

    final answer =
        await rig.run(fullClient) as VisionDelivered<InspectionRecognition>;

    final result = recognised(answer.result);
    expect(result.evidence, hasLength(2));
    // The marker search is shared by every entry; each entry then runs its
    // own title stages, one after the other.
    var previous = answer.startedQpc;
    for (final e in result.evidence) {
      expect(e.qpcMarker, greaterThanOrEqualTo(answer.startedQpc));
      var stage = e.qpcMarker;
      for (final stamp in [e.qpcTitle, e.qpcPreprocess, e.qpcOcr]) {
        expect(stamp, greaterThanOrEqualTo(stage));
        stage = stamp;
      }
      expect(e.qpcTitle, greaterThanOrEqualTo(previous));
      previous = e.qpcOcr;
    }
    expect(previous, lessThanOrEqualTo(answer.finishedQpc));
  });

  group('title margin', () {
    /// The title the fake thresholded for [threshold], bounded to [width]
    /// columns as tightly packed bytes.
    Uint8List expectedTitle(VisionCall threshold, int? ink, int width) {
      final [sourceWidth, height, ...] = threshold.args;
      final source = titleInkImage(sourceWidth, height, ink);
      return Uint8List.fromList([
        for (var y = 0; y < height; y++)
          ...source.sublist(y * sourceWidth, y * sourceWidth + width),
      ]);
    }

    /// Checks the single OCR call read exactly [expected], [width] wide.
    void expectOcrRead(VisionCall ocr, Uint8List expected, int width) {
      final height = expected.length ~/ width;
      expect(ocr.args.take(5), [
        width,
        height,
        1,
        width,
        pixelChecksum(expected, width, height, width),
      ]);
    }

    test('OCR receives the bounded title image', () async {
      for (final request in [targeted, fullClient]) {
        final rig = newRig(
          script: const VisionScript(
            bestScore: 0.9,
            bestX: 40,
            bestY: 12,
            peaks: [TemplatePeak(40, 12, 0.9)],
            titleInk: [100],
          ),
        );

        final evidence = recognised(await rig.recognition(request))
            .evidence
            .single;

        final threshold = rig.control.callsOf(VisionOp.threshold).single;
        // The 141x17 title enlarges to 282x34; ink ends at x 100, so OCR
        // reads columns 0 through 108.
        expect(threshold.args.take(2), [282, 34], reason: '${request.kind}');
        final expected = expectedTitle(threshold, 100, 109);
        expectOcrRead(
          rig.control.callsOf(VisionOp.recognise).single,
          expected,
          109,
        );
        expect((evidence.cropWidth, evidence.cropHeight), (109, 34));
        expect(evidence.crop, expected);
      }
    });

    test('OCR receives a boundary title unchanged', () async {
      // Ink in the last column, and ink closer to it than the margin.
      for (final ink in [281, 276]) {
        final rig = newRig(
          script: VisionScript(
            bestScore: 0.9,
            bestX: 40,
            bestY: 12,
            titleInk: [ink],
          ),
        );

        final evidence = recognised(await rig.recognition(targeted))
            .evidence
            .single;

        final threshold = rig.control.callsOf(VisionOp.threshold).single;
        final expected = expectedTitle(threshold, ink, 282);
        expectOcrRead(
          rig.control.callsOf(VisionOp.recognise).single,
          expected,
          282,
        );
        expect((evidence.cropWidth, evidence.cropHeight), (282, 34));
        expect(evidence.crop, expected, reason: 'ink $ink');
      }
    });

    test('blank title skips OCR and retains white preview', () async {
      final rig = newRig(
        script: const VisionScript(
          bestScore: 0.9,
          bestX: 40,
          bestY: 12,
          titleInk: [null],
          ocrTexts: ['INVENTED'],
        ),
      );

      final answer =
          await rig.run(targeted) as VisionDelivered<InspectionRecognition>;

      final evidence = recognised(answer.result).evidence.single;
      expect(evidence.titleStatus, InspectionTitleStatus.read);
      expect(evidence.text, isEmpty);
      expect(rig.control.callsOf(VisionOp.recognise), isEmpty);
      expect((evidence.cropWidth, evidence.cropHeight), (282, 34));
      expect(evidence.crop, everyElement(255));
      expect(evidence.crop, hasLength(282 * 34));
      expect(evidence.cropDownscaled, isFalse);
      var stage = answer.startedQpc;
      for (final stamp in [
        evidence.qpcMarker,
        evidence.qpcTitle,
        evidence.qpcPreprocess,
        evidence.qpcOcr,
        answer.finishedQpc,
      ]) {
        expect(stamp, greaterThanOrEqualTo(stage));
        stage = stamp;
      }
    });

    test('blank title is followed by a readable second peak', () async {
      final rig = newRig(
        script: const VisionScript(
          peaks: [TemplatePeak(20, 10, 0.95), TemplatePeak(100, 10, 0.9)],
          titleInk: [null, 10],
          ocrTexts: ['SECOND'],
        ),
      );

      final result = recognised(await rig.recognition(fullClient));

      expect(result.evidence.map((e) => e.titleStatus), [
        InspectionTitleStatus.read,
        InspectionTitleStatus.read,
      ]);
      expect(result.evidence.map((e) => e.text), ['', 'SECOND']);
      final thresholds = rig.control.callsOf(VisionOp.threshold);
      expect(thresholds, hasLength(2));
      // Each peak is bounded on its own: the second is not widened or
      // narrowed by the first.
      final expected = expectedTitle(thresholds[1], 10, 19);
      expectOcrRead(
        rig.control.callsOf(VisionOp.recognise).single,
        expected,
        19,
      );
      expect(result.evidence[1].crop, expected);
      expect(result.evidence[0].crop, everyElement(255));
    });

    test(
      'preview equals bounded OCR input and titleRect retains source geometry',
      () async {
        final rig = newRig(
          script: const VisionScript(
            bestScore: 0.9,
            bestX: 40,
            bestY: 12,
            titleInk: [50],
            ocrTexts: ['SHORT'],
          ),
        );
        final frame = CaptureFrame(
          rig.frames.createFrame(frameWidth, frameHeight),
          frameMetadata(),
          rig.frames,
        );

        final answer = await rig.service.submitFrame(frame, targeted);

        expect(frame.isReleased, isTrue);
        expect(rig.frames.liveCount, 0);
        final evidence = recognised(
          (answer as VisionDelivered<InspectionRecognition>).result,
        ).evidence.single;
        expect(
          evidence.titleRect,
          const TitleRegion(x: 59, y: 12, width: 141, height: 17),
        );
        final threshold = rig.control.callsOf(VisionOp.threshold).single;
        final expected = expectedTitle(threshold, 50, 59);
        expectOcrRead(
          rig.control.callsOf(VisionOp.recognise).single,
          expected,
          59,
        );
        expect(evidence.text, 'SHORT');
        expect((evidence.cropWidth, evidence.cropHeight), (59, 34));
        expect(evidence.cropDownscaled, isFalse);
        expect(evidence.crop, expected);
        // Plain owned bytes, not a window onto the wider threshold output.
        expect(evidence.crop.buffer.lengthInBytes, evidence.crop.length);
      },
    );
  });

  test('scaled template is cached for four sizes, oldest evicted', () async {
    // Scales 1, 1.5, 2, 2.5, 3 give 16, 24, 32, 40 and 48 px templates. The
    // best score stays under the gate, so only template resizes happen.
    final rig = newRig();
    InspectionRequest at(double scale) => InspectionRequest(
      kind: InspectionFrameKind.targeted,
      clientWidth: (1920 * scale).round(),
      clientHeight: (1080 * scale).round(),
    );
    int templateResizes() => rig.control
        .callsOf(VisionOp.resize)
        .where((c) => c.args[0] == 28 && c.args[1] == 28)
        .length;

    for (final scale in [1.0, 1.5, 2.0, 2.5, 3.0]) {
      await rig.recognition(at(scale), height: 60);
    }
    expect(templateResizes(), 5);
    final resizes = rig.control.callsOf(VisionOp.resize);
    expect(resizes.map((c) => c.args[2]), [16, 24, 32, 40, 48]);
    // Shrinking (below 28 px) uses area interpolation, enlarging cubic.
    expect(resizes.map((c) => c.args[4]), [
      visionInterArea,
      visionInterArea,
      visionInterCubic,
      visionInterCubic,
      visionInterCubic,
    ]);

    await rig.recognition(at(3.0), height: 60);
    expect(templateResizes(), 5, reason: 'newest size is cached');

    await rig.recognition(at(1.0), height: 60);
    expect(templateResizes(), 6, reason: 'oldest size was evicted');
  });

  test(
    'a template already at the scaled size is used without a resize',
    () async {
      expect(scaledTemplateSize(1.75), 28);
      final rig = newRig();

      await rig.recognition(
        const InspectionRequest(
          kind: InspectionFrameKind.targeted,
          clientWidth: 3360,
          clientHeight: 1890,
        ),
      );

      expect(rig.control.callsOf(VisionOp.resize), isEmpty);
      expect(rig.control.callsOf(VisionOp.matchBest).single.args.take(4), [
        frameWidth,
        frameHeight,
        28,
        28,
      ]);
    },
  );

  test('job runs through VisionService over a fake native without loading a '
      'library', () async {
    final rig = newRig(
      script: const VisionScript(bestScore: 0.9, bestX: 40, bestY: 12),
    );

    final answer = await rig.run(targeted);

    expect(answer, isA<VisionDelivered<InspectionRecognition>>());
    expect(
      (answer as VisionDelivered<InspectionRecognition>).result,
      isA<InspectionRecognised>(),
    );
    // The fake opener ran once, in the worker; no real library was opened.
    expect(rig.control.openCount, 1);
    expect(rig.service.state, VisionServiceState.ready);
    expect(Isolate.current.debugName, isNot('bgv_worker'));
    expect(rig.control.operationCount, greaterThan(0));
  });
}
