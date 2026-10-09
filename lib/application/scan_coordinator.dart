/// The UI-facing values of live scanning and the coordinator that produces
/// them.
///
/// This file is the one `lib/application` or `lib/ui` source that may
/// reference the capture and vision services (ADR-0013). Every capture,
/// trigger, vision and marker-template failure is mapped here into a
/// [ScanFailure], so no other file needs those types.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../data/capture/capture_failure.dart';
import '../data/capture/capture_frame.dart';
import '../data/capture/capture_native.dart';
import '../data/capture/capture_service.dart';
import '../data/capture/capture_snapshot.dart';
import '../data/capture/mouse_release_trigger_source.dart';
import '../data/vision/inspection_recognition.dart';
import '../data/vision/marker_template.dart';
import '../data/vision/vision_job.dart';
import '../data/vision/vision_service.dart';
import '../domain/catalog.dart';
import '../domain/title_matching.dart';
import 'catalog_controller.dart';
import 'recognition_matcher.dart';
import 'settings_controller.dart';

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
  const LiveScanStatus(
    this.state, {
    this.reason,
    this.reasonCode,
    this.stopWarning,
  });

  /// Live scanning is off with nothing to report.
  static const LiveScanStatus off = LiveScanStatus(LiveScanState.off);

  /// The activation state.
  final LiveScanState state;

  /// Why the state is [LiveScanState.unavailable], else null.
  final String? reason;

  /// The machine-readable form of [reason], else null.
  final ScanFailureCode? reasonCode;

  /// A warning kept after a stop that did not complete (for example the hook
  /// thread did not stop), else null.
  final String? stopWarning;

  @override
  bool operator ==(Object other) =>
      other is LiveScanStatus &&
      other.state == state &&
      other.reason == reason &&
      other.reasonCode == reasonCode &&
      other.stopWarning == stopWarning;

  @override
  int get hashCode => Object.hash(state, reason, reasonCode, stopWarning);
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

// ---------------------------------------------------------------------------
// Ports
// ---------------------------------------------------------------------------

/// Where a worker behind a port is in its life.
enum ScanWorkerState {
  /// Constructed; no worker yet.
  idle,

  /// The worker is starting.
  starting,

  /// The worker is warm and has no request running.
  ready,

  /// A request is running.
  active,

  /// A request outlived its deadline and the worker has not replied yet.
  overrun,

  /// A close is draining the worker.
  closing,

  /// The worker is gone and the service was closed.
  closed,

  /// The worker cannot run jobs and is not respawned.
  unavailable,
}

/// The capture service as the coordinator uses it.
abstract interface class ScanCapturePort {
  /// Requests one capture; expected failures are returned, never thrown. The
  /// caller owns a returned frame.
  Future<CaptureResult> capture(TriggerEvent trigger, CaptureMode mode);

  /// Stops admission and drains the worker. Null means it closed cleanly.
  Future<ScanFailure?> close();

  /// Completes when the capture worker isolate has exited.
  Future<void> get workerExit;

  /// Why the worker cannot run, or null.
  ScanFailure? get unavailableReason;
}

/// The vision service as the coordinator uses it.
abstract interface class ScanVisionPort {
  /// Spawns the worker and completes null when it is ready, else with why it
  /// could not be.
  Future<ScanFailure?> start();

  /// Submits [frame] for recognition. The port takes ownership of the frame.
  Future<VisionAnswer<InspectionRecognition>> submitFrame(
    CaptureFrame frame,
    InspectionRequest request,
  );

  /// Answers every waiting request invalidated at once.
  void invalidate();

  /// Stops admission and drains the worker. Null means it closed cleanly.
  Future<ScanFailure?> close();

  /// Completes when the vision worker isolate has exited.
  Future<void> get workerExit;

  /// The worker's state.
  ScanWorkerState get state;

  /// Why the worker cannot run, or null.
  ScanFailure? get unavailableReason;
}

/// The mouse-release hook as the coordinator uses it.
abstract interface class ScanTriggerPort {
  /// Installs the hook. Null means started.
  TriggerFailure? start();

  /// Removes the hook. A [StopTimedOut] means the hook thread may still run.
  TriggerFailure? stop();

  /// Stops the hook and closes [triggers].
  Future<TriggerFailure?> dispose();

  /// Delivered triggers; nothing is buffered while there is no listener.
  Stream<ScanTrigger> get triggers;
}

/// The QPC clock the trigger and capture timestamps use.
abstract interface class ScanClock {
  /// The current QPC tick.
  int qpcNow();

  /// QPC ticks per second.
  int qpcFrequency();
}

/// The UI-side capture platform: the one hook and the clock. Opened lazily,
/// once per coordinator, because only one hook may exist per process.
abstract interface class ScanPlatform {
  /// The mouse-release hook.
  ScanTriggerPort get trigger;

  /// The QPC clock.
  ScanClock get clock;
}

/// Loads the marker template from a runtime directory.
typedef ScanMarkerLoader = Future<MarkerTemplateResult> Function(
  String runtimeDirectory,
);

/// Builds the capture service of one activation.
typedef ScanCaptureFactory = ScanCapturePort Function();

/// Builds the vision service of one activation over a loaded marker template.
typedef ScanVisionFactory = ScanVisionPort Function(
  VisionTemplate marker,
  String runtimeDirectory,
);

/// Opens the UI-side capture platform. May throw when it cannot open.
typedef ScanPlatformFactory = ScanPlatform Function();

/// Builds a catalog's title index off the UI isolate.
typedef ScanIndexBuilder = Future<TitleMatchIndex> Function(CatalogSnapshot s);

/// Ranks the recognition of one scan off the UI isolate.
typedef ScanMatcher = Future<RecognitionOutcome<InspectionEvidence>> Function(
  TitleMatchIndex index, {
  required InspectionRecognition? targeted,
  InspectionRecognition? fullClient,
  required GameMode mode,
});

/// Loads the marker template in one `Isolate.run`.
Future<MarkerTemplateResult> loadMarkerTemplateOffUi(String runtimeDirectory) =>
    Isolate.run(() => loadMarkerTemplate(runtimeDirectory));

/// The default [ScanIndexBuilder].
Future<TitleMatchIndex> buildScanIndex(CatalogSnapshot snapshot) =>
    buildTitleMatchIndexOffUi(snapshot);

/// The default [ScanMatcher].
Future<RecognitionOutcome<InspectionEvidence>> matchScanRecognition(
  TitleMatchIndex index, {
  required InspectionRecognition? targeted,
  InspectionRecognition? fullClient,
  required GameMode mode,
}) => matchRecognitionOffUi(
  index,
  targeted: targeted,
  fullClient: fullClient,
  mode: mode,
);

/// The default [ScanCaptureFactory]: a real capture service.
ScanCapturePort openDefaultScanCapture() =>
    _CaptureServicePort(CaptureService());

/// The default [ScanVisionFactory]: a real vision service running the
/// inspection recognition job over [marker].
ScanVisionPort openDefaultScanVision(
  VisionTemplate marker,
  String runtimeDirectory,
) => _VisionServicePort(
  VisionService<InspectionRequest, InspectionRecognition>(
    runtimeDirectory: runtimeDirectory,
    jobFactory: inspectionRecognitionJobFactory,
    templates: [marker],
  ),
);

/// The default [ScanPlatformFactory]: the native capture platform.
ScanPlatform openDefaultScanPlatform() =>
    _NativeScanPlatform(openDefaultNativeCapturePlatform());

final class _CaptureServicePort implements ScanCapturePort {
  _CaptureServicePort(this._service);

  final CaptureService _service;

  @override
  Future<CaptureResult> capture(TriggerEvent trigger, CaptureMode mode) =>
      _service.capture(trigger, mode);

  @override
  Future<ScanFailure?> close() async {
    final failure = await _service.close();
    return failure == null ? null : scanFailureFromCapture(failure);
  }

  @override
  Future<void> get workerExit => _service.workerExit;

  @override
  ScanFailure? get unavailableReason => null;
}

final class _VisionServicePort implements ScanVisionPort {
  _VisionServicePort(this._service);

  final VisionService<InspectionRequest, InspectionRecognition> _service;

  @override
  Future<ScanFailure?> start() async {
    final failure = await _service.start();
    return failure == null ? null : scanFailureFromVisionStart(failure);
  }

  @override
  Future<VisionAnswer<InspectionRecognition>> submitFrame(
    CaptureFrame frame,
    InspectionRequest request,
  ) => _service.submitFrame(frame, request);

  @override
  void invalidate() => _service.invalidate();

  @override
  Future<ScanFailure?> close() async => switch (await _service.close()) {
    VisionCloseResult.closed => null,
    VisionCloseResult.shutdownIncomplete => const ScanFailure(
      ScanFailureCode.shutdownIncomplete,
      'The vision worker did not stop within its drain.',
    ),
  };

  @override
  Future<void> get workerExit => _service.workerExit;

  @override
  ScanWorkerState get state => switch (_service.state) {
    VisionServiceState.idle => ScanWorkerState.idle,
    VisionServiceState.starting => ScanWorkerState.starting,
    VisionServiceState.ready => ScanWorkerState.ready,
    VisionServiceState.active => ScanWorkerState.active,
    VisionServiceState.overrun => ScanWorkerState.overrun,
    VisionServiceState.closing => ScanWorkerState.closing,
    VisionServiceState.closed => ScanWorkerState.closed,
    VisionServiceState.unavailable => ScanWorkerState.unavailable,
  };

  @override
  ScanFailure? get unavailableReason => switch (_service.unavailableReason) {
    null => null,
    final VisionStartFailure failure => scanFailureFromVisionStart(failure),
  };
}

final class _NativeScanPlatform implements ScanPlatform, ScanClock {
  _NativeScanPlatform(this._platform)
    : trigger = _SourceTriggerPort(MouseReleaseTriggerSource(_platform));

  final CapturePlatform _platform;

  @override
  final ScanTriggerPort trigger;

  @override
  ScanClock get clock => this;

  @override
  int qpcNow() => _platform.qpcNow();

  @override
  int qpcFrequency() => _platform.qpcFrequency();
}

final class _SourceTriggerPort implements ScanTriggerPort {
  _SourceTriggerPort(this._source);

  final MouseReleaseTriggerSource _source;

  @override
  TriggerFailure? start() => _source.start();

  @override
  TriggerFailure? stop() => _source.stop();

  @override
  Future<TriggerFailure?> dispose() => _source.dispose();

  @override
  Stream<ScanTrigger> get triggers => _source.triggers;
}

// ---------------------------------------------------------------------------
// Coordinator
// ---------------------------------------------------------------------------

/// What one activation (one switch-on) holds.
final class _Activation {
  final Completer<void> _cancelled = Completer<void>();

  ScanCapturePort? capture;
  ScanVisionPort? vision;
  StreamSubscription<ScanTrigger>? sub;
  bool hookInstalled = false;

  /// Set once the activation ended, by failure, loss or stop.
  bool retired = false;

  /// The bounded close of both services; set once.
  Future<void>? closing;

  Future<void> get cancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Owns live scanning for the app: the switch, the activation life of the
/// marker template, vision worker and mouse hook, and the status the Scanner
/// shows (ADR-0013).
///
/// A coordinator is the only writer of the session intent [switchOn]. It reads
/// the saved `liveScan` setting once, in [startFromSettings], and never reacts
/// to settings notifications afterwards, so a later unrelated save cannot
/// restart a pipeline the user switched off.
///
/// Activations run through one chain of futures, each link bounded, and carry
/// a token: a stop (switch-off or dispose) retires the activation at once and
/// closes every constructed service without waiting for the step in flight.
class ScanCoordinator extends ChangeNotifier {
  /// Creates a coordinator. The factories default to the real services;
  /// [runtimeDirectory] defaults to the directory of the running executable.
  ScanCoordinator({
    required this.settings,
    required this.catalog,
    required this.appendLogLine,
    this._markerLoader = loadMarkerTemplateOffUi,
    this._captureFactory = openDefaultScanCapture,
    this._visionFactory = openDefaultScanVision,
    this._platformFactory = openDefaultScanPlatform,
    this.indexBuilder = buildScanIndex,
    this.matcher = matchScanRecognition,
    String? runtimeDirectory,
    this.closeTimeout = const Duration(milliseconds: 2500),
  }) : runtimeDirectory =
           runtimeDirectory ?? File(Platform.resolvedExecutable).parent.path;

  /// The settings the switch saves through.
  final SettingsController settings;

  /// The catalog scans match against (read only; used by the scan flow).
  final CatalogController catalog;

  /// Appends one timing log line (used by the scan flow).
  final void Function(Map<String, Object?> line) appendLogLine;

  /// Builds a title index off the UI isolate (used by the scan flow).
  final ScanIndexBuilder indexBuilder;

  /// Ranks recognition off the UI isolate (used by the scan flow).
  final ScanMatcher matcher;

  /// Where the bundle's vision runtime lives.
  final String runtimeDirectory;

  /// The most any one close is awaited before it counts as incomplete.
  final Duration closeTimeout;

  final ScanMarkerLoader _markerLoader;
  final ScanCaptureFactory _captureFactory;
  final ScanVisionFactory _visionFactory;
  final ScanPlatformFactory _platformFactory;

  ScanPlatform? _platform;
  _Activation? _current;
  Future<void> _chain = Future<void>.value();
  Future<void>? _disposing;
  bool _disposed = false;
  bool _started = false;
  int _intent = 0;
  Future<bool>? _onSave;

  bool _switchOn = false;
  String? _error;
  LiveScanState _state = LiveScanState.off;
  ScanFailure? _reason;
  bool _hookStuck = false;
  String? _hookWarning;
  String? _workerWarning;

  /// The session intent of the Scanner switch.
  bool get switchOn => _switchOn;

  /// The last save error to show, or null.
  String? get error => _error;

  /// The activation state with its reason and any stop warning.
  LiveScanStatus get status => LiveScanStatus(
    _state,
    reason: _reason?.message,
    reasonCode: _reason?.code,
    stopWarning: switch ((_hookWarning, _workerWarning)) {
      (null, null) => null,
      (final String one, null) || (null, final String one) => one,
      (final String hook, final String worker) => '$hook $worker',
    },
  );

  /// The QPC clock, once the UI-side platform has opened; else null.
  ScanClock? get clock => _platform?.clock;

  /// Completes when every activation or stop queued so far has finished.
  Future<void> get settled async {
    while (true) {
      final chain = _chain;
      await chain;
      if (identical(chain, _chain)) return;
    }
  }

  /// Reads the saved `liveScan` setting once and starts the pipeline when it
  /// is on. Call after the settings have loaded; later calls do nothing.
  void startFromSettings() {
    if (_disposed || _started) return;
    _started = true;
    if (!settings.settings.liveScan) return;
    _switchOn = true;
    _activate();
  }

  /// The Scanner switch.
  ///
  /// Switching on saves first: a failed or busy save reverts the switch and
  /// starts nothing. Switching off stops the pipeline at once, before and
  /// whatever the save does; a failed or busy save shows an error and the
  /// pipeline stays off for the session.
  Future<void> setLiveScan(bool on) async {
    if (_disposed) return;
    _started = true;
    if (on) {
      if (_switchOn) {
        _notify();
        return;
      }
      // A switch-on save already running decides this tap too.
      final running = _onSave;
      if (running != null) {
        await running;
        return;
      }
      final epoch = ++_intent;
      _error = null;
      final save = _onSave = settings.save(
        settings.settings.copyWith(liveScan: true),
      );
      final saved = await save;
      if (identical(_onSave, save)) _onSave = null;
      if (_disposed || epoch != _intent) return;
      if (!saved) {
        _error = _notSaved(on: true);
        _notify();
        return;
      }
      _switchOn = true;
      _activate();
      return;
    }
    ++_intent;
    _error = null;
    _switchOn = false;
    _stop();
    // Let a switch-on save still running land first, so this save replaces
    // it instead of being refused as busy or skipped.
    final running = _onSave;
    if (running != null) await running;
    if (_disposed) return;
    if (!settings.settings.liveScan) return;
    final saved = await settings.save(
      settings.settings.copyWith(liveScan: false),
    );
    if (_disposed) return;
    if (!saved) {
      _error = _notSaved(on: false);
      _notify();
    }
  }

  /// Stops the pipeline, closes every service and the hook, and makes later
  /// notifications impossible. Bounded by the close timeouts.
  @override
  // ignore: must_call_super, super.dispose runs when the teardown finishes.
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _stop();
    await _chain.timeout(closeTimeout * 2, onTimeout: () {});
    final platform = _platform;
    if (platform != null) {
      try {
        await platform.trigger.dispose().timeout(closeTimeout);
      } on Object catch (error) {
        debugPrint('Scan hook dispose failed: $error');
      }
    }
    super.dispose();
  }

  static String _notSaved({required bool on}) => on
      ? 'Live scan was not switched on: the preference was not saved.'
      : 'Live scan is off for this session, but the preference was not saved '
            'and may return on the next launch.';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _set(LiveScanState state, [ScanFailure? reason]) {
    _state = state;
    _reason = reason;
    _notify();
  }

  void _enqueue(Future<void> Function() link) {
    _chain = _chain.then((_) => link()).catchError((
      Object error,
      StackTrace stack,
    ) {
      debugPrint('Scan lifecycle link failed: $error\n$stack');
    });
  }

  bool _stale(_Activation a) => !identical(_current, a) || a.retired;

  void _activate() {
    final a = _Activation();
    _current = a;
    _workerWarning = null;
    _set(LiveScanState.starting);
    _enqueue(() => _runStart(a));
  }

  /// Retires the current activation now: removes the hook, closes every
  /// constructed service without waiting for a step in flight, and queues the
  /// move to `off`.
  void _stop() {
    final a = _current;
    _current = null;
    if (a == null) {
      if (_state != LiveScanState.off) _set(LiveScanState.off);
      return;
    }
    a.retired = true;
    a.cancel();
    _unhook(a);
    final closing = _closeServices(a);
    _set(LiveScanState.stopping);
    _enqueue(() async {
      await closing;
      if (_current == null && !_disposed) _set(LiveScanState.off);
    });
  }

  /// Removes the hook now (S2: only a stop or a loss calls `stop`).
  void _unhook(_Activation a) {
    unawaited(a.sub?.cancel());
    a.sub = null;
    if (!a.hookInstalled) return;
    a.hookInstalled = false;
    final failure = _platform?.trigger.stop();
    if (failure == null) {
      _hookStuck = false;
      _hookWarning = null;
    } else {
      _hookStuck = true;
      _hookWarning = failure.message;
    }
  }

  Future<void> _closeServices(_Activation a) => a.closing ??= _doClose(a);

  Future<void> _doClose(_Activation a) async {
    final results = await Future.wait([
      _bounded(a.vision?.close()),
      _bounded(a.capture?.close()),
    ]);
    final failures = [
      for (final failure in results)
        if (failure != null) failure.message,
    ];
    if (failures.isNotEmpty) _workerWarning = failures.join(' ');
  }

  Future<ScanFailure?> _bounded(Future<ScanFailure?>? close) async {
    if (close == null) return null;
    try {
      return await close.timeout(
        closeTimeout,
        onTimeout: () => const ScanFailure(
          ScanFailureCode.shutdownIncomplete,
          'A worker did not stop within its drain.',
        ),
      );
    } on Object catch (error) {
      return ScanFailure(
        ScanFailureCode.shutdownIncomplete,
        'A worker failed to stop: $error',
      );
    }
  }

  /// Resolves with [work]'s value, or null as soon as [a] is cancelled.
  Future<(T,)?> _unlessCancelled<T>(_Activation a, Future<T> work) {
    final done = Completer<(T,)?>();
    work.then<void>(
      (value) {
        if (!done.isCompleted) done.complete((value,));
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
    );
    unawaited(
      a.cancelled.then<void>((_) {
        if (!done.isCompleted) done.complete(null);
      }),
    );
    return done.future;
  }

  Future<void> _fail(_Activation a, ScanFailure failure) async {
    if (_stale(a)) return;
    a.retired = true;
    _unhook(a);
    _set(LiveScanState.unavailable, failure);
    await _closeServices(a);
  }

  Future<void> _runStart(_Activation a) async {
    if (_stale(a)) return;
    // S2: a hook whose stop timed out is checked before anything is opened.
    if (_hookStuck) {
      final failure = _platform?.trigger.stop();
      if (failure != null) {
        _hookWarning = failure.message;
        await _fail(a, scanFailureFromTrigger(const AlreadyStarted()));
        return;
      }
      _hookStuck = false;
      _hookWarning = null;
    }

    // 1. The marker template, in one Isolate.run.
    final MarkerTemplateResult? loaded;
    try {
      loaded = (await _unlessCancelled(a, _markerLoader(runtimeDirectory)))?.$1;
    } on Object catch (error) {
      await _fail(
        a,
        ScanFailure(
          ScanFailureCode.markerTemplateUnavailable,
          'The marker template could not be loaded: $error',
        ),
      );
      return;
    }
    if (loaded == null || _stale(a)) return;
    final MarkerTemplateLoaded marker;
    switch (loaded) {
      case MarkerTemplateLoaded():
        marker = loaded;
      case MarkerTemplateUnavailable() || MarkerTemplateInvalid():
        await _fail(a, scanFailureFromMarkerTemplate(loaded)!);
        return;
    }

    // 2. The services, then the vision worker.
    final ScanVisionPort vision;
    try {
      a.capture = _captureFactory();
      vision = a.vision = _visionFactory(marker.template, runtimeDirectory);
    } on Object catch (error) {
      await _fail(
        a,
        ScanFailure(
          ScanFailureCode.visionStartFailed,
          'The scan services could not be created: $error',
        ),
      );
      return;
    }
    _watchExit(a, vision.workerExit, isVision: true);
    _watchExit(a, a.capture!.workerExit, isVision: false);
    final (ScanFailure?,)? started;
    try {
      started = await _unlessCancelled(a, vision.start());
    } on Object catch (error) {
      await _fail(
        a,
        ScanFailure(
          ScanFailureCode.visionStartFailed,
          'The vision worker failed to start: $error',
        ),
      );
      return;
    }
    if (started == null || _stale(a)) return;
    if (started.$1 case final ScanFailure failure) {
      await _fail(a, failure);
      return;
    }

    // 3. The UI-side capture platform and the hook, created once.
    final ScanPlatform platform;
    try {
      platform = _platform ??= _platformFactory();
    } on Object catch (error) {
      await _fail(
        a,
        ScanFailure(
          ScanFailureCode.captureUnavailable,
          'The capture platform could not open: $error',
        ),
      );
      return;
    }
    if (_stale(a)) return;
    final hookFailure = platform.trigger.start();
    if (hookFailure != null) {
      await _fail(a, scanFailureFromTrigger(hookFailure));
      return;
    }
    a.hookInstalled = true;
    a.sub = platform.trigger.triggers.listen(_onTrigger);
    _set(LiveScanState.ready);
  }

  void _watchExit(_Activation a, Future<void> exit, {required bool isVision}) {
    exit.then<void>(
      (_) => _onWorkerExit(a, isVision: isVision),
      onError: (Object _) {},
    );
  }

  /// A worker that exits while its activation is still live is a loss (S1).
  /// Exits the coordinator caused itself retire the activation first.
  Future<void> _onWorkerExit(_Activation a, {required bool isVision}) async {
    if (_stale(a)) return;
    final reason = isVision
        ? (a.vision?.unavailableReason ??
              const ScanFailure(
                ScanFailureCode.visionUnavailable,
                'The vision worker exited.',
              ))
        : (a.capture?.unavailableReason ??
              const ScanFailure(
                ScanFailureCode.captureUnavailable,
                'The capture worker exited.',
              ));
    await _fail(a, reason);
  }

  /// Handles one mouse-release trigger while the pipeline is ready. The scan
  /// flow (task group 7) fills this in.
  void _onTrigger(ScanTrigger trigger) {}
}
