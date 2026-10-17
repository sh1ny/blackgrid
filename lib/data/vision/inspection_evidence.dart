/// The sendable value types of inspection recognition: the request, the
/// evidence entries and the recognition results.
///
/// They hold no frame, lent view or native memory, so they cross isolates and
/// can be used by code that must not depend on the vision service or job.
library;

import 'dart:typed_data';

import 'inspection_geometry.dart';

/// Largest crop copy an evidence entry carries, in bytes (256 KiB).
const int inspectionCropByteLimit = 256 * 1024;

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
  /// The title region was non-empty and its thresholded crop was read: OCR
  /// ran on it, or was skipped because the crop held no foreground pixel and
  /// the text is empty.
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

  /// The title region after clamping and close-button narrowing, in frame
  /// pixels; its width or height may be zero or negative when [titleStatus]
  /// is [InspectionTitleStatus.emptyTitleRegion].
  ///
  /// This is the extraction rectangle, not the size of [crop], which is
  /// rescaled and may be narrowed to its rendered text.
  final TitleRegion titleRect;

  /// Whether the title was read.
  final InspectionTitleStatus titleStatus;

  /// The trimmed OCR text; empty when no title was read or the crop held no
  /// foreground pixel.
  final String text;

  /// The thresholded title crop OCR read, one byte per pixel, [cropWidth] by
  /// [cropHeight]: the normalised crop with its blank right margin bounded,
  /// or the whole blank crop when OCR was skipped for lack of foreground. A
  /// preview within [inspectionCropByteLimit] when [cropDownscaled]; empty
  /// when no title was read.
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
