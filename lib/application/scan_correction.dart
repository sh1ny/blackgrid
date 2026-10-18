import '../domain/catalog.dart';
import '../domain/title_matching.dart';
import 'scan_coordinator.dart';
import 'scan_epoch.dart';

/// The lowest similarity at which a candidate is offered (.40).
const correctionCandidateFloor = .40;

/// The most search results an offer shows (8).
const correctionSearchLimit = 8;

/// A live-catalog candidate of an offer, as the card shows it.
typedef CorrectionCandidate = ({CatalogItem item, double score});

/// An unaccepted scan the player may correct.
///
/// It is immutable. [SelectionController] holds the current one and replaces
/// it with [withQuery] when the player edits the search text.
final class ScanCorrectionOffer {
  /// Creates an offer.
  const ScanCorrectionOffer({
    required this.reportId,
    required this.epoch,
    required this.mode,
    required this.catalogRevision,
    required this.ocrText,
    required this.candidates,
    required this.query,
  });

  /// Identifies the scan report the offer came from.
  final int reportId;

  /// The epoch the scan began in.
  final ScanEpoch epoch;

  /// The game mode the scan matched in.
  final GameMode mode;

  /// The catalog revision the scan matched against.
  final String catalogRevision;

  /// The text OCR read from the scan's title.
  final String ocrText;

  /// The scan's candidates scoring at least [correctionCandidateFloor], in the
  /// matcher's rank order, at most [maxTitleCandidates].
  ///
  /// An id may no longer be in the live catalog. Resolve it there before
  /// showing it.
  final List<TitleCandidate> candidates;

  /// The text of the offer's search field, initially [ocrText].
  final String query;

  /// Returns this offer with [query] as its search text.
  ScanCorrectionOffer withQuery(String query) => ScanCorrectionOffer(
    reportId: reportId,
    epoch: epoch,
    mode: mode,
    catalogRevision: catalogRevision,
    ocrText: ocrText,
    candidates: candidates,
    query: query,
  );
}

/// An immutable record of one correction the player picked.
///
/// It is not an accepted scan: it never reaches the scanner's accepted state.
class ScanCorrection {
  /// Creates the record of a picked correction.
  const ScanCorrection({
    required this.reportId,
    required this.itemId,
    required this.mode,
    required this.catalogRevision,
    required this.correctedAt,
    required this.epoch,
  });

  /// Identifies the unaccepted scan report the correction was offered for.
  final int reportId;

  /// The catalog item the player picked.
  final String itemId;

  /// The live game mode the item was picked in.
  final GameMode mode;

  /// The live catalog revision at the pick.
  final String catalogRevision;

  /// When the selection controller applied the pick, from its own clock.
  final DateTime correctedAt;

  /// The epoch the offer's scan began in.
  final ScanEpoch epoch;
}

/// Builds the offer for [report], or returns null when it offers none.
///
/// Only a rejection `ambiguous` or `belowSimilarity` offers one, and only when
/// its ranked outcome carries both evidence with non-empty text and a match,
/// so the text and the candidates come from one entry. The report must name
/// its epoch, mode and catalog revision. The caller fences the offer against
/// the current epoch and mode.
ScanCorrectionOffer? correctionOfferFor(ScanReport report) {
  if (report case ScanReport(
    end: ScanRejected(
      reason: ScanRejectReason.ambiguous || ScanRejectReason.belowSimilarity,
      outcome: OutcomeRejected(evidence: final evidence?, match: final match?),
    ),
    :final epoch?,
    catalogMode: final mode?,
    :final catalogRevision?,
  )) {
    final text = evidence.text;
    if (text.isEmpty) return null;
    return ScanCorrectionOffer(
      reportId: report.id,
      epoch: epoch,
      mode: mode,
      catalogRevision: catalogRevision,
      ocrText: text,
      candidates: List.unmodifiable(
        match.candidates
            .where((c) => c.score >= correctionCandidateFloor)
            .take(maxTitleCandidates),
      ),
      query: text,
    );
  }
  return null;
}
