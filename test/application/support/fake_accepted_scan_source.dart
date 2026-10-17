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

  @override
  ScanReport? get lastAccepted => _lastAccepted;

  /// Sets [lastAccepted] without notifying.
  set lastAccepted(ScanReport? report) => _lastAccepted = report;

  /// Publishes [report] as the newest accepted scan and notifies.
  void accept(ScanReport report) {
    _lastAccepted = report;
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
