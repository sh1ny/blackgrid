import '../domain/catalog.dart';
import '../domain/decision.dart';
import 'scan_epoch.dart';

/// An immutable record of one scan the app accepted.
///
/// It keeps the facts as they were at acceptance. The card shows the live
/// projection instead, so a later refresh never changes this record.
class AcceptedScan {
  /// Creates the record of an accepted scan.
  const AcceptedScan({
    required this.reportId,
    required this.itemId,
    required this.mode,
    required this.catalogRevision,
    required this.acceptedAt,
    required this.epoch,
    required this.decisionAtAcceptance,
  });

  /// Identifies the scan report this record came from.
  final int reportId;

  /// The catalog item the scan matched.
  final String itemId;

  /// The game mode the scan was taken in.
  final GameMode mode;

  /// The catalog revision the scan matched against.
  final String catalogRevision;

  /// When the selection controller accepted the scan, from its own clock.
  final DateTime acceptedAt;

  /// The epoch the scan began in.
  final ScanEpoch epoch;

  /// The decision computed at acceptance, with FIR unknown.
  final ItemDecision decisionAtAcceptance;
}
