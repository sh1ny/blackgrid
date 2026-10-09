/// The UI-facing values of live scanning, and (in later task groups) the
/// coordinator that produces them.
///
/// This file is the one `lib/application` or `lib/ui` source that may
/// reference the capture and vision services (ADR-0013). Every capture,
/// trigger, vision and marker-template failure is mapped here into a
/// [ScanFailure], so no other file needs those types.
library;

import 'dart:typed_data';

import '../data/capture/capture_failure.dart';
import '../data/vision/inspection_evidence.dart';
import '../data/vision/marker_template.dart';
import '../data/vision/vision_job.dart';
import '../data/vision/vision_service.dart';
import '../domain/catalog.dart';
import '../domain/title_matching.dart';

/// Where live scanning is in its activation life.
enum LiveScanState {
  /// Live scanning is off; nothing is installed or running.
  off,

  /// The marker template, vision worker and hook are being started.
  starting,

  /// The hook is installed and scans run on mouse release.
  ready,

  /// The pipeline is being torn down.
  stopping,

  /// Live scanning cannot run; see [LiveScanStatus.reason].
  unavailable,
}

/// The activation state with the text the Scanner shows beside it.
final class LiveScanStatus {
  /// Creates a status.
  const LiveScanStatus(this.state, {this.reason, this.stopWarning});

  /// Live scanning is off with nothing to report.
  static const LiveScanStatus off = LiveScanStatus(LiveScanState.off);

  /// The activation state.
  final LiveScanState state;

  /// Why the state is [LiveScanState.unavailable], else null.
  final String? reason;

  /// A warning kept after a stop that did not complete (for example the hook
  /// thread did not stop), else null.
  final String? stopWarning;

  @override
  bool operator ==(Object other) =>
      other is LiveScanStatus &&
      other.state == state &&
      other.reason == reason &&
      other.stopWarning == stopWarning;

  @override
  int get hashCode => Object.hash(state, reason, stopWarning);
}

/// Which part of a scan is running.
enum ScanPhase {
  /// No scan is running.
  idle,

  /// The targeted pass is running.
  targeted,

  /// The full-client fallback pass is running.
  fallback,
}

/// A pass of a scan, used to name the pass a result came from.
enum ScanPass {
  /// The targeted pass.
  targeted,

  /// The full-client fallback pass.
  fallback,
}

/// Why a scan or a live scan activation could not deliver. The names are the
/// reasons used in the spec and in the timing log.
enum ScanFailureCode {
  /// The window is gone.
  targetGone,

  /// Another window became foreground.
  targetNotForeground,

  /// The window is minimised.
  targetMinimised,

  /// The window is not the game.
  wrongTarget,

  /// The region is outside the client area.
  roiOutsideClient,

  /// The captured rectangle exceeds the size bounds.
  captureTooLarge,

  /// The target changed during capture.
  targetChanged,

  /// Every captured byte was zero.
  blankCapture,

  /// Four capture frames were already live.
  frameBudgetExceeded,

  /// The native capture failed.
  captureFailed,

  /// Another capture was in progress.
  captureBusy,

  /// The capture missed its deadline.
  captureTimeout,

  /// The capture service is closed.
  captureClosed,

  /// The capture service cannot run.
  captureUnavailable,

  /// The capture service did not shut down within its drain.
  shutdownIncomplete,

  /// The mouse hook is already installed.
  alreadyStarted,

  /// The OS refused the mouse hook.
  triggerUnavailable,

  /// The mouse hook thread did not stop in time.
  stopTimedOut,

  /// A newer vision request replaced this one.
  visionSuperseded,

  /// The vision request was invalidated.
  visionInvalidated,

  /// The vision request missed its deadline.
  visionTimeout,

  /// The vision service was closed.
  visionClosed,

  /// The vision worker cannot run jobs.
  visionUnavailable,

  /// The request violated the vision buffer contract.
  visionInvalidInput,

  /// A vision template is not valid.
  visionInvalidTemplate,

  /// The recognition job threw.
  visionJobFailed,

  /// The recognition job ended with a runtime failure.
  visionFailed,

  /// The vision runtime could not be opened.
  visionRuntimeUnavailable,

  /// The vision worker could not start for another reason.
  visionStartFailed,

  /// The marker template file is missing or does not match the manifest.
  markerTemplateUnavailable,

  /// The marker template files do not describe a usable template.
  markerTemplateInvalid,
}

/// A failure the UI can show: a [code] and a readable [message].
final class ScanFailure {
  /// Creates a failure.
  const ScanFailure(this.code, this.message);

  /// The machine-readable reason.
  final ScanFailureCode code;

  /// A human-readable description.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ScanFailure && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => '${code.name}: $message';
}

/// Maps a capture failure to its [ScanFailure].
ScanFailure scanFailureFromCapture(CaptureFailure failure) {
  final code = switch (failure) {
    TargetGone() => ScanFailureCode.targetGone,
    TargetNotForeground() => ScanFailureCode.targetNotForeground,
    TargetMinimised() => ScanFailureCode.targetMinimised,
    WrongTarget() => ScanFailureCode.wrongTarget,
    RoiOutsideClient() => ScanFailureCode.roiOutsideClient,
    CaptureTooLarge() => ScanFailureCode.captureTooLarge,
    TargetChanged() => ScanFailureCode.targetChanged,
    BlankCapture() => ScanFailureCode.blankCapture,
    FrameBudgetExceeded() => ScanFailureCode.frameBudgetExceeded,
    CaptureFailed() => ScanFailureCode.captureFailed,
    CaptureBusy() => ScanFailureCode.captureBusy,
    CaptureTimeout() => ScanFailureCode.captureTimeout,
    CaptureClosed() => ScanFailureCode.captureClosed,
    CaptureUnavailable() => ScanFailureCode.captureUnavailable,
    ShutdownIncomplete() => ScanFailureCode.shutdownIncomplete,
  };
  return ScanFailure(code, failure.message);
}

/// Maps a trigger (hook) failure to its [ScanFailure].
ScanFailure scanFailureFromTrigger(TriggerFailure failure) {
  final code = switch (failure) {
    AlreadyStarted() => ScanFailureCode.alreadyStarted,
    TriggerUnavailable() => ScanFailureCode.triggerUnavailable,
    StopTimedOut() => ScanFailureCode.stopTimedOut,
  };
  return ScanFailure(code, failure.message);
}

/// Maps a vision answer to the failure it represents, or null when the job
/// delivered a result.
ScanFailure? scanFailureFromVision<R>(VisionAnswer<R> answer) =>
    switch (answer) {
      VisionDelivered() => null,
      VisionSuperseded() => const ScanFailure(
        ScanFailureCode.visionSuperseded,
        'The vision request was replaced by a newer one.',
      ),
      VisionInvalidated() => const ScanFailure(
        ScanFailureCode.visionInvalidated,
        'The vision request was invalidated.',
      ),
      VisionDeadlineExceeded() => const ScanFailure(
        ScanFailureCode.visionTimeout,
        'Vision did not answer within its deadline.',
      ),
      VisionClosed() => const ScanFailure(
        ScanFailureCode.visionClosed,
        'The vision service is closed.',
      ),
      VisionUnavailableAnswer(:final reason) => ScanFailure(
        ScanFailureCode.visionUnavailable,
        'Vision is unavailable: $reason',
      ),
      VisionInvalidInput(:final detail) => ScanFailure(
        ScanFailureCode.visionInvalidInput,
        detail.isEmpty
            ? 'The vision input was invalid.'
            : 'The vision input was invalid: $detail',
      ),
      VisionInvalidTemplate(:final name) => ScanFailure(
        ScanFailureCode.visionInvalidTemplate,
        'Vision template "$name" is invalid.',
      ),
      VisionJobFailed(:final description) => ScanFailure(
        ScanFailureCode.visionJobFailed,
        'The recognition job failed: $description',
      ),
      VisionFailureAnswer(:final failure) => ScanFailure(
        ScanFailureCode.visionFailed,
        failure.message,
      ),
    };

/// Maps a vision start failure to its [ScanFailure].
ScanFailure scanFailureFromVisionStart(VisionStartFailure failure) {
  final code = switch (failure) {
    VisionRuntimeStartFailure() => ScanFailureCode.visionRuntimeUnavailable,
    VisionInvalidTemplateStart() => ScanFailureCode.visionInvalidTemplate,
    VisionWorkerStartFailure() => ScanFailureCode.visionStartFailed,
  };
  return ScanFailure(code, failure.message);
}

/// Maps a marker template load to its failure, or null when it loaded.
ScanFailure? scanFailureFromMarkerTemplate(MarkerTemplateResult result) =>
    switch (result) {
      MarkerTemplateLoaded() => null,
      MarkerTemplateUnavailable(:final failure) => ScanFailure(
        ScanFailureCode.markerTemplateUnavailable,
        failure.message,
      ),
      MarkerTemplateInvalid(:final message) => ScanFailure(
        ScanFailureCode.markerTemplateInvalid,
        message,
      ),
    };

/// QPC stamps of one pass, on the trigger and capture clock. A stage the pass
/// did not reach is null, never zero.
final class PassTimeline {
  /// Creates a pass timeline.
  const PassTimeline({
    this.captureRequested,
    this.acquireStart,
    this.acquireEnd,
    this.captureAnswered,
    this.visionSubmitted,
    this.jobStarted,
    this.marker,
    this.title,
    this.preprocess,
    this.ocr,
    this.jobFinished,
    this.matchStarted,
    this.matchFinished,
  });

  /// The coordinator asked the capture service for a frame.
  final int? captureRequested;

  /// The frame's pixel acquisition began (`qpcBefore`).
  final int? acquireStart;

  /// The frame's pixel acquisition ended (`qpcAfter`).
  final int? acquireEnd;

  /// The capture service answered the coordinator.
  final int? captureAnswered;

  /// The frame was submitted to the vision service.
  final int? visionSubmitted;

  /// The vision worker started the job.
  final int? jobStarted;

  /// After the marker search, from this pass's own evidence.
  final int? marker;

  /// After the title region and close-button probe.
  final int? title;

  /// After resize, grayscale and threshold.
  final int? preprocess;

  /// After OCR.
  final int? ocr;

  /// The vision worker finished the job.
  final int? jobFinished;

  /// Matching started.
  final int? matchStarted;

  /// Matching ended.
  final int? matchFinished;

  /// A copy with the given stamps replaced.
  PassTimeline copyWith({
    int? captureRequested,
    int? acquireStart,
    int? acquireEnd,
    int? captureAnswered,
    int? visionSubmitted,
    int? jobStarted,
    int? jobFinished,
    int? matchStarted,
    int? matchFinished,
  }) => PassTimeline(
    captureRequested: captureRequested ?? this.captureRequested,
    acquireStart: acquireStart ?? this.acquireStart,
    acquireEnd: acquireEnd ?? this.acquireEnd,
    captureAnswered: captureAnswered ?? this.captureAnswered,
    visionSubmitted: visionSubmitted ?? this.visionSubmitted,
    jobStarted: jobStarted ?? this.jobStarted,
    marker: marker,
    title: title,
    preprocess: preprocess,
    ocr: ocr,
    jobFinished: jobFinished ?? this.jobFinished,
    matchStarted: matchStarted ?? this.matchStarted,
    matchFinished: matchFinished ?? this.matchFinished,
  );

  /// A copy whose marker, title, preprocess and OCR stamps come from
  /// [recognition]'s own evidence: [winner] when it is one of its entries,
  /// else its first entry. A pass with no entry has none of these stamps.
  PassTimeline withEvidenceStamps(
    InspectionRecognition recognition, {
    InspectionEvidence? winner,
  }) {
    final entry = switch (recognition) {
      InspectionRecognised(:final evidence) => _pickEntry(evidence, winner),
      InspectionRejected() => null,
    };
    return PassTimeline(
      captureRequested: captureRequested,
      acquireStart: acquireStart,
      acquireEnd: acquireEnd,
      captureAnswered: captureAnswered,
      visionSubmitted: visionSubmitted,
      jobStarted: jobStarted,
      marker: entry?.qpcMarker,
      title: entry?.qpcTitle,
      preprocess: entry?.qpcPreprocess,
      ocr: entry?.qpcOcr,
      jobFinished: jobFinished,
      matchStarted: matchStarted,
      matchFinished: matchFinished,
    );
  }

  /// The reached stages by log key, in stage order.
  Map<String, int> get _stamps => {
    'captureRequested': ?captureRequested,
    'acquireStart': ?acquireStart,
    'acquireEnd': ?acquireEnd,
    'captureAnswered': ?captureAnswered,
    'visionSubmitted': ?visionSubmitted,
    'jobStarted': ?jobStarted,
    'marker': ?marker,
    'title': ?title,
    'preprocess': ?preprocess,
    'ocr': ?ocr,
    'jobFinished': ?jobFinished,
    'matchStarted': ?matchStarted,
    'matchFinished': ?matchFinished,
  };
}

/// The entry of [evidence] equal to [winner] (same marker position, score and
/// text), else the first entry, else null.
InspectionEvidence? _pickEntry(
  List<InspectionEvidence> evidence,
  InspectionEvidence? winner,
) {
  if (evidence.isEmpty) return null;
  if (winner != null) {
    for (final entry in evidence) {
      if (entry.markerX == winner.markerX &&
          entry.markerY == winner.markerY &&
          entry.markerScore == winner.markerScore &&
          entry.text == winner.text) {
        return entry;
      }
    }
  }
  return evidence.first;
}

/// QPC stamps of a whole scan. Converted to milliseconds once, when the scan
/// is logged or shown.
final class ScanTimeline {
  /// Creates a timeline.
  const ScanTimeline({
    required this.trigger,
    this.published,
    this.targeted,
    this.fallback,
  });

  /// The trigger's own QPC tick; the origin of every millisecond offset.
  final int trigger;

  /// When the scan was published, or null if it never was.
  final int? published;

  /// The targeted pass, or null when it never started.
  final PassTimeline? targeted;

  /// The fallback pass, or null when it never started.
  final PassTimeline? fallback;

  /// A copy with the given values replaced.
  ScanTimeline copyWith({
    int? published,
    PassTimeline? targeted,
    PassTimeline? fallback,
  }) => ScanTimeline(
    trigger: trigger,
    published: published ?? this.published,
    targeted: targeted ?? this.targeted,
    fallback: fallback ?? this.fallback,
  );

  /// Milliseconds from [trigger] to [stamp] at [qpcFrequency] ticks per
  /// second, rounded to 0.1 ms.
  double msFromTrigger(int stamp, int qpcFrequency) =>
      ((stamp - trigger) * 10000 / qpcFrequency).round() / 10;
}

/// What one pass found: its recognition, or why it produced none.
final class PassReport {
  /// Creates a pass report. A pass that ran has a [recognition], a [failure],
  /// or neither when it was abandoned (a superseded scan).
  const PassReport({this.recognition, this.failure});

  /// The pass's recognition result, with crop bytes only on the latest report.
  final InspectionRecognition? recognition;

  /// The capture or vision failure that ended the pass, if any.
  final ScanFailure? failure;
}

/// Why a scan was rejected: the ranked outcome's reason, or a pipeline reason.
enum ScanRejectReason {
  /// No marker evidence in either pass.
  noMarker,

  /// The matcher itself failed.
  matcherFailed,

  /// See [TitleRejectReason.emptyCatalog].
  emptyCatalog,

  /// See [TitleRejectReason.titleTooShort].
  titleTooShort,

  /// See [TitleRejectReason.uiChrome].
  uiChrome,

  /// See [TitleRejectReason.belowSimilarity].
  belowSimilarity,

  /// See [TitleRejectReason.ambiguous].
  ambiguous,

  /// See [TitleRejectReason.catalogModeMismatch].
  catalogModeMismatch,

  /// No catalog index was available to match against (pipeline reason).
  catalogUnavailable;

  /// The reason that mirrors the outcome reason [reason].
  static ScanRejectReason fromOutcome(OutcomeRejectReason reason) =>
      switch (reason) {
        OutcomeRejectReason.noMarker => noMarker,
        OutcomeRejectReason.matcherFailed => matcherFailed,
        OutcomeRejectReason.emptyCatalog => emptyCatalog,
        OutcomeRejectReason.titleTooShort => titleTooShort,
        OutcomeRejectReason.uiChrome => uiChrome,
        OutcomeRejectReason.belowSimilarity => belowSimilarity,
        OutcomeRejectReason.ambiguous => ambiguous,
        OutcomeRejectReason.catalogModeMismatch => catalogModeMismatch,
      };
}

/// How a scan ended.
sealed class ScanEnd {
  const ScanEnd();

  /// The `end` value in the log line.
  String get logName;
}

/// A title was accepted as catalog item [itemId].
final class ScanAccepted extends ScanEnd {
  /// Creates an acceptance.
  const ScanAccepted({required this.itemId, required this.outcome});

  /// The accepted catalog ID.
  final String itemId;

  /// The ranked outcome, with its winning evidence.
  final OutcomeAccepted<InspectionEvidence> outcome;

  @override
  String get logName => 'accepted';
}

/// Nothing was accepted. The best candidate is in [outcome], labelled not
/// accepted.
final class ScanRejected extends ScanEnd {
  /// Creates a rejection.
  const ScanRejected({
    required this.reason,
    this.outcome,
    this.fallbackFailure,
  });

  /// Why nothing was accepted.
  final ScanRejectReason reason;

  /// The ranked outcome, or null for a pipeline rejection that had none
  /// (`catalogUnavailable`).
  final OutcomeRejected<InspectionEvidence>? outcome;

  /// The fallback pass's failure when the fallback could not run to a result
  /// after a targeted rejection.
  final ScanFailure? fallbackFailure;

  @override
  String get logName => 'rejected';
}

/// The scan could not complete.
final class ScanFailed extends ScanEnd {
  /// Creates a failure end.
  const ScanFailed(this.failure, {this.targetedFailure});

  /// The failure that ended the scan (the fallback's when both passes failed).
  final ScanFailure failure;

  /// The targeted pass's failure when the fallback also failed.
  final ScanFailure? targetedFailure;

  @override
  String get logName => 'failed';
}

/// The scan was replaced by a newer trigger, a stop or a dispose.
///
/// Only the timing log uses this end. A superseded scan is logged but never
/// published, so no UI state ever holds a report with this end.
final class ScanSuperseded extends ScanEnd {
  /// Creates a superseded end.
  const ScanSuperseded();

  @override
  String get logName => 'superseded';
}

/// Everything known about one finished scan.
///
/// Crop bytes are kept only on the latest published report; call
/// [withoutCrops] to store a summary in the recent list.
final class ScanReport {
  /// Creates a report.
  const ScanReport({
    required this.id,
    required this.utc,
    required this.end,
    required this.timeline,
    required this.droppedTriggers,
    required this.supersededTriggers,
    this.winningPass,
    this.targeted,
    this.fallback,
    this.catalogMode,
    this.catalogRevision,
  });

  /// Identifies the report within the session.
  final int id;

  /// When the scan ended, in UTC.
  final DateTime utc;

  /// How the scan ended.
  final ScanEnd end;

  /// The pass the item or best candidate came from, or null when there was
  /// none.
  final ScanPass? winningPass;

  /// The targeted pass, or null when it never started.
  final PassReport? targeted;

  /// The fallback pass, or null when it did not run.
  final PassReport? fallback;

  /// Game mode of the index the scan matched against, or null.
  final GameMode? catalogMode;

  /// Revision of the index the scan matched against, or null.
  final String? catalogRevision;

  /// The scan's QPC stamps.
  final ScanTimeline timeline;

  /// Native trigger events dropped before this scan's trigger.
  final int droppedTriggers;

  /// Triggers that superseded this scan or were replaced in the pending slot.
  final int supersededTriggers;

  /// The ranked outcome, or null when the scan failed, was superseded or had
  /// no catalog.
  RecognitionOutcome<InspectionEvidence>? get outcome => switch (end) {
    ScanAccepted(:final outcome) => outcome,
    ScanRejected(:final outcome) => outcome,
    ScanFailed() || ScanSuperseded() => null,
  };

  /// Whether any pass or outcome still holds crop bytes.
  bool get hasCrops =>
      _recognitionHasCrops(targeted?.recognition) ||
      _recognitionHasCrops(fallback?.recognition) ||
      switch (outcome) {
        OutcomeAccepted(:final evidence) => evidence.crop.isNotEmpty,
        OutcomeRejected(:final evidence) => evidence?.crop.isNotEmpty ?? false,
        null => false,
      };

  /// A copy with every crop buffer emptied; everything else is kept.
  ScanReport withoutCrops() => ScanReport(
    id: id,
    utc: utc,
    end: switch (end) {
      ScanAccepted(:final itemId, :final outcome) => ScanAccepted(
        itemId: itemId,
        outcome: OutcomeAccepted<InspectionEvidence>(
          outcome.match,
          _stripEntry(outcome.evidence),
        ),
      ),
      ScanRejected(:final reason, :final outcome, :final fallbackFailure) =>
        ScanRejected(
          reason: reason,
          fallbackFailure: fallbackFailure,
          outcome: outcome == null
              ? null
              : OutcomeRejected<InspectionEvidence>(
                  outcome.reason,
                  evidence: outcome.evidence == null
                      ? null
                      : _stripEntry(outcome.evidence!),
                  match: outcome.match,
                  targetedBestMarkerScore: outcome.targetedBestMarkerScore,
                  fallbackBestMarkerScore: outcome.fallbackBestMarkerScore,
                ),
        ),
      ScanFailed() || ScanSuperseded() => end,
    },
    winningPass: winningPass,
    targeted: _stripPass(targeted),
    fallback: _stripPass(fallback),
    catalogMode: catalogMode,
    catalogRevision: catalogRevision,
    timeline: timeline,
    droppedTriggers: droppedTriggers,
    supersededTriggers: supersededTriggers,
  );

  /// The version 1 timing log line (ADR-0013), without `droppedLines`, which
  /// the timing log adds.
  ///
  /// Every `ms` value is a double in milliseconds from the trigger, rounded to
  /// 0.1 ms, except `trigger`, which is the integer 0. A stage not reached, a
  /// pass that did not run and a field with no value are omitted. Scores are
  /// rounded to 4 decimals. Candidates (best, then runner-up) are listed under
  /// the winning pass only, because the ranked outcome spans both passes. The
  /// line holds no pixels or crop bytes.
  Map<String, Object?> toLogLine(int qpcFrequency) {
    final winner = switch (outcome) {
      OutcomeAccepted(:final evidence) => evidence,
      OutcomeRejected(:final evidence) => evidence,
      null => null,
    };
    final match = switch (outcome) {
      OutcomeAccepted(:final match) => match as TitleMatch,
      OutcomeRejected(:final match) => match,
      null => null,
    };
    Map<String, Object?>? passLine(ScanPass pass, PassReport? report) {
      if (report == null) return null;
      final isWinner = winningPass == pass;
      return _passLine(
        report,
        isWinner ? winner : null,
        isWinner ? match : null,
      );
    }

    Map<String, Object?>? passMs(PassTimeline? pass) => pass == null
        ? null
        : {
            for (final MapEntry(:key, :value) in pass._stamps.entries)
              key: timeline.msFromTrigger(value, qpcFrequency),
          };

    final targetedMs = passMs(timeline.targeted);
    final fallbackMs = passMs(timeline.fallback);
    final published = timeline.published;
    final targetedLine = passLine(ScanPass.targeted, targeted);
    final fallbackLine = passLine(ScanPass.fallback, fallback);
    return {
      'v': 1,
      'utc': utc.toUtc().toIso8601String(),
      'end': end.logName,
      if (end case ScanAccepted(:final itemId)) 'item': itemId,
      if (switch (end) {
            ScanRejected(:final reason) => reason.name,
            ScanFailed(:final failure) => failure.code.name,
            ScanAccepted() || ScanSuperseded() => null,
          }
          case final String reason)
        'reason': reason,
      if (winningPass case final ScanPass pass) 'pass': pass.name,
      'targeted': ?targetedLine,
      'fallback': ?fallbackLine,
      'ms': {
        'trigger': 0,
        if (published != null)
          'published': timeline.msFromTrigger(published, qpcFrequency),
        'targeted': ?targetedMs,
        'fallback': ?fallbackMs,
      },
      'droppedTriggers': droppedTriggers,
      'supersededTriggers': supersededTriggers,
    };
  }
}

Map<String, Object?> _passLine(
  PassReport report,
  InspectionEvidence? winner,
  TitleMatch? match,
) {
  final recognition = report.recognition;
  final entry = switch (recognition) {
    InspectionRecognised(:final evidence) => _pickEntry(evidence, winner),
    InspectionRejected() || null => null,
  };
  final bestMarker = switch (recognition) {
    InspectionRecognised(:final bestMarkerScore) => bestMarkerScore,
    InspectionRejected(:final bestMarkerScore) => bestMarkerScore,
    null => null,
  };
  return {
    'bestMarker': ?(bestMarker == null ? null : _round4(bestMarker)),
    if (match != null && match.bestId != null)
      'candidates': [
        {'id': match.bestId, 'score': _round4(match.bestScore)},
        if (match.runnerUpId != null)
          {'id': match.runnerUpId, 'score': _round4(match.runnerUpScore)},
      ],
    'text': ?entry?.text,
    if (report.failure case final ScanFailure failure)
      'failure': failure.code.name,
  };
}

double _round4(double value) => (value * 10000).round() / 10000;

bool _recognitionHasCrops(InspectionRecognition? recognition) =>
    switch (recognition) {
      InspectionRecognised(:final evidence) => evidence.any(
        (e) => e.crop.isNotEmpty,
      ),
      InspectionRejected() || null => false,
    };

PassReport? _stripPass(PassReport? pass) => pass == null
    ? null
    : PassReport(
        recognition: switch (pass.recognition) {
          InspectionRecognised(
            :final kind,
            :final scale,
            :final bestMarkerScore,
            :final evidence,
          ) =>
            InspectionRecognised(
              kind: kind,
              scale: scale,
              bestMarkerScore: bestMarkerScore,
              evidence: [for (final e in evidence) _stripEntry(e)],
            ),
          InspectionRejected() || null => pass.recognition,
        },
        failure: pass.failure,
      );

InspectionEvidence _stripEntry(InspectionEvidence e) => InspectionEvidence(
  markerScore: e.markerScore,
  markerX: e.markerX,
  markerY: e.markerY,
  titleRect: e.titleRect,
  titleStatus: e.titleStatus,
  text: e.text,
  crop: Uint8List(0),
  cropWidth: e.cropWidth,
  cropHeight: e.cropHeight,
  cropDownscaled: e.cropDownscaled,
  qpcMarker: e.qpcMarker,
  qpcTitle: e.qpcTitle,
  qpcPreprocess: e.qpcPreprocess,
  qpcOcr: e.qpcOcr,
);
