/// Async adapters that run title matching off the UI isolate.
///
/// Each adapter performs its work in one `Isolate.run`, following ADR-0004's
/// bulk-CPU pattern. The adapters depend only on the recognition result
/// types, never on the vision service or the recognition job.
library;

import 'dart:async';
import 'dart:isolate';

import '../data/vision/inspection_evidence.dart';
import '../domain/catalog.dart';
import '../domain/title_matching.dart';

/// Runs [computation] off the calling isolate and returns its result.
///
/// The default is [Isolate.run]; tests inject a runner to force an error.
typedef OffUiRunner = Future<R> Function<R>(FutureOr<R> Function() computation);

Future<R> _isolateRun<R>(FutureOr<R> Function() computation) =>
    Isolate.run<R>(computation);

/// Builds the [TitleMatchIndex] of [snapshot] in one isolate.
///
/// Errors from [runner] propagate to the caller.
Future<TitleMatchIndex> buildTitleMatchIndexOffUi(
  CatalogSnapshot snapshot, {
  OffUiRunner runner = _isolateRun,
}) => runner<TitleMatchIndex>(() => TitleMatchIndex.build(snapshot));

/// Maps one recognition [result] to the matcher's input.
///
/// Each evidence entry's peak order is its index in the result's list. A
/// rejected result contributes no entries but keeps its best marker score,
/// which may be null.
RecognitionResultInput<InspectionEvidence> recognitionInputFor(
  InspectionRecognition result,
) => switch (result) {
  InspectionRecognised(:final bestMarkerScore, :final evidence) =>
    RecognitionResultInput<InspectionEvidence>(
      bestMarkerScore: bestMarkerScore,
      entries: [
        for (final (order, e) in evidence.indexed)
          RankableEvidence<InspectionEvidence>(
            evidence: e,
            markerScore: e.markerScore,
            text: e.text,
            emptyTitleRegion:
                e.titleStatus == InspectionTitleStatus.emptyTitleRegion,
            peakOrder: order,
          ),
      ],
    ),
  InspectionRejected(:final bestMarkerScore) =>
    RecognitionResultInput<InspectionEvidence>(
      bestMarkerScore: bestMarkerScore,
      entries: const [],
    ),
};

/// Matches and ranks the evidence of [targeted] and [fullClient] for a caller
/// in [mode], in one isolate.
///
/// A null [targeted] means no targeted frame was recognised: the full-client
/// evidence is then ranked as a whole rather than through the targeted fast
/// path, which would accept its best-ranked entry alone. An error from
/// [runner] yields [OutcomeRejectReason.matcherFailed] carrying both
/// results' best marker scores.
Future<RecognitionOutcome<InspectionEvidence>> matchRecognitionOffUi(
  TitleMatchIndex index, {
  required InspectionRecognition? targeted,
  InspectionRecognition? fullClient,
  required GameMode mode,
  OffUiRunner runner = _isolateRun,
}) async {
  final targetedInput = targeted == null
      ? RecognitionResultInput<InspectionEvidence>(
          bestMarkerScore: null,
          entries: const [],
        )
      : recognitionInputFor(targeted);
  final fallbackInput = fullClient == null
      ? null
      : recognitionInputFor(fullClient);
  try {
    return await runner<RecognitionOutcome<InspectionEvidence>>(
      () => rankOutcome<InspectionEvidence>(
        index,
        targeted: targetedInput,
        fallback: fallbackInput,
        mode: mode,
      ),
    );
  } on Object {
    return OutcomeRejected<InspectionEvidence>(
      OutcomeRejectReason.matcherFailed,
      targetedBestMarkerScore: targetedInput.bestMarkerScore,
      fallbackBestMarkerScore: fallbackInput?.bestMarkerScore,
    );
  }
}
