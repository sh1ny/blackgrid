import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/data/vision/inspection_geometry.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:flutter/foundation.dart';

/// A hand-written [AcceptedScanSource] the test publishes through.
final class FakeAcceptedScanSource extends ChangeNotifier
    implements AcceptedScanSource {
  ScanReport? _lastAccepted;
  ScanReport? _latest;

  @override
  ScanReport? get lastAccepted => _lastAccepted;

  @override
  ScanReport? get latest => _latest;

  /// Sets [latest] without notifying.
  set latest(ScanReport? report) => _latest = report;

  /// Sets [lastAccepted] without notifying.
  set lastAccepted(ScanReport? report) => _lastAccepted = report;

  /// Publishes [report] as the newest accepted scan and notifies.
  void accept(ScanReport report) => publish(report);

  /// Publishes [report] as the coordinator does: it becomes [latest], becomes
  /// [lastAccepted] when accepted, and listeners are notified once.
  void publish(ScanReport report) {
    _latest = report;
    if (report.end is ScanAccepted) _lastAccepted = report;
    notifyListeners();
  }

  /// Notifies without a new accepted scan, as a phase change, a rejected
  /// publish or a failed publish does.
  void notify() => notifyListeners();
}

/// An epoch reader the test moves by hand.
final class FakeScanEpochReader {
  /// Creates a reader that starts at [value].
  FakeScanEpochReader([this.value = const ScanEpoch(0, 0)]);

  /// What the reader returns now.
  ScanEpoch value;

  /// The reader to hand to the feed.
  ScanEpoch call() => value;
}

/// An accepted report for [itemId], stamped with [epoch] and [mode].
///
/// The evidence is minimal and holds no crop bytes.
ScanReport acceptedScanReport({
  required int id,
  required String itemId,
  required ScanEpoch? epoch,
  GameMode? mode = GameMode.pvp,
  String revision = 'r1',
}) {
  final evidence = InspectionEvidence(
    markerScore: 0.9,
    markerX: 1,
    markerY: 2,
    titleRect: const TitleRegion(x: 1, y: 2, width: 3, height: 4),
    titleStatus: InspectionTitleStatus.read,
    text: itemId,
    crop: Uint8List(0),
    cropWidth: 0,
    cropHeight: 0,
    cropDownscaled: false,
    qpcMarker: 1,
    qpcTitle: 2,
    qpcPreprocess: 3,
    qpcOcr: 4,
  );
  return ScanReport(
    id: id,
    utc: DateTime.utc(2026, 1, 1),
    end: ScanAccepted(
      itemId: itemId,
      outcome: OutcomeAccepted<InspectionEvidence>(
        TitleAccepted(
          bestId: itemId,
          normalisedTitle: itemId,
          bestScore: 0.97,
          runnerUpId: null,
          runnerUpScore: 0,
          margin: 0.97,
          confirmedBy: null,
          mode: mode ?? GameMode.pvp,
          revision: revision,
        ),
        evidence,
      ),
    ),
    timeline: const ScanTimeline(trigger: 0),
    droppedTriggers: 0,
    supersededTriggers: 0,
    catalogMode: mode,
    catalogRevision: revision,
    epoch: epoch,
  );
}

/// A rejected report with [text] as its OCR text and [candidates] as its
/// match's ranked candidates.
///
/// [reason] is both the report's and the outcome's reason. The evidence holds
/// no crop bytes. A null [text] or [candidates] leaves the evidence or the
/// match out of the outcome.
ScanReport rejectedScanReport({
  required int id,
  required ScanEpoch? epoch,
  ScanRejectReason reason = ScanRejectReason.ambiguous,
  String? text = 'ANA M1 OD GREEN',
  List<TitleCandidate>? candidates = const [],
  GameMode? mode = GameMode.pvp,
  String revision = 'r1',
}) {
  final evidence = text == null
      ? null
      : InspectionEvidence(
          markerScore: 0.9,
          markerX: 1,
          markerY: 2,
          titleRect: const TitleRegion(x: 1, y: 2, width: 3, height: 4),
          titleStatus: InspectionTitleStatus.read,
          text: text,
          crop: Uint8List(0),
          cropWidth: 0,
          cropHeight: 0,
          cropDownscaled: false,
          qpcMarker: 1,
          qpcTitle: 2,
          qpcPreprocess: 3,
          qpcOcr: 4,
        );
  final match = candidates == null
      ? null
      : TitleRejected(
          reason: TitleRejectReason.ambiguous,
          normalisedTitle: text?.toLowerCase() ?? '',
          bestId: candidates.firstOrNull?.id,
          bestScore: candidates.firstOrNull?.score ?? 0,
          mode: mode ?? GameMode.pvp,
          revision: revision,
          candidates: candidates,
        );
  return ScanReport(
    id: id,
    utc: DateTime.utc(2026, 1, 1),
    end: ScanRejected(
      reason: reason,
      outcome: OutcomeRejected<InspectionEvidence>(
        OutcomeRejectReason.ambiguous,
        evidence: evidence,
        match: match,
      ),
    ),
    timeline: const ScanTimeline(trigger: 0),
    droppedTriggers: 0,
    supersededTriggers: 0,
    catalogMode: mode,
    catalogRevision: revision,
    epoch: epoch,
  );
}

/// A report whose scan failed with `visionTimeout`.
ScanReport failedScanReport({required int id, required ScanEpoch? epoch}) =>
    ScanReport(
      id: id,
      utc: DateTime.utc(2026, 1, 1),
      end: const ScanFailed(
        ScanFailure(ScanFailureCode.visionTimeout, 'timed out'),
      ),
      timeline: const ScanTimeline(trigger: 0),
      droppedTriggers: 0,
      supersededTriggers: 0,
      catalogMode: GameMode.pvp,
      catalogRevision: 'r1',
      epoch: epoch,
    );
