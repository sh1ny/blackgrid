/// The inspection recognition job: finds inspection markers in a captured
/// frame and reads each one's title, inside the vision worker.
///
/// Parameters and results are small sendable value types. Nothing a result
/// holds refers to a frame, a lent view or native memory.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/title_matching.dart' show recognitionGates;
import 'inspection_evidence.dart';
import 'inspection_geometry.dart';
import 'marker_template.dart' show markerTemplateName;
import 'vision_job.dart';
import 'vision_primitives.dart'
    show TemplatePeak, visionInterArea, visionInterCubic;
import 'vision_runtime.dart';

export 'inspection_evidence.dart';

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
