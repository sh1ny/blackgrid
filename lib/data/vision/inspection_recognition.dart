/// The inspection recognition job: finds inspection markers in a captured
/// frame and reads each one's title, inside the vision worker.
///
/// Parameters and results are small sendable value types. Nothing a result
/// holds refers to a frame, a lent view or native memory.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/title_matching.dart' show recognitionGates;
import 'inspection_geometry.dart';
import 'marker_template.dart' show markerTemplateName;
import 'vision_job.dart';
import 'vision_primitives.dart'
    show TemplatePeak, visionInterArea, visionInterCubic;
import 'vision_runtime.dart';

/// Largest crop copy an evidence entry carries, in bytes (256 KiB).
const int inspectionCropByteLimit = 256 * 1024;

/// Most correlation peaks the native scan may list before it reports overflow.
const int _peakCap = 4096;

/// Most inspections read from one full-client frame, after suppression.
const int _maxPeaks = 8;

/// Native status of `BGV_ERR_OVERFLOW`.
const int _nativeOverflow = -6;

/// Most scaled marker templates the job keeps.
const int _templateCacheSize = 4;

/// Inverted binary threshold applied to the title crop.
const int _titleThreshold = 120;

/// Which kind of frame a request carries.
enum InspectionFrameKind {
  /// A small region near the cursor: the single best marker is read.
  targeted,

  /// The whole game client: every marker is read, up to a bound.
  fullClient,
}

/// Why a request produced no result at all.
enum InspectionRejection {
  /// The scaled marker is smaller than 2 px or larger than the frame.
  scaleOutOfRange,

  /// More correlation peaks qualified than the native scan may list.
  markerPeaksOverflow,
}

/// Whether a title was read.
enum InspectionTitleStatus {
  /// The title region was non-empty and OCR ran on it.
  read,

  /// The title region was empty; no probe or OCR ran, and the text is empty.
  emptyTitleRegion,
}

/// The parameters of one recognition: the frame kind and the game client size
/// the frame was captured from, which fixes the processing scale.
final class InspectionRequest {
  /// Creates a request.
  const InspectionRequest({
    required this.kind,
    required this.clientWidth,
    required this.clientHeight,
  });

  /// The kind of frame submitted.
  final InspectionFrameKind kind;

  /// Client width in physical pixels.
  final int clientWidth;

  /// Client height in physical pixels.
  final int clientHeight;
}

/// One inspection found in a frame.
final class InspectionEvidence {
  /// Creates an evidence entry.
  const InspectionEvidence({
    required this.markerScore,
    required this.markerX,
    required this.markerY,
    required this.titleRect,
    required this.titleStatus,
    required this.text,
    required this.crop,
    required this.cropWidth,
    required this.cropHeight,
    required this.cropDownscaled,
    required this.qpcMarker,
    required this.qpcTitle,
    required this.qpcPreprocess,
    required this.qpcOcr,
  });

  /// Normalised correlation score of the marker.
  final double markerScore;

  /// Top-left x of the marker in the submitted frame.
  final int markerX;

  /// Top-left y of the marker in the submitted frame.
  final int markerY;

  /// The title region after clamping and close-button narrowing; its width or
  /// height may be zero or negative when [titleStatus] is
  /// [InspectionTitleStatus.emptyTitleRegion].
  final TitleRegion titleRect;

  /// Whether the title was read.
  final InspectionTitleStatus titleStatus;

  /// The trimmed OCR text; empty when no title was read.
  final String text;

  /// The thresholded title crop, one byte per pixel, [cropWidth] by
  /// [cropHeight]. A preview within [inspectionCropByteLimit] when
  /// [cropDownscaled]; empty when no title was read.
  final Uint8List crop;

  /// Width of [crop] in pixels.
  final int cropWidth;

  /// Height of [crop] in pixels.
  final int cropHeight;

  /// Whether [crop] is a downscaled preview of the crop OCR read.
  final bool cropDownscaled;

  /// QPC tick after the marker search.
  final int qpcMarker;

  /// QPC tick after the title region and close-button probe.
  final int qpcTitle;

  /// QPC tick after resize, grayscale and threshold.
  final int qpcPreprocess;

  /// QPC tick after OCR.
  final int qpcOcr;
}

/// The outcome of one recognition request.
sealed class InspectionRecognition {
  const InspectionRecognition({required this.kind, required this.scale});

  /// The kind of frame recognised.
  final InspectionFrameKind kind;

  /// The processing scale used.
  final double scale;
}

/// The frame was searched. An empty [evidence] list means no marker reached
/// the gate (the `noMarker` case), not a failure.
final class InspectionRecognised extends InspectionRecognition {
  /// Creates a result.
  const InspectionRecognised({
    required super.kind,
    required super.scale,
    required this.bestMarkerScore,
    required this.evidence,
  });

  /// The best marker score observed, whether or not it reached the gate.
  final double bestMarkerScore;

  /// Targeted: 0 or 1 entries. Full client: 0 to 8, in score order.
  final List<InspectionEvidence> evidence;
}

/// The frame could not be searched.
final class InspectionRejected extends InspectionRecognition {
  /// Creates a rejection.
  const InspectionRejected({
    required super.kind,
    required super.scale,
    required this.reason,
    this.bestMarkerScore,
  });

  /// Why nothing was searched or listed.
  final InspectionRejection reason;

  /// The best marker score known, or null when no match ran to completion.
  final double? bestMarkerScore;
}

/// Top-level factory for [InspectionRecognitionJob]; the worker builds its job
/// once from a function like this.
VisionJob<InspectionRequest, InspectionRecognition>
inspectionRecognitionJobFactory() => InspectionRecognitionJob();

/// Finds inspection markers and reads their titles.
///
/// The job lives as long as its worker and keeps up to four scaled marker
/// templates, evicting the oldest first.
final class InspectionRecognitionJob
    implements VisionJob<InspectionRequest, InspectionRecognition> {
  /// Creates a job. [cropByteLimit] caps the crop copy of each evidence entry;
  /// only tests lower it.
  InspectionRecognitionJob({this.cropByteLimit = inspectionCropByteLimit});

  /// The most bytes an evidence crop may hold.
  final int cropByteLimit;

  /// Scaled templates by side, in insertion order.
  final Map<int, VisionImage> _templates = {};

  @override
  InspectionRecognition run(
    VisionJobContext context,
    VisionJobInput input,
    InspectionRequest params,
  ) => input.withImage((frame) => _recognise(context, frame, params));

  InspectionRecognition _recognise(
    VisionJobContext context,
    VisionImage frame,
    InspectionRequest request,
  ) {
    final marker = context.templates[markerTemplateName];
    if (marker == null) {
      throw StateError('Vision template "$markerTemplateName" is missing.');
    }
    final scale = processingScale(request.clientWidth, request.clientHeight);
    final side = scaledTemplateSize(scale);
    if (side < 2 || side > frame.width || side > frame.height) {
      return InspectionRejected(
        kind: request.kind,
        scale: scale,
        reason: InspectionRejection.scaleOutOfRange,
      );
    }

    final gray = _value(context.toGray(frame, rgbOrder: false));
    final template = _scaledTemplate(context, marker.image, side);

    final List<PeakCandidate> found;
    final double best;
    switch (request.kind) {
      case InspectionFrameKind.targeted:
        final match = _value(context.matchTemplate(gray, template));
        best = match.score;
        found = [
          if (best >= recognitionGates.markerScore)
            PeakCandidate(x: match.x, y: match.y, score: best),
        ];
      case InspectionFrameKind.fullClient:
        final peaks = context.matchTemplatePeaks(
          gray,
          template,
          recognitionGates.markerScore,
          _peakCap,
        );
        if (peaks case VisionFailed(
          failure: VisionNativeFailure(status: _nativeOverflow),
        )) {
          return InspectionRejected(
            kind: request.kind,
            scale: scale,
            reason: InspectionRejection.markerPeaksOverflow,
          );
        }
        final listed = _value(peaks);
        found = suppressPeaks(
          [
            for (final TemplatePeak p in listed)
              PeakCandidate(x: p.x, y: p.y, score: p.score),
          ],
          side,
          side,
          maxPeaks: _maxPeaks,
        );
        // With no peak the best match is asked once, so the result still
        // reports the best score observed.
        best = listed.isEmpty
            ? _value(context.matchTemplate(gray, template)).score
            : listed.map((p) => p.score).reduce(math.max);
    }
    final qpcMarker = context.qpcNow();

    return InspectionRecognised(
      kind: request.kind,
      scale: scale,
      bestMarkerScore: best,
      evidence: List.unmodifiable([
        for (final peak in found)
          _readTitle(
            context,
            frame,
            peak,
            side: side,
            scale: scale,
            qpcMarker: qpcMarker,
          ),
      ]),
    );
  }

  /// The marker scaled to [side] pixels, from the cache when present.
  VisionImage _scaledTemplate(
    VisionJobContext context,
    VisionImage marker,
    int side,
  ) {
    final cached = _templates[side];
    if (cached != null) return cached;
    final scaled = _rescale(context, marker, side, side);
    _templates[side] = scaled;
    if (_templates.length > _templateCacheSize) {
      _templates.remove(_templates.keys.first);
    }
    return scaled;
  }

  InspectionEvidence _readTitle(
    VisionJobContext context,
    VisionImage frame,
    PeakCandidate peak, {
    required int side,
    required double scale,
    required int qpcMarker,
  }) {
    final plan = planTitleRegion(
      markerX: peak.x,
      markerY: peak.y,
      scaledWidth: side,
      scaledHeight: side,
      scale: scale,
      frameWidth: frame.width,
      frameHeight: frame.height,
    );
    InspectionEvidence empty(TitleRegion region, int qpc) => InspectionEvidence(
      markerScore: peak.score,
      markerX: peak.x,
      markerY: peak.y,
      titleRect: region,
      titleStatus: InspectionTitleStatus.emptyTitleRegion,
      text: '',
      crop: Uint8List(0),
      cropWidth: 0,
      cropHeight: 0,
      cropDownscaled: false,
      qpcMarker: qpcMarker,
      qpcTitle: qpc,
      qpcPreprocess: qpc,
      qpcOcr: qpc,
    );
    if (!plan.needsProbe) return empty(plan.unprobed, context.qpcNow());

    final closeButton = _value(
      context.findInRangeRow(
        frame,
        plan.probeRow,
        plan.probeStartX,
        closeButtonBgrLo,
        closeButtonBgrHi,
      ),
    );
    final region = plan.narrow(closeButton);
    final qpcTitle = context.qpcNow();
    if (region.isEmpty) return empty(region, qpcTitle);

    final crop = _copyRegion(frame, region);
    final factor = 2 / scale;
    final enlarged = _rescale(
      context,
      crop,
      math.max(1, (crop.width * factor).truncate()),
      math.max(1, (crop.height * factor).truncate()),
    );
    final binary = _value(
      context.thresholdBinaryInv(
        _value(context.toGray(enlarged, rgbOrder: false)),
        _titleThreshold,
        255,
      ),
    );
    final qpcPreprocess = context.qpcNow();
    final text = _value(context.recognise(binary)).text.trim();
    final qpcOcr = context.qpcNow();

    final preview = _preview(context, binary);
    return InspectionEvidence(
      markerScore: peak.score,
      markerX: peak.x,
      markerY: peak.y,
      titleRect: region,
      titleStatus: InspectionTitleStatus.read,
      text: text,
      crop: preview.image.bytes.sublist(
        0,
        preview.image.width * preview.image.height,
      ),
      cropWidth: preview.image.width,
      cropHeight: preview.image.height,
      cropDownscaled: preview.downscaled,
      qpcMarker: qpcMarker,
      qpcTitle: qpcTitle,
      qpcPreprocess: qpcPreprocess,
      qpcOcr: qpcOcr,
    );
  }

  /// [image] itself when it fits [cropByteLimit], else an area-shrunk copy.
  ({VisionImage image, bool downscaled}) _preview(
    VisionJobContext context,
    VisionImage image,
  ) {
    final pixels = image.width * image.height;
    if (pixels <= cropByteLimit) return (image: image, downscaled: false);
    final shrink = math.sqrt(cropByteLimit / pixels);
    final small = _value(
      context.resize(
        image,
        math.max(1, (image.width * shrink).floor()),
        math.max(1, (image.height * shrink).floor()),
        interp: visionInterArea,
      ),
    );
    return (image: small, downscaled: true);
  }
}

/// [image] resized to [width] by [height]: area when shrinking, cubic when
/// enlarging, and untouched at the same size.
VisionImage _rescale(
  VisionJobContext context,
  VisionImage image,
  int width,
  int height,
) {
  if (width == image.width && height == image.height) return image;
  final shrinking = width < image.width || height < image.height;
  return _value(
    context.resize(
      image,
      width,
      height,
      interp: shrinking ? visionInterArea : visionInterCubic,
    ),
  );
}

/// A tight copy of [region] of [frame], keeping the frame's channels.
VisionImage _copyRegion(VisionImage frame, TitleRegion region) {
  final channels = frame.channels;
  final rowBytes = region.width * channels;
  final bytes = Uint8List(rowBytes * region.height);
  for (var row = 0; row < region.height; row++) {
    final start = (region.y + row) * frame.stride + region.x * channels;
    bytes.setRange(row * rowBytes, (row + 1) * rowBytes, frame.bytes, start);
  }
  return VisionImage(
    bytes,
    width: region.width,
    height: region.height,
    stride: rowBytes,
    channels: channels,
  );
}

/// The value of [result], or a [VisionJobAbort] carrying its typed failure.
T _value<T>(VisionResult<T> result) => switch (result) {
  VisionOk(:final value) => value,
  VisionFailed(:final failure) => throw VisionJobAbort(failure),
};
