/// The UI-facing values of live scanning and the coordinator that produces
/// them.
///
/// This file is the one `lib/application` or `lib/ui` source that may
/// reference the capture and vision services (ADR-0013). Every capture,
/// trigger, vision and marker-template failure is mapped here into a
/// [ScanFailure], so no other file needs those types.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../data/capture/capture_failure.dart';
import '../data/capture/capture_frame.dart';
import '../data/capture/capture_native.dart';
import '../data/capture/capture_service.dart';
import '../data/capture/capture_snapshot.dart';
import '../data/capture/mouse_release_trigger_source.dart';
import '../data/scan_frame_recorder.dart';
import '../data/vision/inspection_recognition.dart';
import '../data/vision/marker_template.dart';
import '../data/vision/vision_job.dart';
import '../data/vision/vision_service.dart';
import '../domain/catalog.dart';
import '../domain/title_matching.dart';
import 'catalog_controller.dart';
import 'recognition_matcher.dart';
import 'scan_epoch.dart';
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

/// Where accepted scans come from: a [Listenable] that exposes the newest
/// accepted [ScanReport].
///
/// [ScanCoordinator] is the app's source. Consumers such as the decision feed
/// depend on this interface, so the coordinator never imports them.
abstract interface class AcceptedScanSource implements Listenable {
  /// The most recent accepted scan, or null before any scan is accepted.
  ScanReport? get lastAccepted;
}

/// Everything known about one finished scan.
///
/// Crop bytes are kept only on the latest and the last accepted published
/// reports; call [withoutCrops] to store a summary in the recent list.
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
    this.epoch,
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

  /// The epoch read when the scan began, or null for a report built without
  /// one. It is not part of the timing log line.
  final ScanEpoch? epoch;

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
    epoch: epoch,
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
ScanCapturePort openDefaultScanCapture() => scanCapturePort(CaptureService());

/// The [ScanCapturePort] over [service].
ScanCapturePort scanCapturePort(CaptureService service) =>
    _CaptureServicePort(service);

/// The [ScanVisionPort] over [service].
ScanVisionPort scanVisionPort(
  VisionService<InspectionRequest, InspectionRecognition> service,
) => _VisionServicePort(service);

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
  ScanFailure? get unavailableReason => switch (_service.unavailableReason) {
    null => null,
    final reason => scanFailureFromCapture(CaptureUnavailable(reason)),
  };
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

  /// The QPC clock and its frequency, read once when the platform opened.
  ScanClock? clock;
  int qpcFrequency = 1;

  /// Set once the activation ended, by failure, loss or stop.
  bool retired = false;

  /// The bounded close of both services; set once.
  Future<void>? closing;

  Future<void> get cancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Which stage a scan waits in; it decides how a newer trigger supersedes it.
enum _Stage { waiting, capture, vision, matching }

/// A trigger waiting for the scan in flight to return from capture, and the
/// number of older pending triggers it replaced.
final class _Pending {
  _Pending(this.trigger, this.replaced);

  final ScanTrigger trigger;
  final int replaced;
}

/// One scan in flight: its trigger, the stamps and results gathered so far.
final class _Scan {
  _Scan({
    required this.activation,
    required this.trigger,
    required this.id,
    required this.generation,
    required this.replacedTriggers,
    required this.epoch,
  });

  final _Activation activation;
  final ScanTrigger trigger;
  final int id;

  /// The scan generation current when this scan started. A newer value
  /// anywhere means this scan was superseded.
  final int generation;

  /// Older pending triggers dropped before this scan started.
  final int replacedTriggers;

  /// The epoch read when this scan began.
  final ScanEpoch epoch;

  /// Triggers that arrived while this scan ran.
  int supersedingTriggers = 0;
  _Stage stage = _Stage.capture;
  bool ended = false;

  final Completer<void> _cancelled = Completer<void>();

  /// Completes when a newer trigger, a stop or a loss supersedes this scan,
  /// so a wait ends at once.
  Future<void> get cancelled => _cancelled.future;

  /// Completes [cancelled]; later calls do nothing.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  PassTimeline targetedTimeline = const PassTimeline();
  PassTimeline? fallbackTimeline;
  PassReport? targetedReport;
  PassReport? fallbackReport;
  InspectionRecognition? targetedRecognition;
  InspectionRecognition? fallbackRecognition;
  GameMode? catalogMode;
  String? catalogRevision;

  /// The strip copied for the recorder, when recording was on at its pass.
  RecordedFrame? recordedStrip;

  /// The full-client frame copied for the recorder: the fallback pass's, or
  /// the extra capture's after a targeted acceptance.
  RecordedFrame? recordedFull;

  /// Client size and cursor, read from the first frame copied for recording.
  int? recordedClientWidth;
  int? recordedClientHeight;
  int? recordedCursorX;
  int? recordedCursorY;

  /// The folder of the recording session the scan's first frame was copied
  /// for; a later session never takes the scan.
  String? recordedSession;

  /// Why the extra capture produced no frame, when one was attempted.
  String? extraFailure;

  /// Whether a pixel copy failed, so the scan is left out of the recording.
  bool recordingLost = false;

  PassTimeline? timeline(ScanPass pass) => switch (pass) {
    ScanPass.targeted => targetedTimeline,
    ScanPass.fallback => fallbackTimeline,
  };

  void stamp(ScanPass pass, PassTimeline Function(PassTimeline) update) {
    switch (pass) {
      case ScanPass.targeted:
        targetedTimeline = update(targetedTimeline);
      case ScanPass.fallback:
        fallbackTimeline = update(fallbackTimeline ?? const PassTimeline());
    }
  }
}

/// What one pass produced.
sealed class _PassResult {
  const _PassResult();
}

/// The pass delivered a recognition.
final class _PassRecognised extends _PassResult {
  const _PassRecognised(this.recognition);

  final InspectionRecognition recognition;
}

/// The pass ended in a capture or vision failure.
final class _PassFailed extends _PassResult {
  const _PassFailed(this.failure);

  final ScanFailure failure;
}

/// The scan is no longer current; nothing more is done for it.
final class _PassAbandoned extends _PassResult {
  const _PassAbandoned();
}

/// What the matching stage produced.
sealed class _MatchResult {
  const _MatchResult();
}

/// The matcher ranked the evidence.
final class _Matched extends _MatchResult {
  const _Matched(this.outcome);

  final RecognitionOutcome<InspectionEvidence> outcome;
}

/// No catalog index was available.
final class _NoIndex extends _MatchResult {
  const _NoIndex();
}

/// The scan is no longer current.
final class _MatchAbandoned extends _MatchResult {
  const _MatchAbandoned();
}

/// The cached title index of one catalog snapshot; a failed build is null.
final class _IndexEntry {
  _IndexEntry(this.snapshot, this.index);

  final CatalogSnapshot snapshot;
  final Future<TitleMatchIndex?> index;
}

/// Waits for a duration; the scan flow's only way to wait. Tests inject a
/// waiter they complete by hand.
typedef ScanWaiter = Future<void> Function(Duration duration);

Future<void> _timerWaiter(Duration duration) {
  final done = Completer<void>();
  Timer(duration, done.complete);
  return done.future;
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
class ScanCoordinator extends ChangeNotifier implements AcceptedScanSource {
  /// Creates a coordinator. The factories default to the real services;
  /// [runtimeDirectory] defaults to the directory of the running executable.
  /// [epoch] reads the app's epoch when a scan begins and defaults to a
  /// constant.
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
    ScanWaiter? waiter,
    this.settleDelay = const Duration(milliseconds: 50),
    this.fallbackDelay = const Duration(milliseconds: 200),
    this._recorder,
    ScanEpoch Function()? epoch,
  }) : _waiter = waiter ?? _timerWaiter,
       _epoch = epoch ?? _constantEpoch,
       runtimeDirectory =
           runtimeDirectory ?? File(Platform.resolvedExecutable).parent.path {
    catalog.addListener(_syncIndex);
  }

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

  /// How long after the trigger's timestamp the targeted capture may be
  /// requested, so the inspect window can settle.
  final Duration settleDelay;

  /// How long after the trigger's timestamp the fallback capture may be
  /// requested.
  final Duration fallbackDelay;

  /// How many published scans [recent] keeps.
  static const int recentLimit = 10;

  final ScanMarkerLoader _markerLoader;
  final ScanCaptureFactory _captureFactory;
  final ScanVisionFactory _visionFactory;
  final ScanPlatformFactory _platformFactory;
  final ScanWaiter _waiter;
  final ScanFrameRecorder? _recorder;
  final ScanEpoch Function() _epoch;

  static ScanEpoch _constantEpoch() => const ScanEpoch(0, 0);

  ScanPlatform? _platform;
  _Activation? _current;
  Future<void> _chain = Future<void>.value();
  Future<void>? _disposing;
  bool _disposed = false;
  bool _started = false;
  int _intent = 0;
  Future<bool>? _saving;
  Future<void>? _offPersist;

  ScanPhase _phase = ScanPhase.idle;
  ScanReport? _latest;
  ScanReport? _lastAccepted;
  final List<ScanReport> _recent = [];

  /// Advances when a newer trigger, a stop or a loss supersedes the scans in
  /// flight; a scan started under an older value is never published.
  int _scanGeneration = 0;
  int _nextReportId = 1;
  _Scan? _active;
  _Pending? _pending;
  _IndexEntry? _index;

  /// The match still running off the UI isolate, if any. Matches are
  /// serialised: a new one starts only after this one ends, even when its scan
  /// was superseded and its result will be discarded.
  Future<void>? _runningMatch;

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

  static final ValueListenable<ScanRecordingStatus> _noRecording =
      ValueNotifier<ScanRecordingStatus>(const ScanRecordingStatus());

  /// The recording state, counts, folder and stop reason; constantly off when
  /// the coordinator has no recorder.
  ValueListenable<ScanRecordingStatus> get recordingStatus =>
      _recorder?.status ?? _noRecording;

  /// Turns frame recording on or off.
  ///
  /// Turning on is accepted only while live scan is `ready` and no earlier
  /// session is running or still draining; otherwise it does nothing and the
  /// switch stays off. Turning off stops the session, and the scans already
  /// handed to the writer are still written. Recording is never saved in the
  /// settings.
  Future<void> setRecording(bool on) async {
    final recorder = _recorder;
    if (recorder == null || _disposed) return;
    if (!on) {
      recorder.stop();
      return;
    }
    if (_state != LiveScanState.ready ||
        recorder.status.value.state != ScanRecordingState.off) {
      return;
    }
    await recorder.start();
  }

  /// The QPC clock, once the UI-side platform has opened; else null.
  ScanClock? get clock => _platform?.clock;

  /// The phase of the scan in flight, or [ScanPhase.idle].
  ScanPhase get phase => _phase;

  /// The latest published scan, with its crop bytes, or null.
  ScanReport? get latest => _latest;

  /// The most recent accepted scan, with its crop bytes, or null before any
  /// scan is accepted.
  ///
  /// It stays until a newer scan is accepted, so Scanner keeps showing it
  /// while later scans are rejected or fail. Crop bytes are kept for it as
  /// well as for [latest].
  @override
  ScanReport? get lastAccepted => _lastAccepted;

  /// The most recent published scans, newest first, at most [recentLimit].
  /// Each is a summary without crop bytes.
  List<ScanReport> get recent => UnmodifiableListView(_recent);

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
  /// pipeline stays off for the session. Of taps that overlap a save, only
  /// the latest saves and acts, once the earlier saves have landed.
  Future<void> setLiveScan(bool on) async {
    if (_disposed) return;
    _started = true;
    if (on) {
      if (_switchOn) {
        _notify();
        return;
      }
      // Only the latest tap acts once the saves already running have landed.
      final epoch = ++_intent;
      _error = null;
      await _savesLanded();
      if (_disposed || epoch != _intent) return;
      final saved = await _save(on: true);
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
    final epoch = ++_intent;
    _error = null;
    _switchOn = false;
    _stop();
    final persist = _offPersist = _persistOff(epoch);
    await persist;
  }

  /// Saves the switch-off of tap [epoch]. Dispose waits for it, so an off
  /// tap right before exit still reaches the setting.
  Future<void> _persistOff(int epoch) async {
    // Let a save still running land first, so this save replaces it instead
    // of being refused as busy or skipped; a later tap decides instead.
    await _savesLanded();
    if (epoch != _intent) return;
    if (!settings.settings.liveScan) return;
    final saved = await _save(on: false);
    if (_disposed || epoch != _intent) return;
    if (!saved) {
      _error = _notSaved(on: false);
      _notify();
    }
  }

  /// Saves the `liveScan` setting, tracked so later taps wait for it.
  Future<bool> _save({required bool on}) async {
    final save = _saving = settings.save(
      settings.settings.copyWith(liveScan: on),
    );
    try {
      return await save;
    } finally {
      if (identical(_saving, save)) _saving = null;
    }
  }

  /// Completes once no save started by [setLiveScan] is running.
  Future<void> _savesLanded() async {
    for (var running = _saving; running != null; running = _saving) {
      // A failed save is the tap's own error to report, not this wait's.
      await running.then((_) {}, onError: (Object _) {});
    }
  }

  /// Stops the pipeline, closes every service and the hook, and makes later
  /// notifications impossible. Bounded by the close timeouts.
  @override
  // ignore: must_call_super, super.dispose runs when the teardown finishes.
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    catalog.removeListener(_syncIndex);
    _stop();
    // Let a switch save land before the settings and database are torn down:
    // the off save a tap queued, then any save still running.
    Future<void> saves() async {
      await _offPersist;
      await _savesLanded();
    }

    await saves().timeout(closeTimeout, onTimeout: () {});
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
    // Recording lasts only while live scan is ready, including while it is
    // still starting.
    if (state != LiveScanState.ready) _recorder?.stop();
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
    _syncIndex();
    _set(LiveScanState.starting);
    _enqueue(() => _runStart(a));
  }

  /// Retires the current activation now: removes the hook, closes every
  /// constructed service without waiting for a step in flight, and queues the
  /// move to `off`.
  void _stop() {
    final a = _current;
    _current = null;
    _abandonScans();
    _index = null;
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
    if (failures.isEmpty) return;
    // After a loss the state is already unavailable, so nothing else would
    // tell listeners about the warning.
    _workerWarning = failures.join(' ');
    _notify();
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
    _abandonScans();
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
    a.clock = platform.clock;
    a.qpcFrequency = platform.clock.qpcFrequency();
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

  // -------------------------------------------------------------------------
  // Scan flow
  // -------------------------------------------------------------------------

  /// Whether live scanning is switched on and the coordinator is alive.
  bool get _liveOn => _switchOn && !_disposed;

  /// Whether [s] was superseded or its activation ended; such a scan
  /// publishes nothing and releases any frame it holds.
  bool _dead(_Scan s) =>
      s.generation != _scanGeneration || _stale(s.activation) || _disposed;

  int _now(_Activation a) => a.clock?.qpcNow() ?? 0;

  /// Handles one mouse-release trigger while the pipeline is ready.
  ///
  /// With no scan in flight the trigger starts one. Otherwise it supersedes
  /// the scan in flight, and how the new scan starts depends on the stage the
  /// old one is in: capture cannot be cancelled, so the newest trigger waits
  /// in the pending slot for the capture answer; a wait is cut short and the
  /// new scan starts now; a vision request is invalidated and the new scan
  /// starts now; a match is left to finish and its result is discarded.
  void _onTrigger(ScanTrigger trigger) {
    final a = _current;
    if (_disposed || a == null || a.retired) return;
    final active = _active;
    if (active == null) {
      _begin(a, trigger, replaced: 0);
      return;
    }
    active.supersedingTriggers++;
    _scanGeneration++;
    switch (active.stage) {
      case _Stage.capture:
        final waiting = _pending;
        _pending = _Pending(
          trigger,
          waiting == null ? 0 : waiting.replaced + 1,
        );
      case _Stage.waiting:
        active.cancel();
        _begin(a, trigger, replaced: 0);
      case _Stage.vision:
        a.vision?.invalidate();
        _begin(a, trigger, replaced: 0);
      case _Stage.matching:
        _begin(a, trigger, replaced: 0);
    }
  }

  void _begin(_Activation a, ScanTrigger trigger, {required int replaced}) {
    final scan = _Scan(
      activation: a,
      trigger: trigger,
      id: _nextReportId++,
      generation: _scanGeneration,
      replacedTriggers: replaced,
      epoch: _epoch(),
    );
    _active = scan;
    _setPhase(scan, ScanPhase.targeted);
    unawaited(_run(scan));
  }

  /// Drops the scan in flight and the pending trigger, as a stop or a loss
  /// does. The scan's own flow notices at its next hand-off, releases what it
  /// holds and logs it as superseded.
  void _abandonScans() {
    _scanGeneration++;
    _active?.cancel();
    _active = null;
    _pending = null;
    _phase = ScanPhase.idle;
  }

  Future<void> _run(_Scan s) async {
    try {
      await _flow(s);
    } on Object catch (error, stack) {
      debugPrint('Scan flow failed: $error\n$stack');
      _endSuperseded(s);
    } finally {
      _retire(s);
    }
  }

  /// Frees the in-flight slot of a finished scan and starts the pending
  /// trigger, if one waited for it.
  void _retire(_Scan s) {
    if (!identical(_active, s)) return;
    _active = null;
    final next = _pending;
    _pending = null;
    final a = _current;
    if (next == null || a == null || a.retired || _disposed) return;
    _begin(a, next.trigger, replaced: next.replaced);
  }

  void _setPhase(_Scan s, ScanPhase phase) {
    if (_dead(s) || _phase == phase) return;
    _phase = phase;
    _notify();
  }

  Future<void> _flow(_Scan s) async {
    // Targeted pass, once the inspect window had time to settle.
    if (!await _waitUntil(s, settleDelay)) return _endSuperseded(s);
    ScanFailure? targetedFailure;
    OutcomeRejected<InspectionEvidence>? targetedRejection;
    switch (await _runPass(s, ScanPass.targeted)) {
      case _PassAbandoned():
        return _endSuperseded(s);
      case _PassFailed(:final failure):
        s.targetedReport = PassReport(failure: failure);
        if (!_fallsBackAfterCapture(failure.code)) {
          return _conclude(s, ScanFailed(failure));
        }
        targetedFailure = failure;
      case _PassRecognised(:final recognition):
        s.targetedRecognition = recognition;
        s.targetedReport = PassReport(recognition: recognition);
        switch (await _match(s, ScanPass.targeted, targeted: recognition)) {
          case _MatchAbandoned():
            return _endSuperseded(s);
          case _NoIndex():
            return _conclude(
              s,
              const ScanRejected(reason: ScanRejectReason.catalogUnavailable),
            );
          case _Matched(:final outcome):
            switch (outcome) {
              case OutcomeAccepted<InspectionEvidence>():
                return _conclude(
                  s,
                  ScanAccepted(itemId: outcome.match.bestId!, outcome: outcome),
                );
              case OutcomeRejected<InspectionEvidence>(:final reason):
                if (!_fallsBackAfterRejection(reason)) {
                  return _conclude(s, _rejection(outcome));
                }
                targetedRejection = outcome;
            }
        }
    }

    // Fallback pass: the phase is published before the capture request.
    _setPhase(s, ScanPhase.fallback);
    if (!await _waitUntil(s, fallbackDelay)) return _endSuperseded(s);
    switch (await _runPass(s, ScanPass.fallback)) {
      case _PassAbandoned():
        return _endSuperseded(s);
      case _PassFailed(:final failure):
        s.fallbackReport = PassReport(failure: failure);
        if (targetedRejection != null) {
          return _conclude(
            s,
            _rejection(targetedRejection, fallbackFailure: failure),
          );
        }
        return _conclude(
          s,
          ScanFailed(failure, targetedFailure: targetedFailure),
        );
      case _PassRecognised(:final recognition):
        s.fallbackRecognition = recognition;
        s.fallbackReport = PassReport(recognition: recognition);
        final matched = await _match(
          s,
          ScanPass.fallback,
          targeted: s.targetedRecognition,
          fullClient: recognition,
        );
        switch (matched) {
          case _MatchAbandoned():
            return _endSuperseded(s);
          case _NoIndex():
            return _conclude(
              s,
              const ScanRejected(reason: ScanRejectReason.catalogUnavailable),
            );
          case _Matched(:final outcome):
            return _conclude(s, switch (outcome) {
              OutcomeAccepted<InspectionEvidence>() => ScanAccepted(
                itemId: outcome.match.bestId!,
                outcome: outcome,
              ),
              OutcomeRejected<InspectionEvidence>() => _rejection(outcome),
            });
        }
    }
  }

  /// Holds [s] until [delay] after its trigger's timestamp, or until it is
  /// superseded. Returns whether the scan is still current.
  ///
  /// The wait holds no frame and makes no native call. A trigger already old
  /// enough waits not at all. The wait never exceeds [delay], which also bounds
  /// it when the clock is missing.
  Future<bool> _waitUntil(_Scan s, Duration delay) async {
    final a = s.activation;
    s.stage = _Stage.waiting;
    final frequency = a.qpcFrequency;
    final delayTicks = delay.inMicroseconds * frequency ~/ 1000000;
    final remainingTicks = s.trigger.event.qpc + delayTicks - _now(a);
    final ticks = remainingTicks < delayTicks ? remainingTicks : delayTicks;
    if (ticks > 0) {
      await Future.any<void>([
        _waiter(Duration(microseconds: ticks * 1000000 ~/ frequency)),
        s.cancelled,
      ]);
    }
    return !_dead(s);
  }

  ScanRejected _rejection(
    OutcomeRejected<InspectionEvidence> outcome, {
    ScanFailure? fallbackFailure,
  }) => ScanRejected(
    reason: ScanRejectReason.fromOutcome(outcome.reason),
    outcome: outcome,
    fallbackFailure: fallbackFailure,
  );

  /// The closed list of targeted rejections that run a fallback pass.
  static bool _fallsBackAfterRejection(OutcomeRejectReason reason) =>
      switch (reason) {
        OutcomeRejectReason.emptyCatalog ||
        OutcomeRejectReason.catalogModeMismatch => false,
        OutcomeRejectReason.noMarker ||
        OutcomeRejectReason.matcherFailed ||
        OutcomeRejectReason.titleTooShort ||
        OutcomeRejectReason.uiChrome ||
        OutcomeRejectReason.belowSimilarity ||
        OutcomeRejectReason.ambiguous => true,
      };

  /// The closed list of targeted capture failures that run a fallback pass.
  static bool _fallsBackAfterCapture(ScanFailureCode code) => switch (code) {
    ScanFailureCode.roiOutsideClient ||
    ScanFailureCode.blankCapture ||
    ScanFailureCode.targetChanged => true,
    _ => false,
  };

  /// Captures and recognises one pass of [s].
  Future<_PassResult> _runPass(_Scan s, ScanPass pass) async {
    final a = s.activation;
    final (mode, kind) = switch (pass) {
      ScanPass.targeted => (CaptureMode.targeted, InspectionFrameKind.targeted),
      ScanPass.fallback => (
        CaptureMode.fallback,
        InspectionFrameKind.fullClient,
      ),
    };
    s.stage = _Stage.capture;
    s.stamp(pass, (t) => t.copyWith(captureRequested: _now(a)));
    final CaptureResult result;
    try {
      result = await a.capture!.capture(s.trigger.event, mode);
    } on Object catch (error) {
      s.stamp(pass, (t) => t.copyWith(captureAnswered: _now(a)));
      if (_dead(s)) return const _PassAbandoned();
      return _PassFailed(
        ScanFailure(
          ScanFailureCode.captureFailed,
          'The capture request failed: $error',
        ),
      );
    }
    s.stamp(pass, (t) => t.copyWith(captureAnswered: _now(a)));
    switch (result) {
      case CaptureRejected(:final failure):
        if (_dead(s)) return const _PassAbandoned();
        return _PassFailed(scanFailureFromCapture(failure));
      case CaptureSuccess(:final frame):
        // Stamp reached stages before the fence, so a superseded line keeps them.
        final metadata = frame.metadata;
        s.stamp(
          pass,
          (t) => t.copyWith(
            acquireStart: metadata.qpcBefore,
            acquireEnd: metadata.qpcAfter,
          ),
        );
        if (_dead(s)) {
          frame.release();
          return const _PassAbandoned();
        }
        if (_recordingOn) _copyForRecording(s, pass, frame);
        s.stage = _Stage.vision;
        final VisionAnswer<InspectionRecognition> answer;
        try {
          // The vision port owns the frame from here on.
          answer = await a.vision!.submitFrame(
            frame,
            InspectionRequest(
              kind: kind,
              clientWidth: metadata.clientWidth,
              clientHeight: metadata.clientHeight,
            ),
          );
        } on Object catch (error) {
          frame.release();
          if (_dead(s)) return const _PassAbandoned();
          return _PassFailed(
            ScanFailure(
              ScanFailureCode.visionJobFailed,
              'The recognition request failed: $error',
            ),
          );
        }
        final (int? started, int? finished) = switch (answer) {
          VisionDelivered(:final startedQpc, :final finishedQpc) ||
          VisionJobFailed(:final startedQpc, :final finishedQpc) ||
          VisionFailureAnswer(
            :final startedQpc,
            :final finishedQpc,
          ) => (startedQpc, finishedQpc),
          VisionNotDelivered() => (null, null),
        };
        s.stamp(
          pass,
          (t) => t.copyWith(
            visionSubmitted: answer.submittedQpc,
            jobStarted: started,
            jobFinished: finished,
          ),
        );
        if (answer case VisionDelivered(:final result)) {
          // The report restamps from the winner; a superseded scan keeps these.
          s.stamp(pass, (t) => t.withEvidenceStamps(result));
        }
        if (_dead(s)) return const _PassAbandoned();
        if (answer case VisionDelivered(:final result)) {
          return _PassRecognised(result);
        }
        return _PassFailed(scanFailureFromVision(answer)!);
    }
  }

  /// Ranks the recognition of [pass] against the current catalog index.
  ///
  /// A match never starts while an earlier one still runs, whether or not its
  /// scan is still current. The index is the one current when this match
  /// starts, awaited if it is still being built.
  Future<_MatchResult> _match(
    _Scan s,
    ScanPass pass, {
    required InspectionRecognition? targeted,
    InspectionRecognition? fullClient,
  }) async {
    final a = s.activation;
    s.stage = _Stage.matching;
    for (
      var running = _runningMatch;
      running != null;
      running = _runningMatch
    ) {
      await running;
      if (_dead(s)) return const _MatchAbandoned();
    }
    if (_dead(s)) return const _MatchAbandoned();
    _syncIndex();
    final entry = _index;
    final index = entry == null ? null : await entry.index;
    if (_dead(s)) return const _MatchAbandoned();
    if (index == null) return const _NoIndex();

    final mode = index.mode;
    s.stamp(pass, (t) => t.copyWith(matchStarted: _now(a)));
    final run = Future<RecognitionOutcome<InspectionEvidence>>.sync(
      () => matcher(
        index,
        targeted: targeted,
        fullClient: fullClient,
        mode: mode,
      ),
    );
    late final Future<void> done;
    done = run.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_runningMatch, done)) _runningMatch = null;
    });
    _runningMatch = done;
    RecognitionOutcome<InspectionEvidence> outcome;
    try {
      outcome = await run;
    } on Object catch (error) {
      debugPrint('Scan matcher failed: $error');
      outcome = OutcomeRejected<InspectionEvidence>(
        OutcomeRejectReason.matcherFailed,
        targetedBestMarkerScore: targeted == null
            ? null
            : recognitionInputFor(targeted).bestMarkerScore,
        fallbackBestMarkerScore: fullClient == null
            ? null
            : recognitionInputFor(fullClient).bestMarkerScore,
      );
    }
    s.stamp(pass, (t) => t.copyWith(matchFinished: _now(a)));
    if (_dead(s)) return const _MatchAbandoned();
    s.catalogMode = index.mode;
    s.catalogRevision = index.revision;
    return _Matched(outcome);
  }

  /// Rebuilds the title index when the catalog snapshot changed, only while
  /// live scanning is on. A failed build leaves a null entry that the next
  /// snapshot change replaces.
  void _syncIndex() {
    final snapshot = catalog.snapshot;
    if (!_liveOn || snapshot == null) {
      _index = null;
      return;
    }
    if (identical(_index?.snapshot, snapshot)) return;
    _index = _IndexEntry(snapshot, _buildIndex(snapshot));
  }

  Future<TitleMatchIndex?> _buildIndex(CatalogSnapshot snapshot) async {
    try {
      return await indexBuilder(snapshot);
    } on Object catch (error) {
      debugPrint('Scan title index build failed: $error');
      return null;
    }
  }

  /// Ends [s] with [end]: logs it and publishes it while it is current, else
  /// logs it as superseded. Returns the published report, or null when the
  /// scan was not published.
  ScanReport? _finish(_Scan s, ScanEnd end) {
    if (s.ended) return null;
    if (_dead(s) || !_liveOn) {
      _endSuperseded(s);
      return null;
    }
    s.ended = true;
    final a = s.activation;
    final winner = switch (end) {
      ScanAccepted(:final outcome) => outcome.evidence,
      ScanRejected(:final outcome) => outcome?.evidence,
      ScanFailed() || ScanSuperseded() => null,
    };
    final report = _report(s, end, winner: winner, published: _now(a));
    _log(a, report);
    _publish(report);
    // A worker that reports itself unavailable ends the activation.
    final lost = [s.targetedReport?.failure, s.fallbackReport?.failure]
        .whereType<ScanFailure>()
        .where(
          (f) =>
              f.code == ScanFailureCode.captureUnavailable ||
              f.code == ScanFailureCode.visionUnavailable,
        );
    if (lost.isNotEmpty) _enqueue(() => _fail(a, lost.last));
    return report;
  }

  // -------------------------------------------------------------------------
  // Frame recording
  // -------------------------------------------------------------------------

  /// Whether a recording session takes scans right now.
  bool get _recordingOn =>
      _recorder?.status.value.state == ScanRecordingState.on;

  /// Copies the pixels of [frame] for the recorder, once, on the UI isolate.
  ///
  /// A failed copy leaves the scan out of the recording, counted as dropped;
  /// the caller still submits the frame.
  RecordedFrame? _copyPixels(
    _Scan s,
    CaptureFrame frame, {
    required bool full,
  }) {
    final m = frame.metadata;
    s.recordedSession ??= _recorder?.status.value.folder;
    try {
      final pixels = frame.withPixels(
        (bytes) => TransferableTypedData.fromList([bytes]),
      );
      // The window may have moved or resized between captures, so a
      // full-client frame, the newest and the one the recorded image comes
      // from, always replaces the geometry; a strip only fills a gap.
      // The client origin lies at the desktop point
      // `desktopLeft - captured.left`.
      final cursorX = s.trigger.event.x - (m.desktopLeft - m.captured.left);
      final cursorY = s.trigger.event.y - (m.desktopTop - m.captured.top);
      if (full || s.recordedClientWidth == null) {
        s.recordedClientWidth = m.clientWidth;
        s.recordedClientHeight = m.clientHeight;
        s.recordedCursorX = cursorX;
        s.recordedCursorY = cursorY;
      }
      return RecordedFrame(
        width: m.width,
        height: m.height,
        stride: m.stride,
        pixels: pixels,
        clipped: m.clipped,
        capturedAtUtc: m.capturedAtUtc,
        captured: (
          left: m.captured.left,
          top: m.captured.top,
          width: m.captured.width,
          height: m.captured.height,
        ),
      );
    } on Object catch (error) {
      debugPrint('Scan frame copy failed: $error');
      s.recordingLost = true;
      return null;
    }
  }

  void _copyForRecording(_Scan s, ScanPass pass, CaptureFrame frame) {
    final copy = _copyPixels(s, frame, full: pass == ScanPass.fallback);
    if (copy == null) return;
    switch (pass) {
      case ScanPass.targeted:
        s.recordedStrip = copy;
      case ScanPass.fallback:
        s.recordedFull = copy;
    }
  }

  /// Finishes [s], then hands it to the recorder.
  ///
  /// A targeted acceptance first takes one more full-client capture, after it
  /// is published and logged, so the recorded case has a whole-client image.
  Future<void> _conclude(_Scan s, ScanEnd end) async {
    final report = _finish(s, end);
    final recorder = _recorder;
    if (report == null || recorder == null || !_recordingOn) return;
    if (end is ScanAccepted && report.fallback == null) {
      // A scan the session cannot take is dropped now, at its end, without
      // the extra capture a pending click would wait for.
      if (!recorder.hasRoom) {
        recorder.drop();
        return;
      }
      // The scan belongs to the session it ended in; a session started
      // during the capture never takes it.
      final session = recorder.status.value.folder;
      await _captureExtra(s);
      if (!_extraStillCurrent(s)) return;
      if (recorder.status.value.folder != session) return;
    }
    // Frames copied for an earlier session never go into a later one.
    final copiedFor = s.recordedSession;
    if (copiedFor != null && copiedFor != recorder.status.value.folder) return;
    if (s.recordingLost) {
      recorder.drop();
      return;
    }
    final scan = _recordedScan(s, report, recorder);
    if (scan != null) recorder.record(scan);
  }

  /// Whether [s] was not abandoned by a stop, a pipeline loss or a dispose.
  ///
  /// A newer trigger does not abandon it: the published scan is final and its
  /// extra frame is still recorded.
  bool _extraStillCurrent(_Scan s) =>
      identical(_active, s) && !_stale(s.activation) && !_disposed;

  /// Requests the extra full-client capture of the accepted scan [s] and
  /// copies its pixels. The frame is released here, at once.
  Future<void> _captureExtra(_Scan s) async {
    final a = s.activation;
    if (!_extraStillCurrent(s)) return;
    s.stage = _Stage.capture;
    final CaptureResult result;
    try {
      result = await a.capture!.capture(s.trigger.event, CaptureMode.fallback);
    } on Object catch (error) {
      debugPrint('Scan extra capture failed: $error');
      s.extraFailure = ScanFailureCode.captureFailed.name;
      return;
    }
    switch (result) {
      case CaptureRejected(:final failure):
        s.extraFailure = scanFailureFromCapture(failure).code.name;
      case CaptureSuccess(:final frame):
        try {
          if (_extraStillCurrent(s) && _recordingOn) {
            s.recordedFull = _copyPixels(s, frame, full: true);
          }
        } finally {
          frame.release();
        }
    }
  }

  /// The case for [report], or null when [report] has no end to record.
  RecordedScan? _recordedScan(
    _Scan s,
    ScanReport report,
    ScanFrameRecorder recorder,
  ) {
    final folder = recorder.status.value.folder;
    if (folder == null) return null;
    final session = folder.split(RegExp(r'[\\/]')).last;
    final fullClient =
        s.targetedReport?.failure?.code == ScanFailureCode.roiOutsideClient;
    final (
      outcome,
      acceptedId,
      rejectReason,
      failure,
      text,
    ) = switch (report.end) {
      ScanAccepted(:final itemId, :final outcome) => (
        RecordedOutcome.accepted,
        itemId,
        null,
        null,
        outcome.evidence.text,
      ),
      ScanRejected(:final reason, :final outcome) => (
        RecordedOutcome.rejected,
        null,
        reason.name,
        null,
        outcome?.evidence?.text,
      ),
      ScanFailed(failure: final failed) => (
        RecordedOutcome.failed,
        null,
        null,
        failed.code.name,
        null,
      ),
      ScanSuperseded() => (null, null, null, null, null),
    };
    if (outcome == null) return null;
    return RecordedScan(
      id: '$session-${report.id.toString().padLeft(4, '0')}',
      clientWidth: s.recordedClientWidth,
      clientHeight: s.recordedClientHeight,
      kind: fullClient
          ? RecordedScanKind.fullClient
          : RecordedScanKind.targeted,
      cursorX: fullClient ? null : s.recordedCursorX,
      cursorY: fullClient ? null : s.recordedCursorY,
      outcome: outcome,
      acceptedId: acceptedId,
      rejectReason: rejectReason,
      failure: failure,
      fullFailure:
          s.extraFailure ??
          (s.recordedFull == null
              ? s.fallbackReport?.failure?.code.name
              : null),
      text: text,
      targetedMarkerScore: _bestMarker(s.targetedRecognition),
      fallbackMarkerScore: _bestMarker(s.fallbackRecognition),
      full: s.recordedFull,
      strip: s.recordedStrip,
    );
  }

  static double? _bestMarker(InspectionRecognition? recognition) =>
      switch (recognition) {
        InspectionRecognised(:final bestMarkerScore) => bestMarkerScore,
        InspectionRejected(:final bestMarkerScore) => bestMarkerScore,
        null => null,
      };

  void _endSuperseded(_Scan s) {
    if (s.ended) return;
    s.ended = true;
    final report = _report(s, const ScanSuperseded(), winner: null);
    _log(s.activation, report);
  }

  ScanReport _report(
    _Scan s,
    ScanEnd end, {
    required InspectionEvidence? winner,
    int? published,
  }) {
    final superseded = end is ScanSuperseded;
    final winningPass = _winningPass(
      winner,
      s.targetedRecognition,
      s.fallbackRecognition,
    );
    PassTimeline? stamped(
      ScanPass pass,
      PassTimeline? timeline,
      InspectionRecognition? recognition,
    ) => timeline == null || recognition == null
        ? timeline
        : timeline.withEvidenceStamps(
            recognition,
            winner: winningPass == pass ? winner : null,
          );
    return ScanReport(
      id: s.id,
      utc: DateTime.now().toUtc(),
      end: end,
      winningPass: winningPass,
      targeted: s.targetedReport ?? (superseded ? const PassReport() : null),
      fallback:
          s.fallbackReport ??
          (superseded && s.fallbackTimeline != null
              ? const PassReport()
              : null),
      catalogMode: s.catalogMode,
      catalogRevision: s.catalogRevision,
      epoch: s.epoch,
      timeline: ScanTimeline(
        trigger: s.trigger.event.qpc,
        published: published,
        targeted: stamped(
          ScanPass.targeted,
          s.targetedTimeline,
          s.targetedRecognition,
        ),
        fallback: stamped(
          ScanPass.fallback,
          s.fallbackTimeline,
          s.fallbackRecognition,
        ),
      ),
      droppedTriggers: s.trigger.droppedBefore,
      supersededTriggers: s.replacedTriggers + s.supersedingTriggers,
    );
  }

  /// The pass whose evidence holds [winner], preferring the targeted pass on a
  /// tie, or null when there is no winner.
  static ScanPass? _winningPass(
    InspectionEvidence? winner,
    InspectionRecognition? targeted,
    InspectionRecognition? fallback,
  ) {
    if (winner == null) return null;
    bool holds(InspectionRecognition? recognition) => switch (recognition) {
      InspectionRecognised(:final evidence) => evidence.any(
        (e) =>
            e.markerX == winner.markerX &&
            e.markerY == winner.markerY &&
            e.markerScore == winner.markerScore &&
            e.text == winner.text,
      ),
      InspectionRejected() || null => false,
    };
    if (holds(targeted)) return ScanPass.targeted;
    if (holds(fallback)) return ScanPass.fallback;
    return fallback != null ? ScanPass.fallback : ScanPass.targeted;
  }

  void _log(_Activation a, ScanReport report) {
    try {
      appendLogLine(report.toLogLine(a.qpcFrequency));
    } on Object catch (error) {
      debugPrint('Scan log line failed: $error');
    }
  }

  void _publish(ScanReport report) {
    _phase = ScanPhase.idle;
    _latest = report;
    if (report.end is ScanAccepted) _lastAccepted = report;
    _recent.insert(0, report.withoutCrops());
    while (_recent.length > recentLimit) {
      _recent.removeLast();
    }
    _notify();
  }
}
